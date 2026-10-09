#!/usr/bin/env node
// Doyah Studio · Windows 侧 · 应用图标生成器（platform/windows/App/tools/gen-icons.mjs）
//
// 为什么要有它：Tauri 在 Windows 上把 `bundle.icon` 里那个 `.ico` 嵌进 exe（`tauri-build` 找不到即失败），
// 打包 MSI / NSIS 也要图标。图标是**生成物**（可复现），所以入库的是这个脚本 + **母版** + 生成结果。
//
// 源（唯一母版）：`tools/icon-source-1024.png` —— 与派单仓
//   `_shared/DoyahDispatch/assets/product-icon/icon-transparent-1024.png` **逐字节相同**
//   （1024×1024 · bitDepth 8 · **colorType 6 RGBA** · 无隔行 · **底衬 = 透明**）。
//
// 本脚本**只做等比缩放**（面积平均 / box filter，按源像元与目标像元的覆盖面积加权），
// 产出既有各档 PNG 与**七档 `icon.ico`（16/24/32/48/64/128/256）**：
//   · 不裁切构图、不加底衬、**母版 alpha 逐档原样保留**（四角 / 四边 alpha=0 ⇒ 各档透明底）；
//   · **不引第三方依赖**（解码 / 缩放 / 编码全用 node 内置模块，见文件末 `import` 行）。
//
// 用法：node tools/gen-icons.mjs [--check]
//   --check：只比对（生成物与盘上是否逐字节一致），有漂移即 exit 1。

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { inflateSync, deflateSync } from 'node:zlib'

const here = dirname(fileURLToPath(import.meta.url))
const appDir = resolve(here, '..')
const repoRoot = resolve(here, '../../../..')
const sourcePath = resolve(here, 'icon-source-1024.png')
const outDir = resolve(appDir, 'src-tauri/icons')

// `.ico` 七档全出（缺一不算交付）；PNG 生成物沿用既有四件（Tauri 配置引用面不变）。
const ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

const toRepoPath = (absolute) => relative(repoRoot, absolute).split(sep).join('/')

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

/** Paeth 预测子（PNG 滤波类型 4 用）。 */
function paeth(a, b, c) {
  const p = a + b - c
  const pa = Math.abs(p - a)
  const pb = Math.abs(p - b)
  const pc = Math.abs(p - c)
  if (pa <= pb && pa <= pc) return a
  if (pb <= pc) return b
  return c
}

/** 解码 8 位 PNG（colorType 0/2/4/6 · 非隔行）⇒ { width, height, channels, pixels }（逐像素紧密排列）。 */
function decodePng(buffer) {
  if (buffer.length < 8 || !buffer.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error('不是 PNG 文件（签名不符）')
  }
  let at = 8
  let header = null
  const idat = []
  while (at + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(at)
    const type = buffer.subarray(at + 4, at + 8).toString('ascii')
    const data = buffer.subarray(at + 8, at + 8 + length)
    at += 12 + length // length(4) + type(4) + data + crc(4)
    if (type === 'IHDR') header = data
    else if (type === 'IDAT') idat.push(data)
    else if (type === 'IEND') break
  }
  if (!header) throw new Error('PNG 里没有 IHDR')
  const width = header.readUInt32BE(0)
  const height = header.readUInt32BE(4)
  const bitDepth = header[8]
  const colorType = header[9]
  const interlace = header[12]
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType]
  if (bitDepth !== 8 || channels === undefined || interlace !== 0) {
    throw new Error(`不支持的 PNG 形态（bitDepth=${bitDepth} colorType=${colorType} interlace=${interlace}）`)
  }
  const raw = inflateSync(Buffer.concat(idat))
  const stride = width * channels
  const pixels = Buffer.alloc(height * stride)
  let pos = 0
  for (let y = 0; y < height; y += 1) {
    const filter = raw[pos]
    pos += 1
    const rowStart = y * stride
    const prevStart = (y - 1) * stride
    for (let x = 0; x < stride; x += 1) {
      const rawByte = raw[pos + x]
      const a = x >= channels ? pixels[rowStart + x - channels] : 0
      const b = y > 0 ? pixels[prevStart + x] : 0
      const c = x >= channels && y > 0 ? pixels[prevStart + x - channels] : 0
      let value
      switch (filter) {
        case 0: value = rawByte; break
        case 1: value = rawByte + a; break
        case 2: value = rawByte + b; break
        case 3: value = rawByte + ((a + b) >> 1); break
        case 4: value = rawByte + paeth(a, b, c); break
        default: throw new Error(`未知 PNG 滤波类型 ${filter}`)
      }
      pixels[rowStart + x] = value & 0xff
    }
    pos += stride
  }
  return { width, height, channels, pixels }
}

