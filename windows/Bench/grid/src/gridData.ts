/**
 * 结果集数据通道（基准台用）
 *
 * 形态（对应 §8.5.6-3 的三选一里的「Rust 侧切片喂前端」）：
 * - **数据由 Rust 侧产生**：`windows/Core` 的 `grid-bench` 生成 `grid.f64.bin`（rows×cols 小端 f64）
 *   与 `grid.meta.json`（列名 / 列型 / 文本列字典）。
 * - **前端只按窗口取数**：`window(start, len)` 的语义 = Tauri 命令将来要返回的那一份形状
 *   （`{start, rows: string[][]}`）；本基准台里它直接读同一块 ArrayBuffer（少一次 IPC），
 *   所以**本台的滚动帧率读数是「不含 IPC」的上界**，这一点如实写进 README 与记录。
 * - 文本列在二进制里存的是**字典下标**（f64），渲染时才展开成字符串 —— 与产品里「列式存储 + 取数层」同形。
 */

export type Kind = 'num' | 'text'

export interface GridMeta {
  rows: number
  cols: number
  colNames: string[]
  kinds: Kind[]
  dict: string[]
}

export class GridData {
  readonly meta: GridMeta
  private readonly cells: Float64Array
  private readonly textCols: number[]

  constructor(meta: GridMeta, cells: Float64Array) {
    if (cells.length !== meta.rows * meta.cols) {
      throw new Error(`数据长度 ${cells.length} 与 ${meta.rows}×${meta.cols} 不一致`)
    }
    this.meta = meta
    this.cells = cells
    this.textCols = meta.kinds.map((k, i) => (k === 'text' ? i : -1)).filter((i) => i >= 0)
  }

  get rows(): number {
    return this.meta.rows
  }

  get cols(): number {
    return this.meta.cols
  }

  /** 单元格文本：数值列固定 4 位小数，文本列查字典 */
  cell(row: number, col: number): string {
    const v = this.cells[row * this.meta.cols + col]
    return this.meta.kinds[col] === 'text' ? this.meta.dict[v] ?? '' : v.toFixed(4)
  }

  /** 窗口取数：一次只实体化 len 行（前端渲染需要的就这几十行） */
  window(start: number, len: number): string[][] {
    const from = Math.max(0, Math.min(start, this.meta.rows))
    const to = Math.max(from, Math.min(start + len, this.meta.rows))
    const out: string[][] = []
    for (let r = from; r < to; r++) {
      const row: string[] = new Array(this.meta.cols)
      for (let c = 0; c < this.meta.cols; c++) row[c] = this.cell(r, c)
      out.push(row)
    }
    return out
  }

  /** 前端排序（对照项：用来量化「前端排序 vs Rust 排序」的差距） */
  sortOrder(col: number, desc: boolean): Uint32Array {
    const idx = new Uint32Array(this.meta.rows)
    for (let i = 0; i < idx.length; i++) idx[i] = i
    const cells = this.cells
    const cols = this.meta.cols
    const isText = this.meta.kinds[col] === 'text'
    const dict = this.meta.dict
    const arr = Array.from(idx)
    arr.sort((a, b) => {
      const x = cells[a * cols + col]
      const y = cells[b * cols + col]
      let o: number
      if (isText) {
        const sx = dict[x] ?? ''
        const sy = dict[y] ?? ''
        o = sx < sy ? -1 : sx > sy ? 1 : 0
      } else {
        o = x < y ? -1 : x > y ? 1 : 0
      }
      return desc ? -o : o
    })
    return Uint32Array.from(arr)
  }

  /** 文本列等值筛选（前端对照项） */
  filterText(col: number, needle: string): Uint32Array {
    const hits: number[] = []
    for (let r = 0; r < this.meta.rows; r++) {
      if (this.cell(r, col) === needle) hits.push(r)
    }
    return Uint32Array.from(hits)
  }

  /** 从静态文件载入（Rust 侧产物） */
  static async load(base = '/data'): Promise<GridData> {
    const metaRes = await fetch(`${base}/grid.meta.json`)
    if (!metaRes.ok) throw new Error(`读 meta 失败：${metaRes.status}`)
    const meta = (await metaRes.json()) as GridMeta
    const binRes = await fetch(`${base}/grid.f64.bin`)
    if (!binRes.ok) throw new Error(`读数据失败：${binRes.status}`)
    const buf = await binRes.arrayBuffer()
    return new GridData(meta, new Float64Array(buf))
  }
}
