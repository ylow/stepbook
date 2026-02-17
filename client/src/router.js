import { createRouter, createWebHistory } from 'vue-router'
import BookListView from './views/BookListView.vue'
import HomeView from './views/HomeView.vue'
import SequenceView from './views/SequenceView.vue'

const routes = [
  { path: '/', component: BookListView },
  { path: '/book/:bookId', component: HomeView },
  { path: '/book/:bookId/sequence/:id', component: SequenceView }
]

export default createRouter({
  history: createWebHistory(),
  routes
})
