# Doyah产品开发计划任务清单 · macOS 端

> **版本** v1.0.24（2026-10-26 第二批：会话生命周期 Core 三件（归档 / 真删 / 重新导入）+ 结论可信度与出处契约（`Core/AgentClaimProvenance.swift`），24 例新判据，Core 3926 全绿；三条 ⬜ → 🟡，界面与循环接线待做。上一版 v1.0.23 = 斜杠命令闭环落地：`/help` `/clear` `/sessions` `/stop` 本地执行进输入框、`/model` `/theme` 只出单待批 + 单行审计（11 例新判据）；同批核对回填流式网关 ✅。上一版 v1.0.22 = 本册升为唯一任务清单：吸收原产品级清单 §3 台账 / §4 里程碑 / §6 能力快照；产品级总单按令删除，历史段归档；跨端矩阵改派生件。上一版 v0.10（2026-10-26 P1-7~P1-11 / P2 / P3 / P4 落地：90 例新判据，Core 面全绿）

> **口径登记（2026-10-25 人类主人令）**：① 四条共性能力（工程与工具链 / 授权与版本 / 插件装配 / 命令行出口）**归属 Studio 面**，按《能力规划说明书》§4.1.35 / 4.1.38 / 4.1.39 / 4.2.35 计，需求书 §3.1 只作归档位置（两书不计双份）；② `Docs/requirement-index.jsonl` 口径与《需求索引》一致 = **438 条**（FR 379 · NFR 47 · AC 12）；§5 数据需求与 §6 接口需求的 15 条**按书里原文不入总账**（它们属设计层，家在两份设计书），连同 §8.1 风险 55 / §8.2 待决 4 / 模型字段表等，共 76 条带编号但非总账的行由生成器逐类报数。

## 0. 元信息

- 读者：承担 macOS 端开发任务的 Agent 与人。
- **唯一上游（活书）**：**《Doyah产品详细设计说明书 · macOS端》** —— `Docs/Doyah产品详细设计说明书-macOS.md`（v1.0.10，文件名不带版本号的那份）；次上游：需求规格书（`FR-*`，438 条编号）> 概设。
- **本文件是 macOS 端唯一任务清单**（2026-10-26 人类主人令：任务清单按端分册、与详设同构，不设产品级总单）：
  §3 台账是每条 `FR-*` 的 macOS 状态唯一来源；批次表（§2 与 §4–§5）只负责把 `⬜` / `🟡` 排成可执行的活。
  跨端等价矩阵已降为派生件（`.build/derived/平台矩阵.md`，由 `Scripts/gen-platform-parity.py` 重生成）。
- 估时口径：**按条 25 分钟起**（含改代码 + 判据 + 门禁 + 出包）；复合条目单独给数。助手是执行体，不是外包排期。
- 本文件不写：跨端行为判据（在概设）、函数级实现（在详设）、测试读数快照（在台账）。

## 1. 基线读数（2026-10-23；P1 批次 2026-10-25 计入 P1-9~11 三条设计先行任务）

| 项 | 读数 | 出处 |
|---|---|---|
| 功能需求总数 | **378** 条 `FR-*`（另有 NFR 47 / AC 12） | 计划书 §5 矩阵行数 |
| macOS ✅ | **142**（38%） | 同上（v0.8） |
| macOS 🟡 | **87**（23%） | 同上 |
| macOS ⬜ | **149**（39%） | 同上 |
| 能力层规模 | `Core/` 248 个 .swift · `App/` 127 · `Platform/macOS/` 8 · `CLI/` 4 | 详设 v1.1 §0 |
| 测试规模 | `Tests/` 304 文件 · Core 全量 **3926** 例 | `.build/core-test-count.txt` |
| 现行包 | `dist/DoyahStudio-beta1.0.app` · sha256 前缀 `b329174d19384271` · **92,856 KB**（2026-10-26 18:16 重出·ad-hoc 封签完整；`nm` 在包内二进制数到 72 个 `AgentSessionLifecycle` / `AgentClaimProvenance` 符号 ⇒ 本批真编进了包；`~/Applications/` 副本同 sha 已换；稳定签名待证书信任） | `Scripts/build-app.sh` |

分族读数：

| 族 | 条数 | ✅ | 🟡 | ⬜ | 说明 |
|---|---|---|---|---|---|
| FR-AGT（智能体） | 82 | 64 | 15 | 3 | 2026-10-26 第二批实测（**原表写 68 条是旧读数**，按 `requirement-index.jsonl` 实测 82）：核心闭环 + 压缩边界 + 注册表真源 + 钩子 + 权限/刹停 + 知识治理 + 文档摄取/语音出 + **斜杠命令闭环（FR-AGT-UX-CONV-014 / FR-AGT-UX-CONV-015）/ 流式模型网关（FR-AGT-LINK-CHAN-002）** 已绿；同批把会话生命周期与结论可信度三条推到 🟡（Core + 24 例判据，界面/循环接线待做）；剩麦克风、§3.20 编排、MCP 对端、子代理执行器与需真端点的条目 |
| FR-STD（Studio 工作台） | 210 | 121 | 56 | 32 | 数据库主链已通；编辑面与文件系统大片空白 |
| FR-NTS（笔记） | 19 | 6 | 12 | 1 | **实现在本仓** `Plugins/Notes/`：26 个 .swift + 12 个测试文件约 195 例（含云同步 E2E）；仅「私密保护」未做 |
| FR-RTR（复盘） | 82 | 0 | 0 | 82 | **实现归 `retro` 仓**，本端只做宿主视图 |

## 2. 已完成（✅ 129 条，按模块）

| 模块 | 覆盖内容 | 判据出处 |
|---|---|---|
| 数据库执行主链 | 连接 / 执行 / 取消 / 只读保护 / 手工事务 / 结果渲染（STD-DB-CONN·EXEC·RES 主体） | 详设 §3.1–3.5 · §9.1 测试表 |
| 数据库元数据 | 对象树、下钻、DDL 查看、结构编辑基础（STD-DB-META 主体、DDL 部分） | 详设 §3.7–3.10 |
| 智能体核心 | 自然语言 → SQL、工具注册表、审批主链、导出到授权目录（AGT-LOOP-001/003/005、GUARD-PERM-001） | `AgentPlanRowsTests` 9/9 · `AgentAuditTests` · 真库 217 |
| 对话界面 | 会话列表与切换、会话内搜索、`⌘K` 智能体分组、转写区语汇、代码块语法着色 | `AgentSessionHistoryTests` 8/8 · `CommandPaletteTests` 36/36 |
| 工作台界面骨架 | 活动栏 / 页签 / 命令面板 / 主题令牌 / 关闭确认 / 窗口标题 | `WorkspaceSessionTabKindTests` 3/3 · `check-design-tokens` |
| 授权呈现 | 能力位驱动入口显隐、降级提示 | `LicensePresentation` + 手工点验 |

## 3 需求状态台账

> 一行 = 一条需求。`层次` 与 `优先级` 以需求规格说明书为定义处，本文件跟版；`状态原值` 保留迁出时的写法（含证据后缀）。
>
> **`版本` / `版本口径`（2026-10-20 立）**：本表同时是**版本范围台账** —— 每条需求归到哪个版本（`v0.1.0-alpha` / `v1.0` / `v1.1+` / `未排期`），
> 归到 `v0.1.0-alpha` 的写 `—`；不归 alpha 的必须写清口径（原因或出处节）。
> 「本版做不做」从此只看这两列，**不再在需求书正文里写 `[alpha 不含]` 括注**（旧账 `Scripts/alpha-fr-dispositions.json` 已并入本表并退役）。
> 判据：`Scripts/check-version-scope.py`（版本 ⊆ 台账、口径非空、覆盖率下限）。

