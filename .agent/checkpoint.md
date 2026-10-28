# 检查点

updated: 2026-10-29T00:46

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d` 点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-29 R47）：`verify-core` **4537 例 / 0 failures**（Core 侧未变 —— 本批 7 例在界面探针 target
  `DoyahUISnapshotTests`，不进 `core-tests` 台账）；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 前缀
  `f2b9f6e4` · 99,840 KB（R47 重出，回执「含片」已写本批；同标签前一版 `c74f6093` 回执没写本批 ⇒ 作废）。

## 下一项

**1. 台账 `FR-STD-WS-UI-011`（编辑面底色字色只用主题令牌：三处编辑面同底）** —— 先核三处编辑面
（`CodeEditorView` / `SQLEditorView` / Markdown 预览）现在是不是各自写死了底色 / 字色，再定缺口：
底色字色只能从 `Theme` 取令牌，三处同底。做成「可量的口径 + 判据」优先（同一档还有 `WS-UI-013 / 014`
两条可量出来的界面口径，一轮吃不下就按 011 → 013 → 014 的顺序做）。

其余按台账取「优先=高 → 中；同档取判据可机械跑的」（2026-10-28 R44 实测：**台账里已无「高」档的 `⬜`**）：

2. `FR-STD-WS-UI-013 / 014`（行内动作悬停出 / 对话框按钮形态）—— 两条「可量出来的界面口径」，多半只需补判据与少量视图改动；
   （`FR-STD-WS-VCS-001` 已于 R46 收口、`FR-STD-WS-UI-010` 已于 R47 收口，不再排。）
3. `FR-STD-WS-EDIT-015` / `FR-STD-WS-AI-002` 剩的一半 —— 界面入口（Core 13 / 19 例已在盘）；
4. `FR-STD-WS-TOOL-003`（DAP 调试器）—— 纵切较大，排后；
5. 人工点验项（`WS-WEB-004` 真站点、`WS-FS-004/005/006` 界面点一次、`DB-TASK-002` 逐条审批界面点一次、
   **`DB-TASK-001` 任务定义界面点一次**（存一条 → 换库执行应被拒 → 只读任务里放 `UPDATE` 应被拒）；
   **IM 通道真连一次**：填 AppID + Secret → 手机发一句话 → 桌面出该轮 → 手机会收到结论）；
6. 存量红（与 HEAD 逐条相同，非任何一片引入；见 `.agent/evidence/2026-10-28-DB-TASK-001.md` §7）。

## 已完成的片

- **R47（2026-10-29 00:42）· `FR-STD-WS-UI-010` 页签条高度与溢出** —— 先立量法：`WorkspaceTabStrip` 挂进
  **离屏 `NSWindow`** 走真布局（跑一段 runloop 再读 —— SwiftUI 布局下一跳才落，不跑拿到的是 0×0 退化帧），
  在 AppKit 视图树里找横向 `NSScrollView` 读 clip 宽 / documentView 宽 / `hasHorizontalScroller`。
  基线读数顶出两处缺口：① `showsIndicators: false` ⇒ `hasHorizontalScroller == false`，需求 ③「溢出时横向滚动条
  出现」**根本不成立**；② `Spacer(minLength: Spacing.s)` 与滚动容器同为可伸缩者，白占 12pt（页签区 134 而可用 146）。
  两处同批改掉；**没写** `.frame(maxWidth: .infinity)`（反例注入证明它是 no-op）。判据
  `TestsUISnapshot/WorkspaceTabStripOverflowProbeTests` **7 例**：窗口加宽 1020 ⇒ 页签区加宽 1020±1 · 2/5/11 个
  页签同宽（146）· 行宽 − 页签区 ≤ 276（右侧固定件 274 + 2）· 内容宽与窗口宽度无关（<2%）且随数量增长 ·
  11 个页签四档宽度都溢出且滚动条开着 · 只有 Home 时**不许**报溢出 · 4 档数量 × 4 档宽度同高 **30pt** ≤48 ·
  11 个页签内容高 == 1 个 → 不换行 · 三个玩具证明量法不是恒真。反例四段（关指示条 / 塞回 `Spacer(minLength:)` /
  塞全可伸缩 `Spacer()` / 拿掉 `ScrollView`）逐段判红后逐字节还原（`fbe45a35…`）。
  读数 `verify-core` **4537 / 0 failures（Core 侧未变，本批 7 例在 `DoyahUISnapshotTests`）**，五门全绿，
  包 `f2b9f6e4` · 99,840 KB。台账 `FR-STD-WS-UI-010` 实现 **✅** / 判据 **✅**（三条验收全机械可判，无「只能肉眼」的半边）。

- **R46（2026-10-29 00:22）· `FR-STD-WS-VCS-001` Git 只读与差异** —— 新 `Core/GitWorktreeStatus.swift`
  （porcelain 原文 ⇒ 分支 / ahead-behind / 条目：两列状态码分开判 · 冲突七码单列 · 改名带源路径 ·
  认不出的码保留并标 `.unknown` · 400 条封顶 + 如实报丢弃数 · 排序确定；分支解析与 `AgentGitFacts` 共用
  `GitBranchHeader`）+ `Core/GitUnifiedDiff.swift`（`git diff` 原文 ⇒ 逐行结构：**段边界由 `@@` 计数决定** ·
  旧/新两个游标给行号 · 末尾无换行只标属性不推游标 · 二进制/新文件/删文件/改名 · 单文件 4000 行封顶）+
  取数收一处 `App/GitWorktreeProbe.swift`（只读 · 带超时 · `core.quotePath=false` · 未跟踪走 `--no-index`
  且退出码 1 算有差异；失败四档）+ `App/GitChangesModel.swift` + 下方面板**「变更」页**
  `App/Views/GitChangesPanel.swift`（分支 / ahead-behind / 改动清单 / 逐行差异 + 「暂存·未暂存」开关 + 四档空态）。
  判据 `Tests/GitWorktreeStatusTests` **13 例** + `Tests/GitUnifiedDiffTests` **11 例**，反例八段各判红后逐字节还原；
  读数 `verify-core` **4537** / 0 failures（4513 → +24），五门全绿，包 `1b82fc9b` · 99,840 KB。
  台账 实现 🟡（差人工点一次：选一个有改动的仓库 → 「变更」页列分支与文件 → 点文件出逐行差异）/ 判据 ✅。

- **R45（2026-10-28 23:58）· `FR-STD-WS-NAV-012` 静态检查结果上屏** —— 新 `Core/DiagnosticMarks.swift`
  （投影：越界丢弃 / 零长按 1 / 跨文末截断 / 同范围同文案去重 / 顺序确定；命中取最窄、同窄错误优先；`hoverText` = 检查器
  message + 位置）+ `SQLEditorView.apply` 的下划线改由投影画（画线与命中同一份）+ `SQLTextView` 即时悬浮说明
  （`NSTrackingArea` + `draw` 补一块，弃系统 tooltip 的秒级延迟）+ 标记换掉即撤旧说明；
  **同批修好存量**：`Tests/SQLLinterTests` 花括号错位使 `testRealtimeScanLimitBoundary` 变成另一个用例里的局部函数
  （从未执行）⇒ 恢复。判据 `Tests/DiagnosticMarksTests` **9 例**，反例七段各判红后逐字节还原。
  读数 `verify-core` **4513** / 0 failures（4503 → +10），五门全绿，包 `512a2873` · 99,072 KB。
  台账 实现 🟡（差人工把鼠标停到虚线上看一眼）/ 判据 ✅。

- **R44（2026-10-28 23:35）· `FR-STD-DB-TASK-001` 任务定义可保存复用** —— 新 `Core/SQLTaskDefinition.swift`
  （① 定义实体：连接 / 目标库 / 读写模式（缺省只读）/ 影响行数上限（选填 >0）/ 是否需审批（缺省真）+ `issues()` 一次列全；
  ② `SQLTaskStore`（`sql-tasks.json`）**唯一写入口**两条拒：定义不完整 · 同名不同 id（同名同 id 是原地改、创建时刻跟
  第一次保存走）；③ `SQLTaskGuard.check` 顺序 = 定义完整性 → 连接不符 → 目标库不符 → 只读任务里的写语句 →
  可写任务遇只读连接 → 上限（没带 / 放宽）→ 审批；`rowVerdict` 执行后按实测行数判，`exceeded` 与 `unmeasured` 分开）
  + `AppState`（启动读回 / 存盘即绑定 / 载入时一并切连接与库 / 关页签解绑）+ `executeQuery` 在**建连接之前**过判定
  （拒绝不进确认流程）+ 工具栏「任务」菜单 + `App/Views/SQLTaskSheet.swift` + 语言键 20 个中英齐；
  判据 `Tests/SQLTaskDefinitionTests` **21 例**，反例五段各判红后逐字节还原。
  读数 `verify-core` **4503** / 0 failures，五门全绿，包 `9968e9e8` · 98,996 KB。台账 实现 🟡（差人工点一次）/ 判据 ✅。
  **同标签重出两次**：23:33 那一版回执未含本批文字（前缀 `7da832e3`）⇒ 作废不复用，只认 `9968e9e8`。
- **R43（2026-10-28 23:15）· `FR-AGT-LINK-CHAN-003` 官方 REST 外发（收尾片）** —— 回话不再糊本侧帧：
  新 `Core/AgentIMOutboundSend.swift`（私聊 `POST /v2/users/{openid}/messages` / 群
  `POST /v2/groups/{group_openid}/messages`；`openid` 是外部输入 ⇒ 先过窄放行集再拼路径；
  被动回复 `msg_id` + `msg_seq`（同一 `msg_id` 下递增、**同一条结果重发复用同一序号**，落盘
  `im-reply-seq.json`）；结局六档（401/403/429/5xx/2xx 非 JSON 仍算发出/其余原样带码）；
  `AgentIMOutboundDrain` 只补官方条目、发成才 ack）+ 队列条目带 `target` / `replyToMessageID`
  + 传输层 `replayPending` 改走 `relayPending()`（官方帧不再糊上网关）+ `AppState` 交付口一处岔
  与连上补发 + 面板多一行外发人话；判据 `Tests/AgentIMOutboundSendTests` **18 例** +
  `Tests/AgentIMInboundRunTests` 17 → **18 例**，反例四段各判红后逐字节还原。
  读数 `verify-core` **4482** / 0 failures，五门全绿，包 `b953fcb1` · 98,604 KB。
  台账 实现 🟡（差真凭据与端到端点验）/ 判据 ✅。**第四十一批那句「外发帧 `op=reply`」自本批起只服务自建中继。**
- **R42（2026-10-28 23:03）· `FR-AGT-LINK-CHAN-003` ★0 凭据口径纠正** —— 地址不再由用户填：
  新 `Core/AgentIMQQProvisioning.swift`（环境两档 → 取 token → 取网关 → 取不到用该环境固定地址 → 到期前刷新 / 单飞 /
  失败 401·403·429·5xx·非 JSON·缺 token 分档可读 → 官方 op 码 Identify 2 / 心跳 1 带 seq / 恢复 6 / Hello 10 /
  dispatch 解成入站任务）+ `Platform/macOS/URLSessionAgentIMQQClient.swift`（REST 真实现 + `AgentIMQQClients` 工厂）；
  配置面四样 → **三样**（环境 / AppID / Secret），旧 `gatewayURL` 读成自建中继（迁移）；面板删地址格、加环境选择器、
  自建中继降为高级项、「去 QQ 开放平台」按钮、画出程序取到的地址；传输层加 `AgentIMGatewayHandshake`（nil = 自建中继原样）。
  判据新 `Tests/AgentIMQQProvisioningTests` 18 例 + `Tests/AgentIMSettingsTests` 26 → 27 例；反例三处注入各判红后逐字节还原。
  同批把 `check-network-egress` 从 8 处不合规清到 0（补登两条 IM 出网面 + 修陈旧登记 + 装配缝改走工厂）。
- **R41（2026-10-28 22:32）· `FR-AGT-LINK-CHAN-003` ★2 入站任务真跑 + 结果推回** —— 新 `Core/AgentIMInboundRun.swift`
  （策略三档 → **去重**（平台消息号落盘，保 500 条；QQ 重投只跑一遍）→ 建任务（同一 chat 同一条会话号）→ 跑（闭包注入，
  接界面 `AgentChatModel` ⇒ 审批照旧）→ 回话入 `AgentIMResultQueue` → 推 → **推成才 ack**；跑抛错也回「没跑成」、
  停在审批上只回「等桌面批准」、长结论 1500 字截断指路；外发帧 `op=reply`，真 op 码未对齐记 blocked）
  + `AppState` 接线（结果队列在 `start()` 前接上、同一时刻只跑一条、面板分开报「跑过几轮 / 推回几条」）
  + `AgentChatModel.adoptSession`（两个 chat 不共用上下文）+ `Tests/AgentIMInboundRunTests` **17 例**（反例六段各判红）。
  读数 `verify-core` **4443** / 0 failures，五门全绿，包 `82ef35ce` · 98,016 KB。台账 实现 🟡（差真网关与人工点验）/ 判据 ✅。
- **R40（2026-10-28 22:20）· `FR-AGT-LINK-CHAN-003` IM 通道配置面** —— 新 `Core/AgentIMSettings.swift`
  （地址只认 `ws://` / `wss://`；标识规则与 64 上限；问题一次列全；`AgentIMReadiness` 四样一处 ——
  地址非空但认不出也算缺；`AgentIMStatusKind` 状态行四档**以配置为先**（传输层说在线也不许画绿）；
  `AgentIMInboundPolicy` 三档；`AgentIMConnectivityProbe` 四档，**只有收到一帧才算通**）+ 配置文件扩为
  「AppID + 网关端点 + 机器人标识 + 接收任务」（字段全可选 ⇒ 老文件仍能读；只改 AppID 不冲掉配置面）+
  面板那一节补全并接真 WebSocket 通路（`AppState` 持传输层，面板关掉不掉线）+ 判据 `Tests/AgentIMSettingsTests`
  **26 例**（反例五段：配齐判定不看 Secret / 状态行不先看配置 / 入站不看开关 / 探针把 open 当通 / 只改 AppID 冲掉配置面）。
  **未验证**：真网关 URL 与 AppID/Secret（缺）、面板三枚按钮的人工点验、入站任务真跑（★2）。
