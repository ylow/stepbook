import { createApp } from 'vue'
import App from './App.vue'
import router from './router.js'
import VueKonva from 'vue-konva'
import './style.css'

createApp(App).use(router).use(VueKonva).mount('#app')
