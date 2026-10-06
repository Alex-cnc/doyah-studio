import { createApp } from 'vue'
import App from './App.vue'
import './theme/tokens.generated.css'
import './theme/app.css'
import { applyScheme, applyTheme, readStoredScheme, readStoredTheme } from './theme'

// 主题与配色方案都必须在挂载前落到 <html> 上：容器组件靠 data-theme / data-theme-scheme 选档，
// 晚了会闪一帧浅色（或闪一帧默认主题）——§9.2「即时生效（挂载前应用，避免闪一帧）」。
applyTheme(document.documentElement, readStoredTheme(window.localStorage))
applyScheme(document.documentElement, readStoredScheme(window.localStorage))

createApp(App).mount('#app')