- **R39（2026-10-28 21:58）· `FR-STD-WS-EDIT-021` 自动缩进与智能粘贴** —— 新 `Core/AutoIndent.swift`
  （① 回车继承当前行**实际**缩进（`\t` / 不规则缩进原样带走）② `{` `(` `[` 之后 +一级 ③ `} ) ]` 打头的行 −一级
  （减到 0 为止；`} else {` 先退再进回到本行那一级）④ 行终止符跟当前行（`\r\n` 文档不插裸 `\n`）
  ⑤ 夹在**真成对**的括号中间回车 ⇒ 闭合符挪到下一行、新行落内层 ⑥ 四种「不动」⇒ `nil` 交还系统
  ⑦ 粘贴多行剥外来公共缩进 + 接上下文那一级（**首行不叠加**、空白行不留尾随空格、行尾归一）；单行不重排）
  + **两个编辑面**接线（`CodeTextView.insertNewline/paste` → `applyEditPlan`；`SQLTextView.insertNewline/paste` → `applyAutoIndentPlan`）
  + `Tests/AutoIndentTests` **29 例**（反例四段各判红：① 崩溃 rc≠0 / ②③④ 各 3 红）。
  读数 `verify-core` 4400 / 0 failures，五门全绿，包 `38ce7061` · 97,584 KB。台账 实现 🟡（差人工按一次回车 / 粘一次多行）/ 判据 ✅。
