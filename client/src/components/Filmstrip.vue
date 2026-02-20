<template>
  <div class="filmstrip">
    <button class="nav-btn" @click="scrollLeft">&lt;</button>
    <div class="filmstrip-track" ref="track">
      <div
        v-for="step in steps"
        :key="step.id"
        :data-id="step.id"
        class="filmstrip-thumb"
        :class="{ active: step.id === selectedId }"
        @click="$emit('select', step.id)"
      >
        <img :src="`/images/${step.image_path}`" alt="" />
        <button class="thumb-delete" @click.stop="$emit('delete', step.id)" title="Delete step">&times;</button>
        <span class="thumb-index">{{ step.order_index + 1 }}</span>
      </div>
    </div>
    <button class="nav-btn" @click="scrollRight">&gt;</button>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import Sortable from 'sortablejs'

const props = defineProps({
  steps: { type: Array, required: true },
  selectedId: { type: String, default: null }
})
const emit = defineEmits(['select', 'reorder', 'delete'])

const track = ref(null)
let sortable = null

function scrollLeft() {
  track.value?.scrollBy({ left: -200, behavior: 'smooth' })
}
function scrollRight() {
  track.value?.scrollBy({ left: 200, behavior: 'smooth' })
}

function initSortable() {
  if (sortable) sortable.destroy()
  if (!track.value) return
  sortable = new Sortable(track.value, {
    animation: 150,
    ghostClass: 'sortable-ghost',
    delay: 200,
    delayOnTouchOnly: true,
    touchStartThreshold: 5,
    onEnd(evt) {
      const newOrder = Array.from(track.value.children).map(el => el.dataset.id)
      emit('reorder', newOrder)
    }
  })
}

onMounted(initSortable)
watch(() => props.steps.length, () => {
  setTimeout(initSortable, 50)
})
onUnmounted(() => sortable?.destroy())
</script>

<style scoped>
.filmstrip {
  display: flex;
  align-items: center;
  background: #1e1e30;
  padding: 8px;
  gap: 8px;
  border-top: 1px solid #333;
}

.filmstrip-track {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  flex: 1;
  scrollbar-width: thin;
}

.filmstrip-thumb {
  flex-shrink: 0;
  width: 80px;
  height: 60px;
  border-radius: 4px;
  overflow: hidden;
  cursor: pointer;
  border: 2px solid transparent;
  position: relative;
}

.filmstrip-thumb.active {
  border-color: #64b5f6;
}

.filmstrip-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.thumb-index {
  position: absolute;
  bottom: 2px;
  right: 4px;
  font-size: 10px;
  color: white;
  text-shadow: 0 0 4px black;
}

.nav-btn {
  background: #333;
  border: none;
  color: #aaa;
  padding: 8px;
  border-radius: 4px;
  font-size: 16px;
}

.nav-btn:hover {
  background: #444;
  color: white;
}

.thumb-delete {
  position: absolute;
  top: 2px;
  right: 2px;
  background: rgba(0,0,0,0.7);
  color: #ff5252;
  border: none;
  border-radius: 50%;
  width: 18px;
  height: 18px;
  font-size: 12px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.filmstrip-thumb:hover .thumb-delete {
  display: flex;
}

.sortable-ghost {
  opacity: 0.4;
}

@media (hover: none) and (pointer: coarse) {
  .thumb-delete {
    display: flex;
  }

  .nav-btn {
    display: none;
  }
}
</style>
