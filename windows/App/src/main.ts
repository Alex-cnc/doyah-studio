import { createApp } from 'vue'
import App from './App.vue'
import './theme/tokens.generated.css'
import './theme/app.css'
import { applyTheme, readStoredTheme } from './theme'

// 主题必须在挂载前落到 <html> 上：容器组件靠 data-theme 选档，晚了会闪一帧浅色。
applyTheme(document.documentElement, readStoredTheme(window.localStorage))

createApp(App).mount('#app')