- **R38（2026-10-28 21:45）· `FR-STD-DB-TASK-002` 高危任务逐条审批** —— 新 `Core/HighRiskTaskApproval.swift`
  （`plan` 用执行侧同一个 `StatementSplitter` 拆成一条语句一行：序号 / 原文 / 首词类别 / 目标库逐条各带；
  `Impact` 三档 `pending` / `rows(N)` / `unavailable(原因码)` —— 缺省 `pending`，**估不出来不冒充 0 行**；
  `outcome(for:decision:)` 唯一决策口：批准 ⇒ 整批原序、拒绝 ⇒ **空表**；指纹 FNV-1a 64 逐处敏感，零中文字面量）
  + 审批单逐条呈现（`AgentApprovalSheet` 每条一行，多条时不显示整批合计）+ `AppState.estimateHighRiskPlan` 逐条问优化器
  + 拒绝状态独立（`TaskRunRecord.Status.rejected`「已拒绝」，与「已跳过」分开；`skipDataTaskRun` 删除）
  + `Tests/HighRiskTaskApprovalTests` **18 例**；读数 `verify-core` 4371 / 0 failures，五门全绿，包 `503bdf6a` · 97,560 KB。
  台账 实现 🟡（差人工点一次）/ 判据 ✅。
- **R37（2026-10-28 21:32）· `FR-STD-WS-EDIT-009` 移行与复制行** —— 新 `Core/LineMoveEdit.swift`（行拆「内容 + 终止符」，
  内容按行搬 / 终止符按位置留 ⇒ `\r\n` 与「末行无终止符」都不粘连；光标按「那一行搬到哪」映射；首行上移 / 末行下移 / 空文档 `nil`；
  `⇧⌥↓` 副本紧随原行、选区留在原件）+ `CodeTextView.keyDown` 拦 `⌥↑`/`⌥↓`/`⇧⌥↓` → `applyEditPlan` + `Tests/LineMoveEditTests` 22 例；
  读数 `verify-core` 4353 / 0 failures，五门全绿，包 `92efb40c` · 97,376 KB。台账 实现 🟡 / 判据 ✅（差人工按一次）。
