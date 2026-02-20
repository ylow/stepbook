import { createApp } from 'vue'
import { registerSW } from 'virtual:pwa-register'
import App from './App.vue'
import router from './router.js'
import VueKonva from 'vue-konva'
import './style.css'

// Register service worker with periodic update checks.
// Combined with no-cache headers on sw.js, this ensures
// new deployments are picked up within minutes, not hours.
registerSW({
  immediate: true,
  onRegisteredSW(swUrl, registration) {
    if (registration) {
      setInterval(() => registration.update(), 10 * 60 * 1000)
    }
  }
})

createApp(App).use(router).use(VueKonva).mount('#app')
