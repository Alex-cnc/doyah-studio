// 命令的**唯一登记表**（2.9）：清单 ↔ 分派器 ↔ 视图绑定 **三者对账**
//
// 三条纪律：
//   ① **只有这一份清单**：面板里能看到的命令、快捷键能触发的命令、以及"点菜单能做出来的命令"
//      都从这里来 —— 各写一份必然出现"面板里有、快捷键没有"这类静默分歧（用例把这条钉住）。
//   ② **每项都要能说清"在哪儿看得见"**：命令要么绑在某个视图上（`view`），要么是全局动作
//      （`global`）。**没有第三种** —— 说不清在哪儿的命令就是"藏起来的命令"，不该存在。
//   ③ **匹配与排序在领域层**（Rust 侧 `Db/src/palette.rs`，7 例单测）；这里只登记，不写匹配。

/** 命令的可见性归属（**没有第三种**）。 */
export type CommandScope =
  /** 绑在某个视图上：只有切到那个视图时才能执行 */
  | { kind: 'view'; view: 'workspace' | 'database' }
  /** 全局动作：任何视图下都能执行 */
  | { kind: 'global' }

export interface Command {
  /** 稳定标识（执行时用它分派；与快捷键、菜单对账时也用它） */
  id: string
  title: string
  /** 额外关键词（英文名、缩写之类）：参与匹配但不展示 */
  keywords: string[]
  group: string
  scope: CommandScope
  /** 快捷键提示（只用于展示；**键位不走这里绑定** —— 那要跟系统菜单对齐后再落） */
  shortcut?: string
}

/**
 * 全部命令。**新增命令只在这里加一行**。
 *
 * 顺序 = 面板空查询时的展示顺序（领域层保证空查询按原顺序给）。
 */
export const COMMANDS_LIST: readonly Command[] = [
  {
    id: 'workspace.openFolder',
    title: '打开工作区文件夹',
    keywords: ['open folder', 'workspace'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
  },
  {
    id: 'workspace.search',
    title: '在工作区里搜索',
    keywords: ['search', 'find', 'grep'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
    shortcut: 'Ctrl+Shift+F',
  },
  {
    id: 'workspace.newFile',
    title: '新建文件',
    keywords: ['new file', 'create'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
  },
  {
    id: 'workspace.newFolder',
    title: '新建文件夹',
    keywords: ['new folder', 'mkdir'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
  },
  {
    id: 'workspace.compareExternal',
    title: '比对盘上有没有被别处改过',
    keywords: ['external change', 'stale', 'reload'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
  },
  {
    id: 'workspace.togglePreview',
    title: '切换 Markdown 预览',
    keywords: ['preview', 'markdown'],
    group: '工作区',
    scope: { kind: 'view', view: 'workspace' },
  },
  {
    id: 'database.connect',
    title: '连接数据库',
    keywords: ['connect', 'postgres'],
    group: '数据库',
    scope: { kind: 'view', view: 'database' },
  },
  {
    id: 'database.runQuery',
    title: '执行 SQL',
    keywords: ['run', 'execute', 'query'],
    group: '数据库',
    scope: { kind: 'view', view: 'database' },
    shortcut: 'Ctrl+Enter',
  },
  {
    id: 'database.browseTable',
    title: '浏览表（生成查询）',
    keywords: ['browse', 'table'],
    group: '数据库',
    scope: { kind: 'view', view: 'database' },
  },
  {
    id: 'history.clear',
    title: '清空命令使用记录',
    keywords: ['clear history', 'usage', 'frecency'],
    group: '面板',
    scope: { kind: 'global' },
  },
  {
    id: 'appearance.followSystem',
    title: '外观跟随系统',
    keywords: ['appearance', 'system', 'theme'],
    group: '外观',
    scope: { kind: 'global' },
  },
  {
    id: 'appearance.alwaysDark',
    title: '外观总是深色',
    keywords: ['dark', 'theme'],
    group: '外观',
    scope: { kind: 'global' },
  },
  {
    id: 'appearance.alwaysLight',
    title: '外观总是浅色',
    keywords: ['light', 'theme'],
    group: '外观',
    scope: { kind: 'global' },
  },
]

/** 按 id 取命令（分派器用；找不到就是 `undefined`，**不编一个**）。 */
export function commandById(id: string): Command | undefined {
  return COMMANDS_LIST.find((command) => command.id === id)
}

/** 某个视图下**可执行**的命令（含全局动作）。 */
export function commandsFor(view: 'workspace' | 'database'): Command[] {
  return COMMANDS_LIST.filter(
    (command) => command.scope.kind === 'global' || command.scope.view === view,
  )
}

/**
 * 三者对账（**返回不一致的地方，空数组 = 对上了**）。
 *
 * 对账三件：① id 不重复；② 每条命令都说得清"在哪儿看得见"（`scope` 合法）；
 * ③ 视图绑定里出现的视图名都是已知视图（写错视图名 = 命令永远出不来）。
 */
export function auditCommands(knownViews: readonly string[] = ['workspace', 'database']): string[] {
  const problems: string[] = []
  const seen = new Set<string>()
  for (const command of COMMANDS_LIST) {
    if (seen.has(command.id)) {
      problems.push(`重复的命令 id：${command.id}`)
    }
    seen.add(command.id)
    if (!command.id.includes('.')) {
      problems.push(`命令 id 不像"分组.动作"：${command.id}`)
    }
    if (command.scope.kind === 'view' && !knownViews.includes(command.scope.view)) {
      problems.push(`命令 ${command.id} 绑到了未知视图：${command.scope.view}`)
    }
    if (command.scope.kind === 'view' && !command.id.startsWith(`${command.scope.view}.`)) {
      problems.push(`命令 ${command.id} 的 id 前缀与它绑的视图 ${command.scope.view} 不一致`)
    }
    if (command.scope.kind === 'global' && command.id.includes('.') && command.id.split('.')[0] === 'workspace') {
      problems.push(`命令 ${command.id} 看着像工作区命令，却登记成全局动作`)
    }
  }
  return problems
}
