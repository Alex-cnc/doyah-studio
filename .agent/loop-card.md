## ★ 顶部条目（优先于常规取活，不得顺延、不得再问）

**★00 · 钥匙串每次启动都弹密码 —— ✅ 代码侧已落地（R67，2026-10-29），本条关闭，不得重复执行**

- **症状（原话）**：「keychain 有个问题就是每次启动都要输入密码。」
- **根因两个（已核源码 + 实测）**：① 三处 `SecItemAdd` 不带 `kSecAttrAccessible`、不绑 ACL ⇒ 信任列表由系统按「谁建的」隐式写下；
  ② 构建侧曾**静默回退 ad-hoc** ⇒ 每次重打包换一个「应用」身份。
- **已做**：`Core/CredentialItemReconciliation.swift`（按签名记账的**一次性重写**：能读就一个字节都不动 / 旧签名条目「读→删→按当前签名写回」/
  **读不出来绝不删** / 失败不记账；账本键取**指定要求串**而不是 cdhash）+ `Platform/macOS/KeychainCredentialSlots.swift`
  （四族条目统一带 accessible 与只信任本应用的 `SecAccess`）+ `AppState.reconcileKeychainCredentials`（启动期一次，在旧文件迁移之后、读 Key 之前）
  + `Scripts/build-app.sh` **不再静默回退 ad-hoc**（`DOYAH_ALLOW_ADHOC=1` 才回退）+ `Scripts/make-signing-identity.sh --trust`。
  判据 `Tests/CredentialItemReconciliationTests` 15 例；反例三段各判红后逐字节还原；明细 `.agent/evidence/2026-10-29-keychain-prompt.md`。
- **仍差（不是本条重复项）**：① 主人手动跑一次 `./Scripts/make-signing-identity.sh --trust`（要管理员密码）——
  不信任时点「始终允许」记不住，症状仍会复现；② 「启动不再弹密码」只能本人点验一次。
- **实测边界（别拿属性当证据）**：登录钥匙串**吞掉** `kSecAttrAccessible`（Add 成功、回读 `nil`），数据保护钥匙串要
  `keychain-access-groups`（自签给不了，`-34018`）⇒ 属性今天不产生行为差别，只为将来留好。

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

