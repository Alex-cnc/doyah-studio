// 连接呈现面（FR-CONN-14 / -15 / -16）的判据 —— 含**负例**。
//
// 判据分两半：
//   ① **行为面**：唯一函数在正 / 反用例下的结论（显示名三条边界、环境标签兜底、颜色优先级、折叠读回）；
//   ② **来源面**：这不是「测一个函数返回什么」就够的 —— 需求要的是**两处一致**，
//      只有函数对、调用处各自拼一次照样会不一致。所以这里还要**扫源码**：
//        · 显示名只许由 `connectionDisplayTitle` 拼（别处出现 `(username)` 的拼法 ⇒ 判红）；
//        · 侧边栏连接行与查询上下文栏必须都用**同一个** `ConnectionLabel`（只挂一处 ⇒ 判红）；
//        · 本片两个文件里**不许出现色值字面量**（颜色只走令牌 ⇒ 判红）。

import { describe, expect, it } from 'vitest'
// 源码原文用 Vite 的 `?raw` 取（不引 node 内置：外壳的 tsconfig 没有 @types/node，
// 而 `vite/client` 已经声明了 `*?raw` —— 判据文件也要过类型检查）。
import connectionDisplaySource from './connectionDisplay.ts?raw'
import connectionLabelSource from './ConnectionLabel.vue?raw'
import connectionDialogSource from './ConnectionDialog.vue?raw'
import databaseViewSource from '../views/DatabaseView.vue?raw'
import {
  CATEGORICAL_TONES,
  COLLAPSED_GROUPS_KEY,
  connectionDisplayTitle,
  connectionPresentation,
  environmentBadge,
  groupConnections,
  isCategoricalTone,
  isEnvironment,
  readCollapsedGroups,
  savedConnectionTitle,
  toggleCollapsedGroup,
  writeCollapsedGroups,
  type ConnectionAppearanceSource,
  type KeyValueStore,
} from './connectionDisplay'
import type { SavedConnection } from '../ipc'

const SOURCES: Record<string, string> = {
  'shell/connectionDisplay.ts': connectionDisplaySource,
  'shell/ConnectionLabel.vue': connectionLabelSource,
  'shell/ConnectionDialog.vue': connectionDialogSource,
  'views/DatabaseView.vue': databaseViewSource,
}

function source(relative: string): string {
  const text = SOURCES[relative]
  if (text === undefined) throw new Error(`未登记的源文件：${relative}`)
  return text
}

/** 造一条保存过的连接（只给判据用到的字段；其余给稳定的占位）。 */
function conn(patch: Partial<SavedConnection> = {}): SavedConnection {
  return {
    id: 'c1',
    name: '演示库',
    dbType: 'postgresql',
    host: 'localhost',
    port: 5432,
    database: 'demo',
    username: 'alice',
    sslMode: 'prefer',
    timeout: 5,
    schemaVersion: 1,
    isReadOnly: false,
    ...patch,
  }
}

/** 内存替身：`localStorage` 的最小面（测试不必真有 window）。 */
function memoryStore(): KeyValueStore {
  const map = new Map<string, string>()
  return {
    getItem: (key) => (map.has(key) ? (map.get(key) as string) : null),
    setItem: (key, value) => {
      map.set(key, value)
    },
  }
}

// ── FR-CONN-14 显示名 ─────────────────────────────────────────────────────────

describe('FR-CONN-14 显示名 =「名称 (登录用户名)」', () => {
  it('正例：名称 + 用户名 ⇒「名称 (用户名)」', () => {
    expect(connectionDisplayTitle('演示库', 'alice', '（未命名）')).toBe('演示库 (alice)')
  })

  it('负例边界：名称为空 ⇒ 占位 + 用户名（不出现空名）', () => {
    expect(connectionDisplayTitle('   ', 'alice', '（未命名）')).toBe('（未命名） (alice)')
  })

  it('负例边界：用户名为空 ⇒ 只显示名称、**不产生空括号**', () => {
    const title = connectionDisplayTitle('演示库', '  ', '（未命名）')
    expect(title).toBe('演示库')
    expect(title).not.toContain('(')
  })

  it('负例边界：名称与用户名都空 ⇒ 只有占位', () => {
    expect(connectionDisplayTitle('', '', '（未命名）')).toBe('（未命名）')
  })

  it('从保存的连接取显示名走同一个函数（不是第二套拼法）', () => {
    const c = conn()
    expect(savedConnectionTitle(c, '（未命名）')).toBe(
      connectionDisplayTitle(c.name, c.username, '（未命名）'),
    )
  })
})

