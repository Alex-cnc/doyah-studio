import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'

// 表示层外壳（产品形态）：Tauri 2 在 Windows 上用系统 WebView2 承载这个前端。
// 端口固定 5274（与基准台 5273 分开）：strictPort 让端口被占时立刻失败，而不是静默换端口后
// 跟 tauri.conf.json 的 devUrl 对不上。
export default defineConfig({
  plugins: [vue()],
  // 相对基址：Tauri 里前端由自定义协议加载，绝对路径会 404。
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'chrome120',
  },
  server: { port: 5274, strictPort: true },
  preview: { port: 5274, strictPort: true },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'tests/**/*.test.mjs'],
  },
})
