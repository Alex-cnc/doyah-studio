// 构建标识渲染 —— 行为判据（S-073c · 对应锚点 T-20261007-073 第②条）
//
// 守的不变量：
//   ① 满值 ⇒ `v<version> · <buildHead> · <buildTime>`（分隔符与窗口标题同口径 `·`）；
//   ② 缺任一段（含空串 / `null` 入参）⇒ 退化为 `v<version>`；
//   ③ 输出里**绝不出现** `undefined` / `null` / `unknown` 字样。

import { describe, expect, it } from 'vitest'
import { buildStamp, type BuildStampSource } from './buildStamp'

const FULL: BuildStampSource = { version: '0.3.0', buildHead: '1bd67fa', buildTime: '10-08 07:35' }

describe('构建标识 buildStamp', () => {
  it('满值：v<版本> · <短号> · <时刻>', () => {
    expect(buildStamp(FULL)).toBe('v0.3.0 · 1bd67fa · 10-08 07:35')
  })

  it('缺 buildHead：退化为 v<版本>', () => {
    expect(buildStamp({ ...FULL, buildHead: undefined })).toBe('v0.3.0')
    expect(buildStamp({ ...FULL, buildHead: '' })).toBe('v0.3.0')
    expect(buildStamp({ ...FULL, buildHead: null })).toBe('v0.3.0')
  })

  it('缺 buildTime：退化为 v<版本>', () => {
    expect(buildStamp({ ...FULL, buildTime: undefined })).toBe('v0.3.0')
    expect(buildStamp({ ...FULL, buildTime: '' })).toBe('v0.3.0')
    expect(buildStamp({ ...FULL, buildTime: null })).toBe('v0.3.0')
  })

  it('两者皆缺（含空串）：退化为 v<版本>', () => {
    expect(buildStamp({ version: '0.3.0' })).toBe('v0.3.0')
    expect(buildStamp({ version: '0.3.0', buildHead: '', buildTime: '' })).toBe('v0.3.0')
  })

  it('null / undefined 入参、空 version：仍然是可读的一串，不炸', () => {
    expect(buildStamp(null)).toBe('v')
    expect(buildStamp(undefined)).toBe('v')
    expect(buildStamp({ version: '' })).toBe('v')
    // 版本空、但两段构建标识都在：仍按满值给（输出里同样不出现 undefined/null）
    expect(buildStamp({ version: '', buildHead: '1bd67fa', buildTime: '10-08 07:35' })).toBe(
      'v · 1bd67fa · 10-08 07:35',
    )
  })

  it('浏览器旁路（buildHead=browser / buildTime=空）：退化为 v<版本>，不写死真提交号', () => {
    expect(buildStamp({ version: '0.2.0', buildHead: 'browser', buildTime: '' })).toBe('v0.2.0')
  })

  it('任何情况下输出里不出现 undefined / null / unknown 字样', () => {
    const inputs: Array<BuildStampSource | null | undefined> = [
      FULL,
      { ...FULL, buildHead: undefined },
      { ...FULL, buildTime: undefined },
      {},
      { version: '0.3.0' },
      null,
      undefined,
    ]
    for (const input of inputs) {
      const out = buildStamp(input)
      expect(out).not.toMatch(/undefined|null|unknown/)
      expect(out.startsWith('v')).toBe(true)
    }
  })
})
