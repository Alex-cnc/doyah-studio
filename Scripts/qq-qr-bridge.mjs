#!/usr/bin/env node
// QQ 扫码接入的本地桥（`FR-AGT-LINK-CHAN-003`）。
//
// 为什么要有它：腾讯官方只提供 Node 版 `@tencent-connect/qqbot-connector`（扫码后直接返回
// AppID / AppSecret / 主人 openid），Swift 侧无法直接调用 ⇒ 用一个最小桥把「二维码」和
// 「扫码结果」以**逐行 JSON** 吐给宿主，宿主只管画二维码、轮询状态、落库。
//
// 输出协议（每行一个 JSON 对象，宿主按行解析；其它输出一律忽略）：
//   {"event":"qr","url":"https://…"}                       二维码内容（宿主渲染成图）
//   {"event":"expired"}                                    二维码过期（宿主提示并等下一张）
//   {"event":"success","appId":"…","appSecret":"…","openId":"…"}
//   {"event":"failed","error":"…"}
//
// 宿主取消 = 杀掉本进程（子进程退出即释放轮询，不留后台任务）。

import { pathToFileURL } from 'node:url'
import { homedir } from 'node:os'
import { existsSync } from 'node:fs'

const send = (obj) => process.stdout.write(JSON.stringify(obj) + '\n')

// 连接器只认 **ESM 入口**：它的 CJS 构建在本机 require 会直接抛（实测），所以按文件路径动态 import。
// 查找顺序：显式入口 → DSH 桌面档案 → DSH web 档案 → 全局 node_modules。
const entries = [
  process.env.DOYAH_QQ_CONNECTOR_ENTRY,
  `${homedir()}/.dsh/profiles/desktop/node_modules/@tencent-connect/qqbot-connector/dist/esm/index.js`,
  `${homedir()}/.dsh/profiles/web/node_modules/@tencent-connect/qqbot-connector/dist/esm/index.js`,
  '/opt/homebrew/lib/node_modules/@tencent-connect/qqbot-connector/dist/esm/index.js',
].filter(Boolean)

let connector = null
let lastError = null
for (const entry of entries) {
  try {
    if (!existsSync(entry)) throw new Error('不存在：' + entry)
    connector = await import(pathToFileURL(entry).href)
    if (typeof connector.startQrConnect === 'function') break
    connector = null
    lastError = new Error('该入口没有 startQrConnect')
  } catch (error) {
    lastError = error
  }
}
if (!connector || typeof connector.startQrConnect !== 'function') {
  send({ event: 'failed', error: '找不到 @tencent-connect/qqbot-connector：' + (lastError ? lastError.message : '未知原因') })
  process.exit(3)
}

let disposed = false
const dispose = async () => {
  if (disposed) return
  disposed = true
  try { if (typeof handle === 'function') handle() } catch {}
}

const handle = connector.startQrConnect({
  onQrDisplayed: (url) => {
    const text = typeof url === 'string' ? url.trim() : ''
    if (text) send({ event: 'qr', url: text })
  },
  onQrExpired: () => send({ event: 'expired' }),
  onSuccess: (raw) => {
    const first = Array.isArray(raw) ? raw[0] : raw
    const appId = first && typeof first === 'object' ? String(first.appId ?? '').trim() : ''
    const appSecret = first && typeof first === 'object' ? String(first.appSecret ?? '').trim() : ''
    const openId = first && typeof first === 'object' ? String(first.userOpenid ?? '').trim() : ''
    if (!appId || !appSecret) {
      send({ event: 'failed', error: 'QQ 授权结果缺少 AppID 或 AppSecret' })
    } else {
      send({ event: 'success', appId, appSecret, openId })
    }
    dispose()
  },
  onFailure: (error) => {
    send({ event: 'failed', error: String((error && error.message) || error || '扫码服务不可用') })
    dispose()
  },
}, { displayQrCodeToConsole: false, source: 'doyah-studio' })

// 宿主 Ctrl-C / 取消时把连接器一起释放，避免它继续在后台轮询二维码。
process.on('SIGTERM', async () => { await dispose(); process.exit(0) })
process.on('SIGINT', async () => { await dispose(); process.exit(0) })