// ── FR-CONN-16 环境标签 / 颜色 ───────────────────────────────────────────────

describe('FR-CONN-16 环境标签与颜色（生产 / 预发 / 测试，两处一致）', () => {
  it('逐标签一例：生产 = 危险色、预发 = 警告色、测试 / 开发 = 安全档', () => {
    expect(environmentBadge('production')?.tone).toBe('danger')
    expect(environmentBadge('staging')?.tone).toBe('warning')
    expect(environmentBadge('testing')?.tone).toBe('success')
    expect(environmentBadge('development')?.tone).toBe('success')
    for (const env of ['production', 'staging', 'testing', 'development'] as const) {
      expect(environmentBadge(env)?.labelKey).toBe(`db.env.${env}`)
      expect(environmentBadge(env)?.known).toBe(true)
    }
  })

  it('负例兜底：认不出的标签**原样显示**、走中性色，不许静默当没标', () => {
    const badge = environmentBadge('prod')
    expect(badge).not.toBeNull()
    expect(badge?.known).toBe(false)
    expect(badge?.labelRaw).toBe('prod')
    expect(badge?.labelKey).toBeNull()
    expect(badge?.tone).toBe('neutral')
  })

  it('负例边界：空串 / 全空白 / 缺失都算「没标」（不画徽标）', () => {
    expect(environmentBadge('')).toBeNull()
    expect(environmentBadge('   ')).toBeNull()
    expect(environmentBadge(null)).toBeNull()
    expect(environmentBadge(undefined)).toBeNull()
  })

  it('颜色优先级：环境标签 > 自选色（安全信息不能被自定义色盖掉）', () => {
    const p = connectionPresentation(conn({ environment: 'production', colorTag: 'teal' }), '（未命名）')
    expect(p.accent).toEqual({ kind: 'environment', tone: 'danger' })
  })

  it('没有环境标签时才轮到自选色（按名字取，不存色值）', () => {
    const p = connectionPresentation(conn({ environment: null, colorTag: 'magenta' }), '（未命名）')
    expect(p.accent).toEqual({ kind: 'categorical', tone: 'magenta' })
  })

  it('负例：认不出的自选色名 ⇒ 不画色条（不猜、不静默用别的色）', () => {
    const p = connectionPresentation(conn({ environment: null, colorTag: 'chartreuse' }), '（未命名）')
    expect(p.accent).toBeNull()
    expect(isCategoricalTone('chartreuse')).toBe(false)
    expect(CATEGORICAL_TONES.length).toBeGreaterThan(0)
  })

  it('负例：认不出的环境标签也不冒充安全色（不画环境色条）', () => {
    const p = connectionPresentation(conn({ environment: 'prod', colorTag: 'teal' }), '（未命名）')
    expect(p.accent).toBeNull()
    expect(p.badge?.known).toBe(false)
  })

  it('生产 / 预发建议只读（与 macOS 侧 recommendsReadOnly 同口径）', () => {
    expect(connectionPresentation(conn({ environment: 'production' }), '（未命名）').recommendsReadOnly).toBe(true)
    expect(connectionPresentation(conn({ environment: 'staging' }), '（未命名）').recommendsReadOnly).toBe(true)
    expect(connectionPresentation(conn({ environment: 'testing' }), '（未命名）').recommendsReadOnly).toBe(false)
    expect(connectionPresentation(conn(), '（未命名）').recommendsReadOnly).toBe(false)
  })

  it('isEnvironment 只认那四个词（配置里存的字面量与 macOS 侧 rawValue 一致）', () => {
    expect(isEnvironment('production')).toBe(true)
    expect(isEnvironment('Production')).toBe(false)
    expect(isEnvironment('prod')).toBe(false)
  })
})

