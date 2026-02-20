<template>
  <div class="book-list">
    <header class="book-header">
      <h1>Stepbook</h1>
      <div class="header-actions">
        <button @click="showAddFolder = true">Add Folder</button>
        <button @click="importInput?.click()">Import Book</button>
        <button @click="showCreate = true">+ New Book</button>
        <input
          type="file"
          accept=".zip"
          ref="importInput"
          style="display: none"
          @change="handleImportBook"
        />
      </div>
    </header>

    <div v-if="showCreate" class="create-form">
      <input
        v-model="newName"
        placeholder="Book name"
        @keyup.enter="handleCreate"
        ref="nameInput"
      />
      <button @click="handleCreate">Create</button>
      <button class="cancel-btn" @click="showCreate = false">Cancel</button>
    </div>

    <div v-if="showAddFolder" class="create-form">
      <input
        v-model="addFolderName"
        placeholder="Book name"
        ref="addNameInput"
      />
      <input
        v-model="addFolderPath"
        placeholder="Folder path"
        @keyup.enter="handleAddFolder"
      />
      <button @click="handleAddFolder">Add</button>
      <button class="cancel-btn" @click="showAddFolder = false">Cancel</button>
    </div>

    <div v-if="bookList.length" class="sequence-grid">
      <div
        v-for="book in bookList"
        :key="book.id"
        class="sequence-card"
        @click="openBook(book)"
      >
        <div class="card-thumbnail">
          <div class="book-icon">&#128214;</div>
        </div>
        <div class="card-info">
          <input
            v-if="editingId === book.id"
            class="title-input"
            v-model="editName"
            @blur="saveBookName(book)"
            @keyup.enter="$event.target.blur()"
            @click.stop
            ref="editInput"
          />
          <h3 v-else>{{ book.name }}</h3>
          <span class="step-count">{{ book.path }}</span>
        </div>
        <button
          class="rename-btn"
          @click.stop="startRename(book)"
          title="Rename book"
        >&#9998;</button>
        <button
          class="export-btn"
          @click.stop="handleExportBook(book)"
          title="Export book"
        >&#8681;</button>
        <button
          v-if="book.id !== 'default'"
          class="delete-btn"
          @click.stop="handleRemove(book)"
          title="Remove from list"
        >&times;</button>
      </div>
    </div>
    <p v-else class="empty">No books yet. Create one to get started.</p>
  </div>
</template>

<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { fetchBooks, createBook, addExistingBook, updateBook, removeBook, exportBook, importBook } from '../api.js'

const router = useRouter()
const bookList = ref([])
const showCreate = ref(false)
const showAddFolder = ref(false)
const newName = ref('')
const addFolderName = ref('')
const addFolderPath = ref('')
const nameInput = ref(null)
const addNameInput = ref(null)
const importInput = ref(null)
const editingId = ref(null)
const editName = ref('')
const editInput = ref(null)

async function startRename(book) {
  editingId.value = book.id
  editName.value = book.name
  await nextTick()
  const inputs = editInput.value
  const el = Array.isArray(inputs) ? inputs[0] : inputs
  if (el) { el.focus(); el.select() }
}

async function saveBookName(book) {
  const trimmed = editName.value.trim()
  if (trimmed && trimmed !== book.name) {
    await updateBook(book.id, trimmed)
    await load()
  }
  editingId.value = null
}

async function load() {
  bookList.value = await fetchBooks()
}

async function handleCreate() {
  if (!newName.value.trim()) return
  await createBook(newName.value.trim())
  newName.value = ''
  showCreate.value = false
  await load()
}

async function handleAddFolder() {
  if (!addFolderName.value.trim() || !addFolderPath.value.trim()) return
  await addExistingBook(addFolderName.value.trim(), addFolderPath.value.trim())
  addFolderName.value = ''
  addFolderPath.value = ''
  showAddFolder.value = false
  await load()
}

function openBook(book) {
  router.push(`/book/${book.id}`)
}

async function handleRemove(book) {
  if (!confirm(`Remove "${book.name}" from the book list? (Files will not be deleted)`)) return
  await removeBook(book.id)
  await load()
}

async function handleExportBook(book) {
  try {
    await exportBook(book.id)
  } catch (err) {
    alert('Export failed: ' + err.message)
  }
}

async function handleImportBook(e) {
  const file = e.target.files[0]
  if (!file) return
  try {
    await importBook(file)
    await load()
  } catch (err) {
    alert('Import failed: ' + err.message)
  }
  e.target.value = ''
}

onMounted(load)
</script>

<style scoped>
.book-list {
  max-width: 1200px;
  margin: 0 auto;
  padding: var(--space-2xl);
}

.book-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-xl);
}

.header-actions {
  display: flex;
  gap: var(--space-sm);
}

.create-form {
  display: flex;
  gap: var(--space-sm);
  margin-bottom: var(--space-xl);
}

.create-form input {
  flex: 1;
  max-width: 300px;
}

.cancel-btn {
  background: var(--bg-surface);
}

.cancel-btn:hover {
  background: #3a3a50;
}

.book-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  font-size: 48px;
  background: linear-gradient(135deg, var(--bg-elevated) 0%, var(--bg-surface) 100%);
}

.empty {
  color: var(--text-muted);
  text-align: center;
  margin-top: 60px;
  font-size: 16px;
}

.sequence-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 20px;
}

.sequence-card {
  background: var(--bg-surface);
  border-radius: var(--radius-lg);
  border: 1px solid var(--border);
  overflow: hidden;
  cursor: pointer;
  transition: transform var(--transition-fast), box-shadow var(--transition-fast);
  position: relative;
}

.sequence-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(100, 181, 246, 0.1);
}

.card-thumbnail {
  width: 100%;
  height: 120px;
  overflow: hidden;
  background: var(--bg-elevated);
}

.card-info {
  padding: var(--space-md) var(--space-lg);
}

.card-info h3 {
  font-size: 16px;
  margin-bottom: var(--space-xs);
}

.step-count {
  font-size: 12px;
  color: var(--text-muted);
  word-break: break-all;
}

.title-input {
  font-size: 16px;
  font-weight: bold;
  background: var(--bg-elevated);
  color: #fff;
  border: 1px solid var(--border-focus);
  border-radius: var(--radius-sm);
  padding: 2px 6px;
  width: 100%;
  box-sizing: border-box;
}

.rename-btn,
.export-btn,
.delete-btn {
  position: absolute;
  top: var(--space-sm);
  background: rgba(0, 0, 0, 0.6);
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  opacity: 0;
  transition: opacity var(--transition-fast), background var(--transition-fast);
}

.rename-btn {
  right: 72px;
  color: var(--warning);
  font-size: 16px;
}

.export-btn {
  right: 40px;
  color: var(--border-focus);
  font-size: 18px;
}

.delete-btn {
  right: var(--space-sm);
  color: var(--danger);
  font-size: 18px;
}

.rename-btn:hover,
.export-btn:hover,
.delete-btn:hover {
  background: rgba(0, 0, 0, 0.8);
}

.sequence-card:hover .rename-btn,
.sequence-card:hover .export-btn,
.sequence-card:hover .delete-btn {
  opacity: 1;
}

@media (hover: none) and (pointer: coarse) {
  .rename-btn,
  .export-btn,
  .delete-btn {
    opacity: 1;
  }
}

@media (max-width: 600px) {
  .book-list {
    padding: var(--space-lg);
  }

  .book-header {
    flex-direction: column;
    align-items: stretch;
    gap: var(--space-md);
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
