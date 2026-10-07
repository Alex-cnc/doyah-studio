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
  // IPC 浏览器旁路提示（不是产品路径，但**也要双语**：切英文时不该留中文）
  'ipc.bypass.db': { 'zh-Hans': '浏览器旁路没有真库', en: 'The browser fallback has no real database' },
  'ipc.bypass.workspace': { 'zh-Hans': '浏览器旁路没有工作区', en: 'The browser fallback has no workspace' },
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