// ── FR-CONN-15 分组与折叠持久化 ──────────────────────────────────────────────

describe('FR-CONN-15 分组折叠状态可持久', () => {
  it('分组：未分组永远排最后，命名组按名字排，组内保持传入顺序', () => {
    const sections = groupConnections([
      conn({ id: 'a', name: 'b3', group: '测试' }),
      conn({ id: 'b', name: 'none1', group: null }),
      conn({ id: 'c', name: 'a1', group: '生产' }),
      conn({ id: 'd', name: 'b1', group: '测试' }),
    ])
    expect(sections[sections.length - 1].group).toBeNull()
    const named = sections.slice(0, -1).map((s) => s.group)
    expect([...named].sort()).toEqual(['生产', '测试'].sort())
    expect(named).toEqual(['生产', '测试'].sort((a, b) => (a as string).localeCompare(b as string)))
    const byGroup = new Map(sections.map((s) => [s.group, s]))
    expect(byGroup.get('测试')?.items.map((c) => c.name)).toEqual(['b3', 'b1'])
    expect(byGroup.get('生产')?.items.map((c) => c.name)).toEqual(['a1'])
    expect(byGroup.get(null)?.items.map((c) => c.name)).toEqual(['none1'])
  })

  it('空白组名归一为未分组（沿用领域层口径）', () => {
    const sections = groupConnections([conn({ group: '   ' }), conn({ id: 'c2', group: '生产' })])
    expect(sections.map((s) => s.group)).toEqual(['生产', null])
  })

  it('折叠 → 展开：纯函数不改传入的集合', () => {
    const before = new Set<string>(['生产'])
    const collapsed = toggleCollapsedGroup(before, '测试')
    expect(new Set(collapsed)).toEqual(new Set(['生产', '测试']))
    expect(new Set(before)).toEqual(new Set(['生产']))
    expect(new Set(toggleCollapsedGroup(collapsed, '测试'))).toEqual(new Set(['生产']))
  })

  it('冷启动读回一例：折叠过的那段还在，没折叠的不在', () => {
    const store = memoryStore()
    writeCollapsedGroups(store, new Set(['生产']))
    // 模拟重启：换一块「新组件状态」，从同一份存储读回
    const restored = readCollapsedGroups(store)
    expect([...restored]).toEqual(['生产'])
    expect(restored.has('测试')).toBe(false)
    expect(JSON.parse(store.getItem(COLLAPSED_GROUPS_KEY) as string)).toEqual(['生产'])
  })

  it('冷启动读回：展开过的分组不在集合里（全展开是默认）', () => {
    const store = memoryStore()
    writeCollapsedGroups(store, [])
    expect([...readCollapsedGroups(store)]).toEqual([])
  })

  it('负例：坏值 / 非数组 / 混入非字符串 ⇒ 当作没折叠（不崩，也不静默全折叠）', () => {
    const broken = { getItem: () => '{这不是 JSON', setItem: () => {} }
    expect([...readCollapsedGroups(broken)]).toEqual([])

    const notArray = { getItem: () => '{"生产":true}', setItem: () => {} }
    expect([...readCollapsedGroups(notArray)]).toEqual([])

    const mixed = { getItem: () => JSON.stringify(['生产', 7, '', '  ', '测试']), setItem: () => {} }
    expect([...readCollapsedGroups(mixed)].sort()).toEqual(['测试', '生产'])
  })

  it('负例：拿不到存储（访问就抛）⇒ 当作没有存储，不把折叠当成持久成功', () => {
    const hostile = {
      getItem: () => {
        throw new Error('storage disabled')
      },
      setItem: () => {
        throw new Error('storage disabled')
      },
    }
    expect([...readCollapsedGroups(hostile)]).toEqual([])
    expect(() => writeCollapsedGroups(hostile, new Set(['生产']))).not.toThrow()
    expect([...readCollapsedGroups(null)]).toEqual([])
  })
})

