<template>
  <div
    class="sequence-editor"
    v-if="sequence"
    @dragenter.prevent="onDragEnter"
    @dragover.prevent
    @dragleave="onDragLeave"
    @drop.prevent="onDrop"
  >
    <header class="editor-header">
      <button class="back-btn" @click="$router.push('/book/' + route.params.bookId)">← Back</button>
      <input
        class="title-input"
        v-model="sequence.title"
        @blur="saveTitle"
        @keyup.enter="$event.target.blur()"
      />
      <label class="add-step-btn">
        + Step
        <input type="file" accept="image/*" hidden @change="handleAddStep" multiple />
      </label>
      <button class="notes-toggle" @click="showNotes = !showNotes">
        {{ showNotes ? '✕ Notes' : '📝 Notes' }}
      </button>
    </header>

    <div class="editor-body">
      <div class="canvas-area" @touchstart.passive="onTouchStart" @touchend.passive="onTouchEnd">
        <StepCanvas
          v-if="currentStep"
          :image-src="`/images/${currentStep.image_path}`"
          :annotations="currentStep.annotations"
          @update="saveAnnotations"
        />
        <div v-else class="empty-canvas">
          <p>Upload an image or drag &amp; drop files to create the first step</p>
        </div>
        <label class="fab-add-photos">
          +
          <input type="file" accept="image/*" hidden @change="handleAddStep" multiple />
        </label>
      </div>
      <div class="notes-area" :class="{ 'notes-visible': showNotes }">
        <StepNotes
          v-if="currentStep"
          :notes="currentStep.notes"
          @update="saveNotes"
        />
      </div>
    </div>

    <Filmstrip
      v-if="sequence.steps.length"
      :steps="sequence.steps"
      :selected-id="currentStep?.id"
      @select="selectStep"
      @reorder="handleReorder"
      @delete="handleDeleteStep"
    />

    <!-- Drag-and-drop overlay -->
    <div v-if="dragOver || uploading" class="drop-overlay">
      <div class="drop-message">
        <template v-if="uploading">
          Uploading {{ uploadProgress }} of {{ uploadTotal }}...
        </template>
        <template v-else>
          Drop images to add steps
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import exifr from 'exifr'
import { fetchSequence, updateSequence, addStep, updateStep, reorderSteps, deleteStep } from '../api.js'
import Filmstrip from '../components/Filmstrip.vue'
import StepNotes from '../components/StepNotes.vue'
import StepCanvas from '../components/StepCanvas.vue'

const route = useRoute()
const sequence = ref(null)
const selectedStepId = ref(null)
const showNotes = ref(false)
const dragOver = ref(false)
const uploading = ref(false)
const uploadProgress = ref(0)
const uploadTotal = ref(0)
let dragCounter = 0
let touchStartX = 0
let touchStartY = 0

const currentStep = computed(() => {
  if (!sequence.value?.steps.length) return null
  return sequence.value.steps.find(s => s.id === selectedStepId.value) || sequence.value.steps[0]
})

async function load() {
  sequence.value = await fetchSequence(route.params.id)
  if (sequence.value.steps.length && !selectedStepId.value) {
    selectedStepId.value = sequence.value.steps[0].id
  }
}

function selectStep(id) {
  selectedStepId.value = id
}

async function saveTitle() {
  await updateSequence(sequence.value.id, { title: sequence.value.title })
}

async function saveNotes(notes) {
  await updateStep(currentStep.value.id, { notes })
  currentStep.value.notes = notes
}

async function saveAnnotations(annotations) {
  await updateStep(currentStep.value.id, { annotations })
  currentStep.value.annotations = annotations
}

const ALLOWED_EXTENSIONS = /\.(jpg|jpeg|png|gif|webp)$/i

async function filterAndSortImages(files) {
  const validFiles = Array.from(files).filter(f => ALLOWED_EXTENSIONS.test(f.name))

  const filesWithDates = await Promise.all(
    validFiles.map(async (file) => {
      let date = null
      try {
        const exif = await exifr.parse(file, ['DateTimeOriginal'])
        if (exif?.DateTimeOriginal) date = exif.DateTimeOriginal
      } catch {}
      return { file, date }
    })
  )

  filesWithDates.sort((a, b) => {
    if (a.date && b.date) return a.date - b.date
    if (a.date && !b.date) return -1
    if (!a.date && b.date) return 1
    return a.file.name.localeCompare(b.file.name, undefined, { numeric: true })
  })

  return filesWithDates.map(f => f.file)
}

async function uploadFiles(files) {
  if (!files.length) return
  uploading.value = true
  uploadTotal.value = files.length
  uploadProgress.value = 0
  for (const file of files) {
    uploadProgress.value++
    await addStep(sequence.value.id, file)
  }
  uploading.value = false
  await load()
  if (sequence.value.steps.length) {
    selectedStepId.value = sequence.value.steps[sequence.value.steps.length - 1].id
  }
}