- **R36（2026-10-28 21:10）· `FR-STD-WS-EDIT-020` 括号匹配高亮** —— 新 `Core/BracketHighlight.swift`
  （`plan(in:selection:)`：光标紧邻括号 ⇒ 亮那一半 + 配对者两段；三档角色 `matched` / `unmatched` / `truncated`
  各钉一个主题令牌；有选中不亮；超 `scanLimit` 报「太远」而不是「不匹配」）+ `Theme.nsColor(_:alpha:)` 重载
  （alpha 揉进深浅两套值 —— `withAlphaComponent` 会把 `NSColor(name:)` 的动态性塌成一套）+ 编辑器接线
  （`refreshBracketHighlight` 涂/清唯一落点、选区一变重算、整篇重涂后补回）+ `Tests/BracketHighlightTests` 12 例；
  读数 `verify-core` 4331 / 0 failures，五门全绿，包 `fe8c6662` · 97,328 KB。台账 实现 🟡 / 判据 ✅（差人工点一次）。
- **R35（2026-10-28 20:52）· `FR-STD-WS-FS-004/005/006` Explorer 文件操作收口** —— 新 `Core/WorkspaceFileUndo.swift`
  （**一次撤销**：撤销新建 → 再移进废纸篓 / 撤销删除 → 从废纸篓搬回 / 撤销改名 → 改回原名；原位置被占、废纸篓副本消失、
  跨工作区都如实拒）+ `WorkspaceFileOperations.restore` 与 `trashCopyMissing` + `WorkspaceTabSet.retargeting`
  （改名后页签路径与标题跟随、目录改名整棵子树跟、`a.txt2` 不误伤、脏内容与 `id` 不动）+ 界面三处接线
  （新建文件自动打开到第 1 行 / 改名提交页签跟随 / 结果行撤销按钮 `workspace-undo`）+ `Tests/WorkspaceFileUndoTests` 14 例；
  读数 `verify-core` 4319 / 0 failures，五门全绿，包 `d7cb69e9`。台账三条 实现 🟡 / 判据 ✅（差人工点一次）。
