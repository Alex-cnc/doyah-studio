## ★ 顶部条目（优先于常规取活，不得顺延、不得再问）

**★0 · IM 通道凭据口径纠正 —— ✅ 已落地（R42，2026-10-28），本条关闭，不得重复执行**

- **主人的话**（留档，口径本身有效）：「既然指明了是 QQ 通道，为什么还要用户填 wss 地址？按道理只要 QQ 扫码或者输入机器人 AppID 和 AppSecret 就可以啊。」
- **已做**：`Core/AgentIMQQProvisioning.swift`（环境两档 · 取 token · 取网关 · 取不到用该环境固定地址 · 到期前刷新 / 单飞 ·
  401·403·429·5xx·非 JSON·缺 token 分档可读 · 官方 op 码 Identify 2 / 心跳 1 带 seq / 恢复 6 / Hello 10 / dispatch 解帧）·
  配置面四样 → 三样（环境 / AppID / Secret，`gatewayURL` / `botIdentifier` 作废）· 旧 `gatewayURL` 读成自建中继（迁移）·
  面板删地址格 / 加环境选择器 / 自建中继降高级项 / 「去 QQ 开放平台」按钮（**不做运行时扫码**）/ 画出程序取到的地址与 token 尾 4 位 ·
  传输层 `AgentIMGatewayHandshake`（nil = 自建中继原样）· 判据 `Tests/AgentIMQQProvisioningTests` 18 例 + `AgentIMSettingsTests` 27 例。
- **仍差**（不是本条的重复项）：真 AppID + Secret 与一次端到端点验（记 blocked）。
- **官方外发**（`POST /v2/users/{openid}/messages`）**已做**（R43 第四十三批 `Core/AgentIMOutboundSend.swift`）——
  上一版这条写「尚未做」，本行更正（旧说法作废）。

**★1 · IM 通道的「真配置界面」+ 判据收口（`FR-AGT-LINK-CHAN-003`）—— ✅ 已落地，本条关闭，不得重复执行**

- **2026-10-28 第四十批已做**：配置面 `Core/AgentIMSettings.swift`（地址只认 ws/wss · 标识规则 · 配齐判定四样一处 ·
  状态行四档**以配置为先** · 入站策略三档 · 测试连接四档**只有收到一帧才算通**）+ 配置文件扩为四字段（老文件仍能读、
  只改 AppID 不冲掉配置面）+ 面板那一节补全（网关端点 / 机器人标识 / AppID / Secret 尾 4 / 状态行 / 接收任务开关 /
  保存·测试连接·连接·断开·清除）+ 真 WebSocket 通路接线（`AppState` 持传输层）；判据 `Tests/AgentIMSettingsTests` **26 例**，
  反例五段各判红一次。**「传输层未实现」那句已作废（语言表键删除）。**
- **仍差（不是本条的重复项，见 ★2）**：入站任务真跑 + 结果推回；真连 QQ 需主人给网关 URL 与 AppID/Secret。

**★2 · IM 通道「入站任务真跑 + 结果推回」（`FR-AGT-LINK-CHAN-003` 的后半）—— ✅ 已落地（R41），本条关闭，不得重复执行**

- **2026-10-28 第四十一批已做**：`Core/AgentIMInboundRun.swift`（策略 → 去重（平台消息号落盘）→ 建任务 →
  跑（闭包注入，接界面 `AgentChatModel`，**审批照旧**）→ 回话入队 → 推 → **推成才 ack**；抛错也回「没跑成」、
  停在审批上只回「等桌面批准」、长结论截断指路）+ `AppState` 接线（结果队列在 `start()` 前接上、同一时刻只跑一条、
  面板分开报「跑过几轮 / 推回几条」）+ `AgentChatModel.adoptSession`（两个 chat 不共用上下文）；判据
  `Tests/AgentIMInboundRunTests` **17 例**，反例六段各判红。
- **仍差（外部依赖，不是本条的重复项）**：真 QQ 网关 URL + AppID/Secret ⇒ 握手口径与官方 `op` 码对齐（记 blocked）；
  面板与手机的端到端人工点验一次。

