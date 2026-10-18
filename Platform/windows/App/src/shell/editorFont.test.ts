// 编辑器字体可用性判定 —— 行为判据（FR-EDIT-26 字体面）
//
// 守的是那条最容易假绿的路径：**「选了字体」不等于「字体生效」**。
// 判定错的两个方向都有人吃过苦：
//   · 判成「命中」而其实回落了 ⇒ 界面写着 JetBrains Mono、屏幕上却是 Consolas，
//     用户会以为自己挑错了字体，反复换；
//   · 判成「没装」而其实装了 ⇒ 提示「未安装」，用户去重装一个本来就有的字体。
// 所以这里把量法**注入**进来，逐条咬住三种结局。

import { describe, expect, it } from 'vitest'
import { familyPresent, fontStatus, PROBE_TEXT, canvasMeasure, detectFontStatus } from './editorFont'

/** 造一个「只有这些族参与排版」的假量法：宽度由族的集合决定，与真排版同形。 */
function measureWith(installed: string[], widths: Record<string, number> = {}) {
  const calls: string[] = []
  const measure = (cssFont: string) => {
    calls.push(cssFont)
    // 从 `16px "Name", monospace` 里取出候选族名，装了就给它自己的宽度，没装就给兜底宽度
    const quoted = /^(\d+)px "([^"]+)", monospace$/.exec(cssFont)
    if (!quoted) return 100
    const name = quoted[2]
    if (!installed.includes(name)) return 100
    return widths[name] ?? 121
  }
  return { measure, calls }
}

describe('这个族参与排版了吗', () => {
  it('装了的族 ⇒ 字宽与兜底不同 ⇒ true', () => {
    const { measure } = measureWith(['JetBrains Mono'])
    expect(familyPresent('JetBrains Mono', measure)).toBe(true)
  })

  it('没装的族 ⇒ 字宽与兜底相同 ⇒ false（不静默装作选好了）', () => {
    const { measure } = measureWith([])
    expect(familyPresent('JetBrains Mono', measure)).toBe(false)
  })

  it('族名带引号量（带空格的族名不加引号会被当成多个字体项 ⇒ 恒判没装）', () => {
    const { measure, calls } = measureWith(['Cascadia Mono'])
    familyPresent('Cascadia Mono', measure)
    expect(calls).toEqual(['16px "Cascadia Mono", monospace', '16px monospace'])
    expect(PROBE_TEXT.length).toBeGreaterThan(5)
  })

  it('空族名 ⇒ 不量也算 false（空串不是族）', () => {
    const { measure, calls } = measureWith(['Consolas'])
    expect(familyPresent('   ', measure)).toBe(false)
    expect(calls).toEqual([])
  })

  it('族名两头空白不影响判定（输入框里带空格是常态）', () => {
    const { measure } = measureWith(['Consolas'])
    expect(familyPresent('  Consolas  ', measure)).toBe(true)
  })
})

describe('三档判定', () => {
  it('未选（null / 空串 / 全空白）⇒ system', () => {
    for (const family of [null, '', '   ']) {
      expect(fontStatus(family, () => true)).toBe('system')
    }
  })

  it('选了且量到 ⇒ resolved；选了没量到 ⇒ missing', () => {
    expect(fontStatus('Consolas', () => true)).toBe('resolved')
    expect(fontStatus('Consolas', () => false)).toBe('missing')
    // 判 missing 时**不许**看成 system：界面要据此说「已回落」，不能装作没选过
    expect(fontStatus('Consolas', () => false)).not.toBe('system')
  })
})

describe('真环境入口', () => {
  it('node 环境没有 canvas ⇒ 量不了就不报警（不凭猜测说用户没装）', () => {
    expect(canvasMeasure()).toBeNull()
    expect(detectFontStatus('JetBrains Mono')).toBe('resolved')
    expect(detectFontStatus(null)).toBe('system')
  })
})
