// 界面语言表（1.8 双语的**单一出处**）
//
// 为什么要有它、以及它现在覆盖到哪儿（**如实写清楚，别当成"双语做完了"**）：
// ① 语言轴与标题栏已有的 `activityBar.UiLanguage` 是**同一个**（`zh-Hans` / `en`），
//    这里不另造第二套语言标识；
// ② 表的形状是 `key → { 'zh-Hans': ..., en: ... }`，**缺一种语言就是编译不过**
//    （不是运行时回退）—— 回退会让"漏翻"静默混过去，而双语最容易烂在漏翻上；
// ③ **当前只覆盖界面外壳**（工具栏、面板标题、字段标签、按钮、表格表头）；
//    **未覆盖**：正文说明、服务端错误提示、领域层返回的 hint 文案 ——
//    那些散在命令层与组件里，要全量双语得逐条过一遍（本段**未做**，已登记进版本计划）。
// ④ 不引 i18n 库：本侧要求零第三方依赖，而且这里的需要就是"查表 + 插值"。

import type { UiLanguage } from '../shell/activityBar'

export type { UiLanguage }

/** 一句话的两种语言（缺一种就编译不过）。 */
export interface Entry {
  'zh-Hans': string
  en: string
}

/** 语言表：key 用点分层级，便于按区域找。 */
export const DICT = {
  // 数据库视图（连接表单 / 工具条 / 启动 SQL / 左栏）
  'db.connectedAs': { 'zh-Hans': '已连：', en: 'connected: ' },
  'db.none': { 'zh-Hans': '无', en: 'none' },
  'db.objects.summary': {
    'zh-Hans': '对象（{loaded} 个已加载 · {schemas} 个 schema）',
    en: 'Objects ({loaded} loaded · {schemas} schemas)',
  },
  'db.connections.empty': {
    'zh-Hans': '还没有保存过连接。填好上面的表单按「保存到连接列表」，口令（若勾了记住）进系统凭据管理器。',
    en: 'No saved connections yet. Fill the form above and press "Save to connection list"; the password (if you tick remember) goes to Windows Credential Manager.',
  },
  'db.host': { 'zh-Hans': '主机', en: 'Host' },
  'db.port': { 'zh-Hans': '端口', en: 'Port' },
  'db.database': { 'zh-Hans': '库', en: 'Database' },
  'db.user': { 'zh-Hans': '用户', en: 'User' },
  'db.password': { 'zh-Hans': '口令', en: 'Password' },
  'db.password.placeholder': { 'zh-Hans': '不落盘、不显示', en: 'Never stored or shown' },
  'db.remember.tip': {
    'zh-Hans': '口令进 Windows 凭据管理器（本用户可见），配置文件里没有口令',
    en: 'The password goes to Windows Credential Manager (visible to this user); it is not in the config file',
  },
  'db.remember': { 'zh-Hans': '记住口令', en: 'Remember password' },
  'db.connect': { 'zh-Hans': '连接', en: 'Connect' },
  'db.reconnect': { 'zh-Hans': '重新连接', en: 'Reconnect' },
  'db.disconnect': { 'zh-Hans': '断开', en: 'Disconnect' },
  'db.loadObjects': { 'zh-Hans': '列出对象', en: 'List objects' },
  'db.saveToConnections': { 'zh-Hans': '保存到连接列表', en: 'Save to connection list' },
  'db.connected': { 'zh-Hans': '已连接 {database}（用户 {user}）', en: 'Connected to {database} (user {user})' },
  'db.startup.title': { 'zh-Hans': '启动 SQL（连接后自动执行，逐条发、逐条报错）', en: 'Startup SQL (runs on connect, statement by statement)' },
  'db.startup.last': { 'zh-Hans': '上次：{ok} 成 / {fail} 败', en: 'Last time: {ok} ok / {fail} failed' },
  'db.startup.aria': { 'zh-Hans': '启动 SQL', en: 'Startup SQL' },
  'db.startup.placeholder': {
    'zh-Hans': "例如 SET search_path = app, public;  或  SET statement_timeout = '5s'",
    en: "e.g. SET search_path = app, public;  or  SET statement_timeout = '5s'",
  },
  'db.connections': { 'zh-Hans': '连接列表', en: 'Connections' },
  'db.tree': { 'zh-Hans': '数据库对象', en: 'Database objects' },
  'db.view.hierarchy': { 'zh-Hans': '层级视图', en: 'Hierarchy' },
  'db.view.byKind': { 'zh-Hans': '按类型分组', en: 'By type' },
  'db.search.placeholder': { 'zh-Hans': '搜索对象（名字或 schema）', en: 'Search objects (name or schema)' },
  'db.switchDatabase': {
    'zh-Hans': '切到这个库（重连一次）；选项来自已保存连接里同主机同用户的那些库',
    en: 'Switch to this database (reconnects); options come from saved connections with the same host and user',
  },
  'db.clear': { 'zh-Hans': '清空', en: 'Clear' },
  'db.clear.tip': { 'zh-Hans': '清空编辑器（会先问一句）', en: 'Clear the editor (asks first)' },

  // 外观两轴（配色 / 深浅）——**标签改成语言 key**（原来把中文写死在常量里，
  // 切英文时下拉里仍是中文；扫描器的第三面就是为这类"数据型文案"补的）
  'appearance.mode': { 'zh-Hans': '外观', en: 'Appearance' },
  'appearance.scheme': { 'zh-Hans': '配色', en: 'Color scheme' },
  'appearance.mode.followSystem': { 'zh-Hans': '跟随系统', en: 'Follow system' },
  'appearance.mode.alwaysDark': { 'zh-Hans': '总是深色', en: 'Always dark' },
  'appearance.mode.alwaysLight': { 'zh-Hans': '总是浅色', en: 'Always light' },
  'appearance.scheme.techBlue': { 'zh-Hans': '科技蓝', en: 'Tech blue' },
  'appearance.scheme.beanGreen': { 'zh-Hans': '豆芽绿', en: 'Bean green' },
  'appearance.scheme.roseGold': { 'zh-Hans': '玫瑰金', en: 'Rose gold' },
  'appearance.scheme.stardust': { 'zh-Hans': '星空紫', en: 'Stardust' },
  'appearance.nebula.tip': {
    'zh-Hans': '只在「星空紫 + 深色」时看得出来',
    en: 'Only visible with Stardust + dark',
  },
  'appearance.nebula': { 'zh-Hans': '星云皮肤', en: 'Nebula skin' },
  'appearance.warning': { 'zh-Hans': '外观偏好读不出来（按缺省走）', en: 'Appearance preference unreadable (using defaults)' },
  'shell.commandHint': { 'zh-Hans': 'Ctrl+K 打开命令面板', en: 'Ctrl+K opens the command palette' },
  'shell.panel.expand': { 'zh-Hans': '展开底部面板', en: 'Expand bottom panel' },
  'shell.panel.toggle': { 'zh-Hans': '面板', en: 'Panel' },

  // 底部面板（2.x 界面改版新增；四格 + 空态与未开工说明）
  'panel.problems': { 'zh-Hans': '问题', en: 'Problems' },
  'panel.output': { 'zh-Hans': '输出', en: 'Output' },
  'panel.terminal': { 'zh-Hans': '终端', en: 'Terminal' },
  'panel.debug': { 'zh-Hans': '调试控制台', en: 'Debug console' },
  'panel.notReady': { 'zh-Hans': '{name}（本版未开工）', en: '{name} (not implemented in this version)' },
  'panel.aria': { 'zh-Hans': '底部面板', en: 'Bottom panel' },
  'panel.collapse': { 'zh-Hans': '收起底部面板', en: 'Collapse bottom panel' },
  'panel.terminal.note': {
    'zh-Hans': '内置终端本版未开工（真起 shell 那一半还没打通）。这里不会出现假的提示符。',
    en: 'The built-in terminal is not implemented in this version (the real shell half is not done). No fake prompt appears here.',
  },
  'panel.debug.note': {
    'zh-Hans': '本版没有调试器，这一格暂不开放。',
    en: 'This version has no debugger; this tab is not open yet.',
  },
  'panel.problems.empty': {
    'zh-Hans': '没有问题。连库 / 执行 / 检索出的错都会汇总到这里。',
    en: 'No problems. Errors from connecting, running queries and searching are collected here.',
  },
  'panel.output.empty': {
    'zh-Hans': '还没有输出。连库、执行查询、检索、格式化的回执都会打到这里。',
    en: 'No output yet. Receipts from connecting, running queries, searching and formatting appear here.',
  },
  'panel.expand': { 'zh-Hans': '展开底部面板', en: 'Expand bottom panel' },
  'panel.toggle': { 'zh-Hans': '面板', en: 'Panel' },

  // 结果面工具栏
  'grid.filter.placeholder': { 'zh-Hans': '筛选（当前结果内，不分大小写）', en: 'Filter (current result, case-insensitive)' },
  'grid.rows.summary': { 'zh-Hans': '命中 {hit} / 共 {total} 行', en: '{hit} of {total} rows matched' },
  'grid.page.summary': { 'zh-Hans': '第 {page} / {pages} 页（本页 {rows} 行）', en: 'page {page} / {pages} ({rows} rows)' },
  'grid.prev': { 'zh-Hans': '上一页', en: 'Previous' },
  'grid.next': { 'zh-Hans': '下一页', en: 'Next' },
  'grid.pageSize': { 'zh-Hans': '每页', en: 'Per page' },
  'grid.rows': { 'zh-Hans': '行', en: 'rows' },
  'grid.freeze': { 'zh-Hans': '冻结前', en: 'Freeze first' },
  'grid.columns': { 'zh-Hans': '列', en: 'columns' },
  'grid.copyAs': { 'zh-Hans': '复制为', en: 'Copy as' },
  'grid.copy': { 'zh-Hans': '复制', en: 'Copy' },
  'grid.io': { 'zh-Hans': '导入导出…', en: 'Import / export…' },
  'grid.admin': { 'zh-Hans': '管理面板…', en: 'Admin panel…' },
  'grid.structure': { 'zh-Hans': '表结构设计…', en: 'Table designer…' },
  'grid.rowDetail': { 'zh-Hans': '点这一行看详情', en: 'Click a row for details' },

  // SQL 编辑面
  'sql.run': { 'zh-Hans': '执行', en: 'Run' },
  'sql.cancel': { 'zh-Hans': '取消', en: 'Cancel' },
  'sql.planOnly': { 'zh-Hans': '只看计划', en: 'Plan only' },
  'sql.runWithPlan': { 'zh-Hans': '执行并出计划', en: 'Run with plan' },
  'sql.affected': { 'zh-Hans': '影响 {n} 行（无结果集）', en: 'affected {n} rows (no result set)' },
  'sql.rows': { 'zh-Hans': '{n} 行', en: '{n} rows' },
  'sql.truncated': { 'zh-Hans': '（服务端回来 {returned} 行，已截断，只显示前 {shown} 行）', en: '(server returned {returned}; truncated to {shown})' },

  // 写回
  'write.preview': { 'zh-Hans': '生成 SQL（先看清）', en: 'Generate SQL (preview first)' },
  'write.dryRun': { 'zh-Hans': '试跑（跑完回滚）', en: 'Dry run (rollback)' },
  'write.commit': { 'zh-Hans': '提交（一次事务）', en: 'Commit (one transaction)' },
  'write.discard': { 'zh-Hans': '放弃改动', en: 'Discard changes' },
  'write.readOnly': {
    'zh-Hans': '这条连接标了只读：可以预览将执行的语句，但不会发送',
    en: 'This connection is read-only: statements can be previewed but are never sent',
  },
  'write.noPrimaryKey': {
    'zh-Hans': '这张表没有主键：定位不到是哪一行，所以不给单元格编辑',
    en: 'This table has no primary key: a row cannot be located, so cell editing is disabled',
  },
  'write.edited': { 'zh-Hans': '已改 {n} 处', en: '{n} edited' },

  // 表设计器
  'designer.title': { 'zh-Hans': '表结构', en: 'Table structure' },
  'designer.column': { 'zh-Hans': '列名', en: 'Column' },
  'designer.type': { 'zh-Hans': '类型（原文）', en: 'Type (verbatim)' },
  'designer.nullable': { 'zh-Hans': '可空', en: 'Nullable' },
  'designer.default': { 'zh-Hans': '默认值', en: 'Default' },
  'designer.action': { 'zh-Hans': '操作', en: 'Action' },
  'designer.addColumn': { 'zh-Hans': '加一列', en: 'Add column' },
  'designer.dropColumn': { 'zh-Hans': '删除这列', en: 'Drop column' },
  'designer.generate': { 'zh-Hans': '生成变更集', en: 'Generate changeset' },
  'designer.applySafe': { 'zh-Hans': '执行非破坏性（{n} 句）', en: 'Apply non-destructive ({n})' },
  'designer.copyAll': { 'zh-Hans': '复制全部语句', en: 'Copy all statements' },
  'designer.destructiveNote': {
    'zh-Hans': '其中 {n} 句是破坏性的：只生成、不自动执行',
    en: '{n} of them are destructive: generated only, never run automatically',
  },
  'designer.indexes': { 'zh-Hans': '索引与约束', en: 'Indexes and constraints' },
  'designer.collapse': { 'zh-Hans': '收起', en: 'Collapse' },

  // 导入导出
  'io.exportTitle': { 'zh-Hans': '导出当前 SQL 的结果', en: 'Export the current result' },
  'io.format': { 'zh-Hans': '格式', en: 'Format' },
  'io.targetPath': { 'zh-Hans': '目标文件路径', en: 'Target file path' },
  'io.exportButton': { 'zh-Hans': '导出到文件', en: 'Export to file' },
  'io.importTitle': { 'zh-Hans': '从文件导入（空白字段按 NULL 写入）', en: 'Import from file (blank fields become NULL)' },
  'io.importPath': { 'zh-Hans': '文件路径', en: 'File path' },
  'io.targetTable': { 'zh-Hans': '目标表名', en: 'Target table' },
  'io.hasHeader': { 'zh-Hans': '首行是表头', en: 'First row is a header' },
  'io.preview': { 'zh-Hans': '预览（不写库）', en: 'Preview (no writes)' },
  'io.importButton': { 'zh-Hans': '导入（一个事务）', en: 'Import (one transaction)' },

  // 管理面
  'admin.title': { 'zh-Hans': '库与会话', en: 'Databases and sessions' },
  'admin.refresh': { 'zh-Hans': '刷新', en: 'Refresh' },
  'admin.maintenance': { 'zh-Hans': '生成维护命令', en: 'Generate maintenance commands' },
  'admin.copyOnly': { 'zh-Hans': '复制命令（唯一出口）', en: 'Copy commands (the only exit)' },
  'admin.databases': { 'zh-Hans': '库列表', en: 'Databases' },
  'admin.sessions': { 'zh-Hans': '会话与锁（等锁的排最前）', en: 'Sessions and locks (waiting first)' },
  'admin.waiting': { 'zh-Hans': '在等锁', en: 'waiting on lock' },
  'admin.tableStats': { 'zh-Hans': '表统计（行数是估算）', en: 'Table statistics (row counts are estimates)' },
  'admin.genCancel': { 'zh-Hans': '生成 cancel', en: 'Generate cancel' },
  'admin.genTerminate': { 'zh-Hans': '生成 terminate', en: 'Generate terminate' },
} as const satisfies Record<string, Entry>

export type DictKey = keyof typeof DICT

/**
 * 查表并插值：`{name}` 占位符用 `vars` 里的值替换，**缺键立刻看得见**（打印 `⟪key⟫`）。
 *
 * 为什么缺键要显眼：语言表漏一条时，界面若静默回退到中文，英文用户会以为"这处就是中文"，
 * 而漏翻永远不会被修。显眼标记能让人一眼看到并补上。
 */
export function t(
  key: DictKey,
  language: UiLanguage,
  vars?: Record<string, string | number>,
): string {
  const entry: Entry | undefined = DICT[key]
  if (!entry) return `⟪${key}⟫`
  let text: string = entry[language]
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.split(`{${name}}`).join(String(value))
    }
  }
  return text
}

/** 语言切换：`zh-Hans` ↔ `en`（对称，点一下换一个）。 */
export function toggleLanguage(current: UiLanguage): UiLanguage {
  return current === 'zh-Hans' ? 'en' : 'zh-Hans'
}