/**
 * **等比**面积平均缩放（box filter）：目标像元的颜色 = 源图上该像元覆盖区域内
 * 各源像元按**覆盖面积**加权的平均。不裁切、不变形（正方形入 ⇒ 正方形出）。
 */
function resizeArea(image, targetSize) {
  const { width, height, channels, pixels } = image
  const out = Buffer.alloc(targetSize * targetSize * channels)
  const scaleX = width / targetSize
  const scaleY = height / targetSize
  const acc = new Array(channels).fill(0)
  for (let dy = 0; dy < targetSize; dy += 1) {
    const sy0 = dy * scaleY
    const sy1 = (dy + 1) * scaleY
    const iy0 = Math.floor(sy0)
    const iy1 = Math.min(height, Math.ceil(sy1))
    for (let dx = 0; dx < targetSize; dx += 1) {
      const sx0 = dx * scaleX
      const sx1 = (dx + 1) * scaleX
      const ix0 = Math.floor(sx0)
      const ix1 = Math.min(width, Math.ceil(sx1))
      acc.fill(0)
      let weightSum = 0
      for (let sy = iy0; sy < iy1; sy += 1) {
        const wy = Math.min(sy + 1, sy1) - Math.max(sy, sy0)
        if (wy <= 0) continue
        for (let sx = ix0; sx < ix1; sx += 1) {
          const wx = Math.min(sx + 1, sx1) - Math.max(sx, sx0)
          if (wx <= 0) continue
          const w = wx * wy
          const srcAt = (sy * width + sx) * channels
          for (let ch = 0; ch < channels; ch += 1) acc[ch] += pixels[srcAt + ch] * w
          weightSum += w
        }
      }
      const outAt = (dy * targetSize + dx) * channels
      for (let ch = 0; ch < channels; ch += 1) {
        out[outAt + ch] = weightSum > 0 ? Math.round(acc[ch] / weightSum) : 0
      }
    }
  }
  return { width: targetSize, height: targetSize, channels, pixels: out }
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

/** 编码 8 位 PNG（通道数照旧：3 通道 ⇒ colorType 2，4 通道 ⇒ colorType 6）。 */
function encodePng(image) {
  const { width, height, channels, pixels } = image
  const stride = width * channels
  const rows = Buffer.alloc(height * (stride + 1))
  for (let y = 0; y < height; y += 1) {
    const rowAt = y * (stride + 1)
    rows[rowAt] = 0 // filter: none
    pixels.copy(rows, rowAt + 1, y * stride, y * stride + stride)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = channels === 4 ? 6 : 2 // colour type
  return Buffer.concat([
    PNG_SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(rows, { level: 9 })),
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

if (!existsSync(sourcePath)) {
  process.stderr.write(`✗ 母版不在盘上：${toRepoPath(sourcePath)}（应先有与派单仓逐字节相同的 icon-source-1024.png）\n`)
  process.exit(1)
}
let source
try {
  source = decodePng(readFileSync(sourcePath))
} catch (error) {
  process.stderr.write(`✗ 母版读不出：${toRepoPath(sourcePath)} —— ${error.message}\n`)
  process.exit(1)
}
if (source.width !== source.height) {
  process.stderr.write(`✗ 母版不是正方形（${source.width}×${source.height}）⇒ 等比派生各档取不出（停手，不裁切）\n`)
  process.exit(1)
}

const cache = new Map()
const pngAt = (size) => {
  if (!cache.has(size)) cache.set(size, encodePng(resizeArea(source, size)))
  return cache.get(size)
}

const ico = makeIco(ICO_SIZES.map((size) => ({ size, data: pngAt(size) })))

const targets = [
  { path: resolve(outDir, '32x32.png'), data: pngAt(32) },
  { path: resolve(outDir, '128x128.png'), data: pngAt(128) },
  { path: resolve(outDir, '128x128@2x.png'), data: pngAt(256) },
  { path: resolve(outDir, 'icon.png'), data: pngAt(256) },
  { path: resolve(outDir, 'icon.ico'), data: ico },
]

const checkOnly = process.argv.includes('--check')
let problems = 0
if (!checkOnly) mkdirSync(outDir, { recursive: true })

for (const { path, data } of targets) {
  const repoPath = toRepoPath(path)
  if (checkOnly) {
    if (!existsSync(path) || !readFileSync(path).equals(data)) {
      process.stderr.write(`✗ 图标与生成器不一致：${repoPath} —— 手改过生成物，或换了母版没重新生成\n`)
      problems += 1
    }
    continue
  }
  writeFileSync(path, data)
  process.stdout.write(`✅ 已生成 ${repoPath}（${data.length} 字节）\n`)
}

if (problems > 0) process.exit(1)
if (checkOnly) {
  process.stdout.write(`✅ 图标生成物与生成器一致（${targets.length} 个；母版 ${source.width}×${source.height} · ico ${ICO_SIZES.length} 档）\n`)
}
