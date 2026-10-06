import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 基准台（不是产品表示层）：只服务「结果网格压力基准」这一件事。
// 端口固定，方便脚本/无头浏览器直接连；strictPort 让端口被占时立刻失败而不是静默换端口。
export default defineConfig({
  plugins: [vue()],
  server: { port: 5273, strictPort: true },
  preview: { port: 5273, strictPort: true },
})