**★ 区已清空**：下一条活按台账取（`FR-STD-*` 里实现 `⬜`／`🟡`，优先=高 → 中；同档取判据可机械跑的）。
**R62（2026-10-29）已把 `FR-STD-WS-FS-010`（多工作区切换）接通**：此前工作区**同时只有一个**（`choose()` 先 `store.removeAll()` 再存一条，
换文件夹 = 把上一个从授权表删掉；首页「最近打开的工作区」只展示、点不动）。`Core/WorkspaceRegistry.swift` 一张表收四条口径：
**同一目录只登记一条**（去重按解析出的路径，活动那条优先留下 —— 否则重选一次当前目录会把活动状态随去重丢掉）· **同一时刻只有一个活动**
（`activeID` 一格，`Entry` 不许自带 `isActive`）· **不可用 ≠ 不可见**（目录没了 / 没权限的仍留在表里并写明理由，但 `decision(for:)` 拒绝切过去；
`alreadyActive` 是**什么都不做**，重取一次授权 = 树整棵塌一次）· **容量 8、永不淘汰活动那条**。接线：`WorkspaceStore` 持表 + `switchTo`
（**先确认真能取用再动活动**，失败就留在原工作区只说理由）+ 活动 id 落盘（老版本无记录 ⇒ 第一条当活动）；`choose()` 改成按表算出的 id 落盘。
界面两处**同一份列表、同一个动作**：文件树标头 `WorkspaceSwitchMenu` + 首页 `WorkspaceKnownRow`（原来那三行读的是 `tabs.history.workspaces` ——
流水不是授权表，已换掉）。实现 **🟡**（差人工点一次）/ 判据 **✅**（16 + 5 例；反例五段各判红后逐字节还原）；包 `594b301e（06:22:20）`，
同标签 06:21:52 那份 `1fc685cd`（含片补本条之前）与 06:04:40 那份 `dafed86a` 作废。明细见 `.agent/evidence/2026-10-29-FS-010.md`。
**R63（2026-10-29）陈旧标记归正 8 条**（只翻判据列 🟡 → ✅，**零新增用例、Core 总数 4825 不变、零源码改动 ⇒ 未重建，包沿用 `594b301e`**）：
`FR-STD-WS-NAV-004`（`InlineGhostCompletion` 18 + `InlineGhostSQL` 12 + `InlineGhostPath` 16 = 46 例）· `FS-009`（`WorkspaceChangeScope` 9）· `EDIT-013`（`WorkspaceHeaderSearch` 12）· `UI-003`（`WorkspaceClosePolicy` 10）· `EDIT-006`/`EDIT-007`（同一份 `MarkdownEditing` 18）· `EDIT-019`（`CodeAutoPairing` 21）· `EDIT-008`（`CodeCommentToggle` 12），九个 `--filter` 全 `Executed N … 0 failures`。三处旧数字按实测改登记（30 条 ⇒ 12 例 / 8 例 ⇒ 10 例 / 17 例 ⇒ 18 例）；`FS-009` 实现列 ✅ → 🟡 **如实下调**（备注自己写着「剩：界面点验」）。分族 ⇒ 实现 126/81/6 · 判据 158/48/6/—1（= 213）。明细 `.agent/evidence/2026-10-29-stale-marks-R63.md`。
**R61（2026-10-29）已把 `FR-STD-WS-NAV-005`（片段模板 / snippets）接通**：骨架是数据、判定是纯函数 ——
`Core/SnippetTemplate.swift` 三件纯事：**解析**（`$1` / `${1:默认}` / `$0`；`$$`·`\$` 转义；认不出的 `${…` 原样落字符）·
**触发**（整词、大小写不敏感、后面还接词字符就拒、**触发词范围**落在字符串 / 注释里就拒 —— 判词不判光标：`'select'` 与 `-- select` 那两种现场光标都可能刚好在掩码外一格）·
**会话**（落点用文档绝对坐标，`noteEdit` 随编辑平移；跨落点的改动如实作废、Tab 回缩进）。片段表住 `CodeLanguageDefinitions.snippets`
（SQL `select`/`join`/`insert`/`ctable` · Markdown `table`/`task` · python/swift/js/ts/shell 若干）。接线两个编辑器：
`insertTab` 次序写死 **会话 → 灰字 → 片段 → 缩进**（`CodeTextView` 与 `SQLTextView` 各一遍），`shouldChangeText` 回报编辑。
同批掩码收成一份 `CodeLexer.protectedSpans`（折叠改为转发）。实现 **🟡**（差人工点一次）/ 判据 **✅**（23 + 5 例；反例六段各判红后逐字节还原）；
包 `dafed86a（06:04:40）`，同标签 05:45:45 那份 `50553049` 作废。⚠️ 同批**改写**了 `Tests/IndentProfileTests` 里「Tab 三个动作」那条锚点（现在是四分支、次序写死，理由写在该用例注释里）—— 不是放宽。
明细见 `.agent/evidence/2026-10-29-NAV-005.md`。
**R60（2026-10-29）已把 `FR-STD-DB-META-006` ③（**加载失败在该节点可读错误** **并可重试**）补上**：
此前失败那一行只有一句红字（`ErrorPresenter` 的人话），界面上**没有任何入口** —— 用户唯一出路是自己折起来再展开，
而这件事界面上一个字都没提。`Core/ObjectTreeRetry` 一处收口「出不出入口」与「点了做什么」：四档不出
（`inFlight` 在途 / `notExpanded` 收起 / `noFailure` 空态 / `alreadyLoaded` 已缓存）· 计划 `steps` 顺序即口径
（**先清旧错误再取数**）· `cachedCount: Int?` 分得清「加载过 0 条」与「从没加载过」。接线：失败分支传入口
（**文字**「重试」按钮，带 help / 无障碍标签）+ `retryAction` 只读判定 + `performRetry` 走与手点同一条 `loadChildren`。
实现 **🟡**（差人工点一次）/ 判据 **✅**（11 + 5 例；反例六段各判红后逐字节还原）；包 `50553049（05:45:45）`，
同标签 05:45:26 那份 `164a7fe0` 作废。明细见 `.agent/evidence/2026-10-29-META-006.md`。
**R59（2026-10-29）已把 `FR-STD-WS-EDIT-015`（整批撤回）接通**：账仍是唯一前像来源（`agentEditJournal.before`）—— `snapshots(from:)` → `plan`（同一路径合并时**前像取最早、摘要取最新**；原来取最后一次写，一批里改两次就只撤掉一半，与「一次撤回把所有改动还原」相反）→ `inverse(of:reader:)` 出反向批次（冲突步不生成）⇒ 撤回本身可再撤回 → `AgentBatchRevertReceipt` 留痕（计数取自 `apply` 的读数）。接线：`AppState.revertAgentBatch` / `redoAgentBatchRevert`（路径过沙箱、越界抛错不写盘、撤完同步正开着的页签）+ 对话页输入框上方一行「这一轮 Agent 改了 N 个文件 · 整批撤回 / 已撤回 N 个（M 处没动）· 撤销这次撤回」+ 语言表 6 键中英齐。实现 **🟡**（差人工点一次：① 让 Agent 改两个文件点「整批撤回」，两个都应回到改前；② 撤前手工再改其中一个 ⇒ 那个读「没动」且内容一个字不动；③ 点「撤销这次撤回」应回到 Agent 写完那一版）/ 判据 **✅**（`Tests/AgentBatchRevertTests` 9 例 + `Tests/AgentBatchRevertSourceTests` 5 例，反例四段各判红后逐字节还原）；包 `a120a874（05:28:14）`，同标签 05:25:26 那份 `20adc61a` 作废。明细见 `.agent/evidence/2026-10-29-EDIT-015.md`。
⚠️ 同批把第五十七批留下的 8 条 `check-format-arguments` 真红修干净：四处回执文案从「模板串交给 Core 去格式化」改成**值格式闭包**（`{ L(.receiptSeconds, $0) }`）—— 模板与实参回到同一句，判 B 不再是假红、A/A′ 开始真的检查这四句；形状台账按实测对齐（+5 形状 / 3 处处数跟版 / 预算 170 → 188，理由写进 note）。
下一条活（R62 核过：高档与中档都只剩「人工点验 / 陈旧标记归正」）⇒ ✅ **① `FR-STD-WS-NAV-004` 陈旧标记归正已落地（R63：同类 8 条一并归正、只翻判据列不加用例，本条关闭、不得重复执行）**；② 低档里还剩两个真 ⬜：`FR-STD-WS-NAV-006`（悬停文档 + 跳定义，词法级）/ `FR-STD-WS-EDIT-014`（撤销语义粒度）—— 取之前先 `grep` 源码看机械判据差哪一半；备选：`FR-STD-DB-DIAG-006`（台账那一行需求摘要还是「—」，**先要把口径问出来**，别自己编）· `FR-STD-WS-LIC-001`（授权入口，等人工验收）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**存量红六条（2026-10-29 在干净工作树 `git worktree add 874a3e48` 里逐条对照过：基线就红、本循环未加重）**：`check-core-portability`（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/`）· `check-core-localization`（`Binary files` 未白名单）· `check-button-icon-only`（11 处，含 R53 `HTMLPreviewView`）· `check-literal-language`（`Core/AgentNotifyChannel.swift:178`）· `check-doc-q-series`（`Docs/通用开发规范.md` 解析不到 §4/§6）· `check-doc-layout`（12 条）。**这六条使 `verify-all.sh` 不可能全绿 —— 别每轮重复当新账报，要清它们得单开一条活。**
**`verify-all.sh` 全跑（2026-10-29 R58 实测 18 项 rc=1）另有五处红，也都不是功能片的账**：第 4 项 `check-pending-agenda --self-test` 缺本机文件 `Docs/智能体助手-开发规范.md`（.gitignore 内）· 第 9 项 `test-empty-action-buttons` 的负例夹具还找 `.disabled(trimmedName.isEmpty)`（R57 改走 `isEnabled:` 后没跟夹具，基线同样红）与 `check-panel-root-frames` 的 `scannedFiles` 104 vs 实测 105（R57 新增回执页视图后没跟版，基线同样红）· 第 11 项 `check-menu-language` 起不来应用 dump 菜单（**本会话无 GUI**）· 第 16 项 `check-tri-repo-parity`（共享脚本 sha 与三仓台账不符）· 第 18 项 `check-release-version` 缺 `Docs/发布方案.md` / `Docs/发布计划.md`（本机未同步）。⇒ **收尾只报「五门 + check-format-arguments」；`verify-all` 的红逐条对基线，不重复当新账。**
**R57（`FR-STD-DB-TASK-003` 执行回执）已落地** —— 明细搬进 `.agent/references/history-R57.md`（卡体积预算）。
~~下一条活 = 台账 `FR-STD-WS-VCS-002`（R58 已完成，本行作废，见上段）~~
且 `Core/GitUnifiedDiff` 与「变更」页已在，属同族补齐，不是新起一摊）。
备选：`FR-STD-DB-DIAG-006`（从连接上下文唤起诊断、结论可点回对象）· `FR-STD-WS-LIC-001`（授权决定哪些入口出现）·
低档四条（`FS-010` / `NAV-006` / `NAV-005` / `EDIT-014`）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**可选增强（还没做，别当已完成）**：折叠处没有 `⋯` 占位符 —— 折完看到的是"一段空白"。主人若觉得分不清，下一轮补一枚占位。
**有一条待主人拍板**（已登记，别当已决）：命名分组标题上要不要也给「＋」（现在只有「未分组」那段有）。
**待人工点验的累积清单**（别重复追问，扫一眼就够）：网页预览那一眼（R53）· 文件树拖拽与「在终端中打开」（R52）·
缩进那一格（R54：状态栏显示 / 改完再按 Tab / 改宽度后硬 tab 占几格）· 折叠那一格（R55：小三角折 / 再点展开 / 切页签再回来仍折着 / ⌘F 仍能搜到）·
编码与换行那一格（R56：CRLF 文件的状态栏读数 / 改一行保存后 `git diff` 只一行 / 切 GB18030 保存后文件仍是 GB18030）·
**回执那一格（R57：跑一条查询看四项读数 / 报错语句也有回执 / 只读连接被拦下读「未发出」/ 复制与导出各一次）**。·
**差异视图那一格（R58：只改缩进的文件勾「忽略空白」应归零 / 上下文切 40 行看折行且点开 / 上万行文件一屏出来不卡且末尾有「还有 N 行」）**。
**节点级失败重试那一格（R60：造一个连不上的库展开它，红字旁应有「重试」；点了旧红字先消失并重新取一次；在途时入口应消失）**。
**整批撤回那一格（R59：改两个文件点「整批撤回」应都回改前 / 撤前手工改一个 ⇒ 那个读「没动」且不动 / 点「撤销这次撤回」回到 Agent 版）**。
**片段模板那一格（R61：打 `select` 按 Tab 出骨架且光标在第一个占位符 / 再按 Tab 依次跳、填完最后一格回到缩进 / 字符串与注释里打 `select` 按 Tab 不该展开 / `selects` 这种带尾巴的词也不展开）**。
**多工作区切换那一格（R62：再选一个文件夹后标头菜单应两条且新的打勾 / 在菜单里切回旧的，树与页签跟着换且旧的不再是活动 / 把某个工作区的目录删掉，那一条应写「目录不在了」且点不动 / 重启应用停在最后用的那一条）**。
**接力机制如实记一笔**：本会话没有 `cronjob_manage` 工具 ⇒ 收尾用 `hermes cron run e98fad41f72d`（CLI 等价）点火；
点不着就靠 5 分钟兜底定时器，别手工改 schedule。

# 每轮卡 · Studio macOS 端自主开发（2026-10-28 起）

> 每轮先读这一页（≈1.5KB），按它取活；细则见 `.agent/rules.md`（本卡优先）。
> **队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`**（`FR-STD-*` 里实现为 `⬜`／`🟡` 的行）。
> `.agent/plan.yaml` **已停用**（2026-10-28 起以台账为准，读它等于读旧账）。