// ── 来源面：两处一致 / 颜色只走令牌（负例）────────────────────────────────────

/** 「显示名被第二处各拼一次」的识别式：括号里直接塞 `username`（模板串或插值都算）。 */
const AD_HOC_TITLE_PATTERNS: readonly RegExp[] = [
  /\((?:\$\{|\{\{)[^)}\n]*\busername\b/,
  /['"`]\s*\(\s*['"`]\s*\+[^\n]*\busername\b/,
]

function adHocTitleHits(text: string): number {
  return AD_HOC_TITLE_PATTERNS.reduce(
    (total, pattern) => total + (text.match(new RegExp(pattern.source, 'g'))?.length ?? 0),
    0,
  )
}

describe('来源面：显示名 / 环境标签两处同源', () => {
  it('负例：别处各拼一次「名称 (用户名)」⇒ 判据抓得到（先证明判据不是空的）', () => {
    expect(adHocTitleHits('<span>{{ c.name }} ({{ c.username }})</span>')).toBe(1)
    expect(adHocTitleHits('`${c.name} (${c.username})`')).toBe(1)
    expect(adHocTitleHits("c.name + ' (' + c.username")).toBe(1)
    // 反例：唯一函数那条路不算「各拼一次」
    expect(adHocTitleHits('`${title} (${trimmedUser})`')).toBe(0)
  })

  it('真仓库：显示名只在 connectionDisplay.ts 里拼，视图里没有第二处', () => {
    for (const file of ['views/DatabaseView.vue', 'shell/ConnectionDialog.vue', 'shell/ConnectionLabel.vue']) {
      expect({ file, hits: adHocTitleHits(source(file)) }).toEqual({ file, hits: 0 })
    }
  })

  it('真仓库：连接列表行与查询上下文栏用的是**同一个** ConnectionLabel（列表搬进弹层后跨两件数）', () => {
    // 连接面已经搬进弹层（S-7a）：列表行在 `shell/ConnectionDialog.vue`、查询上下文栏在
    // `views/DatabaseView.vue` —— 两处**都**必须用同一个共用件（判据的强度不变，只是数的面多了一件）。
    const surfaces = ['views/DatabaseView.vue', 'shell/ConnectionDialog.vue']
    const hits = surfaces.reduce(
      (total, file) => total + (source(file).match(/<ConnectionLabel\b/g)?.length ?? 0),
      0,
    )
    expect(hits).toBeGreaterThanOrEqual(2)
    // 而且不自己画环境徽标（徽标只在共用件里）
    for (const file of surfaces) {
      expect({ file, badge: /conn__badge/.test(source(file)) }).toEqual({ file, badge: false })
    }
  })

  it('负例：本片两个文件里不许出现色值字面量（颜色只走 --ds-* 令牌）', () => {
    for (const file of ['shell/connectionDisplay.ts', 'shell/ConnectionLabel.vue']) {
      const text = source(file)
      expect({ file, hex: text.match(/#[0-9A-Fa-f]{3,8}\b/g) ?? [] }).toEqual({ file, hex: [] })
      expect({ file, rgb: text.match(/\brgba?\(/g) ?? [] }).toEqual({ file, rgb: [] })
    }
  })

  it('负例：呈现面只给语义角色、不给色值（角色 → 令牌的映射在样式里）', () => {
    const p = connectionPresentation(conn({ environment: 'production' }), '（未命名）')
    const serialized = JSON.stringify(p)
    expect(serialized).not.toMatch(/#[0-9A-Fa-f]{3,8}/)
    expect(p.accent).toEqual({ kind: 'environment', tone: 'danger' })
  })
})

// ── 类型面：判据用的字面量形状（防止有人把 SavedConnection 的形状改歪）──────────

describe('呈现面输入形状', () => {
  it('ConnectionAppearanceSource 收得住 SavedConnection（多余字段不参与判定）', () => {
    const c: ConnectionAppearanceSource = conn({ environment: 'staging', colorTag: 'blue' })
    expect(connectionDisplayTitle(c.name, c.username, 'x')).toBe('演示库 (alice)')
  })
})