async function handleAddStep(e) {
  const files = await filterAndSortImages(e.target.files)
  await uploadFiles(files)
  e.target.value = ''
}

function onDragEnter(e) {
  dragCounter++
  dragOver.value = true
}

function onDragLeave(e) {
  dragCounter--
  if (dragCounter <= 0) {
    dragCounter = 0
    dragOver.value = false
  }
}

async function onDrop(e) {
  dragCounter = 0
  dragOver.value = false
  const files = await filterAndSortImages(e.dataTransfer.files)
  await uploadFiles(files)
}

async function handleReorder(stepIds) {
  await reorderSteps(sequence.value.id, stepIds)
  await load()
}

async function handleDeleteStep(stepId) {
  if (!confirm('Delete this step?')) return
  await deleteStep(stepId)
  await load()
}

function goToStep(direction) {
  if (!sequence.value?.steps.length) return
  const steps = sequence.value.steps
  const idx = steps.findIndex(s => s.id === selectedStepId.value)
  if (direction === 'prev' && idx > 0) {
    selectedStepId.value = steps[idx - 1].id
  } else if (direction === 'next' && idx < steps.length - 1) {
    selectedStepId.value = steps[idx + 1].id
  }
}

function handleKeyDown(e) {
  if (!sequence.value?.steps.length) return
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return
  if (e.key === 'ArrowLeft') goToStep('prev')
  else if (e.key === 'ArrowRight') goToStep('next')
}

function onTouchStart(e) {
  touchStartX = e.touches[0].clientX
  touchStartY = e.touches[0].clientY
}

function onTouchEnd(e) {
  const deltaX = e.changedTouches[0].clientX - touchStartX
  const deltaY = e.changedTouches[0].clientY - touchStartY
  if (Math.abs(deltaX) < 50 || Math.abs(deltaX) < Math.abs(deltaY)) return
  if (deltaX < 0) goToStep('next')
  else goToStep('prev')
}

onMounted(() => {
  load()
  window.addEventListener('keydown', handleKeyDown)
})
onUnmounted(() => window.removeEventListener('keydown', handleKeyDown))
</script>

<style scoped>
.sequence-editor {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

.editor-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: #1e1e30;
  border-bottom: 1px solid #333;
}

.back-btn {
  background: none;
  color: #64b5f6;
  padding: 4px 8px;
}

.title-input {
  flex: 1;
  background: transparent;
  border: 1px solid transparent;
  color: #e0e0e0;
  font-size: 20px;
  font-weight: 600;
  padding: 4px 8px;
  border-radius: 4px;
}

.title-input:focus {
  border-color: #64b5f6;
  background: #2a2a3e;
}

.add-step-btn {
  background: #3f51b5;
  color: white;
  padding: 8px 16px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
}

.add-step-btn:hover {
  background: #5c6bc0;
}

.editor-body {
  display: flex;
  flex: 1;
  min-height: 0;
}

.canvas-area {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #111;
  overflow: hidden;
}

.empty-canvas {
  color: #666;
  font-size: 16px;
}

.notes-area {
  width: 300px;
  background: #1e1e30;
  border-left: 1px solid #333;
}

.drop-overlay {
  position: fixed;
  inset: 0;
  background: rgba(26, 26, 46, 0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  pointer-events: none;
}

.drop-message {
  color: #e0e0e0;
  font-size: 24px;
  font-weight: 600;
  padding: 32px 48px;
  border: 3px dashed #64b5f6;
  border-radius: 16px;
  background: rgba(63, 81, 181, 0.15);
}

.notes-toggle {
  display: none;
  background: #3a3a50;
  color: #ccc;
  padding: 6px 12px;
  font-size: 14px;
}

.fab-add-photos {
  display: none;
}

@media (hover: none) and (pointer: coarse) {
  .fab-add-photos {
    display: flex;
    align-items: center;
    justify-content: center;
    position: absolute;
    bottom: 16px;
    right: 16px;
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: #3f51b5;
    color: white;
    font-size: 28px;
    cursor: pointer;
    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
    z-index: 10;
  }

  .canvas-area {
    position: relative;
  }
}

@media (max-width: 768px) {
  .editor-body {
    flex-direction: column;
  }

  .notes-area {
    width: 100%;
    display: none;
    max-height: 40vh;
    overflow-y: auto;
    border-left: none;
    border-top: 1px solid #333;
  }

  .notes-area.notes-visible {
    display: block;
  }

  .notes-toggle {
    display: block;
  }
}

@media (max-width: 480px) {
  .editor-header {
    flex-wrap: wrap;
  }

  .title-input {
    order: 3;
    flex-basis: 100%;
    font-size: 16px;
  }
}
</style>
