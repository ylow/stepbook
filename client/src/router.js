import { createRouter, createWebHistory } from 'vue-router'
import HomeView from './views/HomeView.vue'
import SequenceView from './views/SequenceView.vue'

const routes = [
  { path: '/', component: HomeView },
  { path: '/sequence/:id', component: SequenceView }
]

export default createRouter({
  history: createWebHistory(),
  routes
})
