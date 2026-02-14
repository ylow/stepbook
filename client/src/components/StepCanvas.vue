<template>
  <div class="step-canvas" ref="container">
    <div class="toolbar">
      <button
        v-for="t in tools"
        :key="t.id"
        :class="{ active: tool === t.id }"
        @click="tool = t.id"
        :title="t.label"
      >
        {{ t.icon }}
      </button>
      <span class="separator"></span>
      <input type="color" v-model="strokeColor" title="Color" />
      <select v-model.number="strokeWidth" title="Stroke width">
        <option :value="2">Thin</option>
        <option :value="4">Medium</option>
        <option :value="8">Thick</option>
      </select>
      <span class="separator"></span>
      <button @click="undo" title="Undo (Ctrl+Z)">↩</button>
      <button @click="redo" title="Redo (Ctrl+Shift+Z)">↪</button>
      <button @click="clearAnnotations" title="Clear all">Clear</button>
    </div>

    <v-stage
      ref="stageRef"
      :config="stageConfig"
      @mousedown="handleMouseDown"
      @mousemove="handleMouseMove"
      @mouseup="handleMouseUp"
    >
      <!-- Background image layer -->
      <v-layer>
        <v-image :config="imageConfig" />
      </v-layer>

      <!-- Annotations layer -->
      <v-layer ref="annotationLayer">
        <template v-for="(line, i) in lines" :key="i">
          <v-line :config="line" />
        </template>
        <template v-for="(label, i) in labels" :key="'t' + i">
          <v-text :config="{ ...label, draggable: true }" @dragend="(e) => onLabelDragEnd(i, e)" />
        </template>
      </v-layer>
    </v-stage>

    <!-- Text input overlay -->
    <div
      v-if="showTextInput"
      class="text-input-overlay"
      :style="{ left: textInputPos.x + 'px', top: textInputPos.y + 'px' }"
    >
      <input
        ref="textInput"
        v-model="textInputValue"
        @keyup.enter="commitText"
        @keyup.escape="cancelText"
        placeholder="Type text..."
        autofocus
      />
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'

const props = defineProps({
  imageSrc: { type: String, required: true },
  annotations: { type: String, default: '{}' }
})
const emit = defineEmits(['update'])

// Canvas sizing
const container = ref(null)
const stageRef = ref(null)
const canvasWidth = ref(800)
const canvasHeight = ref(600)

const stageConfig = computed(() => ({
  width: canvasWidth.value,
  height: canvasHeight.value
}))

// Background image
const bgImage = ref(null)
const imageConfig = computed(() => ({
  image: bgImage.value,
  width: canvasWidth.value,
  height: canvasHeight.value
}))

function loadImage() {
  const img = new Image()
  img.crossOrigin = 'anonymous'
  img.onload = () => {
    bgImage.value = img
    // Fit canvas to container while maintaining aspect ratio
    if (container.value) {
      const containerRect = container.value.getBoundingClientRect()
      const maxW = containerRect.width
      const maxH = containerRect.height - 44 // toolbar height
      const scale = Math.min(maxW / img.width, maxH / img.height, 1)
      canvasWidth.value = Math.floor(img.width * scale)
      canvasHeight.value = Math.floor(img.height * scale)
    }
  }
  img.src = props.imageSrc
}

watch(() => props.imageSrc, loadImage)
onMounted(loadImage)

// Tools
const tools = [
  { id: 'select', icon: '\u25E6', label: 'Select / Move' },
  { id: 'pen', icon: '\u270F', label: 'Freehand pen' },
  { id: 'line', icon: '\u2571', label: 'Straight line' },
  { id: 'arrow', icon: '\u2192', label: 'Arrow' },
  { id: 'text', icon: 'T', label: 'Text' },
  { id: 'eraser', icon: '\u232B', label: 'Eraser' }
]
const tool = ref('select')
const strokeColor = ref('#ff0000')
const strokeWidth = ref(4)

// Annotation state
const lines = ref([])
const labels = ref([])
const isDrawing = ref(false)
const history = ref([])
const historyIndex = ref(-1)

// Load saved annotations
function loadAnnotations() {
  try {
    const data = JSON.parse(props.annotations || '{}')
    lines.value = data.lines || []
    labels.value = data.labels || []
    saveHistory()
  } catch {
    lines.value = []
    labels.value = []
  }
}

watch(() => props.annotations, loadAnnotations, { immediate: true })

function getState() {
  return JSON.stringify({ lines: lines.value, labels: labels.value })
}

function saveHistory() {
  const state = getState()
  // Remove any redo states
  history.value = history.value.slice(0, historyIndex.value + 1)
  history.value.push(state)
  historyIndex.value = history.value.length - 1
}

function undo() {
  if (historyIndex.value > 0) {
    historyIndex.value--
    const data = JSON.parse(history.value[historyIndex.value])
    lines.value = data.lines
    labels.value = data.labels
    emitUpdate()
  }
}

function redo() {
  if (historyIndex.value < history.value.length - 1) {
    historyIndex.value++
    const data = JSON.parse(history.value[historyIndex.value])
    lines.value = data.lines
    labels.value = data.labels
    emitUpdate()
  }
}

function clearAnnotations() {
  lines.value = []
  labels.value = []
  saveHistory()
  emitUpdate()
}

function emitUpdate() {
  emit('update', JSON.stringify({ lines: lines.value, labels: labels.value }))
}

// Drawing handlers
let lineStartPos = null

