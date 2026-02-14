<template>
  <div class="home">
    <header class="home-header">
      <h1>Stepbook</h1>
      <button @click="showCreate = true">+ New Sequence</button>
    </header>

    <div v-if="showCreate" class="create-form">
      <input
        v-model="newTitle"
        placeholder="Sequence title"
        @keyup.enter="create"
        ref="titleInput"
      />
      <button @click="create">Create</button>
      <button class="cancel-btn" @click="showCreate = false">Cancel</button>
    </div>

    <SequenceList
      v-if="sequences.length"
      :sequences="sequences"
      @delete="handleDelete"
    />
    <p v-else class="empty">No sequences yet. Create one to get started.</p>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { fetchSequences, createSequence, deleteSequence } from '../api.js'
import SequenceList from '../components/SequenceList.vue'

const sequences = ref([])
const showCreate = ref(false)
const newTitle = ref('')
const titleInput = ref(null)

async function load() {
  sequences.value = await fetchSequences()
}

async function create() {
  if (!newTitle.value.trim()) return
  await createSequence(newTitle.value.trim())
  newTitle.value = ''
  showCreate.value = false
  await load()
}

async function handleDelete(id) {
  if (!confirm('Delete this sequence and all its steps?')) return
  await deleteSequence(id)
  await load()
}

onMounted(load)
</script>

<style scoped>
.home {
  max-width: 1200px;
  margin: 0 auto;
  padding: 32px;
}

.home-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.create-form {
  display: flex;
  gap: 8px;
  margin-bottom: 24px;
}

.create-form input {
  flex: 1;
  max-width: 400px;
}

.cancel-btn {
  background: #555;
}

.empty {
  color: #888;
  text-align: center;
  margin-top: 60px;
  font-size: 16px;
}
</style>
