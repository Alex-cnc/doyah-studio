#!/usr/bin/env node
// Doyah Studio · Windows 侧 · 应用图标生成器（platform/windows/App/tools/gen-icons.mjs）
//
// 为什么要有它：Tauri 在 Windows 上把 `bundle.icon` 里那个 `.ico` 嵌进 exe（`tauri-build` 找不到即失败），
// 打包 MSI / NSIS 也要图标。图标是**生成物**（可复现、无二进制依赖），所以入库的是这个脚本 + 生成结果。
//
// 颜色**不手抄**：从生成物 `src/theme/tokens.generated.css` 里读 `--ds-color-categorical-blue`
// （令牌取值的单一来源仍是 macOS 侧 `Core/DesignTokens.swift`）。
//
// 用法：node tools/gen-icons.mjs [--check]
//   --check：只比对（生成物与盘上是否逐字节一致），有漂移即 exit 1。

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { deflateSync } from 'node:zlib'

const here = dirname(fileURLToPath(import.meta.url))
const appDir = resolve(here, '..')
const repoRoot = resolve(here, '../../../..')
const tokensCss = resolve(appDir, 'src/theme/tokens.generated.css')
const outDir = resolve(appDir, 'src-tauri/icons')
const SIZES = [32, 128, 256]

const toRepoPath = (absolute) => relative(repoRoot, absolute).split(sep).join('/')

function readBrandColor() {
  if (!existsSync(tokensCss)) {
    process.stderr.write(`✗ 令牌生成物不在盘上：${toRepoPath(tokensCss)}（先跑 node tools/gen-tokens.mjs）\n`)
    process.exit(1)
  }
  const text = readFileSync(tokensCss, 'utf8')
  const match = text.match(/--ds-color-categorical-blue:\s*#([0-9A-Fa-f]{6})/)
  if (!match) {
    process.stderr.write('✗ 令牌生成物里找不到 --ds-color-categorical-blue ⇒ 图标底色没有来源（不手抄）\n')
    process.exit(1)
  }
  return match[1].toUpperCase()
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n += 1) {
    let c = n
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c
  }
  return table
})()

function crc32(buffer) {
  let c = 0xffffffff
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const length = Buffer.alloc(4)
  length.writeUInt32BE(data.length, 0)
  const typeAndData = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(typeAndData), 0)
  return Buffer.concat([length, typeAndData, crc])
}

/** 32 位 RGBA PNG：底色 = 品牌色，中央一个浅色「D」形块（形状只为辨识，不是品牌稿）。 */
function makePng(size, hex) {
  const [r, g, b] = [hex.slice(0, 2), hex.slice(2, 4), hex.slice(4, 6)].map((part) => Number.parseInt(part, 16))
  const rows = []
  const inset = Math.round(size * 0.22)
  const barWidth = Math.max(1, Math.round(size * 0.12))
  for (let y = 0; y < size; y += 1) {
    const row = Buffer.alloc(1 + size * 4)
    row[0] = 0 // filter: none
    for (let x = 0; x < size; x += 1) {
      const offset = 1 + x * 4
      const inField = x >= inset && x < size - inset && y >= inset && y < size - inset
      const isBar = inField && (x < inset + barWidth || x >= size - inset - barWidth)
      if (isBar) {
        row[offset] = 0xff
        row[offset + 1] = 0xff
        row[offset + 2] = 0xff
        row[offset + 3] = 0xff
      } else if (inField) {
        row[offset] = r
        row[offset + 1] = g
        row[offset + 2] = b
        row[offset + 3] = 0xff
      } else {
        row[offset] = 0
        row[offset + 1] = 0
        row[offset + 2] = 0
        row[offset + 3] = 0
      }
    }
    rows.push(row)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(size, 0)
  ihdr.writeUInt32BE(size, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // colour type: RGBA
  ihdr[10] = 0
  ihdr[11] = 0
  ihdr[12] = 0
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(rows), { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

/** ICO 容器：逐档内嵌 PNG（Vista 起合法，Tauri 用的 `ico` crate 认）。 */
function makeIco(entries) {
  const header = Buffer.alloc(6)
  header.writeUInt16LE(0, 0)
  header.writeUInt16LE(1, 2)
  header.writeUInt16LE(entries.length, 4)
  const directory = Buffer.alloc(entries.length * 16)
  let offset = 6 + entries.length * 16
  entries.forEach((entry, index) => {
    const at = index * 16
    directory[at] = entry.size >= 256 ? 0 : entry.size
    directory[at + 1] = entry.size >= 256 ? 0 : entry.size
    directory[at + 2] = 0
    directory[at + 3] = 0
    directory.writeUInt16LE(1, at + 4)
    directory.writeUInt16LE(32, at + 6)
    directory.writeUInt32LE(entry.data.length, at + 8)
    directory.writeUInt32LE(offset, at + 12)
    offset += entry.data.length
  })
  return Buffer.concat([header, directory, ...entries.map((entry) => entry.data)])
}

const brand = readBrandColor()
const pngs = new Map(SIZES.map((size) => [size, makePng(size, brand)]))
const ico = makeIco([32, 128, 256].map((size) => ({ size, data: pngs.get(size) })))

const targets = [
  { path: resolve(outDir, '32x32.png'), data: pngs.get(32) },
  { path: resolve(outDir, '128x128.png'), data: pngs.get(128) },
  { path: resolve(outDir, '128x128@2x.png'), data: pngs.get(256) },
  { path: resolve(outDir, 'icon.png'), data: pngs.get(256) },
  { path: resolve(outDir, 'icon.ico'), data: ico },
]

const checkOnly = process.argv.includes('--check')
let problems = 0
if (!checkOnly) mkdirSync(outDir, { recursive: true })

for (const { path, data } of targets) {
  const repoPath = toRepoPath(path)
  if (checkOnly) {
    if (!existsSync(path) || !readFileSync(path).equals(data)) {
      process.stderr.write(`✗ 图标与生成器不一致：${repoPath} —— 手改过生成物，或改了品牌色没重新生成\n`)
      problems += 1
    }
    continue
  }
  writeFileSync(path, data)
  process.stdout.write(`✅ 已生成 ${repoPath}（${data.length} 字节）\n`)
}

if (problems > 0) process.exit(1)
if (checkOnly) {
  process.stdout.write(`✅ 图标生成物与生成器一致（${targets.length} 个；品牌色 #${brand}）\n`)
}
