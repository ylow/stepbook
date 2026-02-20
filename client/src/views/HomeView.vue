<template>
  <div class="home">
    <header class="home-header">
      <div class="header-left">
        <button class="back-btn" @click="$router.push('/')">← Books</button>
        <h1>Stepbook</h1>
      </div>
      <div class="header-actions">
        <button @click="triggerImport">Import Zip</button>
        <button @click="showCreate = true">+ New Sequence</button>
        <input
          ref="importInput"
          type="file"
          accept=".zip"
          style="display: none"
          @change="handleImport"
        />
      </div>
    </header>

    <p v-if="dataDir" class="data-info">
      Data saved to <strong>{{ dataDir }}</strong> — back up this folder to preserve your work.
    </p>

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
      :bookId="route.params.bookId"
      @delete="handleDelete"
      @export="handleExport"
    />
    <p v-else-if="loaded" class="empty">No sequences yet. Create one to get started.</p>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { fetchSequences, createSequence, deleteSequence, exportSequence, importSequence, fetchConfig, selectBook } from '../api.js'
import SequenceList from '../components/SequenceList.vue'

const route = useRoute()
const sequences = ref([])
const dataDir = ref('')
const showCreate = ref(false)
const newTitle = ref('')
const titleInput = ref(null)
const importInput = ref(null)
const loaded = ref(false)

async function load() {
  // Select the book first
  await selectBook(route.params.bookId)
  sequences.value = await fetchSequences()
  loaded.value = true
  if (!dataDir.value) {
    try {
      const config = await fetchConfig()
      dataDir.value = config.dataDir
    } catch {}
  }
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

async function handleExport(id) {
  try {
    await exportSequence(id)
  } catch (e) {
    alert('Export failed: ' + e.message)
  }
}

function triggerImport() {
  importInput.value.click()
}

async function handleImport(e) {
  const file = e.target.files[0]
  if (!file) return
  try {
    await importSequence(file)
    await load()
  } catch (err) {
    alert('Import failed: ' + err.message)
  }
  importInput.value.value = ''
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

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.back-btn {
  background: none;
  color: #64b5f6;
  padding: 4px 8px;
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

.header-actions {
  display: flex;
  gap: 8px;
}

.data-info {
  color: #888;
  font-size: 13px;
  margin-bottom: 16px;
}

.empty {
  color: #888;
  text-align: center;
  margin-top: 60px;
  font-size: 16px;
}

@media (max-width: 600px) {
  .home {
    padding: 16px;
  }

  .home-header {
    flex-direction: column;
    align-items: stretch;
    gap: 12px;
  }

  .header-actions {
    flex-direction: column;
  }

  .header-actions button {
    width: 100%;
  }

  .create-form {
    flex-direction: column;
  }

  .create-form input {
    max-width: none;
  }
}
</style>