**R69（2026-10-29）`FR-STD-DB-IO-002` 的「评估改动面」已做完 —— 结论不是「要不要改 vendor」，是「界面没有入口」**：
三处核实（需求规格 **R-036** 已把 `COPY … TO STDOUT` 登记为已知限制并真机验证过游标路径 12 万行 / 27 MB · 《待人工验收清单》§11.5 项 2 建议「**不动 vendor**」· 驱动里 CopyOut **连消息解码都没有**，`PostgresBackendMessage.swift:139` 对 copyOutResponse / copyData / copyDone 一律抛 unknownMessageKind）⇒ **取数机制早就成立，缺的是对象树右键里的入口**。本轮已接**整表导出**（表 / 视图行 → 「导出整表…」五档文本格式 → 游标逐页取 + `ResultStreamWriter` 逐页写 → 小结面板报「N 行 → 路径」；`Core/TableExport.swift` 纯判定 + `AppState.exportTable` + `App/Views/TableExportSheet.swift`；判据 `Tests/TableExportTests` 15 例，反例四段各判红；包 `996be408（08:24:17）`；明细 `.agent/evidence/2026-10-29-DB-IO-002.md`）。**`Vendor/` 一个字节没动。**
**R70（2026-10-29）整库导出已接线，并修掉一处「入口接错渲染器」**：`Core/TableExport.databasePlan`（只导表与视图 / 其余跳过分档报数 / 同一 `(schema, table)` 只导一次 / 跨 schema 时文件名与账里的称呼都带前缀 / 净化和撞名顺延与整表导出共用 `uniqueFileName`）+ `AppState.streamTable`（**整表与整库共用**的取数写盘那一处）+ `AppState.exportDatabase`（选目录 → 逐表导 → `Ledger` 逐表记账 → 小结报「行数 → 路径」+ 合计 + 跳过数）+ 右键数据库 / schema「导出整库…」五档；判据 `Tests/TableExportTests` **22 例** + 新增 `TestsUISnapshot/…testProductionMenuCarriesExportEntries`。**同批修的真缺陷**：上一批的「导出整表…」只加在 SwiftUI 那份（`ObjectTreeContextMenu`，`App/` 下零生产调用方）而生产右键走 `ObjectTreeAppKitMenu` ⇒ 上一版用户点不到；本批补进生产菜单、两套渲染共用一份格式清单。实现 **🟡**（差人工点一次）/ 判据 **✅**（反例七段各判红后逐字节还原）；包 `f023f8d2（08:46:57）`；明细 `.agent/evidence/2026-10-29-DB-IO-002-整库.md`。
**R72（2026-10-29）CLI `export` 的方言判已收 —— 本条关闭，不得重复执行**：核源码时先纠正记录里的一半（`doyah export` 今天**走不到** MySQL：默认路径 `dbType` 写死 `.postgresql`、`mysql` / `gbase8a` 子命令只认 `--sql`），但两处真缺陷都成立并已修：① 方言从连接派生（`SQLDialectFactory.make(for: dbType)`，三个取数函数入参放宽为 `any SQLDialect`）· ② 非 PG 在**建目录 / 拼语句之前**退 **69** 并说清「缺服务端游标 / 一条语句都没发出去 / 可走 `mysql --sql … --json`」· ③ `mysql` / `gbase8a` 子命令不再**静默忽略** `--export`（旧行为 rc=0、无文件），改为**建连接之前**用同一句话拒绝。裁定唯一一处 = `Core/TableExport.decision(for:)`（`.streaming` / `.rejected(类型)`，`streamingSupported` 是它的投影）。判据 +14 例（`Tests/TableExportTests` +7 · `Tests/CLIExportDialectSourceTests` 7），反例七段各判红后逐字节还原；Core **4936 / 0 failures**；包 `be96b836（09:04:34）`；明细 `.agent/evidence/2026-10-29-CLI-export-dialect.md`。
**下一条活（R72 收尾时更新）**：**台账里能自己推的活已清空** —— `FR-STD-*` 实现列 ✅ 126 / 🟡 83 / ⬜ 4 = 213，剩下的都要人：人工点验（整表 / 整库导出那两格 + R59–R68 累积清单）· 拍板（**敏感列口径** · 许愿模式是否另设开关 · `Q60` 取 B）· 缺环境（MySQL/GBase 游标替代方案属新活 · 真跳板机 · 真库面 · `TOOL-003` / `AI-001` 纵切过大）。⇒ 没有新的 ★ 条进来时下一轮应 `action=pause`，不空转。
**循环已暂停（R72 收尾 · 2026-10-29 09:06）**：能自己推的活已清空 ⇒ 已 `hermes cron pause e98fad41f72d`，并复核 `.hermes/cron/jobs.json`：`enabled=false` / `state=paused`。**恢复方式** = 先把新 ★ 条（或新口径）写进本卡，再 `hermes cron resume e98fad41f72d`；恢复后的第一轮**先读本卡再取活**，不沿用旧队列。另一条 job（派单信箱）不归本循环管，停不停由主人定。
**★ 区已清空**：下一条活按台账取（`FR-STD-*` 里实现 `⬜`／`🟡`，优先=高 → 中；同档取判据可机械跑的）。
**R66（2026-10-29）已把 `FR-STD-WS-AI-002`（许愿式编程）的交付面接通**：`Core/WishStaging.swift`（472 行、用例早在跑）此前**零调用方** ⇒ 验收要点 ①「交付前给出改动清单与差异」与 ③「没跑通必须标出来」界面上一个字都没有。落法 = `Core/WishDelivery.swift` 把已落盘的账（`AgentEditJournal.undoable`）投影成**同一份** `WishProposal`（差异仍走 `AgentTextDiff`）：同一路径只出一条（前像取最早、后像取最新）· 净效果为零不进清单 · 删除型改动不在这个账上；判定四档 `noChanges/unverified/passed/failed`（**没记读数一律「未验证」**）。接线 = `AppState.wishDelivery`（与撤账同一把边界）+ 命令批准那档记最后一条真跑起来命令的退出码与输出尾 + 对话页输入框上方一行读数与「看改动清单与差异」逐文件逐行（单文件 40 行上限，超出说「还有 N 行」）+ 语言表 10 键。实现 **🟡**（差人工点一次）/ 判据 **✅**（`Tests/WishDeliveryTests` 10 例；反例三段各判红后逐字节还原）；包 `c109b952（07:32:24）`，07:28:51 那份 `1a6f175f` 作废。明细见 `.agent/evidence/2026-10-29-WS-AI-002.md`。
**历轮已落地（R59–R65，明细原文见 `.agent/references/loop-card-history.md`）**：R65 撤销语义粒度 · R64 悬停文档与跳定义 · R63 陈旧标记归正 8 条 · R62 多工作区切换 · R61 片段模板 · R60 节点级重试 · R59 整批撤回 —— **均「实现 🟡 / 判据 ✅」，差人工点一次（点验清单见本卡末）**。
下一条活（R68 收尾时更新）⇒ **① `WS-UI-004` 判据列 🟡 → ✅ 已落地（R68：判据 27 + 3 例 Core + 2 例端上探针实测 0 failures，实现仍 🟡 差一次真重启点验）—— 本条关闭，不得重复执行**；**②（已作废｜R69 已做完，见上一段）下一轮先做 `DB-IO-002` 的「评估改动面」**（R68 实测：`Vendor/postgres-nio/Sources` 里 `copyOut` 零命中，只有协议层 `copyOutResponse`；公开 API 只有写入向 `copyFrom` ⇒ 缺口成立，但改动面 = 驱动补 copyOut + Core 流式导出 + 界面入口一整片，且要先定口径「`COPY TO STDOUT` 还是既有 `SELECT` 分页」—— 后者今天就能做、前者要动 `Vendor/`）⇒ **只出评估 + 两个方案的代价，别直接动 `Vendor/`**；③ 11 条 🟡 的核实已做完并落 `.agent/evidence/2026-10-29-WS-AI-002.md`：环境挡 5 条（`DB-CONN-020` / `DB-DIAG-003` / `DB-DRV-009` / `DB-IO-003` / `DB-META-002`）· 只差人点 2 条（`WS-VCS-001` / `WS-WEB-003`）· 范围 1 条（`WS-NAV-002` Beta 1 全量语种）· **标记陈旧 1 条（`WS-UI-004`：备注写「光标 + 滚动未交付」，源码里 `reportCursor` / 快照 `scrollOffset` / `WorkspaceAreaView:94` 都已接 ⇒ 按 R63 做法逐个 `--filter` 核例数再翻标记）** · 机械缺口 1 条（`DB-IO-002` COPY … TO STDOUT，缺口在 vendored 驱动内，需先评估改动面）；③ 实现列剩的 3 条 ⬜ 仍不是「能自己推」的（`TOOL-003` / `AI-001` 纵切过大，`LIC-001` 等人工验收；`DB-DIAG-006` 需求摘要还是「—」）。**④ `AI-002` 仍差的那一半**：许愿模式「先出改动后生效」= `WishStaging` 暂存面接线，属产品口径 ⇒ 待主人拍板（别自己起）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**存量红七条（2026-10-29 在干净工作树 `git worktree add 874a3e48` 里逐条对照过：基线就红、本循环未加重）**：`check-core-portability`（`Core/AgentCodeRunner.swift:57` 硬编码 `/usr/local/`）· `check-core-localization`（`Binary files` 未白名单）· `check-button-icon-only`（11 处，含 R53 `HTMLPreviewView`）· `check-literal-language`（`Core/AgentNotifyChannel.swift:178`）· `check-doc-q-series`（`Docs/通用开发规范.md` 解析不到 §4/§6）· `check-doc-layout`（12 条）。· `check-format-arguments`（R72 实测：HEAD 干净树复跑同样红 —— 类型不明实参 200 / 预算 188、`<reason>` 18/17、`<path>` 3/2，13 条；**不在五门内**，但收尾会看它）。**这七条使 `verify-all.sh` 不可能全绿 —— 别每轮重复当新账报，要清它们得单开一条活。**
**`verify-all.sh` 全跑（2026-10-29 R58 实测 18 项 rc=1）另有五处红，也都不是功能片的账**：第 4 项 `check-pending-agenda --self-test` 缺本机文件 `Docs/智能体助手-开发规范.md`（.gitignore 内）· 第 9 项 `test-empty-action-buttons` 的负例夹具还找 `.disabled(trimmedName.isEmpty)`（R57 改走 `isEnabled:` 后没跟夹具，基线同样红）与 `check-panel-root-frames` 的 `scannedFiles` 104 vs 实测 105（R57 新增回执页视图后没跟版，基线同样红）· 第 11 项 `check-menu-language` 起不来应用 dump 菜单（**本会话无 GUI**）· 第 16 项 `check-tri-repo-parity`（共享脚本 sha 与三仓台账不符）· 第 18 项 `check-release-version` 缺 `Docs/发布方案.md` / `Docs/发布计划.md`（本机未同步）。⇒ **收尾只报「五门 + check-format-arguments」；`verify-all` 的红逐条对基线，不重复当新账。**
**R57（`FR-STD-DB-TASK-003` 执行回执）已落地** —— 明细搬进 `.agent/references/history-R57.md`（卡体积预算）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**可选增强（还没做，别当已完成）**：折叠处没有 `⋯` 占位符 —— 折完看到的是"一段空白"。主人若觉得分不清，下一轮补一枚占位。
**有一条待主人拍板**（已登记，别当已决）：命名分组标题上要不要也给「＋」（现在只有「未分组」那段有）。
**另一条待主人一句话确认（R68 登记；决策台账的状态本侧不自行改）**：`Q60`（`FR-STD-WS-UI-004` 会话恢复的验收面）在《项目管理规范》仍写「⏳ 待拍板 · 默认倾向 B」，而两片已按 **B** 全量交付（`189b7420` 提交标题即写「Q60 取 B 的后半」）⇒ 待主人确认「取 B」，确认后本侧把那一行改成「已定 + 落点提交号」。
**待人工点验的累积清单**（别重复追问，扫一眼就够）：网页预览那一眼（R53）· 文件树拖拽与「在终端中打开」（R52）·
缩进那一格（R54：状态栏显示 / 改完再按 Tab / 改宽度后硬 tab 占几格）· 折叠那一格（R55：小三角折 / 再点展开 / 切页签再回来仍折着 / ⌘F 仍能搜到）·
编码与换行那一格（R56：CRLF 文件的状态栏读数 / 改一行保存后 `git diff` 只一行 / 切 GB18030 保存后文件仍是 GB18030）·
**回执那一格（R57：跑一条查询看四项读数 / 报错语句也有回执 / 只读连接被拦下读「未发出」/ 复制与导出各一次）**。·
**差异视图那一格（R58：只改缩进的文件勾「忽略空白」应归零 / 上下文切 40 行看折行且点开 / 上万行文件一屏出来不卡且末尾有「还有 N 行」）**。
**节点级失败重试那一格（R60：造一个连不上的库展开它，红字旁应有「重试」；点了旧红字先消失并重新取一次；在途时入口应消失）**。
**整批撤回那一格（R59：改两个文件点「整批撤回」应都回改前 / 撤前手工改一个 ⇒ 那个读「没动」且不动 / 点「撤销这次撤回」回到 Agent 版）**。
**片段模板那一格（R61：打 `select` 按 Tab 出骨架且光标在第一个占位符 / 再按 Tab 依次跳、填完最后一格回到缩进 / 字符串与注释里打 `select` 按 Tab 不该展开 / `selects` 这种带尾巴的词也不展开）**。
**撤销粒度那一格（R65：连打一行字按一次 ⌘Z 应整段回到输入前 / 移行·注释切换·补全各按一次只退那一步 / 编辑菜单那一行应读得出「撤销 移动行」而不是光秃秃「撤销」/ Markdown 任务行上按 ⌘L 光标与选区不许跳）**。
**整表导出那一格（R69：右键一张表选「导出整表…→CSV」应出小结「N 行 → 路径」且文件有表头与数据 / 导一张十万行以上的表，导的过程中内存不随行数增长 / 空表应读「表里没有行…没有生成文件」而不是「导出成功」）**。
**整库导出那一格（R70：右键一个库或 schema 选「导出整库…→CSV」→ 选一个空目录，目录里应每张表一个文件、面板逐表报「行数 → 路径」并给合计 / 故意让其中一张失败（如临时收回权限）应只在那一行说没成、其余照旧导成 / 序列与函数应出现在「另有 N 个非表对象」那一行而不是凭空消失 / 跨两个 schema 时文件名应带 `schema.` 前缀）**。
**另记一笔（R70 修掉的缺陷，点验时顺带确认）：表 / 视图行右键里**必须**真的能看见「导出整表…」—— 上一版它只加在 SwiftUI 那份渲染里、生产右键（AppKit 那份）没有，所以看不见；本版已补，判据 `testProductionMenuCarriesExportEntries` 钉住。**
**交付面那一格（R66：让 Agent 改两个文件应看到「这一批交付 N 个文件 · 新建/修改 · ＋A / −B 行」/ 展开「看改动清单与差异」应看到逐行 `+/-` / 让它跑一条会失败的命令，那一行应读「没跑通（退出码 N）」而不是「通过」/ 这一批没跑过命令时应读「未验证」）**。
**悬停与跳定义那一格（R64：停在函数调用处应浮出「名字 · 函数 · 行 N · ⌘ 点击跳到定义」/ ⌘ 点它光标应落到函数名上并滚到可见 / 停在字符串里的同名上应**不弹** / 停在本文件没声明的标识符上应明说「本文件里没有它的定义」）**。
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
