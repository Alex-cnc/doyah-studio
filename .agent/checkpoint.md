# 检查点

updated: 2026-10-28T21:32

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d` 点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-28 R37）：`verify-core` **4353 例 / 12 skipped / 0 failures**；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 前缀 `92efb40c` · 97,376 KB（2026-10-28 21:20 出）。

## 下一项

按台账取「优先=高 → 中；同档取判据可机械跑的」：

1. `FR-STD-DB-TASK-002`（**优先=高**；需求正文在《需求规格说明书》§「高危任务执行前逐条列出」= 逐条语句 + 目标库 + 预估影响范围，
   前置审批、未确认不发、拒绝留痕；`Core/AgentApprovalGate` 与审批单「≈N 行」已在盘 —— **先核已有面再定缺口**，别重做）。
   ⚠️ 台账该行「一句话」是 `—`（占位未填，行在台账 §「补登记」段），正文一律以需求书为准；
2. `FR-STD-WS-FS-003` 复核（行内悬浮菜单已在盘；**拖拽移动 / 在终端中打开**未核验）；
3. `FR-STD-WS-EDIT-015` / `FR-STD-WS-AI-002` 剩的一半 —— 界面入口（Core 13 / 19 例已在盘）；
4. `FR-STD-WS-VCS-001`（Git 只读与差异）/ `FR-STD-WS-TOOL-003`（DAP 调试器）—— 优先=中，纵切较大，排后；
5. 人工点验项（`WS-WEB-004` 真站点、`WS-FS-004/005/006` 界面点一次）；
6. 存量红（非任何一片引入，见「未验证项」），做「清红」片时一并处理。

## 已完成的片

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

- `.agent/evidence/2026-10-28-WS-EDIT-009.md`（命令原文 + 读数 + 反例三段 + 口径取舍）
- `.agent/evidence/2026-10-28-WS-FS-004-005-006.md`（缺口表 + 读数 + 反例三段 + 存量红对照）
- `.agent/evidence/2026-10-28-WS-WEB-004.md`（命令原文 + 读数 + 反例三段 + 口径变更由头）
- `.agent/evidence/2026-10-28-WS-AI-002.md`（命令原文 + 读数 + 反例三段）
- 更早的片见 `.agent/evidence/2026-10-2*.md`。

## 未验证项

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
