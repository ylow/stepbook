<template>
  <div class="step-notes">
    <h3>Notes</h3>
    <textarea
      v-model="text"
      placeholder="Add notes for this step..."
      @blur="save"
    ></textarea>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  notes: { type: String, default: '' }
})
const emit = defineEmits(['update'])

const text = ref(props.notes)

watch(() => props.notes, (val) => {
  text.value = val
})

function save() {
  if (text.value !== props.notes) {
    emit('update', text.value)
  }
}
</script>

<style scoped>
.step-notes {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: var(--space-lg);
}

.step-notes h3 {
  margin-bottom: var(--space-md);
  font-size: 14px;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

textarea {
  flex: 1;
  resize: none;
  background: var(--bg-surface);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: var(--radius-sm);
  padding: var(--space-md);
  color: var(--text-primary);
  font-size: 14px;
  line-height: 1.6;
  font-family: inherit;
}

textarea:focus {
  border-color: var(--border-focus);
  box-shadow: 0 0 0 3px rgba(100, 181, 246, 0.2);
}
</style>