| 编号 | 一句话 | 领域 | 层次 | 优先级 | 状态 | 状态原值 | 版本 | 版本口径 |
|---|---|---|---|---|---|---|---|---|
| FR-RTR-MKT-HEALTH-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-ORCH-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-MARKET-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-AI-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-FEATURE-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCREEN-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-006 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-006 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-CAPTURE-001 | — | 3.5 Doyah Notes | 基线必备 | — | 🟡 | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-FORMAT-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-ATTACH-001 | — | 3.5 Doyah Notes | 常用增强 | 中 | 🟡 | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-SEARCH-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-ORG-001 | — | 3.5 Doyah Notes | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-ORG-002 | — | 3.5 Doyah Notes | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-VERSION-001 | — | 3.5 Doyah Notes | 基线必备 | — | 🟡 | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-TRASH-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-SYNC-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-SYNC-002 | — | 3.5 Doyah Notes | 常用增强 | 高 | 🟡 | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-EXPORT-001 | 导出与迁移：导出 Markdown / 纯文本 / 备份包，导入自己导出的包可完整还 | 3.5 Doyah Notes | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-NOTE-PRIVACY-001 | 私密保护：可把单条笔记标为私密（不进搜索、不同步、不外发），需二次验证才可查看 | 3.5 Doyah Notes | 基线必备 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| AC-ALL-GATE-AI-01 | — | 7.4 智能体验收 | — | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| AC-ALL-GATE-AI-02 | — | 7.4 智能体验收 | — | — | ✅ | ✅ 已接线（T-57；真实实例端到端待执行） | v0.1.0-alpha | — |
| AC-ALL-GATE-AI-03 | — | 7.4 智能体验收 | — | — | ✅ | ✅ 已接线（T-57；真实实例端到端待执行） | v0.1.0-alpha | — |
| AC-ALL-GATE-AI-04 | — | 7.4 智能体验收 | — | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-01 | — | 7.1 发布门槛 | — | — | ✅ | ✅ 89/89（2026 | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-02 | — | 7.1 发布门槛 | — | — | ✅ | ✅ SwiftPM `P | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-03 | — | 7.1 发布门槛 | — | — | ✅ | ✅ 28/28（2026 | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-04 | — | 7.1 发布门槛 | — | — | 🟡 | 🟡 连接与查询已实测；对 | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-05 | — | 7.1 发布门槛 | — | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-06 | — | 7.1 发布门槛 | — | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-07 | — | 7.1 发布门槛 | — | — | ✅ | ✅ | v0.1.0-alpha | — |
| AC-ALL-GATE-REL-08 | — | 7.1 发布门槛 | — | — | ✅ | ✅ v1.1 已核对 | v0.1.0-alpha | — |
| FR-AGT-LINK-CHAN-001 | 模型接入配置：可配置模型服务（本地 / 远端，OpenAI 兼容端点）、模型名、AP | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-PLAN-CLAR-001 | 主动澄清：开跑前遇到目标不清 / 缺关键参数 / 两种做法代价差很大时，先问一句再动 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v1.1+ | `Core/AgentClarificationGate`：目标无动词/缺关键参数/代价差≥3 倍才问，其余直接干（判据 10 例） |
| FR-AGT-PLAN-PLAN-004 | 计划修订：执行中发现原计划不成立时，说出为什么改并给出新计划，不静默换路 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | `Core/AgentPlanRevisionLog`：改道必带触发事实与理由，缺一拒收；可机械查出静默换路（判据同上） |
| FR-AGT-GUARD-SOUL-001 | 灵魂分层：L0 角色（我是谁）· L1 领域角色（在这个领域我是谁）· L2 项目做 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | L0/L1/**L2 项目层**齐了（`Core/AgentSoul` 扩 L2，路径 `.doyah/soul-project.md`）；L2 可选、缺不算缺陷、被拒如实报、不得覆盖 L0（判据 6 例） |
| FR-AGT-TOOL-INGEST-001 | 网络检索：按关键词检索公开网页并给出可点开的来源，能区分「搜到标题」与「读到正文」 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-INGEST-002 | 文档解析：把 PDF / Word / Excel / 图片里的文字取出来参与推理， | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-INGEST-003 | 图像理解：把截图 / 图片交给支持视觉的模型，并把「模型不能看图」当成一种明确失败 | 3.2 Doyah Agent | 进阶可选 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MEDIA-001 | 语音输入：把一段语音转成文字再进对话，转写错误可回看原文 | 3.2 Doyah Agent | 进阶可选 | 低 | 🟡 | 🟡 | v0.1.0-alpha | — |
| FR-AGT-TOOL-MEDIA-002 | 语音输出：把回答读出来，可中断、可调语速 | 3.2 Doyah Agent | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SYS-001 | 界面操作：驱动本机图形界面完成点击 / 输入 / 滚动，每一步可见、可中断 | 3.2 Doyah Agent | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SYS-002 | 子任务委派：把独立子任务派给子代理并行做，结果汇总回主任务并标明来源 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 编排契约与来源标注已落（`AgentOrchestrator`），**真实子代理执行器未接**（worker 由调用方注入） |
| FR-AGT-TOOL-SYS-003 | 命令执行：跑一条命令带回 stdout/stderr/退出码，后台可中断 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | `Core/AgentCommandExecutor`：真起进程带回 stdout/stderr/退出码，超时默认 60s 可配、可取消、截断可见（判据 8 例，含超时/取消/截断/越界不起进程） |
| FR-AGT-TOOL-SYS-004 | 命令执行边界：仅授权目录、危险形态进审批、超时 60s 可配 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | 同一 executor 先过工作目录与越界参数判据；危险形态仍走 `AgentCommandPolicy` + 审批（判据同批 8 例） |
| FR-AGT-TOOL-SYS-005 | 代码执行：受限目录跑多行代码，沙箱/无网/超时/截断 | 3.2 Doyah Agent | 基线必备 | 中 | ✅ | ✅ | v1.1+ | `Core/AgentCodeRunner`：受限目录 + `sandbox-exec` 无网剖面 + 60s 超时 + 输出截断（判据 7 例，含真进程语法错/缺依赖/超时/无网） |
| FR-AGT-TOOL-SYS-006 | 代码执行依赖口径：只用本机已装、缺库如实报、不联网装 | 3.2 Doyah Agent | 常用增强 | 低 | ✅ | ✅ | v1.1+ | 依赖口径：缺库/缺解释器原样带回 stderr 并给原因码，不联网装（判据见到 `ModuleNotFoundError` 记 `missingDependency`） |
| FR-AGT-TOOL-SYS-007 | 并行编排：多路无依赖子任务并行，逐路结局并按来源归并 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | `Core/AgentOrchestrator`：并发上限可配、逐路结局（completed/failed/timedOut/needsApproval）、一路失败不拖垮全批（判据 5 例） |
| FR-AGT-TOOL-SYS-008 | 编排归并口径：只收摘要与产物路径；需审批回主控 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 归并口径：主控只收摘要 + 产物路径 + 来源标签；待批回主控（`approvalFingerprint`） |
| FR-AGT-TOOL-MODEL-001 | 模型多档：按任务选档（看图 / 调工具 / 上下文长度 / 语种 / 价格），未标注 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MODEL-002 | 档位端点与模型名可预填且可改（预设是起点不是锁） | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-007 | 中途干预：执行中可插话（改方向 / 停手 / 追加约束），当前步完成后立刻生效 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-008 | 主动通知：长任务完成、出错、需要人决定时主动告知（不让人守着屏幕） | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | `Core/AgentNotifyPolicy`：长任务≥30s / 失败 / 待人拍板才叫；人正看着这一页不弹；必须打断类除外（判据 8 例）——**系统通知与页内提示条的界面接线待做** |
| FR-AGT-UX-CONV-009 | 求助通道：卡住时能明确说「我需要你做一件事」（授权 / 提供信息 / 人工操作），并 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | `Core/AgentHelpRequest`：授权 / 信息 / 亲手做一步三类，必带「要什么 + 为什么 + 给完从哪接」，空话判 `isActionable=false`——**对话里的卡片接线待做** |
| FR-AGT-GUARD-PERM-003 | 隔离执行：任何执行都在受限环境内（工作区沙箱 / 命令白名单 / 出网策略），越界即 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-OPS-OBS-001 | 可观测：每一次模型调用、工具调用、审批与耗时都留有可查记录，能回答「它刚才为什么这么 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-OPS-OBS-002 | 可配置：模型、工具白名单、审批策略、配额、通知规则都可配置，且改完立即生效并有据可查 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | `Core/AgentConfigStore`：六项配置（模型 / 并发 / 命令超时 / 日配额 / 通知 / 工具白名单）带区间校验、改动必带理由、只追加留痕、快照即时生效（判据 6 例）——**设置面板接线待做** |
| FR-AGT-OPS-OBS-003 | 可评测：能用一组固定任务回归「它有没有变笨」，输出可对比的通过率 | 3.2 Doyah Agent | 进阶可选 | 低 | ✅ | ✅ | v1.1+ | `Core/AgentEvalHarness`：固定用例（contains / equals / fails 三种期望），输出 `pass n/N (x%)`，可 `regressions(against:)` 指出这次掉了哪几条；一条挂不中断整批（判据 5 例） |
| FR-AGT-UX-SYNC-001 | 多端一致性：同一会话在桌面与手机上看到的消息、审批与结论一致（壳不同，内容同） | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-007 | 及时刹停：识别到伤害性动作（删库 / 覆盖未备份文件 / 对外发布）时前置停止 —— | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-001 | 自然语言 → SQL：基于当前连接 schema 生成 SQL，结果进入编辑器不自动 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-001 | 对话式诊断：解读执行计划、慢查询与锁阻塞，给出可执行建议 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 |
| FR-AGT-PLAN-PLAN-001 | DBA 维护任务编排：由自然语言描述生成并执行维护任务（备份 / 恢复、VACUUM | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 |
| FR-AGT-PLAN-PLAN-002 | 自然语言 specs → 数据任务：把规格说明转成可执行任务定义（源 / 转换 / | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SCHED-001 | 定时调度：为数据任务设置一次性 / 周期性调度，客户端运行时按计划执行 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-002 | 数据生成 / 合成数据：按 specs 生成测试数据（行数、分布、约束满足），可导出 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：合成数据面板界面点击待人工点验（真机往返已验）|
| FR-AGT-CORE-LOOP-003 | 导出到指定目录：任务产物导出到用户选择的授权目录（由用户在选择器中指定，授权可跨启动 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-GUARD-PERM-001 | 执行审批与审计：智能体发起的写操作 / DDL / 外部动作逐次审批（可配置只读模式 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-LINK-EXT-001 | 互操作接口（MCP 双向）：① 作为 host 接入外部 MCP 服务器 | 3.2 Doyah Agent | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | host 方向仍为批处理式且 resources/read 未做；真 MCP 对端待外部实例 |
| FR-AGT-PLAN-PLAN-003 | specs 版本化与重跑：specs 与任务定义可保存、版本化、diff、回滚、重跑 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：界面点击待人工点验|
| FR-AGT-GUARD-PERM-004 | 安全护栏：智能体不得超越当前连接权限 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | 语句级判定 + 注入不当指令（同批判据 15 例） |
| FR-AGT-KNOW-MEM-001 | 查询记忆层（补全优先）：从已归档的 .sql 文件派生查询记忆（结构指纹 / 频次 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-KNOW-MEM-004 | 参数化与技能候选：把「同一条 SQL 的不同取值」归并成带参数槽位的模板 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 参数化与技能候选：出现≥2 次才成候选 |
| FR-AGT-KNOW-MEM-002 | 记忆治理（可检视 / 可删除 / 可解释 / 生命周期按类型分）：记忆可浏览原文与来 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v1.1+ | 记忆治理：可检视/可解释/删除即真删（AgentKnowledgeTests） |
| FR-AGT-LINK-CHAN-002 | 模型网关扩展（对话侧）：在既有 OpenAI 兼容 LLMClient（现为非流式、 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v1.1+ | **核对后回填**（原文列 ⬜ 是台账滞后）：六条验收要点各有判据 —— ① 请求体 `stream`+`tools`+合法 `tool_choice`（`LLMStreamTests.testRequestBodyCarriesStreamToolsAndLegalToolChoice`）② SSE 逐块拼接与整段逐字一致、`[DONE]` 后不再读（`testChunkedParsingMatchesTheWholeStreamVerbatim` / `testNothingIsReadAfterDone`）③ 用量记录进审计（`testToolCallFragmentsAreAssembledAndUsageIsReported` + `makeModelCall`）④ 本地端点不带 `Authorization`（`testLocalEndpointRequestCarriesNoAuthorizationHeader`）⑤ 门控关掉不发请求（`AgentInvocationGateTests`）⑥ 中途断流抛错不回半截（`testInterruptedStreamThrowsInsteadOfReturningAHalfReply`）。生产路径已接：`AgentLoop(client:)` 收 `LLMStreamingClient`，`AppState` 传 `OpenAICompatibleStreamingClient()`（聊天与 CLI 两条路都是）。`Tests/LLMStreamTests` 共 10 例 |
| FR-AGT-UX-CONV-002 | 对话会话：多轮上下文（消息 / 工具调用 / 审批 / 引用）按工作区持久化，可回放 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：会话持久化已接线（每跳落 .jsonl）；**界面回放需人工点验**|
| FR-AGT-CORE-LOOP-004 | Agent 循环：模型 → tool_calls → 执行 → 结果回灌 → 继续 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：五条验收要点机器可判且全绿（两跳 / 步数上限 / 令牌上限停在发送之前 / 取消留痕 / 未登记与坏参数不执行，判据 13 例）；面板上点「停止」的手感与三种停止提示的观感只能人工点验|
| FR-AGT-CORE-LOOP-005 | 工具注册表（唯一出处）：内置工具与 MCP 工具的统一注册表 —— 每个工具一处声明 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 注册表唯一真源：同名两处停装载（T-3.22-01 绿） |
| FR-AGT-CORE-LOOP-006 | 内置工具 8 个：read_file / list_dir / search（只读， | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | MVP 六个工具已真验五个：`read_file` / `list_dir` / `search` 由人类主人在 App 里点过；`write_file` / `edit_file` / `run_command` 由 `Tests/AgentToolFaceEndToEndTests`（11 例）真落盘、真起进程验证（未批不写、越界拒、大文件截断如实标）。仅 `query_db` 待真库。`read_notes` / `fetch_url` 按需求书属第二批，登记在册未启用（如实拒，不假装能做）。 |
| FR-AGT-LINK-EXT-002 | MCP client（用户自配 server 面）：配置 name / transp | 3.2 Doyah Agent | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 七条验收要点机器可验的部分全绿（配置面 / 握手 → tools/list → tools/call / 名字与参数原样 / enabled=false 不起进程 / 工具级审批 / 未配与连不上如实报 / http 如实报不支持，判据 15 例含真进程端到端）；界面配置面已落并由 Core 判据 20 例守着（加 / 删 / 开关、逐工具开关、文本⇄配置换算）；真 MCP server 端到端与面板点击观感只能人工点验 |
| FR-AGT-CORE-CTX-001 | 上下文供给与边界：@文件 / @目录 / 选中代码 / 当前页签 / 终端尾部 / | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 上下文供给：AgentContextSupply 五类来源 + 分类预算 + 去重 + 稳定序（6 例） |
| FR-AGT-GUARD-PERM-002 | 权限与审批：为新工具定义等级（只读 / 可写 / 可执行）+ 路径沙箱 + 命令白名 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v1.1+ | 配置面：等级/根/白名单 + 非法拒绝并说明（AgentPermissionBoundaryTests 10 例） |
| FR-AGT-GUARD-SOUL-002 | 审计扩展：留痕覆盖到每一次模型调用（含 Agent 循环每一跳，不只工具调用）+ 成 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v1.1+ | §4.1 明示 v1.1+ 核对结论：已落地（台账此前记 ⬜ 是漏记）—— `AgentActionRecord.makeModelCall` 逐跳留痕（AgentLoop 3 处调用点）+ 成本字段（model/endpoint/prompt/completion/total/duration）+ `AgentAuditLog.exportJSON/exportCSV`（`csvColumns` 17 列即白名单，导出前 `AgentAudit.redacted` 脱敏）与 `AgentBudgetReport` 聚合；`Tests/AgentAuditCostTests` **6 例**（两跳 2 模型 + 1 工具、字段齐、键集合恰等白名单且不泄密） |
| FR-AGT-UX-CONV-003 | 对话 UI = Home 区新开页签（占工作区主要区域，不是侧栏）：消息流 · 流式 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：对话页签五项已落（位置 / 流式 / 卡片（含模型与端点）/ 内联审批 / 一步撤销）；界面点击与观感需人工点验|
| FR-AGT-KNOW-MEM-005 | 技能库（skills）：可复用的技能 = 声明式登记（名称 + 适用面 / 触发 + | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 技能库：候选/删除/导出同批判据 |
| FR-AGT-TOOL-SCHED-002 | 定时 agent：为对话 / agent 任务设置一次性或周期性调度，客户端运行时按 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：定时 agent Core 两片 + App tick 与面板已交付；面板真点一遍与「停用后假端点收 0 次请求」的集成取证归人工点验|
| FR-AGT-GUARD-COST-001 | 门控（省 token 的调用门控）：在触发与模型调用之间有一道判定 —— 没有变化 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 门控已交付（同指纹不重复发请求、挡下留痕可导出）；**界面「仍然发送」按钮待接**，端到端需真实端点 |
| FR-AGT-KNOW-MEM-003 | 对话记忆（跨会话的长期记忆）：可检视 / 删除 / 解释 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 对话记忆：upsert 同键覆盖、导出稳定 |
| FR-AGT-UX-CONV-004 | 回边（生产化三件）：模型调用的失败分级与重试 / 退避 + 观察结果回灌（执行结果作 | 3.2 Doyah Agent | 常用增强 | 高 | ✅ | ✅ | v1.1+ | `Core/AgentFailureClassifier`：三档（可重试 / 需人处理 / 不该重试）+ 各自处置（退避秒数 / 求助单 / 停并说明），已接 `AgentLoop` catch（连败读数带 `tier:`）；观察结果回灌沿用工具结果通道（判据 7 例 + 既有 5 例重试判据不回归） |
| FR-AGT-UX-CONV-005 | 回边（生产化四件）：工具 / 命令并发 + 完成判据（自检）+ 长跑监控 + 调用链 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：四件（并发 / 完成判据 / 长跑监控 / 调用链）已落、判据 17 例；告警的界面观感与真端点上的长跑行为只能人工点验|
| FR-STD-ALL-BLD-001 | 从声明式工程描述生成构建工程，可重复生成（生成器属平台实现） | 3.1.1 工程与工具链 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-002 | 生成后自动修复本地包 product 关联（避免 Missing package p | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-003 | Core 逻辑单元测试可一条命令运行 | 3.1.1 工程与工具链 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-004 | 不打开 Xcode 也能产出可运行的 .app | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-005 | 提供依赖镜像脚本应对国内网络 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-006 | 提供本地端到端链路验证（无需外部数据库） | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-007 | 提供真实 PostgreSQL 连接验证脚本 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-008 | 工程可被命令行构建工具直接编译（不依赖图形 IDE） | 3.1.1 工程与工具链 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-BLD-009 | 配套文档随代码同步维护，需求变更可追溯 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-CLI-001 | 提供 DoyahCLI，可在无 UI 环境下验证连接与执行 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-CLI-002 | 支持环境变量连接参数：PGHOST/PGPORT/PGUSER/PGPASSWORD | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-CLI-003 | 支持 -c "SQL" 执行任意 SQL | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-CLI-004 | 支持 --tree 打印对象树，--columns 附带列类型 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-CLI-005 | 失败时返回非零退出码，便于脚本判定 | 3.1.1 工程与工具链 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-007 | 以列表展示全部已保存连接，可选中，选中项作为后续执行 / 元数据的上下文 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-001 | 新建连接：名称、数据库类型、主机、端口、数据库名、用户名、密码、SSL 模式、超时 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-002 | 数据库类型切换时，默认端口、默认 SSL 模式、默认 schema 自动联动 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-008 | 编辑连接：不得出现「点编辑却弹出新建、字段为空」 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-009 | 删除连接：需二次确认，并同时清理系统凭据存储中的密码与连接缓存 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-003 | 配置校验：名称、主机、端口（1–65535）、用户名非空 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-017 | 密码存入系统凭据存储，不写入配置文件 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-018 | 编辑连接时密码留空 = 保持原密码不变 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-021 | 「测试连接」真实连接服务器，返回 server_version / 当前库 / 当前 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-004 | 连接配置带 schemaVersion，为将来配置格式升级预留迁移能力 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-010 | 记忆上次选中的连接，重启后恢复该选中项 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-015 | 查询工具栏上方提供「当前服务器」选择器：枚举已保存连接（名称 + 地址），切换后作为 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-016 | 服务器选择器右侧提供「当前数据库」下拉框：枚举当前服务器上当前登录用户有权限访问的数 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-011 | 连接在界面上的显示名 = 名称 (登录用户名)：连接名后括注登录账号，用于侧边栏连接 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-012 | 连接分组 / 文件夹：连接可归入自定义分组，侧边栏按组折叠展示，便于按「项目 / 环 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 2026-09-27 点验未过：折叠状态活不过一次活动栏切换，已开队列 L-59，修完复验 |
| FR-STD-DB-CONN-013 | 连接颜色与环境标签：可为连接指定颜色与「生产 / 预发 / 测试」标签，侧边栏与查询 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-014 | 只读连接与启动 SQL：可把连接标记为只读（客户端拒绝执行写语句） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-020 | SSH 隧道：通过 SSH 跳板连接不可直连的数据库（密码 / 私钥两种方式） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 仅剩真跳板机的真实握手待环境（「沙箱下不能起 ssh」那条已随 2026-09-29 拍板消解） |
| FR-STD-DB-CONN-005 | 连接 URL 导入 / 导出：支持 postgres://user@host:por | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-006 | 连接保活心跳：空闲连接按间隔发送轻量查询，避免被防火墙 / 中间件掐断长连接 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DATA-001 | 对象树双击表 / 视图节点 → 新建页签并执行「浏览前 N 行」（SELECT * | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DATA-002 | 表行数统计与条件过滤入口：一键 count(*) | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面呈现待人工点验 |
| FR-STD-DB-DATA-003 | 生成 SQL 模板：按表结构生成 SELECT 列清单与 INSERT … VALU | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DATA-004 | 结果集内联编辑（改单元格 / 新增行 / 删除行），提交前预览将执行的 DML，确认 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DATA-005 | 单行详情 / 单元格值编辑器：宽表与长 JSON 竖排查看，JSON 值格式化显示 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-DATA-006 | 外键引用导航：由单元格 / 行跳转到被引用表并自动带入条件 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-DDL-001 | 由列定义生成 CREATE TABLE（列名 + 类型 + NOT NULL），用于 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DDL-002 | 生成 DROP TABLE / TRUNCATE TABLE（DROP 默认带 IF | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DDL-003 | 表结构编辑器：可视化增删列、改类型、加索引与约束，并实时对照将要执行的 DDL （v | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面呈现待人工点验 |
| FR-STD-DB-DDL-004 | Schema 对比与同步：对比两个库 / 两个连接的结构差异并生成同步脚本 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-DDL-005 | ER 图 / 关系图：由外键生成可视化关系图 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DIAG-001 | 执行计划查看：对当前 SQL 执行 EXPLAIN（可选 ANALYZE / BUF | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DIAG-002 | 计划摘要：顶部一行给出节点数、规划 / 执行耗时、全表扫描处数、最慢节点，一眼看出瓶 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DIAG-003 | 慢查询排行：pg_stat_statements 按总耗时 / 平均耗时 / 调用次 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 本机 pgserver 精简构建无扩展目录 → pg_stat_statements 装不上 |
| FR-STD-DB-DIAG-004 | 数据库统计面板：表大小、索引命中率、连接数、缓存命中率等 pg_stat_* 指标 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-DIAG-005 | 锁与阻塞链定位：基于 pg_locks + pg_blocking_pids() 展 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-005 | 定义稳定的 DatabaseService 协议：连接、断开、执行（流式事件）、取消 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-006 | 执行结果以事件流返回：started / resultSet / affectedR | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-007 | 工厂按数据库类型返回实现 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-008 | PostgreSQL 驱动使用成熟的协议实现，版本固定（依赖锁文件 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-001 | SQL 方言协议：标识符引用、分页子句、库/模式/表/列清单、版本号查询与解析、关键 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-002 | 语句拆分按方言：PostgreSQL 跳过 dollar-quote | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-003 | 拆分器只识别边界，不改写 SQL 原文 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-009 | GBase 8a 驱动实现（复用 MySQL 协议系的协议实现，具体库属平台实现） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低（排期最后） | 🟡 | 🟡 | v1.1+ | 无 GBase 8a 实例（方言层与驱动已实现，未端到端验） |
| FR-STD-DB-DRV-010 | MySQL 驱动实现：DatabaseType 新增 mysql 档（默认端口 33 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-001 | 多页签：新建（⌘T）、切换、关闭 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-VCS-001 | Git 只读与差异：显示当前工作区的分支、改动文件清单与逐行差异（不做提交 / 推送 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-TOOL-003 | 调试器：经 DAP 接入既有调试器，支持断点、单步、变量查看（不自研调试协议） | 3.3 Doyah Studio · 工作区 | 进阶可选 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-AI-002 | 许愿式编程：用一段话描述要做的事，Agent 在整个工作区范围内多次读写文件后交付可 | 3.3 Doyah Studio · 工作区 | 常用增强 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-015 | 整批撤回：一次任务内的多处文件改动可按批次一次撤回，只撤 Agent 改的、不动人手 | 3.3 Doyah Studio · 工作区 | 常用增强 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-FS-009 | 外部改动监听：文件被编辑器外的程序改动时，界面立即反映并提示重新载入或对比 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-FS-010 | 工作区切换：可在多个已知工作区之间切换，同一时刻只有一个活动工作区（不做并发多根） | 3.3 Doyah Studio · 工作区 | 常用增强 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-WEB-003 | 网页文件可在编辑器内切「预览」渲染（不是只能看源码） | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-WEB-004 | 站点兼容：对站点呈现常规浏览器身份 | 3.3 Doyah Studio · 工作区 | 常用增强 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-ALL-LIC-001 | 许可证解析与能力位（离线签名校验） | 3.1.2 授权与版本 | 基线必备 | 高 | 🟡 | 🟡（代码与 23 项单测在，未人工验收） | v0.1.0-alpha | — |
| FR-STD-ALL-LIC-002 | 按授权呈现入口 + 「版本与许可证」页 | 3.1.2 授权与版本 | 基线必备 | 高 | 🟡 | 🟡（代码与 23 项单测在，未人工验收） | v0.1.0-alpha | — |
| FR-STD-ALL-LIC-003 | 到期降级与数据归属（不锁数据） | 3.1.2 授权与版本 | 基线必备 | 中 | 🟡 | 🟡（代码与 23 项单测在，未人工验收） | v0.1.0-alpha | — |
| FR-STD-ALL-LIC-004 | 授权范围口径（桌面三块一套 / 移动端不在管辖） | 3.1.2 授权与版本 | 基线必备 | 中 | 🟡 | 🟡（口径已落为能力位定义，未人工验收） | v0.1.0-alpha | — |
| FR-STD-ALL-LIC-005 | 设备配额与设备管理（默认 5 台 / 可释放） | 3.1.2 授权与版本 | 常用增强 | 低 | 🟡 | 🟡（模型与剩余台数在，释放设备交互未验） | v0.1.0-alpha | — |
| FR-STD-WS-NAV-001 | 语法着色：关键字 / 函数 / 字符串 / 注释 / 数字 / 引用标识符分别配色（ | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-007 | 客户端静态检查：未闭合字符串、未闭合块注释、未闭合 dollar-quote、括号不 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-008 | 静态检查基于当前方言的关键字与函数表 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-009 | 服务器端语法检查：「检查」按钮对可 EXPLAIN 的语句执行 EXPLAIN，不真 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-010 | 检查结果：通过显示「已检查 N 条，跳过 M 条」 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-011 | 修改 SQL 后清空上一次检查结果 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-014 | 执行入口为工具栏图标按钮（绿色实心三角形 ▶），不使用文字按钮 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-003 | SQL 自动补全（关键字 + 内建函数） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-SESS-001 | 查询历史（按连接记录，可回填） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-CONN-019 | 密码等敏感输入使用 ASCII 安全字段，避免输入法干扰 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-024 | 大脚本保护：超长 SQL 暂停静态检查，避免输入卡顿 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-007 | SQL 编辑区与结果区之间提供可拖拽分隔条，用户可实时调整两区高度（放大 / 缩小结 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-001 | 工具栏在执行按钮之前提供「保存查询」按钮：把当前页签的 SQL 持久化保存（可命名） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-FS-007 | 工具栏新增「打开文件」按钮：通过系统打开面板选择 SQL / 文本文件，内容载入新建 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-002 | 工具栏保存按钮拆分：主体 = 直接保存（有文件路径则写回磁盘 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-003 | 工具栏新增「编辑」按钮（下拉菜单入口），菜单包含：查找 / 替换、跳到指定行或列、缩 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-010 | 编辑菜单 → 查找 / 替换：在当前 SQL 中查找与替换文本 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-011 | 编辑菜单 → 跳到指定行或列：输入行号（可选列号）后光标定位并滚动到可见位置 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-018 | 编辑菜单 → 缩进 / 反缩进选中文本（多行按行处理） | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-004 | 编辑菜单 → 清除查询：一键清空当前页签 SQL | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-013 | 编辑菜单 → 格式化 SQL：对当前 SQL 做关键字大写、子句换行与缩进 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-HELP-001 | 工具栏新增「帮助」按钮（问号图标），承载帮助入口 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-002 | 新建查询页签的编号在应用生命周期内单调递增（1、2、3…），不受页签被关闭、重命名或 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-005 | 命令面板：⌘K 唤起，可搜索并执行「新建查询 / 执行 / 检查 / 格式化 / 导 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-WS-UI-008 | 主题与字体：浅色 / 深色跟随系统或手动指定，编辑器等宽字体与字号可调 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 主题三态 / 字体字号观感需人工看一眼 |
| FR-STD-WS-EDIT-016 | 多光标与列编辑：⌥ 拖拽 / ⌘D 增加光标，一次修改多处（进阶） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-WS-EDIT-005 | 工具栏与菜单的快捷键全覆盖：工具栏每个按钮都有快捷键，tooltip 显示按键 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-TOOL-001 | 底部终端面板：主窗口底部可拖拽 / 可折叠的面板，内嵌本机交互式 shell（真 P | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | sixel / kitty 图形未做；界面未人工验收（多会话页签的界面与判定均已交付、待点验）；「沙箱下 ^C 不可靠」那条已随 2026-09-29 拍板消解 |
| FR-STD-WS-TOOL-002 | 工作区下方面板（应用级通用面板）：页签为 问题 / 输出 / 终端 / 调试控制台 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-001 | 查询自动归档：执行过的 SQL 自动保存成 .sql 文件，按天一个文件（queri | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-FS-002 | 活动栏 + 工作区 Explorer：主窗口最左侧加一条窄的固定宽度活动栏（46pt | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-009 | 外观配置：主题（配色方案）+ 强调色：主题跟随系统外观（浅色原生精致 / 深色专业暗 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-010 | 页签条高度不由内容与数量决定（空白同高、多了横向滚动） | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | — | v0.1.0-alpha | — |
| FR-STD-WS-UI-011 | 编辑面底色字色只用主题令牌（三处编辑面同底） | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | — | v0.1.0-alpha | — |
| FR-STD-WS-UI-012 | 背景壁纸与层次（四列连续无接缝；浮层/对话框 ≥0.9 不透明衬底；关壁纸回落纯色；侧栏按活动项派生） | 3.3 Doyah Studio · 工作区 | 基线必备 | 中 | ✅ | — | v1.0 | 2026-10-25 浮层衬底改系统不透明控件底色、折叠按钮移标题栏；`db29c037` |
| FR-STD-WS-UI-013 | 行内动作悬停出、常驻不占位（未悬停动作数为 0、行宽不变） | 3.3 Doyah Studio · 工作区 | 基线必备 | 中 | ⬜ | — | v1.1+ | v1.1 起 |
| FR-STD-WS-UI-014 | 对话框按钮用系统文字按钮（Sheet/Form 内无纯图标按钮，取消为 role: .cancel） | 3.3 Doyah Studio · 工作区 | 基线必备 | 中 | ⬜ | — | v1.1+ | v1.1 起 |
| FR-AGT-UX-CONV-010 | 界面语汇跨端一致（行首栏字形 / 正文必渲染 / 描边只给要人动手的卡） | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：待人工点验|
| FR-AGT-UX-CONV-011 | 统一字号与状态行字段序（模型名与就绪态永不丢、无读数整段消失、花费不上状态行） | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：待人工点验|
| FR-AGT-UX-CONV-012 | 九个显示开关（流式/紧凑/思考段/时间戳/工具进度/指示字形/长消息预览/底栏元数据/运行中提交） | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | — | v1.1+ | 开关未全部接线 |
| FR-AGT-UX-CONV-013 | 流式未闭合口径（围栏前照常渲染、围栏起原文照发、收尾不抖、复制给源码） | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | 2026-10-26 人工点验通过（人类主人确认）；此前读数：6 例单测已过，待实机|
| FR-STD-WS-WEB-001 | 内嵌浏览器页签（工作区，完整浏览器）：在工作区新增可关闭的浏览器页签（与 Home、 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | GUI 点击与下载观感待人工点验 |
| FR-STD-WS-FS-001 | 工作区视图有自己的页签集，默认打开 Home 欢迎页：在活动栏切到「工作区」时，编辑 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面切换与点击待人工点验 |
| FR-STD-WS-FS-008 | 在工作区里点文件直接打开，并按文件类别匹配呈现：文本 / 代码文件在编辑器区打开 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-WS-UI-006 | 窗口标题跟着活动栏走 + 标题栏居中的搜索栏：主窗口标题随活动栏当前视图变化（Doy | 3.3 Doyah Studio · 工作区 | 常用增强 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-WS-NAV-002 | 多语言关键字高亮方案（语言表可扩展 + 每语言一套高亮规则 + 颜色走主题令牌）：① | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | Beta 1 全量语种未落；Alpha 2 必做的「前 10」已落 —— 未落的半边与切主题 / 切深浅的观感都不在本 alpha 范围 |
| FR-STD-WS-NAV-014 | 代码格式化能力：对当前工作区文件按语言格式化（编辑器菜单 / 快捷键入口），格式化前 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 代码格式化的界面点击与观感待人工点验（形态已订正为**只用内置**：不探 `PATH`、不联网；认不出语言与规则空转都如实拒绝） |
| FR-STD-WS-AI-001 | 工作区编辑区的 AI 辅助编程（需求提出者 2026-09-30 定：「编辑区如何接 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-FS-003 | 工作区 Explorer 的文件操作（需求提出者 2026-09-30：「现在的工作 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-012 | 跨文件内容搜索与替换（同「非常单薄」的量化结果：Core/WorkspaceSear | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-WS-UI-004 | 会话恢复（同「非常单薄」的量化结果：App/WorkspaceTabsModel.s | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 第二片「光标 + 滚动」未交付（在飞 t_849ac541）；第一片「页签集会话恢复」已交付（锚仓 99cc05b） |
| FR-STD-WS-EDIT-013 | 工作区标头的搜索框（快速查找文件标题与内容关键字）（需求提出者 2026-09-30 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 工作区标头搜索框的界面点击与观感待人工点验（分组与顺序 / 键盘行走 / 行号换算 / 跳过计数已有 30 条 Core 判据；「点下去真的跳到那一行」需人看） |
| FR-STD-WS-WEB-002 | 工作区编辑器的 Markdown 预览（需求提出者 2026-09-30 原话：「工 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-UI-003 | 关闭有未保存改动的文件页签：确认，不阻塞（需求提出者 2026-10-03 原话：「 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 关闭有未保存改动的页签 = 确认框：界面点击待人工点验（规则层有 8 例 Core 判据（7 条规则 + 1 条源码判据）—— 干净页签不弹框 / 脏页签弹且动作与顺序固定 / 取消不关 / 保存失败不关 / 丢弃必关；真点关闭按钮看到框、三个动作各点一遍需人看） |
| FR-STD-WS-EDIT-006 | 工作区 Markdown 的列表续行：回车接着写下一项（需求提出者 2026-10- | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | Markdown 列表续行的界面回车手感待人工点验（规则层有 17 例判据含续行各组；真在编辑器里按回车接着写下一项需人看） |
| FR-STD-WS-EDIT-007 | 工作区 Markdown 的任务框勾选翻转（⌘L）（同上由头）：在 Markdown | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | Markdown 任务框勾选翻转（⌘L）的界面按键待人工点验（规则层判据同上；界面 9 步见清单 §10.33） |
| FR-STD-WS-EDIT-019 | 括号 / 引号自动配对与跳引号：打出 ( [ { " ' 反引号 ⇒ 自动补右半并把 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | Core 逻辑（配对 / 跳引号 / 包选区 / 删整对）与判据已交付；**手感需人工点验**（补不补、光标是否在中间、退格是否删整对、Markdown 里引号是否不补） |
| FR-STD-WS-EDIT-020 | 括号匹配高亮：光标紧邻括号时，与它配对的另一个括号同时点亮（走主题令牌，不写死颜色） | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-008 | 注释切换（⌘/）：按当前语言的注释符给光标行加 / 取消行注释 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | Core 逻辑（注释符只从语言表来、空行不动、取消时连空格一起去掉）与判据已交付；**手感需人工点验**（⌘/ 在中文输入法下是否按键正常） |
| FR-STD-WS-EDIT-009 | 移行与复制行：⌥↑ / ⌥↓ 把当前行（或选中整段）整体上移 / 下移，光标与选区跟 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-021 | 自动缩进与智能粘贴：回车时继承上一行缩进 | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-022 | 缩进检测与状态栏切换：打开文件时按内容判定软 / 硬 tab 与宽度（不靠扩展名猜） | 3.3 Doyah Studio · 工作区 | 常用增强 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-017 | 代码折叠：按语言块级规则折叠函数 / 块 / 区域，行号槽给折叠标记 | 3.3 Doyah Studio · 工作区 | 常用增强 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-012 | 静态检查结果上屏（诊断）：把 FR-STD-WS-NAV-007 已实现的检查（未闭合字符串 / | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-004 | 自动补全接线与扩展：补全在编辑器内真的可触发（FR-STD-WS-NAV-003 的 SQL 关键 | 3.3 Doyah Studio · 工作区 | 常用增强 | 高 | 🟡 | 🟡 | v1.1+ | 行内灰字（词法 / SQL / 路径三路）实现全落、行为判据全绿；观感与手感（画法 / 出现时机 / Tab 接受顺不顺手）只能人工点验 |
| FR-STD-WS-NAV-006 | 悬停文档与跳转到定义（词法级起步）：悬停给一句话说明 + 定义位置 | 3.3 Doyah Studio · 工作区 | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-NAV-005 | 片段模板（snippets）：按语言给片段（SQL 的 select / join | 3.3 Doyah Studio · 工作区 | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-014 | 撤销语义粒度：一段连续输入合并成一次撤销（不逐字符），行级编辑（移行 / 注释切换 | 3.3 Doyah Studio · 工作区 | 常用增强 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-002 | 按当前连接与上下文栏所选数据库执行 SQL，支持多语句 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-DRV-004 | 字符串、注释、dollar-quote 内的分号不得触发拆分 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-003 | 每条语句按顺序执行，逐条上报执行状态 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-009 | 多结果集：全部保留，可通过下拉选择器切换查看 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-010 | 显示行数 × 列数与耗时 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-011 | 显示 SQL 错误详情，可选中复制 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-012 | 执行中的页签不可关闭 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-018 | 「停止」取消当前执行 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-004 | 同一连接的并发执行复用同一个连接，避免重复握手 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-013 | 执行返回「影响行数」（DML command tag） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-015 | 提供事务 API：beginTransaction / commit / rollb | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-005 | 空 SQL 或未选连接时给出明确提示而非静默失败 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-016 | 查询工作区提供图标按钮工具栏，承载常见数据库客户端操作（执行 / 停止 / 检查，后 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-006 | 执行目标判定：有选区只跑选中的那段，没有选区跑整篇 —— 自动判定，不需要用户先设「 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-007 | 事务模式：提供「自动提交」开关与提交 / 回滚按钮 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-017 | 高危语句保护（Safe Mode）：对不带 WHERE 的 UPDATE / DEL | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-EXEC-008 | 查询参数：SQL 中可用 :name / $1 占位符，执行前弹窗填值并做类型化转义 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-IO-001 | 结果集导出：CSV / JSON / TSV / Markdown / INSERT | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-IO-002 | 客户端侧整表 / 整库导出：走 COPY <表> TO STDOUT 流式写文件 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | vendor 驱动只实现 CopyFrom，缺 COPY … TO STDOUT |
| FR-STD-DB-IO-006 | CSV / JSON 导入：COPY … FROM STDIN 流式导入 + 列映射 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-IO-003 | 备份 / 恢复：封装 pg_dump / pg_restore（plain / cu | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 仅剩 217 专用库的真实还原待外部实例（「沙箱下起子进程的临时例外待拍板」那条已随 2026-09-29 拍板消解） |
| FR-STD-DB-IO-004 | 备份文件恢复到指定库（pg_restore 的 --clean / --sectio | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-IO-007 | Excel（.xlsx）导入映射向导 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工；真实软件（Excel / Numbers）产出的文件待人工 |
| FR-STD-DB-IO-005 | 导出 CSV 的文本编码可选：UTF-8（带 BOM，默认）/ GB18030（GB | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-001 | PostgreSQL 树形结构：服务器 → Database → Schema → | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-002 | GBase 8a 树形结构：服务器 → Database → Table → Col | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 无 GBase 8a 实例 → 端到端 0 次 |
| FR-STD-DB-META-003 | 懒加载：仅展开节点时查询下一层 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-004 | 自动过滤系统 schema（information_schema、pg_catalo | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-009 | 列节点显示数据类型 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-005 | 节点类型区分图标（库 / 模式 / 表 / 视图 / 列 / 函数） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-013 | 元数据查询有行数上限保护（10,000 行） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-014 | 元数据加载失败给出错误提示，不阻塞 UI | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-006 | 对象树必须支持持续下钻：从服务器节点开始，Database → Schema → T | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | 🟡 | 🟡 | v1.1+ | 界面未点（展开 / 空态 / 失败态三步已在待人工验收清单 §5） |
| FR-STD-DB-META-007 | 跨数据库浏览：服务器节点展开后列出当前用户可连接的数据库 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | 🟡 | 🟡 | v1.1+ | 失败隔离与重试步骤待人工点验 |
| FR-STD-DB-META-010 | 对象树右键菜单（第一期：仅服务器节点）：右键「服务器」节点提供 ① 连接、② 断开、 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-015 | 全库对象搜索：输入名称片段即跨 schema / 跨库匹配表、视图、列、函数，命中结 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-META-011 | 查看对象 DDL：表 / 视图 / 函数节点右键「查看 DDL」，展示等价建对象语句 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面呈现待人工确认 |
| FR-STD-DB-META-012 | 表 / 视图 / 列节点右键菜单（第二期）：浏览前 N 行、生成 SELECT / | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-META-008 | 对象树按类型 / schema 分组视图：可在「层级视图」与「按类型分组」之间切换 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-ALL-PLUG-001 | 笔记插件以同进程内模块装配（不做独立进程 + IPC、不做可卸载组件包） | 3.1.3 插件装配 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-002 | 活动栏出现「笔记」一项 | 3.1.3 插件装配 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-003 | 宿主向插件单向传上下文（当前连接、库 / 表、选中 SQL） | 3.1.3 插件装配 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-004 | 笔记数据落在本工程数据家之外（独立目录），备份与清理策略各自独立 | 3.1.3 插件装配 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-005 | Linux 端装配笔记，且必须是本地离线实现：数据只落本机 SQLite（笔记自己的 | 3.1.3 插件装配 | 基线必备 | 高 | 🟡 | 🟡 | v1.1+ | 验收要点 ①③④未做（源码在本仓，按平台口径非本侧） |
| FR-STD-ALL-PLUG-006 | 许可证一套覆盖三个能力位（开发工作区 / 智能数据库助理 / 笔记），不做插件独立授 | 3.1.3 插件装配 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-007 | 允许插件复用宿主词法层（CodeSyntax / CodeLexer / CodeC | 3.1.3 插件装配 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-ALL-PLUG-008 | 桌面各端笔记存储统一到本地 SQLite（2026-09-27 拍板 Q23）：主存 | 3.1.3 插件装配 | 基线必备 | 高 | 🟡 | 🟡 | v1.1+ | 界面点击点验待人工；打包项按平台口径非本侧 |
| FR-STD-DB-RES-001 | 结果表格使用平台原生表格控件桥接，支持大结果集滚动 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-002 | 列宽按内容估算，可拖动调整，可重排列顺序 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-003 | 支持多选行，⌘C 与右键菜单复制 | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-004 | NULL 与空字符串可区分显示 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-005 | 二进制 / 复杂类型单元格转为可读字符串 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-010 | 结果导出为 CSV / JSON 文件 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-011 | 结果集分页 / 虚拟滚动超大数据量 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 大表实测待人工（NFR-ALL-GATE-PERF-002 的阻塞） |
| FR-STD-DB-RES-007 | 客户端排序：点表头按列排序，支持多列（次要排序键）、升降序切换、NULL 位置固定 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-RES-008 | 客户端筛选：每列可加条件（包含 / 不包含 / 等于 / 大于 / 小于 / 为空 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-RES-009 | 分页控制条：选择每页行数（50 / 100 / 200 / 500 / 1000）， | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-RES-012 | 导出扩展格式：TSV（表格软件友好）、Markdown 表格（贴文档 / 工单）、S | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-RES-006 | 复制为多种格式：复制即带表头，或直接是 Markdown / INSERT 文本（不 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面粘贴待人工点验 |
| FR-STD-DB-RES-013 | 超大结果集流式落盘：导出直接写文件，不把全量结果驻留内存 | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-RES-014 | 结果集导出 Excel（.xlsx） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | Excel / Numbers 打开需人工（外部软件） |
| FR-STD-DB-SESS-002 | 服务器会话列表：展示当前实例的会话（进程号 / 用户 / 数据库 / 客户端地址 / | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-SESS-003 | 取消 / 终止会话：对选中会话执行「取消当前语句」（PG pg_cancel_bac | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-SESS-004 | 服务器级对象管理：数据库 / 角色 / 表空间 / 扩展的浏览与创建（DBA 日常） | 3.4 Doyah Studio · 数据库 | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-STD-DB-SESS-005 | 权限管理：查看角色对库 / schema / 表 / 序列的已授权限 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-STD-DB-SESS-006 | 库属性管理：ALTER DATABASE（owner / 库级参数 / 连接限制）与 | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-001 | 外发最小化：默认只发 schema 摘要 + 当前语句 | 4.8 AI 智能体 | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-002 | 可降级：无模型 / 未授权 / 网络不可用时，客户端全部既有功能完整可用 | 4.8 AI 智能体 | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-003 | 可审计：每次调用留存模型、请求摘要、耗时、结果状态，可导出 | 4.8 AI 智能体 | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-004 | 成本与配额：提供 token / 调用次数上限与超时 | 4.8 AI 智能体 | 常用增强 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-005 | 可复核：智能体产出（SQL / 任务定义 / 建议）均以文本形式可查看、可编辑、可 | 4.8 AI 智能体 | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-006 | 本地模型优先：支持 OpenAI 兼容的本地端点（如 Ollama / vLLM）， | 4.8 AI 智能体 | 常用增强 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-007 | 会话持久化与长上下文（压缩 / 检查点） | 4.8 AI 智能体 | 常用增强 | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| NFR-ALL-GATE-AI-008 | 长上下文压缩与检查点（State / Checkpoint）：会话跑到第 N 跳要能 | 4.8 AI 智能体 | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-COMP-004 | 支持 macOS 14 / 15 及后续版本 | 4.5 NFR-COMP | 基线必备 | — | 🟡 | 🟡（待验证） | v0.1.0-alpha | — |
| NFR-ALL-GATE-COMP-005 | 支持 Apple Silicon 与 Intel | 4.5 NFR-COMP | 基线必备 | — | 🟡 | 🟡（待验证） | v0.1.0-alpha | — |
| NFR-ALL-GATE-COMP-001 | 支持 PostgreSQL 12–18 多版本回归 | 4.5 NFR-COMP | 基线必备 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-COMP-002 | 支持 GBase 最新版本，并向下兼容至 GBase 8a（版本窗口见下） | 4.5 NFR-COMP | 进阶可选 | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| NFR-ALL-GATE-COMP-003 | 支持 MySQL 最新大版本，并向下兼容最近 5 个大版本（版本窗口见下） | 4.5 NFR-COMP | 常用增强 | — | ⬜ | ⬜ | v0.1.0-alpha | — |
| NFR-ALL-GATE-LANG-01 | v1.x 界面语言为简体中文 | 4.7 国际化 | 常用增强 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-LANG-02 | 预留英文文案抽取（不硬编码在视图里为长期目标） | 4.7 国际化 | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-LANG-03 | 国际化：界面语言支持简体中文 / English 切换，用户可选、选择持久化、重启后 | 4.7 国际化 | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-001 | 核心逻辑单元测试：拆分、方言、配置序列化、静态检查、tokenizer、元数据映射、 | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-002 | 新增数据库类型不改动 UI 层代码 | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-003 | 关键行为有脚本化回归（本地 PostgreSQL 全链路） | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-004 | 代码注释说明「为什么」而非「是什么」（如 -disable-sandbox 的原因） | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-005 | README 与实现同步（含未实现清单） | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-MAINT-006 | 需求可追溯到实现文件与验证方式 | 4.6 NFR-MAINT | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-001 | App 冷启动到可交互 ≤ 2 s（本机 SSD） | 4.1 NFR-PERF | 基线必备 | — | 🟡 | 🟡（待验证） | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-002 | 1 万行 × 20 列结果集渲染与滚动无可感卡顿 | 4.1 NFR-PERF | 基线必备 | — | 🟡 | 🟡（待验证） | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-003 | 10 万行结果集不得 OOM | 4.1 NFR-PERF | 基线必备 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-004 | 元数据单层懒加载在局域网内 ≤ 1 s | 4.1 NFR-PERF | 基线必备 | — | 🟡 | 🟡（待验证） | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-005 | 语法着色与静态检查在 5,000 行 SQL 内保持输入流畅 | 4.1 NFR-PERF | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-PERF-006 | 连接超时默认 5 s，可配置 | 4.1 NFR-PERF | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-REL-001 | 任何 SQL 错误不得导致 App 崩溃或数据丢失 | 4.2 NFR-REL | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-REL-002 | 执行失败后可继续在同一连接上执行下一条语句 | 4.2 NFR-REL | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-REL-003 | 配置文件写入使用原子写，避免半截文件 | 4.2 NFR-REL | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-REL-004 | 配置文件损坏时给出可读错误，不静默清空 | 4.2 NFR-REL | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-REL-005 | 页签在异步回调中被关闭时不得下标越界 | 4.2 NFR-REL | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-001 | 密码存储：不得写入连接配置文件 | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-002 | 连接配置文件不包含密码 | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-003 | 启用平台沙箱（若该平台有），仅申请网络客户端与用户选择文件的读写权限 | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-004 | 启用 Hardened Runtime | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-005 | （v3.2 修订）默认零外发 | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-006 | 支持 PostgreSQL SSL 六种模式（disable / allow / p | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-007 | 删除连接时同步删除系统凭据存储中的凭据 | 4.3 NFR-SEC | 基线必备 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-SEC-008 | 统一外发日志：所有离开本机的网络请求（智能体模型调用、内嵌浏览器导航与子资源、外部程 | 4.3 NFR-SEC | 基线必备 | — | 🟡 | 🟡 | v0.1.0-alpha | — |
| NFR-ALL-GATE-UI-001 | 界面设计语言统一：同一产品内各平台（macOS / Windows / iOS / | 4.9 NFR-UI | 基线必备 | — | ⬜ | ⬜（待落地） <!-- contract-change：登记面漏项补齐（bluewhale v3.323 落笔时未同步 §10.1 索引行）· 依据 = 人类主人 2026-10-08 令「走 A」（让 Studio 闭环可达绿） --> | v0.1.0-alpha | — |
| NFR-ALL-GATE-USE-001 | 常用操作有快捷键：执行 ⌘↩、复制 ⌘C、新建查询页签 ⌘T、表单保存 ↩ | 4.4 NFR-USE | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-USE-002 | 错误文案使用中文，说明「哪里错、怎么办」 | 4.4 NFR-USE | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-USE-003 | 长任务有进行中状态与可取消入口 | 4.4 NFR-USE | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-USE-004 | 界面为原生 macOS 观感（NavigationSplitView、系统控件） | 4.4 NFR-USE | 常用增强 | — | ✅ | ✅ | v0.1.0-alpha | — |
| NFR-ALL-GATE-USE-005 | 走不动的动作必须挑一种处置（灰着/给理由/不可达），禁第四种形状 | 4 非功能需求 | 基线必备 | 高 | ⬜ | — | v0.1.0-alpha | — |
| FR-RTR-MKT-FEED-001 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-001 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FEED-002 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FEED-004 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FEED-005 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-STORE-001 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FEED-003 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-PROFILE-001 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-PROFILE-002 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-PROFILE-003 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-CRON-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-CRON-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-HEALTH-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-HEALTH-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-003 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-004 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-003 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SCENARIO-005 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-004 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-005 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-006 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-007 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-008 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-ATTR-009 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-005 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-006 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-007 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-008 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-CRON-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-005 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-006 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-007 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-008 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-QUERY-009 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-REPORT-009 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-FLOW-CRON-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-005 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-006 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FUND-001 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FUND-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FUND-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-FUND-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-007 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-008 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-002 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-003 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-004 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-BACKTEST-009 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-RSR-SAMPLE-005 | — | 3.6 Doyah Retro | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-STORE-002 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-004 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-STORE-003 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-005 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-MKT-STORE-004 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-RTR-REV-TRADE-006 | — | 3.6 Doyah Retro | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-SESS-001 | — | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-008 | — | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-009 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | 未排期 | 新增：单次任务预算 150 步 / 256K（能力书 3.1.1 · S-15） |
| FR-AGT-CORE-LOOP-010 | 工具按需发现：检索目录 → 取 schema → 调用，未取回不许调用 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v1.1+ | `Core/AgentToolDiscovery`：检索→取 schema→调用三段记账，**没取 schema 调用即拒**；空目录/查不到如实说（判据 6 例） |
| FR-AGT-CORE-LOOP-011 | 工具目录口径：内置+接入两类、schema 可缓存、空目录如实说 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.0 | v1.0 已交付（注册表真源 + 可见性由 profile 决定） |
| FR-AGT-PLAN-PLAN-005 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-PLAN-PLAN-006 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-KNOW-CTX-001 | — | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-KNOW-CTX-002 | — | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-EDIT-001 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-LINK-CHAN-003 | — | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-LINK-EXT-003 | — | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-006 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-014 | 斜杠命令：`/help` `/model` `/clear` `/compact` `/sessions` `/theme` `/stop`，本地执行不进模型 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | 🟡 | v1.1+ | 解析 `Core/AgentSlashCommandParser`（8 例）+ 落地形状 `Core/AgentSlashCommandRuntime`（11 例，`Tests/AgentSlashCommandRuntimeTests`）；**输入框已接线**（`AgentChatModel.send()` 抢在排队之前判定，命令不进模型 / 不占队列）：`/help` 出清单、`/clear` 清上下文（`AgentChatState.clearTranscript()`，不动盘上会话文件与授权）、`/sessions` 按标题检索、`/stop` 中断（没在跑如实说）。**边界如实**：`/compact` **无手动触发点**（压缩只在 `AgentLoop` 请求边界按预算自动发生）⇒ 命令只如实说、审计记 `noManualTrigger` |
| FR-AGT-UX-CONV-015 | 斜杠命令落地：大小写不敏感、可带参数、只留一行审计、改配置照走审批 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | 🟡 | v1.1+ | 大小写不敏感 / 带参 / 单行审计已判据化；**审批已接线**：`/model` `/theme` 只出单（`AgentSlashPendingChange` + 复用 `AgentApproval` 状态机），输入框上方给批准 / 拒绝，**批准之前不动配置**、先落审计再落地；审计一条命令一条（`AgentActionRecord.makeToolCall(toolName: slash)` 走既有追加通道，`executed` / `pendingApproval` / `denied` / `failed` 按事实写）。**落地能力边界**：`/theme` 真落（`AppState.appearanceMode`）；`/model` 本版**无落地入口**（归 `FR-AGT-OPS-OBS-002` 设置面板）⇒ 批准后如实说「没有写配置的入口」，不假装改过 |
| FR-AGT-UX-SESS-001 | 会话生命周期：**新建 / 归档 / 删除 / 导出** —— 删除即真删（不留副本），导出可带走 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | ⬜（Core 三件已落：归档 / 恢复 / 真删含续跑旁挂件 / 导出重新导入，`Core/AgentSessionLifecycle.swift` + `Tests/AgentSessionLifecycleTests` 10 例；界面入口未接） | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-001 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-002 | 跨小时不丢目标（`Core/AgentResumeBrief.swift` + `AgentCheckpoint.goalDigest`；`Tests/AgentResumeBriefTests` **11 例**） | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-003 | 不确定性表达：**不确定就说** —— 给出把握程度与依据，不把猜测说成事实 | 3.2 Doyah Agent | 基线必备 | 高 | 🟡 | ⬜（Core 契约已落：三态必填 + 低把握必须给替代方案，`Core/AgentClaimProvenance.swift` + `Tests/AgentClaimProvenanceTests` 14 例；对话循环尚未按 claim 产出） | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-004 | 断言可溯源：**每条结论能指到出处** —— 文件路径行号 / 命令输出 / 日志 / 文档链接，读者能自己复核 | 3.2 Doyah Agent | 基线必备 | 高 | 🟡 | ⬜（四类出处 + 可复制文本 + 同出处只标一次；`isDeliverable` 逐条判缺出处不进交付物，判据同批 14 例；交付物出口未按它拦） | v0.1.0-alpha | — |
| FR-STD-WS-FS-004 | — | 3.3 Doyah Studio · 工作区 | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-FS-005 | — | 3.3 Doyah Studio · 工作区 | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-FS-006 | — | 3.3 Doyah Studio · 工作区 | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-EDIT-023 | — | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-VCS-002 | — | 3.3 Doyah Studio · 工作区 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-WS-LIC-001 | — | 3.1 共性需求 | 基线必备 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-DB-DIAG-006 | — | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-DB-TASK-001 | — | 3.4 Doyah Studio · 数据库 | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-DB-TASK-002 | — | 3.4 Doyah Studio · 数据库 | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-STD-DB-TASK-003 | — | 3.4 Doyah Studio · 数据库 | 基线必备 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-NTS-TODO-LIST-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-LIST-002 | — | 3.5 Doyah Notes | 基线必备 | 高 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-LIST-003 | — | 3.5 Doyah Notes | 常用增强 | 中 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-CALENDAR-001 | — | 3.5 Doyah Notes | 常用增强 | 中 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-CALENDAR-002 | — | 3.5 Doyah Notes | 常用增强 | 中 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-STATE-001 | — | 3.5 Doyah Notes | 基线必备 | 高 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-STATE-002 | — | 3.5 Doyah Notes | 基线必备 | 高 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |
| FR-NTS-TODO-LINK-001 | — | 3.5 Doyah Notes | 常用增强 | 中 | 🟡 | ⬜ | 未排期 | 版本规划待概要设计完成后统一排（人类主人 2026-10-20 令） |

## 3. 半成品（🟡 75 条）—— 三类成因

| 成因 | 条数 | 处理方式 |
|---|---|---|
| **有代码缺判据**：功能在，没有可复跑的用例钉住 | ≈ 40 | 补判据，不改代码（每条 12 分钟） |
| **有入口缺闭环**：按钮/命令在，走到一半断（如上下文供给只接了部分来源） | ≈ 25 | 补齐闭环，再补判据（每条 25–40 分钟） |
| **文档滞后**：代码已做、需求书未标 ✅ | ≈ 10 | 核对后改需求索引状态，不改代码（每条 5 分钟） |

> 判 🟡 的具体条目见计划书 §5 矩阵的 macOS 列；本文件不复制那张表（避免两处漂移）。

## 4. 待开发批次（⬜ 174 条的 macOS 可执行部分）

### P1 · 智能体闭环（先让闭环能跑完，11 条 · ≈ 490 分钟）

| # | FR | 内容 | 估时 | 判据 | 依赖 |
|---|---|---|---|---|---|
| P1-1 ✅ | FR-AGT-CORE-SESS-001 | 会话持久化：关掉应用再开，能接着上次对话与进度 —— **已落地**（`Core/AgentTurnResumeStore.swift`，实测 **35 分钟**） | 40 | `AgentTurnResumeStoreTests` **9/9**：写读一致 / 身份不符当没有 / 坏文件不冒充 / 没跑过=absent / 覆盖不追加 / 清掉不残留 | 无 |
| P1-2 ✅ | FR-AGT-CORE-LOOP-009 | 单次任务预算：150 步 / 256K token，超限即停并留审计 —— **已落地**（`Core/AgentBudgetReport.swift`，实测 **15 分钟**） | 30 | `AgentBudgetReportTests` **7/7**：默认值就是 150/262,144（20 万旧口径判红）/ 触顶报「停在哪做完哪些」（跳数·完成·被拒·令牌）/ 续跑含进来前已花 / 千分位与 plainLine 双形态 / 完成·取消·配额三种停**不产出**预算报告 | 无 |
| P1-3 ✅ | FR-AGT-CORE-LOOP-008 | 队列：可查看排队、调序、取消未开始项 —— **已落地**（`AgentPromptQueue.moving(id:offset:)` + 排队行 ↑↓✕，实测 **20 分钟**） | 45 | `AgentPromptQueueTests` **11/11**：FIFO / 空串不入队 / 按 id 上移不动邻居 / 首末行夹紧不吞条目 / 未知 id 原样返回 / **取消后不出队、剩余仍 FIFO** | 无 |
| P1-4 ✅ | FR-AGT-PLAN-PLAN-005 | 完成判据：报完成必须附可检验判据 —— **已落地**（核查结论：`AgentCompletionVerifier` + `EVIDENCE:` 解析 + 界面判红早在仓里，16 例判据全绿；台账此前记 ⬜ 是错的） | 25 | `AgentCompletionVerifierTests` **16/16**：无引用判 `unverified:noEvidence` / 引用本次没发生判红 / 盘上变了判红 / 命令退出码不符判红 / 纯答问判 `notClaimed` / 循环级两条端到端 | 无 |
| P1-5 ✅ | FR-AGT-PLAN-PLAN-006 | 失败自恢复：可重试先重试，不可重试换路并说明 —— **已落地**（`AgentLoopLimits.maxConsecutiveFailures`/`fallbackModels` + 循环换路与连续失败停，实测 **35 分钟**） | 30 | `AgentLoopRecoveryTests` **4/4**：不可重试换到备用模型并跑通 / 备用表不乒乓（每模型只试一次）/ 连续失败到顶即停且报次数 / 默认值不改旧行为；`AgentLoopRetryTests` 5 例仍绿 | 无 |
| P1-6 ✅ | FR-AGT-QUAL-VERIFY-001 | 结果自验：产出前自查（能跑跑一遍、能对对一遍）—— **已落地**（`Core/AgentSelfCheck.swift` + 循环最后一跳折表，实测 **40 分钟**） | 25 | `AgentSelfCheckTests` **9/9**：写+跑都过 / 写没复核判红 / 退出码非 0 判红 / 无退出码判红 / 复核推翻记录 / **动过东西零自验 ⇒ skipped** / 纯问答 nothingToCheck / 只读不进分母 / 机器码形状 | 无 |
| P1-7 | FR-AGT-UX-CONV-006 | 过程可见：每一步工具/文件/命令都在界面可见 | 15 | 每一步都出现一行；无静默步 | 转写区已有 |
| P1-8 | FR-AGT-UX-CONV-007 | 中途干预：插话改方向 / 停手 / 追加约束 | 20 | 插话在当前步之后生效，不丢已产生结果 | P1-3 |
| P1-9 | FR-AGT-KNOW-CTX-002 | 压缩只在会话边界：回合内只出预算报告、不改写上下文 —— **契约已立（详设 §3.21 v1.8），实现未跟** | 60 | `T-3.21-01~03` 全绿：回合内压缩计数 0；边界压缩后决策仍可答；压完仍超限如实报 | 详设 §3.21 · P1-2 |
| P1-10 | FR-AGT-CORE-LOOP-005 / -011 | 工具注册表唯一真源 + 可见性由 profile 决定（壳不分叉实现）—— **契约已立（详设 §3.22），实现未跟** | 90 | `T-3.22-01~03` 全绿：重复声明停装载；不可见 ≠ 不存在；同一工具两壳同 handler | 详设 §3.22 |
| P1-11 | FR-AGT-CORE-CTX-001 / OPS-OBS-001 | 引擎生命周期钩子：五钩子、`onSessionEnd` 只在真实边界、失败不中断会话 —— **契约已立（详设 §3.23），实现未跟** | 120 | `T-3.23-01~03` 全绿：真实结束恰好一次；钩子抛错会话继续；回合内调 end 被拒 | 详设 §3.23 · P1-9 |

### P2 · 安全与权限（4 条 · ≈ 300 分钟）

| # | FR | 内容 | 估时 | 判据 |
|---|---|---|---|---|
| P1-11+ | FR-AGT-CORE-CTX-001（供给面） | `Core/AgentContextSupply.swift` | `AgentContextWiringTests` 6/6（五类来源 · 分类预算 · 去重 · 稳定序） | ✅ |
| P2-1 | FR-AGT-GUARD-PERM-002 | 配置面：等级 / 沙箱根 / 白名单如何声明 | 60 | 改配置立即生效；非法配置拒绝并说明 |
| P2-2 | FR-AGT-GUARD-PERM-003 | 运行时边界：任何执行都在受限环境内 | 120 | 越界路径被拒；判据来源 = P2-1 白名单 |
| P2-3 | FR-AGT-CORE-LOOP-007 | 及时刹停：伤害性动作前置停止（不建审批单、不执行） | 60 | 删库/覆盖/对外发布三类各一例 ⇒ 停 |
| P2-4 | FR-AGT-GUARD-PERM-004（🟡） | 语句级判定收口：危险语句与注入内容 | 60 | 危险语句判红；注入样本不被当指令 |

### P3 · 知识与记忆（6 条 · ≈ 180 分钟）

| # | FR | 内容 | 估时 | 判据 |
|---|---|---|---|---|
| P3-1 ✅ | FR-AGT-KNOW-CTX-001 | 项目上下文自动带上（工作区结构 / 分支 / 未提交改动）—— **已落地**（`Core/AgentGitFacts.swift` + `GitStatusProbe`，实测 **35 分钟**） | 45 | `AgentGitFactsTests` **9/9**：分支/ahead/behind/改动排序 · 无上游为 0 · 无分支行⇒nil · 空仓库归一 · 40 条上限且报丢弃数 · 摘要形状 · 排在目录前 · 只带摘要不带 diff · 无仓库不塞空段 |
| P3-2 | FR-AGT-KNOW-CTX-002 | 上下文压缩（超预算按段优先级截断并标记） | 40 | 截断处可见；两次压缩结果一致 |
| P3-3–6 | FR-AGT-KNOW-MEM-002/003/004/005（🟡） | 记忆治理 / 对话记忆 / 参数化与技能候选 / 技能库 | 95 | 可检视、可删除、可解释；删除即真删 |

### P4 · 工具面（12 条 · ≈ 420 分钟）

| 组 | FR | 估时 | 要点 |
|---|---|---|---|
| 编辑 | FR-AGT-TOOL-EDIT-001 | 45 | 按行/块改，给差异，不整文件重写 |
| 摄取 | FR-AGT-TOOL-INGEST-001/002/003 | 105 | 检索带可点来源；PDF/Word/Excel/图片解析；视觉不可用要明说 |
| 模型 | FR-AGT-TOOL-MODEL-001/002 | 60 | 多档 + 端点/模型名可预填 |
| 媒体 | FR-AGT-TOOL-MEDIA-001/002 | 90 | 语音进/出，转写原文可回看、可中断 |
| 系统 | FR-AGT-TOOL-SYS-001/002 | 120 | 界面操作每步可见；子任务委派标来源 |

#### P1~P4 本轮落地（2026-10-26 · 107 例新判据）

| 批次 | FR | 落点 | 判据（实跑） | 状态 |
|---|---|---|---|---|
| P1-7 | FR-AGT-UX-CONV-006 | `Core/AgentStepTrace.swift` + `AgentChat.apply` | `AgentStepTraceTests` 6/6；界面每跳一行、每次工具一行（就地收尾带耗时） | ✅ |
| P1-8 | FR-AGT-UX-CONV-007 | `Core/AgentIntervention.swift` + `AgentInterventionInbox` + 循环接线 | `AgentInterventionTests` 6/6 · `AgentLoopInterventionTests` 3/3（停手不再起跳、约束进下一跳、改方向换提示） | ✅ |
| P1-9 | FR-AGT-KNOW-CTX-002 | `Core/AgentCompressionAdmission.swift` | `AgentCompressionAdmissionTests` 8/8（T-3.21-01~03） | ✅ |
| P1-10 | FR-AGT-CORE-LOOP-005/-011 | `Core/AgentToolCatalogSnapshot.swift` | `AgentToolCatalogSnapshotTests` 8/8（T-3.22-01~03） | ✅ |
| P1-11 | FR-AGT-CORE-CTX-001 / OPS-OBS-001 | `Core/AgentContextEngine.swift` | `AgentContextEngineTests` 6/6（T-3.23-01~03） | ✅ |
| P2-1 | FR-AGT-GUARD-PERM-002 | `Core/AgentPermissionConfig.swift` | `AgentPermissionBoundaryTests` 10/10（改配置立即生效 / 非法拒绝带原因） | ✅ |
| P2-2 | FR-AGT-GUARD-PERM-003 | `Core/AgentSandboxBoundary.swift` | 同上（越界 / `..` 逃逸 / 只读根） | ✅ |
| P2-3 | FR-AGT-CORE-LOOP-007 | `Core/AgentPreActionStop.swift` | `AgentPreActionStopTests` 15/15（删库/覆盖/对外发布 ⇒ 停，不建审批单） | ✅ |
| P2-4 | FR-AGT-GUARD-PERM-004 | `Core/AgentSQLStatementJudge.swift` | 同上（危险语句判红；注入不当指令） | ✅ |
| P3-2 | FR-AGT-KNOW-CTX-002 | `Core/AgentContextPriorityTruncator.swift` | `AgentKnowledgeTests` 14/14（按优先级截断、标记可见、两次一致） | ✅ |
| P3-3~6 | FR-AGT-KNOW-MEM-002~005 | `Core/AgentMemoryGovernance.swift` | 同上（可检视/可解释/删除即真删/技能候选） | ✅ |
| P4-编辑 | FR-AGT-TOOL-EDIT-001 | `Core/AgentBlockEditor.swift` + 既有 `editFile` | `AgentToolFaceTests` 17/17；改走审批 + 陈旧锚点复检 + 租约（`AgentWorkspaceToolsTests`） | ✅ |
| P4-摄取 | FR-AGT-TOOL-INGEST-001/003 | `Core/AgentIngestion.swift` | 同上（可点来源；视觉不可用明说） | ✅ |
| P4-摄取 | FR-AGT-TOOL-INGEST-002 | `Core/AgentDocumentIngestor.swift` + `App/PDFTextExtractor.swift` | `AgentDocumentIngestorTests` 8/8（xlsx 真读 · docx 真读 · PDF 注入 PDFKit · 图片如实报） | ✅ |
| P4-模型 | FR-AGT-TOOL-MODEL-001/002 | `Core/AgentModelPresets.swift` | 同上（三档 + 预填校验） | ✅ |
| P4-媒体 | FR-AGT-TOOL-MEDIA-001/002 | `Core/AgentVoiceSession.swift` · `App/SpeechSynthesizer.swift` | 转写状态机 17/17；语音出已接 AVSpeechSynthesizer（可中断） | 🟡 仅麦克风未接（人类主人令「除了麦克风」） |
| P4-系统 | FR-AGT-TOOL-SYS-001/002 | `Core/AgentSubtaskDelegation.swift` | 每步可见 ✅；委派标来源的台账已就位 | 🟡 子任务依赖 §3.20 编排（未实现） |

> 读数口径：`swift test --filter <类名>` 实跑（Xcode 工具链）；全量 `Scripts/verify-core.sh` = **3793 项**。

### P5 · 通道与运维（7 条 · ≈ 240 分钟）

| 组 | FR | 估时 |
|---|---|---|
| 通道 | FR-AGT-LINK-CHAN-002/003、FR-AGT-LINK-EXT-003 | 90 |
| 运维 | FR-AGT-OPS-OBS-001/002/003 | 105 |
| 灵魂 | FR-AGT-GUARD-SOUL-001/002 | 45 |

### P6 · 工作台编辑面（STD 32 条 · ≈ 600 分钟）

| 组 | 条数 | 代表条目 | 估时 |
|---|---|---|---|
| 编辑语义 | 11 | 移行/复制行、撤销粒度、整批撤回、代码折叠、括号匹配、自动缩进、缩进检测、编码换行 | 240 |
| 文件系统 | 6 | Explorer 文件操作、新建、重命名、删除进废纸篓、外部改动监听、工作区切换 | 120 |
| 导航与诊断 | 4 | 片段模板、悬停与跳定义、静态检查上屏、调试器（DAP） | 120 |
| 版本控制 | 2 | Git 只读与差异、差异视图 | 60 |
| 网页 | 3 | Markdown 预览、HTML 预览、站点身份兼容 | 45 |
| 数据库任务 | 6 | 一句话→任务、高危逐条列出、执行回执、诊断入口、表任务定义 | 90 |

## 5. 🟡 收口（75 条 · 分批核判据）

| 批 | 范围 | 条数 | 估时 | 做法 |
|---|---|---|---|---|
| R1 | STD 族 🟡 中「有代码缺判据」 | ≈ 30 | 360 | 每条一个用例，不改行为 |
| R2 | STD 族 🟡 中「有入口缺闭环」 | ≈ 18 | 540 | 补闭环 + 判据 |
| R3 | AGT 族 🟡 19 条 | 19 | 480 | 上下文供给 / 循环 / 工具 / 门控 / 记忆 / 定时 / 诊断 |
| R4 | 文档滞后 | ≈ 10 | 50 | 核对后改需求索引 |

## 6. 跨仓项（不在本仓写码）

| 族 | 条数 | 归口 | 本端责任 |
|---|---|---|---|
| FR-RTR | 82 | `retro` 仓 | 宿主视图 `App/Views/RetroHostView.swift` + 包扫描路径 |

> RTR 的 macOS 列永远 ⬜ 直到 retro 仓实现——**不要把这 82 条算进本仓进度**。
>
> **订正（v0.2）**：FR-NTS 不属跨仓项。笔记实现就在本仓 `Plugins/Notes/`（`NoteLibrary` / `NoteDatabase` /
> `NoteAutosave` / `NoteSync` / `NotesPanel` / `NotesRichTextEditor`），并已与 Studio 装配联通（`AppState` 引用 `NotesPanel`）。
> v0.1 把整族记成「归 notes 仓、全 ⬜」是照抄了台账里未更新的状态 —— 台账 19 行已按代码事实改正并重生成 §5 矩阵。

## 7. 阻塞与依赖

| # | 阻塞项 | 影响 | 谁解 |
|---|---|---|---|
| 1 | 审批「过期 / 撤回」终局未定（概设 §6.3 只有三种） | P2 无法收口 | 人类主人 |
| 2 | 端云同步三端口径未定 | 多端一致性（FR-AGT-UX-SYNC-001）无从写 | 人类主人 |
| 3 | `FR-AGT-UX-CONV-009` 求助通道缺契约条款 | 只做了 UI 入口 | 契约侧 |
| 4 | 调试器需 DAP 客户端依赖 | STD-WS-TOOL-003 引入依赖需批准 | 人类主人 |

## 8. 已知红灯（背景账，不计工时）

| 项 | 现状 |
|---|---|
| `check-core-localization` 棘轮 A | 基线 730 → 实测 746；无授权不得 `--update-baseline` |
| `check-design-tokens` / `check-panel-root-frames` | 高于基线 |
| `browser-tab-ownership` / `editor-line-numbers` | 高于基线 |
| 判据数 426 vs 438 | 台账与实测不一致（历史遗留） |

## 4 里程碑与迭代

| 阶段 | 内容 | 状态 |
|---|---|---|
| M1 工程骨架 | XcodeGen 工程、Core framework、UI 骨架、沙箱与签名 | ✅ 完成 |
| M2 PostgreSQL 驱动 | PostgresNIO 接入、连接、执行、单元格格式化、CLI 验证 | ✅ 完成 |
| M3 查询工作区闭环 | 多语句执行、多结果集、状态与错误展示、客户端取消 | ✅ 完成 |
| M4 元数据对象树 | 懒加载、系统 schema 过滤、列类型 | ✅ 完成 |
| M5 编辑器与结果体验 | NSTextView 着色 + 静态检查 + EXPLAIN 检查；NSTableView 结果表格与复制 | ✅ 完成 |
| M6 真实服务器回归与文档 | 真机逐项回归（编辑连接、对象树、执行、复制、检查）；建立 SRS 基线 | 🟡 连接/执行已实测；其余回归中 |
| M7 多版本兼容 | 用本地 `pgserver` / Docker 跑 PostgreSQL 12–18 兼容矩阵 | ⬜ |
| M8 查询体验补充 | 查询历史、SQL 补全接入编辑器、结果导出 CSV/JSON、服务器端取消 | ⬜ |
| M8.1 工作区与选择器增强（2026-09-20 新增） | 服务器 / 数据库选择栏（权限过滤）、编辑区 / 结果区拖拽分隔、保存查询 SQL、对象树持续下钻修复、中 / 英语言切换 | ⬜（排在 M9 之前） |
| M9 GBase 8a | `GBaseService` + `GBaseMetadataService`（MySQLNIO），认证插件/版本/DELIMITER 实测 | ⬜（最后） |

**M6—M8 建议需求优先级**：FR-STD-DB-EXEC-018（服务器端取消）> FR-STD-DB-RES-010（导出）> FR-STD-DB-SESS-001（历史）> FR-STD-WS-NAV-003（补全接入）> FR-STD-DB-CONN-009（删除确认）> FR-STD-DB-CONN-003（校验复用）。

**M8.1 新增需求优先级（2026-09-20）**：FR-STD-DB-META-006（对象树持续下钻，先复现定位）> FR-STD-DB-CONN-015 / FR-STD-DB-CONN-016（服务器与数据库选择）> FR-STD-WS-EDIT-001（保存查询）> FR-STD-WS-UI-007（拖拽分隔）> NFR-ALL-GATE-LANG-03（中 / 英切换，依赖文案资源化）。

---

### 8.x v1.0 交付范围（已确认，2026-09-21）

依据 `Docs/调研书-主流数据库客户端基础功能.md` 的差距裁定（基线必备 57 条：22 条已覆盖 / 9 条需扩写 / 3 条需新增），建议：

| 范围 | 内容 |
|---|---|
| **v1.0 纳入** | ① 22 条**已覆盖**的基线能力（核对即可）；② 9 条**部分覆盖**的扩写（含 `DROP/ALTER DATABASE`、多窗口、`pg_dumpall`、对象树分组、角色改删、索引/外键管理、大结果流式）；③ 2 条**新增** DBA 能力（FR-STD-DB-SESS-005 权限管理、FR-STD-DB-DIAG-005 锁与阻塞链）；④ **基本智能体能力**：FR-AGT-LINK-CHAN-001 模型接入、FR-AGT-CORE-LOOP-001 自然语言→SQL（只读）、FR-AGT-PLAN-PLAN-002 specs→数据任务、FR-AGT-TOOL-SCHED-001 定时调度、FR-AGT-CORE-LOOP-002 数据生成/合成、FR-AGT-CORE-LOOP-003 安全作用域目录导出、FR-AGT-GUARD-PERM-001 审批与审计、FR-AGT-GUARD-PERM-004 安全护栏，以及 NFR-AI 全部与 AC-ALL-GATE-AI-01~04 |
| **v1.1+** | 常用增强 74 条中按使用频率挑选（连接分组/颜色、事务模式、查询参数…）；智能体进阶项：FR-AGT-UX-CONV-001 对话式诊断、FR-AGT-PLAN-PLAN-001 DBA 维护编排、FR-AGT-LINK-EXT-001 MCP 对外接口、FR-AGT-PLAN-PLAN-003 specs 版本化 |
| **不做** | 见需求书 §2.4（范围与本期不做） |

> 本表已于 **2026-09-21 经需求提出者确认**；按 §0.6 第 10 条，**冻结窗口自即日解除**，功能开发恢复。
> 后续若要调整 v1.0 范围，按 §0.6 第 9 条走需求变更流程（先改本表与需求条目，再动代码）。

### 4.1 智能体里程碑（规划中，需求条目待 v3.2 落位）

| 里程碑 | 目标角色 | 内容概要 | 状态 |
|---|---|---|---|
| **M-AI-1 接入与只读** | DBA · 数据应用开发者 | FR-AGT-LINK-CHAN-001 / 02 / 12 + NFR-ALL-GATE-AI-001 / 02 / 05：模型接入、自然语言→SQL（只进编辑器）、安全护栏；**只读、零信任外发** | **已纳入 v1.0** |
| **M-AI-2 任务与调度** | 数据应用开发者 | FR-AGT-PLAN-PLAN-002 / 06 / 07 / 08 + 审批（FR-AGT-GUARD-PERM-001）：specs→任务、定时调度、数据生成、目录导出 | **已纳入 v1.0**（依赖 M-AI-1） |
| **M-AI-3 DBA 编排与互操作** | DBA | FR-AGT-UX-CONV-001 / 04 / 10 / 11：对话式诊断、维护任务编排、MCP 双向接口、specs 版本化 | v1.1+（依赖 M-AI-2） |
| **M-AI-4 工作区对话式助手** | DBA · 数据应用开发者（工作区侧） | FR-AGT-LINK-CHAN-002 ~ 29 + NFR-ALL-GATE-AI-007：对话式 agent 循环全链 —— 模型流式与 `tools` / 会话按工作区持久化 / Agent 循环 / 工具注册表 / 内置工具 / MCP client / 上下文边界 / 权限审批 / 审计逐跳 + 成本 / **Home 区对话页签（不是侧栏）**；**M2 半（2026-10-11 令 · beta1 任务 3）** = 技能库 / 定时 agent + 门控 / 对话记忆（`FR-AGT-KNOW-MEM-005` ~ `29`）；契约见 `Docs/Doyah产品概要设计说明书.md` §3.1.21 | v1.1+（依赖 M-AI-1；人类主人 2026-10-10 / 2026-10-11 令） |
| **M-AI-5 回边（生产化）** | DBA · 数据应用开发者（工作区侧） | `FR-AGT-UX-CONV-004` / `FR-AGT-UX-CONV-005` + `NFR-ALL-GATE-AI-008`：**把最小 loop 的四要素接成闭环** —— 失败分级与重试 / 退避 · **观察结果回灌**（执行结果作下一跳输入，**整条 loop 的回边**）· 检查点续跑 · 工具 / 命令并发 · **完成判据（Verifier）** · 长跑监控 · 调用链可追溯；**先在既有底座上补边**（`Core/LLMClient.swift` 现为非 2xx 直接 `throw`；执行结果不回灌 —— 观测只进 `AgentAudit`），**不新造第二套**（重试复用模型通道 / 链路复用 `AgentAudit` / 配额复用 `AgentQuota`）；契约见 `Docs/Doyah产品概要设计说明书.md` §3.1.21 第 ⑧ 组（不变量 27 ~ 31）与 §8.8；实现计划见提案 `0009` | v1.1+（**与 M-AI-4 分条**：M-AI-4 = 对话式助手与工具面，M-AI-5 = 回边与生产化；依赖 M-AI-1；人类主人 2026-10-12 令「Demo 到生产 Agent……」） |

> 定位说明：本工程不重复造传统客户端的轮子，而是把「智能体」做成**与既有能力同一套权限体系**的一等公民——
> 智能体能用的，用户手动也能用；用户不能做的，智能体也不能做。

---

## 6 当前能力快照

| 能力 | 状态 | 说明 |
|---|---|---|
| 连接管理（增删改、Keychain、测试连接） | ✅ | PostgreSQL 真机18.6 验证通过；显示名为「名称 (登录用户名)」（FR-STD-DB-CONN-011） |
| PostgreSQL 查询执行 | ✅ | 多语句、多结果集、错误详情、客户端取消 |
| 元数据对象树 | ✅ | 服务器 → 数据库 → schema → 表 / 视图 → 列；系统 schema 过滤、列类型；展开非当前库时按需建立该库连接（真实库 UI 验收进行中）；服务器节点支持右键菜单（连接 / 断开 / 编辑连接 / 按权限呈现新建数据库，FR-STD-DB-META-010） |
| SQL 编辑器 | ✅ | 关键字紫色着色、静态检查、EXPLAIN 检查 |
| 查询工具栏 | ✅ | 图标按钮：保存查询 / 已保存列表 / 执行（绿色三角形）/ 停止（红色四方形）/ 检查；执行中按钮状态互换 |
| 服务器 / 数据库选择栏 | ✅ | 工作区顶部；服务器下拉与连接列表联动，数据库列表按权限过滤，选择结果决定查询目标库 |
| 编辑区 / 结果区拖拽分隔 | ✅ | `VSplitView`，两区最小高度 120 pt |
| 保存查询 | ✅ | 工具栏书签按钮命名保存 + 已保存列表回填；JSON 持久化，不含密码 |
| 国际化 | ✅ | 菜单「语言」可切简体中文 / English；选择持久化、默认跟随系统；界面文案全部走本地化表 |
| 页签编号 | ✅ | 应用生命周期内单调递增（1、2、3…），关闭 / 重命名页签不影响（FR-STD-WS-UI-002） |
| 打开 / 保存 SQL 文件 | ✅ | 打开文件到新页签（不绑定连接、标题 = 文件名）；保存主体写回 / 下拉箭头另存为；文件页签显示未保存圆点 |
| 编辑菜单（查找 / 替换 / 跳转 / 缩进 / 清除 / 格式化） | ✅ | 系统 Find Bar；跳到行列；缩进 4 空格；清除可撤销；保守格式化（4 项单测） |
| 帮助入口 | ✅ | 问号按钮 + 「帮助内容待补充」占位（正式内容待定） |
| 结果表格 | ✅ | NSTableView、列宽/重排、多选、⌘C TSV 复制 |
| 结果导出 | ✅ | CSV / JSON，`NSSavePanel` 选路径；CSV 带 BOM + RFC 4180 转义，JSON 含列定义（10 项单测） |
| 影响行数 | ✅ | INSERT / UPDATE / DELETE 显示影响行数（状态栏 + 结果区 + CLI） |
| 服务端取消 | ✅ | 独立连接执行 `pg_cancel_backend`；本地链路实测 `canceling statement due to user request` |
| SQL 补全 | ✅ | 方言关键字 + 内建函数；F5 / Esc / ⌃Space 触发 |
| 查询历史 | ✅ | 内存态（上限 50 条，不落盘）；时钟菜单回填 / 清空 |
| 记忆上次连接 | ✅ | `UserDefaults` 持久化，启动恢复（连接不存在时回退首条） |
| 删除二次确认 / 表单校验 | ✅ | 删除对话框明示连带删除钥匙串密码；表单校验复用 `ConnectionConfig.isValid` |
| 配套文档 | ✅ | 需求规范书 / 概要设计 / 测试用例 / 兼容性矩阵 / GBase 技术验证 / 发布方案 + 表格校验脚本 |
| 命令行工具 | ✅ | `-c` / stdin / `--tree` / `--columns` |
| 本地与真机回归脚本 | ✅ | 89 项单测 + 28 项链路检查 |
| GBase 8a 驱动 | ⬜ | 方言已就绪，驱动排期最后 |

### 2.5 主要用例

| 编号 | 用例 | 主流程 |
|---|---|---|
| UC-01 | 新建连接并测试 | 连接列表「+」→ 填表 → 测试连接 → 显示版本/库/用户 → 保存 |
| UC-02 | 编辑连接 | 选中连接 → 编辑 → 改字段（密码留空则不改）→ 保存 |
| UC-03 | 删除连接 | 选中 → 删除 → 清理 Keychain 与连接缓存 |
| UC-04 | 执行单条查询 | 输入 SQL → ⌘↩ → 结果表格显示 |
| UC-05 | 执行多条语句 | 分号分隔 → 逐条执行 → 下拉切换多个结果集 |
| UC-06 | 中途取消 | 执行中点「停止」→ 状态显示「已取消」 |
| UC-07 | 语法预检 | 点「检查」→ 对可 EXPLAIN 语句发 `EXPLAIN` → 显示通过/失败 |
| UC-08 | 浏览对象结构 | 服务器 → 数据库 → schema → 表 / 视图 → 列；展开非当前库时按需建立该库连接 |
| UC-09 | 复制结果 | 选中行 → ⌘C → TSV 文本 → 粘贴进 Excel |
| UC-10 | 新建查询页签 | ⌘T → 新增页签 → 可切换 / 关闭 |
| UC-11 | 无 UI 验证 | 命令行 `-c "SQL"` / `--tree --columns` |
| UC-12 | 工具栏执行 / 停止 | 默认执行=暗绿可点、停止=灰不可点 → 点执行 → 两个按钮状态互换（执行变灰、停止变红）→ 点停止恢复 |
| UC-13 | 切换服务器 / 数据库 | 顶部上下文栏选服务器 → 数据库下拉列出有权限的库 → 选库 → 执行 `SELECT current_database()` 验证 |
| UC-14 | 保存 / 回填查询 | 工具栏书签 → 命名保存 → 重启 App → 已保存列表 → 回填当前页签 |
| UC-15 | 拖拽调整结果区 | 拖动编辑区与结果区之间的分隔条 → 两区高度实时变化 |
| UC-16 | 切换界面语言 | 菜单「语言」→ 选 English → 全部界面文案立即变英文 → 重启保持 → 切回简体中文无残留 |
| UC-17 | 打开 SQL 文件 | 工具栏「打开文件」→ 选 .sql → 新页签按文件名显示、不绑定连接 → 可直接编辑 |
| UC-18 | 保存 / 另存为 | 工具栏保存主体 → 有路径写回；点下拉箭头 → 另存为… → 选路径保存 |
| UC-19 | 编辑菜单 | 点「编辑」→ 查找 / 替换 / 跳转 / 缩进 / 清除 / 格式化 |
| UC-20 | 页签编号回归 | 新建（查询 1、查询 2）→ 关掉查询 1 → 再新建 → 应是「查询 3」 |
---
---

## 9. 交付定义

一批做完 = 五件齐：① 代码 + 判据（含负例）② `verify-core.sh` 全绿且计数与台账一致 ③ 文档门禁全绿 ④ `build-app.sh` 出包并打印 sha ⑤ 一条汇报（改了什么 / 读数 / 包 sha / 未覆盖项）。

## 10. 不做（已定）

面板自由停靠、界面缩放档（90% / 110%）、键位自定义与冲突检测 UI。
