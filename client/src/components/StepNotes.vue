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
  padding: 16px;
}

.step-notes h3 {
  margin-bottom: 12px;
  font-size: 14px;
  color: #aaa;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

textarea {
  flex: 1;
  resize: none;
  background: #2a2a3e;
  border: 1px solid #444;
  border-radius: 4px;
  padding: 12px;
  color: #e0e0e0;
  font-size: 14px;
  line-height: 1.6;
  font-family: inherit;
}
</style>
