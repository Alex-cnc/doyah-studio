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
  // 插件面（契约 §3.52 / 本侧 §8.5.8）
  'plugin.notes.title': { 'zh-Hans': '笔记', en: 'Notes' },
  'plugin.retro.title': { 'zh-Hans': '回放', en: 'Retro' },
  'plugin.notImplemented': {
    'zh-Hans': '本插件尚未实现（本版只落插件骨架）。功能本体将取自产品能力规划说明书。',
    en: 'This plugin is not implemented yet (this version only ships the plugin skeleton). Its features will come from the product capability plan.',
  },
  'plugin.missingEntry': { 'zh-Hans': '插件入口未登记：{entry}', en: 'Plugin entry not registered: {entry}' },

  // IPC 浏览器旁路提示（不是产品路径，但**也要双语**：切英文时不该留中文）
  'ipc.bypass.db': { 'zh-Hans': '浏览器旁路没有真库', en: 'The browser fallback has no real database' },
  'ipc.bypass.workspace': { 'zh-Hans': '浏览器旁路没有工作区', en: 'The browser fallback has no workspace' },
  'ipc.bypass.sqlFormat': {
    'zh-Hans': '浏览器旁路里没有格式化器（真格式化由外壳按「外部工具优先 → 内置兜底」判定），文本一个字都没动。',
    en: 'The browser fallback has no formatter (the shell decides external-first, then builtin), so the text is untouched.',
  },
  'ipc.bypass.terminal': { 'zh-Hans': '浏览器旁路没有真终端', en: 'The browser fallback has no real terminal' },
  'ipc.bypass.hint': {
    'zh-Hans': '请在 Tauri 外壳里{action}（npm run tauri dev）。',
    en: 'Please {action} in the Tauri shell (npm run tauri dev).',
  },
  'ipc.action.connect': { 'zh-Hans': '连库', en: 'connect' },
  'ipc.action.run': { 'zh-Hans': '执行', en: 'run queries' },
  'ipc.action.selfCheck': { 'zh-Hans': '自检', en: 'run self-checks' },
  'ipc.action.generate': { 'zh-Hans': '生成', en: 'generate' },
  'ipc.action.preview': { 'zh-Hans': '预览', en: 'preview' },
  'ipc.action.writeBack': { 'zh-Hans': '写回', en: 'write back' },
  'ipc.action.designer': { 'zh-Hans': '打开表设计器', en: 'open the table designer' },
  'ipc.action.export': { 'zh-Hans': '导出', en: 'export' },
  'ipc.action.previewImport': { 'zh-Hans': '预览导入', en: 'preview an import' },
  'ipc.action.import': { 'zh-Hans': '导入', en: 'import' },
  'ipc.action.openWorkspace': { 'zh-Hans': '打开工作区', en: 'open a workspace' },
  'ipc.action.terminal': { 'zh-Hans': '起终端会话', en: 'start a terminal session' },
  'ipc.action.schemaSnapshot': { 'zh-Hans': '抓结构快照', en: 'take a structure snapshot' },
  'ipc.action.schemaDiff': { 'zh-Hans': '对比结构', en: 'compare schemas' },
  'ipc.confirm.dbName': {
    'zh-Hans': '库名不一致，没有删除（这是防误删的闸）',
    en: 'Database name does not match; nothing was dropped (this is the guard against accidents)',
  },

  // 命令面板：命令标题（**面板显示与搜索词都从这里取**，不再各写一份）
  'cmd.workspace.openFolder': { 'zh-Hans': '打开工作区文件夹', en: 'Open workspace folder' },
  'cmd.workspace.search': { 'zh-Hans': '在工作区里搜索', en: 'Search in workspace' },
  'cmd.workspace.newFile': { 'zh-Hans': '新建文件', en: 'New file' },
  'cmd.workspace.newFolder': { 'zh-Hans': '新建文件夹', en: 'New folder' },
  'cmd.workspace.save': { 'zh-Hans': '保存当前文件', en: 'Save current file' },
  'cmd.workspace.format': { 'zh-Hans': '格式化当前文件', en: 'Format current file' },
  'cmd.workspace.reveal': { 'zh-Hans': '在资源管理器中显示', en: 'Reveal in File Explorer' },
  'cmd.workspace.closeTab': { 'zh-Hans': '关闭当前页签', en: 'Close current tab' },
  'cmd.database.connect': { 'zh-Hans': '连接数据库', en: 'Connect to database' },
  'cmd.database.newConnection': { 'zh-Hans': '新建连接', en: 'New connection' },
  'cmd.database.editConnection': { 'zh-Hans': '编辑连接', en: 'Edit connection' },
  'cmd.database.runQuery': { 'zh-Hans': '执行查询', en: 'Run query' },
  'cmd.database.explain': { 'zh-Hans': '查看执行计划', en: 'Show query plan' },
  'cmd.database.backup': { 'zh-Hans': '备份数据库…', en: 'Back up database…' },
  'cmd.database.export': { 'zh-Hans': '导出结果', en: 'Export results' },
  'cmd.database.import': { 'zh-Hans': '导入数据', en: 'Import data' },
  'cmd.appearance.followSystem': { 'zh-Hans': '外观跟随系统', en: 'Follow system appearance' },
  'cmd.appearance.dark': { 'zh-Hans': '总是深色', en: 'Always dark' },
  'cmd.appearance.light': { 'zh-Hans': '总是浅色', en: 'Always light' },
  'cmd.history.clear': { 'zh-Hans': '清空命令使用记录', en: 'Clear command usage history' },
  'cmd.workspace.compareExternal': { 'zh-Hans': '对比盘上的改动', en: 'Compare with disk' },
  'cmd.workspace.togglePreview': { 'zh-Hans': '切换预览 / 源码', en: 'Toggle preview / source' },
  'cmd.database.browseTable': { 'zh-Hans': '浏览表数据', en: 'Browse table data' },
  'cmd.appearance.alwaysDark': { 'zh-Hans': '总是深色', en: 'Always dark' },
  'cmd.appearance.alwaysLight': { 'zh-Hans': '总是浅色', en: 'Always light' },
  // 面板分组名
  'cmdGroup.workspace': { 'zh-Hans': '工作区', en: 'Workspace' },
  'cmdGroup.database': { 'zh-Hans': '数据库', en: 'Database' },
  'cmdGroup.appearance': { 'zh-Hans': '外观', en: 'Appearance' },
  'cmd.agent.settings': { 'zh-Hans': '智能体设置…', en: 'Agent settings…' },
  'cmd.agent.audit': { 'zh-Hans': '智能体审计记录…', en: 'Agent audit log…' },
  'cmdGroup.agent': { 'zh-Hans': '智能体', en: 'Agent' },
  'cmdGroup.history': { 'zh-Hans': '面板', en: 'Palette' },

  // 侧栏（活动栏的窄条）
  'sidebar.aria': { 'zh-Hans': '视图', en: 'Views' },
  'sidebar.notReady': { 'zh-Hans': '{name}（未开工）', en: '{name} (not implemented)' },

  // 状态栏
  'status.rows': { 'zh-Hans': '结果集 {rows} 行 × {cols} 列', en: 'Result: {rows} rows × {cols} columns' },
  'status.window': { 'zh-Hans': '本片已取 {loaded} 行 / 逻辑 {total} 行', en: 'Loaded {loaded} of {total} rows' },
  'status.theme.aria': { 'zh-Hans': '主题（配色方案）', en: 'Theme (color scheme)' },
  'status.theme.draft': { 'zh-Hans': '（推导草案）', en: '(derived draft)' },
  'status.system': { 'zh-Hans': '跟随系统', en: 'Follow system' },
  'status.light': { 'zh-Hans': '浅色', en: 'Light' },
  'status.dark': { 'zh-Hans': '深色', en: 'Dark' },
  // 命令面板
  'palette.recent': { 'zh-Hans': '最近使用', en: 'Recently used' },
  'palette.aria': { 'zh-Hans': '命令面板', en: 'Command palette' },
  'palette.placeholder': {
    'zh-Hans': '输入命令名或缩写（例如 fmt / 格式 / 保存）',
    en: 'Type a command name or acronym (e.g. fmt / format / save)',
  },
  'palette.search.aria': { 'zh-Hans': '命令搜索', en: 'Command search' },
  'palette.empty': { 'zh-Hans': '没有匹配的命令', en: 'No matching commands' },
  // 标题栏搜索
  'titlebar.search.placeholder': { 'zh-Hans': '搜索（当前：{title}）', en: 'Search (now: {title})' },
  'titlebar.search.aria': { 'zh-Hans': '工作区搜索', en: 'Global search' },
  'titlebar.search.hidden': {
    'zh-Hans': '窗口太窄：搜索栏让位给标题（用快捷键搜索）',
    en: 'Window too narrow: the search field yields to the title (use the shortcut)',
  },
  'titlebar.search.hiddenShort': { 'zh-Hans': '搜索栏让位', en: 'search hidden' },

  // 工作区 Home 页（三栏）
  'home.welcome': { 'zh-Hans': '欢迎回来', en: 'Welcome back' },
  'home.lead': {
    'zh-Hans': '左边选工作区，点文件就能在编辑器里打开；配色与补全按文件类型自动匹配。',
    en: 'Pick a workspace on the left and click a file to open it in the editor; colors and completion follow the file type.',
  },
  'home.version': { 'zh-Hans': '版本 {version}', en: 'Version {version}' },
  'home.privacy': {
    'zh-Hans': '© 2026 DoyahStudio · 本机优先：数据与文件不出这台机器',
    en: '© 2026 DoyahStudio · local-first: your data and files stay on this machine',
  },
  'home.openFile': { 'zh-Hans': '打开文件…', en: 'Open file…' },
  'home.recentFiles': { 'zh-Hans': '最近打开的文件', en: 'Recent files' },
  'home.recentFiles.empty': { 'zh-Hans': '还没有打开过文件。', en: 'No files opened yet.' },
  'home.recentWorkspaces': { 'zh-Hans': '最近打开的工作区', en: 'Recent workspaces' },
  'home.recentWorkspaces.empty': { 'zh-Hans': '还没有打开过工作区。', en: 'No workspaces opened yet.' },
  'home.current': { 'zh-Hans': '当前工作区', en: 'Current workspace' },
  'home.connections': { 'zh-Hans': '连接', en: 'Connections' },
  'home.connectTo': { 'zh-Hans': '连接到 {name}', en: 'Connect to {name}' },

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
  'db.connectionDialog.title.new': { 'zh-Hans': '新建连接', en: 'New connection' },
  'db.connectionDialog.title.edit': { 'zh-Hans': '编辑连接', en: 'Edit connection' },
  'db.connectionDialog.title.current': { 'zh-Hans': '连接数据库', en: 'Connect to database' },
  'db.connectionDialog.close': { 'zh-Hans': '关闭', en: 'Close' },
  'db.tree': { 'zh-Hans': '数据库对象', en: 'Database objects' },
  'db.view.hierarchy': { 'zh-Hans': '层级视图', en: 'Hierarchy' },
  'db.view.byKind': { 'zh-Hans': '按类型分组', en: 'By type' },
  'db.view.aria': { 'zh-Hans': '对象树视图切换', en: 'Object tree view' },
  'db.tree.loading': { 'zh-Hans': '加载中…', en: 'Loading…' },
  'db.tree.nodeCount': { 'zh-Hans': '已加载 {nodes} 行', en: '{nodes} loaded rows' },
  'db.columns.toggle': { 'zh-Hans': '展开 / 收起列与数据类型', en: 'Expand / collapse columns and types' },
  'db.columns.empty': { 'zh-Hans': '这一层没有列', en: 'No columns at this layer' },
  'db.kind.table': { 'zh-Hans': '表', en: 'Tables' },
  'db.kind.view': { 'zh-Hans': '视图', en: 'Views' },
  'db.kind.materializedView': { 'zh-Hans': '物化视图', en: 'Materialized views' },
  'db.kind.foreignTable': { 'zh-Hans': '外部表', en: 'Foreign tables' },
  'db.kind.sequence': { 'zh-Hans': '序列', en: 'Sequences' },
  'db.kind.system': { 'zh-Hans': '系统目录', en: 'System catalog' },
  'db.kind.other': { 'zh-Hans': '其他', en: 'Other' },
  // 节点类型图标（FR-META-06）：图标是给眼睛的，读屏与悬停给的是这一句
  'db.icon.tip': { 'zh-Hans': '节点类型：{kind}', en: 'Node type: {kind}' },
  // 服务器节点与它的右键三动作（FR-META-11 第一期）
  'db.server': { 'zh-Hans': '服务器', en: 'Server' },
  'db.server.menu.aria': { 'zh-Hans': '服务器节点菜单', en: 'Server node menu' },
  'db.server.menu.connect': { 'zh-Hans': '连接', en: 'Connect' },
  'db.server.menu.disconnect': { 'zh-Hans': '断开', en: 'Disconnect' },
  'db.server.menu.editConnection': { 'zh-Hans': '编辑连接…', en: 'Edit connection…' },
  'db.server.reason.alreadyConnected': {
    'zh-Hans': '已经连着这台服务器',
    en: 'Already connected to this server',
  },
  'db.server.reason.notConnected': {
    'zh-Hans': '当前没有连接可断开',
    en: 'There is no connection to disconnect',
  },
  'db.server.reason.busy': {
    'zh-Hans': '有动作正在执行（连接中 / 断开中）',
    en: 'An action is in progress (connecting / disconnecting)',
  },
  'db.server.menu.disabledTip': {
    'zh-Hans': '{name}不可用：{reason}',
    en: '{name} is unavailable: {reason}',
  },
  'db.server.menu.connected': {
    'zh-Hans': '已连 {database}（用户 {user}）',
    en: 'Connected to {database} (user {user})',
  },
  'db.tree.notConnected': { 'zh-Hans': '未连接', en: 'Not connected' },
  'db.tree.noSchema': { 'zh-Hans': '没有可展开的 schema', en: 'No schema to expand' },
  // 元数据查询行数上限（FR-META-07）：到顶时如实说"可能不完整"
  'db.meta.truncated': {
    'zh-Hans': '元数据超过上限（{limit} 行）：只显示前 {limit} 条，列表可能不完整',
    en: 'Metadata exceeded the limit ({limit} rows): showing the first {limit}, the list may be incomplete',
  },
  // 查询页签标题（与 macOS `workspaceTabTitle` =「查询 %d」/「Query %d」同一句；编号不复用）
  'db.queryTab': { 'zh-Hans': '查询 {n}', en: 'Query {n}' },
  // 对象右键菜单（第二期那一组）—— 这几条原来写死在模板里，本片顺手收进语言表
  'db.menu.browse': { 'zh-Hans': '浏览数据…', en: 'Browse data…' },
  'db.menu.generateQuery': { 'zh-Hans': '生成查询', en: 'Generate query' },
  'db.menu.design': { 'zh-Hans': '表结构设计…', en: 'Table designer…' },
  'db.menu.copyName': { 'zh-Hans': '复制名', en: 'Copy name' },
  'db.tree.objectTip': {
    'zh-Hans': '{kind} · 点一下生成查询；右键有更多',
    en: '{kind} · click to generate a query; right-click for more',
  },
  'db.search.hits': {
    'zh-Hans': '命中 {hit} 个（只在已加载的 {loaded} 个对象里找）',
    en: '{hit} matched (searched the {loaded} loaded objects)',
  },
  'db.search.hitTip': {
    'zh-Hans': '{schema}.{name}（命中依据：{basis}）',
    en: '{schema}.{name} (matched on: {basis})',
  },
  'db.search.basis.qualified': { 'zh-Hans': '限定名', en: 'qualified name' },
  'db.search.basis.name': { 'zh-Hans': '对象名', en: 'object name' },
  'db.search.basis.schema': { 'zh-Hans': 'schema 名', en: 'schema name' },
  'db.search.placeholder': { 'zh-Hans': '搜索对象（名字或 schema）', en: 'Search objects (name or schema)' },
  'db.switchDatabase': {
    'zh-Hans': '切到这个库（重连一次）；选项来自已保存连接里同主机同用户的那些库',
    en: 'Switch to this database (reconnects); options come from saved connections with the same host and user',
  },
  'db.clear': { 'zh-Hans': '清空', en: 'Clear' },
  'db.clear.tip': { 'zh-Hans': '清空编辑器（会先问一句）', en: 'Clear the editor (asks first)' },
  // 连接配置面收口（S-1a）：引擎联动 / 逐项校验 / 从 URL 导入
  'db.type': { 'zh-Hans': '引擎', en: 'Engine' },
  'db.name': { 'zh-Hans': '名称', en: 'Name' },
  'db.ssl': { 'zh-Hans': 'SSL', en: 'SSL' },
  'db.type.defaults': {
    'zh-Hans': '换引擎会带上该类型的默认端口与 SSL（默认值挂在类型上，表单不另写一份）',
    en: 'Switching the engine applies that type\u2019s default port and SSL (defaults live on the type, not in the form)',
  },
  'db.validation.summary': {
    'zh-Hans': '还有 {n} 项没填好：{fields}',
    en: '{n} field(s) still need attention: {fields}',
  },
  'db.urlImport': { 'zh-Hans': '从连接 URL 导入', en: 'Import from connection URL' },
  'db.urlImport.placeholder': {
    'zh-Hans': 'postgres://user@host:5432/db?sslmode=prefer',
    en: 'postgres://user@host:5432/db?sslmode=prefer',
  },
  'db.urlImport.button': { 'zh-Hans': '导入', en: 'Import' },
  'db.urlImport.ignored': {
    'zh-Hans': '认不出的参数（没有静默丢掉）：{list}',
    en: 'Unrecognised parameters (not silently dropped): {list}',
  },

  // 连接呈现面收口（S-1b）：显示名 / 分组折叠 / 颜色与环境标签（FR-CONN-14 / -15 / -16）
  'db.connections.ungrouped': { 'zh-Hans': '未分组', en: 'Ungrouped' },
  'db.connections.untitled': { 'zh-Hans': '（未命名）', en: '(untitled)' },
  'db.connections.rowTip': {
    'zh-Hans': '{user}@{host}:{port}/{database}（口令不在配置文件里）',
    en: '{user}@{host}:{port}/{database} (the password is not in the config file)',
  },
  'db.connections.groupToggle': { 'zh-Hans': '折叠 / 展开分组「{name}」', en: 'Collapse / expand group "{name}"' },
  'db.env.production': { 'zh-Hans': '生产', en: 'Production' },
  'db.env.staging': { 'zh-Hans': '预发', en: 'Staging' },
  'db.env.testing': { 'zh-Hans': '测试', en: 'Testing' },
  'db.env.development': { 'zh-Hans': '开发', en: 'Development' },
  'db.env.badge': { 'zh-Hans': '环境：{name}', en: 'Environment: {name}' },
  'db.env.unknownTip': {
    'zh-Hans': '认不出的环境标签「{name}」—— 原样显示，不当作没标',
    en: 'Unrecognised environment label "{name}" — shown as-is, not treated as unlabelled',
  },
  'db.color.amber': { 'zh-Hans': '琥珀', en: 'Amber' },
  'db.color.blue': { 'zh-Hans': '蓝', en: 'Blue' },
  'db.color.magenta': { 'zh-Hans': '洋红', en: 'Magenta' },
  'db.color.teal': { 'zh-Hans': '青', en: 'Teal' },
  'db.connections.colorTag': { 'zh-Hans': '自选色：{name}', en: 'Colour tag: {name}' },

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
  // 编辑器字体（FR-EDIT-26 字体面）：三档结果**分开说** —— 「系统等宽」「挑的族生效了」
  // 「这台机器上没有这个族、已回落」混成一句的话，用户会一直以为自己选对了。
  'appearance.font.family': { 'zh-Hans': '编辑器字体', en: 'Editor font' },
  'appearance.font.placeholder': {
    'zh-Hans': '留空 = 系统等宽（可直接输族名）',
    en: 'Empty = system monospace (type a family name)',
  },
  'appearance.font.apply': { 'zh-Hans': '应用', en: 'Apply' },
  'appearance.font.size': { 'zh-Hans': '字号', en: 'Size' },
  'appearance.font.system': {
    'zh-Hans': '当前使用：系统等宽 · {n} pt',
    en: 'Using system monospace · {n} pt',
  },
  'appearance.font.resolved': {
    'zh-Hans': '当前使用：{family} · {n} pt',
    en: 'Using {family} · {n} pt',
  },
  'appearance.font.missing': {
    'zh-Hans': '这台机器上没有「{family}」，已回落系统等宽（装好后点「应用」即生效）',
    en: 'No "{family}" on this machine — fell back to system monospace (click Apply once it is installed)',
  },
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
  // 终端页签（W-C 底部终端 · 2.7 · S-9b 起接真会话）：会话页签条 + 输出区 + 输入行
  'panel.terminal.session': { 'zh-Hans': '{n} 号终端', en: 'Terminal {n}' },
  'panel.terminal.new': { 'zh-Hans': '新建终端', en: 'New terminal' },
  'panel.terminal.close': { 'zh-Hans': '关闭终端', en: 'Close terminal' },
  'panel.terminal.aria': { 'zh-Hans': '终端会话', en: 'Terminal session' },
  'panel.terminal.empty': {
    'zh-Hans': '进入终端页签会自动起一个会话。',
    en: 'A session starts automatically when you open this tab.',
  },
  'panel.terminal.input': {
    'zh-Hans': '在此输入（直接送到 shell）',
    en: 'Type here (sent straight to the shell)',
  },
  'panel.terminal.ended': {
    'zh-Hans': '会话已结束（退出码 {code}）',
    en: 'Session ended (exit code {code})',
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
  // 编辑器按键提示（B1 接线后可见面：告诉用户这几组键存在，否则只有摸到的人知道）
  'sql.keys': {
    'zh-Hans': 'Ctrl+Z 撤销 · Ctrl+Shift+Z 重做 · Ctrl+/ 注释 · Alt+↑↓ 移行 · Alt+Shift+↓ 复制行 · Tab 缩进 · 回车自动缩进 · 括号自动配对 · Ctrl+F 查找 · Ctrl+G 跳行列',
    en: 'Ctrl+Z undo · Ctrl+Shift+Z redo · Ctrl+/ comment · Alt+↑↓ move line · Alt+Shift+↓ duplicate · Tab indent · Enter auto-indent · auto-pair brackets · Ctrl+F find · Ctrl+G go to line',
  },
  // 补全清单的键盘提示（B1 收尾）：↑↓ 与回车能用这件事必须写在脸上，否则只有摸到的人知道
  'sql.completionKeys': {
    'zh-Hans': '↑↓ 选择 · 回车/Tab 插入 · Esc 关闭',
    en: '↑↓ select · Enter/Tab insert · Esc close',
  },
  // 分隔条（FR-EDIT-13）：拖动 / 键盘 / 复位三件事都要在提示里说清，否则用户只会去追 textarea 的角
  'db.split.aria': { 'zh-Hans': '编辑区与结果区的分隔条', en: 'Divider between the editor and the results' },
  'db.split.tip': {
    'zh-Hans': '拖动调整编辑区与结果区高度 · ↑↓ 微调 · 双击恢复自动高度',
    en: 'Drag to resize editor and results · ↑↓ to nudge · double-click to restore automatic height',
  },
  // 编辑器状态栏（B1 第二批）：光标位置 / 缩进口径 / 括号配对
  'sql.caret': { 'zh-Hans': '行 {line} · 列 {column}', en: 'Ln {line}, Col {column}' },
  'sql.problems': { 'zh-Hans': '问题 {n}', en: '{n} problem(s)' },
  'sql.indentSpaces': { 'zh-Hans': '空格 ×{n}', en: 'Spaces ×{n}' },
  'sql.indentTab': { 'zh-Hans': 'Tab 缩进', en: 'Tab indents' },
  'sql.bracketNone': { 'zh-Hans': '光标处无括号', en: 'no bracket at caret' },
  'sql.bracketMatched': { 'zh-Hans': '括号配对 {from} ↔ {to}', en: 'bracket {from} ↔ {to}' },
  'sql.bracketUnmatched': {
    'zh-Hans': '括号不配对：{char} @ {line}:{column}',
    en: 'unmatched {char} @ {line}:{column}',
  },
  'sql.gotoOpen': { 'zh-Hans': '跳行列…', en: 'Go to line…' },
  'sql.gotoTip': { 'zh-Hans': '跳到指定行或「行:列」（Ctrl+G）', en: 'Jump to a line or line:column (Ctrl+G)' },
  'sql.gotoLabel': { 'zh-Hans': '行 / 行:列', en: 'Line / line:column' },
  'sql.gotoGo': { 'zh-Hans': '跳转', en: 'Go' },
  // 编辑菜单（FR-EDIT-17）：一个入口管五件事 —— 五件全接上了真动作
  // （查找替换 / 跳行 / 缩进 / 清除 / 格式化 SQL）。**菜单里不放点了没反应的项**：假入口比没有入口更糟。
  'sql.editMenu': { 'zh-Hans': '编辑', en: 'Edit' },
  'sql.editMenu.tip': {
    'zh-Hans': '编辑菜单：查找 / 替换 · 跳到行或列 · 缩进 / 反缩进 · 清除查询 · 格式化 SQL',
    en: 'Edit menu: find / replace · go to line · indent / outdent · clear query · format SQL',
  },
  'sql.edit.find': { 'zh-Hans': '查找 / 替换…', en: 'Find / replace…' },
  // 撤销 / 重做（FR-EDIT-60）：菜单里这两项空栈时是灰的，标题写清键位 ——
  // 键位与「连续输入合并一步」的口径都写在这儿，帮助面（`sql.keys`）另有一行。
  'sql.edit.undo': { 'zh-Hans': '撤销', en: 'Undo' },
  'sql.edit.redo': { 'zh-Hans': '重做', en: 'Redo' },
  'sql.edit.undoTip': {
    'zh-Hans': '撤销上一步编辑（Ctrl+Z）；一段连续输入算一步',
    en: 'Undo the last edit (Ctrl+Z); a run of typing counts as one step',
  },
  'sql.edit.redoTip': { 'zh-Hans': '重做（Ctrl+Shift+Z / Ctrl+Y）', en: 'Redo (Ctrl+Shift+Z / Ctrl+Y)' },
  'sql.undo.exhausted': { 'zh-Hans': '已经撤到最早一步了', en: 'Already at the earliest step' },
  'sql.redo.exhausted': { 'zh-Hans': '没有可重做的步骤', en: 'Nothing to redo' },
  'sql.undo.rebuilt': {
    'zh-Hans': '这块内容刚被整篇换过（回填已保存查询 / 打开表 / 换成 AI 结果），撤销栈已重置',
    en: 'The content was replaced wholesale (refilled query / opened table / AI result) — the undo history was reset',
  },
  // 页签徽标：**切走再回来历史还在**（第 26 轮：每页签一份栈），这件事要有可见面。
  'sql.tabUndoDepth': {
    'zh-Hans': '这张页签还能撤 {n} 步（切走再回来历史还在）',
    en: '{n} step(s) still undoable in this tab (history survives switching away)',
  },
  'sql.edit.goto': { 'zh-Hans': '跳到行或列…', en: 'Go to line…' },
  'sql.edit.indent': { 'zh-Hans': '缩进选中行', en: 'Indent selected lines' },
  'sql.edit.outdent': { 'zh-Hans': '反缩进选中行', en: 'Outdent selected lines' },
  'sql.edit.clear': { 'zh-Hans': '清除查询', en: 'Clear query' },
  // 格式化 SQL（FR-EDIT-22）：回执必须说清「用了什么引擎 / 没改动 / 为什么拒绝」——
  // 真做的只有关键字大写（不重排空白），所以入口文案也不写「美化」这种含糊词。
  'sql.edit.format': { 'zh-Hans': '格式化 SQL（关键字大写）', en: 'Format SQL (uppercase keywords)' },
  'sql.format.empty': { 'zh-Hans': '编辑器里没有 SQL 可格式化', en: 'Nothing to format in the editor' },
  'sql.format.failed': { 'zh-Hans': '格式化没有跑成：{reason}', en: 'Formatting failed: {reason}' },
  'sql.format.dismiss': { 'zh-Hans': '知道了', en: 'Dismiss' },

  // 查询参数（FR-EXEC-17）：填值面板 + 执行中页签不可关闭的说明
  'sql.params.title': { 'zh-Hans': '这条语句有 {n} 个参数，先填值', en: 'This statement has {n} parameter(s) — fill them in first' },
  'sql.params.tip': {
    'zh-Hans': '编辑器里的占位符不会被替换；绑定只用于这一次执行。',
    en: 'The placeholders in the editor stay as they are; binding applies to this run only.',
  },
  'sql.params.occurrences': { 'zh-Hans': '出现 {n} 次', en: 'appears {n} times' },
  'sql.params.kind': { 'zh-Hans': '类型', en: 'type' },
  'sql.params.value': { 'zh-Hans': '值', en: 'value' },
  'sql.params.kind.text': { 'zh-Hans': '文本', en: 'text' },
  'sql.params.kind.number': { 'zh-Hans': '数字', en: 'number' },
  'sql.params.kind.boolean': { 'zh-Hans': '布尔', en: 'boolean' },
  'sql.params.kind.null': { 'zh-Hans': 'NULL', en: 'NULL' },
  'sql.params.nullHint': { 'zh-Hans': 'NULL 不需要填值', en: 'NULL needs no value' },
  'sql.params.missing': { 'zh-Hans': '还缺这些参数：{names}', en: 'Still missing values for: {names}' },
  'sql.params.submit': { 'zh-Hans': '填好，执行', en: 'Run with these values' },
  'sql.params.cancel': { 'zh-Hans': '取消', en: 'Cancel' },
  'sql.params.cancelled': { 'zh-Hans': '已取消：这条语句没有执行。', en: 'Cancelled: nothing was executed.' },
  'sql.params.bound': { 'zh-Hans': '参数已绑定：{list}', en: 'Parameters bound: {list}' },
  'sql.params.boundLine': { 'zh-Hans': '{name} → {kind} {literal}', en: '{name} → {kind} {literal}' },
  'sql.params.unused': {
    'zh-Hans': '另外还给了 SQL 里没有的参数：{names}（可能是拼错）。',
    en: 'Also got values for parameters the SQL does not use: {names} (probably a typo).',
  },
  'sql.params.failed': { 'zh-Hans': '绑定没有成功：{reason}', en: 'Binding failed: {reason}' },
  'sql.tabRunningTip': {
    'zh-Hans': '{title} 正在执行查询，不能关闭（等它跑完，或点「取消」）',
    en: '{title} is running a query and cannot be closed (wait for it, or press Cancel)',
  },
  'sql.tabRunningBlocked': {
    'zh-Hans': '{title} 正在执行查询：不能关闭。要停下请先点「取消」。',
    en: '{title} is running a query: it cannot be closed. Press Cancel to stop it first.',
  },
  // 查找 / 替换条（FR-EDIT-18）：读数与"没有匹配"都必须写出来 —— 安静不是结论
  'sql.find.label': { 'zh-Hans': '查找', en: 'Find' },
  'sql.find.replaceLabel': { 'zh-Hans': '替换为', en: 'Replace with' },
  'sql.find.case': { 'zh-Hans': 'Aa 区分大小写', en: 'Aa match case' },
  'sql.find.caseTip': {
    'zh-Hans': '缺省不区分大小写（SQL 里随手打是常态）',
    en: 'Case-insensitive by default (SQL is typed loosely)',
  },
  'sql.find.prev': { 'zh-Hans': '上一处', en: 'Prev' },
  'sql.find.next': { 'zh-Hans': '下一处', en: 'Next' },
  'sql.find.one': { 'zh-Hans': '替换', en: 'Replace' },
  'sql.find.all': { 'zh-Hans': '全部替换', en: 'Replace all' },
  'sql.find.close': { 'zh-Hans': '关闭', en: 'Close' },
  'sql.find.readout': { 'zh-Hans': '{position} / {total} 处', en: '{position} of {total}' },
  'sql.find.none': {
    'zh-Hans': '没有匹配（按字面量查，不认正则）',
    en: 'No match (literal search, not regex)',
  },
  'sql.find.note': { 'zh-Hans': '替换了 {n} 处', en: 'Replaced {n}' },
  'sql.find.noteNext': {
    'zh-Hans': '替换了 {n} 处 · 下一处已选中',
    en: 'Replaced {n} · next match selected',
  },
  'sql.find.noteDone': {
    'zh-Hans': '替换了 {n} 处 · 已替完，没有别的匹配了',
    en: 'Replaced {n} · done, no other matches left',
  },
  'sql.find.placeholder': { 'zh-Hans': '要查的文字', en: 'Text to find' },
  'sql.find.replacePlaceholder': { 'zh-Hans': '替成什么（字面量）', en: 'Replacement (literal)' },
  'sql.find.emptyQuery': { 'zh-Hans': '先输入要查的文字', en: 'Type something to find first' },
  'sql.cancel': { 'zh-Hans': '取消', en: 'Cancel' },
  'sql.planOnly': { 'zh-Hans': '只看计划', en: 'Plan only' },
  'sql.runWithPlan': { 'zh-Hans': '执行并出计划', en: 'Run with plan' },
  'sql.affected': { 'zh-Hans': '影响 {n} 行（无结果集）', en: 'affected {n} rows (no result set)' },
  'sql.rows': { 'zh-Hans': '{n} 行', en: '{n} rows' },
  'sql.truncated': { 'zh-Hans': '（服务端回来 {returned} 行，已截断，只显示前 {shown} 行）', en: '(server returned {returned}; truncated to {shown})' },

  // 智能体设置（FR-AI-01）：总开关 / 端点 / 模型 / 配额 / 密钥 + 一句裁决
  'agent.title': { 'zh-Hans': '智能体设置', en: 'Agent settings' },
  'agent.close': { 'zh-Hans': '关闭', en: 'Close' },
  'agent.enabled': { 'zh-Hans': '启用智能体（总开关）', en: 'Enable the agent (master switch)' },
  'agent.gate.disabled': {
    'zh-Hans': '总开关关闭：不会向任何模型服务发送数据。',
    en: 'Master switch is off: nothing is sent to any model service.',
  },
  'agent.gate.ready': {
    'zh-Hans': '将使用 {model}（{scope}）。',
    en: 'Will use {model} ({scope}).',
  },
  'agent.gate.missing': { 'zh-Hans': '还不能外发，缺这几项：', en: 'Cannot send yet — missing:' },
  'agent.scope.local': { 'zh-Hans': '本机端点，无需密钥', en: 'local endpoint, no key needed' },
  'agent.scope.remote': { 'zh-Hans': '远端端点', en: 'remote endpoint' },

  // 对话式诊断（FR-AI-03）：先摊证据，再粘模型回复；结论必须有依据
  'diag.entry': { 'zh-Hans': '诊断…', en: 'Diagnose…' },
  'diag.entryTip': {
    'zh-Hans': '取这条查询的执行计划 / 锁阻塞 / 慢查询统计 / 表访问统计，摊成资料块 —— 复制去问任意模型，再粘回复回来解读',
    en: 'Gather the plan, lock waits, slow-query stats and table stats as a brief — ask any model, then paste the reply back',
  },
  'diag.title': { 'zh-Hans': '诊断这条查询', en: 'Diagnose this query' },
  'diag.intro': {
    'zh-Hans': '本面板只取证据并解读：不执行你的语句（执行计划用 EXPLAIN，不加 ANALYZE），建议只放进编辑器、由你自己按确认走。',
    en: 'This panel only gathers evidence and reads a reply: it never runs your statement (EXPLAIN without ANALYZE), and suggestions only go into the editor.',
  },
  'diag.close': { 'zh-Hans': '关闭', en: 'Close' },
  'diag.evidence.plan': { 'zh-Hans': '执行计划', en: 'Execution plan' },
  'diag.evidence.locks': { 'zh-Hans': '锁阻塞', en: 'Lock waits' },
  'diag.evidence.slow': { 'zh-Hans': '慢查询统计', en: 'Slow-query stats' },
  'diag.evidence.stats': { 'zh-Hans': '表访问统计', en: 'Table access stats' },
  'diag.status.rows': { 'zh-Hans': '{n} 行', en: '{n} rows' },
  'diag.status.empty': { 'zh-Hans': '查到了，但没有行', en: 'Queried, no rows' },
  'diag.status.unavailable': { 'zh-Hans': '未取到', en: 'Unavailable' },
  'diag.evidenceSql': { 'zh-Hans': '取证 SQL（可复跑）', en: 'Evidence SQL (re-runnable)' },
  'diag.briefLabel': { 'zh-Hans': '资料块（复制去问任意模型）', en: 'Brief (copy to any model)' },
  'diag.copy': { 'zh-Hans': '复制资料块', en: 'Copy brief' },
  'diag.copied': { 'zh-Hans': '已复制到剪贴板', en: 'Copied to clipboard' },
  'diag.copyFailed': {
    'zh-Hans': '剪贴板不可用（{reason}）：请在上面那格手动全选复制',
    en: 'Clipboard unavailable ({reason}): select and copy the box manually',
  },
  'diag.replyLabel': { 'zh-Hans': '粘贴模型回复', en: 'Paste the model reply' },
  'diag.replyTip': {
    'zh-Hans': '结论行写成「结论: … [依据: e1,e2]」，建议行写成「建议: <SQL>」；没有依据的结论会被拒。',
    en: 'Write conclusions as "结论: … [依据: e1,e2]" and suggestions as "建议: <SQL>"; conclusions without evidence are rejected.',
  },
  'diag.parse': { 'zh-Hans': '解读', en: 'Read reply' },
  'diag.noReply': { 'zh-Hans': '还没有解读结果。', en: 'No parsed result yet.' },
  'diag.acceptedCount': { 'zh-Hans': '采纳 {n} 条', en: '{n} accepted' },
  'diag.rejectedCount': { 'zh-Hans': '拒绝 {n} 条', en: '{n} rejected' },
  'diag.unrecognizedCount': { 'zh-Hans': '认不出 {n} 行（原样保留）', en: '{n} unreadable lines (kept verbatim)' },
  'diag.citations': { 'zh-Hans': '依据', en: 'Evidence' },
  'diag.suggestionFor': { 'zh-Hans': '对应第 {n} 条结论', en: 'for conclusion {n}' },
  'diag.insert': { 'zh-Hans': '放进编辑器', en: 'Insert into editor' },
  'diag.risk.safe': { 'zh-Hans': '只读 · 可直接执行', en: 'read-only · safe to run' },
  'diag.risk.confirm': { 'zh-Hans': '会改数据 · 执行前要确认', en: 'writes data · confirm before running' },
  'diag.risk.forbidden': { 'zh-Hans': '只读连接会拒绝这条', en: 'rejected on a read-only connection' },
  'diag.reject.no_citation': { 'zh-Hans': '结论没有引用证据', en: 'conclusion cites no evidence' },
  'diag.reject.unknown_evidence': { 'zh-Hans': '引用了不存在的证据编号', en: 'cites an evidence id that does not exist' },
  'diag.reject.unavailable_evidence': { 'zh-Hans': '引用了没取到的证据', en: 'cites evidence that was not available' },
  'diag.reject.empty_suggestion': { 'zh-Hans': '建议行里没有 SQL', en: 'suggestion has no SQL' },
  'diag.reject.orphan_suggestion': { 'zh-Hans': '这条建议前面没有已采纳的结论', en: 'suggestion has no accepted conclusion before it' },
  'diag.gathering': { 'zh-Hans': '正在取证据…', en: 'Gathering evidence…' },
  'diag.gatherFailed': { 'zh-Hans': '取证据失败：{message}', en: 'Could not gather evidence: {message}' },
  'agent.issue.endpointMissing': { 'zh-Hans': '端点地址', en: 'endpoint URL' },
  'agent.issue.modelMissing': { 'zh-Hans': '模型名', en: 'model name' },
  'agent.issue.keyMissing': { 'zh-Hans': 'API Key（远端端点必填）', en: 'API key (required for remote endpoints)' },
  'agent.issue.endpointScheme': {
    'zh-Hans': '端点必须以 http:// 或 https:// 开头（现在是「{detail}」）',
    en: 'The endpoint must start with http:// or https:// (got "{detail}")',
  },
  'agent.issue.endpointHost': { 'zh-Hans': '端点里没有主机名', en: 'The endpoint has no host name' },
  'agent.issue.timeoutOutOfRange': {
    'zh-Hans': '超时要在 1~600 秒之间（现在是 {detail}）',
    en: 'Timeout must be 1–600 seconds (got {detail})',
  },
  'agent.issue.hourlyLimitOutOfRange': {
    'zh-Hans': '每小时上限要在 1~100000 之间（现在是 {detail}）',
    en: 'Hourly limit must be 1–100000 (got {detail})',
  },
  'agent.generate.title': { 'zh-Hans': '用一句话生成 SQL', en: 'Generate SQL from a sentence' },
  'agent.generate.entry': { 'zh-Hans': 'AI 生成…', en: 'Generate with AI…' },
  'agent.generate.entryTip': {
    'zh-Hans': '用一句话描述要查什么，生成可读的 SQL（结果只进编辑器，不会自动执行）',
    en: 'Describe what to query in one sentence and get SQL (it only goes into the editor, never runs)',
  },
  'agent.generate.intro': {
    'zh-Hans': '分两步：先看「将要发出去的内容」，确认后再点生成。要发的是**表名 / 列名 / 类型 + 你的问题**，不含任何行数据、不含密钥。',
    en: 'Two steps: first see exactly what would be sent, then generate. Only table names, column names, types and your question go out — no row data, no key.',
  },
  'agent.generate.question': { 'zh-Hans': '要查什么', en: 'What to query' },
  'agent.generate.questionPlaceholder': {
    'zh-Hans': '例如：最近 7 天每天的订单数与金额合计',
    en: 'e.g. daily order count and total amount for the last 7 days',
  },
  'agent.generate.previewButton': { 'zh-Hans': '先看要发什么', en: 'Show what will be sent' },
  'agent.generate.previewing': { 'zh-Hans': '正在装配…', en: 'Preparing…' },
  'agent.generate.sendButton': { 'zh-Hans': '发送并生成', en: 'Send and generate' },
  'agent.generate.sending': { 'zh-Hans': '等待模型回话…', en: 'Waiting for the model…' },
  'agent.generate.tableCount': { 'zh-Hans': '随请求外发 {n} 张表', en: '{n} table(s) go out with the request' },
  // 每小时配额（FR-AI-02 第三片）：读数 / 满了还要等多久 / 被拦时说清「一条都没发」
  'agent.generate.quotaLeft': {
    'zh-Hans': '本小时已用 {used}/{limit}（还剩 {remaining} 次）',
    en: '{used}/{limit} used this hour ({remaining} left)',
  },
  'agent.generate.quotaFull': {
    'zh-Hans': '本小时额度已用完（上限 {limit} 次），{wait}后可再发',
    en: 'Hourly budget used up (limit {limit}); available again in {wait}',
  },
  'agent.generate.quotaWaitMin': { 'zh-Hans': '{m} 分 {s} 秒', en: '{m}m {s}s' },
  'agent.generate.quotaWaitSec': { 'zh-Hans': '{s} 秒', en: '{s}s' },
  'agent.generate.throttled': {
    'zh-Hans': '本小时已发满 {limit} 次 —— 这一次一条请求都没有发出去；{wait}后可再发。',
    en: 'Hourly limit of {limit} reached — nothing was sent this time; try again in {wait}.',
  },
  'agent.generate.outgoing': { 'zh-Hans': '将要外发的内容（逐字，就是你上一步看到的这份）', en: 'Exactly what will be sent' },
  'agent.generate.dropped': {
    'zh-Hans': '另有 {n} 张表因上限没有列出（表太多反而会写错 SQL）',
    en: '{n} more table(s) were left out of the list (too many tables hurts accuracy)',
  },
  'agent.generate.result': { 'zh-Hans': '生成的 SQL（未执行）', en: 'Generated SQL (not executed)' },
  'agent.generate.tablesUsed': { 'zh-Hans': '用到这些表：{tables}', en: 'Tables used: {tables}' },
  'agent.generate.tablesNone': {
    'zh-Hans': '这段 SQL 没有点到当前已加载的表（可能是新表名或不带表名的语句）',
    en: 'This SQL does not reference any loaded table (maybe a new name or a table-less statement)',
  },
  'agent.generate.stats': { 'zh-Hans': '模型 {model} · 往返 {ms} ms', en: 'model {model} · {ms} ms round trip' },
  'agent.generate.neverRuns': {
    'zh-Hans': '这段 SQL 不会被自动执行：点下面的按钮才写进编辑器，运行仍要你自己按。',
    en: 'This SQL is never auto-executed: the button below only puts it in the editor; you still press run.',
  },
  'agent.generate.insert': { 'zh-Hans': '写入编辑器', en: 'Put in editor' },
  'agent.generate.saveAsQuery': {
    'zh-Hans': '存成已保存查询',
    en: 'Save as saved query',
  },
  'agent.generate.saveAsQueryTip': {
    'zh-Hans': '把这段 SQL 存进「已保存」（编辑器内容不动；保存面板里还能改名、同名会先问覆盖）',
    en: 'Store this SQL under Saved (the editor is untouched; you can rename it there, and a duplicate name asks before overwriting)',
  },
  'agent.generate.history': { 'zh-Hans': '生成历史', en: 'History' },
  'agent.generate.historyHint': {
    'zh-Hans': '共 {n} 条（只记成功的那一次；点一条可回填问句、看回那次的 SQL）',
    en: '{n} in all (successful runs only; click one to reuse the question and see its SQL)',
  },
  'agent.generate.historyEmpty': {
    'zh-Hans': '还没有成功的生成记录。第一次发送成功后，问句与结果会留在这里。',
    en: 'No successful runs yet. After the first successful send, the question and result stay here.',
  },
  'agent.generate.historyRowTip': {
    'zh-Hans': '点一下：把这个问句填回输入框，并摊出那次的 SQL（不会自动执行）',
    en: 'Click to reuse this question and show its SQL (never executed)',
  },
  'agent.generate.historyReopened': {
    'zh-Hans': '历史里那一次的 SQL（{when} · 未执行）',
    en: 'SQL from that run ({when} · not executed)',
  },
  'agent.generate.historyTruncated': {
    'zh-Hans': '原文太长，这里存的是截断后的版本（要看全文请当时就「存成已保存查询」）。',
    en: 'The original was too long, so this is a truncated copy (for the full text, use "Save as saved query" at the time).',
  },
  'agent.generate.desktopOnly': {
    'zh-Hans': '浏览器预览里没有外发通道，生成功能只在桌面应用里可用。',
    en: 'The browser preview has no outbound channel; this works in the desktop app only.',
  },
  'agent.generate.desktopOnlyHint': {
    'zh-Hans': '打开桌面版 Doyah Studio，在 SQL 编辑器那一行点「AI 生成…」。',
    en: 'Open the desktop Doyah Studio and use "Generate with AI…" above the SQL editor.',
  },
  'agent.preset': { 'zh-Hans': '服务商', en: 'Provider' },
  'agent.preset.deepseek': { 'zh-Hans': 'DeepSeek', en: 'DeepSeek' },
  'agent.preset.openai': { 'zh-Hans': 'OpenAI', en: 'OpenAI' },
  'agent.preset.qwen': { 'zh-Hans': '通义千问', en: 'Qwen (DashScope)' },
  'agent.preset.zhipu': { 'zh-Hans': '智谱 GLM', en: 'Zhipu GLM' },
  'agent.preset.ollama': { 'zh-Hans': 'Ollama（本机）', en: 'Ollama (local)' },
  'agent.preset.vllm': { 'zh-Hans': 'vLLM（本机）', en: 'vLLM (local)' },
  'agent.preset.custom': { 'zh-Hans': '自定义', en: 'Custom' },
  'agent.endpoint': { 'zh-Hans': '端点', en: 'Endpoint' },
  'agent.endpoint.placeholder': {
    'zh-Hans': 'https://api.example.com/v1（OpenAI 兼容）',
    en: 'https://api.example.com/v1 (OpenAI compatible)',
  },
  'agent.model': { 'zh-Hans': '模型', en: 'Model' },
  'agent.model.placeholder': { 'zh-Hans': '模型名', en: 'model name' },
  'agent.model.manual': {
    'zh-Hans': '这家服务商没有可预置的模型清单（接入点 / 已加载模型只能自己填）。',
    en: 'This provider has no preset model list — type the deployment or loaded model yourself.',
  },
  'agent.timeout': { 'zh-Hans': '超时（秒）', en: 'Timeout (s)' },
  'agent.hourlyLimit': { 'zh-Hans': '每小时上限', en: 'Hourly limit' },
  'agent.quota.used': {
    'zh-Hans': '本小时已用 {used}/{limit}（还剩 {remaining} 次）',
    en: '{used}/{limit} used this hour ({remaining} left)',
  },
  'agent.quota.full': {
    'zh-Hans': '本小时已满额（上限 {limit} 次）：约 {minutes} 分钟后才有空位，期间「AI 生成…」会被拦住（一条请求都不发）。',
    en: 'Hourly limit reached ({limit} used): about {minutes} min until a slot frees up — generation is refused until then (nothing is sent).',
  },
  'agent.quota.refresh': { 'zh-Hans': '刷新读数', en: 'Refresh' },

  // 智能体审计记录（FR-AI-09 的审计半）：每条 = 一次外发尝试，含「一条都没发出去」的那几次。
  'audit.title': { 'zh-Hans': '智能体审计记录', en: 'Agent audit log' },
  'audit.close': { 'zh-Hans': '关闭', en: 'Close' },
  'audit.note': {
    'zh-Hans':
      '每一条 = 一次外发尝试。被总开关 / 配置不全 / 每小时上限挡住的那几次也在（它们一条请求都没发出去）；问句与失败原因在写入前已抹掉形似凭据的片段。',
    en:
      'Each row is one outbound attempt. Refused attempts (switch off, incomplete config, hourly limit) are logged too — nothing was sent for those. Credential-shaped fragments are scrubbed before anything is written.',
  },
  'audit.empty': {
    'zh-Hans': '还没有任何外发尝试（用「AI 生成…」发过之后这里就会有一条）。',
    en: 'No outbound attempts yet — one row appears after the first AI generation.',
  },
  'audit.refresh': { 'zh-Hans': '刷新', en: 'Refresh' },
  'audit.verdict.ok': { 'zh-Hans': '成功', en: 'Sent' },
  'audit.verdict.failed': { 'zh-Hans': '失败', en: 'Failed' },
  'audit.verdict.blocked': { 'zh-Hans': '被闸门挡住', en: 'Refused (gate)' },
  'audit.verdict.throttled': { 'zh-Hans': '被每小时上限挡住', en: 'Refused (hourly limit)' },
  'audit.egress.sent': { 'zh-Hans': '已出网', en: 'left this machine' },
  'audit.egress.notSent': { 'zh-Hans': '未出网', en: 'nothing left' },
  'audit.summary.empty': { 'zh-Hans': '（没有记到问句）', en: '(no question recorded)' },
  'audit.model': { 'zh-Hans': '模型 {model}', en: 'model {model}' },
  'audit.tables': { 'zh-Hans': '发出去 {n} 张表', en: '{n} table(s) sent' },
  'audit.duration': { 'zh-Hans': '{ms} 毫秒', en: '{ms} ms' },
  'agent.save': { 'zh-Hans': '保存设置', en: 'Save settings' },
  'agent.saving': { 'zh-Hans': '保存中…', en: 'Saving…' },
  'agent.saved': { 'zh-Hans': '已保存', en: 'Saved' },
  'agent.key': { 'zh-Hans': 'API Key', en: 'API key' },
  'agent.key.present': { 'zh-Hans': '已配置', en: 'configured' },
  'agent.key.absent': { 'zh-Hans': '未配置', en: 'not configured' },
  'agent.key.placeholder': { 'zh-Hans': '粘贴密钥（保存后不再回显）', en: 'Paste the key (never shown again after saving)' },
  'agent.key.save': { 'zh-Hans': '保存密钥', en: 'Save key' },
  'agent.key.saved': { 'zh-Hans': '密钥已保存', en: 'Key saved' },
  'agent.key.clear': { 'zh-Hans': '清除密钥', en: 'Clear key' },
  'agent.key.cleared': { 'zh-Hans': '密钥已清除', en: 'Key cleared' },
  'agent.key.storage.dpapi': {
    'zh-Hans': '密钥加密存放（Windows DPAPI，与当前用户绑定），不写进配置文件',
    en: 'Key is stored encrypted (Windows DPAPI, bound to this user), never in the config file',
  },
  'agent.key.storage.unavailable': {
    'zh-Hans': '本机没有可用的系统凭据加密 —— 密钥无法保存',
    en: 'No system credential encryption on this machine — the key cannot be stored',
  },
  'agent.key.note': {
    'zh-Hans': '密钥单独一份密文文件；界面只显示「在不在」，永远不会把它显示出来。',
    en: 'The key lives in its own encrypted file; the UI only shows whether it exists and never displays it.',
  },
  'agent.key.empty': { 'zh-Hans': '密钥是空的，没有保存。', en: 'The key is empty, nothing was saved.' },
  'agent.key.emptyHint': {
    'zh-Hans': '要么填一个密钥，要么用「清除密钥」把已存的删掉。',
    en: 'Either type a key, or use "Clear key" to delete the stored one.',
  },

  // 保存查询（FR-EDIT-14）：按钮在执行之前；同名会先问「覆盖保存」
  'saveQuery.save': { 'zh-Hans': '保存查询', en: 'Save query' },
  'saveQuery.saveTip': {
    'zh-Hans': '把当前页签的 SQL 存下来（可命名；同名会先问要不要覆盖）',
    en: 'Save the current tab SQL (you can name it; a duplicate name asks before overwriting)',
  },
  'saveQuery.list': { 'zh-Hans': '已保存', en: 'Saved' },
  'saveQuery.listTip': {
    'zh-Hans': '已保存的查询：可回填到当前页签或新页签',
    en: 'Saved queries: refill the current tab or open one in a new tab',
  },
  'saveQuery.title': { 'zh-Hans': '保存查询', en: 'Save query' },
  'saveQuery.nameLabel': { 'zh-Hans': '查询名', en: 'Query name' },
  'saveQuery.namePlaceholder': { 'zh-Hans': '给这条 SQL 起个名字', en: 'Name this SQL' },
  'saveQuery.submit': { 'zh-Hans': '保存', en: 'Save' },
  'saveQuery.overwrite': { 'zh-Hans': '覆盖保存', en: 'Overwrite' },
  'saveQuery.cancel': { 'zh-Hans': '取消', en: 'Cancel' },
  'saveQuery.nameRequired': {
    'zh-Hans': '先给这条查询起个名字（不能只有空格）',
    en: 'Give this query a name first (spaces alone do not count)',
  },
  'saveQuery.sqlRequired': { 'zh-Hans': '编辑器里没有可保存的 SQL', en: 'There is no SQL in the editor to save' },
  // 保存面板的两种来源：默认存编辑器；从「AI 生成」过来时存的是**生成的那一段**（编辑器不动）。
  // 这句必须显示 —— 否则用户会以为存的是编辑器里的内容（存错东西比存不上更糟）。
  'saveQuery.sourceGenerated': {
    'zh-Hans': '要存的是「AI 生成」的那段 SQL —— 编辑器里的内容不动',
    en: 'Saving the SQL that the assistant generated — the editor content stays untouched',
  },
  'saveQuery.conflict': {
    'zh-Hans': '已有同名查询「{name}」（存于 {time}）—— 覆盖会替换它，不会多出一条',
    en: 'A query named “{name}” already exists (saved at {time}) — overwriting replaces it instead of adding a second one',
  },
  'saveQuery.saved': { 'zh-Hans': '已保存「{name}」', en: 'Saved “{name}”' },
  'saveQuery.refilled': { 'zh-Hans': '已回填「{name}」', en: 'Refilled “{name}”' },
  'saveQuery.failed': { 'zh-Hans': '保存失败：{reason}', en: 'Save failed: {reason}' },
  'saveQuery.empty': { 'zh-Hans': '还没有保存过查询', en: 'No saved queries yet' },
  'saveQuery.refill': { 'zh-Hans': '回填', en: 'Refill' },
  'saveQuery.refillTip': { 'zh-Hans': '把这条 SQL 放回当前页签（替换编辑器内容）', en: 'Put this SQL back into the current tab (replaces the editor content)' },
  'saveQuery.refillNew': { 'zh-Hans': '新页签', en: 'New tab' },
  'saveQuery.refillNewTip': { 'zh-Hans': '在新页签打开这条 SQL（当前页签不动）', en: 'Open this SQL in a new tab (the current tab is untouched)' },
  'saveQuery.delete': { 'zh-Hans': '删除', en: 'Delete' },
  'saveQuery.deleteTip': { 'zh-Hans': '删掉这条已保存查询（不动数据库里的任何数据）', en: 'Delete this saved query (the database is not touched)' },

  // 查询自动归档（FR-EDIT-31：执行过的 SQL 按天落盘；同一条只累计次数）
  'archive.button': { 'zh-Hans': '归档', en: 'Archive' },
  'archive.listTip': {
    'zh-Hans': '执行过的 SQL（按天落在 DoyahStudio\\queries\\ 下，可翻看前几天）',
    en: 'Executed SQL (one file per day under DoyahStudio\\queries\\ — earlier days can be browsed)',
  },
  'archive.daysAria': { 'zh-Hans': '归档日期', en: 'Archive days' },
  'archive.today': { 'zh-Hans': '今天', en: 'Today' },
  'archive.dayTip': { 'zh-Hans': '看这一天的归档（一天一份文件）', en: "Show this day's archive (one file per day)" },
  'archive.empty': { 'zh-Hans': '今天（{day}）还没有归档：执行一条查询就会自动记下来', en: 'Nothing archived for {day} yet — running a query records it automatically' },
  'archive.emptyDay': { 'zh-Hans': '{day} 这一天没有归档', en: 'Nothing was archived on {day}' },
  'archive.untitled': { 'zh-Hans': '未命名页签', en: 'Untitled tab' },
  'archive.runs': { 'zh-Hans': '执行 {runs} 次', en: 'ran {runs}×' },
  'archive.elapsed': { 'zh-Hans': '{ms} 毫秒', en: '{ms} ms' },
  'archive.rows': { 'zh-Hans': '{rows} 行', en: '{rows} rows' },
  'archive.refill': { 'zh-Hans': '回填', en: 'Refill' },
  'archive.refillTip': { 'zh-Hans': '把这条 SQL 放回当前页签（替换编辑器内容）', en: 'Put this SQL back into the current tab (replaces the editor content)' },
  'archive.refilled': { 'zh-Hans': '已回填「{title}」', en: 'Refilled “{title}”' },
  'archive.saved': { 'zh-Hans': '已归档 · 今天第 {runs} 次执行', en: 'Archived · run {runs} today' },
  'archive.full': {
    'zh-Hans': '今天这份归档到上限（512KB）了：这一条没写进去，明天会新起一份',
    en: 'Today’s archive hit its 512 KB ceiling — this one was not written; a new file starts tomorrow',
  },
  'archive.failed': { 'zh-Hans': '归档失败：{reason}（查询结果不受影响）', en: 'Archiving failed: {reason} (the query result is unaffected)' },
  'archive.file': { 'zh-Hans': '文件：{path} · {bytes} 字节', en: 'File: {path} · {bytes} bytes' },

  // 备份（FR-IO-04：封装本机 pg_dump —— 命令行先摊出来，再真跑）
  'backup.title': { 'zh-Hans': '备份数据库', en: 'Back up database' },
  'backup.close': { 'zh-Hans': '关闭', en: 'Close' },
  'backup.note': {
    'zh-Hans':
      '备份会起本机的 pg_dump 子进程：一致性由它的快照保证。口令只经环境变量传给它，不进命令行、也不进日志。',
    en: 'The backup runs the local pg_dump as a child process (its snapshot is what makes the dump consistent). The password is passed via an environment variable only: never on the command line, never in the log.',
  },
  'backup.path': { 'zh-Hans': '写到', en: 'Write to' },
  'backup.pathHint': {
    'zh-Hans': '完整路径，例如 D:\\backup\\shop-20261018.dump；目录形式填一个尚不存在的目录。',
    en: 'A full path, e.g. D:\\backup\\shop-20261018.dump; for the directory format give a directory that does not exist yet.',
  },
  'backup.format': { 'zh-Hans': '格式', en: 'Format' },
  'backup.format.plain': { 'zh-Hans': '纯 SQL（能直接看、能 psql 灌）', en: 'Plain SQL (readable, psql can load it)' },
  'backup.format.custom': { 'zh-Hans': '自定义归档（体积小、可分段还原）', en: 'Custom archive (smaller, --section restores)' },
  'backup.format.directory': { 'zh-Hans': '目录形式（可并行，目标目录须不存在）', en: 'Directory (parallelisable; target must not exist)' },
  'backup.database': { 'zh-Hans': '备份哪个库', en: 'Database to back up' },
  'backup.databaseHint': { 'zh-Hans': '留空 = 当前连接的库', en: 'Empty = the connected database' },
  'backup.program': { 'zh-Hans': 'pg_dump 程序', en: 'pg_dump program' },
  'backup.programHint': { 'zh-Hans': '留空 = 自动找（PATH → PostgreSQL 安装目录）', en: 'Empty = auto-detect (PATH, then the PostgreSQL install dirs)' },
  'backup.programFound': { 'zh-Hans': '找到：{path}', en: 'Found: {path}' },
  'backup.programMissing': { 'zh-Hans': '没找到 pg_dump，所以还跑不了', en: 'pg_dump was not found, so it cannot run yet' },
  'backup.preview': { 'zh-Hans': '将要执行的命令行', en: 'Command line that will run' },
  'backup.run': { 'zh-Hans': '开始备份', en: 'Start backup' },
  'backup.running': { 'zh-Hans': '备份中…', en: 'Backing up…' },
  'backup.cancel': { 'zh-Hans': '取消备份', en: 'Cancel backup' },
  'backup.cancelling': { 'zh-Hans': '正在取消…（pg_dump 收到信号后停下）', en: 'Cancelling… (pg_dump stops once it gets the signal)' },
  'backup.cancelIdle': { 'zh-Hans': '没有备份在跑，没什么可取消的。', en: 'No backup is running, so there is nothing to cancel.' },
  // 跑着的读数：**三个数都是实测的**（已写字节 / 已跑秒数 / 子进程吐了多少行），没有百分比
  'backup.progressStarting': { 'zh-Hans': '正在备份：正在起 pg_dump…', en: 'Backing up: starting pg_dump…' },
  'backup.progressWaiting': {
    'zh-Hans': '正在备份：已起 pg_dump，还在连库 / 还没写出字节 · 已跑 {s} 秒',
    en: 'Backing up: pg_dump is running, still connecting / nothing written yet · {s}s elapsed',
  },
  'backup.progress': {
    'zh-Hans': '正在备份：已写 {bytes} · 已跑 {s} 秒 · 子进程已吐 {lines} 行',
    en: 'Backing up: {bytes} written · {s}s elapsed · {lines} lines from the child',
  },
  'backup.progressLast': { 'zh-Hans': 'pg_dump 最近一行：{line}', en: 'Last line from pg_dump: {line}' },
  'backup.cancelledHint': {
    'zh-Hans': '取消是强杀子进程：这次留下的半截文件已由外壳删掉，别把盘上的旧文件当成这一份。',
    en: 'Cancelling kills the child process: the half-written file from this run has been removed, so do not mistake an older file for this attempt.',
  },
  'backup.needPath': { 'zh-Hans': '先填写到哪儿，这里就会显示将要执行的命令行。', en: 'Fill in the target path and the exact command line will show up here.' },
  'backup.ok': {
    'zh-Hans': '备份完成：{bytes} 字节 → {path}（耗时 {ms} ms）',
    en: 'Backup finished: {bytes} bytes → {path} ({ms} ms)',
  },
  'backup.failed': { 'zh-Hans': '备份失败（退出码 {code}）', en: 'Backup failed (exit code {code})' },
  'backup.noCode': { 'zh-Hans': 'pg_dump 被意外终止，没有退出码', en: 'pg_dump was terminated without an exit code' },
  'backup.log': { 'zh-Hans': 'pg_dump 的输出', en: 'pg_dump output' },
  'backup.logEmpty': { 'zh-Hans': '（这次它一个字也没输出）', en: '(it printed nothing this time)' },
  'backup.logTrimmed': { 'zh-Hans': '日志只带回尾部：前面还有 {n} 个字符没显示。', en: 'Only the log tail came back: {n} characters before it are not shown.' },
  'backup.planRefresh': { 'zh-Hans': '重算命令行', en: 'Recompute the command line' },
  'backup.noConnection': { 'zh-Hans': '还没有连接数据库：备份要连的是当前连接。', en: 'No database is connected: a backup targets the current connection.' },

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
  // ── Schema 对比与同步（FR-DDL-04）────────────────────────────────────────────────
  'schema.title': { 'zh-Hans': 'Schema 对比与同步', en: 'Compare and sync schemas' },
  'schema.open': { 'zh-Hans': '结构对比', en: 'Compare schemas' },
  'schema.close': { 'zh-Hans': '关闭', en: 'Close' },
  'schema.base': { 'zh-Hans': '基准（左）', en: 'Base (left)' },
  'schema.target': { 'zh-Hans': '目标（右）', en: 'Target (right)' },
  'schema.baseHint': {
    'zh-Hans': '左 = 你想要的结构，右 = 要被改的结构；同步脚本只会把右侧改成左侧的样子。',
    en: 'Left is the structure you want, right is the one to change: the sync script only turns the right side into the left one.',
  },
  'schema.schemaName': { 'zh-Hans': 'schema', en: 'schema' },
  'schema.capture': { 'zh-Hans': '抓当前结构', en: 'Capture current structure' },
  'schema.slotEmpty': { 'zh-Hans': '还没抓', en: 'not captured yet' },
  'schema.slotFilled': { 'zh-Hans': '{schema} · {tables} 张表 · {when}', en: '{schema} · {tables} tables · {when}' },
  'schema.compare': { 'zh-Hans': '对比', en: 'Compare' },
  'schema.allowDrop': { 'zh-Hans': '允许删除（会生成 DROP）', en: 'Allow drops (generates DROP)' },
  'schema.allowDropNote': {
    'zh-Hans': '默认关闭：删表 / 删列只列出、不生成语句，跳过了什么会在下方逐条报出来。',
    en: 'Off by default: extra tables/columns are listed but no DROP is generated, and every skip is reported below.',
  },
  'schema.copy': { 'zh-Hans': '复制同步脚本', en: 'Copy sync script' },
  'schema.openInEditor': { 'zh-Hans': '在编辑器打开', en: 'Open in editor' },
  'schema.busy': { 'zh-Hans': '抓取中…', en: 'Capturing…' },
  'schema.needBoth': { 'zh-Hans': '两侧都要先抓一份快照才能对比', en: 'Capture both sides before comparing' },
  'schema.inSync': {
    'zh-Hans': '两侧结构一致：没有语句，也没有被跳过的差异。',
    en: 'Both sides match: no statements and nothing skipped.',
  },
  'schema.diffTitle': { 'zh-Hans': '差异（{n} 张表）', en: 'Differences ({n} tables)' },
  'schema.statementTitle': {
    'zh-Hans': '同步脚本（{n} 条，其中删除类 {m} 条）',
    en: 'Sync script ({n} statements, {m} destructive)',
  },
  'schema.skippedTitle': { 'zh-Hans': '跳过的差异（{n} 条）', en: 'Skipped differences ({n})' },
  'schema.status.create': { 'zh-Hans': '基准有、目标没有 → 建表', en: 'only in base → create' },
  'schema.status.drop': { 'zh-Hans': '目标多出来的 → 删表', en: 'only in target → drop' },
  'schema.status.alter': { 'zh-Hans': '两侧都有、结构不同 → 改表', en: 'both sides, structure differs → alter' },
  'schema.status.same': { 'zh-Hans': '一致', en: 'same' },
  'schema.addedCols': { 'zh-Hans': '加 {n} 列', en: '+{n} columns' },
  'schema.removedCols': { 'zh-Hans': '删 {n} 列', en: '-{n} columns' },
  'schema.alteredCols': { 'zh-Hans': '改 {n} 列', en: '~{n} columns' },
  'schema.pkDiffers': { 'zh-Hans': '主键不同（只报告、不生成）', en: 'primary key differs (reported, not generated)' },
  'schema.copyDone': { 'zh-Hans': '已复制 {n} 条语句', en: 'Copied {n} statements' },
  'schema.openedNote': {
    'zh-Hans': '同步脚本已放进编辑器（未执行）',
    en: 'The sync script was put into the editor (not executed)',
  },
  'schema.copyFailed': {
    'zh-Hans': '复制失败：外壳不给剪贴板权限（可手动选中脚本复制）',
    en: 'Copy failed: no clipboard permission (select the script and copy it manually)',
  },

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

// ── 当前语言（**单一出处**）─────────────────────────────────────────────────────
//
// 为什么要有它：`ipc.ts` 里的**浏览器旁路提示**也要双语，但它是底层模块、拿不到组件属性。
// 让语言有一个**模块级**的当前值，底层模块就能读；界面侧改语言时同步一次即可。
// 这样"语言"仍然只有一处，不是每个模块各存一份。

let current: UiLanguage = 'zh-Hans'

/** 读当前语言（底层模块用它）。 */
export function currentLanguage(): UiLanguage {
  return current
}

/** 设当前语言（界面侧改语言时调一次）。 */
export function setLanguage(language: UiLanguage): void {
  current = language
}

/** 按当前语言翻一句（**底层模块的便捷入口**，不必自己传语言）。 */
export function tNow(key: DictKey, vars?: Record<string, string | number>): string {
  return t(key, current, vars)
}

export function toggleLanguage(current: UiLanguage): UiLanguage {
  return current === 'zh-Hans' ? 'en' : 'zh-Hans'
}