function getPointerPos() {
  const stage = stageRef.value?.getStage()
  if (!stage) return { x: 0, y: 0 }
  return stage.getPointerPosition()
}

function handleMouseDown() {
  const pos = getPointerPos()

  // Commit any pending text input before doing anything else
  if (showTextInput.value) {
    commitText()
  }

  if (tool.value === 'select') {
    return
  }

  if (tool.value === 'text') {
    showTextInputAt(pos)
    return
  }

  if (tool.value === 'eraser') {
    eraseAt(pos)
    return
  }

  isDrawing.value = true

  if (tool.value === 'pen') {
    lines.value.push({
      points: [pos.x, pos.y],
      stroke: strokeColor.value,
      strokeWidth: strokeWidth.value,
      lineCap: 'round',
      lineJoin: 'round'
    })
  } else if (tool.value === 'line' || tool.value === 'arrow') {
    lineStartPos = pos
    lines.value.push({
      points: [pos.x, pos.y, pos.x, pos.y],
      stroke: strokeColor.value,
      strokeWidth: strokeWidth.value,
      lineCap: 'round'
    })
  }
}

function handleMouseMove() {
  if (!isDrawing.value) return
  const pos = getPointerPos()

  if (tool.value === 'pen') {
    const last = lines.value[lines.value.length - 1]
    last.points = [...last.points, pos.x, pos.y]
    // Force reactivity
    lines.value = [...lines.value]
  } else if (tool.value === 'line' || tool.value === 'arrow') {
    const last = lines.value[lines.value.length - 1]
    last.points = [lineStartPos.x, lineStartPos.y, pos.x, pos.y]
    lines.value = [...lines.value]
  }
}

function handleMouseUp() {
  if (!isDrawing.value) return
  isDrawing.value = false

  // If arrow tool, add an arrowhead by setting Konva arrow properties
  if (tool.value === 'arrow') {
    const last = lines.value[lines.value.length - 1]
    last.pointerLength = 10
    last.pointerWidth = 10
    lines.value = [...lines.value]
  }

  saveHistory()
  emitUpdate()
}

// Eraser
function eraseAt(pos) {
  const threshold = 15
  // Remove lines near the click
  lines.value = lines.value.filter(line => {
    for (let i = 0; i < line.points.length; i += 2) {
      const dx = line.points[i] - pos.x
      const dy = line.points[i + 1] - pos.y
      if (Math.sqrt(dx * dx + dy * dy) < threshold) return false
    }
    return true
  })
  // Remove text labels near the click
  labels.value = labels.value.filter(label => {
    const dx = label.x - pos.x
    const dy = label.y - pos.y
    return Math.sqrt(dx * dx + dy * dy) > threshold
  })
  saveHistory()
  emitUpdate()
}

// Text input
const showTextInput = ref(false)
const textInputPos = reactive({ x: 0, y: 0 })
const textInputValue = ref('')
const textInput = ref(null)

function showTextInputAt(pos) {
  textInputPos.x = pos.x
  textInputPos.y = pos.y + 44 // offset for toolbar
  textInputValue.value = ''
  showTextInput.value = true
  nextTick(() => textInput.value?.focus())
}

function commitText() {
  if (textInputValue.value.trim()) {
    labels.value.push({
      x: textInputPos.x,
      y: textInputPos.y - 44,
      text: textInputValue.value.trim(),
      fontSize: strokeWidth.value * 4 + 8,
      fill: strokeColor.value
    })
    labels.value = [...labels.value]
    saveHistory()
    emitUpdate()
  }
  showTextInput.value = false
}

function cancelText() {
  showTextInput.value = false
}

// Label dragging
function onLabelDragEnd(index, e) {
  const node = e.target
  labels.value[index] = { ...labels.value[index], x: node.x(), y: node.y() }
  labels.value = [...labels.value]
  saveHistory()
  emitUpdate()
}

// Keyboard shortcuts
function handleKeyDown(e) {
  if (e.ctrlKey || e.metaKey) {
    if (e.key === 'z' && !e.shiftKey) {
      e.preventDefault()
      undo()
    } else if ((e.key === 'z' && e.shiftKey) || e.key === 'y') {
      e.preventDefault()
      redo()
    }
  }
}

onMounted(() => window.addEventListener('keydown', handleKeyDown))
onUnmounted(() => window.removeEventListener('keydown', handleKeyDown))
</script>

<style scoped>
.step-canvas {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  height: 100%;
}

.toolbar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 12px;
  background: #2a2a3e;
  border-radius: 6px;
  margin: 6px;
  z-index: 10;
}

.toolbar button {
  background: #3a3a50;
  border: none;
  color: #ccc;
  padding: 6px 10px;
  border-radius: 4px;
  font-size: 14px;
}

.toolbar button.active {
  background: #3f51b5;
  color: white;
}

.toolbar button:hover {
  background: #4a4a60;
}

.separator {
  width: 1px;
  height: 24px;
  background: #555;
  margin: 0 4px;
}

.toolbar input[type="color"] {
  width: 32px;
  height: 28px;
  padding: 0;
  border: none;
  cursor: pointer;
}

.toolbar select {
  background: #3a3a50;
  color: #ccc;
  border: 1px solid #555;
  padding: 4px;
  border-radius: 4px;
  font-size: 12px;
}

.text-input-overlay {
  position: absolute;
  z-index: 20;
}

.text-input-overlay input {
  padding: 4px 8px;
  font-size: 16px;
  background: rgba(0, 0, 0, 0.8);
  color: white;
  border: 1px solid #64b5f6;
  border-radius: 4px;
}
</style>
