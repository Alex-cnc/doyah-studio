// 查找 / 替换 · 行为判据（FR-EDIT-18）
//
// 用例名就是需求里那句话，读清单 = 读需求。反面用例（不认正则 / 不重叠 / 位置失效不改文本）与正例同权 ——
// 这一片的危险动作是"改文本"，判错一次就是静默改坏别人的 SQL。

import { describe, expect, it } from 'vitest'
import {
  findMatches,
  matchIndexAt,
  readout,
  replaceAll,
  replaceOne,
  stepMatch,
} from './findReplace'

describe('查找：字面量命中', () => {
  it('大小写不区分是缺省档（SQL 里随手打是常态）', () => {
    expect(findMatches('SELECT a FROM t', 'select')).toEqual([0])
  })

  it('区分大小写档只认原样', () => {
    expect(findMatches('SELECT a FROM t', 'select', { caseSensitive: true })).toEqual([])
    expect(findMatches('SELECT a FROM t', 'SELECT', { caseSensitive: true })).toEqual([0])
  })

  it('多处命中按起点升序全给出来', () => {
    expect(findMatches('aa-bb-aa', 'aa')).toEqual([0, 6])
  })

  it('非重叠：aaa 里查 aa 只算一处（重叠会让"全部替换"把同一段改两遍）', () => {
    expect(findMatches('aaa', 'aa')).toEqual([0])
  })

  it('空查询不出匹配（查空串命中每一处是噪音，不是功能）', () => {
    expect(findMatches('select 1', '')).toEqual([])
  })

  it('查的是字面量：count(*) 里的括号与星号不当正则元字符', () => {
    expect(findMatches('select count(*) from t', 'count(*)')).toEqual([7])
    expect(findMatches('select a.b from t', 'a.b')).toEqual([7])
  })

  it('中文与表情上按码元下标切，不按肉眼字符数', () => {
    const text = 'select 名字 from 表'
    const at = findMatches(text, 'from')
    expect(text.slice(at[0], at[0] + 4)).toBe('from')
    const emoji = 'x🙂y'
    expect(findMatches(emoji, 'y')).toEqual([3]) // 🙏 占两个码元
  })
})

describe('当前该看哪一处 / 上一处下一处', () => {
  it('从光标处往后找第一条命中；都过了就绕回第一处', () => {
    const matches = findMatches('aa-aa-aa', 'aa')
    expect(matchIndexAt(matches, 0)).toBe(0)
    expect(matchIndexAt(matches, 1)).toBe(1)
    expect(matchIndexAt(matches, 99)).toBe(0)
  })

  it('没有命中时返回 -1（调用方据此说"没有匹配"，而不是假装在第 1 处）', () => {
    expect(matchIndexAt([], 5)).toBe(-1)
  })

  it('下一处 / 上一处都环绕，一条都没有时 -1', () => {
    expect(stepMatch(3, 2, 1)).toBe(0)
    expect(stepMatch(3, 0, -1)).toBe(2)
    expect(stepMatch(3, -1, 1)).toBe(0)
    expect(stepMatch(3, -1, -1)).toBe(2)
    expect(stepMatch(0, -1, 1)).toBe(-1)
  })

  it('读数：0 处说 0 处；第几处是 1 基且越界夹回末处', () => {
    expect(readout([], -1)).toEqual({ total: 0, position: 0, empty: true })
    expect(readout([0, 3, 6], 1)).toEqual({ total: 3, position: 2, empty: false })
    expect(readout([0, 3, 6], 9)).toEqual({ total: 3, position: 3, empty: false })
  })
})

describe('替换一处', () => {
  it('替掉起点那一处，光标落在替换串之后', () => {
    const result = replaceOne('select 1 from t', 'from', 'FROM', 9)
    expect(result.text).toBe('select 1 FROM t')
    expect(result.count).toBe(1)
    expect(result.caret).toBe(13)
  })

  it('区分大小写下大小写不符 ⇒ 一个字都不改（不"顺手"改个大小写）', () => {
    const result = replaceOne('select 1', 'SELECT', 'x', 0, { caseSensitive: true })
    expect(result.text).toBe('select 1')
    expect(result.count).toBe(0)
  })

  it('起点处已经不是那段文字（文本在两次调用之间被改过）⇒ 不改文本', () => {
    const result = replaceOne('select 22 from t', 'from', 'FROM', 9)
    expect(result.text).toBe('select 22 from t')
    expect(result.count).toBe(0)
  })

  it('起点越界 ⇒ 不改文本', () => {
    expect(replaceOne('abc', 'abc', 'x', 99).count).toBe(0)
    expect(replaceOne('abc', 'abc', 'x', -1).count).toBe(0)
  })
})

describe('替换全部', () => {
  it('逐处替换并给出计数', () => {
    const result = replaceAll('a FROM t WHERE a FROM x', 'from', 'FROM')
    expect(result.text).toBe('a FROM t WHERE a FROM x')
    expect(result.count).toBe(2)
  })

  it('替换串里的 $& / $1 是字面量（不许被当成"匹配到的原文"）', () => {
    const result = replaceAll('price = 1', '1', '$&$1')
    expect(result.text).toBe('price = $&$1')
  })

  it('替换串里含着查询串 ⇒ 只扫原文一遍，不会自己喂自己', () => {
    const result = replaceAll('a.a', '.', '..')
    expect(result.text).toBe('a..a')
    expect(result.count).toBe(1)
  })

  it('一处都没有 ⇒ 文本原样、计数 0（界面据此说"没有匹配"）', () => {
    const result = replaceAll('select 1', 'zzz', 'x')
    expect(result.text).toBe('select 1')
    expect(result.count).toBe(0)
  })
})