## 第 0 步：轮次锁（防两轮叠在同一棵树上）

```
若 .agent/round.lock 存在且 mtime 在 90 分钟内 ⇒ 上一轮还在跑，本轮什么都不做，直接结束（不汇报）
否则：写 .agent/round.lock（内容=时间戳+本轮取的条号）→ 干活 → 收尾时删掉它
```

## 一跳的形状（一次只做一条）

```
读台账 → 取一条（优先=高 → 中 → 低；同档取「判据可机械跑」的）
→ 做这一条的最小纵切（Core 机制 + 接线 + 用例），≤ 一轮
→ verify-core 取新总数 → 同批改：doc-numbers / AGENT-SPEC / 台账行（实现·判据·备注）/ 变化记录版本行
→ 五门：numbers tables versions invariants version-scope（全绿才收）
→ xcodegen generate → Scripts/build-app.sh → 记包哈希
→ 落 .agent/evidence/<日期>-<条号>.md（命令原文 + 读数尾部）→ 改 checkpoint.md 的「下一项」
→ 汇报三行
```

## 写死的口径

1. **纵切优先**：先把一条从头到尾打通，不铺半成品。
2. **不虚翻**：Core 有代码但界面上点不到 ⇒ 实现 `🟡`（备注写「差哪个入口」），判据可 `✅`。
3. **测试总数只认 `bash Scripts/verify-core.sh`**（真值 `.build/core-test-count.txt`）；`--filter` 的 `Executed N` 只是过滤后数。
4. **跑 Swift 必须 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`**。
5. **单一活书**：只改顶层台账，不新建 v2、不建副本；`Docs/frozen/` 与 `Docs/archive/` 不动。
6. **判据成对**：新增判据必须能判红（改坏一处 ⇒ 红），至少 6 例起步。
7. **不碰**：别人未提交的改动（`git status` 里不是你这片动的文件）、`Platform/` 下别的端、凭据文件。
8. **只提交不推送**：本仓常有两个写者，推送由主人在前台决定；提交前 `git add` 只加本片文件。
9. **版本行必跟**：台账「> **版本**」进一位 + 变化记录写清本批做了什么、读数多少。
10. **不能自己判的**：观感／真机／外部账号 ⇒ 台账留 `🟡` 并在备注写「等人工点验」，**不假装完成**。

## 出口（只有三个，不许以提问结尾）

1. 台账里 `FR-STD-*` 的实现 `⬜` 清零 ⇒ 收口汇报，`cronjob_manage action=pause` 停自己；
2. 只剩 `🟡`（外部依赖 / 人工点验）⇒ 同上，并列出「卡在谁那里」；
3. 撞见需授权（花钱 / 删数据 / 外发 / 改系统配置）⇒ 只记 blocked + 转下一条。

## 节奏：接力（2026-10-28 主人拍板）

- **一轮结束就接下一轮**：收尾时先删 `.agent/round.lock`，若台账里还有可推进的活 ⇒ 立刻点火下一轮，不要等定时器。
  点火有两个入口，**有什么用什么**：`cronjob_manage action=run job_id=e98fad41f72d`（有该工具的会话），
  否则 `hermes cron run e98fad41f72d`（CLI，等价：下一跳调度器拉起）。两个都用不了 ⇒ 靠 5 分钟兜底定时器接续，
  并在汇报里如实说一句「本轮未点火、靠兜底」——**不许假装点着了**，也不许手工改 schedule。
- 定时器每 **5 分钟**一跳只作**兜底**（上一轮崩了、或点火没成功时能把链子接回来）；锁还在 ⇒ 空转不汇报。
- 没有活可做 ⇒ `cronjob_manage action=pause` 停自己，不点火。
- 不要改 schedule，不要再按剩余条数自调阶梯。

## 汇报（三行，QQ 只发这个）

- 结论：本轮哪条 + 实现/判据状态 + 包哈希
- 一行证据：`verify-core` 读数 + 五门 rc
- 要我做的事：只列本轮新增的拍板／点击项，无则写「无」
