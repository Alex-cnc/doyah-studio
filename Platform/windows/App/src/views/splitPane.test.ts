// 分隔条纯逻辑判据（FR-EDIT-13）
//
// 为什么单测这一层：拖动链上真正会错的是「夹紧」——上下限、容器量不到、容器比两倍下限还窄。
// 那些在挂载测试里要造一堆假尺寸才碰得到，而它们的正确性只跟算术有关。
import { describe, expect, it } from 'vitest'
import { SPLIT_MIN_PANE, SPLIT_STEP, clampSplitHeight, stepSplitHeight } from './splitPane'

describe('clampSplitHeight（两区各 ≥120px）', () => {
  it('正常值原样返回（取整）', () => {
    expect(clampSplitHeight(240.4, 600)).toBe(240)
  })

  it('小于下限 ⇒ 夹到 120（拖动不可能把编辑区压成 0）', () => {
    expect(clampSplitHeight(10, 600)).toBe(SPLIT_MIN_PANE)
    expect(clampSplitHeight(-500, 600)).toBe(SPLIT_MIN_PANE)
  })

  it('大于「容器 − 120」⇒ 夹到上限（结果区也留 120）', () => {
    expect(clampSplitHeight(900, 600)).toBe(480)
  })

  it('容器量不到（0 / 非有限数）⇒ 只保下限，不硬夹上限', () => {
    expect(clampSplitHeight(300, 0)).toBe(300)
    expect(clampSplitHeight(300, Number.NaN)).toBe(300)
    expect(clampSplitHeight(10, 0)).toBe(SPLIT_MIN_PANE)
  })

  it('容器比两倍下限还窄 ⇒ 保下限（不产出负数或 0，宁可让下方区溢出）', () => {
    expect(clampSplitHeight(300, 200)).toBe(SPLIT_MIN_PANE)
    expect(clampSplitHeight(300, 10)).toBe(SPLIT_MIN_PANE)
  })

  it('想要的值本身不是有限数 ⇒ 退回下限', () => {
    expect(clampSplitHeight(Number.NaN, 600)).toBe(SPLIT_MIN_PANE)
    expect(clampSplitHeight(Number.POSITIVE_INFINITY, 600)).toBe(SPLIT_MIN_PANE)
  })
})

describe('stepSplitHeight（↑↓ 步进 16px）', () => {
  it('加减一步', () => {
    expect(stepSplitHeight(240, SPLIT_STEP, 600)).toBe(256)
    expect(stepSplitHeight(240, -SPLIT_STEP, 600)).toBe(224)
  })

  it('越界即夹紧，不环绕（到底再按 ↓ 不该跳回顶）', () => {
    expect(stepSplitHeight(470, SPLIT_STEP, 600)).toBe(480)
    expect(stepSplitHeight(130, -SPLIT_STEP, 600)).toBe(SPLIT_MIN_PANE)
  })

  it('当前值不是有限数 ⇒ 按下限算（首帧没量到尺寸也不会跳变）', () => {
    expect(stepSplitHeight(Number.NaN, SPLIT_STEP, 600)).toBe(SPLIT_MIN_PANE + SPLIT_STEP)
  })
})
