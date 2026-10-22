import { createApp } from 'vue'
import App from './App.vue'
import './theme/tokens.generated.css'
import './theme/app.css'
import {
  applyScheme,
  applyTheme,
  isLinuxShell,
  LINUX_PINNED_MODE,
  LINUX_PINNED_SCHEME,
  readStoredScheme,
  readStoredTheme
} from './theme'

// 主题与配色方案都必须在挂载前落到 <html> 上：容器组件靠 data-theme / data-theme-scheme 选档，
// 晚了会闪一帧浅色（或闪一帧默认主题）——§9.2「即时生效（挂载前应用，避免闪一帧）」。
// Linux 外壳**钉死**深色 + 深空苍穹（概设 §9.3.11：工作环境，科技风浅蓝 + 深色底）：
// 不读存储、不跟系统 —— 公司机器白天被切成浅色就不像这块屏了。Windows 侧照旧可切。
if (isLinuxShell()) {
  applyTheme(document.documentElement, LINUX_PINNED_MODE)
  applyScheme(document.documentElement, LINUX_PINNED_SCHEME)
} else {
  applyTheme(document.documentElement, readStoredTheme(window.localStorage))
  applyScheme(document.documentElement, readStoredScheme(window.localStorage))
}

createApp(App).mount('#app')