- **R34（2026-10-28 20:41）· `FR-STD-WS-WEB-004` Core 面 + 引擎接线** —— 新 `Core/BrowserIdentity.swift`
  （确定性 UA 不带产品名 / 站点存储缺省持久化 / 弹窗必有可见结果 / 证书三类失败必问人 / 用常规浏览器打开的出口）
  + `Platform/macOS/WebKitBrowserEngine.swift` 接线（`customUserAgent`、`applicationNameForUserAgent = nil`、
  `WKUIDelegate` 弹窗、server-trust 挑战）+ `Tests/BrowserIdentityTests` 10 例 + 平台 3 例；
  读数 `verify-core` 4305 / 0 failures，五门全绿，包 `5c30c03b`。台账 实现 🟡 / 判据 ✅（差真站点点验）。
  **口径变更**：站点存储缺省 非持久化 → 持久化（由头见引擎注释 ③ 与证据文件）。
- **R1（2026-10-28 20:15）· 在途件收尾** —— 前一会话 10-27 06:58 ~ 10-28 18:59 落盘未提交的 42 改 + 26 新文件，复核（verify-core 4276/0 failures + 五门全绿）后补提交 `893cc774`，未改其一字。
- **R1（2026-10-28 20:13）· `FR-STD-WS-AI-002` Core 面** —— `Core/WishStaging.swift`（暂存面：只动内存 / 清单 + 差异 / 验证没跑通标「没跑通」且默认不许验收 / 验收才写盘一次）+ `Tests/WishStagingTests.swift` **19 例**；同批给 `AgentWriteBatchRevert` 补 `record(_ snapshot:)` 与「自己删的能还原」分支。读数：`verify-core` 4295 / 0 failures，反例两次各判红（4 红 / 1 红）。台账 `FR-STD-WS-AI-002` 判据 `✅`、实现 `🟡`（差界面入口）。
- `T0.1`~`T5.2`（2026-10-24/25，plan.yaml 时代，历史见 `.agent/evidence/`）。

