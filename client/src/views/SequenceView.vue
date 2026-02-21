<template>
  <div
    class="sequence-editor"
    :class="{ 'mobile-view-mode': isMobile && !editMode }"
    v-if="sequence"
    @dragenter.prevent="onDragEnter"
    @dragover.prevent
    @dragleave="onDragLeave"
    @drop.prevent="onDrop"
  >
    <!-- Mobile view mode: floating overlay -->
    <div v-if="isMobile && !editMode" class="view-overlay" :class="{ 'overlay-hidden': !overlayVisible }">
      <div class="view-overlay-top">
        <button class="view-back-btn" @click="$router.push('/book/' + route.params.bookId)">&#8592;</button>
        <span v-if="sequence.steps.length" class="step-counter">{{ currentStepIndex + 1 }} / {{ sequence.steps.length }}</span>
      </div>
    </div>

    <!-- Header: hidden in mobile view mode -->
    <header v-if="!isMobile || editMode" class="editor-header">
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
          :hide-toolbar="isMobile && !editMode"
          @update="saveAnnotations"
        />
        <div v-else class="empty-canvas">
          <p>Upload an image or drag &amp; drop files to create the first step</p>
        </div>
        <label class="fab-add-photos">
          +
          <input type="file" accept="image/*" hidden @change="handleAddStep" multiple />
        </label>
        <!-- Mobile: Edit FAB (view mode) / Done FAB (edit mode) -->
        <button v-if="isMobile && !editMode" class="mode-fab edit-fab" @click="enterEditMode">&#x270E;</button>
        <button v-if="isMobile && editMode" class="mode-fab done-fab" @click="exitEditMode">&#x2713; Done</button>
      </div>
      <div class="notes-area" :class="{ 'notes-visible': showNotes }">
        <StepNotes
          v-if="currentStep"
          :notes="currentStep.notes"
          @update="saveNotes"
        />
      </div>
    </div>

    <!-- Mobile view mode: caption bar for notes -->
    <div
      v-if="isMobile && !editMode && currentStep?.notes"
      class="caption-bar"
      :class="{ 'caption-expanded': captionExpanded }"
      @click="captionExpanded = !captionExpanded"
    >
      <p>{{ currentStep.notes }}</p>
    </div>

    <Filmstrip
      v-if="sequence.steps.length && (!isMobile || editMode)"
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
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
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
let touchStartTime = 0

// Mobile view/edit mode
const editMode = ref(false)
const overlayVisible = ref(true)
const captionExpanded = ref(false)
const isMobile = ref(false)
const mobileQuery = window.matchMedia('(hover: none) and (pointer: coarse)')
isMobile.value = mobileQuery.matches

function onMobileChange(e) {
  isMobile.value = e.matches
  if (!e.matches) editMode.value = false
}

function enterEditMode() {
  editMode.value = true
}

function exitEditMode() {
  editMode.value = false
  overlayVisible.value = true
  captionExpanded.value = false
}

const currentStep = computed(() => {
  if (!sequence.value?.steps.length) return null
  return sequence.value.steps.find(s => s.id === selectedStepId.value) || sequence.value.steps[0]
})

const currentStepIndex = computed(() => {
  if (!sequence.value?.steps.length || !currentStep.value) return 0
  return sequence.value.steps.findIndex(s => s.id === currentStep.value.id)
})

watch(currentStep, () => {
  captionExpanded.value = false
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
  touchStartTime = Date.now()
}

function onTouchEnd(e) {
  const deltaX = e.changedTouches[0].clientX - touchStartX
  const deltaY = e.changedTouches[0].clientY - touchStartY
  const elapsed = Date.now() - touchStartTime

  // In mobile view mode, detect taps to toggle overlay
  if (isMobile.value && !editMode.value) {
    const isTap = elapsed < 300 && Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10
    if (isTap && !e.target.closest('.mode-fab')) {
      overlayVisible.value = !overlayVisible.value
      return
    }
  }

  if (Math.abs(deltaX) < 50 || Math.abs(deltaX) < Math.abs(deltaY)) return
  if (deltaX < 0) goToStep('next')
  else goToStep('prev')
}

onMounted(() => {
  load()
  window.addEventListener('keydown', handleKeyDown)
  mobileQuery.addEventListener('change', onMobileChange)
})
onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
  mobileQuery.removeEventListener('change', onMobileChange)
})
</script>

<style scoped>
.sequence-editor {
  position: relative;
  display: flex;
  flex-direction: column;
  height: 100vh;
  height: 100dvh;
}

.editor-header {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-md) var(--space-lg);
  background: var(--bg-elevated);
  border-bottom: 1px solid var(--border);
}

.back-btn {
  background: none;
  color: var(--border-focus);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  padding: var(--space-xs) var(--space-md);
}

.back-btn:hover {
  background: rgba(100, 181, 246, 0.1);
  border-color: var(--border-focus);
  box-shadow: none;
  transform: none;
}

