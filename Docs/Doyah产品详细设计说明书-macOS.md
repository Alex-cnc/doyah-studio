> **版本** **v1.1.15**（2026-11-08 §3.39 **第二轮**：取证图显示入口**叠在正文上**（压住上翻途中最后可见的一行）⇒ 把「恒留 40pt 带」改成**保留窄条**：入口不在时这条**整个不存在（高 0，空间还给正文）**，出现时占 40pt、视口相应让位；带不再常驻。上一版留下的反对意见「条件伸缩会让视口矮 40pt、到底时入口永远关不掉」**不成立**（实测反证：滚到内容底边时 `NSClipView` 把偏移夹到 `内容高 − 视口高`，距底 **0.0pt** ⇒ 消失条件可达），另立一条硬约束：**条高 ≤ 出现门槛**（40 ≤ 40），于是出现那一拍视口缩短不需要夹紧偏移、正文一行都不跳。判据从「带恒留、两态视口高相同」改成**五条**并能判红的读数 —— ① 入口 `{383.5, 476.5, 133, 22}` vs 正文可视 `{0, 20, 900, 453.5}`：吃掉可视正文 **0.0pt**、视口底部那一行可见高 **15.0pt**（= 行高，与无入口基线 **15.0pt** 相同；反例·叠层吃掉 **22.0pt**、那一行只剩 **12.0pt** ⇒ 红）；② 入口不在时保留条 **0.0pt**、视口 **493.5pt** = 无入口基线 **493.5pt**（反例·恒留空带 ⇒ 红）；③ 点一下距底 **240.0 → 0.0pt**、入口 **22.0 → 0.0pt**、条 **40.0 → 0.0pt**、视口回 **493.5pt**，随后 5 次追加距底全 **0.0pt**；④ 出现采样 **51** 点只有两个值 **513.5 → 473.5pt**、消失采样 **54** 点 **473.5 → 513.5pt**（中间值 0 个；反例·插一帧 493.5 ⇒ 红）；⑤ 入口与正文可视矩形**不相交**（上沿在视口底之下 **3.0pt**；反例·伸进 10pt ⇒ 相交高 **7.0pt** ⇒ 红）。同批把该族探针真正编进 `DoyahUISnapshotTests` 并跑出 **Executed 5 / 0 failures**）
> **版本** **v1.1.14**（2026-11-08 **双向追溯补齐**：审「详设有没有越出概设范畴」后把九节（§3.31–§3.39）的上游挂上 —— ① 各节首行加「上游：概设 §X / `P-xx`」一行，不再有「设计写了、概设里没有」的悬空；② §0.1 矩阵补 8 行（§8.11 ⑦ 过程区高度、§8.11 ⑧ 信息层级与导航入口、§3 三条新组件契约 —— 检索 / 审批授权（免问账）/ 工作区根，以及 `P-28` / `P-29`），矩阵数据行 50 → 58；③ §3.38 的「对应需求」由书里不存在的 `FR-STD-WS-FS-011` 改指 `FR-STD-WS-FS-002` ⑥（需求书同批补条文，概设 §3「工作区根」行与 `P-29` 同批立））
> **版本** **v1.1.13**（2026-11-08 §3.39 新增「回到底部的浮动入口」：主人「用户拖动会话界面到上面去之后，在 This task 框上沿（会话对话框的最底部）出现一条浮动的、可点击的文字「回到消息底部」，类似 DSH-tui 的效果」—— 对话区底部、滚动视口**之下**的一条**恒留 40pt 带**里放一行**浮动胶囊**（22pt；上沿距视口底 4pt、底边距对话区底边 12pt = 块间距；恒留 = 呼吸 4 + 入口 22 + 块间距 12 + 视口内衬 2），只在**距底 > 40pt 且不在贴底态**时出现、回落到 ≤ 4pt 即消失（滞回），点它滚到内容底边**并恢复自动跟随**（撤本轮落点 + 重置状态机）、点下即隐；带放在视口之外是因为取证图显示「浮在正文上」会压住上翻途中最后可见的一行；带恒留是因为条件伸缩会让视口矮 40pt、到底时入口永远关不掉。与吸顶条（20pt）、三行汇总、过程区自适应高度共存。六条判据各带反例读数 —— ① 初始距底 **0.0pt**/入口高 **0.0pt**、② 上翻后入口 **22.0pt**（frame `{383.5, 476.5, 133, 22}`）、上沿在视口底之下 **3.0pt**、③ 点一下距底 **200.0 → 0.0pt**、入口 **22 → 0pt**、随后 5 次追加距底全 **0.0pt**、④ 回底 **0pt** 后再上翻 ⇒ **22.0pt**、⑤ 入口不伸进视口、两态视口高 **453.5pt** 逐点相同（带 40pt）、⑥ 吸顶条 **20.0pt** 与入口 **22.0pt** 同屏不重叠。同时把 §3.37 契约 8/9（汇总与结论之间只留一块块间距；折叠态三行之和 60pt）与 §3.33.3 契约 6/7（换轮按几何事实重定位；贴底判定只留读数器里那一份）的产品形态定稿。）
> **版本** **v1.1.12**（2026-11-07 结构调整：①按主人指正，标题去「第N轮 / betaX / 日期」改按契约主题命名；②把原 §3.38「契约性改动的四书同步纪律」**移出详设**——那是流程纪律，不是产品设计，归《项目管理规范》；本节原编号作废，后续不重排以免打乱既有引用）。
> **版本** **v1.1.11**（2026-11-07 §3.37 + 《项目管理规范》「契约性改动的四书同步纪律」 **第六轮**：beta1.0.8 真机「现在又变成了 thinking/tools 等区域是固定高度，中间空一个大空白区域，只有等返回最终结论之后才能填满」+ 同日补拍「结论不要带『结论』二字前缀」—— 根因：`AgentThinkingViewport.height(expanded:)` 只返回 `200`/`20` 两个常量（`Core/AgentThinkingStream.swift:132-134`），视图在 `App/Views/AgentProcessBlocks.swift:305-308` / `:353-355` 把整块与视口都钉成定高，工具行体又只有 `maxHeight`（`:95` / `:506`）；改法：**高度 = min(内容实测高, 上限)** 且内容实测高**按整行向上取**（`AgentThinkingViewport.quantizedContentHeight`，步长 20pt + `ContentHeightSpy` 实测 + 只在量化值变时写 `@State`），工具行体按行数直接算（`AgentProcessBody.height`），并落**阶段形态表**（运行中贴着长 / 终态一行让位，思考区 20pt、工具区 20pt、结论完整）；结论层新增 `AgentAnswerLabel.stripping(_:)` 在**渲染前**剥「结论：/Conclusion:/## 结论/📌」，原文一个字节不改；判据九条各带反例读数 —— ① 1 行 ⇒ 区高 **42pt**（恒 200 形态 200pt 判红）、② 1/3/8 行 ⇒ **42/82/162pt**、③ 60 行 ⇒ **200/178/文档 901pt**、④ 300 次追加高度只变 **8 次**（内容 25 行；未量化样本 299 次判红）、⑤ 空白 **4/14/19pt** < 一行（恒 200pt ⇒ 162pt 判红）、⑥ 运行中 **102pt** → 终态 **20pt** 且**跳变 1 次**、⑦ 终态 `Tool calls` 行 **20pt**、⑧ 7 个带壳样本剥净 + 3 个正文样本逐字节不变（不剥 ⇒ 判红）、⑨ 量化/限高/行体纯函数 **20/64/216pt**；另新增 《项目管理规范》「契约性改动的四书同步纪律」 四书同步纪律与 `Scripts/check-doc-sync.py`（提示级，最近 12 个提交实测 **6 个**碰代码、其中 **1 个**未碰文档；`--self-test` **5 例**全过））。
> **版本** **v1.1.10**（2026-11-07 §3.33.4 **第五轮**：beta1.0.7 真机「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」—— 根因：思考区在 `AgentChatView.swift:158` 的 `ForEach(model.messages)` 循环体里**按消息（= 按 step）实例化**（`:171-173` → `:1607` 的 `thinkingZone`），五步就是五块；改法：**一轮 = 一个思考区**（`Core/AgentTurnThinking.swift` 把本轮段聚成一个数组、区挂在轮首那条过程消息），区内退成**轻分隔**（一行发丝 + 极小字「第 N 步」），折 / 展一次作用于整轮；主人同日收口为**一轮只许三行汇总**（`▸ Thinking  ~308 tokens` / `▾ Tool calls (1)  ~16 tokens` / `Σ ~324 total`，默认全折、三行互不影响、第二行展开后逐次调用仍各一行 20pt），token 口径写死为 `Σ = thinking + tools + output`（合并后区的文本 + 工具过程行 + 结论段，一律走 `AgentTokenEstimator` 并带 `~`，端点 usage 只作 tooltip 旁证）；定高 200 / 折叠 20 一个字没动；八条判据各带反例读数 —— ① 五步 ⇒ 区 **1** 个（改前 **5** 个）、② 整块 **200pt** / 视口 **178pt** / 文档 **271pt**、③ 段序 `[1,2,3,4,5]`（倒序判红）、④ **20 → 200 → 20pt** 且区数恒 1（分块形态 5 区合计 100pt）、⑤ 工具块 **5 个**各 **20pt**、⑥ 三行各 **1** 行且 **[20,20,20]**（分块形态 Thinking **5** 行）、⑦ Thinking 行 **324** == 合并后区 **324**（写输出段 **18** ⇒ 判红）、⑧ `Σ 352 = 324 + 10 + 18`（只算输出 **18** ⇒ 判红））。
> **版本** **v1.1.9**（2026-11-07 §3.33.3 **第四轮**：beta1.0.6 真机「每 Step 里的思考过程是可以滚动，但整个界面却不滚动了，要手工去拖动」—— 外层对话区跟随的三处根因：① 落点是底部**哨兵**、比内容底边高 **12pt**（`Spacing.m` 尾随 padding）⇒ 每跟一次距底恒 12pt > 4pt 容差；② 判定只看「距底多少」⇒ **内容长高**与**人上翻**不可分，跟一次就把 `pinned` 打成假、而 `follow` 先 `guard pinned` ⇒ 整段流式再也不跟；③ 触发只挂 `scrollTick`、读数只订阅 `clip.boundsDidChange` ⇒ 内容长高 / 吸顶条进出（视口 −20pt）一律漏。改法：落点=内容底边、判定升级为**状态机**（看偏移的变化方向）、读数器三路订阅（clip bounds / document frame / clip frame）+ 贴底态当场补跟；五条判据各带反例读数）。
> **版本** **v1.1.8**（2026-11-07 §3.36 **新增「审批授权三档」**：beta1.0.6 真机「需要确认的次数太多了，要提供一次授权、会话内授权等选项」—— 审批单与待审批卡片并列三档（**仅这一次** 默认不记任何东西 / **本会话内允许** 只在同一会话、同一「工具 + 作用域」不再问且不落盘 / **总是允许** 落盘跨重启并**当场告知后果**）；记账键 = **工具名 + 规范化作用域**（文件 = 路径、命令 = 首词、MCP/SQL = 参数摘要，**不许只写工具名**）；删除 / 越界 / 对外发送 / 凭据**不提供**另外两档且**盘上有旧授权也不认**；设置 → 运行策略 → 「已授权的操作」逐条可撤、撤销立即生效且落盘；五条判据 + 作用域判据各带反例读数）。
> **版本** **v1.1.7**（2026-11-07 §3.35 **新增「输入框 shell 式历史导航」**：beta1.0.5 真机「当光标在输入框中，按上下方向键能自动补全历史输入」—— 输入框由**单行 `TextField`** 改为**多行 `NSTextView`**（⏎ 发送 / ⇧⏎ 换行），↑↓ **只在首行行首 / 末行行末**回填历史（多行中间一律走光标，硬约束）、草稿不丢、只回填不发送、提交成功才入历史（连续重复去重 / 上限 200 / 落盘）；六条判据各带反例读数）。
> **版本** **v1.1.6**（2026-11-07 §3.34 **新增「当前轮用户问题吸顶一行」**：beta1.0.4 真机「用户发出的问题被滚动的输出冲掉了……应该跟 hermes 一样：如果输出的文字太多，用户这句话就挂在最顶端」—— 对话区顶部新增**一行**吸顶条（20pt，只在当前轮提问滚出视口顶时出现、滚回即消失、点它滚回那条消息的顶边、不遮内容、不重排行）；五条判据各带反例读数）。
> **版本** **v1.1.5**（2026-11-07 §3.33.2 **第三轮**：beta1.0.4 真机「流式输出让滚动条很闪」—— 思考区的流式上屏改为 **50ms 合并窗口**（头一条立即上屏、结构边界强刷、收尾强刷）、展开态**定高 200pt 视口**（不再跟内容长）、自动跟随**只在贴底态**发生（且不带动画）、运行中**不画滚动指示器**；四条判据各带反例读数）。
> **版本** **v1.1.4**（2026-11-07 §3.33 **第二轮**：beta1.0.3 真机复验三条 ——「思考过程」定型为**思考区三态**（运行中展开 / 任一终态自动折一行 / 手动展开本轮内 sticky）、「哪一段算结论」给出四条判定规则、工具调用**默认折一行**、旧库 `display.longPreview = 2+2` **一次性迁移**到 `off` 并写回 v2）。
> **版本** **v1.1.3**（2026-11-07 新增 §3.33「对话区展示优先级：结论默认展开、过程信息默认折叠」—— 由头：主人真机「结论竟然折叠起来，却把 29 个 claims 全展开放屏幕上」；定死三块的高度与默认形态 + 未核断言一行告警，并把 `display.longPreview` 默认值由 `2+2` 改为 `off`）。
> **版本** **v1.1.2**（2026-11-07 新增 §3.32「搜索策略：多词 / 缓存 / 只读工具预算」—— 由头：主人「搜索的策略也是设计范畴」；引擎选了 rg 只是手段，**问几次、怎么问、重复问要不要重扫**同样是契约，不写进详设下次必被重做一遍）。
> **版本** **v1.1.1**（2026-11-07 新增 §3.31「搜索工具引擎：随包 ripgrep + 三级回落」—— 由头：主人问「加 rg 的设计有没有更新到详细设计活书」；核查属实**未更新**（全文 0 处提 ripgrep），本段补契约三段 + 四条判据 + 语义差异与平台边界）。
> **版本** **v1.1.0**（2026-11-05 **beta1 冻结基线** —— 主人令「beta1 版本先冻结 v1.1 四书，在 1.1.xxx 基础上演进活书；beta2 包含这些能力、对应冻结 v1.2.0，以此类推」；本段起活书按 `v1.1.NNN` 演进）**v1.0.23**（2026-10-31 §3.27 自动链改为「配 key 则 Tavily 优先、网络不通才回内置」；先前 v1.0.20（2026-10-31 §3.27 补 Bing 后端与「自动 = DDG → Bing」链（境内实测 DDG / Tavily 整个域名不通）；此前 v1.0.19（2026-10-31 新增 §3.27「联网工具」：`web_search` 新建、`fetch_url` 启用、后端可配 DDG/Tavily、抓取边界防 SSRF；此前 v1.0.18（2026-10-31 新增 §3.26「工作区外访问（越界授权）」：越界不再硬拒，改为出单、一次一单；此前 v1.0.17（2026-10-31 新增 §5.3.8.4：对话区「谁在说话」配色定稿 —— 金/蓝/紫三色相分离，批准绿、拒绝红；主人看图拍板。上一版 v1.0.16（2026-10-31 改 §3.17：命令执行面改为 Agent 专用 PTY shell + 终端页签镜像；起因：主人「你执行工具不是在 Terminal 中执行吗」）
> 上一版 v1.0.15（2026-10-30 补 §3.25「IM 通道凭据：扫码接入 / 手填 / 自检」契约 + §4.2 两条存储契约（`im-channel-qq.json` / 钥匙串 `agent-im-qq`）；起因：主人问「改了之后有没有同步更新详细设计文档」，核查属实漏更；上一条：（2026-10-26 编号改为「冻结段 + 流水」三段式：`v1.0.NNN`，NNN 上限 999，满了冻结为 v1.1）；承接历史流水 v1.9；原条目：2026-10-26 **§3.21~§3.23 三条偏差全部闭合**：实现落地 + `T-3.21~3.23` 全绿；活书更新，未冻结。v1.8（2026-10-25 补 §3.21~§3.23 三条 Agent 内核接口约束：压缩时机 / 注册表唯一真源与 profile 可见性 / 引擎生命周期钩子 + 矩阵 47→50 行 + §11 新增「契约已立实现未跟」登记 3 条；v1.7：2026-10-25 补 §3.20 并行编排契约 + 矩阵 46→47 行 + T-3.20-01~03；v1.6：2026-10-25 补 §3.18 代码执行、§3.19 工具目录两节七段契约 + 矩阵 §8.11/命令执行/代码执行/工具目录四行 + 5 个新用例；v1.5：2026-10-25 补 §3.17 命令执行七段契约 + 矩阵 §8.11 行 + 4 个 T-3.17 用例；v1.4：2026-10-25 Agent 界面按 Hermes TUI 基准补齐 §5.3.8.1–5.3.8.3；v1.3：2026-10-25 `DETAIL_CONFLICT` 第 1 条已裁决并落地（口令/模型密钥改注入系统钥匙串）；v1.2 内容：按 `detail-design-spec-writing` 自检修齐：补 §2.2 注入点与 §2.3 命名约束；§3 由六节散文改为十六节逐函数契约；§5.3 拆七个组件六态小节并新增 §5.8 界面用例表；§6 拆 6.1/6.2/6.3；§7、§8 拆子节；§0.1 矩阵由 21 行拆到 42 行逐条对齐；§11 增 DETAIL_GAP 登记；已知坑移 §13）；2026-10-27 §5.3 产品形象补「关于页头部品牌块」（56pt 图标 + 四行；文案取 `appCopyright` / `licAboutDeveloper` / `appCopyrightHolder`）；2026-10-28 §3.24 立项「记忆写入 / 检索 / 冲突 / 上下文账本 / 项目规则文件 / 技能沉淀」六件事（**未建**，写明落点与判据，建成前台账不许标 ✅）；2026-10-28 §3.24 项目规则文件由「未建」转「已建」（`AgentProjectRules` + 上下文接线 + 10 例判据）。

> v1.1（2026-10-21 扫差补齐：加笔记域与复盘宿主两章、矩阵补笔记域与复盘域两行）

> v1.0（2026-10-21 全量重写：在 v0.1 摘要稿基础上补齐追溯矩阵 / 函数契约 / 状态覆盖 / 界面六态 / 错误映射 / 测试 ID；上游契约 = `Docs/Doyah产品概要设计说明书.md` v0.6）

## 0. 文档元信息与追溯关系

- 项目/功能名称：Doyah · macOS 端全部能力（Studio 工作区与数据库 / Notes / Retro 宿主 / Agent 在 Studio 内的表现 / 授权呈现）
- 文档版本：v1.0.22（2026-11-05 补登记 11-04 真机修的四类缺陷：§3.29 步数计数与步骤详单上限、§3.30 子代理委派三条隔离约束、§3.25 入站 ack / 进度节流 / 失败落盘 / 重复闸 / 通知角标）
- 实现范围（2026-10-25 实测件数）：`Core/` 260 个 `.swift` + `App/` 133 个 `.swift` + `Platform/macOS/` 5 个文件 + `CLI/` 4 个文件；测试面 `Tests/` 283 个文件
- 上游依据：
  - 概要设计说明书：`Docs/Doyah产品概要设计说明书.md` v1.0.13（含 §11.4 非功能归属 47 条与 §21 标准对照）
  - 需求规格书：`Docs/Doyah产品需求规格说明书.md` v1.0.429
  - 能力规划书：`Docs/Doyah产品能力规划说明书.md` v1.0.250
  - 设计规范（视觉）：`Core/DesignTokens.swift` + `Docs/规范/界面设计节-写作规范.md`
- 本文件性质：**概要设计的实现级展开。** 概要设计说「不许做什么」，本文件说「具体怎么做、做完怎么证明」。本文件允许出现平台名、类型名、文件路径与库版本。
- 优先级：需求规格书 > 概要设计 > 本详细设计 > 现有代码。
- 冲突处理：与概要设计冲突时以概要设计的「禁止」条款为准，输出 `DESIGN_CONFLICT`，不得自行裁决。
- 禁止行为：不得在本文件未定义的函数/组件中新增公开行为；不得修改 §1.3 禁止文件、不得引入 §1.1 基线外依赖；不得修改测试断言、跳过测试或放宽校验来适配实现。

### 0.1 概设—详设追溯矩阵

> 每一行 = 概要设计一条契约 → 本文件一个落点节 → 一个实现单元 → 至少一个真实存在的测试 ID。区间行一律拆到单条。

| 概设章节 | 概设条款摘要 | 详设落点 | 实现单元 | 测试用例 ID |
|---|---|---|---|---|
| 概要设计 §3 | 20 组件必须做/禁止做；禁越层、禁界面持句柄、禁方言分支散落 | 2.1 | `AppState`、`DatabaseService` 协议 | `T-2.1-01` |
| 概要设计 §3.1 | 浏览页签与文件页签同类；禁并入执行面、禁预览侧改写源文件 | 2.1、5.3.7 | `BrowserTabView`、`Core/BrowserTabStore.swift` | `UI-5.3.7-01` |
| 概要设计 §4.1 | 连接建立四类行为；凭据不入请求体；不自动重试认证失败 | 3.1、2.2 | `DatabaseServiceFactory.make`、`ConnectionConfig` | `T-3.1-01`、`T-3.1-02`、`T-2.2-01` |
| 概要设计 §4.2 | 删除连带清凭据；重复删报已不存在；执行中禁删 | 3.2 | `ConnectionStore.save`、`SecretStore` 实现 | `T-3.2-01`、`T-3.2-02` |
| 概要设计 §4.3 | 选区判定、按文本顺序逐条、多结果集全保留 | 3.3、3.5 | `DatabaseService.execute`、`ExecutionSafety.check` | `T-3.3-01`、`T-3.3-02`、`T-3.3-03`、`T-3.5-01` |
| 概要设计 §4.4 | 服务端真取消、连接仍可用、重复取消同一结局 | 3.4 | `DatabaseService.cancel` | `T-3.4-01` |
| 概要设计 §4.5 | 层级按类型；刷新不清选择；禁伪造占位节点 | 3.7 | `MetadataService.loadChildren` | `T-3.7-01` |
| 概要设计 §4.6 | 浏览前 N 行在服务端过滤；无主键不给行编辑；影响 0 行报冲突 | 3.8、3.9 | `RowBrowsingQuery.browse`、`AppState.applyRowEdits` | `T-3.8-01`、`T-3.9-01` |
| 概要设计 §4.7 | 未预览不得执行；删表带存在才删；禁把 DDL 当普通查询 | 3.10 | `SchemaScriptRunner.run`、`TableDesign.validate` | `T-3.10-01`、`T-3.10-02` |
| 概要设计 §4.8 | 流式写文件；目标存在必询问；部分失败列明细 | 3.11、3.12 | `ResultExporter.text`、`TableImport.plan` | `T-3.11-01`、`T-3.12-01` |
| 概要设计 §4.9 | 终止需二次确认并说明后果；权限不足上浮原话 | 3.13 | `SessionMonitor.sessions` | `T-3.13-01` |
| 概要设计 §4.10 | 行数据须确认并留痕；禁投递凭据与连接串 | 3.14 | `AgentContext.assemble` | `T-3.14-01` |
| 概要设计 §5.1 | 连接配置字段、允许读写方、不含口令本体 | 4.1、4.2 | `ConnectionConfig` | `T-4.1-01` |
| 概要设计 §5.2 | 执行记录按天一份、同 SQL 只计次数、归档失败不回滚业务 | 4.1、4.2 | `QueryHistoryStore` | `T-4.2-01` |
| 概要设计 §5.3 | 任务定义字段（读写模式 / 影响行数上限 / 是否需审批） | 4.1、4.2 | 任务配置件 | `T-4.2-02` |
| 概要设计 §5.4 | 审批单与回执；预估取不到写「未接」，禁编造 | 4.1、4.2、3.6、3.16 | `AgentApprovalConsumption`、`AgentPlanRows.estimate` | `T-3.6-01`、`T-3.16-01` |
| 概要设计 §6.1 | 连接状态机闭集；禁失败直跳已连接 | 4.4 | `ConnectionState` | `T-4.4-01`、`T-4.4-02` |
| 概要设计 §6.2 | 语句执行状态机闭集；禁已取消转已完成 | 4.4 | `QueryEvent` | `T-4.4-03`、`T-4.4-04` |
| 概要设计 §6.3 | 审批单状态机闭集；禁已拒绝/已过期转已批准 | 4.4、3.6 | `AgentApprovalVerdict` | `T-4.4-05`、`T-4.4-06` |
| 概要设计 §6.4 | 页签状态机闭集；执行中不可关闭；恢复不重放语句 | 4.4 | `QueryTabState` | `T-4.4-07`、`T-4.4-08` |
| 概要设计 §7.1 | 查询全链调用顺序与失败处理表 | 4.3 | `AppState` 执行入口 | `T-3.3-01`、`T-3.5-01` |
| 概要设计 §7.2 | 结构变更顺序：生成→预览→二次确认→执行 | 4.3、3.10 | `ExecutionSafety`、`SchemaScriptRunner` | `T-3.10-01`、`T-3.10-02` |
| 概要设计 §7.3 | 外部改动提示二选一；保存失败不清脏标记 | 4.8 | `WorkspaceSession` 与编辑器状态 | `T-4.8-01` |
| 概要设计 §8.1 | 界面范围与边界；禁新增未登记入口、禁新界面库 | 5.1 | `App/Views/*` | `UI-5.1-01` |
| 概要设计 §8.2 | 八类页面/视图职责与禁止呈现项 | 5.1 | 视图清单表 | `UI-5.1-02` |
| 概要设计 §8.3 | 导航允许流转四条与禁止跳转 | 5.7 | 页签模型与活动栏路由 | `UI-5.7-01` |
| 概要设计 §8.4 | 界面六态必须呈现与禁止行为 | 5.3 | 六态落点表与七个组件小节 | `UI-5.3-01`、`UI-5.3-02`、`UI-5.3.1-01`、`UI-5.3.2-01`、`UI-5.3.3-01`、`UI-5.3.4-01`、`UI-5.3.5-01`、`UI-5.3.6-01` |
| 概要设计 §8.5 | 交互规则：校验前禁提交、不可逆二次确认、禁 toast 承载决策 | 5.5 | 事件绑定表 | `UI-5.5-01` |
| 概要设计 §8.6 | 表单字段校验规则与错误定位位置 | 5.6 | `ConnectionFormView` 校验分支 | `UI-5.6-01` |
| 概要设计 §8.7 | 八个界面动作 → 接口映射与禁止行为 | 5.5 | 动作映射表 | `UI-5.5-02` |
| 概要设计 §8.8 | 字段级/页面级/服务器错误呈现规则 | 6.1 | `AppError` 呈现路径 | `T-6.1-01` |
| 概要设计 §8.9 | 键盘路径成套、读屏语义、快捷键只在一处定义 | 5.6、5.7 | `AppCommandCatalog` | `UI-5.7-02` |
| 概要设计 §8.10 | 界面契约验收八条判据 | 5.8 | 界面用例表 | `UI-5.8-01` |
| 概要设计 §9 | 21 个错误码 + 四级兜底禁令 + 日志要求 | 6.1、6.2、6.3 | `AppError`、`ConnectionFailure` | `T-6.1-01`、`T-6.2-01` |
| 概要设计 §10 | 12 条被拒绝方案 | 1.1 | — | 静态检查 |
| 概要设计 §11.4 | 47 条非功能需求的设计归属 | 2.2、7.1、7.2、8.1、8.2 | `actor` 与 `@MainActor` 边界、`EgressLog` | `T-7.1-01`、`T-7.2-01`、`T-8.1-01`、`T-8.2-01` |
| 概要设计 §12 | 设计合规验收判据十条 | 10.2 | — | 自检输出 |
| 概要设计 §14.1 | 缺口清单与四条暂定口径（过期/预估/自动附带/设备配额） | 11 | 本文件「暂定口径承接」 | 人工点验 |
| 概要设计 §15 | 笔记域 14 节不变量（捕获/附件/私密/回收站/待办/日历） | 4.5 | `NoteLibrary`、`NoteDatabase`、`NoteAutosave` | `T-4.5-01` |
| 概要设计 §16 | 复盘域 18 节（行情/特征/回测/复盘稿/周报） | 4.7 | `App/Views/RetroHostView.swift`（宿主；实现不在本仓） | `T-4.7-01` |
| 概要设计 §18.1 | 循环与工具：参数先校验、观测有界、预算耗尽即结束 | 3.15 | `AgentStandardDispatcher.dispatch` | `T-3.15-01` |
| 概要设计 §19.2 | 插件装配：同进程模块、清单为唯一装配源 | 2.3 | `Scripts/check-plugin-assembly.py` 对应清单 | `T-2.3-01` |
| §3 组件契约（命令执行） | 起一条命令并带回 stdout/stderr/退出码；后台可中断；审批+审计；仅授权目录 | §3.17 | `AgentCommandRunner.run(_:in:timeout:)` | `T-3.17-01` `T-3.17-02` `T-3.17-03` `T-3.17-04` |
| §8.11 界面语汇与可配置项 | 行首栏字形 / 一个字号 / 状态行字段序 / 九个显示开关 / 主题按角色 | §5.3.8.1 / §5.3.8.2 / §5.3.8.3 | `AgentChatView`（字形与状态行）· `AgentMarkdownBody` · 主题值表 | `UI-5.8-01` `UI-5.8-02` |
| §3 组件契约（代码执行） | 受限目录跑多行代码，沙箱无网、超时/内存上限、输出截断 | §3.18 | `AgentCodeRunner.run(_:language:in:)` | `T-3.18-01` `T-3.18-02` `T-3.18-03` |
| §3 组件契约（工具目录） | 按名/用途检索工具并取回 schema；未取回不得调用 | §3.19 | `AgentToolCatalog.search(_:limit:)` | `T-3.19-01` `T-3.19-02` |
| §3 组件契约（并行编排） | 多路无依赖子任务并行、各自隔离、逐路给结局并归并、可改方向或叫停 | §3.20 | `AgentOrchestrator.run(_:options:)` | `T-3.20-01` `T-3.20-02` `T-3.20-03` |
| §18.2 上下文先验（`FR-AGT-CORE-CTX`）+ §18.22 预算 | 压缩只在会话边界发生；回合内只出预算报告，不许改写上下文 | §3.21 | `AgentContextCompression` | `T-3.21-01` `T-3.21-02` `T-3.21-03`（待落地） |
| §18.1 循环与工具（`FR-AGT-CORE-LOOP`） | 工具注册表唯一真源；可见性由 profile 决定，壳不分叉实现 | §3.22 | `AgentToolRegistry` | `T-3.22-01` `T-3.22-02` `T-3.22-03`（待落地） |
| §18.2 上下文先验 + §18.23 可观测（`FR-AGT-OPS-OBS`） | 引擎钩子只挂真实边界；onSessionEnd 恰好一次、失败不中断 | §3.23 | `AgentContextEngine`（待建） | `T-3.23-01` `T-3.23-02` `T-3.23-03`（待落地） |
| 概要设计 §3（组件契约 · 并行编排） | 子代理委派的三条隔离约束：事件不分流、预算不独立、重派不换会话 | 3.30 | `AgentSubtaskEventChannel`、`AgentSubagentExecution` | `T-3.30-01`、`T-3.30-02`、`T-3.30-03` |
| 概要设计 §18.23（可观测） | 对话区能回答「走到第几步 / 还剩多少」且步骤详单不撑窗口 | 3.29 | `AgentChatModelStepCounter`、`AgentStepListPanel` | `T-3.29-01`、`T-3.29-02` |
| 概要设计 §8.11 ⑦（过程区高度与阶段形态） | 高度 = min(内容实测高, 上限) 且按整行量化；终态折成一行只跳一次；结论首行不带标签壳 | 3.37 | `AgentThinkingViewport`、`AgentProcessBody`、`AgentAnswerLabel` | `T-3.37-01` … `T-3.37-12` |
| 概要设计 §8.11 ⑧（信息层级 / 未核断言告警） | 结论整段可见、过程信息折一行；未核断言的条数出现在折起那一行上 | 3.33 | `AgentClaimTrace`、`AgentDisplayPreferences`、`AgentAnswerClassifier` | `T-3.33-01` … `T-3.33-10` |
| 概要设计 §8.11 ⑧（本轮提问吸顶） | 只吸当前轮一行、点它回该条消息、不遮内容不重排行 | 3.34 | `AgentStickyQuestion`、`StickyQuestionSpy` | `T-3.34-01` … `T-3.34-05` |
| 概要设计 §8.11 ⑧（输入框历史） | ↑↓ 只在首行行首 / 末行行末回填；只回填不发送；去重、上限与落盘 | 3.35 | `AgentComposerHistory`、`AgentComposerTextView` | `T-3.35-01` … `T-3.35-06` |
| 概要设计 §8.11 ⑧（回到最新内容） | 离底出现、点击回内容底边并恢复跟随、不压正文 | 3.39 | `AgentJumpToBottom`、`AgentJumpToBottomBar` | `T-3.39-01` … `T-3.39-06` |
| 概要设计 §3（组件契约 · 检索）+ `P-28` | 多词分组、缓存作废、截断与降级如实报数、只读工具每轮预算 | 3.31、3.32 | `AgentRipgrep`、`AgentSearchCache`、`AgentRepeatGuard` | `T-3.31-01` … `T-3.31-04`、`T-3.32-01` … `T-3.32-03` |
| 概要设计 §3（组件契约 · 审批授权（免问账）） | 三档并列、键 = 工具 + 规范化作用域、危险面不降级、可逐条撤销 | 3.36 | `AgentApprovalGrantStore` | `T-3.36-01` … `T-3.36-06` |
| 概要设计 §3（组件契约 · 工作区根）+ `P-29` | 根只有两态且来源可查、默认根创建并验证可写、迁移给可见提示 | 3.38 | `WorkspaceRootOrigin`、`WorkspaceStore` | `T-3.38-01` … `T-3.38-05` |

矩阵数据行：58 行。概设契约节（§3.1、§4.1–§4.10、§5.1–§5.4、§6.1–§6.4、§7.1–§7.3、§8.1–§8.10、§11.4）在本表逐节有落点，无缺口。

---
## 1. 平台基线与实现范围

### 1.1 平台基线（Agent 不得更换）

| 项 | 取值 | 版本约束 | 改动方式 |
|---|---|---|---|
| 语言 | Swift | 5.9+ | 需人类主人批准 |
| 部署目标 | macOS 14 | `Package.swift` 的平台声明 | 需人类主人批准 |
| 界面框架 | SwiftUI（AppKit 兜底桥接） | 随 toolchain | 需人类主人批准 |
| 嵌入式库 | SQLite（笔记数据家，vendored） | `Scripts/vendored-sqlite.json` | 需人类主人批准 |
| 构建 | SwiftPM + `Scripts/build-app.sh` | 见 §9.3 | 需人类主人批准 |
| 测试 | XCTest（`Tests/` 283 文件） | `Scripts/verify-core.sh` | 需人类主人批准 |
| 版本控制 | 只读展示（禁提交/推送/合并/切分支） | — | — |

概要设计 §10 的 12 条被拒绝方案在本端的禁止项：

| 概设 §10 被拒绝方案 | 本端禁止项 | 检查方式 |
|---|---|---|
| 只读连接给「仍然执行」 | 禁止绕过 `ExecutionSafety.Decision.refused` 的任何入口 | 代码检索 `refused` 分支 + `rg '仍然执行'` 为空 |
| `EXPLAIN ANALYZE` 估行数 | 仅允许 `EXPLAIN (FORMAT JSON)` | 代码检索 `rg 'EXPLAIN ANALYZE'` 为空 |
| 行数用表总行数或猜测 | `AgentPlanRows` 取不到即如实说「未接」，不报 0 | `T-3.16-01` |
| 写语句自动重试 | 禁止对写语句自动重试 | 代码检索 + `T-3.3-02` |
| 界面层缓存服务对象 | 服务按「连接 + 库」唯一（`AppState.ensureService`） | 评审 + `T-7.1-01` |
| 整表读进内存导出 | 必须流式写文件 | 代码检索 + `T-3.11-01` |
| 多语句并发执行 | 必须按文本顺序逐条 | `T-3.3-01` |
| 未授权入口显示灰色 | 未授权即不出现 | `UI-5.5-01` |
| 到期锁死数据 | 降级入口，数据可开可导出 | `UI-5.3-01` |
| 结果行数据默认投给助理 | 必须显式确认并留痕 | `T-3.14-01` |
| 实现读数写进契约 | 读数只进台账 | 评审 |
| 只读日志面板冒充终端 | 终端必须真交互（PTY） | `UI-5.1-02` |

### 1.2 本文件覆盖的落点文件

| 文件路径 | 操作 | 用途 | 允许修改的符号 | 对应概设条款 |
|---|---|---|---|---|
| `Core/DatabaseService.swift` | 修改 | 协议 + 工厂 | `DatabaseService`、`DatabaseServiceFactory` | 概要设计 §3、§4.1 |
| `Core/ExecutionSafety.swift` | 修改 | 只读/写判定与高危确认 | `ExecutionSafety.check`、`Decision` | 概要设计 §4.3、§7.1 |
| `Core/ConnectionStore.swift` | 修改 | 连接清单持久化 | `load`、`save`、`fileLocation` | 概要设计 §4.1、§5.1 |
| `Core/AgentApprovalGate.swift` | 修改 | 审批单与消费记录 | `request`、`grant`、`peek` | 概要设计 §5.4、§6.3 |
| `Core/MetadataService.swift` | 修改 | 对象树与表结构取数 | `loadRoot`、`loadChildren`、`tableStructure` | 概要设计 §4.5 |
| `Core/RowBrowsing.swift` | 修改 | 前 N 行浏览与过滤 | `RowBrowsingQuery.browse`、`Filter` | 概要设计 §4.6 |
| `Core/TableDesign.swift` | 修改 | 列定义校验 | `TableDesign.validate`、`columnChanges` | 概要设计 §4.7 |
| `Core/ResultExporter.swift` | 修改 | 结果集多格式导出 | `ResultExporter.text`、`data` | 概要设计 §4.8 |
| `Core/AgentContext.swift` | 修改 | 助理上下文装配与脱敏 | `assemble`、`filterSecretsOnly` | 概要设计 §4.10 |
| `Core/AgentPlanRows.swift` | 修改 | 影响行数预估 | `estimate`、`rows(fromExplainJSON:)` | 概要设计 §5.4 |
| `App/AppState.swift` | 修改 | 界面意图 → 能力层 | 相关 `@MainActor` 方法 | 概要设计 §3、§7.1 |
| `App/Views/ConnectionFormView.swift` | 修改 | 连接表单与校验呈现 | 校验分支 | 概要设计 §8.6 |
| `App/Views/ObjectTreeView.swift` | 修改 | 对象树六态与刷新语义 | 刷新分支 | 概要设计 §4.5、§8.4 |
| `App/Views/AgentApprovalSheet.swift` | 修改 | 审批单呈现与确认 | 提交分支 | 概要设计 §5.4、§8.5 |
| `Platform/macOS/KeychainSecretStore.swift` | 修改 | 凭据存取落点 | `setPassword`、`password`、`deletePassword` | 概要设计 §3、§4.2 |

### 1.3 禁止修改的文件

| 文件/目录 | 原因 |
|---|---|
| `Platform/linux/` 整棵子树 | 对侧端实现，本侧不改、不判红 |
| `Platform/windows/` 整棵子树 | 对侧端实现，本侧不改、不判红 |
| `Tests/` 下已有断言 | 不许放宽校验来适配实现 |
| `Scripts/path-ownership.json` | 归属真值，改动需派单 |
| `Docs/` 下他人署名的契约节 | 契约层归契约所有者 |

### 1.4 本文件不覆盖的内容

- 跨端行为判据（在概要设计）；进度与状态（一单）；测试读数（台账）。
- Windows / Linux / 移动端实现（各自的详细设计文件）。
- 概要设计 §14.1 的四条暂定口径本身（过期终局 / 预估取不到 / 自动附带上下文 / 设备配额交互）：本文件只承接其落点，口径由人类主人可否决。

---

## 2. 分层与模块

四层，依赖单向：

| 层 | 目录 | 职责 | 线程模型 |
|---|---|---|---|
| 界面层 | `App/Views/` | 渲染、手势、键盘 | 主线程 |
| 装配层 | `App/AppState.swift`、`App/AgentChatModel.swift` | 承接界面意图、调能力层、把值分发给主线程模型 | `@MainActor` |
| 能力层 | `Core/`（260 个文件）、`Plugins/Notes/Sources/` | 数据库执行、智能体、笔记、同步、导入导出 | 无 UI 依赖；阻塞工作不在主线程 |
| 平台接入 | `Platform/macOS/` | 系统能力（Keychain、目录授权、WebKit、SSH 凭据） | 按调用方 |

### 2.1 组件 → 实现单元

| 模块 | 主要文件 | 契约条款 |
|---|---|---|
| 数据库执行 | `Core/DatabaseService.swift`、`PostgresService.swift`、`MySQLService.swift`、`GBaseService.swift`、`ExecutionSafety.swift` | 概要设计 §4.1 / §4.3 / §4.4 |
| 连接与凭据 | `Core/ConnectionStore.swift`、`ConnectionConfig.swift`、`Platform/macOS/KeychainSecretStore.swift` | 概要设计 §4.1 / §4.2 / §5.1 |
| 元数据与对象树 | `Core/MetadataService.swift`、`DatabaseObjectRef.swift`、`ObjectTreeRefreshGate.swift` | 概要设计 §4.5 |
| 行浏览与写回 | `Core/RowBrowsing.swift`、`App/Views/BrowseRowsSheet.swift` | 概要设计 §4.6 |
| 结构变更 | `Core/TableDesign.swift`、`App/Views/TableDesignSheet.swift` | 概要设计 §4.7 |
| 导入导出 | `Core/ResultExporter.swift`、`Core/TableImport.swift`、`App/Views/ImportPanel.swift` | 概要设计 §4.8 |
| 服务器会话 | `Core/SessionMonitor.swift`、`App/Views/SessionPanel.swift` | 概要设计 §4.9 |
| 智能体回合 | `Core/AgentLoop.swift`、`AgentToolRegistry.swift`、`AgentStandardDispatcher.swift`、`AgentSQLGenerator.swift` | 概要设计 §18.1 |
| 审批与审计 | `Core/AgentApprovalGate.swift`、`AgentAudit.swift`、`AgentPlanRows.swift` | 概要设计 §5.4 / §6.3 |
| 会话与上下文 | `Core/AgentSession.swift`、`AgentContext.swift`、`AgentMemory.swift` | 概要设计 §4.10 / §5.1 |
| 笔记 | `Plugins/Notes/Sources/NoteStorage/`（`NoteLibrary`、`NoteDatabase`、`NoteAutosave`）、`NoteSync/`（`CloudSyncService`、`SyncQueue`） | 概要设计 §15 |
| 内嵌浏览器 | `App/Views/BrowserTabView.swift`、`Core/BrowserTabStore.swift`、`Platform/macOS/WebKitBrowserEngine.swift` | 概要设计 §3.1 |
| 命令登记 | `App/AppCommandCatalog.swift` | 概要设计 §8.3 / §8.9 |

概要设计 §3 的「禁止做」在本端的实现级禁令：

- 界面层禁止 `import` 驱动实现（`PostgresService` / `MySQLService` / `GBaseService`）：`rg -n 'PostgresService|MySQLService|GBaseService' App/` 必须为空。
- 任意组件禁止跨层持有连接句柄、事务句柄、文件句柄：句柄只存在于 `DatabaseService` 实现内部，对外只暴露 `ExecutionHandle` 值类型。
- 方言分支禁止散进界面或业务层：方言差异只允许出现在 `Core/Dialects.swift` 与各 `*Service.swift`。
- 能力层禁止回调界面刷新：能力层只递值（`AsyncStream` / 闭包），界面更新一律回 `@MainActor`。

### 2.2 注入点与可替换依赖

| 依赖 | 注入方式（三选一，写死） | 注入点 | 测试替身 | 禁止做法 |
|---|---|---|---|---|
| 数据库执行 | 协议 + 构造函数参数 | `DatabaseServiceFactory.make(for:password:language:)` 是唯一造实例入口；测试直接用 `FakeDatabaseService` 实现 `DatabaseService` 协议 | `FakeDatabaseService`（`Tests/`，实现同一协议） | 界面或装配层 `PostgresService(...)` 直接 new；实现内部按 `dbType` 再分支 |
| 方言 | 构造函数参数 | `ResultExporter.text(for:format:tableName:schema:dialect:)`、`RowBrowsingQuery.browse(table:schema:filter:dialect:)`、`ExecutionSafety.check(...)` 均收 `any SQLDialect` / `DatabaseType` 形参 | `FakeSQLDialect`（实现 `SQLDialect` 协议） | 在函数体内按 `config.dbType` 取全局方言单例 |
| 时钟 | 构造函数参数（调用点传 `Date`） | `QueryHistoryStore.load(now:)`、`append(_:now:)`、`AgentApprovalGate.grant(fingerprint:at:)`、`peek(fingerprint:at:)`、`ServerSession.elapsedSeconds(now:)` 全部收 `Date` 形参，默认值 `Date()` 只许出现在签名 | 固定 `Date(timeIntervalSince1970:)` | 函数体内直接 `Date()` 而绕开形参；用 `Timer` 当时间源 |
| ID 生成器 | Provider 协议 | `IDProvider { func makeID() -> UUID }` 由装配层持有并注入；`QueryTabState.init(id: UUID = UUID())` 一类签名保留 `id` 形参供替身注入 | `SequentialIDProvider` | 业务代码里散落 `UUID()`（`rg -n 'UUID\(\)' Core/` 只允许出现在默认参数与 `IDProvider` 实现里） |
| HTTP / 模型出口 | Provider 协议 | `HTTPTransport` 与 `HTTPStreamingTransport` 协议；会话内不出现 `URLSession.shared` | `StubTransport`（离线固定响应） | 视图或装配层直接 `URLSession.shared`；实现内部硬编码端点 |
| 密钥存储 | 构造函数参数 | 调用方持 `any SecretStore`（协议在 `Core/SecretStore.swift`，macOS 实现 `Platform/macOS/KeychainSecretStore.swift`），由装配层构造时给 | `InMemorySecretStore` | 业务代码直连 `SecItemAdd` 而不经协议 |
| 文件系统定位 | 构造函数参数 | `ConnectionStore.init(directoryURL:)`、`NoteLibrary` 的库路径由装配层给 | 临时目录 | 硬编码 `~/Library/Application Support` 字符串 |

- 三选一的落地口径：**主注入手段 = 构造函数参数**（凡有实现类的依赖）；**Provider 协议**只用于「同一接口多实现且运行期选择」的两种依赖（ID 生成器、HTTP 出口）。工厂（Factory）只用于 `DatabaseServiceFactory` 一处，因为方言选择必须与 `ConnectionConfig` 同源。
- **已修（2026-10-25 人类主人裁定「改实现」）**：`AppState.secretStore` 不再是 `FileSecretStore()` 写死 —— `AppState.init` 改为**构造函数注入**，默认 `KeychainSecretStore()`（`Platform/macOS/KeychainSecretStore.swift`），`FileSecretStore()` 只作测试 / 开发态显式注入。同一处 `agentKeyStore` 默认改为 `KeychainAgentKeyStore()`（`NFR-ALL-GATE-AI-007`）。本行原为 `DETAIL_CONFLICT` 登记，现已闭合。

### 2.3 目录与命名约束

- 新增文件目录：能力代码只进 `Core/`；界面代码只进 `App/Views/`；平台专属实现只进 `Platform/macOS/`；测试只进 `Tests/`（单元）或 `TestsUISnapshot/`（快照）。
- 命名：类型 `UpperCamelCase`；函数与属性 `lowerCamelCase`；协议名不加 `Protocol` 后缀；测试文件与被测类型同名加 `Tests`；测试方法名 `test_<被测>_<条件>_<期望>`。
- 插件装配唯一来源：`Plugins/*/manifest` 一类清单文件；新增插件必须同时登记清单与 `Scripts/check-plugin-assembly.py` 的期望列表，两处不一致即判红（`T-2.3-01`）。
- 禁止跨层引用：`App/Views/**` 不得 `import` 数据库驱动实现、不得引用 `Core/` 下以 `Service` 结尾的具体类型；`Core/` 不得引用 `App/` 任何符号。
- 判据：`rg -n 'import ' App/Views/ | rg 'Postgres|MySQL|GBase'` 为空；`rg -n 'AppState' Core/` 为空。

---

## 3. 函数/方法级契约

> 每节 = 一个公开函数；七段齐：前置条件 / 后置条件 / 错误契约表 / 禁止行为 / 并发·幂等·事务 / 日志字段 / 测试 ID。错误契约表是本节的唯一表格，逐行必须有「可重试」判定。

### 3.1 `DatabaseServiceFactory.make(for:password:language:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.1
- 用途：按 `ConnectionConfig.dbType` 造出方言实现，口令与界面语言由调用方显式给。
- 前置条件：
  - [ ] `config.dbType` ∈ {`postgresql`、`mysql`、`gbase8a`}（`DatabaseType` 闭集）
  - [ ] `host` 非空；`port` 先解析再校验且 ∈ 1…65535；`database`、`username` 均非空
  - [ ] `password` 由 `SecretStore` 取到；取不到走 `CONN_NO_CREDENTIAL`，不得用空串顶替
  - [ ] `language` 必填，签名不得给默认值
- 后置条件：
  - [ ] 返回 `DatabaseService`，懒连：本函数不建连、不发任何网络请求
  - [ ] `service.config` 与入参 `config` 逐字段相等
  - [ ] 不写任何持久化状态；不在内部缓存实例（实例由 `AppState.ensureService` 以「连接 id + 库」为键持有）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 参数非法（空主机 / 端口越界 / 库名空） | `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 否 | 禁止用默认值补参后照造实例 |
| 类型不在闭集 | `CONN_INVALID_CONFIG` | `AppError.notImplemented` | 否 | 禁止回落到别的方言冒充支持 |
| 凭据缺失 | `CONN_NO_CREDENTIAL` | 调用方在造实例前抛，本函数不吞 | 人工 | 禁止用空口令尝试连接 |
| 依赖超时 | 不适用（本函数无 IO） | 不适用 | 不适用 | 禁止在工厂内建连来「提前发现」故障 |

- 禁止行为：
  - 禁止在内部读环境变量或偏好补齐缺参；缺参即失败。
  - 禁止把方言分支写进界面层或装配层。
  - 禁止用 `fatalError` / `preconditionFailure` 代替可显示错误。
- 并发·幂等·事务：纯构造，无共享可变状态；不持有事务；并发调用互不影响。
- 日志字段：`connection_id`、`db_type`、`elapsed_ms`；禁记 `password`、`dsn`、凭据引用原文。
- 测试 ID：`T-3.1-01`（正例）、`T-3.1-02`（非法输入）

### 3.2 `ConnectionStore.save(_:)`

- 所属单元：`Core/ConnectionStore.swift` ｜ 对应概设条款：概要设计 §4.2、§5.1
- 用途：把整份连接清单原子落盘，供连接管理与执行路径读取。
- 前置条件：
  - [ ] 入参数组内 `id` 唯一；`name` 在同一工作区内唯一
  - [ ] 每项通过 `ConnectionConfig` 校验（端口 1…65535、必填非空、SSL 模式属于该类型集合）
  - [ ] 无「执行中语句」的连接被删除（删除前由装配层判，判不过即拒）
- 后置条件：
  - [ ] 整文件原子替换：要么全写成功，要么旧文件逐字节不变
  - [ ] `fileLocation()` 可读回刚写的条目数
  - [ ] `schemaVersion` 保留并只升级一次（旧格式读入后立即回写新格式）
  - [ ] 删除连接时连带清 `SecretStore` 条目，清理失败必须上浮残留位置
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目录不可写 | `CRED_PURGE_FAILED` | `AppError.persistence` | 人工 | 禁止静默丢配置后返成功 |
| 迁移失败（旧格式解析不通过） | `CONN_INVALID_CONFIG` | `AppError.persistence` | 否 | 禁止用默认值覆盖旧文件 |
| 凭据清理失败 | `CRED_PURGE_FAILED` | 上浮残留条目位置 | 人工 | 禁止只删列表项而留下凭据 |
| 依赖超时（磁盘 IO 超时） | 不适用（无网络） | 不适用 | 不适用 | 禁止在超时后当作已保存 |

- 禁止行为：
  - 禁止先删旧文件再写新文件（半写会丢全部连接）。
  - 禁止在 `save` 内部改 `ConnectionConfig` 字段（迁移只补版本号）。
  - 禁止捕获写盘错误后不记录、不返回。
- 并发·幂等·事务：`actor` 内串行；同一份内容的重复 `save` 结果逐字节一致；单次写在同一原子替换内完成，不跨多次写。
- 日志字段：`entry_count`、`target_path`、`schema_version`、`elapsed_ms`；禁记口令与凭据引用原文。
- 测试 ID：`T-3.2-01`（往返）、`T-3.2-02`（迁移）

### 3.3 `DatabaseService.execute(_:options:handle:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.3、§7.1
- 用途：执行一段 SQL（选区或整篇），逐条上报进度并保留全部结果集。
- 前置条件：
  - [ ] SQL 文本非空（空串或纯空白在上层即被拦，报 `EXEC_EMPTY_SQL`）
  - [ ] 已过 `ExecutionSafety.check`：`refused` 不得进入本函数；`needsConfirmation` 须已确认
  - [ ] 连接处于已连接态；目标库与上下文栏一致
  - [ ] `handle` 由调用方新建且只用于本次执行
- 后置条件：
  - [ ] 事件序列为 `started` → `resultSet`×N → `finished`，或 `cancelled` / `failed` 收尾
  - [ ] 语句按文本顺序逐条执行，第 N 条的序号随事件上报
  - [ ] 多结果集全部保留在流里，不覆盖、不丢弃
  - [ ] 行数只累加一次；耗时按语句与整体各记一份
  - [ ] 失败即停：后续语句不再发送，事务状态标记为未知或已回滚
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 服务端报错 | `EXEC_SERVER_ERROR` | 流内 `failed`（含序号与原文） | 视错误码，写语句一律人工 | 禁止改写成模糊文案 |
| 链路断开 | `EXEC_CONNECTION_LOST` | 流内 `failed` | 否 | 禁止静默重连后重放写语句 |
| 未连接 | `EXEC_NO_CONNECTION` | `AppError.notConnected` | 否 | 禁止默认连第一个连接 |
| 只读连接遇写语句 | `EXEC_READONLY_DENIED` | `refused`（本函数不接收） | 否 | 禁止提供「仍然执行」入口 |
| 依赖超时（服务端无响应） | `EXEC_SERVER_ERROR` | 流内 `failed`（原话） | 人工（重跑是新执行） | 禁止超时后自动重发写语句 |

- 禁止行为：
  - 禁止并发打乱同一批语句的顺序；禁止把多结果集只留最后一个。
  - 禁止在事务进行中切换连接或目标库。
  - 禁止把「用户取消」写进执行记录的成功分支。
- 并发·幂等·事务：同一连接上串行（服务内部串行队列）；查询幂等，写不自动重试；手工事务由调用方驱动 `beginTransaction` / `commit` / `rollback`。
- 日志字段：`connection_id`、`statement_index`、`elapsed_ms`、`error_code`、`row_count`；禁记结果行数据与凭据。
- 测试 ID：`T-3.3-01`（顺序与选区）、`T-3.3-02`（取消即止）、`T-3.3-03`（空 SQL）

### 3.4 `DatabaseService.cancel(_:)`

- 所属单元：`Core/DatabaseService.swift` ｜ 对应概设条款：概要设计 §4.4
- 用途：让服务端语句真被取消，并把结局如实交回界面。
- 前置条件：
  - [ ] `handle` 属于当前连接且由本连接的一次 `execute` 产生
  - [ ] 该次执行仍处于执行中（已结束的句柄走同一路径返回既有结局）
- 后置条件：
  - [ ] 返回 `CancelOutcome`：成功取消 / 服务端已结束 / `failed(reason:)`
  - [ ] 成功取消后流不再产出 `resultSet`；半截结果不落历史库
  - [ ] 连接保持可用（取消不等于断开）
  - [ ] 重复取消返回同一结局，不产生第二次服务端动作
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 句柄不属于本连接 | `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 否 | 禁止「尽力取消」后报成功 |
| 方言不支持取消 | `EXEC_CANCEL_FAILED` | `CancelOutcome.failed(reason:)` | 否 | 禁止只停界面接口而不停服务端 |
| 连接已断 | `EXEC_CONNECTION_LOST` | `CancelOutcome.failed(reason:)` | 人工 | 禁止把连接标成不可用 |
| 服务端拒绝 | `EXEC_CANCEL_FAILED` | `failed(reason:)` 带上服务端原话 | 人工 | 禁止把原话改写成模糊文案 |

- 禁止行为：
  - 禁止用「关掉界面进度条」冒充取消成功。
  - 禁止在取消后清空已有结果（已收到的结果集照常保留）。
- 并发·幂等·事务：以 `handle` 为幂等键；并发重复取消只发一次服务端请求，其余等同一结局；不在锁内做网络等待。
- 日志字段：`connection_id`、`handle_id`、`outcome`、`elapsed_ms`；禁记 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.4-01`

### 3.5 `ExecutionSafety.check(sql:databaseType:policy:)`

- 所属单元：`Core/ExecutionSafety.swift` ｜ 对应概设条款：概要设计 §4.3、§7.1
- 用途：执行前判定「允许 / 需确认 / 直接拒绝」，结论只读一次。
- 前置条件：
  - [ ] `sql` 非空（空串由上层拦，本函数返回 `allow` 不得被当作放行依据）
  - [ ] `policy` 必传；`policy.isReadOnly` 是连接属性，总开关关掉也不得绕过
  - [ ] 语句切分按 `databaseType` 的方言规则进行
- 后置条件：
  - [ ] 返回 `.allow` / `.needsConfirmation(reasons:findings:statements:)` / `.refused(reasons:statements:)`
  - [ ] `refused` 必带可显示原因与涉事语句（`readOnlyRefusal` 生成的文案非空）
  - [ ] 结论在本次执行内不再改判：界面状态变化不得翻转已下的结论
  - [ ] 不修改入参、不落盘、不发网络
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 只读连接遇写语句 | `EXEC_READONLY_DENIED` | `.refused(reasons:statements:)` | 否 | 禁止退化成 `needsConfirmation` 让用户点过去 |
| 无 WHERE 的 UPDATE/DELETE | `EXEC_CONFIRM_REQUIRED` | `.needsConfirmation(...)` | 不适用（等人确认） | 禁止先执行后补确认 |
| DROP / TRUNCATE | `EXEC_CONFIRM_REQUIRED` | `.needsConfirmation(...)` | 不适用 | 禁止强制确认策略关闭时放行生产连接 |
| 语句切分失败 | `EXEC_SERVER_ERROR` | `.needsConfirmation` 并把原文列入 findings | 否 | 禁止把切分失败当 `allow` |

- 禁止行为：
  - 禁止返回空原因的 `refused`；禁止把原因写成「不允许」这类无信息文案。
  - 禁止在判定里读界面状态（页签是否脏、按钮是否灰）。
  - 禁止为「生产标签连接」这类未实现特性造旁路开关（标签与只读连接联动尚未实现，登记于 §10.1）。
- 并发·幂等·事务：纯函数，无共享可变状态；同一 `(sql, policy)` 结论恒定；不持有事务。
- 日志字段：`decision`、`reason_code`、`statement_count`；禁记完整 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.5-01`

### 3.6 `AgentApprovalGate.grant(fingerprint:at:)`

- 所属单元：`Core/AgentApprovalGate.swift` ｜ 对应概设条款：概要设计 §5.4、§6.3
- 用途：把用户的批准按次消费到某条待审语句上，并落一条不可重放的消费记录。
- 前置条件：
  - [ ] `fingerprint` 对应一条 `pending` 审批单（由 `request` 造出）
  - [ ] `at` 由调用方给（时钟注入，见 §2.2）
  - [ ] 该 `fingerprint` 尚未被消费（消费集合不含它）
- 后置条件：
  - [ ] 返回 `AgentApprovalVerdict`；批准路径必落一条 `AgentApprovalConsumption`
  - [ ] 消费记录追加式写入，不覆盖既有行
  - [ ] 同一条批准不可重放：第二次 `grant` 同一 `fingerprint` 返回 `.missing`
  - [ ] 审批终态只前进不后退：`approved` 之后不改回 `pending`
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无该审批单 | 不适用（判决值） | `.missing` | 否 | 禁止把 `.missing` 当通过 |
| 已拒绝 | 不适用（判决值） | `.denied(requestID:)` | 否 | 禁止 `denied → approved` 翻转 |
| 已过期 | 不适用（判决值） | `.expired(requestID:)` | 否 | 禁止 `expired → approved` 翻转 |
| 依赖超时（写消费记录失败） | 不适用 | 抛 `AppError.persistence` | 人工 | 禁止在消费记录未落盘时返回 `.approved` |

- 禁止行为：
  - 禁止把 `pending` / `denied` / `expired` / `.missing` 四档任一当通过。
  - 禁止一次批准复用到另一条语句（`fingerprint` 与语句清单一对一）。
  - 禁止在回执里写口令、连接串原文、敏感字面量。
- 并发·幂等·事务：以 `fingerprint` 为幂等键；消费写入与判决返回在同一原子操作里；并发 `grant` 同一 `fingerprint` 只允许一次成功，其余得 `.missing`。
- 日志字段：`request_id`、`fingerprint`、`verdict`、`at`；禁记语句原文。
- 测试 ID：`T-3.6-01`

### 3.7 `MetadataService.loadChildren(of:)`

- 所属单元：`Core/MetadataService.swift` ｜ 对应概设条款：概要设计 §4.5
- 用途：按数据库类型返回某节点的下一层对象，供对象树展开。
- 前置条件：
  - [ ] 已连接；`object` 来自同一次连接的 `loadRoot()` 或上一层的 `loadChildren`
  - [ ] `object.kind` 属于该方言支持的层级（服务器 → 库 → schema → 表/视图 → 列）
- 后置条件：
  - [ ] 返回 `DatabaseObject` 数组，每项带名称、种类、是否有子节点
  - [ ] 层级形状随 `databaseType` 变化，不做跨类型强制统一
  - [ ] 刷新不清空用户已选中节点（选中态由界面按 `id` 保留）
  - [ ] 不返回任何占位节点（除真正的加载中态由界面渲染）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 该类型不支持该层级 | `META_UNSUPPORTED` | 抛出并说明层级差异 | 否 | 禁止拿上一层的对象冒充子节点 |
| 服务端查询失败 | `META_FAILED` | 抛出服务端原话 | 人工 | 禁止返回空数组冒充「没有对象」 |
| 未连接 | `EXEC_NO_CONNECTION` | `AppError.notConnected` | 否 | 禁止自动连第一个连接 |
| 依赖超时 | `META_FAILED` | 抛出（含耗时） | 是，重试 1 次，退避 300 ms | 禁止超时后返回部分结果并标成功 |

- 禁止行为：
  - 禁止把不同数据库类型的层级强行统一成一种。
  - 禁止在树里伪造「加载中」以外的占位节点。
  - 禁止把结果写进任何缓存而不带过期判定。
- 并发·幂等·事务：读取幂等；同一节点并发展开只发一次请求（`ObjectTreeRefreshGate` 合并）；不持有事务。
- 日志字段：`connection_id`、`object_kind`、`child_count`、`elapsed_ms`；禁记列注释原文中的敏感内容。
- 测试 ID：`T-3.7-01`

### 3.8 `RowBrowsingQuery.browse(table:schema:filter:dialect:)`

- 所属单元：`Core/RowBrowsing.swift` ｜ 对应概设条款：概要设计 §4.6
- 用途：生成「前 N 行 + 服务端过滤 + 服务端排序」的查询语句。
- 前置条件：
  - [ ] `table` 非空；`schema` 可为 nil
  - [ ] `filter.limit` > 0 且默认 200；`filter.where` / `orderBy` 未经转义时拒绝
  - [ ] `dialect` 必传（标识符引用与分页语法随方言）
- 后置条件：
  - [ ] 返回可执行 SQL 文本；行数上限、排序、过滤全部落在语句里，不由前端过滤
  - [ ] 标识符经 `SQLGenerator.qualifiedName` 转义；不拼接用户原串
  - [ ] 同一 `(table, filter, dialect)` 生成逐字节一致的语句
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 过滤条件非法（空 WHERE 值 / 非法 ORDER BY） | `DATA_WRITE_CONFLICT` 不适用；此处 `BuildError` | `Result.failure(BuildError)` | 否 | 禁止忽略坏条件返回全表 |
| 表名含非法标识符 | `META_UNSUPPORTED` | `Result.failure(BuildError)` | 否 | 禁止直接把表名拼进 SQL |
| 行数上限越界 | 不适用 | 夹到 1…上限并由界面提示 | 否 | 禁止静默夹取不提 |
| 依赖超时 | 不适用（纯字符串生成） | 不适用 | 不适用 | 禁止在此处发起 IO |

- 禁止行为：
  - 禁止把整表读进内存再截断前 N 行。
  - 禁止前端排序冒充服务端排序。
  - 禁止在只读连接上生成写语句（本函数只生成 `SELECT`）。
- 并发·幂等·事务：纯函数；不持有事务；并发调用互不影响。
- 日志字段：`table`、`limit`、`elapsed_ms`；禁记 `where` 里的字面量。
- 测试 ID：`T-3.8-01`

### 3.9 `AppState.applyRowEdits(_:on:key:)`

- 所属单元：`App/AppState.swift` ｜ 对应概设条款：概要设计 §4.6
- 用途：把行编辑按主键写回，逐行报结局。状态：**未实现**（登记于 §10.1），本签名为实现时的目标契约。
- 前置条件：
  - [ ] 结果集存在可定位标识（主键或唯一键），否则不开放行编辑入口（`DATA_NO_PK`）
  - [ ] 连接非只读（`policy.isReadOnly == false`）
  - [ ] 每条改动带旧值快照，写回语句带主键条件与旧值条件
- 后置条件：
  - [ ] 逐行返回结局：成功 / 影响 0 行（冲突）/ 失败（原话）
  - [ ] 影响 0 行必须报 `DATA_WRITE_CONFLICT`，不得当成功
  - [ ] 成功的行更新本地快照；失败的行保留用户输入
  - [ ] 写回语句逐条执行，不并发
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无可定位标识 | `DATA_NO_PK` | 不开放入口并说明原因 | 否 | 禁止按「全列相等」猜行 |
| 影响 0 行 | `DATA_WRITE_CONFLICT` | 逐行结局：冲突 + 原话 | 人工（重新读行） | 禁止当成功；禁止整批回滚后报成功 |
| 服务端拒绝 | `DATA_WRITE_FAILED` | 逐行结局：失败 + 原话 | 否 | 禁止改写成模糊文案 |
| 只读连接 | `EXEC_READONLY_DENIED` | 拒绝并不渲染写入口 | 否 | 禁止只灰掉按钮 |
| 依赖超时 | `DATA_WRITE_FAILED` | 逐行结局：失败 | 人工 | 禁止自动重发写语句 |

- 禁止行为：
  - 禁止无 WHERE 的整表写回。
  - 禁止把「部分行成功」汇总成一条成功提示。
  - 禁止在写回途中重新排列行的执行顺序。
- 并发·幂等·事务：以主键为幂等键；同一行重复写回结果一致（旧值条件不满足时报冲突）；一批写回在一个事务内，冲突行不阻断其他行，但必须逐行如实上报。
- 日志字段：`connection_id`、`table`、`row_key`、`outcome`、`affected_rows`；禁记列值原文。
- 测试 ID：`T-3.9-01`

### 3.10 `SchemaScriptRunner.run(script:previewed:confirmedTableName:)`

- 所属单元：`Core/TableDesign.swift` 与新增执行闸 ｜ 对应概设条款：概要设计 §4.7
- 用途：在「已预览 + 已二次确认」两个前提下执行结构脚本。状态：**未实现**（登记于 §10.1），`TableDesign.validate(tableName:columns:)` 已实现并列定义校验。
- 前置条件：
  - [ ] `script` 由 `TableDesign` 生成且与预览时展示的文本逐字节相同
  - [ ] `previewed == true`（未预览直接拒绝）
  - [ ] 删除类动作必须手输表名且与目标表相等（`confirmedTableName`）
  - [ ] 连接与任务均非只读；任务影响行数上限未越界
- 后置条件：
  - [ ] 返回执行结局与回执读数（成功/失败、耗时、错误原文）
  - [ ] 删表语句带「存在才删」语义
  - [ ] 执行后写执行记录与审计；「预览成功」不得记为「执行成功」
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 未预览即执行 | `DDL_PREVIEW_REQUIRED` | 拒绝并回预览步骤 | 否 | 禁止把脚本当普通查询静默执行 |
| 未二次确认 | `DDL_CONFIRM_REQUIRED` | 拒绝并要求确认 | 否 | 禁止默认确认 |
| 只读连接或只读任务 | `EXEC_READONLY_DENIED` | `.refused` | 否 | 禁止为 DDL 开旁路 |
| 服务端拒绝 | `DDL_FAILED` | 抛出服务端原话 | 人工 | 禁止改写成模糊文案 |
| 依赖超时 | `DDL_FAILED` | 抛出（含语句） | 人工（重跑需重新预览） | 禁止超时后自动重发 DDL |

- 禁止行为：
  - 禁止跳过预览；禁止把预览文本与实际执行文本分成两份来源。
  - 禁止在生成的脚本里写入用户数据或口令。
  - 禁止对影响行数超上限的任务继续执行。
- 并发·幂等·事务：同一表同一时刻只允许一个结构变更任务（以表名为锁键）；DDL 不幂等，重跑需重新预览与确认；执行期不与其他写语句共用事务。
- 日志字段：`connection_id`、`table`、`script_kind`、`previewed`、`outcome`、`elapsed_ms`；禁记脚本里的敏感字面量。
- 测试 ID：`T-3.10-01`（预览闸）、`T-3.10-02`（只读与上限）

### 3.11 `ResultExporter.text(for:format:tableName:schema:dialect:)`

- 所属单元：`Core/ResultExporter.swift` ｜ 对应概设条款：概要设计 §4.8
- 用途：把结果集渲染成 CSV / JSON / TSV / Markdown / INSERT 文本。
- 前置条件：
  - [ ] `format` ∈ `ResultExportFormat` 闭集
  - [ ] 结果集列结构完整（列名非空、行数与列数一致）
  - [ ] 生成 INSERT 时 `dialect` 非空（标识符引用随方言）
- 后置条件：
  - [ ] 返回字符串；列顺序与 `result.columns` 一致
  - [ ] 单元格内的分隔符、引号、换行按格式规范转义
  - [ ] 同一 `(result, format, tableName, schema, dialect)` 输出逐字节一致
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 格式不在闭集 | `IO_FORMAT_UNSUPPORTED` | `AppError.notImplemented` | 否 | 禁止生成不支持格式的空文件 |
| 编码与格式组合不适用 | `IO_FORMAT_UNSUPPORTED` | `ResultExportEncodingError.notApplicableToFormat` | 否 | 禁止静默忽略编码参数 |
| 列结构不齐 | `IO_PARTIAL` | 抛出并指明列名 | 否 | 禁止补空列后照常导出 |
| 依赖超时 | 不适用（纯内存渲染） | 不适用 | 不适用 | 禁止在此处读整表到内存 |

- 禁止行为：
  - 禁止把口令、连接串原文、凭据引用写进导出文本。
  - 禁止在导出路径上先把整表载入内存（流式写由调用方按批喂入）。
  - 禁止按界面当前排序改写结果顺序（顺序以结果集为准）。
- 并发·幂等·事务：纯函数；不持有事务；不共享可变状态。
- 日志字段：`format`、`row_count`、`column_count`、`elapsed_ms`；禁记单元格原文。
- 测试 ID：`T-3.11-01`

### 3.12 `TableImport.plan(source:target:mapping:mode:)`

- 所属单元：`Core/TableImport.swift` ｜ 对应概设条款：概要设计 §4.8
- 用途：把导入源按目标列映射编成可执行计划（逐条 INSERT 或 `COPY` 批次），并在落地前校验。
- 前置条件：
  - [ ] `source` 的列数与 `mapping` 一致；`mapping` 每项指向目标表真实列
  - [ ] `mode` ∈ `ImportWriteMode` 闭集（新建 / 追加 / 覆盖）
  - [ ] 覆盖模式下目标表存在性已询问过用户并得到明确答复
- 后置条件：
  - [ ] 返回 `Plan`：语句批次、每批行数、目标列顺序
  - [ ] 值类型转换按 `valueType(forTypeName:)` 判定；不可转的值进 `invalidValues`
  - [ ] 批次划分固定（不随机分批），同一输入同一切分
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目标已存在且未确认 | `IO_TARGET_EXISTS` | 拒绝并回询问 | 不适用（等答复） | 禁止静默覆盖既有表 |
| 部分行不可转 | `IO_PARTIAL` | 返回 `invalidValues` 明细 | 人工 | 禁止丢坏行后报全部成功 |
| 列不匹配 | `IO_FORMAT_UNSUPPORTED` | 抛出并指明列 | 否 | 禁止按位置硬塞 |
| 导入中途失败 | `IO_PARTIAL` | 逐批结局：成功批与失败批 | 人工 | 禁止留半张表且不告知 |
| 依赖超时 | `IO_PARTIAL` | 逐批结局：失败批 | 人工 | 禁止超时后自动重发整批 |

- 禁止行为：
  - 禁止在失败后静默删除已导入数据来「假装没发生」。
  - 禁止在方言不支持 `COPY` 时悄悄退回逐条 INSERT 而不告知。
  - 禁止把凭据或连接串写进导入日志。
- 并发·幂等·事务：以「目标表 + 批次序号」为幂等键；同一批重跑会重复写入，故重跑前必须清目标或换模式；批次各自成事务，不做跨批大事务。
- 日志字段：`table`、`batch_index`、`row_count`、`invalid_count`、`elapsed_ms`；禁记行值原文。
- 测试 ID：`T-3.12-01`

### 3.13 `SessionMonitor.sessions(from:)`

- 所属单元：`Core/SessionMonitor.swift` ｜ 对应概设条款：概要设计 §4.9
- 用途：把服务端会话查询结果映射成会话列表（进程号、用户、库、状态、等待事件、已运行时长、当前 SQL）。
- 前置条件：
  - [ ] `result` 的列名可被识别（兼容 `pg_stat_activity` 与 `SHOW PROCESSLIST` 两套命名）
  - [ ] 已连接且当前用户有读会话视图的权限
- 后置条件：
  - [ ] 返回 `ServerSession` 数组；无法解析出进程号的行被丢弃并可报数
  - [ ] 多行 SQL 压成一行供列表显示（`summarize(_:limit:)`）
  - [ ] 时长由 `elapsedSeconds(since:now:)` 计算，解析失败返回 nil 并显示原始字符串
  - [ ] 只映射，不发取消、不终止任何会话
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无权限读会话视图 | `SESS_KILL_DENIED` 不适用；此处 `META_UNSUPPORTED` | 抛出并说明缺哪个权限 | 否 | 禁止显示空列表冒充「没有会话」 |
| 时间戳形态不可解析 | 不适用（返回值） | `nil`，界面显示原串 | 不适用 | 禁止猜一个时长 |
| 终止会话（动作路径） | `SESS_KILL_DENIED` | 上浮服务端原话 | 否 | 禁止无二次确认就终止 |
| 终止前未确认 | `SESS_KILL_REQUIRED_CONFIRM` | 拒绝 | 不适用 | 禁止默认确认 |
| 依赖超时 | `META_FAILED` | 抛出（含耗时） | 是，重试 1 次 | 禁止超时后返回半份列表并标成功 |

- 禁止行为：
  - 禁止不说明「会掐断连接并回滚未提交事务」就执行终止。
  - 禁止把「读列表」与「终止」合成一个动作。
  - 禁止在会话视图里展示其他连接的会话（作用域限当前连接）。
- 并发·幂等·事务：读取幂等；终止动作不幂等，重复终止报 `SESS_NOT_FOUND`；不在事务内终止。
- 日志字段：`connection_id`、`session_count`、`action`、`target_pid`、`outcome`；禁记会话当前 SQL 原文中的敏感字面量。
- 测试 ID：`T-3.13-01`

### 3.14 `AgentContext.assemble(_:limits:)`

- 所属单元：`Core/AgentContext.swift` ｜ 对应概设条款：概要设计 §4.10
- 用途：把当前连接、库表、选中 SQL 的文本与标识装配成投给助理的上下文摘要。
- 前置条件：
  - [ ] 每条 `AgentContextReference` 指向当前工作区可见对象
  - [ ] 含结果行数据时必须带用户显式确认标记；无标记即拒
  - [ ] `limits` 给出单段与总长上限
- 后置条件：
  - [ ] 返回可核对的摘要（投了什么、多长、是否含行数据）
  - [ ] 含行数据的投递写一条审计（谁、何时、哪条连接、投了什么类型）
  - [ ] 凭据、连接串原文、口令一律被 `filterSecretsOnly` 剥掉
  - [ ] 超限内容是报错，不静默截断
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 含行数据未确认 | `BRIDGE_ROW_DATA_REQUIRES_CONFIRM` | 拒绝并说明需确认 | 不适用（等确认） | 禁止静默投递行数据 |
| 上下文为空 | `BRIDGE_EMPTY_CONTEXT` | 拒绝 | 否 | 禁止投一条空上下文占位 |
| 超长 | `BRIDGE_EMPTY_CONTEXT` 不适用；超限按错误返回 | 抛出超限说明 | 人工（缩小范围） | 禁止静默截断后当完整上下文 |
| 依赖超时 | 不适用（本地装配） | 不适用 | 不适用 | 禁止在装配期发起网络调用 |

- 禁止行为：
  - 禁止投递凭据或连接串原文。
  - 禁止让助理据此直接执行写操作而不经 §3.6 的审批链。
  - 禁止把「自动附带」当默认值（概要设计 §14.1 第 6 条：默认关闭，仅显式勾选时附带并写审计）。
- 并发·幂等·事务：装配幂等（同输入同摘要）；不持有事务；审计为追加写，不覆盖。
- 日志字段：`connection_id`、`reference_count`、`contains_row_data`、`total_chars`、`at`；禁记被投递的正文。
- 测试 ID：`T-3.14-01`

### 3.15 `AgentStandardDispatcher.dispatch(_:approvals:)`

- 所属单元：`Core/AgentStandardDispatcher.swift` ｜ 对应概设条款：概要设计 §18.1
- 用途：执行一个模型发起的工具调用，返回观察值。
- 前置条件：
  - [ ] `invocation` 的工具名在 `AgentToolRegistry` 里已登记
  - [ ] 参数 JSON 通过 `AgentToolSchemaValidator.validate(argumentsJSON:against:)`
  - [ ] 需审批的工具，其 `fingerprint` 在 `approvals` 集合里且已被消费
- 后置条件：
  - [ ] 返回 `AgentToolOutcome`；拒绝类返回 `AgentToolRefusal` 机器码
  - [ ] 观察值有界：超限报错，不静默截断
  - [ ] 每次调用留审计（工具名、参数摘要、结局）
  - [ ] 拒绝时不产生任何副作用（不写文件、不执行 SQL）
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 工具未登记 | `META_UNSUPPORTED` | `AgentToolOutcome` 失败 + 机器码 | 否 | 禁止执行未登记工具 |
| 参数不合规 | `CONN_INVALID_CONFIG` 不适用；返回模型可读错误 | 失败 + 校验明细 | 是（模型改参数后重试） | 禁止「宽容解析」后照执行 |
| 未获审批 | `EXEC_CONFIRM_REQUIRED` | `AgentToolRefusal` | 不适用（等审批） | 禁止绕过审批执行写操作 |
| 工具内部超时 | `EXEC_SERVER_ERROR` | 失败 + 原因码 | 是，重试 1 次（仅只读工具） | 禁止对写工具自动重试 |

- 禁止行为：
  - 禁止在参数不合规时执行工具再报错。
  - 禁止对写类工具自动重试。
  - 禁止把异常事件文案写进界面字符串（文案由语言表按机器码映射）。
- 并发·幂等·事务：同一回合内工具串行；写类工具不幂等，重跑需重新审批；预算耗尽即结束回合（`AgentLoopLimits`），不静默续命。
- 日志字段：`tool_name`、`arguments_summary`、`outcome`、`elapsed_ms`、`request_id`；禁记完整参数里的敏感字面量。
- 测试 ID：`T-3.15-01`

### 3.16 `AgentPlanRows.estimate(json:)`

- 所属单元：`Core/AgentPlanRows.swift` ｜ 对应概设条款：概要设计 §5.4
- 用途：把 `EXPLAIN (FORMAT JSON)` 的结果解析成影响行数预估四档结论。
- 前置条件：
  - [ ] `json` 来自 `EXPLAIN (FORMAT JSON) <DML>`，且该语句不带 `ANALYZE`
  - [ ] 非 DML 或多语句时上游不应调用本函数（`explainStatement(for:)` 返回 nil）
- 后置条件：
  - [ ] 返回四档之一：有值 / `noAnswer` / `parseFailed` / 上游原因码（`notDataChange`、`dialectUnsupported`、`noConnection`）
  - [ ] 根节点为 `ModifyTable` 一类且 `Plan Rows` 为 0 时取 `Plans` 的第 0 项（坑见 §13.1）
  - [ ] 取不到就返回 `noAnswer` / `parseFailed`，不返回 0
  - [ ] 结果只作批准前参考读数，不参与任何执行判定
- 错误契约：

| 场景 | 错误码 | 抛出/返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 没有 JSON | 不适用（结论值） | `.unavailable("noAnswer")` | 不适用 | 禁止用表总行数填充 |
| 解析失败 | 不适用（结论值） | `.unavailable("parseFailed")` | 不适用 | 禁止返回 0 当「没有影响行」 |
| 非数据变更语句 | 不适用（上游码） | `.unavailable("notDataChange")` | 不适用 | 禁止给非 DML 造一个数 |
| 方言不支持 | 不适用（上游码） | `.unavailable("dialectUnsupported")` | 不适用 | 禁止换用 `ANALYZE` 取数 |
| 依赖超时 | 不适用（解析本地 JSON） | 上游已收不到结果，走 `noConnection` | 不适用 | 禁止本地估算 |

- 禁止行为：
  - 禁止为了拿到数而执行 `EXPLAIN ANALYZE`。
  - 禁止把预估写回审批单的「已确认」字段（审批与读数是两件事）。
  - 禁止把读数写进契约文档（读数只进台账）。
- 并发·幂等·事务：纯解析；幂等；不持有事务；不发网络。
- 日志字段：`conclusion`、`plan_node`、`duration_ms`；禁记完整执行计划 JSON。
- 测试 ID：`T-3.16-01`

---

### 3.17 `AgentCommandRunner.run(_ command: String, in directory: URL, timeout: TimeInterval) async -> CommandOutcome`

- 对应概设条款：概要设计 §3 组件契约（命令执行）· §4 接口契约 · §11.4 `PERF-006`
- 用途：在本机跑**一条**命令，带回标准输出、标准错误与退出码。**它是 Agent 侧唯一起进程的入口**。
- **执行面（2026-10-31 改）**：命令进 **Agent 专用的交互式 shell（PTY，`AgentShellSession`）** 跑，不再每条命令起一个独立进程。理由三条：① 人在终端面板里看得见它在敲什么；② 同一条会话内 `cd` / 环境变量 / 函数跨命令延续；③ 多行脚本、heredoc、管道原样可用（不再只能靠 `sh -c` 拼）。
- 会话按**工作区根**建一条并复用；首次派活时在终端面板开「Agent」页签显示它（页签只是显示面，关页签不终止这条 shell）。
- 与用户自己的终端页签**不共用**同一条 shell：两条会话各自的光标、历史、输入互不干扰。

**前置条件**
- `directory` 必须是用户已授权的工作区目录（`WorkspaceAccessScope` 判定为真）；未授权 ⇒ 直接返回 `.refused(.directoryNotAuthorized)`，**不落任何进程**。
- `command` 非空且不含 NUL；`timeout` ∈ [1, 600]，缺省取配置 60 s。

**后置条件**
- 成功：返回 `.finished(exitCode:stdout:stderr:truncated:)`，`exitCode == 0` 才算成功。
- 失败：返回 `.finished(exitCode: != 0)` 或 `.timedOut` / `.refused(reason)`，**三者互斥且必须有一个**。
- 输出超 2000 行或 1 MB ⇒ `truncated = true`，内容按行截断，**不静默吞**。
- **回收协议**：写入的是「命令 + 取退出码 + 打印哨兵行」三段；读到 `<SENTINEL>:<退出码>` 才算这一条跑完。PTY 会把写入内容回显一遍，回收时按整段匹配剔除（匹配不上按行剔），不把命令本身混进输出。
- 同一时刻**只受理一条**：上一条没回收完时第二条立即返回「上一条还在跑」，不排队（排队会让两段输出在同一缓冲里串起来）。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 目录未授权 | `.refused(.directoryNotAuthorized)` | 否 | 不启动进程 |
| 长时间独占前台的程序（全屏 TUI） | 超时后 `.timedOut`（发 Ctrl-C 打断） | 是（同一命令最多 1 次） | 现在是真 TTY，能起；但不能让它把这一轮拖死 |
| 危险形态（`DROP DATABASE` / `rm -rf` / 改系统路径 / 下载即执行） | 先出审批单（含完整命令），**批准前不启动** | 否 | 审批拒绝 = `.refused(.approvalDenied)` |
| 超时 | `.timedOut` | 是（同一命令最多 1 次，超时不自动重试） | 进程必须被**终止并回收**，不留下孤儿 |
| 二进制不存在 | `.finished(exitCode: 127, stderr: …)` | 是（同一命令最多 1 次，超时不自动重试） | 原样回传，不翻译成「未知错误」 |

**禁止行为**
- 禁止把模型给的参数**不加引号**拼进命令行：argv → 命令行的转换只在 `AgentLocalCommandRunner.shellLine` 一处做，每个参数单独加单引号（内部的 `'` 按 `'\''` 转义）。命令原文本身仍走同一张审批单。
- 禁止与用户终端页签**共用**同一条 shell，也禁止由页签关停 Agent 的会话。
- 禁止在**主线程**或界面同步链路上起进程（`dispatch` 的同步桥已在主线程上直接拒：`runCommandOnMainThread`）。
- 禁止把非零退出码包装成「已完成」，也禁止在输出里塞进自己编的摘要替代原文。

**并发 / 幂等 / 事务**
- 同一会话内**串行**执行（一个 runner 一条跑道）；并发发起时排队，不并行起两个进程。
- 无事务概念；命令本身的副作用由审批与审计兜底，本层不做回滚。

**日志字段**（写审计，不写会话正文）
- 必记：`commandHash`（sha256 前 16 位）· `directory`（绝对路径）· `exitCode` · `durationMs` · `truncated` · `approvalID`（有审批时）。
- 禁记：命令的完整原文（脱敏后只留前 120 字）· 任何口令 / token · 标准输出原文。

**测试 ID**：`T-3.17-01`（正例：退出码 0 且带回 stdout）· `T-3.17-02`（负例：未授权目录被拒且未起进程）· `T-3.17-03`（负例：超时被终止且不留孤儿）· `T-3.17-04`（负例：危险形态进审批，拒绝后未执行）


### 3.18 `AgentCodeRunner.run(_ code: String, language: AgentCodeLanguage, in directory: URL) async -> CodeOutcome`

- 对应概设条款：概要设计 §3 组件契约（代码执行）· §11.4 `SEC-005`（默认零外发）

**前置条件**：`directory` 为授权工作区目录；`language` ∈ {python, shell}（本机已装版本，缺失则 `.refused(.interpreterMissing)`）；`code` 非空。

**后置条件**：`.finished(exitCode:stdout:stderr:truncated:)` / `.timedOut` / `.refused(reason)` 三选一且必有一个；临时文件落会话临时目录并在返回前删除。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 解释器未安装 | `.refused(.interpreterMissing)` | 否 | 报「未安装 <lang>」，不自动联网安装 |
| 超时（默认 30 s） | `.timedOut` | 否 | 子进程终止并回收 |
| 内存超 512 MB | `.refused(.memoryLimit)` | 否 | 内核级限制，先于 OOM |
| 试图联网 | `.refused(.networkForbidden)` | 否 | 沙箱无网络出口；命中即拒并记审计 |
| 退出码非零 | `.finished(exitCode: != 0)` | 是（同一段最多 1 次） | 原样回传 stderr |

**禁止行为**：禁止继承宿主全部权限；禁止写授权目录外路径；禁止在界面线程运行；禁止把失败包装成「已完成」。

**并发 / 幂等 / 事务**：同会话串行；每次运行独立临时目录；无事务（改盘走 §3.1 `edit_file`）。

**日志字段**：必记 `codeHash`（sha256 前 16 位）· `language` · `exitCode` · `durationMs` · `truncated`；禁记代码原文与 stdout 全文。

**测试 ID**：`T-3.18-01`（正例：退出码 0 且带回 stdout）· `T-3.18-02`（负例：试图联网被拒且零外发）· `T-3.18-03`（负例：超时终止、临时目录已清）

### 3.19 `AgentToolCatalog.search(_ query: String, limit: Int) async -> [AgentToolCandidate]`

- 对应概设条款：概要设计 §3 组件契约（工具目录）

**前置条件**：`limit ∈ [1,20]`（超上限按 20 截断）；`query` 非空。

**后置条件**：返回候选（名 / 用途一句 / 来源内置或接入）；同一会话内 schema 取回后缓存，二次取回不发请求；未取回 schema 的调用由派发层拒绝。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 无匹配 | `[]` + `hint = .noSuchTool` | 是（换词） | 不回退到全表 |
| 超过 limit | 截断 + `remaining` 计数 | 否 | 界面显示「还有 N 件」 |
| 接入类工具离线 | 该件标 `unavailable` | 是 | 目录仍返回，不整表失败 |

**禁止行为**：禁止把全部工具塞进上下文；禁止替模型选择；禁止对未登记名字静默回退。

**并发 / 幂等 / 事务**：只读，可并发；同 query 结果 60 秒内复用。

**日志字段**：必记 `queryHash` · `hitCount` · `limit`；禁记 query 原文（含用户意图）。

**测试 ID**：`T-3.19-01`（按用途检索命中内置与接入两类）· `T-3.19-02`（未取回 schema 直接调用被拒）

### 3.20 `AgentOrchestrator.run(_ tasks: [Subtask], options: OrchestrationOptions) async -> [SubtaskOutcome]`

- 对应概设条款：概要设计 §3 组件契约（并行编排）· §11.4 `AI-004`（配额与超时）

**前置条件**：`tasks` 非空且两两**无依赖**（有依赖者由调用方先排序，本层不猜顺序）；`options.maxConcurrency` ∈ [1,8]，缺省 4；每个 `Subtask` 带 `id`、`goal`、`workdir`；子任务 `depth` 必须为 0（**禁止再派**）。

**后置条件**：返回数组与输入**等长同序**，每项含 `id` / `outcome`（finished / failed / timedOut / cancelled）/ `summary` / `artifactPaths`；超并发上限的任务**排队后仍全部执行完**；单路失败不改变其余各项。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 有依赖却并发提交 | `.refused(.dependencyCycleOrOrder)` | 否 | 先排序再提交 |
| 超并发上限 | 排队（不报错） | — | 按到达序启动 |
| 单路超时（默认 10 min） | 该路 `.timedOut` | 否 | 终止该路，其余继续 |
| 子执行体试图再派 | 该路 `.failed(.nestedDelegationForbidden)` | 否 | 深度锁死为 0 |
| 需审批动作 | 主控出审批单，该路挂起等待 | 是（批准后继续） | 子执行体不得代签 |

**禁止行为**：禁止把有依赖的步骤并发；禁止无上限并发；禁止让子执行体继承主控的凭据与授权；禁止归并时收整段上下文（只收摘要与产物路径）。

**并发 / 幂等 / 事务**：并发度由 `options.maxConcurrency` 控制；同一 `Subtask.id` 重复提交幂等（返回已有结局）；无跨子任务事务。

**日志字段**：必记 `runID` · 每路 `subtaskID` / `outcome` / `durationMs` / `depth`；禁记子任务 prompt 原文（只记 `goalHash`）。

**测试 ID**：`T-3.20-01`（三路并行全部完成且等长同序）· `T-3.20-02`（并发上限 4：第 5 路排队后仍完成）· `T-3.20-03`（一路失败其余不受影响）

> 2026-11-04 真机点验后补的三条**隔离约束**（子路事件不混主对话 / 子预算按子循环截止 / 同 id 重派换会话号）见 **§3.30**；本节只讲编排能力面，隔离约束不在本节重复。

### 3.21 `AgentContextCompression.admit(at:) -> CompressionAdmission` —— 压缩只在会话边界发生

- 对应概设条款：概要设计 §18.2 上下文先验（`FR-AGT-CORE-CTX`）· §18.22 结果自验的预算口径
- 对应需求：`FR-AGT-KNOW-CTX-002`（超限时有损但如实地压）· `FR-AGT-CORE-LOOP-009`（150 步 / 256K）

**前置条件**：`at` 属于四类**会话边界**之一 —— ①会话开始前（新会话装载历史）②用户显式 `/compact` ③会话结束落盘前 ④网关侧会话过期回收。当前回合的 token 读数取自 `AgentModelMeter`（含 prompt + completion 的实测量，不用估算值）。压缩器可用（`AgentContextCompression` 已就绪且有策略）。

**后置条件**：返回 `CompressionAdmission`，四种结局之一：`.runNow(boundary:)` / `.deferToBoundary(next:)` / `.skip(reason:)` / `.refuse(reason:)`。`.runNow` 时压缩产物必须附带三样可读输出：①压缩后仍能回答「刚才决定了什么」（决策与约束保留）②明确写出「丢了什么类别」（细节 / 冗长正文 / 重复调用结果）③压缩前后 token 读数。**回合内（turn 中）任何调用只允许返回 `.deferToBoundary`**，同时另外产出 `AgentBudgetReport` —— 预算报告是唯一允许在回合内说话的东西，改写上下文不是。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 回合内被要求压缩 | `.deferToBoundary(next:)` | — | 记一条 `compressDeferred` 日志，不当错误 |
| 无可用压缩器 | `.skip(.noEngine)` | 否 | 如实说「这次没压」，不许假装压过 |
| 压缩后仍超上限 | `.refuse(.stillOverLimit(before:after:))` | 否 | 报「压完还是超」，**不许静默截断** |
| 会话边界判定不明（跨进程恢复） | `.skip(.boundaryUnknown)` | 是（下一轮再判） | 由 `AgentTurnResumeStore` 给出边界证据 |

**禁止行为**：禁止 per-turn 压缩（这是本节存在的原因 —— Hermes 在 `context_engine.py` 里把这条写成生命周期注释，我们落成判据）；禁止在压缩里删掉用户显式要求保留的约束（灵魂条款 / 审批结论 / 未完成待办）；禁止把「压缩失败」当错误重试（重试会二次耗预算）；禁止压缩时改写已发出的历史（只改下一轮装载的内容）。

**并发 / 幂等 / 事务**：同一会话同一时刻只允许一个压缩任务（`sessionID` 维度串行）；压缩期间新回合**排队**不并发；同一 `(sessionID, boundary)` 重复调用幂等，返回首次结局。

**日志字段**：必记 `sessionID` · `boundary` · `beforeTokens` / `afterTokens` · `droppedKinds[]` · `durationMs` · `outcome`；**禁记**被压缩正文（只记类别与字数）。

**测试 ID**：`T-3.21-01`（回合内不压）· `T-3.21-02`（边界压且保留决策）· `T-3.21-03`（压完仍超限如实报）

### 3.22 `AgentToolRegistry.snapshot(for: AgentProfile) -> ToolCatalogSnapshot` —— 注册表唯一真源，可见性由 profile 决定

- 对应概设条款：概要设计 §18.1 循环与工具（`FR-AGT-CORE-LOOP`）· §18.18 MCP（`FR-AGT-LINK-EXT`）
- 对应需求：`FR-AGT-CORE-LOOP-005`（唯一出处）· `-006`（内置 8 个）· `-010`（按需发现）· `-011`（目录口径）

**前置条件**：注册表已加载完成且**每个工具只有一处声明**（名称 + `schemaJSON` + 权限等级 + 审批策略 + 指纹）；`profile` ∈ {`.terminalShell`, `.graphicalShell`, `.subagent`} 且带可见集合（白名单为空 = 继承全量）。

**后置条件**：返回不可变快照，含 `tools[]`（`name` / `source(builtin|mcp)` / `visible` / `fingerprint`）与 `omittedCount`。**可见性只决定「能不能被发现与调用」，不决定「实现是哪一份」** —— 同一个工具在终端壳与图形壳里必须指向同一 handler 标识；目录检索与 schema 缓存按 §3.19 口径（未取回 schema 不许调用）。快照在会话期内不可变，新增工具只能重载注册表（指纹变化必须留痕）。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 名字未登记 | `.refused(.toolNotRegistered(name))` | 否 | 提示「没有这个工具」，不回退全表猜测 |
| 已登记但在本 profile 不可见 | `.refused(.toolNotVisibleInProfile(name, profile))` | 否 | **不许伪装成「不存在」** —— 两者对用户是不同信息 |
| schema 未取回就调用 | `.refused(.schemaNotFetched(name))` | 是（先取 schema） | 与 `FR-AGT-CORE-LOOP-010` 同源 |
| 同名两处声明 | 注册期直接报 `.duplicateDeclaration(name)` | 否 | 停装载，不取后者 |

**禁止行为**：禁止在任何第二处硬编码工具清单（含界面侧的「工具开关」）；禁止按壳各写一套实现（壳只决定看得见，不决定能力）；禁止拿可见性当权限用（权限与审批走 §3.6，可见 ≠ 可执行）；禁止在运行期热改快照。

**并发 / 幂等 / 事务**：注册表加载期串行，加载完成后只读；`snapshot(for:)` 幂等（同一 profile 同一指纹返回同一内容）；无事务语义（注册表不是业务数据）。

**日志字段**：必记 `toolName` · `profile` · `visible` · `source` · `fingerprint`；拒绝时另记 `refusalCode`。

**测试 ID**：`T-3.22-01`（重复声明停装载）· `T-3.22-02`（不可见 ≠ 不存在，两种提示不同）· `T-3.22-03`（同一工具两壳指向同一 handler）

### 3.23 `AgentContextEngine` 生命周期钩子协议 —— 钩子只挂在真实边界上

- 对应概设条款：概要设计 §18.2 上下文先验 · §18.23 可观测（`FR-AGT-OPS-OBS`）
- 对应需求：`FR-AGT-KNOW-CTX-002` · `FR-AGT-OPS-OBS-001`（能回答「刚才为什么这么做」）

**前置条件**：会话已创建；引擎实现已注册（当前唯一实现 = 默认压缩引擎，未开放第三方插件选择）。五个钩子固定顺序与时机：`onSessionStart()` → 每响应 `updateFromResponse(_:)` → 每轮 `shouldCompress()` / `compress()`（判据见 §3.21）→ **`onSessionEnd()` 只在真实会话边界**（CLI 退出 / 会话重置 / 网关过期回收）。

**后置条件**：每个钩子返回 `HookOutcome`（`.ok` / `.degraded(reason:)` / `.failed(code:)`），**任何钩子失败都不得中断会话主循环** —— 记一条降级日志后继续；`onSessionEnd` 每次真实会话结束**恰好触发一次**（不重复、不遗漏）。钩子只读写会话上下文，不改用户内容、不发阻塞网络请求。

**错误契约**

| 情形 | 返回 | 可重试 | 说明 |
|---|---|---|---|
| 钩子抛错 | `.failed(code:)` 上浮给可观测层，会话继续 | 否（本轮不重试） | 不许把钩子错误升格成会话错误 |
| 回合内被调 `onSessionEnd` | 直接拒（`.refused(.notASessionBoundary)`） | — | 边界判定权在会话层，不在调用方 |
| 同一 session 重复 `onSessionEnd` | 幂等返回首次结局 | — | 网关过期与 CLI 退出可能同时到 |
| 引擎未注册 | `.skipped(.noEngine)` | 否 | 如实报「没有引擎」，不假装 |

**禁止行为**：禁止 per-turn 触发 `onSessionEnd`；禁止钩子里做重试风暴或长阻塞；禁止钩子改写历史消息正文；禁止新增第六个钩子而不改本节（钩子集是封闭集合，加一个要走版本与矩阵）。

**并发 / 幂等 / 事务**：钩子串行执行，与会话生命周期同一 actor；`updateFromResponse` 可高频调用但必须无副作用累积（幂等）；`compress` 与 §3.21 的串行约束一致；无事务语义。

**日志字段**：必记 `hook` · `sessionID` · `durationMs` · `outcome` · `degradedReason?`；`onSessionEnd` 另记 `boundaryKind`（cliExit / sessionReset / gatewayExpiry）。

**测试 ID**：`T-3.23-01`（真实结束触发一次）· `T-3.23-02`（钩子抛错不中断会话）· `T-3.23-03`（回合内调 end 被拒）

### 3.24 记忆写入 / 检索 / 冲突 / 上下文账本（**未建**）

- 对应概设条款：概要设计 §18.9 记忆 · §18.10 项目上下文
- 对应需求：`FR-AGT-KNOW-MEM-006`（写入过闸）· `-007`（相关性检索）· `-008`（冲突）· `-009`（上下文账本）· `FR-AGT-KNOW-CTX-003`（项目规则文件）

**为什么单列一条**：核对时发现这五件事**都没有落点** —— 记忆只有读（`AgentMemoryContext.references` 挂进上下文），`AgentMemoryStore.record()` 除测试外**零调用点**，盘上连记忆目录都没有；技能只有声明式登记与披露，没有沉淀。本节是**待建契约**，建成前不许在台账上标 ✅。

**落点（各一个文件，判据与实现同批）**

| 能力 | 落点 | 判据 |
|---|---|---|
| 写入过闸 | `Core/AgentMemoryWriteGate.swift`（**已建 2026-10-28**：73 行，触发三态 + 内容闸 + `superseding`；判据 `Tests/AgentMemoryWriteGateTests` 9 例）（三档拒因 + 来源轮次 + 同键覆盖）+ 工具登记 `remember_memory` / `forget_memory`（等级 = 写入、逐次审批） | `Tests/AgentMemoryWriteGateTests` |
| 相关性检索 | `Core/AgentMemoryRetrieval.swift`（打分：词命中 + 类别 + 时间衰减；**命中理由逐条可解释**；宁可少给） | `Tests/AgentMemoryRetrievalTests` |
| 冲突消解 | `Core/AgentMemoryConflict.swift`（同键新者胜、旧值留档可查、冲突留记录） | `Tests/AgentMemoryConflictTests` |
| 上下文账本 | `Core/AgentContextLedger.swift`（五段 token 与占比、被裁条目逐条点名、只读） | `Tests/AgentContextLedgerTests` |
| 项目规则文件 | 读 `AGENTS.md` / `DOYAH.md` / `.doyah/rules`（只读，带路径进上下文；找不到明说）—— **已建 2026-10-28**：`Core/AgentProjectRules.swift`（142 行）+ `AgentContextReference.projectRule`（排上下文最前）+ App 接线 | `Tests/AgentProjectRulesTests` **10 例**（已绿） |
| 技能沉淀 | `Core/AgentSkillSedimentation.swift`（只从成功且被确认的任务抽、可检视可作废、只动登记档） | `Tests/AgentSkillSedimentationTests` |

**禁止行为**：禁止把记忆写入做成「模型觉得重要就静默落库」；禁止按时效平铺最近 N 条冒充检索；禁止同键两条同时进上下文；禁止账本改写正文；禁止规则文件进可写面。

**测试 ID**：`T-3.24-01`（无指令不落库）· `T-3.24-02`（相关命中、无关不进）· `T-3.24-03`（同键新者胜、旧值可查）· `T-3.24-04`（账本逐段报数且只读）· `T-3.24-05`（规则文件读入带路径 / 找不到明说）· `T-3.24-06`（只抽成功且被确认的做法）

### 3.25 IM 通道凭据：扫码接入 / 手填 / 自检

- 对应概设条款：概要设计 §18.17「IM 凭据」不变量
- 对应需求：`FR-AGT-LINK-CHAN-003`（判据 ④ 扫码接入 · ⑤ 自检）

**为什么单列**：这条跨五轮交付（配置面 → 入站 → 官方 REST 外发 → 扫码 → 分页与自检），当时只落在需求书 / 概设 / 台账，**详设一直没有契约级描述** —— 换人接手只能读代码猜边界，而这一条里恰好有「凭据不许落明文」「扫码后返回的是真凭据」这类一读错就要出事的地方。

| 能力 | 落点 | 契约要点 | 判据 |
|---|---|---|---|
| 桥输出解析 | `Core/AgentIMQRLogin.parse(line:)` | 只认 `qr` / `expired` / `success` / `failed` 四种事件；`success` 缺 AppID 或 AppSecret ⇒ `failed`（半套凭据一律不落库）；空行、非 JSON、未知事件返 `nil`（噪声不许当事件） | `Tests/AgentIMQRLoginTests`（14 例） |
| 状态机 | `Core/AgentIMQRLogin.next(_:event:)` | 四档 `idle` / `showing` / `expired` / `succeeded` / `failed`；**成功即定稿**（新码与过期通知不许打回）；`expired` 记住上一张码；`showing` 期间 `allowsRestart == false`（不许重复起进程） | 同上 |
| 起桥参数 | `AgentIMQRLogin.launchArguments` / `.environment` | 只传脚本路径（不留参数注入面）；连接器入口可用 `DOYAH_QQ_CONNECTOR_ENTRY` 覆盖，其余继承宿主环境 | 同上 |
| 桥进程 | `Scripts/qq-qr-bridge.mjs` | 走官方 `@tencent-connect/qqbot-connector` 的**ESM 入口**（其 CJS 在本机 `require` 直接抛）；逐行 JSON 到 stdout；`SIGTERM` 时释放连接器；构建期复制进 `Contents/Resources` | 桥脚本自检用例（源码含 `startQrConnect` 与四个事件名）+ 本机实测出码 |
| 自检 | `Core/AgentIMSelfCheck.problems(_:)` | 五项事实（配置在盘 / AppID / AppID 纯数字 / Secret 在钥匙串 / 环境）→ **有顺序**的问题清单，`configFileMissing` 排第一；`receiveTasks` 关闭**不算缺陷** | `Tests/AgentIMSelfCheckTests`（6 例） |
| 落库 | `AppState.saveAgentIMCredentials(appID:secret:)` | AppID 进 `im-channel-qq.json`、Secret 只进钥匙串；扫码产出与手填走**同一个**入口 | `Tests/AgentIMCredential*`（既有） |
| 入站确认（ack） | `Core/AgentIMInboundRun.swift` | 收到任务**立刻回一条「收到」**，再开始跑；旧实现跑完才回，用户在聊天里等几十分钟看不到任何回应 | `Tests/AgentIMInboundRunTests`（收到即 ack，且 ack 在首条进度前） |
| 进度节流 | `Core/AgentIMProgress.swift` | 长任务按**时间窗**推进度（同一窗口内多次进展只发一条），既不刷屏也不静默 | 同上（窗口内 5 条进展 → 只发 1 条；跨窗口各发 1 条） |
| 失败落盘 | `Core/AgentIMInboundRun.swift` | 跑崩/超时要把**失败原因**写进会话与日志，并在聊天里回一句人话；旧实现只回「没有结论」 | `Tests/AgentIMRunPathTests`（失败路径带原因码，不回「没有结论」） |
| 重复调用闸 | `Core/AgentRepeatGuard.swift` | 同一条入站消息在**未结束前**重复到达 ⇒ 不重复起跑（返回「已在处理」），结束后的重发按新任务处理 | `Tests/AgentRepeatGuardTests`（并发两条同 id：只起一次） |
| 通知与角标 | `App/AgentNotificationPoster.swift` | 后台跑完发系统通知；**ad-hoc 签名下系统可能静默丢弃**，因此同时置 Dock 角标兜底；角标随「看过/收尾」清 | `Tests/AgentNotificationBadgeTests`（角标在收尾后清、被激活秒清不再复现） |

**禁止行为**：禁止界面自判「已连上」（必须收到一帧或取到 token）；禁止把半套凭据落库；禁止在 Swift 侧另写一套扫码协议；禁止关窗 / 取消时不杀子进程；禁止把「用户选择不收任务」写成缺陷。

**测试 ID**：`T-3.25-01`（噪声行不被当事件）· `T-3.25-02`（缺一半凭据判失败）· `T-3.25-03`（成功即定稿，晚到的码与过期通知不改状态）· `T-3.25-04`（自检问题顺序：配置未落盘排第一）· `T-3.25-05`（桥脚本存在于包内且声明四事件）。

### 3.26 工作区外访问（越界授权）

- 对应概设条款：「越界授权（工作区外访问）」行 + 「命令执行」行的默认边界
- 对应需求：`FR-AGT-CORE-LOOP-006` 验收要点 ④ / `FR-STD-WS-AI-002`

**为什么单列**：主人 2026-10-31 原话——「在沙箱运行没问题，但如果授权了也可以访问沙箱外的文件或执行命令啊」。
此前实现是硬边界（`outsideWorkspace` 直接拒）：批准只能授权「这一次工具调用」，没有任何一条路能让人主动把边界打开一次。
这属于**设计没写细**，不是实现走偏，所以先把契约补在这一节，再改代码。

| 环节 | 契约 | 落点 |
|---|---|---|
| 路径解析 | 先把目标绝对化、再判是否在工作区根以内（`standardizedFileURL` + 符号链接解引用后比较） | `AgentWorkspaceTools.resolve` |
| 工作区内 | 行为不变：读直接做；写 / 改照旧走审批 | 同上 |
| **工作区外** | **不再 `.refused(.outsideWorkspace)`**，改为 `.needsApproval`，单上写明「越界：<绝对路径>（工作区：<root>）」；**在批准之前一个字节都不动** | `prepareWrite` / `prepareEdit` / `prepareCommand` |
| 指纹 | `工具名 \| 绝对路径 \| 参数摘要`。**越界单的路径必须是绝对路径**：同一个相对路径在不同工作区指向不同文件，用相对路径会让「在别处批过的那次」在这边也算数 | `AgentApprovalRequest.fingerprint` |
| 放行 | `granted` 命中指纹才允许越界；**一次一单**，用完不残留（不做「本会话永久放行」） | `writeFile` / `editFile` / `readFile` / `runCommand` |
| 命令越界 | `cd` 到工作区外、或参数里出现工作区外绝对路径 ⇒ 出单；批准后才执行，且 shell 的 cwd 变更如实镜像到「Agent」页签 | `AgentCommandPolicy.assess` + `AgentShellSession` |
| 拒绝 / 超时 | 如实回报 `denied:outsideWorkspace`，**不自动重试**；超时按拒绝（与 `AgentLoopContext.approvalDecision` 的 600s 一致） | `AgentLoop` |
| 审计 | 单上目标落审计：`outside:<绝对路径>`；批准与拒绝各一条 | `AgentAuditSink` |

**禁止行为**：禁止越界静默放行；禁止把一次批准记成永久放行；禁止按工具名放行（换参数必须重新出单）；
禁止把越界目标折算成工作区相对路径；禁止在越界单没批的情况下先落盘再报「等审批」。

**测试 ID**：`T-3.26-01`（越界读：出单、盘上零改动）· `T-3.26-02`（批准后读到）· `T-3.26-03`（同一单换参数 ⇒ 重新出单）·
`T-3.26-04`（拒绝 ⇒ 停，不重试）· `T-3.26-05`（`cd` 到工作区外 ⇒ 出单）· `T-3.26-06`（越界单的指纹用绝对路径：换工作区不认旧批准）

### 3.27 联网工具（`web_search` / `fetch_url`）

- 对应概设：§18.12【契约】网络检索；对应需求：`FR-AGT-TOOL-INGEST-001` / `-004`、`NFR-AGT-TOOL-INGEST-001`
- 对应能力：能力书 §3.5.2

**为什么单列**：2026-10-31 主人报「Doyah Agent 没有联网工具」。查下来不是没设计，是**没接线，而且书里标了完成**：

| 事实 | 证据 |
|---|---|
| `fetch_url` 登记了但**从未启用** | `Core/AgentToolRegistry.swift` 里 `stage: .secondBatch, enabled: false` |
| 连 `web_search` 这个工具都不存在 | `AgentToolCapability` 枚举里无联网检索项 |
| 一单却把 `FR-AGT-TOOL-INGEST-001` 标成 ✅✅ | 备注栏是「—」，没有任何实现文件 —— 这正是铁律 #2 / #15 要防的形态 |

**工具契约**

| 工具 | 能力 | 参数 | 等级 / 审批 | 回灌（给模型看的） |
|---|---|---|---|---|
| `web_search` | `webSearch`（新增） | `query`（string，必填）· `limit`（int，默认 5，上限 10） | 只读 / 不弹审批 | `search:<n> 条` + 每条「标题 — URL」+ 摘要（有界截断） |
| `fetch_url` | `fetchURL`（已有，本次启用） | `url`（string，必填）· `maxBytes`（int，可选） | 只读 / 不弹审批 | `fetch:<finalURL>:<bytes>B` + 正文纯文本（HTML 转文本），截断如实标注 |

**检索后端（可配置）**

| 梗 | 契约 |
|---|---|
| 协议 | `AgentWebSearchBackend.search(query:limit:) async throws -> [AgentWebSearchHit]` |
| 默认 | `DuckDuckGoHTMLBackend`：`POST https://html.duckduckgo.com/html/`，表单 `q`；取 `result__a` 标题与链接、`result__snippet` 摘要；`//duckduckgo.com/l/?uddg=<真实地址>` 要解回真实 URL |
| 备用（国内） | `BingBackend`：`GET https://cn.bing.com/search?q=&count=`，桌面 UA（Bing 对非浏览器 UA 回空结果页，实测）；解析 `<li class="b_algo">` 块 |
| 自动链 | `auto` = 配了 Tavily key ⇒ `[Tavily, DuckDuckGo, Bing]`，没配 ⇒ `[DuckDuckGo, Bing]`；**仅在「后端整个不可用」（网络层拿不到回应）时换下一个**；`noResults` / 鉴权失败 / 限流都不换（换了就是把「没有」说成「有」，或者让人以为在用付费后端） |
| 可选 | `TavilyBackend`：`POST https://api.tavily.com/search`，`apiKey` 从凭据库取（**不进日志、不进审计、不回显**）；映射 `results[].title/url/content` |
| 选择 | 设置项 `webSearch.backend ∈ {auto, duckduckgo, tavily}`；`auto` = 有 Tavily key 走 Tavily，否则 DDG |
| 失败三态 | `notConfigured`（没配后端）/ `unavailable`（被限流、网络不通、鉴权失败，**带原始原因**）/ `noResults`（通但确实零命中）—— **三句不同的话，不许混成「没找到」** |
| 禁止 | Tavily 鉴权失败时**静默回落**到 DDG（会让人以为在用付费后端）；任何情况下**编造结果** |

**抓取边界（`NFR-AGT-TOOL-INGEST-001`，负例必须判红）**

| 检查 | 口径 |
|---|---|
| scheme | 只许 `http` / `https`；`file:` / `data:` / `javascript:` 一律拒 |
| host | 解析后拒环回（127/8、::1）、私网（10/8、172.16/12、192.168/16）、链路本地（169.254/16、fe80::/10）、唯一本地（fc00::/7）、`.local`；**每次重定向都要重校验** |
| 超时 | 单次 20 秒（连接 + 读取合计）；超时给可读错误，不重试第二次 |
| 重定向 | 手动跟随，最多 5 跳，只跟 `http(s)` |
| 体量 | 上限 2 MB；`Content-Type` 非文本类（HTML/JSON/纯文本）直接拒并说明 |
| 外发身份 | 固定 UA `DoyahStudio/<version>`；**不带 Cookie、不带凭据、不带 Referer** |

**审计**：每次外发一条 `web:<method> <host><path>`；query 参数原样记（便于复盘），**任何 key / token 不进审计**。

**测试 ID**：`T-3.27-01`（DDG 空配置可搜）· `T-3.27-02`（填 Tavily key 后走 Tavily 且设置显示后端）·
`T-3.27-03`（Tavily key 无效 ⇒ 报鉴权失败、不静默回落）· `T-3.27-04`（零命中报 `noResults`，不报错也不编）·
`T-3.27-05`（`fetch_url 127.0.0.1` / `10.0.0.1` / `file:///etc/passwd` 全拒 —— **负例**）· `T-3.27-06`（重定向到内网被拦）·
`T-3.27-07`（超时与截断都有可读标注）。

### 3.31 搜索工具引擎：随包 ripgrep + 三级回落

> **上游**：概设 §3 组件契约「检索（工作区检索与 `search` 工具）」· §11 依赖清单（随包命令行工具 / 可选加速路径）· §10 被拒绝的替代方案（依赖现场工具 vs 随包）· `P-28`（引擎来源与降级）。

**落点**：`Core/AgentRipgrep.swift`（引擎 / 定位 / 加速）、`Core/AgentWorkspaceTools.swift:532-545`（`searchStructured` 优先走 rg，`nil` 时 `??` 回落）、`Scripts/build-app.sh`（打包 + 逐个 Mach-O 签名 + `codesign -v` 验签）。

**契约（三段）**
1. **顺序固定**：随包 `Contents/Resources/tools/rg` → PATH 里的 `rg` → 内置 `WorkspaceSearch.findFileNames/findContents`。前两级任一不可用（缺失、无执行权、架构不符 `EBADARCH`）都必须**静默落到下一级**，不许抛错、不许返回空集。
2. **语义差异必须写死**（搜索行为不是逐字节等价）：rg 只做**大小写不敏感**匹配、**不折叠变音符号**（`cafe` 搜不到 `café`）；行号按 `\n` 计；命中超上限时两条路径截到的是**不同子集**。界面侧标头搜索/替换仍走 `WorkspaceSearch` 本体，不受 rg 影响。
3. **许可与平台边界**：随包 `rg` 为 ripgrep 15.2.0（Unlicense / MIT），`COPYING` 与 `LICENSE-MIT` 随包，`THIRD-PARTY-NOTICES.md` 设「随包命令行工具」条目。**仅 macOS arm64**；Windows 侧需各自提供 `rg.exe`（不在本次范围，缺失即回落）；Intel/universal 包会 `EBADARCH` 并回落。

**判据（`Tests/AgentRipgrep*` / `Tests/AgentSearchBudgetProbeTests`）**
- `T-3.31-01` 同词同机：工具级 `search()` **1413ms → 61ms（23×）**，命中 **231 = 231**、文件集 **2334 = 2334** 双向差集 0；
- `T-3.31-02` 降级：把 rg 改名 / `chmod 644` ⇒ `accelerate` 返回 `nil`、`search` 仍出 231 条（与 rg 臂同集），不抛错不空；
- `T-3.31-03` 打包面：`Contents/Resources/tools/rg` 存在、可执行、`codesign -v` 与 `--deep --strict` 均 rc=0；`THIRD-PARTY-NOTICES.md` 命中 ripgrep 条目；
- `T-3.31-04` 预算与缓存（配合 §3.14 工具面）：多词一次调用返回多组、包含关系命中缓存（`cached` + `partial`）、只读工具每轮上限（search/list_dir 各 6，0 = 不限）。

**未覆盖 / 边界**：rg 与内置实现在「变音符号」与「超上限截断子集」上不等价（上面第 2 段已声明，不做等价承诺）；Windows 侧 `rg.exe` 未提供。


### 3.32 搜索策略：多词 / 缓存 / 只读工具预算

> **上游**：概设 §3 组件契约「检索」行（多词分组 / 缓存作废 / 截断如实 / 只读工具每轮预算）· `P-28`；需求 `FR-AGT-CORE-LOOP-004` ⑥、`FR-AGT-CORE-LOOP-006` ⑤。

引擎（§3.31）解决「用谁扫」，本节解决「**怎么问、问几次、重复问要不要再扫**」——2026-11-07 真机一轮 26 步 149.6 秒里，`search` 被以近义词反复调用十余次（`会话时间太长` / `会话超时` / `会话时间` / `会话`…），每次全仓重扫。

**策略四条（全部落在 `Core`，界面与 CLI 共用）**
1. **多词一次搜**：`query` 按空白/逗号拆词（或直接传 `queries: [String]`），**一次遍历返回按词分组的命中**；回灌文本必须写明「本次已搜过这 N 个词」，否则模型会换个词再来一遍。
2. **同轮缓存**（`Core/AgentSearchCache.swift`）：键 =（工作区根，规范化后的词）；同词**直接命中**；**包含关系**（已搜 `会话时间太长`，再搜 `会话时间`）从缓存里筛出子串命中并标 `cached=true, partial=true`；TTL **60 秒**；**写 / 改 / 跑命令立即整表作废**（结果不可信比慢更糟）。
3. **只读工具每轮预算**（`Core/AgentRepeatGuard.swift`）：按**能力**记账而非精确参数——`search` 6 次、`list_dir` 6 次为默认上限（`0` = 不限，保留旧行为）；到顶回灌「先用已有结果给结论，或把词一次放进 `queries`」。**精确参数去重拦不住近义改写**，这是这条策略存在的理由。
4. **忽略与截断**：`Vendor` / `node_modules` / `.build` / `dist` / `.git` 进忽略集合（本仓 90 万文件里绝大部分属这几类）；单文件大小上限、命中上限、每文件上限保持既有默认，截断必须**如实报数**（`truncated`），不许静默少给。

**判据**
- `T-3.32-01` 一次传 3 词 ⇒ **1 次调用返回 3 组**，回灌含「本次已搜过这 3 个词」；
- `T-3.32-02` 包含关系 ⇒ 第二次 `cached=true / partial=true` 且耗时 **0ms**（反例：关缓存 ⇒ 回到 350ms 级别，判红）；
- `T-3.32-03` 连调 7 次 `search` ⇒ 第 7 次被 `tool-budget` 拦下、前 6 次正常执行（反例：预算设 0 ⇒ 7 次全放行，判红）。

**读数**：6 近义词连搜 **2213ms → 1174ms（一把给）**，配合真机模型往返 ≈9s/次 ⇒ 6 次变 1 次，单轮省约 **45 秒**；缓存命中 **424ms → 0ms**。


### 3.33 对话区展示优先级：结论默认展开、过程信息默认折叠

> **上游**：概设 §8.11 ⑤（工具进度默认摘要 / 长消息预览默认关）· §8.11 ⑦（过程区阶段形态）· §8.11 ⑧（信息层级 / 未核断言告警）；需求 `FR-AGT-UX-CONV-003` ⑧⑪。

由头：人类主人 2026-11-07 真机 ——「**结论竟然折叠起来，却把 29 个 claims 全展开放屏幕上**，而且我也不懂这些 claims 有什么用。hermes 最终的界面就是**思考和其他对用户没用的信息都是默认折叠不占地方**，只把用户的问题和结论呈现出来」。

两处**优先级倒置**（同一条缺陷的两半）：`assistantBody` 按「长消息预览」（当时的默认 `2+2`）把**结论本身**折成首 2 末 2 行；`noticeRow` 把断言台账（机器头 + 29 条断言 + 每条下面的出处行）**整块铺开**，一条不折、无上限。要读的折了，不该读的铺满一屏。

**契约三条（写死，不许按条数或屏高动态裁决）**
1. **结论默认展开**：助手正文（含代码块）默认**整段呈现**。「长消息预览」（`display.longPreview`）的契约默认值由 `2+2` 改为 **`off`** —— 它折的正是结论本身；开关仍在（**显式 opt-in**），打开后才折，且折叠处必须有 `… 展开`。
2. **过程信息默认折叠 + 限高 + 内部滚动**：断言台账（claims）· 思考段 · 执行步骤详单 —— 三者一律「摘要行 + 高度上限 + 内部滚动」，**高度只由常量决定，与条数 / 行数无关**。
3. **未核断言必须一行告警**：台账里存在「没验证」的断言时，折叠那一行**就是**告警（`⚠ 8 条断言没有依据（共 29 条）`，警示色）；全部已核则那一行是普通汇总（`✓ 29 条断言 · 已核 29 / 未核 0`）。**禁止**只在展开区里呈现。

| 块 | 落点 | 默认形态 | 高度常量 |
|---|---|---|---|
| 结论（助手正文） | `App/Views/AgentChatView.swift`（`assistantBody` / `conclusionBody`）+ `Core/AgentAnswerSplit.swift`（`AgentAnswerClassifier`，边界见 §3.33.1 ②）+ `Core/AgentDisplayPreferences.swift`（`contractDefault = .off` 与 v1→v2 迁移） | **整段**（含代码块） | 不设上限（结论就该看完） |
| 断言台账 claims | `App/Views/AgentClaimAuditRow.swift:30/36/42`（一行 + 明细）+ `Core/AgentClaimTrace.swift:107/171/225`（机器头 / `AgentClaimAudit` / `parse`）+ `App/Views/AgentChatView.swift:415`（`noticeRow` 认机器头） | **一行** | 折叠 `summaryHeight = 20pt`；展开 `expandedMaxHeight = 262pt`（= 20 + 间距 2 + 明细上限 **240pt**） |
| 思考区（过程独白 + 思考段，**一轮一个区**） | `App/Views/AgentProcessBlocks.swift`（`AgentThinkingZone`）+ `Core/AgentTurnThinking.swift`（一轮的段聚合，§3.33.4）+ `Core/AgentAnswerSplit.swift`（`AgentThinkingFold` / `AgentThinkingManualState`）+ `Core/AgentThinkingStream.swift`（视口常量 / 跟随判定 / 合并器，§3.33.2） | **运行中展开 / 任一终态折一行 / 手动动过本轮内 sticky**（§3.33.1 ③）；**整轮一个区**、区内按步轻分隔（§3.33.4） | 折叠 `collapsedHeight = 20pt`；展开**整块恒 200pt**（抬头 20 + 发丝 2 + 视口 178，定高不跟内容长），内容内部滚动 |
| 工具调用块 | `App/Views/AgentProcessBlocks.swift`（`AgentToolBlockView`）+ `App/Views/AgentChatChrome.swift`（`AgentToolBlockSummary`） | **一行摘要** `▸ 56 次工具调用 · 8.2s · 展开`（§3.33.1 ④） | 折叠 20pt；展开整块 **238pt**（抬头 20 + 发丝 2 + 行体 216 ≤ 240pt），行体内部滚动 |
| 执行步骤详单 | `App/Views/AgentStepListPanel.swift`（§3.29 / §3.31 已落，本节不改） | 表头 + **2 行** | 收起 `collapsedHeight`（≈ 80pt）/ 展开 `maxHeight = 168pt` |

**台账为什么折成一行、而不是删掉**：claims 是**审计台账**（每条 = 「这句话我有没有依据」，`FR-AGT-QUAL-VERIFY-003/004`），**不是阅读内容**。删掉等于把「凭什么」丢了；全展等于把台账糊在结论上。折成一行 + 记账可展开，是这一条要求的形状。

**机器头**：台账落进消息流的那段文本，首行是**语言无关的计数** `claims:总/已核/推断/未核`（例 `claims:29/21/0/8`），界面据此算「折成一行、要不要告警」。为什么不是那句人话汇总：切个语言就认不出，判据会绑在文案上。人话（汇总行 / 告警 / 组头「已验证 21 条」）一律由界面按当前语言现算（L-47）。**没有机器头的时间线事件不归这条管** —— 界面继续按 `noticeText` 原样画那一行灰字（`finished` / `monitor:stalled` 等）。

**判据**（`TestsUISnapshot/AgentChatAnswerPriorityProbeTests.swift`，`DOYAH_UI_SNAPSHOT=1` 才跑；Core 侧 `Tests/AgentClaimTraceTests.swift`）
- `T-3.33-01` 29 条台账 + 一段 30 行结论（真 `AgentChatView`，900×620）：结论**可见高 455pt**（> 0）；台账只多占 **24pt = 一行 20 + 块间距 4**；条数 29 → 300 对话区内容高**逐点不变**（523pt = 523pt）；对话区视口 517.5pt 不缩；
- `T-3.33-02` 未核 8 ⇒ 折叠行文案「8 条断言没有依据（共 29 条） · 展开看依据」+ 字形 `⚠`；全部已核 ⇒「29 条断言 · 已核 29 / 未核 0 · 展开看依据」+ 字形 `✓`，且**不出现**「没有依据」；
- `T-3.33-03` 展开 ⇒ 262pt（29 条与 300 条**同高**）、宿主里 **1 个**内部滚动容器、明细上限 240pt；
- `T-3.33-04` **反例必须判红**（同一套判据函数）：明细无上限 **1296pt**、整块台账原样铺 **885pt**、结论按 `2+2` 折（藏 25 行）、台账整块铺进消息流使整页内容高 **1373pt**（比只有结论的 499pt 多 **874pt**）。

**禁止行为**
- 禁止把断言台账 / 思考段 / 步骤详单**按条数**铺进对话区（高度必须由常量封顶）；
- 禁止把「未核断言」的告警藏进展开区（展开才看得见 = 没有）；
- 禁止为了让「长消息预览」这个开关「有落点」去折结论（结论是交付物，折它就是本节要修的那个缺陷）；
- 禁止把台账明细从消息流里删掉（那是审计留痕；折起来不等于不记）。

#### 3.33.1 过程信息的默认折叠与结论可见性

主人装上 beta1.0.3 后仍报三条：① 「Doyah Agent 里输出的『**我先读一下……再……**』这是思考过程吗？」② 「**最新的版本仍然是把结论折叠了**」③ 「claim 已经折叠了」，但「**tools 调用了最终还没折叠起来**」。三条各是一个独立根因，不许当成一条「再调调参数」。

**① 旧库偏好的一次性迁移（结论为什么「还是折」）**

上一批只把 `contractDefault` 改成 `off`，那只管**新装机器**。显示开关是**持久化偏好**（`agent-display-preferences.json`，`Core/AgentDisplayPreferences.swift`），已装用户盘上仍是当年按旧默认写下的 `2+2`。契约：

- 盘上 `version < 2` **且** `display.longPreview` 恰好等于**旧契约默认** `2+2` ⇒ 视为「当年那份默认」，载入时迁到 `off`，并由 `AppState.loadAgentDisplayPreferencesIfNeeded()` **写回**一次（v2），此后不再迁；
- v1 格式里「用户显式选过 `2+2`」与默认值**不可区分** —— 这是格式的事实，不在这一层假装能分辨；迁移只做一次，写回 v2 之后用户再自己设 `2+2` 就按他的选择存（`Tests/AgentDisplayPreferencesTests` 三条钉住：迁、只迁一次、非默认值不迁）；
- 写不进盘**不改结论**：这一屏照样按 `off` 显示（迁移在内存里已经完成）。

**② 「哪一段算结论」——四条判定规则**（`Core/AgentAnswerSplit.swift` 的 `AgentAnswerClassifier`）

1. **按段切**：空行分段；**围栏代码块（``` / ~~~）永不切开**（切了就是把结论的代码块撕成两半）。
2. **一段是不是过程独白**，两个信号任一成立：
   a. **过程自述开头**（去掉列表符号 / 标题井号 / 引用号 / 数字编号之后）：`我先` `我要先` `我得先` `让我先/让我看/让我读/让我查` `我来看/我来读/我来查` `我先看/我先读/我先查` `我再看/我再读/我再查` `再看/再读` `先看一下/先读一下/先确认` `接下来我` `然后我` `现在我先` `我首先/首先我`；英文 `Let me` / `I'll` / `I will` / `I'm going to` / `First,` / `Now let me`（大小写不敏感）。
   b. **续接式独白**：含省略号（`…` 或 `...`）**且**含「再 / then」，且这一段不含围栏代码块（「我先读一下 A……再决定改哪里」这种把话留到下一步的收尾）。单看省略号不算、单看「再」也不算 —— 结论里两者都常见。
3. **结论 = 末尾那一段连续的非独白段**（从最后一段往前收，遇到独白段就停）。末段自己就是独白时**仍按结论给它**（不许把整条消息折成 0 —— 那比铺开更坏）。
4. **段内再切一句**：结论段若以过程自述开头（「我先读一下 A。」后面接结论），把开头那几句自述挪进独白；剩下为空就不切（宁可不切，也不许切没）。

**轮内位置**（`AgentChatTurnShape`）：一轮（两次用户提问之间）里**最后一条**助手消息 = 结论，其余 = 中间叙述（整条进思考区）。位置是确定的事实；「长短 / 有没有代码块」是启发式，猜会引出第二个答案。

**③ 思考区三态（主人 2026-11-07 拍的产品决策，覆盖「一律默认折叠」）**

过程独白（以及开关打开时的 `reasoning_content`）**只住思考区**，正文区一个字都不留 —— 主人问的那句「我先读一下……再……」就是归到这里，不是正文。判定在 `Core/AgentAnswerSplit.swift`（`AgentThinkingFold` / `AgentThinkingManualState`），渲染在 `App/Views/AgentProcessBlocks.swift`（`AgentThinkingZone`）：

| 状态 | 形态 | 高度 |
|---|---|---|
| **运行中（本轮未结束）** | **默认展开**，可流式增量；用户可手动收起 | 整块**恒 200pt**（抬头 20 + 发丝 2 + 视口 178），内容内部滚动（§3.33.2 ②） |
| **任一终态（完成 / 失败 / 取消）** | **自动折成一行**摘要：`思考过程 · 12 步 · 18.4s · 展开` | **20pt**（`collapsedHeight` = 一行） |
| **用户手动动过** | 以用户为准，且**本轮内保持**（sticky） | 展开同 200pt；收起同 20pt |
| **新轮开始** | 手动态**清空** ⇒ 回到「按阶段默认」 | — |

摘要行**必须带步数与耗时**：折起来之后它是那一轮过程信息的唯一读数，只写「思考过程」等于把「跑了多久、走了几步」也折掉了。手动态按**轮次**记（`currentTurnKey` = 最后一条用户提问的 id），同一轮内反复重绘不许清（清了就是「点一开就自己折回去」）。

**④ 工具调用默认折成一行摘要**（`App/Views/AgentProcessBlocks.swift` 的 `AgentToolBlockView`）

改前默认形态是 `!(compact || toolProgress == .summary)`，契约默认 `toolProgress = .all` ⇒ **默认展开**：一轮 56 次调用铺 56 行。契约：**默认恒为一行摘要** `▸ 56 次工具调用 · 8.2s · 展开`（条数 + Σ耗时 + 动作）；展开态**有上限**（抬头 20 + 发丝 2 + 行体 **216** = **238pt ≤ 240**）且行体在 `ScrollView` 里 —— 56 次与 300 次对外层一样高。`.toolProgress = .off` 那一档照旧只留「调用 N 次」，连展开口都不给。

**判据**（`TestsUISnapshot/AgentChatNarrationProbeTests.swift`，`DOYAH_UI_SNAPSHOT=1`；Core 侧 `Tests/AgentAnswerSplitTests.swift` 17 例 + `Tests/AgentDisplayPreferencesTests.swift` 14 例）

- `T-3.33-05` **旧库端到端**：临时目录写一份 v1 + `longPreview = 2+2` 的盘 → `AppState.loadAgentDisplayPreferencesIfNeeded()`（真启动路径）→ 结论可见高 **455pt = 全文 455pt**（新装默认同值），盘上写回 `version 2`；反例（把 `2+2` 写成 v2、迁移条件不成立）⇒ 结论只 **96pt**，判据报红；纯函数层另判：迁移后 `previewSplit` 为 `nil`，反例非 `nil`；
- `T-3.33-06` **思考区三态**（读数为 §3.33.2 定高口径；改前是「按内容长」的 37 / 97pt）：运行中 **200pt**（= 定高，≤ 200）/ 终态 **20pt**（= 一行）/ 终态手动展开 **200pt** → 追加事件后 **200pt**（仍展开、不跟内容长）/ 运行中手动收起 **20pt**；摘要行「思考过程 · 12 步 · 18.4s · 展开」；反例（12 行思考不折）**240pt** ⇒ 报红；
- `T-3.33-07` **独白不进正文**：`split.narration` = 「我先读一下…」、`split.conclusion` 首行「第 1 行：结论正文。」且不含「我先读一下」；整页运行中 **720pt** vs 终态 **521pt**（思考区展开多占 **199pt** = 200 定高 − 一行 20 + 块间距，§3.33.2），结论两种状态都完整可见；
- `T-3.33-08` **工具块默认一行**：折叠态 56 次 **20pt**、300 次 **20pt**（逐点同高）；展开态 **233pt**（≤ 240pt）、56 次与 300 次同高、内部滚动容器 **1 个**；摘要「56 次工具调用 · 5.6s · 展开」；整页只多占 **24pt**（一行 20 + 间距 4）；反例（56 行不折）**1230pt**、展开无上限 **1252pt** ⇒ 报红；
- `T-3.33-09` **整页对照**：新形态（结论整段 + 思考一行 + 工具一行）**545pt** / 旧形态重建（结论 2+2 + 独白当正文 + 56 行工具）**1965pt**，省 **1420pt**；对话区视口 437.5pt 不变；
- `T-3.33-10` 手动态作用域（Core）：同一轮内 5 次重绘仍保持、新轮回到默认展开。

**边界（如实登记）**
- `display.thinking` 开关仍管 `reasoning_content` 那一路（关 = 不画那段，数据照收）；**过程独白不受它管** —— 它是模型写进正文的字，既不能回正文，也不该被开关静默吞掉；
- 整条都是独白（`isNarrationOnly`，例如只说了一句「我先看一下」就断了）⇒ 按规则 3 的兜底走正文，此时思考区**不再重复放一遍**（同一段字在两处出现，读起来像重复）；
- 流式中同样只把结论那一段画进正文：否则终态一到独白会在正文里「消失」，读起来像内容被吞了。


#### 3.33.2 流式上屏的合批节奏与视口高度

主人装上 beta1.0.4 后的原话：

> 「思考过程中，流式输出让滚动条很闪，不像 hermes 的输出这么丝滑」

「丝滑」不是文案、也不是滚动条画法，是**上屏节奏**。三处根因各自独立，逐条量过：

| # | 根因（改前位置） | 机制 |
|---|---|---|
| ① | `App/AgentChatModel.swift:1206-1208`（`observe` 每条事件都 `state.apply`）+ `Core/AgentChat.swift:485-502` | 模型是 token 级回调 ⇒ **一条增量改一次 `@Published state`** ⇒ SwiftUI 重算一帧 ⇒ 思考区 `ScrollView` 的内容尺寸变一次、指示器按新尺寸重算一次。端点每秒 50~200 个增量就是每秒 50~200 次重排 |
| ② | `App/Views/AgentProcessBlocks.swift:214-221` | 内容格是 `.frame(maxHeight: 178)` —— **上限不是定高**。`ScrollView` 在内容比 178pt 短时缩到内容高 ⇒ 整块高度跟着字数长，下面的正文被一遍遍往下推 |
| ③ | `App/Views/AgentChatView.swift:283-289` | `follow(_:)` 在 `scrollTick` 每次变化时**无条件** `withAnimation(.easeOut(0.15)) { scrollTo(bottom) }`。`scrollTick` 每个 token 都变 ⇒ 150ms 的动画**永远重启、永远跑不完**，滚动条一路处于「正在滑」；用户往上翻也照样被拽回底部 |

**契约五条**

1. **合并窗口 50ms**（`Core/AgentThinkingStream.swift` 的 `AgentStreamCoalescer`）：`.delta` / `.reasoningDelta` 先进 buffer，**一个窗口一次上屏**。
   - **头一条不等**（leading edge）：距上次上屏已过窗口 ⇒ 立刻上屏（「第一句字马上出现」是体感的一半）；
   - **结构边界强刷**：工具开跑 / 跳开始 / 终态 / 失败这些**非增量**事件到场前，先把积压的字上屏（否则过程行会跑到正文前面）；
   - **收尾强刷**：`finish` 前清空 buffer（结论末几个字不许断在半句）；**新轮丢弃**上一轮残留。
2. **一批一次状态变更**（`AgentChatState.applyBatch`）：一个窗口的增量在**同一次 `@Published`** 里落地 ⇒ 一次窗口只重算一帧，不做「批里再逐条 apply」。
3. **固定视口 200pt**（`AgentThinkingViewport` + `AgentThinkingZone`）：运行中与手动展开**整块恒 200pt**（抬头 20 + 发丝 2 + 视口 178），内容只在视口**内部**滚。定高而不是 `maxHeight` —— 上限会让整块跟着内容长。
4. **条件跟随**（`AgentScrollFollow` + `App/Views/ScrollOffsetSpy.swift`）：只在**用户贴着底**时跟新内容；往上滚就停手，滚回底部才恢复。跟随**直接跳、不加动画**。
   - 贴底判定**只吃真实滚动读数**（`NSScrollView` 的 clip `boundsDidChange`）；**内容长高不刷新它** —— 否则「贴着底 + 新内容刚到、还没跟」这一瞬会被误判成「用户往上翻了」，跟随当场断掉（表现是「有时跟、有时停在半路」）。
5. **滚动条策略**：**运行中隐藏指示器**（`.scrollIndicators(.hidden)`），终态手动展开时交回系统默认（`.visible`）。
   - 理由：运行中内容每 50ms 长一截，指示器的滑块尺寸每次都得按新内容高重算 —— 那正是主人看到的「闪」；视口只有 178pt，一屏之内不需要位置指示。终态展开是**静态内容**（不重算），交回系统默认既守住可发现性、也不会闪。
   - 取舍（如实登记）：运行中用户上翻时没有指示器，但「字不再往下滚」本身就是状态信号；滚回底部跟随自动恢复。

**两档切换不插值**（`AgentThinkingViewport.height(expanded:)`）：折叠 20pt / 展开 200pt，**只有这两个数**。折叠与展开**直接切档**，不许 `withAnimation` 改高度 —— 动画期间尺寸逐帧插值，看着又是一档闪。

> **2026-11-07 起被 §3.37 取代（原文保留以便追溯）**：展开态**不再是定高 200pt**，而是
> `min(抬头 20 + 发丝 2 + 内容实测高, 200)`，且内容实测高按**整行向上取**（量化）—— 定高解决了「抖」，
> 却让一两行内容下面空出一大块（beta1.0.8 主人原话）。折叠仍是 20pt；「不插值、不加动画」这一条不变。

| 判据 | 读数（真跑） | 反例（同一套判据） |
|---|---|---|
| `T-3.33-11` **刷新频率**（`Tests/AgentThinkingStreamTests.swift`） | 200 条增量、每条间隔 2ms（= 500 增量/秒）⇒ **上屏 9 次（4.5%）**，每批 25~26 条 + 尾批 20；走生产路径（`AgentChatModel.observe`）量 `@Published`：**发 8 次**（结构边界强刷后 10 次），拼出的 890 字与逐条追加**逐字相同** | 关节流（`interval = 0`）⇒ **上屏 200 次（100%）** ⇒ 判红 |
| `T-3.33-12` **视口稳定**（`TestsUISnapshot/AgentThinkingFlowProbeTests.swift`） | 200 段增量、逐次采样 200 次 ⇒ **min 200.0pt / max 200.0pt / 方差 0.0000**；内部文档高 **5986pt**、视口 **178pt**、文档宽 **900pt**（真在内部滚） | 改前形态（`ScrollView.frame(maxHeight: 178)`）⇒ 高度 **67 → 97 → 127 → 157 → 187 → 200pt** 递增 ⇒ 判红；同一口径下新形态逐次 **200pt** |
| `T-3.33-13` **跟随策略** | 贴底态新增一段 ⇒ 偏移 **708 → 738pt**（永远停在最大偏移，「距底 0pt」）；**模拟用户上滚**（`NSClipView.scroll(to:)` + `reflectScrolledClipView`）后新增三段 ⇒ 偏移 **0pt → 0pt**（一动不动） | 无条件跟随（改前的 `follow`）⇒ 上滚后仍被拽回底部（738pt）⇒ 判红 |
| `T-3.33-14` **无动画抖动** | 运行中 ↔ 终态 ↔ 手动展开 ↔ 手动收起 ↔ 回运行中，每态连采 6 拍共 **30 次** ⇒ 取到的档位只有 **{20, 200}pt** | 一条插值样本序列（200 → 168 → 92 → 40 → 20）喂同一套判据 ⇒ **3 个中间值** ⇒ 判红 |

> **2026-11-07 起 `T-3.33-12` 的「定高 200 / 方差 0」读数被 §3.37 取代**（原文保留）：新读数 =
> 200 段增量首 **42pt** → 上限 **200pt**，全部落在「抬头 22 + 整行 20」格点上，变化次数远小于段数
> （新判据 `T-3.37-04`，函数 `steppedViolations`）；旧形态 `maxHeight` 仍判红 —— 实测
> 67 / 97 / 127 / 157 / 187 / 200pt，其中 **5 档脱离整行格点**。`T-3.33-14` 的「无动画」不受影响。

**探针边界（如实登记）**
- `GeometryReader` + 偏好回传在离屏宿主里**收不到值**（实测恒 0）⇒ 整块高度改读**真宿主视图的 frame 高**（`NSHostingView` 缩到内容尺寸，实测 200.0pt）；
- `NSHostingView` 会缩到内容的 fitting **宽**：空内容时整块只剩 **16pt 宽**、文字被挤成一字一行（文档高实测 13 万 pt）⇒ 探针必须把宽度钉死成 900；
- 离屏宿主**没有 display link**，`.animation` 会直接跳到终态（实测 6 拍全是终值）⇒ `T-3.33-14` 的反例在**判据函数**上验（插值样本必须判红），不在活宿主里验；
- 活宿主里 `ScrollView` 会被分到定额高度 ⇒ 「旧形态跟着内容长」只能按 `fittingSize` 量（上一轮 `T-3.33-06` 的 37 / 97pt 就是同一口径）。

**禁止行为**
- 禁止把增量直接写进 `@Published state`（一 token 一帧 = 本节要修的那个缺陷）；
- 禁止给思考区内容格用 `maxHeight`（整块高度必须由常量定死，与字数无关）；
- 禁止自动跟随时用 `withAnimation`（动画永远被下一个增量重启）；
- 禁止在用户已经上翻时继续跟随（抢控制权）；
- 禁止用几何读数当「贴底」判据（内容长高会把它变成「用户上翻」）。

#### 3.33.3 外层对话区的跟随落点与贴底判定

主人装上 beta1.0.6 后的原话：

> 「每 Step 里的思考过程是可以滚动，但整个界面却不滚动了，要手工去拖动」

即：**内层**思考视口（§3.33.2 定高 178pt）能滚，**外层**对话区在流式输出 / 新步骤追加时不再自动贴底。
三处根因各自独立，全部按真读数定位（不是猜）：

| # | 根因（改前位置） | 机制（实测读数） |
|---|---|---|
| ① | `App/Views/AgentChatView.swift:369-375`（`follow(_:)`） | 落点走 `ScrollViewProxy.scrollTo(bottomAnchor, anchor: .bottom)`，而底部哨兵是内容里**最后一行**，内容末尾还有 `.padding(.vertical, Spacing.m)` = **12pt**。对齐哨兵底边 ⇒ 跟完距底**恒 12.0pt**（探针逐次读数：`max 49.0 / min 12.0`，300 次里**贴底 0 次**） |
| ② | `App/Views/AgentChatView.swift:200-201`（贴底判定） | 判定只看「距底多少」，于是**内容长高**与**人往上滚**不可分：①的 12pt 每跟一次就把 `transcriptPinned` 打成假，而 `follow` 是**先 `guard pinned`** ⇒ 之后一次都不跟。真机表现就是「要么不动、要么得手工拖」 |
| ③ | `App/Views/AgentChatView.swift:204-218` + `App/Views/StickyQuestionAnchor.swift:112-126`（触发挂点） | 跟随只挂 `scrollTick`（消息数 + 正文长度）；读数只订阅 `clip.boundsDidChange`。而**内容长高**与**视口变矮**都不改偏移 ⇒ 不发读数：吸顶条一出现（视口 −20pt）就漏出 20pt，思考区折/展同理 |

**契约六条**（§3.33.2 契约 4 的**收口**，两条不冲突：仍是「贴底才跟、上翻即停」）

1. **落点 = 内容底边**（`StickyQuestionSpy.SpyView.scrollToBottom()` → `NSClipView.scroll(to: maxOffset)`）：跟随与判定用**同一个分母**。禁止用底部哨兵当落点（哨兵的对齐点比内容底边高 12pt，等于每跟一次自杀一次）。
2. **判定分得清「人上翻」与「内容长高」**（`AgentScrollFollow.update(contentHeight:viewportHeight:offsetFromTop:)`）：
   - 距底 ≤ **4pt** ⇒ 贴底；
   - 距底 > 4pt **且偏移比上次小（> 0.5pt）** ⇒ 人往上滚 ⇒ 停跟；
   - 其余（内容长高 / 视口变矮 / 我们自己的跟随还没落定）⇒ **保持原判定**。
   状态机住在**读数器**里（`SpyView.follow`），宿主只在**判定翻转**时收一次通知 —— 放进 `@State` 结构体就得每帧写状态，那正是 §3.33.2 要消掉的「闪」。
3. **触发 = 几何落后，不是内容事件**：读数器订阅三路 —— clip `boundsDidChange`（人滚 / 程序滚）、**document `frameDidChange`**（内容长高：流式逐段 / 新步骤 / 思考区折展）、**clip `frameDidChange`**（视口变矮：吸顶条进出 / 窗口改高）。`report()` 里若「贴底且距底 > 4pt」就**当场补跟**（不等「通知 → 下一拍回写 → 再重排」那条链，实测那里会漏一帧 20pt）。
4. **内层滚动不污染外层**（契约②）：读数只从**订阅时那一个 clip** 取（`attachedClip` 身份守卫）；子滚动区（内层思考视口）的 `boundsDidChange` 通知 object 不是它，进不来。内层自己的跟随仍是 `ScrollOffsetSpy` + `AgentScrollFollow(distanceToBottom:)`（那里没有 padding，落点即底边 —— 两处口径在 Core 的注释里写明为什么可以不同）。
5. **不许改的两处读数**：吸顶条高度（`AgentStickyQuestion.barHeight` = 20pt，§3.34）与思考区定高（`AgentThinkingViewport.totalHeight` = 200pt / 视口 178pt，§3.33.2）一个字都没动；本轮只改**跟随的落点与判定**。
6. **换轮强制重定位**（`StickyQuestionSpy.SpyView.repinToBottom()` / `turnTarget`）：新一轮开始时
   （本轮提问行换了**轮钥**），上一轮的「人上翻」意图当场作废 —— 状态机重置、视口落到
   **本轮开始处**（本轮提问行顶边，夹到 `maxOffset`；新一轮内容不足一屏时夹到的就是底部），
   之后整轮保持「贴着最新内容」。裁决口径三条：
   - **触发是几何事实，不是视图事件**：换轮由读数器判（标记带**轮钥** + `updateNSView` 喂进来的
     当前轮钥），**不许**依赖宿主 `.onChange(of:)` 的时机（实测那些钩子在部分宿主里一次都不跑）；
   - **落点整轮有效**：换轮那一拍的几何还是旧的，滚到位之后这次布局可能又把它摆回去 ⇒
     每次读数发现「不在落点上」就再落一次（上限 40 次）；这正是「当前轮一直贴着最新内容」；
   - **用户一上手就交还控制权**：滚轮 / 拖滚动条（真实 `NSEvent`）⇒ 撤掉本轮落点，此后不再抢回。
     判定**不许**用「偏移变小了」——它分不清「人上翻」与「布局把我们摆回去」。
7. **贴底判定只许有一份**：宿主的 `follow()` 只发「想跟」的意图（`scrollToBottomIfPinned()`），
   跟不跟**由读数器里的状态机当场判**。禁止在宿主 `@State` 里另存一份「贴不贴底」——
   两份副本必然漂移：副本卡「假」⇒ 整轮不跟（换轮也不跳）；副本卡「真」⇒ 人上翻被拽回。

**产品形态（人看得见的三件事）**：一轮结束时，三行汇总下面**紧接**结论首行，中间就是一块块间距（4pt）——
不再有 2~3 行看不见却占位的空行（改前实测 **61pt**）；发下一条消息时视口**自动落到本轮开始处**
（本轮那条提问），不用人往下拖，而人一旦自己滚过就立刻交还控制权、本轮内不再抢回；
同一时刻只有**一份**「贴不贴底」，所以「贴底却突然不跟」与「上翻被拽回」两种反向病不会同时出现。

| 判据 | 读数（真跑） | 反例（同一套判据） |
|---|---|---|
| `T-3.33-15` **判定状态机**（`Tests/AgentThinkingStreamTests.swift`） | 内容长高 200pt（偏移不动）⇒ **仍跟**；视口变矮 20pt ⇒ **仍跟**；偏移小 100pt ⇒ **停跟**；停跟后内容再长 ⇒ **仍停跟**（不回弹）；往下滚但距底 520pt ⇒ **仍停跟**；回底 3pt ⇒ **恢复**；0.2pt 抖动 ⇒ **仍跟** | 把同一串读数喂给「只看距底」的旧口径 ⇒ 第 2 步 `shouldFollow = false` ⇒ 判红（正是 beta1.0.6 断跟的机制） |
| `T-3.33-16` **① 流式 300 次追加**（`TestsUISnapshot/AgentTranscriptFollowProbeTests.swift`） | 走生产路径（`AgentChatModel.observe(.delta)`）追加 300 次、逐次采样 ⇒ **贴底 300/300**，距底 **max = min = 0.0pt**；文档高 **3662pt** / 视口 **390.5pt**；偏移 **1181.5 → 3271.5pt** | 关掉跟随（偏移冻在 1181.5pt）⇒ 距底 **2018.5 → 7400.5pt** 单调递增 ⇒ 判红；**改前读数**：贴底 **0/300**、距底 min **12.0** / max **49.0pt** |
| `T-3.33-17` **② 内层滚动不污染外层** | 内层思考视口滚 **200pt**（内层文档 **601pt** / 视口 178pt）⇒ 外层偏移 **1181.5 → 1181.5pt**（一格不动）、距底 **0.0pt**；随后追加一次 ⇒ 仍贴底（`pinned` 仍为真） | 把内层滚到半路时的距底读数（**120pt**）喂给外层判定 ⇒ `shouldFollow = false` ⇒ 判红（内层污染外层长这样） |
| `T-3.33-18` **③ 上翻即停** | 上翻 **100pt** ⇒ 偏移 **1181.5 → 1081.5pt**；再追加 **20 次** ⇒ 偏移**最大漂移 0.0pt**（不回弹） | 上翻态下跟随仍开着 ⇒ 偏移漂移 **200pt** ⇒ 判红 |
| `T-3.33-28` **⑤ 换轮强制重定位**（`TestsUISnapshot/AgentSummaryGapAndTurnFollowProbeTests.swift`） | 3 轮对话、第 1 轮上翻后再发提问（走生产路径 `AgentChatModel.send()` → `beginRun`）：轮钥 `48211B67 → 8FE3397C`，**触发重定位 1 次**（第 5 轮累计 5 次），落点目标读到**本轮提问行的内容坐标 3058.5pt**（本轮首行未物化时退回底部）；上翻态在这一轮被重置 | 改前同一夹具：轮钥变了但**重定位 0 次**，视口偏移停在 **0.0pt**（第一轮区域）、新一轮首行在视口外 **3058.5pt** ⇒ 判红 |
| `T-3.33-29` **⑥ 同轮上翻不被抢回** | 同一轮内上翻到偏移 **0.0pt** 后继续追加 10 次增量（内容长到 `maxOffset` 1807.5pt）：偏移**仍 0.0pt**（漂移 0.0pt） | 改前读数：同一轮内长高把视口从 **0.0pt** 拽到 **2556.5pt** ⇒ 判红（两副本漂移的「卡真」那一侧） |
| `T-3.33-19` **④ 回底恢复** | 滚回距底 **3pt**（容差内）⇒ 下一拍贴到 **1181.5pt / 距底 0.0pt** | 距底停在 **6pt**（容差外）⇒ 追加后偏移 **1175.5 → 1175.5pt**（不跟）⇒ 容差边界成立 |

**探针边界（如实登记）**
- **换轮重排那一拍，离屏宿主会丢掉外层滚动视口约束**：`send()` 之后外层 `NSScrollView` 的 clip 高读成
  **3526pt**（≈ 整份内容），偏移恒为 0 ⇒ 换轮的**落点几何**在离屏宿主里量不到。判据 `T-3.33-28` 因此读
  「换轮有没有触发重定位 + 落点目标是多少」这两个**不依赖视口**的量，落点几何由真机复测；不许把
  「0 == 0」当绿（那一版是假绿，已改断言并在本节登记）。
- **活宿主的异步回写必须用 `pumpAsync`**
- **活宿主的异步回写必须用 `pumpAsync`**：`RunLoop.current.run` 泵着的期间主队列块**不落地**（实测 `[trace] hop fires` 一次都没打出来）⇒ 读数永远回不到宿主，`pinned` 冻在初值「真」；换 `pumpAsync`（`Task.sleep` 让出主 actor）之后回写才落。上一版 `T-3.33-13` 之所以「绿」，是因为它只量滚动落点、不量判定翻转。
- **思考段默认是关的**（`AgentDisplayPreferences.thinking`）⇒ 判据② 要经**生产开关**（`AppState.setAgentDisplay(key: .thinking, value: "on")` + 临时目录）把它打开，不许给视图塞假思考区。
- 探针读的是**真 `NSScrollView` 的 clip 偏移**（外层取面积最大的那个；内层取高 178pt 的那个），不推算。

**禁止行为**
- 禁止拿「距底多少」一个量同时判「人上翻」与「内容长高」（必须带上**偏移的变化方向**）；
- 禁止用底部哨兵 / `ScrollViewProxy.scrollTo(anchor: .bottom)` 当跟随落点（与内容底边差 12pt）；
- 禁止跟随状态住进宿主的 `@State` 结构体（每帧写状态 = 把 §3.33.2 的「不闪」拆掉）；
- 禁止只挂内容事件（`scrollTick`）当触发：内容长高与视口变矮不改偏移，必须从**几何**触发；
- 禁止让内层滚动区的读数改写外层跟随状态。

#### 3.33.4 一轮一个思考区：段模型与三行汇总

主人装上 beta1.0.7 后的原话：

> 「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」

即：一轮里**所有步骤**的思考要**合并成一个思考区**（一个可滚动的整体，按时间顺序累积），
而不是每个 step 各自一个可折叠块。三态（§3.33.1 ③）、定高 200pt（§3.33.2 ②）、
工具块一行摘要（§3.33.1 ④）**行为与高度都不变** —— 本轮只改「区按什么粒度实例化」。

**根因（`文件:行号`，改前）**

| # | 落点（改前） | 事实 |
|---|---|---|
| ① | `App/Views/AgentChatView.swift:158`（`ForEach(model.messages)`）+ `:171-173`（`thinkingZone(message, …)` 在**逐条消息的循环体里**） | 思考区是**按消息（= 按 step）实例化**的：五步 ⇒ 五块，各带自己的抬头与折叠态 |
| ② | `App/Views/AgentChatView.swift:1607-1623`（`thinkingZone(_:isFinalAssistant:isLastTurn:)`）+ `:1613`（`AgentThinkingZone(text: parts.joined(…))`） | 「这一格显示什么」= **这一条消息**的 `thinkingParts`（`:1631`），单条作用域；跨步骤没有累积的去处 |
| ③ | 无（新增） | 「一轮的思考」此前**没有任何一处**是数据：段序、步号、本轮步数都得由视图现拼 ⇒ 判据也没法数「页面上几个区」 |

**契约五条**

1. **一轮 = 一个思考区**：本轮所有步骤的思考文本按**发生顺序**累积进**同一个** `AgentThinkingZone`；不许每个 step 一个新块。归属只在 `Core/AgentTurnThinking.swift` 判一处（`zones(in:includeReasoning:)` / `zonesByAnchorIndex(in:includeReasoning:)`），轮切分仍走 `AgentChatTurnShape`（轮的定义只许有一处）。
2. **内部仍可分段**：步骤边界用**轻分隔**（一行发丝 + 极小字「第 N 步」，`monoSmall` + 三级文字色）或段间距，**不用**多级折叠头（段上不挂点击、不占抬头高度）；整体仍**定高 200pt + 内部滚动**（`AgentThinkingViewport` 一个字没动）。
3. **三态不变**：运行中展开（可流式）/ 终态自动折成一行（`思考过程 · N 步 · 18.4s · 展开`，`N` = 本轮**真有思考的段数**）/ 手动展开后本轮内 sticky（`AgentThinkingManualState`，钥匙 = 轮首消息 id）。
4. **折 / 展是一次作用于整轮**：区只有**一处**抬头，`onToggle` 改的是这一轮的手动态；「点一下只折了某一步」在结构上不可能发生（没有按步的折叠态）。
5. **工具块保持不变**：工具调用按调用 / 步骤各自成块（`AgentToolBlockView`，默认折一行 20pt），**不并进**思考区；思考区文本里一条工具行都不许出现（`Core` 侧只取 `AgentAnswerClassifier` 认出的独白 + 思考段）。

**契约六条（收口版：一轮结束时只允许「三行汇总」）**

主人 2026-11-07 补的最终形态（在上面「一轮一个区」之上再加三行）：

```
▸ Thinking  ~308 tokens
▾ Tool calls (1)  ~16 tokens
Σ ~324 total
```

6. **一轮只能是这三行**：顺序固定 `Thinking` → `Tool calls (N)` → `Σ total`，**默认全折**（各 20pt）；三行的折叠态**互不影响**（各自一个 `@State`，键 = 轮首消息 id）。**Thinking 行就是合并后的那一个思考区**（运行中按 §3.33.1 ③ 展开 200pt、可流式；终态折一行）——所以「两块 Thinking」在结构上不可能出现。
7. **Token 数字的口径（写死，改口径先改 `Core/AgentTurnUsage`）**：
   - `Thinking` = **合并后那个区**的文本 token 数（`AgentTurnThinking` 给视图的段 `joined("\n\n")`，与区**同一份字**）；
   - `Tool calls (N)`：`N` = 本轮**调用次数**（一行一次调用），token = 本轮工具过程行文本的合计；
   - `Σ` **定义为** `thinking + tools + output`（`output` = 本轮结论正文）。端点回报的 usage 是**整个请求**口径（系统提示 + 历史 + 工具 schema），与本轮产出不同源 ⇒ 只进 tooltip 作旁证，**不进** 任何一个数。
   - 有 usage 用 usage、没有就估算：端点**没有分项 usage**，所以三项一律走仓库既有估算器 `AgentTokenEstimator.tokens(_:)`（汉字 1 字 = 1 token、其余 4 字符 = 1 token；与上下文账本同一套），数字前带 `~`；`isEstimated = false` 才允许去掉波浪号。
   - **不许写死 / 占位**：三个数都从消息文本现算；运行中随增量涨（`AgentChatView` 每帧从 `AgentTurnUsageReader` 读，估算成本是线性扫文本）。
8. **第二行展开后，内部仍是逐次调用各一行 20pt**（§3.33 口径不变）：`AgentToolCallRow` 一次调用一行、带 `├─ ⏺` 与耗时；工具数不因合并而变（判据⑤）。

**怎么实现（四件，各管一件事）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 轮切分 | `Core/AgentTurnThinking.swift`（`AgentTurnSpan` / `AgentTurnSpans.spans(in:)`） | 「这一轮从哪条到哪条、过程信息挂哪一行」只有一处实现；思考聚合与用量都读它 |
| 聚合 | `Core/AgentTurnThinking.swift`（`AgentThinkingSegment` / `AgentTurnThinkingZone` / `AgentTurnThinking`） | 一轮一段数组：`segmentText(of:isFinalAssistant:includeReasoning:)` 的口径**与改前 `thinkingParts` 逐条一致**（思考段受 `display.thinking` 管、独白不受），只是搬进 Core 让判据也读它；`zonesByAnchorIndex` 保证**一轮最多命中一条消息**（= 页面上最多一个区） |
| 读数 | `Core/AgentTurnUsage.swift`（`AgentTurnUsage` / `AgentTurnUsageReader`） | 三行里的三个数：`thinking` 直接用聚合区的 `text`（同一份字，±0）、`tools` 扫工具过程行（`▸ ` 前缀计次）、`output` 取结论段；`totalTokens = thinking + tools + output`（等式写死在 `AgentTurnUsage`） |
| 形态 | `App/Views/AgentProcessBlocks.swift`（`AgentThinkingZone(segments:…)`、`stepDivider(_:)`、`AgentToolCallsSummaryRow`、`AgentToolCallRow`、`AgentTurnTotalRow`、四个探针锚）+ `App/Views/AgentChatChrome.swift`（`AgentTurnUsageLines`，行文本形制） | 三行按固定顺序渲染、各 20pt、各自折展；段按 `ForEach(segments)` 渲染，第 2 段起插一条轻分隔；行文本一律走 `AgentTurnUsageLines`（判据与界面同一份） |

**判据**（`TestsUISnapshot/AgentTurnThinkingZoneProbeTests.swift`，900×620 真 `AgentChatView`，`DOYAH_UI_SNAPSHOT=1`；聚合规约在 `Tests/AgentTurnThinkingTests.swift` 5 例）

| 判据 | 读数（真跑） | 反例（同一套判定函数） |
|---|---|---|
| `T-3.33-20` **① 五步 ⇒ 1 个区** | 五步一轮（每步一段叙述 + 一次工具调用）⇒ 页面上 `AgentThinkingZone` 实例 **1 个** | 改前形态（一条消息一块，`LegacyPerStepThinking`）⇒ **5 个** ⇒ 判红（断言 `legacyCount == 5`） |
| `T-3.33-21` **② 定高 200pt + 内部滚到末尾** | 整块 **200.0pt** / 内容视口 **178.0pt** / 文档 **271.0pt** / 滚到底距底 **0.0pt** | 视口跟着内容长 ⇒ `viewportViolations` 报「≠ 178pt」；文档 ≤ 视口 ⇒ 报「撑不出内部滚动」 |
| `T-3.33-22` **③ 顺序保真** | 段锚按文档坐标上→下 = **`[1, 2, 3, 4, 5]`**；段文本开头 `["第 1 步"…"第 5 步"]` | 段序 **`[5, 4, 3, 2, 1]`** ⇒ `orderViolations` 判红 |
| `T-3.33-23` **④ 折一次 = 折整轮** | 终态 **20.0pt** → 点一次 **200.0pt** → 再点 **20.0pt**，全过程**区数恒为 1** | 按 step 分块：**5 个区、合计 100pt**（点哪块只折哪块）⇒ 判红 |
| `T-3.33-24` **⑤ 工具块不变** | 工具块 **5 个**、行高 **[20, 20, 20, 20, 20]**（`Tool calls` 行展开时逐条）；思考区文本里 `read_file` **0 处** | 工具并进思考区 ⇒ 块数 < 5 且区文本含 `read_file` ⇒ 判红 |
| `T-3.33-25` **⑥ 三行各恰好一行** | 一轮 5 步 + 1 次工具、终态：`Thinking` 行 **1** / `Tool calls` 行 **1** / `Σ` 行 **1**，行高 **[20, 20, 20]** | 改前形态（一条消息一块）⇒ `Thinking` 行 **5** ⇒ 判红 |
| `T-3.33-26` **⑦ Thinking 行 == 合并后的区** | 抬头画的 **324 tokens** == 合并后区的 `AgentTokenEstimator.tokens(zone.text)` **324 tokens**（输出段是 **18**，两者不等 ⇒ 认得出源） | 抬头写输出段的数（**18**）⇒ 判红 |
| `T-3.33-27` **⑧ Σ == thinking + tools + output** | `Σ` **352** = thinking **324** + tools **10** + output **18**；Σ > thinking（说明后两段真进去了）、tools > 0 | `Σ` **只算输出**（**18**）⇒ 判红 |

**边界（如实登记）**
- 折叠动作是 `onTapGesture`（离屏宿主点不动）⇒ ④ 把 `onToggle` 的结论（`manual`）直接喂回去：生产里点抬头改的是同一个值，探针与生产读**同一份渲染代码**。
- 「页面上几个区」靠**锚视图**计数（`AgentThinkingZoneMarker` / `AgentThinkingSegmentMarker` / `AgentToolBlockMarker`，零行为、零尺寸语义）：`Text` 不落 `NSTextField`、折叠态也没有滚动容器，数折头只能靠显式记号。
- 内层视口要**最内层**那格 `NSScrollView`：外层对话区也是滚动容器，它的 `documentView` 子树里同样躺着段锚（实测先命中它 ⇒ 读到视口 390.5pt）。
- 早轮次里 `elapsedSeconds` 仍取 `model.lastElapsedSeconds`（只对最后一轮准）—— 本轮不碰，登记在案。
- **探针要先把外层滚回顶部**：运行中那一页会自动贴底，而 `LazyVStack` 会把滚出视口的行回收（实测顶部的过程块整块消失 ⇒ 记号 0 个）。读数前 `scrollToTop` 只动滚动位置，不改任何一行。
- 估算器的成本 = 线性扫消息文本（每帧一次）；真机一轮几万字也在毫秒级，未做节流 —— 如果将来出现长会话 + 大历史，先量再优化，不提前加缓存。

**禁止行为**
- 禁止在 `ForEach` 的循环体里逐条实例化思考区（那是「一块一块」的定义）；
- 禁止给段加折叠态 / 点击（段只是分隔，折展只有整区一个口）；
- 禁止为了合并把工具行写成思考段（动作与思考是两回事，⑤ 会判红）；
- 禁止一轮出现第二块 `Thinking`（三行是**上限也是下限**：有过程就只许这三行）；
- 禁止把端点回报的 usage 当成 `Σ`（分母不同，等式会崩；只进 tooltip）；
- 禁止把三个 token 数写死 / 占位（必须从消息文本现算，估算也要带 `~`）；
- 禁止改定高 200 / 折叠 20 这两档（§3.33.2 ④ 的两档制不变）；
- 禁止在视图里另写一份「这一轮该显示什么」（只许走 `AgentTurnThinking`）。

> **2026-11-07 补（§3.37）**：上面「禁止改定高 200」这一条的**展开态**部分已被 §3.37 取代 ——
> 展开态改为 `min(内容实测高, 200)` 且按整行量化，折叠态仍是 20pt 一行。其余禁止项一条不变。

### 3.34 当前轮用户问题吸顶一行

> **上游**：概设 §8.11 ⑧（本轮提问吸顶）· §8.5 交互规则；需求 `FR-AGT-UX-CONV-003` ⑨。

主人原话（装好的 beta1.0.4）：

> 「用户发出的问题被滚动的输出冲掉了，有时候要滚到前面去才能看到。
>  应该跟 hermes 一样：如果输出的文字太多，用户这句话就挂在最顶端。」

**现状与根因（`文件:行号`）**

| # | 落点 | 事实 |
|---|---|---|
| ① | `App/Views/AgentChatView.swift:121`（`transcript`）、`:138`（`AgentStickyQuestionColumn`）、`:143` 起的 `ScrollView` | 对话区是**单一 `ScrollView`**，只有底部锚 `agentChatBottom` 与贴底跟随 —— 没有任何「把当前轮那句提问留住」的机制。一轮输出几百行之后，那句提问就是被滚走的普通一行。 |
| ② | `App/Views/AgentChatView.swift:233`（`currentTurnKey`，改前实现是 `messages.last(where: { $0.role == .user })`） | 「当前轮」在视图里有**第二份定义**（与 `AgentChatTurnShape` 的轮切分并列）。要做吸顶就必须先把它收成一处，否则「钉哪一条」会有两个答案。 |
| ③ | 无（新增） | 判定要的两个量（视口顶在内容里的位置、那句提问顶边在内容里的位置）此前**没有任何一处**报出来。 |

**契约五条**

1. **只吸当前轮，且只吸一行**：滚到当前轮的用户消息**离开可视区顶部**时，它以**一行**形式钉在对话区顶端（高 = `AgentStickyQuestion.barHeight` = **20pt** ≤ 28pt；文本截断 `…` + 悬停给全文）；滚回顶部、原消息重新可见时**条必须消失**（不重叠、不双显）。
2. **不遮内容**：吸顶条是滚动区**上面的兄弟视图**（`App/Views/AgentStickyQuestionBar.swift:80` 的 `AgentStickyQuestionColumn`：`VStack { 条? ; 内容 }`）—— 视口从条的底边起，内容一行都不被盖；条本身**不参与滚动**。
3. **点击跳回**：点条 ⇒ 滚到**那条消息的顶边**（不是页面顶部）。
4. **本轮结束不立刻消失**：判定**只与几何有关**（跑没跑完、成没成功都不进门）；进入下一轮才换，滚出本轮范围 / 回到消息处才消。
5. **与既有三态共存**：思考区三态（运行中展开 / 终态折一行 / 手动 sticky，§3.33.1 ③）与工具块一行摘要（§3.33.1 ④）**行为与高度都不变** —— 条只吃视口，不碰任何一行。

**怎么实现（三个部件，各管一件事）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 判定 | `Core/AgentStickyQuestion.swift:55` `currentTurn(in:)`、`:67` `shouldStick(viewportTop:questionTop:)`、`:76` `lineText(_:)` | 「钉哪一条」（取 `AgentChatTurnShape.turnStartIndices(...).last`，`Core/AgentAnswerSplit.swift:283`）+ 「钉不钉」（`视口顶 > 提问顶 + 0.5pt`）+ 一行化 |
| 读数 | `App/Views/StickyQuestionAnchor.swift:68` `StickyQuestionSpy`（+ `:17` `StickyQuestionRowMarker` / `:20` `StickyQuestionRowAnchor`） | 一次 `clip.boundsDidChange` 出三个读数：视口顶位置 / 距底距离 / `isStuck`。挂在**滚动内容根**上（内容多长它都在），按标记实例身份缓存提问顶边：行被 `LazyVStack` 回收后**沿用最后一份** |
| 形态 | `App/Views/AgentStickyQuestionBar.swift:23`（一行条）、`:111`/`:146`（真 `NSButton` 点击面）、`:80`（列布局） | 一行、暖金 `>` 前缀、不透明底、底部发丝线、`↑` 提示；点击面是**真 `NSButton`**（`Button` 在离屏宿主里落不成 `NSButton`，判据点不动） |

**为什么判定用「内容坐标」而不是「屏幕坐标」**：条的出现/消失会改视口高度（少一行）。若判定拿「行相对视口的可见位置」，条一出现这个量就变 ⇒ 判定翻转 ⇒ 条消失 ⇒ 又变回来 —— 自激闪。两个量都放进内容坐标之后，条在不在都**不改它们**；条只吃视口（`T-3.34-04`：行内容高逐点不变、视口正好少一行），内容一侧的文档高读数只受 `LazyVStack` 估值影响、与条无关（见「边界」）。

**为什么不用 `ScrollViewProxy.scrollTo(id, anchor: .top)` 做跳回**：那一行的 id 同时是 `ForEach` 的条目身份，`scrollTo` 解析到的是**条目容器**（前面还带一条轮次分隔线 `12 + 0.5 + 12` 与 4pt 块间距）—— 实测落点比行顶低 **28.5pt**。契约③ 要的是「定位到**该消息**顶部」，所以落点由 `StickyQuestionScroller`（`App/Views/StickyQuestionAnchor.swift:36`）按内容坐标直接给 `NSClipView.scroll(to:)`，并补一次（`LazyVStack` 对未物化行只有估值）。

**判据**（`TestsUISnapshot/AgentChatStickyQuestionProbeTests.swift`，900×620 真 `AgentChatView`，`DOYAH_UI_SNAPSHOT=1`；纯判定在 `Tests/AgentStickyQuestionTests.swift` 8 例）

- `T-3.34-01` **出现且一行、不遮内容**：300 行输出、滚到底 ⇒ 偏移 **5850.5pt**、条高 **20.0pt**（= 一行）、条 frame `{0,0,900,20}`、视口 `{0,20,900,417.5}`（**内容上沿 = 条底边，差 0pt**）；反例（条不出现）判红、反例（条压在第一行字上，差 −20pt）判红；
- `T-3.34-02` **滚回顶部即消失**：偏移 **0pt** 时条高 **0.0pt**（提问相对视口 78.5pt，确实看得见）；反例（回顶后仍挂 20pt）判红；
- `T-3.34-03` **点条跳回那条消息的顶边**：偏移 **8733.0pt → 78.5pt**（= 提问顶边），提问顶端相对视口 **0.0pt**，条随之消失（20 → 0pt）；反例（只滚到页面顶部 0pt ≠ 78.5pt）判红；
- `T-3.34-04` **不重排行**：同一份生产布局挂着真行（思考区展开视口 **178pt** + 工具块行体 **216pt**）⇒ 条开/关两遍，行内容高 **178 / 216 逐点相同**，只有外层视口 **620 → 600pt**（正好少一行）；整页：视口 **437.5 → 417.5pt**（少 20pt）、条底边 = 视口上沿（差 0pt）；反例（行被挤短 174/212）判红；
- `T-3.34-05` **长问题仍一行**：262 字、带换行的提问 ⇒ 条高仍 **20.0pt**、一行化后无换行；反例（不折行，同一段字直接 `Text`）**75.0pt** 判红。

**边界（如实登记）**
- SwiftUI `Text` 在离屏宿主里不落 `NSTextField`（`ExecutionReceiptPaneProbeTests` 同一条）⇒ 条高读的是它的**点击面 `NSButton` 的 frame 高**（铺满条）；
- 判据里「点一下」走 `NSButton.performClick(nil)`：生产里用户点它、探针里点它，**同一条 action**（`onTapGesture` 在离屏宿主里点不动，`DialogActionRowProbeTests` 已登记）；
- `LazyVStack` 的未物化行按**估值**参与布局 ⇒ 滚动位置不同，`documentView` 高度读数本来就会变（实测 6125pt ↔ 10102pt）⇒ **不作为**「行没被重排」的判据（改用行内滚动容器高度 + 视口高度）；同一估值也是 `scrollTo` 落点偏 28.5pt 的来源；
- 从被回收那一行的闭包回写宿主 `@State` 会踩「Modifying state during view update」（本轮实测），写进去的值被丢弃 ⇒ 读数与缓存一律放在**长命的** `StickyQuestionSpy` 上，回写统一走下一拍。

**禁止行为**
- 禁止「一直显示最后一条用户消息」（那是把问题变成常驻标题，不是吸顶；契约①要的是**滚出去才钉、滚回就消**）；
- 禁止用 padding / `.overlay` 把条压在滚动内容上（必须让出布局位置，否则第一行字被盖）；
- 禁止让吸顶条的显隐改变任何一行的尺寸（行高只由 §3.33 的常量决定）；
- 禁止在视图里另写一份「当前轮」判定（只许走 `AgentChatTurnShape` 的轮切分）；
- 禁止在 `isRunning == false` 时把条收掉（契约④：本轮结束不立刻消失）。

### 3.35 输入框历史导航（↑↓ 回填）

> **上游**：概设 §8.11 ⑧（输入框历史）· §8.5 交互规则；需求 `FR-AGT-UX-CONV-003` ⑦。

主人原话（装好的 beta1.0.5）：

> 「当光标在输入框中，按上下方向键能自动补全历史输入」

**现状与根因（`文件:行号`，改前）**

| # | 落点 | 事实 |
|---|---|---|
| ① | `App/Views/AgentChatView.swift:1964`（`TextField(L(.agentChatPlaceholder), text: $model.input)`）、`:1971`（`.onSubmit`） | 输入框是**单行** SwiftUI `TextField`：⏎ 提交、**⇧⏎ 也是提交**（没有换行的概念）、↑↓ 被字段编辑器吃掉（`App/` 与 `Core/` 里 `keyDown`／`doCommandBy` **零处**），历史无从接。 |
| ② | `App/AgentChatModel.swift:400`（`send()`）、`:409`／`:426`（两处 `input = ""`）、`:1060`（`start` 里 `if intent == .newQuestion { input = "" }`） | 「发出去」这件事**没有留痕**：清空输入框的三处各写各的，历史上限 / 去重 / 落盘一概不存在。 |
| ③ | 无（新增） | 「这条 ↑↓ 该归历史还是归光标」此前**没有任何判定** —— 直接接管会踩契约①那条硬约束（多行文本里 ↑ 是往上移一行）。 |

**契约六条**

1. **不抢光标**：**只有**光标在**首行行首**（偏移 0）时 ↑ 切历史、**末行行末**（偏移 == 文本长度）时 ↓ 切历史；其余位置（多行文本中间、首行中间、第二行行首）↑↓ **一律走正常光标移动**，有选区 / 输入法组字期间同理。这条是硬约束 —— 抢掉光标移动比没有历史更烦。
2. **草稿不丢**：**开始浏览的那一拍**保存当前输入为草稿；浏览到最新一条再按 ↓ ⇒ **回到那份草稿**（含未提交文字、含换行与尾随空格）。
3. **只回填不发送**：↑↓ 只改文字（回填后光标落到末尾，接着就能改），**绝不触发提交**。
4. **历史口径**：**提交成功才入历史**（被门控挡下 / 造不出循环 ⇒ 不入）；**连续重复去重**（`A、A、B` ⇒ `A、B`）；隔开的重复照收（`A、B、A`）；**上限 200 条**（超出挤掉最旧的）；**空串（含全空白）不入库**；**落盘持久化**（`agent-input-history.json`，跨重启不丢，顺序「旧 → 新」）。
5. **到边界不静默**：到最旧再按 ↑ **停在最旧**（不循环到最新）；回到草稿态再按 ↓ **什么都不做**。两处都返回「不接管」，按键交还系统而不是被吞掉。
6. **与提交 / 补全共存**：⏎ 仍是发送、**⇧⏎ 换行**（`insertNewlineIgnoringFieldEditor` 那一档同）；斜杠命令候选条开着时 ↑↓ **归浮层**（不回填历史）。

**怎么实现（四件，各管一件事）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 历史值 + 落盘 | `Core/AgentComposerHistory.swift:14`（`AgentInputHistory`）、`:38`（`record`）、`:103`（`AgentInputHistoryStore`，`standard()` 落在应用数据目录） | 去重 / 上限 / 归一化 / 原子写盘；读坏文件抛错不静默（调用方当空历史，但能说出原因） |
| 浏览状态机 | `Core/AgentComposerHistory.swift:159`（`AgentInputHistoryNavigator`）、`:172`（`up`）、`:188`（`down`） | 草稿只存一次、最旧停住、回到草稿才退出浏览；`nil` 的语义固定为「这次按键不该被历史吃掉」 |
| 按键归属 | `Core/AgentComposerHistory.swift:219`（`AgentComposerArrowRouter.takesHistory`） | 纯函数：`overlayOpen` / 有选区 / 偏移不在两个边界 ⇒ `false`（默认交出） |
| 编辑面 | `App/Views/AgentComposerEditor.swift:27`（`AgentComposerTextView`）、`:96`（`keyDown` 判 ↑↓）、`:123`（`insertNewline` = 提交）、`:132`（换行档）、`:139`（`replaceEntireText` 保留可撤销）、`:173`（`AgentComposerEditor`，`NSScrollView` + 高度 1..8 行） | 只做三件事：按键归属、把回填写进文本、量高度；判定全在 Core |
| 接线 | `App/AgentChatModel.swift:327`（`recordInputHistory`）、`:334`（`recallHistory`）、`:465` / `:483` / `:1120`（三个「真的发出去了」的落点） | 命令 / 排队 / 直接开跑三条路都记；视图侧 `AgentChatView.swift:1974` 换成新编辑面 |

**为什么把 `TextField` 换成 `NSTextView`**：契约①要判「光标在**第二行行中**」，单行控件根本没有第二行可量；契约⑥要 ⇧⏎ 换行，而 `TextField` 的 `.onSubmit` 对 ⇧⏎ 一视同仁。换成多行编辑面之后，↑↓ 的归属判定才有可能落在**真实光标位置**上；代价是输入区从「基线对齐的单行」变成「顶部对齐 + 内容高度 1..8 行、超过 8 行框内滚」，提示符 `>` 自己补 `verticalInset` 对齐首行。

**判据**（`Tests/AgentComposerHistoryTests.swift` 16 例，`Executed 16 tests, with 0 failures`；真控件那几条用的是 `AgentComposerTextView` 本体，不是另造的宿主）

- `T-3.35-01` **① 顺序**：历史 `A、B`、空输入 ⇒ ↑ **B**、↑ **A**、↓ **B**、↓ **空**（草稿），真控件上 `keyDown` 跑同一串得到 `B / A / B / 空`；反例（↑ 从最旧开始）判红；
- `T-3.35-02` **② 草稿保真**：`草稿文字` ↑ 得历史、↓ 回 ⇒ **`草稿文字`**（带换行与尾随空格的那一例同样逐字回来）；反例读数：把「回草稿」改成回空串 ⇒ `Optional("")` ≠ `Optional("草稿文字")` ⇒ **判红**；
- `T-3.35-03` **③ 不抢光标**：`第一行\n第二行` 光标在**第二行行中（偏移 5）** ⇒ 路由 `false`、回填计数 **0**、**文字逐字不变**，随后系统默认 `moveUp` 把光标从 **5 → 1**（落在第一行）；反例读数：把路由改成「↑ 一律接管」⇒ 文字被换成历史 `不该被填进来`、6 条断言判红；
- `T-3.35-04` **④ 回填不发送**：↑ 之后提交回调 **0** 次、模型侧「造循环」**0** 次、消息条数 **0**；反例读数：回填时顺手调一次 `onSubmit` ⇒ 计数 **4 / 1** ⇒ 判红；
- `T-3.35-05` **⑤ 历史口径**：`A、A、B、A` ⇒ `["A","B","A"]`（反例读数：去掉去重 ⇒ `["A","A","B"]` ⇒ 判红）；205 条 ⇒ 保留 **200** 条、首条 `q6`、末条 `q205`；落盘 → 新 store / 新 model 载入仍是 `["第一条","第二条"]`，顺序不变；坏文件 `load()` **抛错**（不静默当空）；
- `T-3.35-06` **⑥ 边界**：最旧再 ↑ = `nil`（文字与光标都不动）、草稿态再 ↓ = `nil`；`⏎` ⇒ 提交 **1** 次、换行档 ⇒ 文本多一行而提交仍是 **1** 次。

**边界（如实登记）**

- 判据里的按键是**合成 `NSEvent`**（`charactersIgnoringModifiers` 用 `0xF700/0xF701`）：`AgentComposerTextView.arrow(for:)` 因此同时认 `specialKey` 与函数键码 —— 只认前者时合成事件永远落到 `nil`，判据会假绿（「一次都没接管」也符合断言）；
- 真窗口里「点一下输入框再按 ↑」这一路（第一响应者由点击建立）**没有机器判据**，留给人工点验；本节判据只覆盖「按键到达编辑面之后」；
- 高度是**按内容量出来的 1..8 行**（`AgentComposerMetrics.maxLines = 8`），超过 8 行框内滚 —— 探针没有量这个上限（它不参与六条契约）；
- 历史文件与工作区历史共用应用数据目录，但**各自一份 JSON**（`agent-input-history.json`），坏掉互不牵连。

**禁止行为**

- 禁止在 ↑↓ 判定里「顺手」处理多行中间的位置（契约①：默认交出，不是默认接管）；
- 禁止回填走发送那条路（`onSubmit`）或回填后自动提交；
- 禁止把「空串 / 全空白」写进历史（回填一条空白 = 把输入框清空）；
- 禁止在组字期间（`hasMarkedText()`）接管 ↑↓ 或 ⏎（输入法要用它们选字 / 确认候选）；
- 禁止把历史上限做成不封顶（200 是契约值，判据钉着）；
- 禁止只做内存历史不落盘（「跨重启不丢」是契约第 4 条的一半）。



### 3.36 审批授权三档：仅这一次 / 本会话内 / 总是允许

> **上游**：概设 §3 组件契约「审批授权（免问账）」行 · §10 被拒绝的替代方案（以工具名作授权键）；需求 `FR-AGT-GUARD-PERM-002` ⑦。

主人原话（装好的 beta1.0.6）：

> 「需要确认的次数太多了，要提供一次授权、会话内授权等选项」

**现状与根因（`文件:行号`，改前）**

| # | 落点 | 事实 |
|---|---|---|
| ① | `Core/AgentWorkspaceTools.swift:340`（越界出单）、`:644`（`prepareWrite`）、`:740`（`prepareEdit`）、`:818`（`prepareCommand`）、`Core/AgentStandardDispatcher.swift:314`（MCP 工具）、`Core/AgentDatabaseTool.swift:111`（`query_db`） | 六处出单只带 `toolName / fingerprint / payload / baseDigest` —— **没有「作用域」这一格**。指纹里塞着参数原文，于是「同一条命令再跑一次」也要重新问；而「能不能别再问」这件事在出单那一刻根本无从表达。 |
| ② | `App/AppState.swift:4794`（`awaitAgentApproval`）、`:4785`（`agentSessionGrants: Set<String>`）、`:4788`（`isSessionGrantable`） | 唯一的「少问」机制是**按指纹**记的会话集合：键里带着参数原文 ⇒ 同一条命令改了参数就重新问（人抱怨的正是这个），而且它**不是选项**（没有「仅这一次」这一档可比）、**不落盘**、**不可撤**（用户看不见也删不掉）。 |
| ③ | `App/AppState.swift:4837`（`resolveAgentApproval(fingerprint:granted:)`）、`App/Views/AgentApprovalDecisionRow.swift:159`（`make`）、`App/Views/AgentApprovalSheet.swift:246`（`decisionRow`）、`App/Views/AgentChatView.swift:846`（待审批卡片那两枚图标） | 决定只有「批准 / 拒绝」两档布尔值 —— **没有「以后还问不问」这一维**：批准一次就完事，界面也没有地方让人表达「这一类别再问」。 |
| ④ | 无（新增） | 「哪里算同一类」「哪些事永远不许免问」「记下来的授权在哪儿撤」此前**一条都没有**。 |

**契约四条**

1. **三档并列**（审批单与待审批卡片上都是这三档，标签写人话）：
   - **仅这一次**（默认，**不记任何东西**）；
   - **本会话内允许**（只在本会话内、同一「工具 + 作用域」不再问；会话结束 / 换会话即失效，**不落盘**到全局设置）；
   - **总是允许**（落盘到设置，跨重启生效）—— **必须同时告知后果**（一行小字：以后这类操作不再询问，可在设置里改回）。
2. **范围粒度不许糊**：记账键 = **工具名 + 规范化后的作用域值**（`AgentApprovalScope.key`，形如 `write_file|a.txt`）。作用域按工具各自的**事实**取：文件写 / 改 = 规范化路径；执行命令 = **首个词**；无路径类参数（MCP / SQL）= 参数原文摘要。**禁止「只写工具名」单键** —— 那等于「允许写 a.txt」顺带允许写全盘。
3. **危险面不降级**：`AgentApprovalHazard != .ordinary`（越界 / 删除 / 对外发送 / 凭据）**只保留「仅这一次」**，另外两档**不提供**（不是置灰）并在面板上写明原因；而且即使**盘上已经存在**一条针对该作用域的全局授权（历史遗留 / 手改文件），`isGranted` 也**不认**它。
4. **可撤回**：设置 → 智能体 → 运行策略 → **已授权的操作** 里列出所有授权（会话级 / 全局级各带档位标注），**逐条可撤**、也能一次全撤；撤销立即生效（判定读的就是这本账）。

**怎么实现（五件，各管一件事）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 档位 | `Core/AgentApprovalGrant.swift:8`（`AgentApprovalTier`） | `once / session / always` 三档；`remembersGrant` / `isPersistent` 是判定用的两个谓词（`once` 不留任何东西） |
| 作用域 | `Core/AgentApprovalGrant.swift:36`（`AgentApprovalScope`，`:59` 路径规范化 / `:70` 命令首词 / `:78` 参数摘要） | `key` = 工具名 + 作用域值；路径**按分量**规范化，不做字符串前缀匹配（`/a/x.txt` 不许匹配 `/a/x.txt.bak`） |
| 危险面 | `Core/AgentApprovalGrant.swift:86`（`AgentApprovalHazard`）、`:128`（`AgentApprovalHazardRules`：`:150` 命令、`:167` SQL、`:177` 文本网） | 三张网取**更严**的那个：命令首词 / `git` 子命令（`rm`、`git reset`、`git push` …）；SQL 首关键字（`DELETE` / `DROP` / `TRUNCATE` / `ALTER … DROP`）；工具名或参数里的发送 / 凭据字样 |
| 账本 | `Core/AgentApprovalGrant.swift:221`（`AgentApprovalGrantStore`，`:257` `isGranted`、`:271` `remember`、`:294` `revoke`、`:302` `revokeAll`） | 会话级只在内存（带 `sessionID`）、全局级落 `agent-approval-grants.json`（原子写）；`isGranted` 的**第一步**就是 `hazard.allowsGrant` |
| 闸门 | `App/AppState.swift:4808`（`awaitAgentApproval`：先看账、再问人）、`:4853`（`rememberAgentApprovalGrant`）、`:4877` / `:4888`（撤销两口）、`:1070`（给界面的投影 `agentApprovalGrants`） | 账上有 ⇒ 直接放行；没有 ⇒ 照旧问，问完按人选的那一档记账；`resolveAgentApproval` 多带一格 `tier`，先到的批准也按档记（`:4837`） |
| 接线 | `Core/AgentWorkspaceTools.swift:172`（`scope` / `hazard` 两格）、`:187`（`approvalScope`）；出单六处同上表①；`App/Views/AgentApprovalSheet.swift:265`（三档单选 + 范围 + 后果）、`App/Views/AgentApprovalDecisionRow.swift:160`（`tier` 取当前值）、`App/Views/AgentChatView.swift:876`（卡片上的「允许方式…」菜单）、`App/Views/AgentSettingsSheet.swift:474`（可撤销清单） | 界面只收集意图；判定与记账全在 Core 那本账 + `AppState` 那一处 |

**判据**（`Tests/AgentApprovalGrantTests.swift` 6 例，`Executed 6 tests, with 0 failures`；每条都带反例读数）

- `T-3.36-01` **① 仅这一次**：`remember(.once)` 返回 `nil`、账本 **0 条**、盘上**没有**文件、同工具第 2 次**仍问** = `true`；反例：若 `once` 也记账 ⇒ 账本条数 1 且第 2 次不问 ⇒ 判红。
- `T-3.36-02` **② 本会话内**：同会话免问 = `true`；**换一个会话仍问 = `true`**（反例：会话级漏成全局 ⇒ 判红）；**重启（同目录重新读盘）仍问 = `true`、落盘 = `false`**（反例：写进全局 ⇒ 判红）；`endSession` 之后同会话仍问 = `true`。
- `T-3.36-03` **③ 总是允许 + 范围**：重启后读回 **1 条**、同路径免问 = `true`；写 `/a/x.txt` 被允许而写 **`/b/y.txt` 仍问 = `true`**、同目录兄弟文件 `/a/x.txt.bak` **仍问 = `true`**、换工具（`edit_file`）**仍问 = `true`**；反例：键退化成「工具名」⇒ 后三条全部变成 `false` ⇒ 判红。
- `T-3.36-04` **④ 不可逆仍确认**：`rm -rf` ⇒ `destructive`（可记授权 = `false`）、对外发送 ⇒ `outbound`（可记授权 = `false`）；两档都选「总是」⇒ `remember` 返回 `nil`、**仍问 = `true`**；更狠的一格：盘上**预置**一条 `run_command|rm` 的「总是」授权（模拟历史遗留 / 手改文件）⇒ 读进 **1 条**且**仍问 = `true`**；反例：放行 ⇒ 判红。
- `T-3.36-05` **⑤ 撤销**：两条授权撤掉一条 ⇒ 该条**仍问 = `true`**、另一条**仍免问 = `true`**（不是一键清空）；撤销**落盘**（重启后剩 1 条、该条仍问 = `true`）；`revokeAll` 之后账本 **0 条**、盘上 **0 条**。
- `T-3.36-06` **作用域取法（判据 ②③ 的地基）**：`/a/b/../b/x.txt` 规范化成 `/a/b/x.txt`；`python3 hello.py` 的作用域 = `python3`、`write_file` 的 = `a.txt`（**不是工具名**）；`git reset --hard` ⇒ `destructive`；越界出单的作用域 = 绝对路径且危险面 = `outsideWorkspace`（永不记授权）；`DELETE FROM …` ⇒ `destructive`、`UPDATE …` ⇒ `ordinary`（可记授权）。读数：`写=a.txt 命令=python3 git=destructive 越界=/etc/hosts.bak/outsideWorkspace`。

**为什么键要窄到「路径 / 首词」**：「本会话内允许」比「总是允许」轻，但它**不是**「这一类都免问」的许可证。会话级的价值在同一个目标反复改（模型改一版再看一遍、再改回来），所以键取到文件这一级；命令取首词，是因为 `python3 a.py` 与 `python3 b.py` 的风险面对人来说是同一个（同一个解释器、同一个沙箱根），而换成 `git` 就是另一个工具。两条取法都写在 `AgentApprovalScope` 里，判据逐条钉着。

**边界（如实登记）**

- 作用域**不做目录前缀**：「允许写 `src/` 下任何文件」这一档没有做 —— 它比逐次审批更危险（人以为只批了一个文件），要放开只能在设置里改「权限配置」的沙箱根，那是另一条契约（§3.26 / `AgentPermissionConfig`）；
- SQL 的作用域是**语句原文摘要**（不是表名）：`UPDATE orders SET a=1` 与 `UPDATE orders SET a=2` 是两条 —— 宁可多问一次，也不替人把「两张表」概括成一句；
- 卡片上的「允许方式…」菜单是**界面层的提前收口**（按 `approvalPreview` 文本判危险面），与出单时的权威判定（`hazard`）**可能不一致**：不一致时以权威判定为准（`isGranted` 用的是出单那一刻的 `hazard`），界面多给一次选项也不会放行不可逆动作；
- 会话级授权的归属靠 `sessionID`（`makeAgentChatLoop` 每轮开跑刷新 `agentApprovalCurrentSessionID`）；审计面板那条审批单不在循环里，它记「本会话内」时用的是这一格 —— 从没跑过对话就直接在审计面板里批，会话级授权归 `""`，等价于「下一次跑起来之前不认」；
- 真机上的「点一下菜单再点某一档」没有机器判据（离屏宿主里 `Menu` 不落可点的 `NSButton`），本节判据覆盖的是**判定与记账**这一层；界面那两颗按钮的既有探针（`TestsUISnapshot/AgentApprovalDecisionProbeTests`）仍打在同一个 `AgentApprovalDecisionWiring.make` 上。

**禁止行为**

- 禁止把授权键记成「工具名」（§3.36 ②：那是「允一次 = 允全盘」的形状，判据 ③ 专门钉它）；
- 禁止为了少弹框把不可逆动作（删除 / `rm -rf` 类 / 对外发送 / 凭据）放进「本会话内」或「总是允许」（判据 ④：盘上有历史授权也不认）；
- 禁止把「本会话内」写进全局设置文件（判据 ②：重启后必须重新问）；
- 禁止只在内存里撤销（判据 ⑤：撤了要落盘，重启不能复活）；
- 禁止让「仅这一次」留下任何痕迹（判据 ①：账本 0 条、盘上无文件）；
- 禁止界面自己算一遍「要不要问」（判定只有一处：`AgentApprovalGrantStore.isGranted`）。



### 3.28 调试器接入（DAP）的口径层 —— 先落「出错时说真话」，再接进程

`FR-STD-WS-TOOL-003`「经 DAP 接既有调试器，支持断点、单步、变量查看，**不自研调试协议**」。
本条的三条判据都不是「能不能调试」，而是**接不上 / 被改动时说真话**，所以第一片先落口径层
（`Core/DAPCore.swift`，13 例测试），**不碰进程**：

| 层 | 内容 | 现在 |
|---|---|---|
| 分帧 `DAPFrame` | `Content-Length: n\r\n\r\n` + n 字节；**半包等下一批**、两条粘一起照切、头读不懂就丢到分隔符为止（不许死循环） | ✅ 已落 |
| 断点复验 `DebugBreakpoints.recheck` | 原行内容还在 ⇒ 不动；只在别处出现**唯一**一处 ⇒ 移到那儿并说「原位置已不存在」；找不到或**多处命中 ⇒ 移除，不猜** | ✅ 已落 |
| 调试期改文件 `DebugConsistency.warning` | 仅 `running` 时提示「代码与运行体不一致」并列出改动的文件名；`idle` / `terminated` 一律沉默（日常改动不许当噪音） | ✅ 已落 |
| 不可用不挡编辑 `DebugAvailability` | `canEdit` **恒真**（不做成配置项）；`canStart=false` 时必须给一句人话原因（缺适配器 / 立刻退出带退出码 / 握手超时 / 用户停掉） | ✅ 已落 |
| stdio 传输 + `initialize` / `launch` / `setBreakpoints` 往返（`Core/DAPClient.swift`） | 真起适配器跑最小会话；**读不阻塞写**（`readabilityHandler` 收字节）、**请求必有时限**、失败分四种报（缺适配器 / 启动即退带退出码 / 超时 / 对端关闭） | ✅ 已落 |
| 单步 / 变量读取（`DAPSession.step` / `.variables`） | `next`/`stepIn`/`stepOut`/`continue` + 栈顶帧变量；**先等事件再算停**（响应回来 ≠ 停下来） | ✅ 已落 |
| 断点面板 / 调试工具栏 UI | 界面上真的能下断点、单步、看变量 | ⬜ 下一片 |

**为什么不先起进程**：一次 `swift test` 能核的东西先钉死（半包、粘包、断点漂移、噪音提示），
否则等真接上 lldb-dap 时，才发现「半包被当成格式错误」这类问题会跟协议本身混在一起。

**判据**：`Tests/DAPCoreTests.swift` 13 例 + `Tests/DAPClientTests.swift` 7 例（假适配器测传输与单步）+ `Tests/DAPSmokeTests.swift` 1 例（**真 lldb-dap 烟测**，需 `DOYAH_DAP_SMOKE=1`）。
实测：假适配器 7 例 0 failures；真适配器烟测 **1 例 0 failures**（clang 编 C 程序 → 断点停在第 5 行 → 步过后行号变化 → 读到局部变量 `i` / `total`）。
未设 `DOYAH_DAP_SMOKE` 时该例报 `skipped`（**没条件 ≠ 通过**）。
反例都写在用例里：多处命中不许猜、没在调试时不许弹「不一致」、调试器不可用时编辑必须仍可用。


### 3.29 对话区的两处可观测口径

`FR-AGT-UX-SESS-001` / `FR-AGT-TOOL-SYS-002` 在 2026-11-04 真机点验时暴露了两处「看着像卡住」的显示缺陷，
当天已修（提交 `46cec72e`），但**详设当时没跟上** —— 换人接手只会看到两个魔法数。本节把它钉成契约。

| 口径 | 落点 | 契约要点 | 判据 |
|---|---|---|---|
| 步数计数的分子与分母 | `App/AgentChatModelStepCounter.swift` + `Core/AgentChat.swift` | 分母 = 本次运行**允许的总步数上限**（来自 `AgentLoopLimits`），分子 = 已走步数；**分母不许随已完成步数增长**（旧实现把分母写成「当前步数」，于是显示成 1/1、2/2，用户看永远「刚开始」） | `Tests/AgentStepCounterTests.swift` 6 例（含「分母恒为上限」反例：喂 5 步后分母仍是同一个数） |
| 执行步骤详单的展开高度 | `App/Views/AgentStepListPanel.swift` | 详单有**最大高度**，超出后**内部滚动**；窗口不再被一长串步骤撑高，输入框与发送键始终在视野内 | `TestsUISnapshot/AgentChatStepListProbeTests.swift`（40 步的长详单：面板高度 ≤ 上限、内部可滚动、输入区仍在） |

**禁止行为**

- 禁止把步数分母写成「已完成步数 + 1」这类「看起来一直在动」的实现（那是骗人，不是进度）。
- 禁止让步骤详单无上限撑开窗口（滚轮在窗口外就找不到输入框）。
- 禁止把「步数」当 token / 时长指标展示（三个口径不许互相换算）。

**测试 ID**：`T-3.29-01`（分母恒为总上限）· `T-3.29-02`（40 步详单不撑窗口）

### 3.30 子代理委派的隔离与记账

`FR-AGT-TOOL-SYS-002`（子任务委派）在 2026-11-04 真机点验时三个缺陷当天修完（提交 `3ac07a7a`），
详设原先只在 §3.20 写了「并行编排」的能力面，没有这三条**隔离约束**，等于把最容易回归的地方留空。

| # | 约束 | 落点 | 违反时的形态（都已真机见过） | 判据 |
|---|---|---|---|---|
| ① | **子路事件不进主对话** | `Core/AgentSubtaskEventChannel.swift`（分流通道） | 子代理的工具调用、进度、错误直接混进主对话流，用户以为主控自己跑偏了 | `Tests/AgentSubtaskIsolationTests.swift`（子路发 3 条事件：主对话只收到 1 条归并摘要） |
| ② | **预算按子循环截止时刻算** | `Core/AgentSubagentExecution.swift` + `Core/AgentLoop.swift` | 预算沿用主控截止时刻 ⇒ 子路一开跑就「超时」，或反过来无限跑 | 同上（子路 deadline = 派单时刻 + 子预算，主控预算不受影响） |
| ③ | **同 id 重派换子会话号** | `Core/AgentSubagentExecution.swift` | 复用旧子会话号 ⇒ 新一轮继承了上一轮的上下文，模型照着旧结论干活 | 同上（同 id 重派后会话号不同，历史不串） |

**禁止行为**

- 禁止子路直接写主对话的消息数组（必须经 `AgentSubtaskEventChannel` 归并）。
- 禁止子路继承主控的凭据与授权（§3.20 已禁，这里再钉一次：审批单只能由主控出）。
- 禁止把「重派」实现成「续跑」（重派 = 新会话号 + 新预算 + 干净上下文）。

**测试 ID**：`T-3.30-01`（子路事件不混主对话）· `T-3.30-02`（子路预算独立于主控）· `T-3.30-03`（同 id 重派换子会话号）

### 3.37 过程区高度自适应与结论正文去壳

> **上游**：概设 §8.11 ⑦（过程区高度与阶段形态，跨端三条硬约束）· §8.11 ⑧；需求 `FR-AGT-UX-CONV-003` ⑧⑪、`FR-AGT-UX-CONV-006`。

主人装上 beta1.0.8 后的两句话：

> 「现在又变成了 thinking/tools 等区域是固定高度，中间空一个大空白区域，只有等返回最终结论之后
>  才能填满，这个给人感受不好。」

> 「结论不要带『结论』二字前缀，首行直接就是答案内容。」

前一轮（§3.33.2 ③）为压住「高度一个 token 抖一次」，把展开态钉成**恒 200pt**；钉住之后内容只有
一两行时下面空一大块。本轮把口径改成 **高度 = min(内容实测高, 上限)**，且内容高**按整行向上取** ——
「抖」与「空白」两个反例在同一条口径下同时关掉。同日主人补了**阶段形态**的拍板（和 Hermes 对齐）：
运行中「看得见、贴着长、跟着滚」，终态「自觉让位、一行交代」。

**根因（`文件:行号`，改前）**

| # | 落点（改前） | 事实 |
|---|---|---|
| ① | `Core/AgentThinkingStream.swift:132-134`（`AgentThinkingViewport.height(expanded:)`） | 只返回两个数：`200` / `20`。**没有任何「内容有多少」的输入口** ⇒ 视图没有第二个选择 |
| ② | `App/Views/AgentProcessBlocks.swift:305-308`（`.frame(height: AgentThinkingViewport.height(expanded: expanded))`） | 展开态整块被钉成常量 200pt |
| ③ | 同文件 `:353-355`（视口 `.frame(height: Self.contentMaxHeight)` = 178pt） | 视口同样定高 ⇒ 一行内容也硬占 178pt（这就是主人看到的「中间一个大空白区域」） |
| ④ | 同文件 `:95`（工具块行体 `.frame(maxHeight: Self.bodyMaxHeight)`）与 `:506`（`Tool calls` 行体同） | 行体只有**上限**：短内容时真机留白、离屏宿主又拿满 216 ⇒「几条调用占多高」没有唯一答案 |
| ⑤ | `App/Views/AgentChatView.swift:1709`（`conclusionBody(AgentAnswerClassifier.split(…).conclusion…)`）+ `:1717`（`conclusionBody` 直出 `markdownBody(text)`） | 结论段**原样**进 markdown 渲染 ⇒ 模型/模板带的 `结论：`、`## 结论`、`📌` 全被当正文首行画出来 |
| ⑥ | 审计结论（如实登记）：语言表里**没有**「结论」标签键（`Localization.swift` 全文只有 `diagnosisFormatConclusion` 等诊断域键，与对话正文无关） | 这层壳**不是**本轮某处模板新加的，而是模型原文 + markdown 标题带进来的；所以只能在**渲染前**剥，不能在语言表里删 |

**契约（九条）**

1. **高度口径**：展开态整块高 = `min(抬头 20 + 发丝 2 + 内容实测高, 200)`；内容视口高 = `min(内容实测高, 178)`。
   折叠态不变（一行 20pt）。
2. **量化（不许退回逐 token 抖）**：内容实测高先按**整行向上取**（`AgentThinkingViewport.quantizedContentHeight(_:)`，
   步长 = `Metrics.listRowHeight` = 20pt），再进第 1 条。⇒ 高度只在**跨过行高倍数**时变；一次上屏最多把下面
   的正文推**一整行**，而推的总量 = 内容真长出来的高度。
3. **内容实测**：`App/Views/ContentHeightSpy.swift`（零行为 `NSView`）挂在**内容根**上回读 `frame.height`
   （`ScrollView` 沿滚动轴给内容无约束高度 ⇒ 读到的是**自然高**，不是被视口裁过的）。两条纪律：回调**拖到
   下一拍**（布局中改 `@State` 会重排两遍）；**只有量化值变了才写状态**（写一次 = 一次重排）。
4. **过程行体（工具块 / `Tool calls`）**：行数是整数、行高是常量 ⇒ 直接算
   `AgentProcessBody.height(rows:spacing:cap:)` = `min(行数×20 + (行数−1)×2, 216)`。两条调用就 64pt，
   不再先占满 216；60 行才卡 216。
5. **阶段形态表**（运行中 / 终态两列 × 思考区 / 工具区 / 结论三行）：

   | 行 | 运行中（本轮未结束） | 终态（完成 / 失败 / 取消） |
   |---|---|---|
   | 思考区 | 展开；高 = min(内容实测高, 200)，超了内部滚；50ms 合批上屏（§3.33.2 ①）；运行中不画滚动指示器 | **自动折成一行 20pt**：`▸ Thinking  ~N tokens` |
   | 工具区 | 按调用各自成块；展开态高 = min(行数×20, 216)；跑着的调用调暗一档 | **折成一行 20pt**：`▾ Tool calls (n)  ~N tokens`，其后跟 `Σ ~N total` 一行 |
   | 结论 | 只画结论段（§3.33），随流式增长 | 完整可见、默认不折（`longPreview = off`） |

6. **一次跳变**：运行中 → 终态**只允许一次**高度跳变（过程区从「贴着内容」直接切到「一行 20pt」），
   中途不许反复抖；**不加 `withAnimation` 改高度**（动画逐帧插值 = 又一档闪）。
7. **结论不带壳**：渲染前经 `AgentAnswerLabel.stripping(_:)`（`Core/AgentAnswerSplit.swift`）剥掉开头那层
   标签壳（`结论：` / `Conclusion:` / `## 结论` / `📌` / `**结论**：`，最多叠 3 层）。**只动展示**：
   `message.text`、会话记录、复制、IM 转发、审计指纹读的都是原文。正文中间出现「结论」两字是内容（不动）；
   `结论是：…` 这种句子不是壳（标签后必须紧跟分隔符），原样保留。

8. **过程区与结论之间只有一块块间距**：`Σ total` 那一行底边到结论首行顶边的距离 ==
   `AgentProcessBlock.answerGap`（= 转写区既有块间距 `Spacing.xs` = **4pt**）。
   前提是**被折进三行汇总的那些消息一个都不占行**：工具行与轮内中间叙述折进汇总之后，
   行首栏时间戳与悬停操作条仍会让那一行占位（`.opacity(0)` 不参与「是否占位」的判定）——
   实测一段 6 条消息的轮次里，Σ 行到结论之间有 3 个这样的空行 ⇒ 空白 **61pt**。
   判定只走 `AgentTranscriptRow.draws(role:text:isStreaming:isFinalAssistant:foldedIntoTurnSummary:streamingEnabled:)`
   （视图与判据同一份）；一行都不画的消息**整行不出现**（连行首栏一起）。
   这一条与 §3.33.4 的「三行汇总」是同一件事的两半：汇总收进去的内容不许在下面再占一次位。
9. **折叠态三行之和 = 60pt**：三行各一行 20pt、**行间不留间距**（`AgentProcessBlock.rowSpacing` = 0），
   折叠态过程区高 = `AgentProcessBlock.collapsedHeight` = **60pt**，不多不少。
   改前三行之间有 `Spacing.hair`（2pt）× 2 = 4pt 的额外空隙（64pt）：既与「三行之和」对不上，
   视觉上也是「汇总区自己空了一块」。折／展**不许出现中间尺寸**（不加 `withAnimation`，见第 6 条）。

**产品形态（这一节之后长什么样）**：思考区高度跟着内容走 —— 一行 **42pt**、八行 **162pt**，
超过上限才 **200pt** 并在内部滚；终态的三行汇总一共 **60pt**（3 × 20pt，行间不留缝），
下面直接接结论；结论首行就是答案本身，`结论：` / `## 结论` / `📌` 这些壳不出现（原文一个字节不改）。

**怎么实现（四件）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 口径（纯函数） | `Core/AgentThinkingStream.swift`（`AgentThinkingViewport.quantizedContentHeight` / `expandedViewportHeight` / `expandedHeight` / `isOverflowing`、`AgentProcessBody.height`） | 量化、限高、行体高**只有这一处**算；视图与判据读同一份 |
| 实测 | `App/Views/ContentHeightSpy.swift` | 内容根自然高 → 下一拍回调；只在高度真变时回调 |
| 形态 | `App/Views/AgentProcessBlocks.swift`（`AgentThinkingZone` 的 `measuredContentHeight` / `viewport(_:)`、`AgentToolBlockView` 行体、`AgentToolCallsSummaryRow.bodyRowCount`） | 高度 = 口径函数的结果；`@State` 只存**量化后**的实测高 |
| 剥壳 | `Core/AgentAnswerSplit.swift`（`AgentAnswerLabel`）+ `App/Views/AgentChatView.swift:1717`（`conclusionBody` 里一次调用） | 剥壳规则在 Core（可判红），剥的**位置**在渲染前 |

**判据**（`TestsUISnapshot/AgentThinkingAdaptiveHeightProbeTests.swift`，900×620 真视图，`DOYAH_UI_SNAPSHOT=1`；
纯函数部分 `Tests/AgentThinkingStreamTests.swift` 3 例 + `Tests/AgentAnswerSplitTests.swift` 2 例）

| 判据 | 读数（真跑） | 反例（同一套判定函数） |
|---|---|---|
| `T-3.37-01` **① 1 行 ⇒ 一行高** | 一行思考：区高 **42.0pt**（= 抬头 20 + 发丝 2 + 一行 20），**< 200** | 改前形态（`LegacyFixedHeightZone` 恒 200pt）：**200.0pt** ⇒ 判红 |
| `T-3.37-02` **② 高度随行数递增** | 1 / 3 / 8 行 ⇒ **42 / 82 / 162pt**（内容 16 / 46 / 121pt） | 任一档不高于前一档 ⇒ `monotoneGrowthViolations` 判红 |
| `T-3.37-03` **③ 超上限恰为 200pt + 内部滚** | 60 行：区高 **200.0pt** / 视口 **178.0pt** / 文档 **901.0pt** | 桌面高 ≤ 视口 ⇒ 报「内部滚动没生效」；区高 ≠ 200 ⇒ 判红 |
| `T-3.37-04` **④ 流式不抖** | 300 次追加（每次 8 字、不换行）：首 **42pt** → 末 **200pt**，高度**只变 8 次**，内容 496pt = **25 行**（8 ≤ 25）；单调不减 | 300 次各变 0.6pt 的样本（未量化那版的形状）⇒ 变 299 次 > 25 行 ⇒ 判红 |
| `T-3.37-05` **⑤ 无空白** | 区高 − 自然高：1 行 **4.0pt** / 3 行 **14.0pt** / 8 行 **19.0pt**，三档都 **< 一行 20pt** | 恒 200pt + 一行内容（16pt）⇒ 空白 **162pt** ⇒ 判红 |
| `T-3.37-06` **⑥ 阶段形态（只跳一次）** | 运行中 5 行 ⇒ **102.0pt**；切终态后连采 12 拍全部 **20.0pt**，全过程**跳变 1 次** | 逐帧插值（多次中间值）⇒ 跳变次数 > 1 ⇒ 判红 |
| `T-3.37-07` **⑦ 终态工具区一行** | `Tool calls (3)` 折叠态行高 **20.0pt** | 终态仍展开 ⇒ 行高 > 20 ⇒ 判红 |
| `T-3.37-08` **⑧ 结论不带壳** | 7 个带壳样本（`结论：` / `结论:` / `**结论**：` / `## 结论` / `Conclusion:` / `📌 结论：` / `✅ 已改好：`）全部剥净；3 个正文样本（句中「结论」/「结论是：」/ 无壳）**逐字节不变** | 不剥的原文（`结论：口令错了。`）喂同一套判定 ⇒ 判红 |
| `T-3.37-10` **⑩ 汇总区与结论的间距**（`TestsUISnapshot/AgentSummaryGapAndTurnFollowProbeTests.swift`） | `Σ total` 行底边 → 结论首行顶边 = **4.0pt**（= 块间距 `AgentProcessBlock.answerGap`），过程区高 **60.0pt** | 改前读数 **61.0pt**（3 个空行：15×3 + 块间距）喂同一套判定 ⇒ 判红；阈值就是一行 20pt |
| `T-3.37-11` **⑪ 折展往返不变、无中间尺寸** | 运行中 `Tool calls` 展开（行高 **86.0pt**）时间距 **4.0pt**；切终态折回后仍 **4.0pt**；折回全过程连采 **10 拍**全部 **4.0pt** | 换算成另一档间距（4 → 16pt、中间两档）⇒ `roundTripViolations` 判红 |
| `T-3.37-12` **⑫ 三行之和 60pt** | 折叠态过程区高 **60.0pt**（= 3 × 20pt，行间 0） | 改前 **64.0pt**（行间 2pt × 2）⇒ 判红 |
| `T-3.37-09` **量化/限高/行体（纯函数）** | 量化 `0/1/15/19.9/20/20.1/39.9/40/178/179/1000` ⇒ `0/20/20/20/20/40/40/40/180/180/1000`；60 行 ⇒ **200.0pt**；行体 1/3/60 行 ⇒ **20/64/216pt** | 量化差 ≥ 一行 / 60 行不到 200 / 1 行占满 216 ⇒ 判红 |

**边界（如实登记）**
- 探针读的是**锚视图的 frame 高**（`AgentThinkingZoneMarker`），与生产同一份渲染代码；内容高读的是那格
  `NSScrollView` 的 `documentView.bounds.height`（= 内容自然高，未被视口裁）。
- `ContentHeightSpy` 的回调是**异步下一拍**：离屏宿主必须 `settle → 跑 30ms → settle` 才读得到稳定值
  （探针里 `settleHeight(_:)`），真机上就是「一次 coalescer 窗口之后」。
- 量化向上取整 ⇒ 内容未超上限时**最多留不到一行**的余量（实测 4 / 14 / 19pt，判据⑤ 的阈值就是一行）；
  这是「不抖」的必要代价，登记在案。
- §3.33.2 的「定高 200pt」与 §3.33.4 的「禁止改定高 200」**被本节取代**（折叠 20pt 不变）；原文保留以便追溯。
- 三行汇总的**行间间距由 2pt 收到 0**（§3.33.4 的 `AgentProcessBody.height` 那条「3 行 ⇒ 64pt」是**行体内**的
  明细行口径，不受影响）：这两处过去被当成同一条，实测才发现「三行之和」对不上 —— 汇总带是**一条读数带**，
  不是三个卡片。
- 结论剥壳是**展示层**行为：同一条消息在会话文件里仍带 `结论：`，复制/转发走出去也仍带（那是原文）；
  本轮**没有**改模型侧提示词（不许拿「提示模型别写」冒充实现）。

**禁止行为**
- 禁止把展开态高度写回常量（`200` / `178` 只作**上限**用）；
- 禁止用未量化的实测高直接当高度（一个 token 一次 0.3pt 的重排 = 上一轮那个缺陷）；
- 禁止在布局过程中同步写 `@State`（`ContentHeightSpy` 的回调必须下一拍）；禁止每次回调都写状态（只在量化值变时写）；
- 禁止给高度变化加 `withAnimation`；
- 禁止为了「不空」把内容行数补齐（用空白行/占位行填满是同一个缺陷的另一种画法）；
- 禁止在渲染处**改写** `message.text` 来去掉壳（原文是审计与复制的唯一来源）；剥壳只能发生在 `AgentAnswerLabel`；
- 禁止扩大剥壳范围（句中「结论」、`结论是：…` 都是正文）。

### 3.38 工作区根的两态来源：默认 `~/.doyah` 与用户打开

> **上游**：概设 §3 组件契约「工作区根」行（根只有两态、来源可查）· 「越界授权」行（边界取这个根）· §11 依赖与权限约束 · `P-29`（默认工作区根与来源）。
- 对应概设条款：§3「工作区根」行（**默认 / 用户打开**两态、来源可查、迁移必须给可见提示）+「越界授权」行（读写与执行边界一律取这个根）
- 对应需求：`FR-STD-WS-FS-002` ⑥（工作区根只有「默认 / 用户打开」两态，不许从别处推断）；受它约束的边界 = `FR-AGT-CORE-LOOP-006`、`FR-STD-WS-AI-002`、`FR-STD-WS-FS-010`

**为什么单列**：工作区根以前是**推**出来的 —— 活动书签（`workspace-bookmark.json` 里记的那一条）
和会话快照里的 `workspacePath` 一起决定它。同一个 bundle 标识的所有包共用一份数据目录，
于是装到 `/Applications` 的正式包会继承开发时打开的开发目录，Agent 的读写边界就锁在某个开发树里。
根不是「上次刚好打开过哪儿」的副产品：它必须是一个**有来源的决定**。

| 环节 | 契约 | 落点 |
|---|---|---|
| 两种来源 | 根只有 `默认`（`~/.doyah`）与 `用户打开`（用户经「打开文件夹…」选定）两态。不承认第三态；**不许从别处推断**（编译目录、进程工作目录、书签表第一条都不是来源） | `Core/WorkspaceRootOrigin.swift`（`WorkspaceRootOrigin`） |
| 首次运行 | 数据目录里没有来源标记 ⇒ 根 = `~/.doyah`；目录不存在则**创建**，建完**验证可写**，不可写如实报一句（不装作能干活） | `WorkspaceStore.adoptDefaultRoot` |
| 用户显式打开 | 根 = 那个目录；来源落 `用户打开` 并持久化；重启仍用它。书签缺失也不许静默落回默认根 | `WorkspaceStore.choose` / `switchTo` / `markUserOpened` |
| 旧数据迁移 | 盘上有 `workspacePath`（活动书签 / 会话快照）但**没有来源标记** ⇒ 视为未显式选择：根落默认根，并写一条**可见提示**；提示写明新根与原目录，重启后不再重复 | `WorkspaceRootPlanning.plan` + `WorkspaceStore.originNotice` |
| 可见性 | 「智能体工作区」一格常驻设置页（页签之外，翻到哪页都在）：绝对路径 + 来源（默认 / 用户打开）+「恢复默认（`~/.doyah`）」按钮；已停在默认根时按钮置灰。工作区编辑区顶部另有一行迁移提示条 | `App/Views/AgentWorkspaceSection.swift`、`WorkspaceAreaView.originNoticeBar` |
| 恢复默认 | 一键回默认根，来源同步落盘。已知工作区表**不清空**：用户还能从列表切回某个目录，那一次重新记成「用户打开」 | `WorkspaceStore.restoreDefaultRoot` |
| Agent 作用域 | 工具（读 / 写 / 搜索 / 命令）的边界一律取这个根；宿主只有一条路把它交给工具：`workspacePathProvider` ⇒ `AgentWorkspaceTools(root:)` | `DoyahStudioApp`（`appState.workspacePathProvider`）、`AppState.makeAgentChatLoop` |
| 沙箱 | `~/.doyah` 在容器之外：沙箱构建必须持有 home-relative 读写例外，否则默认根这一态在沙箱下写不进去（非沙箱构建不受影响） | `App/DoyahStudio.entitlements` |
| 扫码桥脚本 | 桥脚本的候选路径落在用户数据目录（`<应用数据目录>/qq-qr-bridge.mjs`），不写开发仓库路径 | `QQLoginController.defaultBridgePath` |

**禁止行为**：禁止从书签表 / 会话快照直接推出根（那是「继承」，不是「来源」）；禁止迁移静默
（换了根而界面不说一句话）；禁止把默认根写进书签表（下次会被当成「用户打开」的候选）；
禁止在默认根建不出来 / 不可写时假装工作区已就绪；禁止把开发仓库路径写进产品代码的候选路径。

**测试 ID**：`T-3.38-01`（空数据目录 ⇒ 默认根、目录被创建且可写）· `T-3.38-02`（旧数据 ⇒ 默认根 + 可见提示，重启不再重复）·
`T-3.38-03`（用户打开 `/tmp/ws-x` ⇒ 根与来源成立，重载仍是它）· `T-3.38-04`（恢复默认 ⇒ 回默认根且重启保持）·
`T-3.38-05`（根内写成功、根外写出越界单且不落盘）

### 3.39 回到底部的浮动入口

> **上游**：概设 §8.11 ⑧（回到最新内容并恢复跟随）· §8.5 交互规则；需求 `FR-AGT-UX-CONV-003` ⑩。

主人 2026-11-08 的原话：

> 「用户拖动会话界面到上面去之后，在 This task 框上沿（会话对话框的最底部）出现一条浮动的、
>  可点击的文字「回到消息底部」，类似 DSH-tui 的效果」

**为什么另立一条入口**：它与 §3.34 的吸顶条是对话区上下两头的**一对**，管的却是两件不同的事 ——
吸顶条把人带回**本轮开头**（往回看时还认得出问的是什么），这条把人带回**最新内容**，
并把跟随**重新贴上**。只滚到底、不恢复跟随等于「下一条增量又停在半路」（§3.33.3 已经修过的
同一个坑的另一侧），所以点击的语义必须是「回到跟随」，不是「滚这一次」。

**落点（`文件:行号`，新增）**

| 部件 | 落点 | 职责 |
|---|---|---|
| 判定（纯函数） | `Core/AgentJumpToBottom.swift`（`isVisible(currently:distanceToBottom:isPinnedToBottom:)` + 尺寸常量 + `reservedHeight(visible:)`） | 出现 / 消失门槛、入口高、上下间距、保留条高（出现 40 / 不出现 **0**）**只有这一处**算；视图与判据读同一份 |
| 入口本体 | `App/Views/AgentJumpToBottomBar.swift`（`AgentJumpToBottomBar` / `AgentJumpToBottomReservedStrip` / `AgentJumpToBottomStripMarker` / `AgentJumpToBottomClickButton`） | 胶囊形态、位置（视口下方那一条保留窄条）、真 `NSButton` 点击面、**条高读数点** |
| 显示态接线 | `App/Views/AgentChatView.swift`（`showsJumpToBottom`、`StickyQuestionSpy` 读数闭包里的一次判定、`jumpToBottom()`） | 只读读数器的结论（距底 + 贴底态），不自己拼几何 |
| 落点与状态机 | `App/Views/StickyQuestionAnchor.swift`（`StickyQuestionScroller.jumpToBottomRestoringFollow()` → `SpyView.jumpToBottomRestoringFollow()`） | 撤本轮落点、把状态机重置为贴底、滚到内容底边（与跟随同一个落点） |
| 尾部读数点 | `App/Views/StickyQuestionAnchor.swift`（`AgentTranscriptTailAnchor`） | 内容末尾 1pt 记号：判据量得到的「最后一行的底边」 |
| 文案 | `Core/Localization.swift`（`agentChatJumpToBottom`） | 中文「↓ 回到消息底部」/ 英文「↓ Jump to latest」 |

**契约六条**

1. **出现条件**：距底 **> 40pt** 且**不在贴底态**（`AgentScrollFollow` 判）时出现；距底回落到
   **≤ 4pt**（= 贴底容差 `AgentScrollFollow.bottomTolerance`）即消失；两档之间**保持现状**（滞回）——
   否则在 40pt 上下抖一像素，入口就闪一次。带上「不在贴底态」这一条的理由：内容刚长高、我们还没跟上
   的那一帧距底也可能 > 40pt，但那是**我们自己**落后，弹出入口等于催人去点一下。
2. **位置**：对话区**底部**、滚动视口**之下**的一条**保留窄条**里，水平居中；入口高 **22pt**
   （落在 20–24 的带里），胶囊底 + 半透明毛玻璃；入口上沿距视口底 **≈ 4pt**（呼吸），
   底边距对话区底边 **≈ 12pt**（块间距 `Spacing.m`）。条高 = 呼吸 4 + 入口 22 + 底边间距 12
   + 视口内衬 2 = **40pt**，**只在入口出现时占位**。
   - **不叠层**：条是滚动视口**下面的兄弟**，视口到条的上沿为止 —— 入口若浮在正文上，
     「正好贴底」时确实不遮，可**上翻途中**经过入口那一条的正文会被压掉半行
     （上一版取证图上就是压住了最后可见的一行）。这是本条的硬形态：**入口矩形与正文可视矩形不相交**。
   - **不出现时高 0**：`if` 分支整个不建，`VStack` 少一格，视口立刻拿回那 40pt ——
     恒留一条空带等于「入口不在时也长期白占一格」，那是白留白，不是留位。
   - **为什么条件占位不会「关不掉」**：滚到内容底边时 `NSClipView` 把偏移**夹到**
     `内容高 − 视口高`，距底恒 **0.0pt** ⇒ 消失门槛（≤ 4pt）永远可达（判据②/④ 量的就是这个数；
     上一版「滚到底仍差一条」的推理漏了夹紧这一步）。
   - **硬约束：条高 ≤ 出现门槛**（40 ≤ 40）。出现要求「距底 > 40」，故出现那一拍偏移离底已超过
     一条，视口缩短**不需要**夹紧偏移 ⇒ **正文一行都不跳**（`appearsWithoutShiftingContent`）。
   - **高度跳变一次到位**：条上没有动画（`.transaction { $0.animation = nil }`），
     出现 / 消失各只有**一次**视口高跳变，采样无中间值（判据④）。
   - 与 §3.34 吸顶条**同一方向**（都挤视口、都不盖正文），差别只在挤的是底部一条。
3. **文案与形态**：`↓ 回到消息底部`（语言表新增键 `agentChatJumpToBottom`，中英齐；中文不留英文）；
   一行、宽度按文字收（不是通栏装饰条），悬停给完整文案。
4. **点击**：滚到**内容底边**（与跟随同一落点，距底 0pt）**并恢复自动跟随** ——
   `jumpToBottomRestoringFollow()` 先撤本轮落点、再把状态机重置为贴底、最后滚；
   此后新内容仍贴底（不是「只滚这一次」）。入口在点下的那一刻**当场隐去**（不等下一拍读数）。
5. **与既有共存**：顶部吸顶条（20pt，§3.34）、三行汇总（§3.33.4）、过程区自适应高度（§3.37）
   行为一个字不变；上翻时吸顶条仍显示本轮问题，两者同屏且互不重叠。
6. **不抢滚动**：入口只是带里的一个快捷入口 —— 它不在滚动链上、不拦滚轮与滚动条拖动，
   滚动位置永远由用户与跟随状态机决定；人继续滚，入口按距底判据自己进出，不需要谁去「关」它。

**判据**（`TestsUISnapshot/AgentJumpToBottomProbeTests.swift`，900×620 真视图，`DOYAH_UI_SNAPSHOT=1`；
纯函数 8 例在 `Tests/AgentJumpToBottomTests.swift`。探针读数：**Executed 5 / 0 failures**；
跑法见下方「跑法」）

| 判据 | 读数（真跑） | 反例（同一套判定函数） |
|---|---|---|
| `T-3.39-01` **① 入口不吃正文** | 入口 `{383.5, 476.5, 133, 22}` vs 正文可视 `{0, 20, 900, 453.5}`：吃掉可视正文 **0.0pt**、视口底部那一行可见高 **15.0pt** = 行高、与无入口基线（`jumpToBottomEntry: false`，同一位置）**15.0pt** 相同 | 叠层写法（入口浮在视口底内侧 12pt、高 22）⇒ 吃掉 **22.0pt**、那一行只剩 **12.0pt** ⇒ 判红 |
| `T-3.39-02` **② 入口不在 ⇒ 保留条 0、空间还回去** | 贴底：距底 **0.0pt**、入口高 **0.0pt**、保留条 **0.0pt**、视口 **493.5pt** = 无入口基线 **493.5pt** | 恒留 40pt 空带（条 40pt、视口 453.5pt）⇒ 判红 |
| `T-3.39-03` **③ 点一下 ⇒ 距底 0、入口与条都归 0、跟随恢复** | 距底 **240.0 → 0.0pt**、入口 **22.0 → 0.0pt**、条 **40.0 → 0.0pt**、视口 **493.5pt**（= 基线）；随后连追加 **5 次**，距底 **0.0/0.0/0.0/0.0/0.0pt** | 只滚一次、跟随没恢复（距底 0/0/12/24/36pt）⇒ 判红 |
| `T-3.39-04` **④ 出现 / 消失各只跳一次** | 出现：采样 **51** 点 → 只有两个视口高 **513.5 → 473.5pt**（跳变量 40.0pt）；消失：采样 **54** 点 → **473.5 → 513.5pt**；消失后距底 **0.0pt** | 出现时逐帧插值（513.5 → 493.5 → 473.5，3 个值）⇒ 判红 |
| `T-3.39-05` **⑤ 入口与正文可视矩形不相交** | 入口 `{383.5, 476.5, 133, 22}` vs 正文可视 `{0, 20, 900, 453.5}`：上沿在视口底之下 **3.0pt**、相交 **0.0pt** | 入口伸进视口 10pt ⇒ 相交 `{383.5, 466.5, 133, 7}`（高 **7.0pt**）⇒ 判红 |
| `T-3.39-06` **⑥ 与吸顶条共存** | 上翻时吸顶条高 **20.0pt**（`{0, 0, 900, 20}`）+ 入口高 **22.0pt**（`{383.5, 476.5, 133, 22}`），视口 `{0, 20, 900, 453.5}`，两者不重叠 | 入口落进吸顶条那一行 ⇒ 判红；任一方不在场 ⇒ 判红 |

**跑法**（本机 `xcode-select` 指向 CommandLineTools 时 `XCTest` 不在那份 SDK 里 ⇒ 必须走仓里的口径）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
DOYAH_UI_SNAPSHOT=1 "$SWIFT" test --scratch-path .build-agent \
  -Xswiftc -DDOYAH_UI_SNAPSHOT --filter AgentJumpToBottomProbeTests
```

**边界（如实登记）**
- **保留条只在入口出现时占位**（不出现时 0pt）：代价是入口进出各一次 40pt 的视口高跳变 ——
  这是「不叠层」与「不白留白」两条约束的交点，跳变要求**一次到位**（判据④ 采样无中间值），
  不是「逐帧长出来」。
- 距视口底 / 对话区底边的两个量，探针量的是**可见内容区（`NSClipView`）**的框，不是
  `NSScrollView` 自己的框：后者底部比可见区多 2pt（滚动条那条边），拿它量会整体差 2pt。
- 「视口底部那一行」是一个**几何带**（高 = 一个等宽行高，贴在视口底边），不是某一段文本的 run：
  SwiftUI 的 `Text` 在 macOS 上不落 `NSView`，逐行矩形取不到。带在**两态、两个视图**上用同一个定义，
  所以「差多少」是真读数（叠层那 22pt 就是这么量出来的）。
- 离屏宿主里读数是**异步回写**：`RunLoop` 泵循环期间主队列块不落地，探针必须走 `pumpAsync`
  才收得到读数（否则入口根本不露面，会误判成「不出现」）。
- 取证截图 `agent-jump-to-bottom-zh.png` / `-en.png` **上翻两屏之后**拍：入口的位置、尺寸、文案都看得到，
  但离屏宿主那一拍的 `LazyVStack` 行没被画出来（回收后没重新物化）—— 这是取证工具的能力边界，
  不是正文不渲染（同一拍里行的 frame、尾部记号、保留条 frame 都量得到）。两张图**必须重建视图树**
  才换语言（活宿主切语言不会重排，上一版实测两张逐字节相同 ⇒ 语言覆盖门禁会判红）。
- 「距底」在长会话里会被 `LazyVStack` 的估值抬高；判据只要求「> 40pt 且不在贴底态」，
  不要求等于脚本设的那个数（实测：上翻 100pt 的请求在入口出现后读成 140pt，多出来的就是那 40pt 条）。
- 新轮落在本轮开始处、而本轮内容比一屏长时，距底同样 > 40pt ⇒ 入口也会出现（那确实离底很远，
  且下一条增量不会把人拽回来）。这是有意的：它描述的是「离底多远」，不是「谁滚的」。

**禁止行为**
- 禁止拿「距底 > 40pt」一个数同时判「人上翻」与「内容长高」（必须带上贴底态，同 §3.33.3 口 2）；
- 禁止让入口叠在正文上（任何一行被入口压住即违反契约 2；判据① 的 `eaten > 0`、判据⑤ 的矩形相交就是这条的红）；
- 禁止入口不在时仍占一条空带（恒留 40pt ⇒ 判据② 红：那是白留白）；
- 禁止让保留条高超过出现门槛（40 > 40 时入口一出现就要夹紧偏移、正文跳一条，`appearsWithoutShiftingContent` 判红）；
- 禁止给保留条加动画 / 逐帧插值（判据④ 的采样会出现中间值）；
- 禁止点击只滚到底、不重置跟随状态机（下一条增量又会停在半路）；
- 禁止在视图里另存一份「贴不贴底」（§3.33.3 扣 7 同一条：两份副本必然漂移）；
- 禁止把入口做成通栏 / 常驻（它不是又一条状态栏，是一行可点的胶囊）；
- 禁止中文文案里夹英文、或英文文案里夹中文。

## 4. 数据与状态

### 4.1 内部结构映射

| 概设实体 | 本端类型 | 关键字段 | 序列化契约 | 允许写入方 |
|---|---|---|---|---|
| 连接配置 | `ConnectionConfig` | id / name / dbType / host / port / database / username / sslMode / timeout / schemaVersion / isReadOnly / group / sshTunnel | JSON，字段名即属性名；日期 `ISO8601`；缺省值用 `null` 不用空串；口令不入结构体 | 连接表单 → `ConnectionStore` |
| 凭据 | 密钥存储条目 | 键 = 连接 id | 系统密钥存储，不落明文 | `Platform/macOS/KeychainSecretStore.swift` |
| 执行记录 | `QueryHistory` | 归档日 / SQL 文本 / 连接 id / 目标库 / 时刻 / 耗时 / 重复次数 | 按天一份；JSON 行；时间 `ISO8601` | 执行路径 → `QueryHistoryStore` |
| 任务定义 | 任务配置件 | 目标库 / 读写模式 / 影响行数上限 / 是否需审批 | JSON；布尔显式写 `true`/`false` | 任务面板 |
| 审批与回执 | `AgentApprovalConsumption` | requestID / fingerprint / 时间 | 追加式 JSON 行，防重放 | `AgentApprovalGate` |

### 4.2 存储契约

| 存储 | 主键 | 约束 | 允许写入方 | 迁移策略 |
|---|---|---|---|---|
| 连接清单文件 | 连接 `id` | 名称同工作区唯一；端口 1…65535；`schemaVersion` 非空 | `ConnectionStore` | `schemaVersion` 升级一次，旧文件先备份再写 |
| 查询历史（本机库） | 自增 | 只本机不上传；上限 500 条 / 90 天先到者为准 | `QueryHistoryStore` | 只增不改 |
| 审批消费记录 | requestID | 追加式，不覆盖；同 fingerprint 只一条 | `AgentApprovalGate` | 只增不改 |
| 笔记库（SQLite） | note id | 本体 / 标签 / 时间线同事务；正文权威源是 span 树 | `NoteLibrary` | 迁移只增不改 |
| 审计日志 | 追加序号 | JSONL 追加，不删不改 | `AgentAudit`、`EgressLog` | 只增不改 |
| IM 通道配置件 `im-channel-qq.json` | 频道（`qq`） | AppID 明文 / 环境（正式 / 沙箱）/ 是否收任务；**Secret 不在本文件** | `AgentIMCredentialStore` | 只改不迁移；老文件缺字段按缺省读 |
| IM 通道凭据 | 钥匙串账户 `agent-im-qq` | Secret 只在此处；写入带 accessible 与只信任本应用的 ACL | `KeychainAgentIMSecretStore` | 按签名记账的一次性重写（读不出来绝不删） |

- 事务边界：一次业务动作一个事务；归档与审计属「动作后置」，失败只报「记录未落盘」，不回滚已成功的业务执行。
- 迁移文件只增不改：`Plugins/Notes/Sources/` 下的迁移脚本与 `Core/` 的 schema 版本号表，历史条目禁止编辑。

### 4.3 算法伪代码

- 对应概设：概要设计 §7.1（查询执行全链）

```text
输入：编辑器文本 T、选区 S、连接 C、目标库 DB、事务模式 M
1  若 C 未连接 → 报 EXEC_NO_CONNECTION 并停
2  Q ← S 非空 ? S : T              # 有选区只跑选区，无选区跑整篇
3  若 Q 为空 → 报 EXEC_EMPTY_SQL 并停
4  D ← ExecutionSafety.check(Q, policy)   # refused → 停；需确认 → 等确认
5  M 为手工事务且未开事务 → beginTransaction
6  for 每条语句 in 按文本顺序切分(Q):
7      上报「第 N 条」→ 执行 → 收 resultSet（全保留）
8      失败 → 报 EXEC_SERVER_ERROR（含序号与原文）→ 停，事务标记未知
9  全部完成 → 汇总行列数与耗时 → 写历史与归档 → 审计一条
```

- 对应概设：概要设计 §7.2（结构变更与高危写）

```text
输入：列定义 L、目标表 TB、脚本种类 K、连接 C
1  issues ← TableDesign.validate(TB, L)；issues 非空 → 停并逐条显示
2  script ← 生成脚本(K, TB, L)        # 不执行
3  展示 script + TB + K；预览未完成 → 停
4  K 为删表/清表 → 要求手输表名；不一致 → 停
5  refusals ← ExecutionSafety.check(script)   # refused → 停
6  执行 → 回执（成功/失败、耗时、错误原文）→ 写执行记录与审计
```

### 4.4 状态覆盖清单

| 状态机 | 当前 → 目标 | 触发 | guard / 抛出 | 测试 ID |
|---|---|---|---|---|
| 连接 | 未连接 → 连接中 | 建立请求且校验通过 | `ConnectionConfig` 校验失败抛 `AppError.invalidConfiguration` | `T-4.4-01` |
| 连接 | 失败 → 已连接 | — | **禁止**跳转，必须先经连接中再握手 | `T-4.4-02` |
| 语句执行 | 待发 → 执行中 | 开始执行 | 空 SQL 被拦（`EXEC_EMPTY_SQL`），不进入执行中 | `T-3.3-03` |
| 语句执行 | 执行中 → 已取消 | 取消请求 | `cancel` 成功且不再收 `resultSet` | `T-4.4-03` |
| 语句执行 | 已取消 → 已完成 | — | **禁止**；重跑是一次新执行 | `T-4.4-04` |
| 审批单 | 已拒绝 → 已批准 | — | `AgentApprovalVerdict` 不可翻 | `T-4.4-05` |
| 审批单 | 已过期 → 已批准 | — | 过期即 `.expired`；按概要设计 §14.1 第 4 条暂定口径 = 拒绝 | `T-4.4-06` |
| 查询页签 | 执行中 → 已关闭 | 关闭请求 | 拒绝并提示「执行中，请先停止」 | `T-4.4-07` |
| 查询页签 | 有未保存改动 → 已关闭 | 关闭请求 | 需确认后进会话快照；保存失败时脏标记不回退 | `T-4.4-08` |

实现口径：`AgentApprovalVerdict` 还有第五档 `.missing`（无记录）。它不是概要设计 §6.3 的四态之一，语义等价于「不能批准」，禁止被当成通过；判定落点见 §3.6。

- 闭集约束：禁止新增未列出的状态或事件；禁止绕过 guard 直接赋值状态；`ConnectionState` / `QueryEvent` / `AgentApprovalVerdict` / `QueryTabState` 四个枚举新增 case 必须先改概要设计 §6。

### 4.5 笔记模块（域契约 = 概要设计 §15）

- `NoteLibrary` 是 actor：库连接只在它内部持有，界面层拿不到连接。
- `NoteDatabase` 负责 SQLite；本体 + 标签 + 时间线**同一事务**写入，失败整笔回滚。
- 正文权威源是 span 树，正文视图是投影；投影与正文不一致时按 span 树重投影，不反向写。
- `NoteAutosave` 合并窗口 1.5 s（比工作区编辑器的 0.12 / 0.45 s 大，自动保存是落盘不是重绘）；三条守卫（许可 / 有内容 / 有改动）缺一不写；`idle` / `pending` / `failed` 三态，`pending` 期间再编辑保持 pending 并重排，不丢新按键；切走时先快照再排队。
- `CloudSyncService` 管同步态，`SyncQueue` 串行单飞；401 ⇒ 续期一次并重放一次，仍失败则降级但保留队列；续期失败不当作登出；登录态与同步态不合并。
- 私密保护与加密边界、回收站与历史版本、待办与日历：落点在 `Plugins/Notes/Sources/`，本仓只做宿主装配与能力位判定，业务判据在笔记分册自跑。

### 4.6 会话与搜索

- `AgentSessionStore`：一会话一文件，文件名即 id；`summaryList(workspace:)` 含跳过文件数（跳过不许静默）。
- 搜索按 `Character` 偏移切分（不按 utf8/utf16，否则中文错位）；命中不重叠；返回 `total` 与 `firstMatchID` 供跳转。
- `AgentChatModel` 只读派生；打开会话要显式切 `sessionID`，不隐式切。
- 命令面板是全产品命令的唯一输入面（`AppCommandCatalog` 为唯一出处），新增命令必须同时登记目录与 `Scripts/check-palette-wiring.py`。

### 4.7 复盘宿主（概要设计 §16 域）

- 本端**只做宿主装配**：`App/Views/RetroHostView.swift` 承载复盘插件的界面槽位；复盘实现本体在独立仓（`retro`），不在本仓。
- 契约口径：概要设计 §16 十八节（行情接入 / 特征 / 回测 / 复盘稿 / 周报）由复盘仓实现；本端只保证宿主侧「插件装配 + 单向上下文 + 数据家隔离」。
- 禁止：把复盘业务逻辑写进 Studio 仓；让复盘插件反向依赖 Studio 装配层；宿主向复盘插件回写其数据家。
- 判据：宿主装配门禁（插件装载 6 组绿）+ `RetroHostView` 可挂载；业务判据在复盘仓自跑（`T-4.7-01` 标「他仓」）。

### 4.8 工作区编辑器与外部改动（概要设计 §7.3）

- 脏标记唯一来源：编辑器缓冲与上次落盘内容的比对；`isDirty` 只在保存成功后清零。
- 保存：有路径直接写回；无路径走系统保存面板；保存失败不得清脏标记、不得关闭页签。
- 外部改动：监听磁盘变更 → 提示「磁盘上已变」→ 二选一（重新载入 / 保留本地）；禁止静默覆盖任何一侧。
- 监听的落法（2026-10-28）：`App/WorkspaceFileWatcher`（`FSEventStream` 挂工作区根，`FileEvents`，防抖 180ms 合成一批）→ `AppState.handleDiskChanges` → `WorkspaceStore.reloadDirectories(forChangedPaths:)` **只重列被改目录**（判定在 `Core/WorkspaceChangeScope`：根内 / 父目录已展开 / 忽略 `.git`·`.build`·`node_modules`·`dist` / 同目录合一；9 例判据）。**不许**调 `refresh()`（它走 `adopt`，会清 `expandedPaths` 把树整棵塌掉）。换工作区时 `startWorkspaceWatching` 认根并重挂。
- 编码与换行：识别结果必须显示在状态行；禁止把猜测结果写回文件而不告知。
- 撤销粒度合并窗口：0.12 s（输入）/ 0.45 s（结构输入），两档都写在编辑器状态机里，不在视图层各写一份。

---

## 5. 界面实现

### 5.1 视图与组件落点

| 概设视图（§8.2） | 本端视图/组件 | 依赖接口 | 备注 |
|---|---|---|---|
| 查询页签 | `App/Views/CodeEditorView.swift` + `ResultTableView.swift` | 概要设计 §4.3 / §4.4 | 执行/停止按钮状态互换 |
| 结果区 | `App/Views/ResultTableView.swift` | 概要设计 §4.3 / §4.8 | 多结果集切换器、导出入口 |
| 连接表单 | `App/Views/ConnectionFormView.swift` | 概要设计 §4.1 | 类型切换联动默认端口与 SSL |
| 连接清单 | `App/Views/ConnectionListView.swift` | 概要设计 §4.1 / §4.2 | 删除二次确认并明说连带删凭据 |
| 对象树 | `App/Views/ObjectTreeView.swift` + `BrowseRowsSheet.swift` | 概要设计 §4.5 / §4.6 | 刷新不清选中 |
| 表设计 | `App/Views/TableDesignSheet.swift` | 概要设计 §4.7 | 预览与执行是两个动作 |
| 导入导出 | `App/Views/ImportPanel.swift` + `BackupRestoreSheet.swift` | 概要设计 §4.8 | 部分失败列明细 |
| 会话视图 | `App/Views/SessionPanel.swift` + `AgentAuditPanel.swift` | 概要设计 §4.9 | 四项读数 + 确认终止 |
| 对话页签 | `App/Views/AgentChatView.swift` | 概要设计 §4.10 / §4.3 | 工具卡片可展开 |
| 审批 | `App/Views/AgentApprovalSheet.swift` | 概要设计 §5.4 | 逐条列语句与目标库 |
| 浏览页签 | `App/Views/BrowserTabView.swift` | 概要设计 §3.1 | 与文件页签同类，可 ⌘W |
| 命令面板 | `App/Views/CommandPaletteView.swift` | 命令目录 | 全局搜索唯一输入面 |

- 视图清单外的入口一律不得新增：`Scripts/check-palette-wiring.py` 的「未登记差集」必须为 0。

### 5.2 状态来源与刷新

- 视图状态从 `AppState`（`@MainActor`）单向派生；视图不缓存可写副本。
- 刷新路径：能力层事件 → 装配层折叠值 → 主线程更新；禁止视图轮询、禁止双写。
- 派生值（行数、耗时、可编辑判定）只在装配层算一次，视图只读。

### 5.3 组件级六态契约

> 六态 = 加载中 / 空数据 / 错误 / 权限不足 / 提交中 / 部分失败。每个组件六行齐；「禁止渲染」列逐行给出必须为空的渲染结果，任一行留空即判缺陷（`UI-5.3-01`）。

#### 5.3.1 查询页签 `QueryTabView`

- 对应概设条款：概要设计 §8.4 / §8.5 / §8.7
- 输入（Props）：`tabID`、`connectionID?`、`database?`、`sql`、`isReadOnly`
- 内部状态：`isExecuting`、`results`、`selectedResultIndex`、`errorMessage`、`statusMessage`、`isSaving`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isExecuting == true` | 执行按钮换停止 + 逐条进度 | 空白结果区；允许重复点执行 |
| 空数据 | `results.isEmpty && !isExecuting && errorMessage == nil` | 空态文案 + 「执行当前 SQL」引导 | 错误件；无说明的空白页 |
| 错误 | `errorMessage != nil` | 错误件（原因 + 语句序号 + 位置）+ 重试入口 | 静默失败；空结果冒充成功 |
| 权限不足 | `ExecutionSafety.Decision.refused` | 只读原因 + 涉事语句 | 灰色「仍然执行」入口；先渲染再报错 |
| 提交中 | `isSaving == true` | 按钮进行中态 + 禁用 | 重复发起第二次保存 |
| 部分失败 | 多语句汇总含失败条 | 逐条列成功/失败 + 行数 | 整体报成功；丢失败条 |

- 副作用：执行成功写历史与审计；取消写「已取消」结局；关闭页签走 §4.4 页签 guard。
- 禁止行为：失败后清空编辑器；只改界面状态冒充取消；把多结果集折叠成一个。

#### 5.3.2 连接表单 `ConnectionFormView`

- 对应概设条款：概要设计 §8.4 / §8.6
- 输入：`mode`（新建 / 编辑）、`ConnectionConfig?`、`databases`（已接入类型）
- 内部状态：`draft`、`fieldErrors`、`isSubmitting`、`testResult`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isTesting == true` | 试探连接进度 + 表单禁用 | 无反馈地卡住按钮 |
| 空数据 | `databases.isEmpty` | 「无可用类型」+ 引导 | 空下拉可提交 |
| 错误 | `fieldErrors` 非空或 `testError` | 字段下方错误 + 原因原话 | 只弹全局提示 |
| 权限不足 | 授权能力位缺失 | 明说缺哪个能力位与怎么给 | 先展示表单再报错 |
| 提交中 | `isSubmitting == true` | 提交按钮进行中态 + 禁用 | 重复提交产生两条连接 |
| 部分失败 | 校验通过但试探连接失败 | 保存结果与试探结论分开列 | 试探失败却把配置标成已就绪 |

- 副作用：保存成功刷新清单并保持选中；试探连接不写盘。
- 禁止行为：明文口令回显；端口越界静默夹取；类型切换不联动默认 SSL。

#### 5.3.3 连接清单 `ConnectionListView`

- 对应概设条款：概要设计 §8.4 / §8.7
- 输入：`ConnectionConfig` 数组、选中 id
- 内部状态：`pendingDelete`、`isDeleting`、`errorMessage`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isLoading == true` | 列表骨架 + 禁用删除 | 空白列表冒充无连接 |
| 空数据 | `connections.isEmpty` | 空态文案 + 「新建连接」 | 错误件 |
| 错误 | `errorMessage != nil` | 原因 + 重试 | 空列表冒充成功 |
| 权限不足 | 无授权能力位 | 入口不出现 | 灰色条目诱导点击 |
| 提交中 | `isDeleting == true` | 该行进行中态 + 全局禁用重复删 | 重复发删除请求 |
| 部分失败 | 删除成功但凭据清理失败 | 明说残留位置 | 报整体成功 |

- 副作用：删除连带清凭据；执行中的连接不允许删除。
- 禁止行为：无确认删除；只删列表项留凭据；删除后自动切到别的连接执行。

#### 5.3.4 对象树 `ObjectTreeView`

- 对应概设条款：概要设计 §4.5 / §8.4
- 输入：连接 id、根节点、选中节点 id
- 内部状态：`expanded`、`childrenCache`、`loadingNodes`、`metaError`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `loadingNodes` 含该节点 | 该节点加载指示 | 伪造占位子节点 |
| 空数据 | 该节点子数组为空 | 「该层无对象」 | 空白无说明 |
| 错误 | `metaError` 对该节点置位 | 节点级错误 + 重试 | 空树冒充无对象 |
| 权限不足 | `META_UNSUPPORTED` 或权限缺失 | 层级差异说明 | 抹平层级强行展示 |
| 提交中 | 刷新请求进行中 | 刷新按钮进行中态 | 重复刷新叠请求 |
| 部分失败 | 部分子节点取数失败 | 成功子节点照常 + 失败提示 | 整树清空 |

- 副作用：刷新不清选中；展开请求按 `ObjectTreeRefreshGate` 合并。
- 禁止行为：跨类型统一层级；刷新清空选择；在树里塞未授权入口。

#### 5.3.5 审批单 `AgentApprovalSheet`

- 对应概设条款：概要设计 §5.4 / §6.3 / §8.4
- 输入：`AgentApprovalRequest`、语句清单、目标库、预估读数
- 内部状态：`verdict`、`isSubmitting`、`estimate`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 预估读数计算中 | 「预估计算中」占位 | 编造一个行数 |
| 空数据 | 语句清单为空 | 「无待审语句」并禁用批准 | 空白批准按钮 |
| 错误 | `verdict == .expired` / `.missing` | 终局说明 + 关闭 | 把过期当待审 |
| 权限不足 | 任务只读或能力位缺失 | 只读原因 + 禁止批准 | 灰掉批准但可点 |
| 提交中 | `isSubmitting == true` | 批准按钮进行中态 + 禁用 | 重复批准产生两条消费记录 |
| 部分失败 | 多语句中部分语句被 `refused` | 逐条列被拒语句 | 整单批准成功 |

- 副作用：批准按次消费（`grant`）；拒绝与过期留痕。
- 禁止行为：把 `.pending` / `.denied` / `.expired` / `.missing` 当通过；回执写口令或敏感字面量；预估取不到时编数（取不到写「未接」）。

#### 5.3.6 导入导出面板 `ImportPanel`

- 对应概设条款：概要设计 §4.8 / §8.4
- 输入：来源（结果集 / 表 / 库）、格式集合、目标路径
- 内部状态：`phase`、`writtenRows`、`failedItems`、`targetExistsPrompt`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `phase == .running` | 已写行数 + 进度 | 无反馈的空白进度条 |
| 空数据 | 来源为空 | 「无数据可导出」 | 生成空文件并报成功 |
| 错误 | `phase == .failed` | 原因 + 重试 | 失败留半成品不说 |
| 权限不足 | 目标路径无写权限 | 明说缺哪个目录授权 | 静默改写到别处 |
| 提交中 | 导入覆盖确认未答 | 询问对话框 + 按钮禁用 | 直接覆盖既有表 |
| 部分失败 | `failedItems` 非空 | 成功项与失败项分别列出 | 整体回滚却不告知 |

- 副作用：导出流式写文件；导入逐批成事务。
- 禁止行为：把整表读进内存再写；导出夹带凭据；失败后静默删数据。

#### 5.3.7 浏览页签 `BrowserTabView`

- 对应概设条款：概要设计 §3.1 / §8.4
- 输入：`tabID`、`initialURL?`
- 内部状态：`url`、`canGoBack`、`canGoForward`、`isLoading`、`loadError`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isLoading == true` | 进度指示 + 刷新按钮换停止 | 白屏无反馈 |
| 空数据 | `url == nil` | 地址栏 + 起始页 | 空白页冒充已加载 |
| 错误 | `loadError != nil` | 错误页（URL + 原因）+ 重试 | 空白页冒充 200 |
| 权限不足 | 目录授权或网络策略拒绝 | 明说缺哪个授权 | 静默拦请求 |
| 提交中 | 表单提交中（页面内） | 保持页面可交互并显示进行中 | 重复提交 |
| 部分失败 | 页面资源部分加载失败 | 已加载内容 + 失败资源提示 | 整页清空 |

- 副作用：导航历史进页签模型；关闭走页签 guard（执行中页签无此态）。
- 禁止行为：把浏览页签并入 SQL 工作区；跨页签共享登录态以外的用户数据；预览侧改写源文件。

#### 5.3.8 Agent 对话页签 `AgentChatView`

- 对应概设条款：概要设计 §4.10（助理上下文传递）/ §8.4（界面状态契约）/ §15（笔记侧 Markdown 单一口径）
- 输入（Props）：`sessionID`、`readOnly`（会话已归档时为真）
- 内部状态：`messages`、`streamingText`、`isRunning`、`pendingApproval`、`errorMessage`
- **正文渲染（本节新增，2026-10-25 实机缺陷补齐）**：消息正文必须**渲染成富文本**，不许把 Markdown 源码直出。
  - 解析层**只许复用** `Core` 的 Markdown 解析（`MarkdownDocument`，判据 `Scripts/check-markdown-single-source.py`）；**禁止**在 `AgentChatView` 里自写第二套行内/块级解析。
  - 必须渲染：代码块（含语言标注与等宽底色）、有序/无序列表、任务列表勾选状态、引用块、表格、行内强调（粗体/斜体/行内代码/链接）。
  - 流式未闭合（如围栏 ```` ``` ```` 只出现一半）⇒ **原文照发、不做猜测性渲染**；收尾后按完整文档重排，不许在中途抖动整块高度。
  - 复制按钮复制的是**源码文本**，不是渲染后的可见文本（用户要拿去粘回终端）。
  - 工具卡片（tool call / 结果）与正文分开渲染，不参与 Markdown 解析。

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `isRunning && streamingText.isEmpty` | 逐字追加的占位行 + 停止入口 | 空白气泡；重复发出同一请求 |
| 空数据 | `messages.isEmpty && !isRunning` | 空态引导（一句话 + 示例提问） | 错误件；无说明的空白页 |
| 错误 | `errorMessage != nil` | 错误件（原因 + 可重试入口）+ 已产生的部分消息照常显示 | 清空历史冒充「没发生过」；把网络错误渲染成模型回答 |
| 权限不足 | `pendingApproval != nil` 或 `readOnly` | 审批卡（逐条语句与目标库）+ 输入框禁用 | 灰色「仍然发送」；先发后问 |
| 提交中 | `isRunning` | 发送按钮换停止 + 队列提示 | 重复入队同一句话；静默丢弃 |
| 部分失败 | 工具调用中部分成功 | 逐条标成功/失败 + 失败原因 | 整轮报失败；丢失败条目 |

- 副作用：一轮结束写会话留痕（不含审批正文）；停止按钮经 `§3.13` 定向到本次执行。
- 禁止行为：把 Markdown 源码当正文直接 `Text(...)` 显示；自写第二套 Markdown 解析；流式中途重排导致滚动跳位。

##### 5.3.8.1 版式语汇（对照 Hermes TUI 的两张基准图，逐项照抄）

> **跨端出处**：语汇 / 骨架 / 开关 / 主题四层的**唯一权威在《Doyah产品概要设计说明书》§8.11**；本节只做「映射到本端落点」，不得重新定义语汇。
>
> **参考基准登记（比对面 = 以下四项，缺一项就算没参考）**
> ① 启动界面截图：`~/Desktop/Hermes-startup.png` ② 工作界面截图：`~/Desktop/Hermes-GUI.png`
> ③ 实现骨架源码（TUI 侧）：`ui-tui/src/components/appLayout.tsx`（主骨架）· `appChrome.tsx`（`statusBarSegments(cols)`）· `theme.ts`（30+ 配色键）· `blockLayout.test.ts`（行数分配）
> ④ 行为开关：`config.yaml` 的 `display:` 段；配色/品牌/符号：皮肤引擎 `hermes_cli/skin_engine.py` + `~/.hermes/skins/<名>.yaml`
>
> 纪律：以后改这一节，先重新看这四项再动笔；只凭文字描述改版式 = 返工。

> 基准：启动界面 = 桌面 `Hermes-startup.png`；工作界面 = 桌面 `Hermes-GUI.png`。两张图是**唯一比对面**，不是「风格参考」。以下每题都写成可核项。

**① 一个字号**：正文、工具行、状态行、输入行**同一字号**（`Theme.font(.body)` 同档），层级只靠颜色与字形，**不许**把工具行/状态行缩小一号。判据：`grep -c 'Theme.font(.caption)'` 在本视图内为 0（除表头与 `⌘` 提示）。

**② 行首栏（固定两字符列宽，等宽字形，不用 SF Symbol）**

| 位置 | 字形 | 含义 |
|---|---|---|
| 用户消息 | `>` | 人说的一句 |
| 助手正文 | （无字形，顶格） | 模型回答 |
| 工具块折叠头 | `└─ ▼` / `└─ ▶` | 一组工具调用，可折叠 |
| 工具条目 | `├─ ⏺`（末条 `└─ ⏺`） | 单次调用 |
| 提示/警告 | `▼` / `⚠` | 启动界面里的分节头与告警 |

工具条目一行内四段：`⏺ <工具名>("<参数摘要>") (<耗时>s)`；参数摘要超 60 字截断加 `…`。**耗时必须写**（对照图里每条都带 `(0.5s)`）。

**③ 边框只给「要人动手」的卡**：终端语汇里**没有通栏底纹、没有通栏卡片**。
- 允许描边：审批卡（等用户点）、发起界面里的信息面（启动图中间那一圈细边框，**棕色 1pt**，圆角 `Radius.badge`）。
- 禁止：给每条助手消息加卡片/底纹；用分隔横线（`---`，`Spacing.m` 上下留白、`Metrics.hairline` 细线）代替卡片。

**④ 状态行（底部，字段顺序固定，`|` 分隔，右端对齐工作目录/会话名）**

```
— ready | <模型名> | <上下文已用>/<窗口> | [████░░] <百分比> | ⊙ <缓存命中> | ↑ <t/s> | voice off      — <会话标题>
```
- 无读数时**整段不出现**（不写 `0`、不写 `n/a`）；运行中把 `ready` 换成 `( •_•)>◉─ computing…` 并附已跑时长。
- 花费**不在状态行**（2026-10-25 令：成本只看 token）。

**⑤ 输入行**：`>` 提示符 + 等宽输入框；右侧动作控件一律等宽字形（`⏎` 发送 / `■` 停止 / `▶` 继续 / `⏱` 定时），**不用 SF Symbol**；运行中在输入框下常驻一行灰字 `⏎rl+C to interrupt…` 的等价提示（本端为 `⌘.` 中断）。

**⑥ 启动界面（空会话 / 首启）**：自上而下五块，块间距 `Spacing.l`：
1. 品牌块：大号等宽艺术字（`HERMES-AGENT` 等价物 = 本产品名）+ 一行暗色副题；不出现 logo 位图。
2. 信息面（唯一允许描边的块）：左侧三行（模型 · 品牌 / 数据目录 / `Session: <id 前 8 位>`），右侧三组折叠头（`▼ 可用工具` / `▼ 可用技能 (N)` / `▼ MCP 服务器 (N)`），底部一行汇总 `N tools · N skills · /help for commands`，右上角版本号。
3. 空态引导一句话（灰色）。
4. 状态行（同 ④）。
5. 输入行（同 ⑤）。

**⑦ 颜色分配（只用令牌，不写字面色）**：强调 = `Theme.text(.bright)` 或 `Theme.status(.warning)` 档（对照图里的金/琥珀是强调色家族）；次要 = `Theme.text(.secondary)`；正文 = `Theme.text(.primary)`；链接 = 强调色 + 下划线。**禁止**仅靠颜色传达状态（`NFR-ALL-GATE-UI-001`）。

**⑧ 尺寸取令牌**：行高 `Metrics.listRowHeight`（20）· 工具块缩进 `Metrics.listIndent`（14）· 块间距 `Spacing.s/m/l` · 圆角 `Radius.badge/control`。**禁止**在视图里写裸数字（判据 `Scripts/check-design-tokens.py`）。

**⑨ 不许出现的东西**（对照图里没有的，本端也不许有）：通栏卡片、气泡尾巴、头像圆点、工具栏按钮文字、二级标题用更大字号、同一条信息画两遍（行内一句 + 下面卡片一次）。

##### 5.3.8.2 渲染骨架与可配置项（对照 Hermes TUI 的实现骨架）

> 参考来源（人类主人 2026-10-25 给出的实现骨架）：`ui-tui/src/components/appLayout.tsx`（主骨架）· `appChrome.tsx`（顶栏/状态栏分段，`statusBarSegments(cols)` 决定显示哪些段）· `theme.ts`（30+ 配色键 → 皮肤色值）· `blockLayout.test.ts`（消息块**行数分配算法**）；行为开关在 `config.yaml` 的 `display:` 段；配色/品牌/符号在皮肤系统（9 套内置 + `~/.hermes/skins/<名>.yaml`，合并规则见下）。

**① 三个骨架部件 ↔ 本端落点（骨架是代码，不是配置）**

| 职责 | TUI 侧 | 本端落点 | 契约 |
|---|---|---|---|
| 滚动正文 | `TranscriptPane` | `AgentChatView` 的 `ScrollView` + `LazyVStack` | 只在这一处滚；工具块折展不重排整列 |
| 输入框 | `PromptPrefix` + `composer` | `AgentChatView` 的输入行（`>` 前缀） | 输入行**永不随正文滚动** |
| 状态栏分段 | `statusBarSegments(cols)` | `AgentChatView.statusBar`（纯函数 `segments(width:)`） | **按宽度决定显示哪些段**：宽度不足时从右往左丢段（丢缓存率 → 丢 t/s → 丢 token 用量），**永不丢模型名与 ready/computing** |
| 行数分配 | `blockLayout` 算法 | `AgentBlockLayout.rows(for:width:)`（纯函数，可单测） | 同一块在窄/宽两档的**折叠行数**由它算，视图不自己数行 |

`blockLayout` 必须抽成**纯函数**并单测（窄 40 列 / 宽 120 列两档，断言折叠头行数与截断字符数），否则「窄屏挤成两行」这类走样只能靠肉眼抓。

**② 行为开关（等价物 = 本端 `ui.agent.*` 偏好，可在设置里改，不改代码）**

| 键 | 默认 | 影响 | 判据 |
|---|---|---|---|
| `streaming` | `true` | 逐字追加 vs 收齐再显示 | 关掉时首字延迟 = 整轮耗时 |
| `compact` | `false` | 紧凑模式：工具块默认折叠、块间距 `Spacing.hair` | 切换后同一屏幕可见消息数增加 |
| `show_reasoning` | `false` | 是否显示思考段（灰字缩进） | 关掉时思考段**零占位**（不留空行） |
| `timestamps` | `false` | 每条消息前加 `HH:mm` | 关掉时行首栏宽度不变（不抖动） |
| `show_cost` | **`false`（2026-10-25 令：固定关，不设开关）** | 花费——已从界面撤除 | `grep 'estimatedCost'` 在 App/ 视图面 0 处 |
| `tool_progress` | `all` | `all` / `summary` / `off` 三档 | `summary` 只显示折叠头 + 条数；`off` 只剩「调用 N 次」一行 |
| `status_indicator` | `kaomoji` | `kaomoji` / `unicode` / `ascii` 三档字形 | 三档都能表示 computing / ready / error 三态 |
| `user_message_preview` | `首2末2` | 长用户消息折成「前 2 行 … 后 2 行」 | 折叠处有 `…` 且可点开全文 |
| `runtime_footer` | `false` | 底栏附加 模型 / 上下文百分比 / 工作目录 | 关掉时状态行少这三段，其余不动 |
| `busy_input_mode` | `interrupt` | 运行中提交 = 打断 vs 排队 | `interrupt` 时先停后发（与 §5.3.8 提交中一列一致） |

**③ 配色 / 品牌 / 符号 = 主题集（唯一可自由配置的一层）**

- 本端等价物 = `Core/DesignTheme.swift` 的 5 套主题（tech-blue / bean-green / rose-gold / stardust / deep-space）+ `Core/DesignTokens.swift` 的角色表；**不许**在视图里写字面色（判据 `check-design-tokens.py`）。
- TUI 的 30+ 键按**角色**归并到本端令牌（`Surface` / `TextTone` / `StatusTone` / `SyntaxTone`），**不 1:1 照搬键名** —— 键名进了视图就会长成两套口径。
- **合并规则的坑（照抄，免得返工）**：TUI 的 `colors` / `spinner` / `branding` 在 `default` 之上**逐键合并**（只写想改的）；而 `light_colors` / `dark_colors` **不合并** —— 留空 = 该皮肤没有手调明暗变体，由引擎自动适配。本端对应实现：主题值表按「角色 × 明暗」两列给值，**缺失的明暗变体必须回落推导值并登记**（不许静默落成同一色，那就等于没有明暗两套）。
- 品牌与符号：`tool_prefix` 等价物 = 行首栏字形表（见 §5.3.8.1 ②）；`branding.name/icon/prompt/welcome` = 启动界面 §5.3.8.1 ⑥ 的品牌块与提示符；这些**进主题表、不进视图代码**。

##### 5.3.8.4 对话区「谁在说话」配色（`Theme.ChatSpeaker`）

**一条规矩**：一屏最多**三种有彩色** —— 金 = 人、蓝 = 机器动作、紫 = 等你拍板；其余全中性。
成功/失败只出现在徽章与按钮上，**从不染正文**（否则满屏都在喊，金黄就不显眼了）。

| 角色 | 枚举值 | 深色 | 浅色 | 用在哪 | 不用于 |
|---|---|---|---|---|---|
| 用户 | `.user` | `#FFC740` | `#8A5E00` | 用户整行正文 + 行首 `>` | 提醒条、告警 |
| 助手正文 | `.assistant` | `#E6EDF2` | `#1B2733` | Markdown 正文（三段渲染路径同一色） | 任何强调 |
| 命令/参数 | `.command` | `#7AB0FA` | `#1C63C4` | 工具卡的 `name(args)`、展开后的参数 | 结果正文 |
| 系统/时间线 | `.notice` | `#8FA3B0` | `#5B6B78` | notice、`▼` 事件行 | 报错原因（走警告色） |
| 思考段 | `.thinking` | `#6E8B9A` | `#7A8A96` | 思考标题 + 正文、行首 `·` | 正文 |
| 待批 | `.pending` | `#A78BFA` | `#5B3FB5` | 待批卡描边、`⚠` 字形、「待你决定」徽章 | **批准/拒绝按钮** |

**批准 = 绿、拒绝 = 红**（`Theme.status(.success/.danger)`）：紫只标「这件事在等你」，不兼职动作色。
这是主人 2026-10-31 看图后的原话：「待我批准用紫色没问题，但是批准是绿色，拒绝应该是红色」。

**为什么待批不用琥珀**：琥珀与用户的黄金色相太近（同一屏里两种暖黄 = 分不清「我说的」和「等我点头的」）。
改紫之后金/蓝/紫三色相彼此远离，一眼可辨。

**实现约束**：
- hex 只允许出现在 `App/AppTheme.swift` 的 `ChatSpeaker.hex(dark:)` 一张表里；视图写 `Theme.chat(.role, colorScheme)`，**不许写裸色**。
- 与「哪套主题」解耦是有意的：这表达「谁在说话」，不是「当前什么配色」；深浅两档同色相、只压明度。
- `ToolbarIcon` / `ToolbarIconButton` 的 `tint` 为可选项（默认 `nil` = 既有观感），只给语义动作（批准/拒绝）用。

##### 5.3.8.3 皮肤与品牌值表（TUI 皮肤 YAML 字段 → 本端主题表）

**字段对照（写全，缺一个就会「改了不生效」）**

| TUI 皮肤字段 | 含义 | 本端落点 | 口径 |
|---|---|---|---|
| `colors.*`（`banner_border` / `banner_title` / `ui_accent` / `ui_ok` / `prompt` / `status_bar_bg` 等 30+ 键） | 各角色色值 | `Core/DesignTheme.swift` 每个主题一份 `palette`，按 `Surface` / `TextTone` / `StatusTone` / `AccentFamily` 角色取值 | **按角色归并，不 1:1 搬键名** |
| `light_colors` / `dark_colors` | 手调明暗变体 | 主题值表的 `light` / `dark` 两列 | **不合并**：缺失的变体必须回落推导值并在值表里登记理由（静默落成同一色 = 没有明暗两套） |
| `spinner` | 加载动画字形 | `status_indicator` 三档 + `busy` 字形（`kaomoji` / `unicode` / `ascii`） | 三档都要能表达 computing / ready / error |
| `branding.{name,icon,prompt,welcome,goodbye,tool,help_header}` | 品牌与提示语 | 启动界面品牌块、输入行提示符 `>`、欢迎/告别文案（走语言表） | 文案**只从语言表取**，不写在视图里 |
| `tool_prefix`（如 `┊`） | 工具行行首字形 | 行首栏字形表（§5.3.8.1 ②：`└─ ▼` / `├─ ⏺`） | 字形常量集中在 `AgentGlyphs`，视图不散写 |
| `tool_emojis` | 工具图标 | 本端不用 emoji（终端语汇里 emoji 破坏等宽列） | 只用等宽字形；判据：本视图内 emoji 0 处 |
| `banner_logo` / `banner_hero` | 大图 / 艺术字 | 启动界面品牌块（等宽艺术字） | 用文本字形，不用位图 |
| `customCSS`（上限 32KB） | 注入样式 | **本端不提供** | 理由：原生渲染无 CSS；等价能力 = 主题值表 + 令牌，且必须过对比度门槛（`Scripts/check-theme-set.py` 的 310 条） |

**皮肤清单与覆盖度**

- TUI 侧内置 **9 套**（`default` / `ares` / `mono` / `slate` / `daylight` / `warm-lightmode` / `poseidon` / `sisyphus` / `charizard`），自定义放 `~/.hermes/skins/<名>.yaml`。
- 本端**不照搬 9 套**：主题集是 5 套（tech-blue / bean-green / rose-gold / stardust / deep-space，见 `Docs/design/外观方案-v1.md`），每套必须给全「角色 × 明暗」两列值并过对比度门槛 —— 这是本端比 TUI 严的一条（TUI 允许某皮肤没有手调明暗变体，本端不允许缺值不登记）。
- 存放与切换：TUI = 用户自建 YAML；本端 = 主题选择持久化在 `ui.designTheme`，**不开放用户自带皮肤包**（理由：值表要过 100 角色 / 310 条门槛的独立复算，外部 YAML 无法保证；新增一套主题走代码 + 值表 + 判据三处同改）。

**合并规则的两条坑（都照抄进本端）**

1. `colors` / `spinner` / `branding` 在 `default` 之上**逐键合并** ⇒ 本端主题值表也按「只写覆盖项、其余继承基准主题」实现，别要求每套主题写满 100 个角色。
2. `light_colors` / `dark_colors` **不合并** ⇒ 本端对应实现是「明暗两列独立求值 + 缺值必须登记」，**不许**用「合并成一套」偷懒（那会让深色主题在浅色档里失真）。

### 5.3.9 浮层（paper）版式语汇

本端有三类「压在内容之上的层」，**口径唯一，各视图不得各自发挥**：

| 类型 | 用在哪 | 衬底 | 外形 | 备注 |
|---|---|---|---|---|
| 浮层 paper | 笔记本架、期次浮层、行内悬停菜单 | `.thickMaterial`（≈95% 不透，随明暗自适应） | `Radius.card` 圆角 + 阴影 `black 0.28 / r12 / y2` | **不得用系统控件底色**（暗色下会是死黑），**不得只用半透明 surface**（壁纸透上来字发糊） |
| 面板 panel | 结果面板、审批单 | `Theme.surface(.panel)` | 1pt 描边 `Theme.hairline` | 与内容同层，不浮起，无阴影 |
| 对话框 sheet | 设置、确认框 | 系统 sheet | 系统 | 只放系统控件，不套本端语汇 |

**四条硬纪律**：

1. **压住内容的层必须不透明**：凡是浮在壁纸之上的层，衬底不透明度 ≥ 0.9；半透明只允许出现在**不承载文字**的装饰层。
2. **不透明不等于纯色黑**：浮层衬底**一律 `Theme.paper(_:)`** —— 它取主题面板色的**不透明**取值，随明暗主题各自求值。
   **禁止在浮层上调用 `Theme.surface(_:)`**：壁纸皮肤（如「深空苍穹」）下它按值表**故意半透明**，
   照片从内容层与浮层两层透上来，文字必糊；也**禁止**改用 `.thickMaterial` / 系统控件底色
   （暗色主题下偏黑，且与主题配色不同源）。2026-10-25 实机连撞三次（半透明 → 系统控件色死黑 → thickMaterial 偏黑）才定位到这一层。
3. **浮层不参与布局**：挂 `.overlay`，不得进 `HStack`/`VStack` 的尺寸协商 —— 浮出与收起时内容区宽度逐点相同。
4. **入口悬停出、离开收**：行内与分组标题上的动作（`＋` / `…`）常驻不占位，鼠标进入时才浮出；同一条动作**只画一次**，工具条与行内不得并存两份。

### 5.3.10 根视图分栏骨架（自绘，不用 `NavigationSplitView`）

**为什么自绘**：macOS 会给 `NavigationSplitView` 的 sidebar 列套一层 `NSVisualEffectView`（模糊材质），`NSVisualEffectView.Material` **没有 `.clear` 取值**（实测编译失败），SwiftUI 也没有任何公开 API 关掉它 ⇒ 壁纸透不上来；自铺壁纸又会变成「每列各贴一张、接缝对不上」。结论：**侧栏只提供拖宽 / 折叠 / 记忆三件事，自绘更可控**。

**骨架（`MainWindow.body`）**

```
HStack(spacing: 0) {
    ActivityBarView()                      // 应用级 chrome，不随侧栏动
    if isSidebarVisible {
        sidebarContent.frame(width: sidebarWidth)
        SidebarResizeDivider(width: $sidebarWidth)   // 1pt 发丝线 + Spacing.xs 热区 + 左右箭头光标
    }
    Group { …各活动项主视图… }.frame(maxWidth: .infinity, maxHeight: .infinity)
}
.background(WallpaperBackground())         // 壁纸只铺一次（窗口根部）
```

**五条落点纪律**

| # | 纪律 | 理由（都踩过） |
|---|---|---|
| 1 | 壁纸**只**在窗口根部铺一次，任何列/面板不得再铺 | 再铺一份就变成“每列各贴一张”，缩放与裁剪对不上，接缝可见 |
| 2 | `Group` **不传递尺寸**，必须显式 `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 少了它，内容列 x 原点算错，浮动书架被挤到活动栏与导航栏之间 |
| 3 | **侧栏可见性由活动项派生**（`item != .notes && item != .retro`），不得交给容器代管 | 笔记/周报的导航在各自内容区内部（浮动书架 / 期次左栏），外层侧栏再画一次就是“同一份导航画两遍” |
| 4 | 折叠按钮挂 **`.toolbar { ToolbarItem(placement: .primaryAction) }`**（标题栏最右端） | 系统那枚随 `NavigationSplitView` 一并消失；放在 `.navigation` 会挤在标题前、又小又不显眼 |
| 5 | 侧栏宽度单点 = `Metrics.sidebarWidth` / `Metrics.sidebarMaxWidth`，拖拽写回偏好 | 裸值散在视图里就没有旋钮（`check-design-tokens` 也会判红） |

**产品形象（`BrandMark`）**：应用图标一律取 `NSApp.applicationIconImage`（与 Dock / 关于本应用同一份），**不另存图片资源** —— 换图标只改一处。落点：工作区首页品牌段（44pt）、Agent 欢迎页品牌块（36pt，与艺术字并排）、**「版本与许可证」页头部品牌块（56pt 图标 + 右侧四行：产品名 → 版权 → 版本 → 开发者；`AboutLicenseSheet.header`）**。关于页那四行的文案取自语言表 `appCopyright`（中文 `© 2026 豆丫科技` / 英文 `© 2026 Doyah Tech`，各叫各的名字）、`licAboutAppVersion`、`licAboutDeveloper`（标签「开发者 / Developer」，**不用 Owner**）与 `appCopyrightHolder`（值：中文「豆丫科技」/ 英文「Doyah Tech」）；版式改动只许改这一处，不得在别处再拼一份关于页。

**图标按钮的适用面**：活动栏、工具条、行内悬停操作可用图标；**对话框、表单、确认框一律用系统文字按钮**（`Button(…)` + `.bordered` / `.borderedProminent`），主界面第一面之外不得以图标代按钮。

### 5.4 状态与数据流

- 单一数据源：页签模型在 `AppState.tabs`；结果集在页签对象内；视图不持有可写副本。
- 派生：行数、耗时、可编辑判定、预估读数由装配层算出后单向下发；视图不得自行重算。
- 缓存失效：对象树按「连接 + 库」缓存，连接断开或结构变更成功后整体失效；不设基于时间的过期。
- 跨页签共享：同一「连接 + 库」共享一个 `DatabaseService`（`AppState.ensureService`）；事务状态挂在该服务上，页签不得各自开事务。

### 5.5 事件绑定与动作映射

| 界面动作 | 调用接口 | 成功行为 | 失败行为 | 禁止行为 |
|---|---|---|---|---|
| 点执行 | `execute`（§3.3） | 逐条上报 + 渲染 + 写历史 | 错误件 + 保留 SQL | 失败后清空编辑器 |
| 点停止 | `cancel`（§3.4） | 状态已取消、连接可用 | 明说服务端拒绝原话 | 只改界面状态 |
| 保存连接 | `ConnectionStore.save`（§3.2） | 清单刷新 + 选中保持 | 字段级错误 | 静默丢配置 |
| 删除连接 | `ConnectionStore.save` + 凭据清理 | 条目消失 + 清理项清单 | 明说残留位置 | 无确认删除 |
| 展开节点 | `loadChildren`（§3.7） | 渲染层级 | 节点级错误 + 重试 | 显示空树冒充无对象 |
| 行写回 | `applyRowEdits`（§3.9） | 逐行结局 | 冲突行明示 + 保留输入 | 影响 0 行当成功 |
| 生成脚本 | `TableDesign.validate` + 预览 | 展示脚本 + 待确认 | 明说缺什么 | 直接执行 |
| 导出 | `ResultExporter`（§3.11） | 进度 + 完成 + 文件大小 | 部分成功列明细 | 失败留半成品不说 |
| 终止会话 | `SessionMonitor` + 确认（§3.13） | 结局 + 刷新列表 | 权限原话 | 无确认终止 |
| 投递上下文 | `AgentContext.assemble`（§3.14） | 摘要可核对 | 拒绝并说明需确认 | 静默投递行数据 |

- 通用禁令：不可逆操作（删连接、删表、清表、终止会话、高危写）必须先二次确认并说明后果；需要用户决策的错误不得用 toast 承载；未授权入口不出现（不是灰掉）。

### 5.6 表单实现与校验落点

| 表单/字段 | 前端校验 | 后端校验 | 错误定位位置 | 禁止行为 |
|---|---|---|---|---|
| 连接名称 | 非空、同工作区唯一 | 同左 | 字段下方 | 仅前端校验 |
| 主机 | 非空 | 同左 | 字段下方 | 前端拼连接串 |
| 端口 | 整数，先解析再校验 1…65535 | 同左 | 字段下方 | 越界静默夹取 |
| 用户名 | 非空 | 非空 | 字段下方 | 空口令尝试连接 |
| SQL 文本 | 非空 | 非空 + 目标库一致 | 编辑器下方错误件 + 消息面 | 空执行静默通过 |
| 导出格式 | 取值为支持集合 | 同左 | 字段下方 | 生成不支持格式的空文件 |
| 导入目标 | 目标存在必须询问 | 同左 | 顶部汇总 + 字段 | 静默覆盖既有表 |

- 前后端校验必须一致，后端为最终依据；前端通过不得假定后端成功。
- 可访问性落点：每个视图主动作有键盘路径；容器、按钮、输入框、状态提示带可读名称；空/加载/错误三态有文字表述；同一动作的文案、图标、快捷键、禁用条件只在 `AppCommandCatalog` 定义一次。

### 5.7 导航与权限落点

| 起点 | 触发 | 终点 | 前置条件 | 禁止行为 |
|---|---|---|---|---|
| 活动栏 | 点「数据库」 | 查询页签 | 有可用连接（无连接先给建连引导） | 直接报错 |
| 对象树节点 | 双击表 | 新查询页签（浏览前 N 行） | 连接已就绪 | 未连接时打开空页签 |
| 查询页签 | 执行成功 | 同页签结果区 | 至少一条语句完成 | 自动跳到别的页签 |
| 会话视图 | 终止会话 | 同视图 | 已二次确认 | 未确认离开 |
| 对话页签 | 点写操作卡片 | 审批单 | 该动作需审批 | 越过审批直接执行 |

- 路由守卫落点：`AppState.openTab(kind:)` 一处判定入口可见性与前置条件；界面不得各自判一次。
- 未授权处理：入口不渲染；到期只降级入口，数据可开可导出（禁锁死用户数据）。
- 禁止：新增未列出的路由或入口；未确认离开导致未保存内容丢失；同一入口在两处各判权限。

### 5.8 界面测试契约

| 用例 ID | 类型 | 覆盖条款 | Given | When | Then |
|---|---|---|---|---|---|
| `UI-5.1-01` | 路由清单 | 概要设计 §8.1 / §8.2 | 视图清单与命令目录 | 遍历所有可打开入口 | 无清单外路由，`check-palette-wiring.py` 差集 0 |
| `UI-5.1-02` | 职责 | 概要设计 §8.2 | 八类视图各打开一次 | 逐视图核对呈现项 | 禁止呈现项（口令/连接串/未授权入口）出现 0 次 |
| `UI-5.3-01` | 组件 | 概要设计 §8.4 | 七个组件各造六态 | 逐态渲染 | 六态齐，六张表的「禁止渲染」列各行为空 |
| `UI-5.3-02` | 错误呈现 | 概要设计 §8.8 | 注入四类错误（字段/页面/服务器/不可恢复） | 渲染 | 每类都含原因 + 位置 + 重试入口 |
| `UI-5.3.1-01` | 组件 | 概要设计 §8.4 / §8.7 | 查询页签六态夹具 | 逐态渲染 | 只在 `isExecuting` 时出现停止按钮；失败不清空 SQL |
| `UI-5.3.2-01` | 组件 | 概要设计 §8.6 | 连接表单六态夹具 | 逐态渲染 | 校验未过时提交按钮禁用且零请求 |
| `UI-5.3.3-01` | 组件 | 概要设计 §8.4 / §8.7 | 连接清单六态夹具 | 逐态渲染 | 删除必先确认；凭据清理失败要明说残留 |
| `UI-5.3.4-01` | 组件 | 概要设计 §4.5 / §8.4 | 对象树六态夹具 | 逐态渲染 | 刷新后选中节点不变；无伪造占位节点 |
| `UI-5.3.5-01` | 组件 | 概要设计 §5.4 / §6.3 | 审批单六态夹具 | 逐态渲染 | 过期/无记录不可批准；预估缺失显示「未接」 |
| `UI-5.3.6-01` | 组件 | 概要设计 §4.8 / §8.4 | 导入导出六态夹具 | 逐态渲染 | 部分失败分别列成功与失败项 |
| `UI-5.3.7-01` | 组件 | 概要设计 §3.1 / §8.4 | 浏览页签六态夹具 | 逐态渲染 | 加载失败不出现空白成功页；关闭参与 ⌘W 口径 |
| `UI-5.5-01` | 交互 | 概要设计 §8.5 | 五类不可逆动作 | 触发动作 | 每次都先出确认并说明后果；需要决策的错误不走 toast |
| `UI-5.5-02` | 动作映射 | 概要设计 §8.7 | 十行动作表 | 逐行制造失败 | 失败保留用户输入，无一条冒充成功 |
| `UI-5.6-01` | 表单 | 概要设计 §8.6 / §8.9 | 七行字段表 | 逐字段注入非法值 | 错误定位到字段；键盘可走完连库→执行→看结果→关页 |
| `UI-5.7-01` | 导航 | 概要设计 §8.3 | 五条允许流转 + 非法跳转 | 逐条触发 | 非法跳转被拒并给理由 |
| `UI-5.7-02` | 可访问性 | 概要设计 §8.9 | 三主题 × 各视图 | 纯键盘 + 读屏走一遍 | 焦点可见、三态有文字、快捷键只在命令目录一处 |
| `UI-5.8-01` | 覆盖率 | 概要设计 §8.10 | 本表与 §0.1 矩阵 | 比对矩阵 UI 行 | 矩阵每个 UI 行在本表都有用例；本表无用例游离 |
| `UI-5.8-02` | 概要设计 §8.11 | §5.3.8.1 / §5.3.8.2 | 一屏真实对话（含工具块与状态行） | 逐条比对行首栏字形 / 字号唯一 / 状态行字段序 / 有无通栏卡片 | 六项全合规，任一不符即红 |

测试禁止行为：禁止 `XCTSkip` / 只跑一个用例 / `sleep` 等待 / 依赖真实网络与真实库 / 改动断言适配实现。

---

## 6. 错误映射与日志

### 6.1 错误码映射（概要设计 §9 的 21 码）

| 概设错误码 | 本端落点 | 状态 |
|---|---|---|
| `CONN_INVALID_CONFIG` | `AppError.invalidConfiguration` | 已有 |
| `CONN_NO_CREDENTIAL` | `AppError.credentialStore` + `SecretStore` 实现 | 已有 |
| `CONN_UNREACHABLE` | `ConnectionFailure`（不可达分类） | 已有 |
| `CONN_AUTH_FAILED` | `ConnectionFailure`（认证分类） | 已有 |
| `CONN_NOT_FOUND` | 连接清单查找路径（按 `.notConnected` 呈现） | 无专门类型 |
| `CRED_PURGE_FAILED` | `AppError.credentialStore` + 残留位置上浮 | 已有 |
| `EXEC_EMPTY_SQL` | 装配层前置校验（`ExecutionScope.Issue`） | 无专门类型 |
| `EXEC_NO_CONNECTION` | `AppError.notConnected` | 已有 |
| `EXEC_READONLY_DENIED` | `ExecutionSafety.Decision.refused` | 已有 |
| `EXEC_CONFIRM_REQUIRED` | `ExecutionSafety.Decision.needsConfirmation` | 已有 |
| `EXEC_SERVER_ERROR` | `AppError.queryFailed` + 服务端原文 | 已有 |
| `EXEC_CONNECTION_LOST` | `QueryEvent` 失败事件 | 已有 |
| `EXEC_CANCEL_ILLEGAL` | `CancelOutcome.failed(reason:)` | 已有 |
| `META_UNSUPPORTED` | `AppError.notImplemented` + 层级差异说明 | 已有 |
| `DATA_NO_PK` | `applyRowEdits` 前置（§3.9） | 未实现（§10.1） |
| `DATA_WRITE_CONFLICT` | `applyRowEdits` 逐行结局（§3.9） | 未实现（§10.1） |
| `DDL_PREVIEW_REQUIRED` | `SchemaScriptRunner.run` 预览闸（§3.10） | 未实现（§10.1） |
| `IO_TARGET_EXISTS` | `TableImport.plan` 覆盖询问（§3.12） | 未实现（§10.1） |
| `IO_PARTIAL` | `TableImport.plan` 逐批结局（§3.12） | 未实现（§10.1） |
| `SESS_KILL_DENIED` | `SessionMonitor` 动作路径（§3.13） | 未实现（§10.1） |
| `LIC_NO_CAPABILITY` | 授权判定（入口可见性） | 未实现（§10.1） |

- 概要设计 §4.x 另有 10 个接口级码不在 §9 的 21 码清单内：`EXEC_CANCEL_FAILED`、`META_FAILED`、`DATA_WRITE_FAILED`、`DDL_CONFIRM_REQUIRED`、`DDL_FAILED`、`IO_FORMAT_UNSUPPORTED`、`SESS_NOT_FOUND`、`SESS_KILL_REQUIRED_CONFIRM`、`BRIDGE_ROW_DATA_REQUIRES_CONFIRM`、`BRIDGE_EMPTY_CONTEXT`。这 10 个码逐条落在 §3 各节的错误契约表里，不另立映射表。
- 呈现规则：字段级错误呈现在字段附近；页面级错误呈现在结果区或页面顶部并带重试入口；服务器错误保留原文（可复制）并附语句序号与目标库；不可恢复错误阻断当前动作并给下一步。

### 6.2 四条禁止兜底在本端的实现级禁令

| 概设禁令 | 本端落点 | 判据 |
|---|---|---|
| 禁止返回空对象冒充成功 | `AppError` 全枚举无 `.empty` 型成功值；`loadChildren` 只能在真有 0 个子节点时返回空数组 | `T-6.2-01` 反例：注入失败 ⇒ 必须抛错，不得返回 `[]` |
| 禁止用默认值掩盖缺失 | 缺参一律失败（§3.1 前置）；预估缺数写「未接」（§3.16） | `T-3.1-02`、`T-3.16-01` |
| 禁止捕获异常后不记录、不返回、不处理 | 每个 `catch` 必须至少做「记 + 返」之一；`rg -n 'catch \{ *\}'` 为空 | `T-6.2-01` |
| 禁止把依赖失败降级为业务成功 | 归档失败只报「记录未落盘」，业务结果不回滚（§4.2）；同步续期失败不当作登出 | `T-4.2-01`、`T-4.5-01` |

### 6.3 日志字段

- 必记：错误码、连接标识、会话/页签标识、调用方、时间、耗时、结局。
- 禁记：口令、凭据引用原文、完整连接串、结果行数据、执行计划全文、导出正文。
- 落点：审计与出口日志统一走 `AgentAudit` / `EgressLog`（追加式 JSONL）；日志写入失败不得吞掉（记到 stderr 并保留计数）。
- 判据：`rg -n 'password|secret|dsn' Core/ | rg -i 'log|print'` 为空；导出前脱敏由 `AgentContext.filterSecretsOnly` 承担。

---

## 7. 并发与线程模型

### 7.1 并发模型与共享可变状态

| 约束 | 落法 |
|---|---|
| 界面状态只在主线程改 | 装配层与模型 `@MainActor`；能力层回调只递值 |
| 一个「连接 + 库」只有一个服务实例 | `AppState.ensureService` 以「连接 + 库」为键；跨页签共享 |
| 同一连接上的语句串行 | 服务内部串行队列；取消走句柄，不靠抢占 |
| 笔记写入单事务 | `NoteLibrary` actor 内串行 |
| 同步单飞 | `SyncQueue` 串行，重入即排队 |
| 禁止 | 事务中发外部网络调用；锁内慢操作；无界并发 |

### 7.2 事务边界与幂等

- 事务边界：一次执行一个事务；手工事务由用户驱动，跨页签不共享事务对象。
- 幂等键：连接建立 = 连接 id；取消 = 执行句柄；行写回 = 主键；审批 = fingerprint；导入 = 目标表 + 批次序号。
- 归档与审计属动作后置：失败只报「记录未落盘」，不回滚业务；写入原子（JSONL 追加 + 换行）。
- 禁止：事务进行中切换连接或目标库；把取消写进成功分支；对写语句自动重试。

---

## 8. 安全

### 8.1 鉴权与凭据落点

- 鉴权落点：能力层与驱动层判定（只读、能力位）；界面只呈现结果，禁止前端-only 判定。
- 凭据：只经 `SecretStore` 协议取用，macOS 实现 `Platform/macOS/KeychainSecretStore.swift`；删除连接连带清理；口令不进日志、不进模型上下文、不进导出包。
- 已修：`AppState.init(secretStore:agentKeyStore:)` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`；文件实现仅测试态显式注入（见 §2.2）。
- 到期与授权：能力位解析离线可校验，入口可见性只在一处判定；到期降级入口但保留数据可开可导出。

### 8.2 输入校验与注入防护

- 输入校验位置：`ConnectionConfig` 与装配层前置校验；服务端校验为最终依据。
- 注入防护：一律参数化（`:name` / `$1` 类型化转义），禁止字符串拼接；标识符经 `SQLGenerator` 转义。
- 外部工具输出一律不可信：工具观察值进模型前先脱敏与限长。
- 错误信息不泄露堆栈、连接串与凭据引用；`EgressLog` 记录每一次外发（目的地、体量、时刻），不含正文。

---

## 9. 判据与测试

### 9.1 测试文件与组织

| 测试文件 | 被测单元 | 类型 | 必须覆盖的条款 |
|---|---|---|---|
| `Tests/ConnectionConfigTests.swift` | `ConnectionConfig`、`DatabaseServiceFactory` | 单元 | §3.1、§4.1 |
| `Tests/ConnectionConfigMigrationTests.swift` | `ConnectionStore` | 单元 | §3.2、§4.2 |
| `Tests/ExecutionScopeTests.swift` | 选区判定与空 SQL 拦截 | 单元 | §3.3 前置 |
| `Tests/ExecutionSafetyTests.swift` | `ExecutionSafety.check` | 单元 | §3.5 |
| `Tests/CancellationNoiseTests.swift` | `execute` / `cancel` 流语义 | 单元 | §3.3 后置、§3.4 |
| `Tests/ConnectionReadOnlyTests.swift` | 只读连接拒写 | 单元 | §3.5、§4.4 |
| `Tests/AgentApprovalGateTests.swift` | `AgentApprovalGate` | 单元 | §3.6、§4.4 |
| `Tests/ConnectionFailureTests.swift` | 错误码呈现 | 单元 | §6.1 |
| `Tests/AgentPlanRowsTests.swift` | 影响行数预估 | 单元 | §3.16 |
| `TestsPlatform/`（快照面） | 视图六态 | 快照 | §5.3、§5.8 |
| `TestsUISnapshot/AgentWorkspaceRootProbeTests.swift` | `WorkspaceStore` 根来源判定、`AgentWorkspaceTools` 边界、`AgentWorkspaceSection` 可见性 | 探针（`DOYAH_UI_SNAPSHOT=1`） | §3.38 |
| `Scripts/verify-core.sh` | 全能力层回归 | 集成 | §9.3 |

### 9.2 必测用例清单（后端）

| 用例 ID | 对应概设条款 | 对应详设契约 | Given | When | Then |
|---|---|---|---|---|---|
| `T-2.1-01` | 概要设计 §3 | §2.1 禁令 | 全仓源码 | 检索界面层对驱动的引用 | 命中 0 处；界面不持句柄 |
| `T-2.2-01` | 概要设计 §4.1 / §11.4 | §2.2 注入点 | 注入替身（方言 / 时钟 / ID / HTTP） | 跑 §3.1–§3.16 各用例 | 全部可用替身驱动，无需改生产代码 |
| `T-2.3-01` | 概要设计 §19.2 | §2.3 插件清单 | 插件清单与门禁期望列表 | 比对两处 | 差集 0；跨层引用检索为空 |
| `T-3.1-01` | 概要设计 §4.1 | §3.1 后置 | 合法 `ConnectionConfig` | 调 `make` | 返回服务且 `config` 逐字段相等；未建连 |
| `T-3.1-02` | 概要设计 §4.1 | §3.1 错误表 | 空主机 / 端口 0 / 未知类型 | 调 `make` | 分别抛 `invalidConfiguration` / `notImplemented`，无实例产生 |
| `T-3.2-01` | 概要设计 §4.2 | §3.2 后置 | 两条连接配置 | `save` 后 `load` | 逐字段一致；`schemaVersion` 保留 |
| `T-3.2-02` | 概要设计 §5.1 | §3.2 迁移 | 旧格式文件 | `loadWithReport` | 读出新条目并升级一次，二次读不再升级 |
| `T-3.3-01` | 概要设计 §4.3 / §7.1 | §3.3 后置 | 两段 SQL + 一段选区 | 执行 | 有选区只跑选区；按文本顺序逐条上报；结果集全保留 |
| `T-3.3-02` | 概要设计 §4.3 | §3.3 后置 | 长查询 | 执行中取消 | 不再收 `resultSet`；无噪声事件；连接仍可用 |
| `T-3.3-03` | 概要设计 §4.3 | §3.3 前置 | 空串 / 纯空白 | 点执行 | 报 `EXEC_EMPTY_SQL`，不发语句 |
| `T-3.4-01` | 概要设计 §4.4 | §3.4 后置 | 执行中句柄 | 重复 `cancel` 两次 | 两次同一结局；连接仍可用；服务端真取消 |
| `T-3.5-01` | 概要设计 §4.3 / §7.1 | §3.5 后置 | 只读连接 / 无 WHERE 写 / DROP | 调 `check` | 分别 `refused`（原因非空）/ `needsConfirmation` |
| `T-3.6-01` | 概要设计 §5.4 / §6.3 | §3.6 后置 | 一条 pending 审批单 | 连续两次 `grant` 同一 fingerprint | 第一次 approved 且落一条消费；第二次 `.missing` |
| `T-3.7-01` | 概要设计 §4.5 | §3.7 后置 | 已展开并选中的对象树 | 刷新 | 层级随类型；选中不变；无占位节点 |
| `T-3.8-01` | 概要设计 §4.6 | §3.8 后置 | 表名 + 过滤 + 上限 | 生成浏览语句 | 上限与排序在服务端；坏条件返回 failure |
| `T-3.9-01` | 概要设计 §4.6 | §3.9 错误表 | 无主键结果集 / 并发改行 | 写回 | 前者不开放入口；后者报 `DATA_WRITE_CONFLICT` |
| `T-3.10-01` | 概要设计 §4.7 / §7.2 | §3.10 前置 | 已生成脚本未预览 | 执行 | 报 `DDL_PREVIEW_REQUIRED`，服务端未收语句 |
| `T-3.10-02` | 概要设计 §4.7 / §7.2 | §3.10 错误表 | 只读连接 / 超上限任务 | 执行 DDL | 前者 `refused`；后者拒绝且不改表 |
| `T-3.11-01` | 概要设计 §4.8 | §3.11 后置 | 含特殊字符的结果集 | 五种格式导出 | 转义正确；输出逐字节可重现；不含凭据 |
| `T-3.12-01` | 概要设计 §4.8 | §3.12 错误表 | 目标已存在 / 部分行不可转 | 导入 | 前者先询问；后者列 `invalidValues` |
| `T-3.13-01` | 概要设计 §4.9 | §3.13 错误表 | 无终止权限的会话 | 终止 | 上浮服务端原话；无确认时先拒绝 |
| `T-3.14-01` | 概要设计 §4.10 | §3.14 错误表 | 含结果行数据的上下文 | 未确认投递 | 报 `BRIDGE_ROW_DATA_REQUIRES_CONFIRM`；审计 0 条 |
| `T-3.15-01` | 概要设计 §18.1 | §3.15 错误表 | 参数不合规的工具调用 | `dispatch` | 直接给模型可读错误；工具未执行、无副作用 |
| `T-3.16-01` | 概要设计 §5.4 | §3.16 后置 | `ModifyTable` 根节点 `Plan Rows` 为 0 | `estimate` | 取子节点行数；取不到返回 `noAnswer`，不返回 0 |
| `T-4.1-01` | 概要设计 §5.1 | §4.1 | 一份连接配置 | 编码再解码 | 字段与约束一致；不含口令字段 |
| `T-4.2-01` | 概要设计 §5.2 | §4.2 | 同一 SQL 执行两次 | 读历史 | 一条记录、重复次数 2；归档失败不回滚业务 |
| `T-4.2-02` | 概要设计 §5.3 | §4.2 | 任务定义 | 执行时参数与定义不一致 | 拒绝执行；上限越界拒绝 |
| `T-4.4-01` | 概要设计 §6.1 | §4.4 | 未连接 | 建立连接 | 进入连接中，再进已连接 |
| `T-4.4-02` | 概要设计 §6.1 | §4.4 | 失败态 | 直接置已连接 | 拒绝；必须经连接中 |
| `T-4.4-03` | 概要设计 §6.2 | §4.4 | 执行中 | 取消 | 进入已取消 |
| `T-4.4-04` | 概要设计 §6.2 | §4.4 | 已取消 | 置已完成 | 拒绝；重跑是新执行 |
| `T-4.4-05` | 概要设计 §6.3 | §4.4 | 已拒绝 | 置已批准 | 判决为 `.denied`，不可翻 |
| `T-4.4-06` | 概要设计 §6.3 | §4.4 | 已过期 | 置已批准 | 判决为 `.expired`，不可翻 |
| `T-4.4-07` | 概要设计 §6.4 | §4.4 | 执行中页签 | 关闭 | 拒绝并给理由「执行中，请先停止」 |
| `T-4.4-08` | 概要设计 §6.4 | §4.4 | 有未保存改动页签 | 关闭并确认 | 进会话快照；保存失败时脏标记保留 |
| `T-4.5-01` | 概要设计 §15 | §4.5 | 一条带标签与时间线的笔记 | 写入中断 | 本体/标签/时间线同事务回滚；续期失败不登出 |
| `T-4.7-01` | 概要设计 §16 | §4.7 | 插件装载清单 | 装载复盘宿主 | 宿主可挂载；业务判据在复盘仓自跑（他仓） |
| `T-4.8-01` | 概要设计 §7.3 | §4.8 | 磁盘文件被外部改动 | 保存与重新载入二选一 | 无静默覆盖；保存失败不清脏标记 |
| `T-6.1-01` | 概要设计 §9 | §6.1 | 21 个错误码各造一次 | 触发并呈现 | 每码有落点与呈现形态；文案来自文案表 |
| `T-6.2-01` | 概要设计 §9 | §6.2 | 四类兜底场景（空对象 / 默认值 / 吞异常 / 降级） | 注入失败 | 四类均不被当成成功；空 `catch` 检索为空 |
| `T-7.1-01` | 概要设计 §11.4 | §7.1 | 同连接两个页签并发执行 | 同时点执行 | 语句串行；服务实例唯一；无事务串台 |
| `T-7.2-01` | 概要设计 §11.4 | §7.2 | 手工事务进行中 | 切换连接 | 拒绝；归档失败只报「记录未落盘」 |
| `T-8.1-01` | 概要设计 §11.4 | §8.1 | 删除连接 | 观察凭据与日志 | 凭据条目清空；日志无口令与连接串 |
| `T-8.2-01` | 概要设计 §11.4 | §8.2 | 含引号与分号的值 | 参数化执行 | 值不参与语句拼接；注入样例不改变语法结构 |
| `T-3.17-01` | 概要设计 §3 / §4 | §3.17 | 授权目录 + `echo hi` | 执行 | 返回 exitCode 0，stdout 含 `hi`，无截断 |
| `T-3.17-02` | 概要设计 §3 / §11.4 | §3.17 | 未授权目录 | 执行任意命令 | 返回 `.refused(.directoryNotAuthorized)`，进程启动次数 0 |
| `T-3.17-03` | 概要设计 §3 / §11.4 | §3.17 | `sleep 5` + timeout 1s | 执行 | 返回 `.timedOut`，子进程已终止（`ps` 查不到） |
| `T-3.17-04` | 概要设计 §3 / §5.4 | §3.17 | `rm -rf build` | 执行 | 先出审批单且命令完整；拒绝后进程启动次数 0 |
| `T-3.18-01` | 概要设计 §3 | §3.18 | 授权目录 + `print(1+1)` | 执行 | exitCode 0，stdout 含 `2`，无截断 |
| `T-3.18-02` | 概要设计 §3 / §11.4 | §3.18 | 代码里发起 HTTP 请求 | 执行 | `.refused(.networkForbidden)`，外发日志 0 条 |
| `T-3.18-03` | 概要设计 §3 | §3.18 | `while True: pass` | 执行 | `.timedOut`，进程已终止，临时目录已清 |
| `T-3.19-01` | 概要设计 §3 | §3.19 | query=「跑代码」 | 检索 | 命中内置代码执行与接入类各一，标注来源 |
| `T-3.19-02` | 概要设计 §3 | §3.19 | 未取回 schema 直接调用未知工具 | 派发 | 被拒并说明「未取回参数说明」 |
| `T-3.20-01` | 概要设计 §3 | §3.20 | 三个无依赖子任务 | 并发执行 | 返回长度 3、顺序与输入一致、全部 finished |
| `T-3.20-02` | 概要设计 §3 / §11.4 | §3.20 | 五路 + 并发上限 4 | 执行 | 第 5 路排队后仍完成；峰值并发 ≤ 4 |
| `T-3.20-03` | 概要设计 §3 | §3.20 | 三路，中间一路抛错 | 执行 | 该路 failed，另两路 finished，归并含三路结局 |
| `T-3.21-01` | 概要设计 §18.2 | §3.21 禁止 | 上下文已接近上限、处于回合中 | 连续 3 轮模型调用 | 压缩计数 0；每轮只出 `AgentBudgetReport`，上下文未被改写 |
| `T-3.21-02` | 概要设计 §18.2 | §3.21 后置 | 会话结束边界、历史超限 | 触发压缩 | 返回 `.runNow(boundary:)`；决策与约束仍在；输出含「丢了什么类别」与前后 token 读数 |
| `T-3.21-03` | 概要设计 §18.2 | §3.21 错误表 | 压缩后仍超上限 | 压缩完成 | 返回 `.refuse(.stillOverLimit)` 并带前后读数；无静默截断 |
| `T-3.22-01` | 概要设计 §18.1 | §3.22 错误表 | 注册表内同名工具两处声明 | 装载注册表 | 报 `.duplicateDeclaration(name)`，装载中止，不取后者 |
| `T-3.22-02` | 概要设计 §18.1 | §3.22 错误表 | 工具已登记、当前 profile 不可见 | 调用该工具 | 返回 `.toolNotVisibleInProfile`；与「未登记」提示文案不同 |
| `T-3.22-03` | 概要设计 §18.1 / §18.20 多端一致性 | §3.22 后置 | 同一工具在两壳 | 分别取快照 | 两壳 `fingerprint` 与 handler 标识相同，实现不分叉 |
| `T-3.23-01` | 概要设计 §18.2 / §18.23 | §3.23 后置 | 一次真实会话结束 | 退出 CLI | `onSessionEnd` 恰好触发 1 次，日志含 `boundaryKind=cliExit` |
| `T-3.23-02` | 概要设计 §18.23 | §3.23 错误表 | 引擎钩子抛错 | 继续会话 | 会话不中断；降级日志入库；`HookOutcome=.failed` 上浮可观测层 |
| `T-3.23-03` | 概要设计 §18.2 | §3.23 错误表 | 回合进行中 | 调 `onSessionEnd` | 拒绝并返回 `.notASessionBoundary`；不写结束记录 |
| `T-3.29-01` | 概要设计 §18.23 | §3.29 步数口径 | 一次运行上限 150 步，已走 5 步 | 读步数显示 | 分子 5、分母仍 150（不随步数增长） |
| `T-3.29-02` | 概要设计 §18.23 | §3.29 详单高度 | 40 步的长详单 | 展开执行步骤 | 面板高度 ≤ 上限且内部滚动；输入区仍在窗口内 |
| `T-3.30-01` | 概要设计 §3 | §3.30 ① | 子代理跑 3 条事件 | 看主对话 | 主对话只出现 1 条归并摘要，子路事件不混入 |
| `T-3.30-02` | 概要设计 §3 | §3.30 ② | 主控预算剩 5 分钟、子预算 10 分钟 | 派一个子任务 | 子路按自己的截止时刻算，不因主控剩余而立刻超时 |
| `T-3.30-03` | 概要设计 §3 | §3.30 ③ | 同一子任务 id 完成后再派一次 | 重派 | 子会话号不同；新一轮上下文不含上一轮结论 |
### 9.3 判据怎么跑

| 场景 | 命令 | 期望 |
|---|---|---|
| 纯能力层改动 | `bash Scripts/verify-core.sh` | 全绿，计数与台账一致 |
| 要出包 | `bash Scripts/build-app.sh` | 打印字节数 + sha256 前缀 |
| 界面改动 | `python3 Scripts/check-design-tokens.py` | 不高于基线 |
| 新命令入口 | `python3 Scripts/check-palette-wiring.py` | 未登记差集 0 |
| 新中文文案 | `python3 Scripts/check-core-localization.py` | 无缺键 / 无未分类 |
| 插件装配 | `python3 Scripts/check-plugin-assembly.py` | 装载 6 组绿 |
| 文档改动 | `python3 Scripts/check-doc-tables.py && python3 Scripts/check-doc-layout.py` | 两者 rc=0 |
| 本文件自检 | `python3 <skill>/scripts/audit_lld.py Docs/Doyah产品详细设计说明书-macOS.md --hld Docs/Doyah产品概要设计说明书.md --repo .` | 硬失败 0 / 告警 0 |

---

## 10. 合规自检

### 10.1 未实现位点（代码现状，不是文档缺口）

| 位点 | 现状 | 契约要求 |
|---|---|---|
| 行编辑（`DATA_NO_PK` / `DATA_WRITE_CONFLICT`） | 无专门类型，`RowBrowsing` 只做浏览 | §3.9 四类行为，实现时按错误表补分支 |
| 结构脚本预览闸（`DDL_PREVIEW_REQUIRED`） | 未实现（`TableDesign` 只做列定义校验） | §3.10 两个前置不可绕 |
| 导入导出错误（`IO_TARGET_EXISTS` / `IO_PARTIAL`） | `ResultExporter` 已实现；导入询问与部分失败汇总未实现 | §3.12 逐批结局 |
| 服务器会话终止（`SESS_KILL_DENIED`） | `SessionMonitor` 只解析列表 | §3.13 确认 + 原话上浮 |
| 授权能力位（`LIC_NO_CAPABILITY`） | 未实现，入口可见性无统一判据 | §8.1 单点判定 |
| 凭据存储注入 | **已修（2026-10-25）**：`AppState.init` 默认 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，文件实现只在测试态注入 | §2.2 构造函数注入（已落地） |
| 只读连接与生产标签联动 | 标签特性未实现，当前由 `policy.isEnabled` 全局开关承担 | §3.5 不得造旁路开关 |
| 内嵌浏览器 / 插件装载 / 端云同步 | 有实现文件但本节未逐函数展开 | 概要设计已定行为，本文件待补（§11 `DETAIL_GAP` 第 6 条） |

### 10.2 逐条自检

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | §1.2 每个「修改」路径真实存在 | 过 | 15 张文件均在盘（`ls` 逐条） |
| 2 | §1.2 与 §1.3 路径集合交集为空 | 过 | 集合比对，交集 0 |
| 3 | 每个公开函数七段齐 | 过 | §3.1–§3.16 各含前置/后置/错误表/禁止/并发/日志/测试 ID |
| 4 | 每张错误表有「可重试」列且逐行有判定 | 过 | `audit_lld.py` 的 C01 读数 0 |
| 5 | 21 个错误码都有落点或标「未实现」 | 过 | §6.1 表 21 行 |
| 6 | 七个组件六态齐且「禁止渲染」非空 | 过 | §5.3.1–§5.3.7；U01 读数 0 |
| 7 | 矩阵无空「落点/测试 ID」 | 过 | §0.1 42 行全填 |
| 8 | 测试 ID 无悬空 | 过 | `audit_lld.py` 的 T01 读数 0 |
| 9 | 测试 ID 无孤儿 | 过 | `audit_lld.py` 的 T02 读数 0 |
| 10 | 未引入 §1.1 禁止项 | 过 | 12 条静态检查清单逐条检索为空 |
| 11 | 状态机未新增状态、未绕过 guard | 过 | §4.4 九行 + `.missing` 实现口径 |
| 12 | 落点节引用全部解析得到 | 过 | `audit_lld.py` 的 M04 读数 0 |
| 13 | 概设契约节全覆盖 | 过 | `audit_lld.py` 的 H02 读数 0（33 节逐节有行） |
| 14 | 无禁用词、无占位符 | 过 | `audit_lld.py` 的 W01 / P01 读数 0 |

---

## 11. 偏离处理与登记

| 信号 | 触发条件 | 动作 |
|---|---|---|
| `DETAIL_GAP` | 本文件未覆盖的公开行为 | 取最小假设继续，并登记到本节表 |
| `DETAIL_CONFLICT` | 与代码现状冲突 | 停工，报人类主人 |
| `CONTRACT_DEVIATION` | 偏离 §3 / §5.3 契约 | 等确认 |
| `PLATFORM_CHANGE` | 需要更换本端基线 | 停工 |
| `DESIGN_CONFLICT` | 与概要设计冲突 | 以概要设计的「禁止」为准，不自行裁决 |

已登记的 `DETAIL_GAP`（概要设计未定义、本文件按最小假设落地）：

| # | 未覆盖点 | 所做选择 | 影响范围 | 建议补的条款 |
|---|---|---|---|---|
| 1 | 行写回 SQL 的具体形态（是否带旧值条件） | 带主键 + 旧值条件，影响 0 行报冲突 | §3.9 | 概要设计 §4.6 补一句「写回带旧值条件」 |
| 2 | 导入批大小与回滚粒度 | 每批一个事务，批大小固定常量 | §3.12 | 概要设计 §4.8 补批粒度 |
| 3 | 笔记库事务隔离级别 | 同库单连接串行，用默认隔离级别 | §4.5 | 概要设计 §15.1 补隔离级别 |
| 4 | 「到期降级」后允许的导出格式集合 | 全部已支持格式均允许导出 | §8.1 | 概要设计 §3 授权判定补格式白名单 |
| 5 | 复盘插件装载失败时宿主的界面表现 | 宿主显示占据位 + 失败原因，不隐藏槽位 | §4.7 | 概要设计 §16.2 补宿主失败态 |
| 6 | 内嵌浏览器/插件装载/端云同步的逐函数契约 | 本文件暂不展开，只给禁止项 | §2.3、§5.3.7 | 本文件下一版补，或概要设计补组件级接口 |

已登记的 `CONTRACT_DEVIATION`（契约已立、实现未跟 —— 设计与实现的时间差，关闭判据是测试转绿）：

| # | 条款 | 现状 | 关闭判据 |
|---|---|---|---|
| 1 | §3.21 压缩只在会话边界 | ✅ **已闭合 2026-10-26**：`Core/AgentCompressionAdmission.swift`（`AgentContextCompression.admit(at:)`，四结局 + 幂等台账） | `T-3.21-01~03` **全绿**（`AgentCompressionAdmissionTests` 8 例；回合内只 `.deferToBoundary`） |
| 2 | §3.22 注册表唯一真源 + 可见性由 profile 决定 | ✅ **已闭合 2026-10-26**：`Core/AgentToolCatalogSnapshot.swift`（`AgentToolCatalog.snapshot(for:)`；同名两处停装载；不可见≠未登记；两壳同 fingerprint） | `T-3.22-01~03` **全绿**（`AgentToolCatalogSnapshotTests` 8 例） |
| 3 | §3.23 引擎生命周期钩子 | ✅ **已闭合 2026-10-26**：`Core/AgentContextEngine.swift`（五钩子封闭集、抛错折 `.failed` 不断会话、`onSessionEnd` 恰好一次、回合内拒 `.notASessionBoundary`） | `T-3.23-01~03` **全绿**（`AgentContextEngineTests` 6 例） |

已登记的 `DETAIL_CONFLICT`（与代码现状冲突，须人类主人裁决，Agent 不得自行改设计或改代码）：

| # | 冲突点 | 代码现状 | 契约要求 | 处置 |
|---|---|---|---|---|
| 1 | 凭据存储形态（**已闭合**） | 原：`AppState.secretStore = FileSecretStore()`（XOR 混淆）。现：`AppState.init(secretStore:)` 默认 `KeychainSecretStore()` | 概要设计 §3「口令只存密钥存储」；本文件 §2.2 构造函数注入 `SecretStore` | **已裁决（2026-10-25 人类主人令「改实现」）**：`AppState.init` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，`FileSecretStore` 退为测试态；本行保留留痕，冲突关闭 |

暂定口径承接（概要设计 §14.1 第 4、5、6、8 条，本端按暂定口径实现，人类主人可否决）：

- 审批单过期 = 拒绝（`.expired` 不可翻批准）；撤回 = `.denied` 并留痕；已批准未执行的按拒绝处理。
- 影响行数取不到 ⇒ 审批单写「未接」并照常提交，不得用表总行数或本地估算填充。
- 助理桥「自动附带上下文」默认关闭，仅当前会话显式勾选时附带，每次附带写审计。
- 设备配额超限：提示「先移除最久未使用的一台」并列出候选，禁止自动踢设备。

---

## 13. 本端已知坑（必须先读）

### 13.1 PG 18 改进数据语句的 `Plan Rows` 在根节点上是 0

`EXPLAIN (FORMAT JSON) UPDATE …` 的根节点是 `ModifyTable`，`Plan Rows` 恒为 0（不带 `RETURNING` 时它不输出行），真实预估在子节点（如 `Seq Scan` 500）。只读根会稳定报「0 行」，这是最危险的假数。

规则：根为 `ModifyTable` / `Update` / `Delete` / `Insert` / `Merge` 且根值为 0 ⇒ 取 `Plans` 的第 0 项；根非 0（带 `RETURNING`）用根。这条只有对真库跑才能发现，落点见 §3.16。

### 13.2 `swift test` 不带 `DEVELOPER_DIR` 会找不到 XCTest

报 `unable to resolve module dependency: 'XCTest'`。跑法：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`。

### 13.3 测试总数只认 `verify-core.sh`

`swift test --filter` 的 `Executed N tests` 是过滤后的数，不能当 Core 总数；真值在 `bash Scripts/verify-core.sh` 写出的 `.build/core-test-count.txt`。

### 13.4 localization 棘轮与锚仓 `pre-push` 护栏

- `check-core-localization` 基线上调需授权，不得自行 `--update-baseline`。
- 锚仓 `.git/hooks/pre-push` 白名单只放 `Docs/` 一类路径；推 `Scripts/` 会被拦，需 `-c core.hooksPath=/dev/null` 单次绕过并留痕。

### 13.5 `FileSecretStore` 仍留在仓里，只能测试态注入

2026-10-25 人类主人裁定「改实现」后：`AppState.init(secretStore:agentKeyStore:)` 默认注入 `KeychainSecretStore()` / `KeychainAgentKeyStore()`，口令与模型密钥都进系统钥匙串。`FileSecretStore`（XOR 混淆）只剩测试 / 开发态用途 —— **任何新代码不得把它当默认值**，判据：`grep -n 'FileSecretStore()' App/` 只能命中测试注入点，不许命中 `AppState` 的存储声明。

### 13.6 文档门禁的两条本端口径

- `audit_lld.py` 的测试 ID 定义面只认 §4.4 / §5.8 / §9.2 三节正文：用例只写进 §9.1 会被算成悬空，必须落 §9.2。
- `check-doc-tables.py` 会把「表格后紧跟一行普通散文」判成续行：每张表后面必须留空行或起新块。
