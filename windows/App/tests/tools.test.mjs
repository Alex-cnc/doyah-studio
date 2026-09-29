import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { RULES, countBareValues, collectDefinedVars, collectReferencedVars } from '../tools/token-ratchet.mjs'

const appDir = resolve(import.meta.dirname, '..')
const swiftSource = resolve(appDir, '../../Core/DesignTokens.swift')
const paletteSource = resolve(appDir, '../../Core/DesignTheme.swift')

function run(script, args) {
  return spawnSync(process.execPath, [resolve(appDir, `tools/${script}`), ...args], {
    cwd: appDir,
    encoding: 'utf8',
  })
}

describe('gen-tokens（令牌生成物 ⇄ Swift 源）', () => {
  it('真仓库：生成物与源一致（--check 通过）', () => {
    const result = run('gen-tokens.mjs', ['--check'])
    expect(result.stderr).toBe('')
    expect(result.status).toBe(0)
  })

  it('源少一条令牌 ⇒ 非零退出并说出期望条数（不静默少生成几条）', () => {
    const dir = mkdtempSync(resolve(tmpdir(), 'doyah-tokens-'))
    const source = readFileSync(swiftSource, 'utf8').replace('    public static let hair: CGFloat = 2\n', '')
    const fixture = resolve(dir, 'DesignTokens.swift')
    writeFileSync(fixture, source)
    const result = run('gen-tokens.mjs', ['--source', fixture, '--out', resolve(dir, 'out.css'), '--check'])
    expect(result.status).not.toBe(0)
    expect(result.stderr).toMatch(/spacing：期望 7 条，实际 6 条/)
  })

  it('别名被改成字面量 ⇒ 非零退出并点名 ALIASES（防「取值换了来源」）', () => {
    const dir = mkdtempSync(resolve(tmpdir(), 'doyah-tokens-'))
    const source = readFileSync(swiftSource, 'utf8').replace(
      'case .identifier: return TextTone.primary.color(in: theme)',
      'case .identifier: return ThemeColor(light: 0x000000, dark: 0xFFFFFF)',
    )
    const fixture = resolve(dir, 'DesignTokens.swift')
    writeFileSync(fixture, source)
    const result = run('gen-tokens.mjs', ['--source', fixture, '--out', resolve(dir, 'out.css'), '--check'])
    expect(result.status).not.toBe(0)
    expect(result.stderr).toMatch(/ALIASES|没登记/)
  })

  it('值表少一个字段 ⇒ 非零退出并说出主题与期望条数（主题轴也是形状的一部分）', () => {
    const dir = mkdtempSync(resolve(tmpdir(), 'doyah-tokens-'))
    const source = readFileSync(paletteSource, 'utf8').replace(
      '        panel: ThemeColor(light: 0xF4F7FB, dark: 0x15263A),\n',
      '',
    )
    const fixture = resolve(dir, 'DesignTheme.swift')
    writeFileSync(fixture, source)
    const result = run('gen-tokens.mjs', ['--palette-source', fixture, '--out', resolve(dir, 'out.css'), '--check'])
    expect(result.status).not.toBe(0)
    expect(result.stderr).toMatch(/techBlue.*期望 \d+ 个字段|缺字段 panel/)
  })

  it('生成是确定的：同源两次生成逐字节相同', () => {
    const dir = mkdtempSync(resolve(tmpdir(), 'doyah-tokens-'))
    const a = resolve(dir, 'a.css')
    const b = resolve(dir, 'b.css')
    expect(run('gen-tokens.mjs', ['--out', a]).status).toBe(0)
    expect(run('gen-tokens.mjs', ['--out', b]).status).toBe(0)
    expect(readFileSync(a).equals(readFileSync(b))).toBe(true)
  })
})

describe('token-ratchet（裸值棘轮）', () => {
  it('规则名与 mac 基线同名（六条，改名即两侧对不上）', () => {
    expect(RULES).toEqual(['bare-color', 'bare-font', 'bare-spacing', 'bare-radius', 'bare-textstyle', 'bare-foreground'])
  })

  it('裸色值 / 裸字号 / 非零间距与圆角会被计入', () => {
    const counts = countBareValues('.a { color: #ff0000; font-size: 13px; padding: 8px; border-radius: 6px; }')
    expect(counts['bare-color']).toBe(1)
    expect(counts['bare-font']).toBe(1)
    expect(counts['bare-spacing']).toBe(1)
    expect(counts['bare-radius']).toBe(1)
    expect(counts['bare-foreground']).toBe(1)
  })

  it('走令牌 / 零值 / 合法关键字都不计（否则棘轮第一天就没法维护）', () => {
    const counts = countBareValues(
      '.a { color: var(--ds-color-text-primary); padding: 0 var(--ds-spacing-s); border-radius: 0; font-size: var(--ds-font-body-size); color: inherit; font: inherit; }',
    )
    expect(counts).toEqual({
      'bare-color': 0,
      'bare-font': 0,
      'bare-spacing': 0,
      'bare-radius': 0,
      'bare-textstyle': 0,
      'bare-foreground': 0,
    })
  })

  it('引用面 / 定义面解析：能抓出「引用了没定义的变量」', () => {
    const defined = collectDefinedVars([':root { --ds-spacing-xs: 4px; --ds-color-text-primary: #1D1D1F; }'])
    const referenced = collectReferencedVars('.a { padding: var(--ds-spacing-xs); color: var(--ds-color-text-primry); }')
    expect([...referenced].filter((name) => !defined.has(name))).toEqual(['--ds-color-text-primry'])
  })

  it('真仓库：棘轮未升高且引用面没有悬空命名', () => {
    const result = run('token-ratchet.mjs', [])
    expect(result.status).toBe(0)
    expect(result.stdout).toMatch(/裸值棘轮未升高/)
  })

  it('生成物里真的定义了外壳用到的那些变量（拼法一处一处核）', () => {
    const css = readFileSync(resolve(appDir, 'src/theme/tokens.generated.css'), 'utf8')
    for (const name of [
      '--ds-spacing-xs',
      '--ds-metric-row-height',
      '--ds-metric-hairline',
      '--ds-color-surface-content',
      '--ds-color-text-bright',
      '--ds-color-accent-accentGlow', // 颜色变量沿用 Swift case 名的拼法（camelCase 保留，与旧生成物一致）
      '--ds-font-body-size',
      '--ds-color-hairline-light',
      '--ds-hairline-dark-alpha',
      '--ds-overlay-selection-dark-alpha',
    ]) {
      expect(css).toContain(`${name}:`)
    }
  })

  it('每个主题一个变量块（§9.2）：三态齐全，且 id 用 rawValue 而不是 Swift case 名', () => {
    const css = readFileSync(resolve(appDir, 'src/theme/tokens.generated.css'), 'utf8')
    for (const id of ['tech-blue', 'bean-green', 'rose-gold']) {
      expect(css).toContain(`:root[data-theme-scheme='${id}'] {`)
      expect(css).toContain(`:root[data-theme-scheme='${id}'][data-theme='dark'] {`)
      expect(css).toContain(`:root[data-theme-scheme='${id}']:not([data-theme='light']):not([data-theme='dark']) {`)
    }
    expect(css).not.toContain('data-theme-scheme=\'techBlue\'')
  })
})
