import { describe, expect, it } from 'vitest'
import { DICT, t, toggleLanguage, type DictKey } from './index'

describe('i18n 语言表', () => {
  it('每条都有两种语言，且都不为空', () => {
    for (const [key, entry] of Object.entries(DICT)) {
      expect(entry['zh-Hans'].trim(), `${key} 的中文为空`).not.toBe('')
      expect(entry.en.trim(), `${key} 的英文为空`).not.toBe('')
    }
  })

  it('两种语言的键集合完全一致（缺一种编译期就过不去，这里再验一次）', () => {
    for (const [key, entry] of Object.entries(DICT)) {
      const zh = Object.keys(entry).sort()
      expect(zh, `${key} 的键不一致`).toEqual(['en', 'zh-Hans'])
    }
  })

  it('查表按语言给对应文案', () => {
    expect(t('sql.run', 'zh-Hans')).toBe('执行')
    expect(t('sql.run', 'en')).toBe('Run')
  })

  it('插值替换所有同名占位符，且不动其它文字', () => {
    const text = t('grid.rows.summary', 'en', { hit: 3, total: 10 })
    expect(text).toBe('3 of 10 rows matched')
    const truncated = t('sql.truncated', 'zh-Hans', { returned: 500, shown: 100 })
    expect(truncated).toContain('500')
    expect(truncated).toContain('100')
  })

  it('没给变量时占位符原样留着（不静默吞掉）', () => {
    // 这比"替换成空串"好：空串会让句子看着通顺但少了数字
    expect(t('sql.rows', 'en')).toContain('{n}')
  })

  it('切换语言是对称的', () => {
    expect(toggleLanguage('zh-Hans')).toBe('en')
    expect(toggleLanguage('en')).toBe('zh-Hans')
    expect(toggleLanguage(toggleLanguage('en'))).toBe('en')
  })

  it('缺键会打印显眼标记而不是静默回退', () => {
    // 用类型断言造一个不存在的键：真实代码里这种键编译期就过不去
    const missing = t('no.such.key' as DictKey, 'en')
    expect(missing).toBe('⟪no.such.key⟫')
  })

  it('关键外壳文案确实两语都有（抽查最常用的几条）', () => {
    for (const key of ['sql.run', 'sql.cancel', 'grid.prev', 'grid.next', 'write.commit'] as DictKey[]) {
      expect(t(key, 'zh-Hans')).not.toBe(t(key, 'en'))
    }
  })
})