## 证据

- `.agent/evidence/2026-10-29-WS-UI-010.md`（已有面核查表 + 缺口实测读数 + 落法 + 命令原文 + 读数 + 反例四段 + 口径取舍 5 条 + 未覆盖 4 条）
- `.agent/evidence/2026-10-28-DB-TASK-001.md`（已有面核查表 + 落法 + 命令原文 + 读数 + 反例五段 + 口径取舍 5 条 + 存量红对照 + 未验证项）
- `.agent/evidence/2026-10-28-WS-EDIT-021.md`（已有面核查表 + 落法 + 命令原文 + 读数 + 反例四段 + 口径取舍 5 条）
- `.agent/evidence/2026-10-28-DB-TASK-002.md`（已有面核查表 + 命令原文 + 读数 + 反例四段 + 存量红对照）
- `.agent/evidence/2026-10-28-WS-EDIT-009.md`（命令原文 + 读数 + 反例三段 + 口径取舍）
- `.agent/evidence/2026-10-28-WS-FS-004-005-006.md`（缺口表 + 读数 + 反例三段 + 存量红对照）
- `.agent/evidence/2026-10-28-WS-WEB-004.md`（命令原文 + 读数 + 反例三段 + 口径变更由头）
- `.agent/evidence/2026-10-28-WS-AI-002.md`（命令原文 + 读数 + 反例三段）
- 更早的片见 `.agent/evidence/2026-10-2*.md`。

## 未验证项

- `FR-STD-WS-UI-010` 的**观感**没人看过（不在那条验收里，但如实登记）：滚动条出现的位置与外观、页签之间的间距是否好看；
  另两条未验：macOS「始终显示滚动条」偏好下 `showsIndicators: true` 是否挤压页签区、触控板横滑手势（`NSScrollView` 既有行为）。
- `FR-STD-WS-UI-010` 的判据里 `maximumTrailingOccupancy = 276` 是「右侧固定件宽度」的实测口径（274 + 2）——
  **往页签条右侧再加按钮要同批改这个数**，否则那条断言会红（这是有意的：它量的是「页签区是唯一伸缩者」）。

- `FR-STD-DB-TASK-001` 的**界面面**一次都没人手点过（工具栏「任务」菜单 / 保存表单四格 / 换库执行应被拒 /
  只读任务里放 `UPDATE` 应被拒 / 上限 1 行跑 3 行应报超限）⇒ 实现 🟡，等人工点一次。
- `FR-STD-DB-TASK-001` 的**上限与事务的关系**没定口径也没实测：超限只当场报，**不回滚**已执行的部分
  （要回滚得先有「上限与事务」的拍板，本片不擅自发明）。
- `Core/SQLTaskDefinition.swift` 的拒绝 / 审批理由仍是 Core 直接产出的中文（与 `ExecutionSafety` 同族），
  未走语言表 ⇒ `check-core-localization` 棘轮 A 本片 **+1 文件 / +26 行**（干净树对照：HEAD 89 / 836 → 本片 90 / 862；
  基线 74 / 748 早已落后，**未上调**）。
- `FR-AGT-LINK-CHAN-003` 的**真发一条**（R43 之后只差凭据）：要 AppID + Secret + 一个真人手机，
  `手机发一句话 ⇒ 桌面出该轮 ⇒ 手机收到结论`。被动回复的时间窗 / 次数上限**本片不擅自定义**（未实测）。
