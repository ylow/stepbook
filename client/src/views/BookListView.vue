<template>
  <div class="book-list">
    <header class="book-header">
      <h1>Stepbook</h1>
      <div class="header-actions">
        <button @click="showAddFolder = true">Add Folder</button>
        <button @click="showCreate = true">+ New Book</button>
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
          <h3>{{ book.name }}</h3>
          <span class="step-count">{{ book.path }}</span>
        </div>
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
import { fetchBooks, createBook, addExistingBook, removeBook } from '../api.js'

const router = useRouter()
const bookList = ref([])
const showCreate = ref(false)
const showAddFolder = ref(false)
const newName = ref('')
const addFolderName = ref('')
const addFolderPath = ref('')
const nameInput = ref(null)
const addNameInput = ref(null)

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

.sequence-card:hover .delete-btn {
  display: flex;
}
</style>