.title-input {
  flex: 1;
  background: transparent;
  border: 1px solid transparent;
  color: var(--text-primary);
  font-size: 20px;
  font-weight: 600;
  padding: var(--space-xs) var(--space-sm);
  border-radius: var(--radius-sm);
}

.title-input:focus {
  border-color: var(--border-focus);
  background: var(--bg-surface);
  box-shadow: 0 0 0 3px rgba(100, 181, 246, 0.2);
}

.add-step-btn {
  background: var(--accent);
  color: white;
  padding: var(--space-sm) var(--space-lg);
  border-radius: var(--radius-sm);
  cursor: pointer;
  font-size: 14px;
  transition: background var(--transition-fast);
}

.add-step-btn:hover {
  background: var(--accent-hover);
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
  color: var(--text-muted);
  font-size: 16px;
}

.notes-area {
  width: 300px;
  background: var(--bg-elevated);
  border-left: 1px solid var(--border);
}

.drop-overlay {
  position: fixed;
  inset: 0;
  background: rgba(26, 26, 46, 0.9);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  pointer-events: none;
}

.drop-message {
  color: var(--text-primary);
  font-size: 24px;
  font-weight: 600;
  padding: var(--space-2xl) 48px;
  border: 3px dashed var(--border-focus);
  border-radius: var(--radius-lg);
  background: var(--accent-glow);
}

.notes-toggle {
  display: none;
  background: var(--bg-surface);
  color: var(--text-secondary);
  padding: var(--space-sm) var(--space-md);
  font-size: 14px;
}

.notes-toggle:hover {
  background: #3a3a50;
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
    bottom: var(--space-lg);
    right: var(--space-lg);
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: var(--accent);
    color: white;
    font-size: 28px;
    cursor: pointer;
    box-shadow: var(--shadow-md);
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
    border-top: 1px solid var(--border);
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

/* Landscape on touch devices: compact header */
@media (orientation: landscape) and (hover: none) and (pointer: coarse) {
  .editor-header {
    padding: var(--space-xs) var(--space-md);
    gap: var(--space-sm);
  }

  .title-input {
    font-size: 16px;
  }

  .add-step-btn {
    padding: var(--space-xs) var(--space-md);
    font-size: 13px;
  }
}

/* ── Mobile View Mode ── */

.mobile-view-mode .fab-add-photos {
  display: none !important;
}

/* Floating overlay (back + step counter) */
.view-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 20;
  pointer-events: none;
  transition: opacity 0.25s ease;
}

.view-overlay.overlay-hidden {
  opacity: 0;
  pointer-events: none;
}

.view-overlay-top {
  display: flex;
  align-items: center;
  padding: var(--space-md) var(--space-lg);
  padding-top: calc(var(--space-md) + env(safe-area-inset-top, 0px));
  background: linear-gradient(to bottom, rgba(0, 0, 0, 0.6), transparent);
  pointer-events: auto;
}

.view-back-btn {
  background: rgba(0, 0, 0, 0.4);
  color: white;
  border: none;
  border-radius: var(--radius-full);
  padding: var(--space-sm) var(--space-lg);
  font-size: 18px;
  min-height: 44px;
  min-width: 44px;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}

.view-back-btn:hover {
  background: rgba(0, 0, 0, 0.6);
  transform: none;
  box-shadow: none;
}

.step-counter {
  flex: 1;
  text-align: center;
  color: white;
  font-size: 15px;
  font-weight: 600;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.6);
  margin-right: 44px; /* balance back button width */
}

/* Caption bar for notes */
.caption-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: rgba(0, 0, 0, 0.7);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  padding: var(--space-md) var(--space-lg);
  z-index: 20;
  cursor: pointer;
  transition: opacity 0.25s ease;
}

.caption-bar.overlay-hidden {
  opacity: 0;
  pointer-events: none;
}

.caption-bar p {
  color: var(--text-primary);
  font-size: 14px;
  line-height: 1.5;
  margin: 0;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.caption-bar.caption-expanded p {
  -webkit-line-clamp: unset;
  overflow: visible;
  max-height: 50vh;
  overflow-y: auto;
}

/* Edit / Done FAB */
.mode-fab {
  position: absolute;
  bottom: var(--space-lg);
  right: var(--space-lg);
  width: 56px;
  height: 56px;
  border-radius: 50%;
  font-size: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 15;
  box-shadow: var(--shadow-md);
  border: none;
  min-height: auto;
  min-width: auto;
  padding: 0;
}

.edit-fab {
  background: var(--accent);
  color: white;
}

.edit-fab:hover {
  background: var(--accent-hover);
  transform: none;
}

.done-fab {
  width: auto;
  padding: 0 var(--space-lg);
  border-radius: var(--radius-full);
  background: #388e3c;
  color: white;
  font-size: 15px;
  font-weight: 600;
  gap: var(--space-xs);
}

.done-fab:hover {
  background: #43a047;
  transform: none;
}
</style>