- `FR-AGT-LINK-CHAN-003` ★2 的**真网关那半**：缺 AppID/Secret ⇒ 握手口径与官方 `op` 码按文档落地但**没在真网关上跑过**；
  入站链路的判据用假 socket / 闭包跑通，**不等于真连过**。（~~外发帧的 `op` 名是本侧约定~~ —— **R43 作废**：
  官方路径已改走 REST 两条端点，本侧帧只服务自建中继。）
- ★2 的**界面面**待人工点验：在设置面板填齐四样并连接后，从手机发一句话 ⇒ 桌面对话页签应出现这一轮、
  含写/执行类动作应弹审批（点了才动）；手机那头应收到结论；关掉「接收任务」后应一条都不进。
- `FR-STD-WS-EDIT-021` 的**手感面**只能人判：在编辑器里真按一次回车（缩进行应保持缩进 / `{` 后应多一级 /
  `}` 行应回退 / `{}` 中间应按出三行）、真粘一次多行（应剥外来缩进、按上下文对齐、空白行不留尾随空格）⇒ 实现 `🟡`。
- `FR-STD-DB-TASK-002` 的**界面面**已接成逐条呈现但没人手点过（覆盖写入任务应列出 `TRUNCATE` + `INSERT` 两条、
  目标库与各自行数分开、点拒绝后执行历史读作「已拒绝」）⇒ 实现 🟡，等人工点一次。
- `check-core-localization.py` **存量红**（本批用干净树 `git worktree add /tmp/wt-r38 HEAD` 对照：HEAD 就是 88 文件 / 834 行 vs 基线 74 / 748，
  与本片无关）；本批 +1 行（`Core/DataTask.swift` 的「已拒绝」），基线**未上调** —— 棘轮只许降。
- `FR-STD-WS-EDIT-009` 的**界面面**已接线但没人手按过（`⌥↑` / `⌥↓` / `⇧⌥↓` 三个键、⌘Z 是否一步回去）⇒ 实现 `🟡`，等人工按一次。
- 台账第 281 行（`FR-AGT-UX-CONV-012` 备注格）里有一处 `⟪HERMES-CONTEXT-COMPRESSION…⟫` 占位串**已入库**（HEAD 就有，
  上一轮工具调用写坏的），无门禁覆盖 —— 属别人那片的历史缺陷，本片不动，做「清号」片时一并修。
- `FR-STD-WS-FS-004/005/006` 的**界面面**已接线但没人手点过（悬浮菜单三枚 / 新建后自动打开到第 1 行 / 改名后页签标题 / 结果行撤销按钮）⇒ 实现 `🟡`，等人工点一次。
- `FR-STD-WS-AI-002` 的界面面（许愿输入框 + 差异视图 + 验收按钮）未做 ⇒ 实现 `🟡`，等下一片。
- 存量红（R35 用 `git worktree add /tmp/wt-r35 HEAD` 干净树对照过，**原因与条数相同** ⇒ 与本片无关）：
  `check-req-ids` / `check-plan-coverage`（正文有、索引无 5 条 `FR-AGT-KNOW-MEM-006`~`-010`；索引有、台账无 `FR-STD-WS-HELP-002`）·
  `check-board-parity`（`.build/derived/任务清单-按平台.md` 是 10-27 的派生件，重生成即可）· `check-doc-layout`（三书九轮自审 12 条）·
  `check-core-localization`（`Core/AgentSQLStatementJudge.swift:90` 的 `you are now` 未登记）· `check-literal-language`（`Core/AgentNotifyChannel.swift` 2 处写死语言）·
  `check-core-portability`（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/…`）。
- 台账 §3/§4/§5 节标题里的旧基线计数（74 / 174 / 75，实测 🟡 94 / ⬜ 123）是**早于本轮**的漂移、无门禁覆盖 —— 待「清号」片一次收口（R35 只在证据文件登记，未改）。
- `verify-all.sh`（十八项）未整跑：上述存量红会挡它，需先清红再整跑。
- `FR-STD-WS-WEB-004` 站点存储「持久化」的口径变更仍等主人点头（要保留非持久化就说一声）。
