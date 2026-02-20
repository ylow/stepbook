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
  padding: 32px;
}

.book-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.header-actions {
  display: flex;
  gap: 8px;
}

.create-form {
  display: flex;
  gap: 8px;
  margin-bottom: 24px;
}

.create-form input {
  flex: 1;
  max-width: 300px;
}

.cancel-btn {
  background: #555;
}

.book-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  font-size: 48px;
}

.empty {
  color: #888;
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
  background: #2a2a3e;
  border-radius: 8px;
  overflow: hidden;
  cursor: pointer;
  transition: transform 0.15s, box-shadow 0.15s;
  position: relative;
}

.sequence-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 20px rgba(0,0,0,0.3);
}

.card-thumbnail {
  width: 100%;
  height: 120px;
  overflow: hidden;
  background: #1e1e30;
}

.card-info {
  padding: 12px 16px;
}

.card-info h3 {
  font-size: 16px;
  margin-bottom: 4px;
}

.step-count {
  font-size: 12px;
  color: #888;
  word-break: break-all;
}

.title-input {
  font-size: 16px;
  font-weight: bold;
  background: #1e1e30;
  color: #fff;
  border: 1px solid #4fc3f7;
  border-radius: 4px;
  padding: 2px 6px;
  width: 100%;
  box-sizing: border-box;
}

.rename-btn {
  position: absolute;
  top: 8px;
  right: 72px;
  background: rgba(0,0,0,0.6);
  color: #ffa726;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 16px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.export-btn {
  position: absolute;
  top: 8px;
  right: 40px;
  background: rgba(0,0,0,0.6);
  color: #4fc3f7;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.delete-btn {
  position: absolute;
  top: 8px;
  right: 8px;
  background: rgba(0,0,0,0.6);
  color: #ff5252;
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  font-size: 18px;
  padding: 0;
  display: none;
  align-items: center;
  justify-content: center;
}

.sequence-card:hover .rename-btn,
.sequence-card:hover .export-btn,
.sequence-card:hover .delete-btn {
  display: flex;
}

@media (hover: none) and (pointer: coarse) {
  .rename-btn,
  .export-btn,
  .delete-btn {
    display: flex;
  }
}

@media (max-width: 600px) {
  .book-list {
    padding: 16px;
  }

  .book-header {
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
