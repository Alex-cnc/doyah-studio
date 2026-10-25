# Doyah 产品开发计划书

> 文档编号 `PC-PLAN-001` · 维护：契约侧 · 上游 = 《Doyah 产品需求规格说明书》
>
> **这本书只回答一件事：哪一条做到哪儿了。** 要什么、验收怎么算 → 需求规格说明书；是什么、边界在哪 → 能力规划说明书；怎么做 → 概要设计说明书。

| 版本 | v0.28（2026-10-20：台账 +4 —— 概要设计契约回流需求书四条；§11 分区条目数跟版） |
|---|---|

## 1 定位

### 1.1 四件文档的分工

| 文档 | 回答 | 不写什么 |
|---|---|---|
| 产品能力规划说明书 | **是什么** | 状态、进度、实现 |
| 产品需求规格说明书 | **要什么**（含验收判据） | **状态、进度** —— 一律在本文件 |
| 产品概要设计说明书 | **怎么做** | 不改变「要什么」 |
| **产品开发计划书**（本文件） | **做到哪了** | 不定义需求、不改验收判据 |

**依赖单向**：能力规划 → 需求分析 → 概要设计 → 开发计划。下游可以引用上游的编号，上游不引用下游。

### 1.2 状态口径

| 符号 | 含义 | 谁能改 |
|---|---|---|
| ⬜ | 未开始 | 动手的那一方，提交时同批改 |
| 🟡 | 部分实现（落了一半，或只在某一端落） | 同上 |
| ✅ | 已实现**且**已按验收判据验过 | 同上；只有判据跑过才能翻 |
| ➖ | 评估后不做（写清理由） | 同上 |

**三条纪律**：

1. **状态只有一处**：本文件。需求规格说明书里出现状态符号即为疏漏（门禁 `Scripts/check-doc-tables.py` 现在查这一条）。
2. **翻 ✅ 要有证据**：附判据名或命令读数；判据没跑过就翻 ✅ 视为假绿。
3. **编号是锚**：本文件编号与需求规格说明书 §9.1 索引一一对应，不许自增、不许合并、不许漏。

## 2 总览

共 **401 条**（FR 343 · NFR 46 · AC 12）：✅ 168 · 🟡 82 · ⬜ 151 · ➖ 0。

| 分区 | 条数 | ✅ | 🟡 | ⬜ |
|---|---|---|---|---|
| 3.6 Doyah Retro | 第六章 | 18 | `FR-RTR-MKT-FEED-001` ~ `FR-RTR-REV-AI-001`（82 条） | **18 / 18 每点都有条目**（2026-10-20 归位；回测与验证拆为回测引擎 / 验证与样本；归位表暂定） |
| 3.5 Doyah Notes | 19 | 0 | 0 | 19 |
| 7.4 智能体验收 | 4 | 2 | 0 | 2 |
| 7.1 发布门槛 | 8 | 5 | 1 | 2 |
| 3.2 Doyah Agent | 第三章 | 50 | `FR-AGT-LINK-CHAN-001` ~ `FR-AGT-QUAL-VERIFY-004`（67 条） | **覆盖 50 / 50**（2026-10-20 补齐 15 条；补 LOOP-009 单次任务预算 1 条） |
| 3.1.1 工程与工具链 | 14 | 14 | 0 | 0 |
| 3.4 Doyah Studio · 数据库 | 4.2 | 34 | `FR-CONN`20 · `FR-EXEC`17 · `FR-RES`14 · `FR-META`15 · `FR-DATA`6 · `FR-DDL`5 · `FR-DIAG`5 · `FR-SESS`5 · `FR-DRV`9 · `FR-EDIT`4（共 106 条） | **34 / 34**（对话式诊断 / 任务定义 / 审批 / 执行回执已在节内立条；4.2.35 命令行出口归 §3.1.4） |
| 3.3 Doyah Studio · 工作区 | 4.1 | 38 | `FR-STD-WS-UI-001`~`07` · `09` · `12`~`72`（69 条） | **38 / 38**（看差异、授权与版本已各自立条，不再指路） |
| 3.1.3 插件装配 | 8 | 6 | 2 | 0 |
| 4.8 AI 智能体 | 8 | 5 | 2 | 1 |
| 4.5 NFR-COMP | 5 | 0 | 3 | 2 |
| 4.7 国际化 | 3 | 2 | 1 | 0 |
| 4.6 NFR-MAINT | 6 | 6 | 0 | 0 |
| 4.1 NFR-PERF | 6 | 2 | 4 | 0 |
| 4.2 NFR-REL | 5 | 5 | 0 | 0 |
| 4.3 NFR-SEC | 8 | 7 | 1 | 0 |
| 4.9 NFR-UI | 1 | 0 | 0 | 1 |
| 4.4 NFR-USE | 4 | 4 | 0 | 0 |

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
| FR-AGT-PLAN-CLAR-001 | 主动澄清：开跑前遇到目标不清 / 缺关键参数 / 两种做法代价差很大时，先问一句再动 | 3.2 Doyah Agent | 常用增强 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-PLAN-PLAN-004 | 计划修订：执行中发现原计划不成立时，说出为什么改并给出新计划，不静默换路 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-GUARD-SOUL-001 | 灵魂分层：L0 角色（我是谁）· L1 领域角色（在这个领域我是谁）· L2 项目做 | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-INGEST-001 | 网络检索：按关键词检索公开网页并给出可点开的来源，能区分「搜到标题」与「读到正文」 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-INGEST-002 | 文档解析：把 PDF / Word / Excel / 图片里的文字取出来参与推理， | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-INGEST-003 | 图像理解：把截图 / 图片交给支持视觉的模型，并把「模型不能看图」当成一种明确失败 | 3.2 Doyah Agent | 进阶可选 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MEDIA-001 | 语音输入：把一段语音转成文字再进对话，转写错误可回看原文 | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MEDIA-002 | 语音输出：把回答读出来，可中断、可调语速 | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SYS-001 | 界面操作：驱动本机图形界面完成点击 / 输入 / 滚动，每一步可见、可中断 | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SYS-002 | 子任务委派：把独立子任务派给子代理并行做，结果汇总回主任务并标明来源 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MODEL-001 | 模型多档：按任务选档（看图 / 调工具 / 上下文长度 / 语种 / 价格），未标注 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-MODEL-002 | 档位端点与模型名可预填且可改（预设是起点不是锁） | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | — | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-007 | 中途干预：执行中可插话（改方向 / 停手 / 追加约束），当前步完成后立刻生效 | 3.2 Doyah Agent | 常用增强 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-008 | 主动通知：长任务完成、出错、需要人决定时主动告知（不让人守着屏幕） | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-009 | 求助通道：卡住时能明确说「我需要你做一件事」（授权 / 提供信息 / 人工操作），并 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-GUARD-PERM-003 | 隔离执行：任何执行都在受限环境内（工作区沙箱 / 命令白名单 / 出网策略），越界即 | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-OPS-OBS-001 | 可观测：每一次模型调用、工具调用、审批与耗时都留有可查记录，能回答「它刚才为什么这么 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-OPS-OBS-002 | 可配置：模型、工具白名单、审批策略、配额、通知规则都可配置，且改完立即生效并有据可查 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-OPS-OBS-003 | 可评测：能用一组固定任务回归「它有没有变笨」，输出可对比的通过率 | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-SYNC-001 | 多端一致性：同一会话在桌面与手机上看到的消息、审批与结论一致（壳不同，内容同） | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-007 | 及时刹停：识别到伤害性动作（删库 / 覆盖未备份文件 / 对外发布）时前置停止 —— | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-001 | 自然语言 → SQL：基于当前连接 schema 生成 SQL，结果进入编辑器不自动 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-001 | 对话式诊断：解读执行计划、慢查询与锁阻塞，给出可执行建议 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 |
| FR-AGT-PLAN-PLAN-001 | DBA 维护任务编排：由自然语言描述生成并执行维护任务（备份 / 恢复、VACUUM | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 |
| FR-AGT-PLAN-PLAN-002 | 自然语言 specs → 数据任务：把规格说明转成可执行任务定义（源 / 转换 / | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-TOOL-SCHED-001 | 定时调度：为数据任务设置一次性 / 周期性调度，客户端运行时按计划执行 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-CORE-LOOP-002 | 数据生成 / 合成数据：按 specs 生成测试数据（行数、分布、约束满足），可导出 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 合成数据面板界面点击待人工点验（真机往返已验） |
| FR-AGT-CORE-LOOP-003 | 导出到指定目录：任务产物导出到用户选择的授权目录（由用户在选择器中指定，授权可跨启动 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-GUARD-PERM-001 | 执行审批与审计：智能体发起的写操作 / DDL / 外部动作逐次审批（可配置只读模式 | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-LINK-EXT-001 | 互操作接口（MCP 双向）：① 作为 host 接入外部 MCP 服务器 | 3.2 Doyah Agent | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | host 方向仍为批处理式且 resources/read 未做；真 MCP 对端待外部实例 |
| FR-AGT-PLAN-PLAN-003 | specs 版本化与重跑：specs 与任务定义可保存、版本化、diff、回滚、重跑 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-AGT-GUARD-PERM-004 | 安全护栏：智能体不得超越当前连接权限 | 3.2 Doyah Agent | 基线必备 | 高 | 🟡 | 🟡 | v1.1+ | 注入端到端未验（缺模型端点与实例）；连接权限的客户端校验未做 |
| FR-AGT-KNOW-MEM-001 | 查询记忆层（补全优先）：从已归档的 .sql 文件派生查询记忆（结构指纹 / 频次 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v0.1.0-alpha | — |
| FR-AGT-KNOW-MEM-004 | 参数化与技能候选：把「同一条 SQL 的不同取值」归并成带参数槽位的模板 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-AGT-KNOW-MEM-002 | 记忆治理（可检视 / 可删除 / 可解释 / 生命周期按类型分）：记忆可浏览原文与来 | 3.2 Doyah Agent | 常用增强 | 高 | 🟡 | 🟡 | v1.1+ | 界面点击待人工点验 |
| FR-AGT-LINK-CHAN-002 | 模型网关扩展（对话侧）：在既有 OpenAI 兼容 LLMClient（现为非流式、 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v1.1+ | §4.1 明示 v1.1+ |
| FR-AGT-UX-CONV-002 | 对话会话：多轮上下文（消息 / 工具调用 / 审批 / 引用）按工作区持久化，可回放 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 会话持久化已接线（每跳落 .jsonl）；**界面回放需人工点验** |
| FR-AGT-CORE-LOOP-004 | Agent 循环：模型 → tool_calls → 执行 → 结果回灌 → 继续 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 五条验收要点机器可判且全绿（两跳 / 步数上限 / 令牌上限停在发送之前 / 取消留痕 / 未登记与坏参数不执行，判据 13 例）；面板上点「停止」的手感与三种停止提示的观感只能人工点验 |
| FR-AGT-CORE-LOOP-005 | 工具注册表（唯一出处）：内置工具与 MCP 工具的统一注册表 —— 每个工具一处声明 | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ✅ | v1.1+ | §4.1 明示 v1.1+ |
| FR-AGT-CORE-LOOP-006 | 内置工具 8 个：read_file / list_dir / search（只读， | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 六个 MVP 工具已全部接线（query_db 只回结构 / 行数 / 语句类型 —— 行数据不出本机）；**端到端需真实模型端点与凭据** |
| FR-AGT-LINK-EXT-002 | MCP client（用户自配 server 面）：配置 name / transp | 3.2 Doyah Agent | 进阶可选 | 低 | 🟡 | 🟡 | v1.1+ | 七条验收要点机器可验的部分全绿（配置面 / 握手 → tools/list → tools/call / 名字与参数原样 / enabled=false 不起进程 / 工具级审批 / 未配与连不上如实报 / http 如实报不支持，判据 15 例含真进程端到端）；界面配置面已落并由 Core 判据 20 例守着（加 / 删 / 开关、逐工具开关、文本⇄配置换算）；真 MCP server 端到端与面板点击观感只能人工点验 |
| FR-AGT-CORE-CTX-001 | 上下文供给与边界：@文件 / @目录 / 选中代码 / 当前页签 / 终端尾部 / | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 上下文第一批（表结构摘要 + 活跃页签）已挂载；文件 / 选中 / 终端尾部三类待接；**端到端需真实模型端点** |
| FR-AGT-GUARD-PERM-002 | 权限与审批：为新工具定义等级（只读 / 可写 / 可执行）+ 路径沙箱 + 命令白名 | 3.2 Doyah Agent | 常用增强 | 高 | ⬜ | ⬜ | v1.1+ | §4.1 明示 v1.1+ |
| FR-AGT-GUARD-SOUL-002 | 审计扩展：留痕覆盖到每一次模型调用（含 Agent 循环每一跳，不只工具调用）+ 成 | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v1.1+ | §4.1 明示 v1.1+ |
| FR-AGT-UX-CONV-003 | 对话 UI = Home 区新开页签（占工作区主要区域，不是侧栏）：消息流 · 流式 | 3.2 Doyah Agent | 常用增强 | 高 | 🟡 | 🟡 | v1.1+ | 对话页签五项已落（位置 / 流式 / 卡片（含模型与端点）/ 内联审批 / 一步撤销）；界面点击与观感需人工点验 |
| FR-AGT-KNOW-MEM-005 | 技能库（skills）：可复用的技能 = 声明式登记（名称 + 适用面 / 触发 + | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 技能库 Core 已交付（加载校验 / 按需披露 / 渲染，技能不执行工具）；登记档数据与界面入口待接；端到端需真实模型端点 |
| FR-AGT-TOOL-SCHED-002 | 定时 agent：为对话 / agent 任务设置一次性或周期性调度，客户端运行时按 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 定时 agent Core 两片 + App tick 与面板已交付；面板真点一遍与「停用后假端点收 0 次请求」的集成取证归人工点验 |
| FR-AGT-GUARD-COST-001 | 门控（省 token 的调用门控）：在触发与模型调用之间有一道判定 —— 没有变化 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 门控已交付（同指纹不重复发请求、挡下留痕可导出）；**界面「仍然发送」按钮待接**，端到端需真实端点 |
| FR-AGT-KNOW-MEM-003 | 对话记忆（跨会话的长期记忆）：可检视 / 删除 / 解释 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 对话记忆 Core 已落进 master（事实源 + 治理面 + 派生索引 + 进上下文的唯一入口）；治理界面与会话侧写入提炼未落 |
| FR-AGT-UX-CONV-004 | 回边（生产化三件）：模型调用的失败分级与重试 / 退避 + 观察结果回灌（执行结果作 | 3.2 Doyah Agent | 常用增强 | 高 | ⬜ | ⬜ | v1.1+ | §4.1 明示 v1.1+ |
| FR-AGT-UX-CONV-005 | 回边（生产化四件）：工具 / 命令并发 + 完成判据（自检）+ 长跑监控 + 调用链 | 3.2 Doyah Agent | 常用增强 | 中 | 🟡 | 🟡 | v1.1+ | 四件（并发 / 完成判据 / 长跑监控 / 调用链）已落、判据 17 例；告警的界面观感与真端点上的长跑行为只能人工点验 |
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
| FR-AGT-PLAN-PLAN-005 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-PLAN-PLAN-006 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-KNOW-CTX-001 | — | 3.2 Doyah Agent | 常用增强 | 中 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-KNOW-CTX-002 | — | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-TOOL-EDIT-001 | — | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-LINK-CHAN-003 | — | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-LINK-EXT-003 | — | 3.2 Doyah Agent | 进阶可选 | 低 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-CONV-006 | — | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-UX-SESS-001 | — | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-001 | — | 3.2 Doyah Agent | 基线必备 | 高 | ✅ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-002 | — | 3.2 Doyah Agent | 常用增强 | 中 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-003 | — | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
| FR-AGT-QUAL-VERIFY-004 | — | 3.2 Doyah Agent | 基线必备 | 高 | ⬜ | ⬜ | v0.1.0-alpha | — |
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

## 5 平台实现状态

> **不要手工编辑本表**：各平台在 `Docs/平台实现状态.json` → `platforms.<名>.overrides`（编号 → 状态）里登记，
> 然后运行 `python3 Scripts/gen-platform-parity.py` 重写本表；`--check` 判定漂移（闭环第 7 项）。
> 状态含义与 §0.4 一致；macOS 状态取自 §10.1 索引（单一事实来源，**不在台账里登记**）。
> 平台列由台账决定（当前 Linux / Windows 两列）——**加一列只改台账，不改脚本**；
> 不设列的平台（移动端）在台账 `notPlatforms` 里写明理由。

<!-- BEGIN platform-parity -->
> 共 379 条功能需求。**macOS** 状态取自《Doyah 产品需求规格说明书-需求索引》（**基线，唯一来源**，不由本脚本维护）。
> **watchOS** 状态取自 `Docs/平台实现状态.json` → `platforms.watchos.overrides`（Apple 全系第三端（与 macOS / iOS 同一机组；实现未开工）；维护者：铁皮大河马（`hugehippo` · macOS/iOS/watchOS 侧））。
> **Linux** 状态取自 `Docs/平台实现状态.json` → `platforms.linux.overrides`（Doyah Studio 全量 PC 端第三端（2026-10-14 人类主人令：本仓实现开工）；维护者：铁皮大河马（`hugehippo` · macOS/iOS/Linux 侧）—— 2026-10-15 人类主人拍板「Linux 与 macOS 底层血缘更近 ⇒ 归 `hugehippo`」（原归 `babyhippo`）；实现面在 `platform/linux/`，平台设计层写概设 §8.6 `[独占:linux]`）。
> **Windows** 状态取自 `Docs/平台实现状态.json` → `platforms.windows.overrides`（对等目标端（与 macOS 完全一致）；维护者：奶牙小河马（`babyhippo` · Windows/Android/Harmony 侧）—— 2026-10-16 人类主人定案：不再设分组键，Windows 归 babyhippo；`fatshark` 侧名已退役）。
> 未在台账里逐条登记的，一律按 `⬜` 记。
> `⚠️` = 与该需求的 macOS 基线不一致（**未在 §10.9 登记的平台差异一律视为「必须一致」**，见 §0.8 R2）。
> 平台列：watchOS / Linux / Windows（表由 `Scripts/gen-platform-parity.py` 重写，`--check` 判定漂移）。
> **移动端（鸿蒙 / 安卓 / iOS）不设列**：移动端 = Doyah Notes（只有笔记），不是 Doyah Studio 的平台版本（§0.10 / 规划书 §4.13）⇒ 不在本矩阵设列，免得造出一列永远 ⬜ 的假进度。

**FR-AGT**（68 条。与 macOS 基线一致：watchOS 34 / Linux 34 / Windows 34 条）

| 编号 | 需求摘要 | macOS | watchOS | Linux | Windows |
|---|---|---|---|---|---|
| FR-AGT-CORE-CTX-001 | 上下文供给与边界：@文件 / @目录 / 选中代码 / 当前页签 / 终端尾部 / DB schema … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-001 | 自然语言 → SQL：基于当前连接 schema 生成 SQL，结果进入编辑器不自动执行，并附「用到哪些… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-002 | 数据生成 / 合成数据：按 specs 生成测试数据（行数、分布、约束满足），可导出或写入目标表 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-003 | 导出到指定目录：任务产物导出到用户选择的授权目录（由用户在选择器中指定，授权可跨启动恢复），不硬编码路径 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-004 | Agent 循环：模型 → tool_calls → 执行 → 结果回灌 → 继续；步数 / 令牌上限（… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-005 | 工具注册表（唯一出处）：内置工具与 MCP 工具的统一注册表 —— 每个工具一处声明（名称 + sche… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-006 | 内置工具 8 个：read_file / list_dir / search（只读，限工作区内）· ru… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-007 | 及时刹停：识别到伤害性动作（删库 / 覆盖未备份文件 / 对外发布）时前置停止 —— 不建审批单、不执行… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-CORE-LOOP-008 | 队列：多个任务排队执行 —— 可查看排队、调整顺序、取消未开始的任务；同一工作区不并发跑两条会互相踩的任… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-LOOP-009 | 单次任务的预算：一次任务最多 150 步、256K token（能力书 3.1.1 · S-15）；新任… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-CORE-SESS-001 | 会话持久化：会话可保存、可恢复 —— 关掉应用再打开，能接着上次的对话与进度往下走；上下文与已调用的工具… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-GUARD-COST-001 | 门控（省 token 的调用门控）：在触发与模型调用之间有一道判定 —— 没有变化 / 没有新内容 / … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-GUARD-PERM-001 | 审批主链（分工：等级与白名单怎么配见 -002、运行时隔离边界见 -003、语句级判定与注入防护见 -0… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 ⚠️ |
| FR-AGT-GUARD-PERM-002 | 配置面（分工：审批单与审计在 -001，本条只管「等级 / 沙箱根 / 白名单」怎么声明）：为新工具定义… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-GUARD-PERM-003 | 运行时边界（分工：判据来源见 -002 的白名单与沙箱根，审批在 -001）：任何执行都在受限环境内（工… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-GUARD-PERM-004 | 语句级判定（分工：本条判「这句话危不危险」及内容侧注入，-001 判「谁来批」）：智能体不得超越当前连接… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-GUARD-SOUL-001 | 灵魂分层：L0 角色（我是谁）· L1 领域角色（在这个领域我是谁）· L2 项目做法（这个项目怎么做）… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-GUARD-SOUL-002 | 审计扩展：留痕覆盖到每一次模型调用（含 Agent 循环每一跳，不只工具调用）+ 成本字段（模型 / 端… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-KNOW-CTX-001 | 项目上下文：开跑前自动带上看料 —— 工作区结构、当前分支与未提交改动、关键文件摘要，不必用户手贴 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-KNOW-CTX-002 | 压缩（分工：跨进程的检查点续跑在 FR-AGT-UX-CONV-004 ③，本条只管会话内超限时怎么压）… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-KNOW-MEM-001 | 查询记忆层（补全优先）：从已归档的 .sql 文件派生查询记忆（结构指纹 / 频次 / 来源连接），在编… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-KNOW-MEM-002 | 记忆治理（可检视 / 可删除 / 可解释 / 生命周期按类型分）：记忆可浏览原文与来源、可单条删除、可整… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-KNOW-MEM-003 | 对话记忆（跨会话的长期记忆）：可检视 / 删除 / 解释；按工作区（与连接）隔离；不得携带结果集行数据与… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-KNOW-MEM-004 | 参数化与技能候选：把「同一条 SQL 的不同取值」归并成带参数槽位的模板；跨天频次 / 跨越天数 / 时… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-KNOW-MEM-005 | 技能库（skills）：可复用的技能 = 声明式登记（名称 + 适用面 / 触发 + 步骤（引用工具名）… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-LINK-CHAN-001 | 模型接入配置：可配置模型服务（本地 / 远端，OpenAI 兼容端点）、模型名、API Key 存入系统… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 ⚠️ |
| FR-AGT-LINK-CHAN-002 | 模型网关扩展（对话侧）：在既有 OpenAI 兼容 LLMClient（现为非流式、无 tools）上支… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-LINK-CHAN-003 | IM 通道：从聊天里收发任务 —— 手机上发一句话即可派活，长任务完成推回结论；权限与桌面端同一套 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-LINK-EXT-001 | 互操作接口（MCP 双向）：① 作为 host 接入外部 MCP 服务器；② 作为 server 把本客… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-LINK-EXT-002 | MCP client（用户自配 server 面）：配置 name / transport（stdio … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-LINK-EXT-003 | 插件：第三方能力以插件接入 —— 插件须声明权限与数据边界，装了才生效，卸了不留残留 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-OPS-OBS-001 | 可观测：每一次模型调用、工具调用、审批与耗时都留有可查记录，能回答「它刚才为什么这么做」 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-OPS-OBS-002 | 可配置：模型、工具白名单、审批策略、配额、通知规则都可配置，且改完立即生效并有据可查 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-OPS-OBS-003 | 可评测：能用一组固定任务回归「它有没有变笨」，输出可对比的通过率 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-PLAN-CLAR-001 | 主动澄清：开跑前遇到目标不清 / 缺关键参数 / 两种做法代价差很大时，先问一句再动手，不靠猜 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-PLAN-PLAN-001 | DBA 维护任务编排：由自然语言描述生成并执行维护任务（备份 / 恢复、VACUUM / ANALYZE… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-PLAN-PLAN-002 | 自然语言 specs → 数据任务：把规格说明转成可执行任务定义（源 / 转换 / 目标 / 调度 / … | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-PLAN-PLAN-003 | specs 版本化与重跑：specs 与任务定义可保存、版本化、diff、回滚、重跑 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-PLAN-PLAN-004 | 计划修订：执行中发现原计划不成立时，说出为什么改并给出新计划，不静默换路 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-PLAN-PLAN-005 | 完成判据：任务完成必须有可检验的判据 —— 「看起来做完了」不算；每条任务开工前先给出「怎么算做完」，做… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-PLAN-PLAN-006 | 失败自恢复：工具失败可重试或换路 —— 可重试的先重试，不可重试的换手段；连续失败要停下来说明，不无限重… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-QUAL-VERIFY-001 | 结果自验：产出前先自查 —— 能跑的跑一遍、能对的对一遍，再报完成；验不过就说验不过。分工：本条管事后怎… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-QUAL-VERIFY-002 | 长任务一致性：跨小时不丢目标 —— 中断、重启、换端之后仍知道在做什么、做到哪一步 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-QUAL-VERIFY-003 | 不确定性表达：不确定就说 —— 给出把握程度与依据，不把猜测说成事实 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-QUAL-VERIFY-004 | 断言可溯源：每条结论能指到出处 —— 文件路径行号 / 命令输出 / 日志 / 文档链接，读者能自己复核 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-EDIT-001 | 局部精确编辑：按行或按块改 —— 不做整文件重写；改完给差异，用户能看清动了哪几行 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-INGEST-001 | 网络检索：按关键词检索公开网页并给出可点开的来源，能区分「搜到标题」与「读到正文」 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-INGEST-002 | 文档解析：把 PDF / Word / Excel / 图片里的文字取出来参与推理，保留页码或位置以便回… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-INGEST-003 | 图像理解：把截图 / 图片交给支持视觉的模型，并把「模型不能看图」当成一种明确失败 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-MEDIA-001 | 语音输入：把一段语音转成文字再进对话，转写错误可回看原文 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-MEDIA-002 | 语音输出：把回答读出来，可中断、可调语速 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-MODEL-001 | 模型多档：按任务选档（看图 / 调工具 / 上下文长度 / 语种 / 价格），未标注的能力当作没有 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-MODEL-002 | 档位的端点和模型名可预填（2026-10-20 从概要设计 §3.32 回流）：配置面从内置提供商预设里… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-SCHED-001 | 定时调度：为数据任务设置一次性 / 周期性调度，客户端运行时按计划执行 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-TOOL-SCHED-002 | 定时 agent：为对话 / agent 任务设置一次性或周期性调度，客户端运行时按计划触发一次会话；错… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-TOOL-SYS-001 | 界面操作：驱动本机图形界面完成点击 / 输入 / 滚动，每一步可见、可中断 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-TOOL-SYS-002 | 子任务委派：把独立子任务派给子代理并行做，结果汇总回主任务并标明来源 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-CONV-001 | 对话式诊断：解读执行计划、慢查询与锁阻塞，给出可执行建议 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-UX-CONV-002 | 对话会话：多轮上下文（消息 / 工具调用 / 审批 / 引用）按工作区持久化，可回放 / 审计；会话记录… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-UX-CONV-003 | 对话 UI = Home 区新开页签（占工作区主要区域，不是侧栏）：消息流 · 流式渲染 · 工具调用卡… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-UX-CONV-004 | 回边（生产化三件）（分工：本条只管模型调用这一侧；工具执行失败的重试与换路见 FR-AGT-PLAN-P… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-CONV-005 | 回边（生产化四件）：工具 / 命令并发 + 完成判据（自检）+ 长跑监控 + 调用链可追溯 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-AGT-UX-CONV-006 | 过程可见：每一步都在界面上看得到 —— 调了什么工具、读了哪个文件、跑了哪条命令，按时间排列可回看 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-CONV-007 | 中途干预：执行中可插话（改方向 / 停手 / 追加约束）—— 改方向与追加约束在当前步完成后生效；停手立… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-CONV-008 | 主动通知：长任务完成、出错、需要人决定时主动告知（不让人守着屏幕） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-CONV-009 | 求助通道：卡住时能明确说「我需要你做一件事」（授权 / 提供信息 / 人工操作），并给出具体要什么 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-SESS-001 | 会话生命周期：新建 / 归档 / 删除 / 导出 —— 删除即真删（不留副本），导出可带走 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-AGT-UX-SYNC-001 | 多端一致性：同一会话在桌面与手机上看到的消息、审批与结论一致（壳不同，内容同） | ⬜ | ⬜ | ⬜ | ⬜ |

**FR-NTS**（19 条。与 macOS 基线一致：watchOS 1 / Linux 1 / Windows 1 条）

| 编号 | 需求摘要 | macOS | watchOS | Linux | Windows |
|---|---|---|---|---|---|
| FR-NTS-NOTE-ATTACH-001 | 附件与图片：插入图片与文件，附件存文件系统、笔记里存引用，原图不被压缩覆盖 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-CAPTURE-001 | 快速捕获：一个动作记下一条笔记（手机锁屏 / 桌面快捷键），不要求先选目录与标签 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-EXPORT-001 | 导出与迁移：导出 Markdown / 纯文本 / 备份包，导入自己导出的包可完整还原 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-FORMAT-001 | 编辑与格式：标题、列表、待办、引用、代码块、表格等基础格式，所见即所得与源码可切换 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-ORG-001 | 整理：标签、收藏、归档、置顶与批量操作，批量操作前显示影响条数 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-PRIVACY-001 | 私密保护：可把单条笔记标为私密（不进搜索、不同步、不外发），需二次验证才可查看 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-NTS-NOTE-SEARCH-001 | 列表与检索：按时间 / 标签 / 关键词 / 语义检索，两种检索都在，语义不可用时降级并说出来 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-SYNC-001 | 同步与账号：手机端与桌面端同步，离线可用、联网合并，冲突按 §3.5.9「记录级 LWW + 留两版」处… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-SYNC-002 | 冲突合并：按记录级 LWW（rev + updatedAt）+ 冲突留两版 —— 落败的那版原样留底、能… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-TRASH-001 | 删除与恢复：删除进回收站，可恢复，到期才彻底清除 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-NOTE-VERSION-001 | 历史版本：每次保存留版本，可查看与回滚，回滚本身也生成新版本 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-CALENDAR-001 | 月视图（可切周视图）把任务铺在日期上（按截止时间；有提醒的日子同时打点） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-CALENDAR-002 | 点某天看当天任务、点任务进详情；逾期任务显式标识 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-LINK-001 | 任务 ↔ 笔记双向转化：笔记生成任务、任务记成笔记，带回指，可撤销 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-LIST-001 | 待办事项本体：标题 / 截止时间 / 重复规则 / 完成态，与笔记同级，共用同一套同步与加密 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-LIST-002 | 清单式列出各种任务（标题 / 截止时间 / 完成态 / 优先级 / 标签），支持新建 / 编辑 / 完成… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-LIST-003 | 组织与检索：分组（按时间 / 按状态 / 按标签）· 筛选（今天 / 本周 / 已过期 / 无截止）· … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-STATE-001 | 完成 / 改期在清单与日历上是同一次写入、同一事务；日历上可直接完成 / 改期（拖拽或长按） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-NTS-TODO-STATE-002 | 清单是唯一事实源：任务数据只有一份，日历不另存、切视图不复制、不产生第二套状态 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |

**FR-RTR**（82 条。与 macOS 基线一致：watchOS 82 / Linux 82 / Windows 82 条）

| 编号 | 需求摘要 | macOS | watchOS | Linux | Windows |
|---|---|---|---|---|---|
| FR-RTR-FLOW-CRON-001 | 触发规则登记与持久化：把档案里的「价格 / 资金 / 事件」三类触发条件与动作结构化入库，跨会话可查、可… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-FLOW-CRON-002 | 触发检查与提醒投递：按调度检查规则命中情况，命中后复用宿主提醒能力投递，并留痕 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-FLOW-CRON-003 | 定时生成与缺期口径：按节拍自动生成周报 —— 由生成侧（前门 dsh）定时调度 → 生成 → 投递；Re… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-FLOW-CRON-004 | 触发面（新增 · 2026-10-09 人类主人拍板 C）：① 手动「生成本期」按钮（调用本机生成侧）②… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-FLOW-MARKET-001 | 内置市场 skill：把行业口径（放量 / 缩量 / 突破 / 回踩 / 背离 / 量价配合 / 板块轮… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-FLOW-ORCH-001 | 工作流编排：把取数 / 算特征 / 跑回测 / 生成文本 / 推送编成可命名、可复用、可定时的流水线 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FEED-001 | 盘后一键抓取：对配置的自选池，一条命令 / 一次触发抓取行情（日线）、资金流、财务、板块数据，原始产物落… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FEED-002 | 复权口径与来源标注：价格序列标明前 / 后复权与数据源，跨源对比时口径可对齐 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FEED-003 | 数据源适配层（可切换、可多源交叉）：取数按「能力 → 适配器」组织，换源不改上层 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FEED-004 | 行情文件导入：读入本地行情文件（CSV / JSON），字段 = 时间 + 开高低收，成交量可选（缺列如… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FEED-005 | 内置样本数据：随包内置一份样本成交 + 一段样本行情，保证开箱能立刻走完四步（导入 → 回放 → 标注 … | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FUND-001 | 事件叠加 · 财报与业绩预告 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FUND-002 | 事件叠加 · 涨跌停与放量突破（阈值可配） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FUND-003 | 事件叠加 · 股东增减持 / 回购 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-FUND-004 | 事件叠加 · 行业政策 / 新闻节点（手工录入 + 来源链接 + 录入时刻） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-HEALTH-001 | 抓取记录与接口健康：每次抓取记录各接口的响应码、耗时、空字段率，可查历史 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-HEALTH-002 | 断档与字段漂移告警：交易日数据缺失、字段名变化（库升级 / 接口改版）时告警并建议备用源 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-HEALTH-003 | 数据健康：查出缺口、跳空异常、成交量为零、复权前后对不上、日期不连续，并拦住口径不一致的计算 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-STORE-001 | 导入结果如实报数：导入前预览、导入后报「成功 N 条 / 跳过 M 条及原因」；无法识别的行不丢也不猜，… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-STORE-002 | 真实口径：只记真实成交与持仓（禁用回测 / 模拟数据充数）；每笔含 时间 · 标的 · 方向 · 数量 … | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-STORE-003 | 净值记账：按日（或周）算净值曲线，计入费用与成本；可选基准对比；口径单点定义（含分红 / 送转 / 资金… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-MKT-STORE-004 | 数据主权与录入方式：Retro 是持仓与决策记录的「真值源」；智能体记忆 / 笔记里的持仓只作副本或指针… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-AI-001 | AI 复盘：检出异常操作（追高 / 频繁交易 / 不止损 / 逆势加仓），写成挂在原始记录上的复盘稿 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-001 | 异常操作检出：基于成交记录识别「高买低卖 / 逆趋势加仓 / 超预设仓位」等操作，输出异常清单 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-002 | 同行 / 板块对比面板：对自定义板块展示多标的的日线、资金流、估值对比 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-003 | 策略 / 模型提炼（策略卡片）：从多期周报与跟踪日志中提取用户反复使用的判断逻辑，形成可复用卡片 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-004 | 七件套指标：胜率 / 盈亏比（profit factor）/ 期望值（expectancy）/ 平均 R… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-005 | 权益曲线：按时间画出账户权益 / 累计盈亏，可叠加回撤区 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-006 | 月历热力图：按月历展示每日盈亏（颜色深浅 = 幅度），点某天看当天成交 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-007 | 分组统计：按标的 / 时段（星期几、小时）/ 标签分组统计 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-008 | MFE / MAE（进出场效率）：每笔的最大浮盈 / 最大浮亏，回答「该走的时候走了吗」 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-ATTR-009 | A 股税费口径：佣金 / 印花税 / 过户费按可配置费率计入成本（海外的复盘产品都不管这块） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-001 | 可溯源上下文检索接口：给出「某标的 + 区间」的结构化上下文（数据 + 当时的日志 / 周报观点 + 来… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-002 | 对话式复盘：用户对某标的某段历史要求 AI 分析对错，结论必须可溯源到原始记录 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-003 | 回放会话归档：一次回放可以存成一次复盘会话（含当时的标注与结论），下次能直接打开接着看 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-004 | 左侧导航列表：展示已发布的周报条目（期号 / 标题 / 发布日期 / 封面缩略图），按发布日倒序，当前阅… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-005 | 右侧主工作区正文：选中左栏任意一项，右侧渲染该期正文（Markdown 标题 / 段落 / 列表 / 引… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-006 | 多媒体内联：正文里的图片 / 视频就地在正文位置渲染 —— 图片可点开看原图；视频可播（进度 / 音量 … | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-007 | 周报包导入 + 本机存储：按周报包契约（见《Doyah Retro 需求规范书》§6.5）从指定目录导入… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-008 | 与鲸鱼娘产出的格式契约：把「周报包」定为跨化身交换面（鲸鱼娘写、Retro 读），并写明不变量（目录结构… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-QUERY-009 | 本仓独立报告视图（新增 · 2026-10-06）：复用 FR-R-12 的呈现契约与 FR-STD-A… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-001 | 券商成交明细导入：读入本人账户导出的对账单 / 交割单（CSV / Excel），按统一中间格式清洗后入… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-002 | 笔记钉在 K 线 / 成交上：一条笔记可挂在某根 K 线或某笔成交上（图标标记），点图标即看；另有一份列… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-003 | 标签体系：成交可打标签（预设：入场理由 / 出场理由 / 错误类型 / 情绪），标签可自定义 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-004 | 决策留痕（依据指针）：每笔调仓必须挂决策依据指针（当时的证据：数据项 / 研报 / 规则条号，如基本法或… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-005 | 每月决策复盘：复盘「决策」而不是「行情」 —— 逐笔看当时的依据是否成立 + 结果如何；产出可拍板的规则… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-REV-TRADE-006 | 只读不交易（安全不变量 · 不可砍项）：永不下单 / 撤单 / 改单 / 资金划转；不连交易通道；本工具… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-001 | 时间游标语义收口（日线为主、周线辅助；日/周推进共用一条游标） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-002 | 防未来函数判据（硬）：任何计算所读数据行满足 date ≤ 游标日 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-003 | 复权口径切换（前复权 / 不复权；与 FR-RTR-MKT-FEED-002 的来源标注一致） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-004 | 买卖规则定义（入场 / 出场 / 仓位规则集，人类可读文本、可 diff、可复用） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-005 | 自定义信号表达式（如 close > ma20 and vol > vol_ma5 * 2） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-006 | 规则驱动回放 · 逐日自动标记触发（买 / 卖点；成交价口径写死并标注） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-007 | 板块联动读数（同板块其他标的当日涨跌 / 放量） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-008 | 同期多股同步回放（同一天、同板块 N 只，共享一条游标） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-BACKTEST-009 | 复盘标签与笔记落到回放（"启动点" / "诱多" 等自定义标签 + 当时为什么买 / 没买） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-FEATURE-001 | 特征模型：把「牛股特征」写成可计算的定义（指标 + 阈值 + 时间窗），保存为可复用模型，能对任意标的与… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-PROFILE-001 | 一键生成个股跟踪档案：由当日快照渲染「建立信息 + 一句话状态 + 核心数据表 + 关键价位 + 触发规… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-PROFILE-002 | 分析报告生成：由快照 + 当日档案渲染「结论先行 + 今天的数据 + 为什么动 + 走势复盘 + 证据审… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-PROFILE-003 | 产物归档进宿主笔记：档案 / 报告按命名规范写入宿主笔记，带标签与时间线 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-001 | 周报草稿生成：按主题（如芯片 / 半导体）与日期区间，汇总本期多标的的数据与事件，生成周报草稿 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-002 | 周报转笔记：把周报按「笔记的一种形态」写入宿主笔记（正文 markdown + 内嵌表格 + 标签），可… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-003 | 用户自定义规则与要求：用户可配「生成什么、按什么口径」—— 可编辑模板（Markdown + 变量占位）… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-004 | 产物 = 报告（本仓可读 + 笔记形态并行）：报告 = FR-STD-ALL-IFACE-005 周报包… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-005 | 单篇 + 幂等覆盖 + 固定标签 + 可配归属：幂等键 uid = 规则ID + 周期（重跑覆盖同一篇）… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-006 | 可编辑 + 改后不覆盖（前置规则 ①）：自动生成的笔记允许用户编辑；一旦用户编辑过 ⇒ 该篇转为「用户自… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-007 | 交换面（走契约交换面，不走同库直写）：Retro（或生成侧）产出中间文件 → Notes 导入 ⇒ 落成… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-008 | MVP（最小可讨论版 · 2026-10-06 改）：生成侧每周一跳 → 按模板（含一段自然语言要求）生… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-REPORT-009 | 多媒体契约（新增 · 2026-10-06，媒体形态 = 组合）：图片 = 包内 assets/ 相对路… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-001 | 策略绩效输出（每笔盈亏 / 胜率 / 盈亏比 / 最大回撤 / 持仓天数 / 交易次数） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-002 | 特征筛选回放（条件 → 历史全部命中时点 → 逐个回放 → 统计走牛比例 / 平均涨幅 / 失败样本） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-003 | 牛股倒推（已知大牛股 → 回放到启动前 → 列出当时信号 → 同信号反扫其他标的） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-004 | 失败案例库（同形态失败样本入库存档并可回放） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-005 | 模式库（把验证有效的形态 / 规则存成可复用条目，带出处与命中统计） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SAMPLE-006 | 回测与验证：把特征模型放到历史区间跑出命中率、超额收益、最大回撤与样本数，并做样本外验证 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-001 | 按标的 / 时间段回溯查询：输入标的 + 日期区间，拉出行情、资金流、基本面的时间序列对比，并同屏对照当… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-002 | 导出：查询结果 / 档案 / 周报可导出 markdown 与 CSV | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-003 | 逐根 K 线回放（行情为底）：按所选周期逐根推进 K 线，支持播放 / 暂停 / 单步 / 后退、速度可… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-004 | 成交驱动回放（成交回放为主）：时间轴以我自己的成交为主轴推进 —— 推到某笔成交时停下、标出该笔的买入 … | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-005 | 成交 ↔ 行情对齐：把成交与行情放进同一时间轴 + 同一标的，容差规则显式可配、可解释 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCENARIO-006 | 历史情形：给定当前形态，检索历史上相似情形，给样本量与后续 N 日涨跌分布（中位数 / 分位 / 最大回… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-RTR-RSR-SCREEN-001 | 选股与筛选：按一个或多个特征模型在指定股票池与时间段里跑出候选清单，带命中原因 | ⬜ | ⬜ | ⬜ | ⬜ |

**FR-STD**（210 条。与 macOS 基线一致：watchOS 32 / Linux 32 / Windows 149 条）

| 编号 | 需求摘要 | macOS | watchOS | Linux | Windows |
|---|---|---|---|---|---|
| FR-STD-ALL-BLD-001 | 从声明式工程描述生成构建工程，可重复生成（生成器属平台实现） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-002 | 生成后自动修复本地包 product 关联（避免 Missing package product） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-003 | Core 逻辑单元测试可一条命令运行 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-004 | 不打开 Xcode 也能产出可运行的 .app | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-005 | 提供依赖镜像脚本应对国内网络 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-006 | 提供本地端到端链路验证（无需外部数据库） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-007 | 提供真实 PostgreSQL 连接验证脚本 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-008 | 工程可被命令行构建工具直接编译（不依赖图形 IDE） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-BLD-009 | 配套文档随代码同步维护，需求变更可追溯 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-CLI-001 | 提供 DoyahCLI，可在无 UI 环境下验证连接与执行 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-CLI-002 | 支持环境变量连接参数：PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABAS… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-CLI-003 | 支持 -c "SQL" 执行任意 SQL；无 -c 时从标准输入读取 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-CLI-004 | 支持 --tree 打印对象树，--columns 附带列类型 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-CLI-005 | 失败时返回非零退出码，便于脚本判定 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-LIC-001 | 许可证解析与能力位：许可证声明「开发工作区 / 数据库 / 笔记」三块能力位与到期时间，离线可校验（签名… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-LIC-002 | 按授权呈现入口：活动栏与菜单按能力位显示；未授权的区域不出现（不是显示成灰的诱导），并提供一处「版本与许… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-LIC-003 | 降级与数据归属：许可证到期后如实提示并降级，绝不锁死或隐藏用户数据 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-LIC-004 | 授权范围口径：桌面三块（开发工作区 / 数据库 / 笔记）同属一套许可证；移动端授权不在这份许可证管辖内 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-LIC-005 | 设备配额与设备管理（备用能力）：默认上限 5 台；只用随机设备标识、不做硬件指纹；支持释放设备（换机不锁… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-PLUG-001 | 笔记插件以同进程内模块装配（不做独立进程 + IPC、不做可卸载组件包） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-002 | 活动栏出现「笔记」一项；未授权时不出现（不是灰掉）；可见性只有一处判据 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-003 | 宿主向插件单向传上下文（当前连接、库 / 表、选中 SQL）；只传文本与标识，不传结果行数据；行数据入笔… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-004 | 笔记数据落在本工程数据家之外（独立目录），备份与清理策略各自独立 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-005 | Linux 端装配笔记，且必须是本地离线实现：数据只落本机 SQLite（笔记自己的数据家，不写进工程数… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-ALL-PLUG-006 | 许可证一套覆盖三个能力位（开发工作区 / 智能数据库助理 / 笔记），不做插件独立授权与单独开关 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-007 | 允许插件复用宿主词法层（CodeSyntax / CodeLexer / CodeCompletion）… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-ALL-PLUG-008 | 桌面各端笔记存储统一到本地 SQLite（2026-09-27 拍板 Q23）：主存进库 —— 笔记元数… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-CONN-001 | 新建连接：名称、数据库类型、主机、端口、数据库名、用户名、密码、SSL 模式、超时 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-002 | 数据库类型切换时，默认端口、默认 SSL 模式、默认 schema 自动联动 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-003 | 配置校验：名称、主机、端口（1–65535）、用户名非空 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-004 | 连接配置带 schemaVersion，为将来配置格式升级预留迁移能力 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-005 | 连接 URL 导入 / 导出：支持 postgres://user@host:port/db?sslmo… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-006 | 连接保活心跳：空闲连接按间隔发送轻量查询，避免被防火墙 / 中间件掐断长连接 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-007 | 以列表展示全部已保存连接，可选中，选中项作为后续执行 / 元数据的上下文 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-008 | 编辑连接：不得出现「点编辑却弹出新建、字段为空」 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-009 | 删除连接：需二次确认，并同时清理系统凭据存储中的密码与连接缓存 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-010 | 记忆上次选中的连接，重启后恢复该选中项 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-011 | 连接在界面上的显示名 = 名称 (登录用户名)：连接名后括注登录账号，用于侧边栏连接列表、服务器选择器、… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-012 | 连接分组 / 文件夹：连接可归入自定义分组，侧边栏按组折叠展示，便于按「项目 / 环境」组织大量连接 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-CONN-013 | 连接颜色与环境标签：可为连接指定颜色与「生产 / 预发 / 测试」标签，侧边栏与查询上下文栏一致着色，避… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-014 | 只读连接与启动 SQL：可把连接标记为只读（客户端拒绝执行写语句）；可配置连接后自动执行的 SQL（如 … | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-015 | 查询工具栏上方提供「当前服务器」选择器：枚举已保存连接（名称 + 地址），切换后作为当前查询与元数据的上… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-016 | 服务器选择器右侧提供「当前数据库」下拉框：枚举当前服务器上当前登录用户有权限访问的数据库，仅显示可见 /… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-017 | 密码存入系统凭据存储，不写入配置文件 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-018 | 编辑连接时密码留空 = 保持原密码不变 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-019 | 密码等敏感输入使用 ASCII 安全字段，避免输入法干扰 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-CONN-020 | SSH 隧道：通过 SSH 跳板连接不可直连的数据库（密码 / 私钥两种方式） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-DB-CONN-021 | 「测试连接」真实连接服务器，返回 server_version / 当前库 / 当前用户 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DATA-001 | 对象树双击表 / 视图节点 → 新建页签并执行「浏览前 N 行」（SELECT * FROM <表> L… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DATA-002 | 表行数统计与条件过滤入口：一键 count(*)；浏览时可填 WHERE / ORDER BY 并在服务… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DATA-003 | 生成 SQL 模板：按表结构生成 SELECT 列清单与 INSERT … VALUES (?, ?) … | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DATA-004 | 结果集内联编辑（改单元格 / 新增行 / 删除行），提交前预览将执行的 DML，确认后再提交 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DATA-005 | 单行详情 / 单元格值编辑器：宽表与长 JSON 竖排查看，JSON 值格式化显示 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DATA-006 | 外键引用导航：由单元格 / 行跳转到被引用表并自动带入条件 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DDL-001 | 由列定义生成 CREATE TABLE（列名 + 类型 + NOT NULL），用于「复制表结构」与结构… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DDL-002 | 生成 DROP TABLE / TRUNCATE TABLE（DROP 默认带 IF EXISTS） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DDL-003 | 表结构编辑器：可视化增删列、改类型、加索引与约束，并实时对照将要执行的 DDL （v3.0 扩写）索引、… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DDL-004 | Schema 对比与同步：对比两个库 / 两个连接的结构差异并生成同步脚本 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DDL-005 | ER 图 / 关系图：由外键生成可视化关系图 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DIAG-001 | 执行计划查看：对当前 SQL 执行 EXPLAIN（可选 ANALYZE / BUFFERS / FOR… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DIAG-002 | 计划摘要：顶部一行给出节点数、规划 / 执行耗时、全表扫描处数、最慢节点，一眼看出瓶颈 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DIAG-003 | 慢查询排行：pg_stat_statements 按总耗时 / 平均耗时 / 调用次数排序 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 |
| FR-STD-DB-DIAG-004 | 数据库统计面板：表大小、索引命中率、连接数、缓存命中率等 pg_stat_* 指标 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DIAG-005 | 锁与阻塞链定位：基于 pg_locks + pg_blocking_pids() 展示锁等待关系与被阻塞… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DIAG-006 | 连接上下文里的诊断入口：可从当前连接 / 库 / 对象唤起诊断，把连接、库、对象与最近一次执行的读数一并… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-DB-DRV-001 | SQL 方言协议：标识符引用、分页子句、库/模式/表/列清单、版本号查询与解析、关键字与函数表 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-002 | 语句拆分按方言：PostgreSQL 跳过 dollar-quote；GBase 支持 DELIMITE… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-003 | 拆分器只识别边界，不改写 SQL 原文 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-004 | 字符串、注释、dollar-quote 内的分号不得触发拆分 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-005 | 定义稳定的 DatabaseService 协议：连接、断开、执行（流式事件）、取消、事务 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-006 | 执行结果以事件流返回：started / resultSet / affectedRows / noti… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-007 | 工厂按数据库类型返回实现；未实现类型返回明确的「功能尚未实现」错误 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-008 | PostgreSQL 驱动使用成熟的协议实现，版本固定（依赖锁文件；具体库属平台实现，各端按同一契约实现… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-DRV-009 | GBase 8a 驱动实现（复用 MySQL 协议系的协议实现，具体库属平台实现） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-DRV-010 | MySQL 驱动实现：DatabaseType 新增 mysql 档（默认端口 3306、显示名 MyS… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 ⚠️ |
| FR-STD-DB-EXEC-001 | 查询自动归档：执行过的 SQL 自动保存成 .sql 文件，按天一个文件（queries/2026-09… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-DB-EXEC-002 | 按当前连接与上下文栏所选数据库执行 SQL，支持多语句 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-003 | 每条语句按顺序执行，逐条上报执行状态 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-004 | 同一连接的并发执行复用同一个连接，避免重复握手 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-005 | 空 SQL 或未选连接时给出明确提示而非静默失败 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-006 | 执行目标判定：有选区只跑选中的那段，没有选区跑整篇 —— 自动判定，不需要用户先设「运行范围」 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-007 | 事务模式：提供「自动提交」开关与提交 / 回滚按钮；手工事务下多条语句在同一事务内执行，出错可整体回滚 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-008 | 查询参数：SQL 中可用 :name / $1 占位符，执行前弹窗填值并做类型化转义，避免手工拼串 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-009 | 多结果集：全部保留，可通过下拉选择器切换查看 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-010 | 显示行数 × 列数与耗时 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-011 | 显示 SQL 错误详情，可选中复制；错误不导致 App 崩溃 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-012 | 执行中的页签不可关闭 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-013 | 执行返回「影响行数」（DML command tag） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-014 | 执行入口为工具栏图标按钮（绿色实心三角形 ▶），不使用文字按钮；快捷键 ⌘↩ | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-015 | 提供事务 API：beginTransaction / commit / rollback | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-016 | 查询工作区提供图标按钮工具栏，承载常见数据库客户端操作（执行 / 停止 / 检查，后续可扩展事务、导出、… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-017 | 高危语句保护（Safe Mode）：对不带 WHERE 的 UPDATE / DELETE，以及 DRO… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-EXEC-018 | 「停止」取消当前执行 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-IO-001 | 结果集导出：CSV / JSON / TSV / Markdown / INSERT（明细见 FR-ST… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-IO-002 | 客户端侧整表 / 整库导出：走 COPY <表> TO STDOUT 流式写文件 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 |
| FR-STD-DB-IO-003 | 备份 / 恢复：封装 pg_dump / pg_restore（plain / custom / dir… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-IO-004 | 备份文件恢复到指定库（pg_restore 的 --clean / --section / --jobs… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 |
| FR-STD-DB-IO-005 | 导出 CSV 的文本编码可选：UTF-8（带 BOM，默认）/ GB18030（GBK、GB2312 的… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-IO-006 | CSV / JSON 导入：COPY … FROM STDIN 流式导入 + 列映射与类型推断（不要求先… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-IO-007 | Excel（.xlsx）导入映射向导 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-META-001 | PostgreSQL 树形结构：服务器 → Database → Schema → Table / Vi… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-002 | GBase 8a 树形结构：服务器 → Database → Table → Column（无 sche… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-DB-META-003 | 懒加载：仅展开节点时查询下一层 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-004 | 自动过滤系统 schema（information_schema、pg_catalog、pg_toast… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-005 | 节点类型区分图标（库 / 模式 / 表 / 视图 / 列 / 函数） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-006 | 对象树必须支持持续下钻：从服务器节点开始，Database → Schema → Table / Vie… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-META-007 | 跨数据库浏览：服务器节点展开后列出当前用户可连接的数据库；展开非当前数据库时，按需建立指向该数据库的独立… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | 🟡 |
| FR-STD-DB-META-008 | 对象树按类型 / schema 分组视图：可在「层级视图」与「按类型分组」之间切换 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-META-009 | 列节点显示数据类型 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-010 | 对象树右键菜单（第一期：仅服务器节点）：右键「服务器」节点提供 ① 连接、② 断开、③ 编辑连接…；并根… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-011 | 查看对象 DDL：表 / 视图 / 函数节点右键「查看 DDL」，展示等价建对象语句并可复制 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-META-012 | 表 / 视图 / 列节点右键菜单（第二期）：浏览前 N 行、生成 SELECT / INSERT 模板、… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-013 | 元数据查询有行数上限保护（10,000 行） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-014 | 元数据加载失败给出错误提示，不阻塞 UI | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-META-015 | 全库对象搜索：输入名称片段即跨 schema / 跨库匹配表、视图、列、函数，命中结果可直接跳转并浏览数… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-001 | 结果表格使用平台原生表格控件桥接，支持大结果集滚动 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-002 | 列宽按内容估算，可拖动调整，可重排列顺序 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-003 | 支持多选行，⌘C 与右键菜单复制 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-004 | NULL 与空字符串可区分显示 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-005 | 二进制 / 复杂类型单元格转为可读字符串 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-006 | 复制为多种格式：复制即带表头，或直接是 Markdown / INSERT 文本（不发文件） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-007 | 客户端排序：点表头按列排序，支持多列（次要排序键）、升降序切换、NULL 位置固定；能解析成数字的列按数… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-008 | 客户端筛选：每列可加条件（包含 / 不包含 / 等于 / 大于 / 小于 / 为空 / 非空），多条件 … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-009 | 分页控制条：选择每页行数（50 / 100 / 200 / 500 / 1000），显示「第 N / M… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-010 | 结果导出为 CSV / JSON 文件 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-011 | 结果集分页 / 虚拟滚动超大数据量 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-012 | 导出扩展格式：TSV（表格软件友好）、Markdown 表格（贴文档 / 工单）、SQL INSERT … | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-RES-013 | 超大结果集流式落盘：导出直接写文件，不把全量结果驻留内存 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-RES-014 | 结果集导出 Excel（.xlsx） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-SESS-001 | 查询历史（按连接记录，可回填） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-SESS-002 | 服务器会话列表：展示当前实例的会话（进程号 / 用户 / 数据库 / 客户端地址 / 状态 / 等待事件… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-SESS-003 | 取消 / 终止会话：对选中会话执行「取消当前语句」（PG pg_cancel_backend；GBase… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-DB-SESS-004 | 服务器级对象管理：数据库 / 角色 / 表空间 / 扩展的浏览与创建（DBA 日常） （v3.0 扩写）… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-DB-SESS-005 | 权限管理：查看角色对库 / schema / 表 / 序列的已授权限；生成并执行 GRANT / REV… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-SESS-006 | 库属性管理：ALTER DATABASE（owner / 库级参数 / 连接限制）与 DROP DATA… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-DB-TASK-001 | 一句话 → 一条可执行任务：任务定义落在连接上（目标库、只读 / 可写、影响行数上限、是否需审批），保存… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-DB-TASK-002 | 高危任务执行前逐条列出：将要执行的语句、目标库、预估影响范围，等人工确认；确认才发送，拒绝即中止并留痕。 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-DB-TASK-003 | 执行回执：记录成功 / 失败、影响行数、耗时、错误原文与执行时刻，挂在会话上可作为审计依据；回执不含口令… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-AI-001 | 工作区编辑区的 AI 辅助编程（需求提出者 2026-09-30 定：「编辑区如何接入 AI 辅助编程」… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-AI-002 | 许愿式编程：用一段话描述要做的事，Agent 在整个工作区范围内多次读写文件后交付可运行结果（不是单点补… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-001 | 工具栏在执行按钮之前提供「保存查询」按钮：把当前页签的 SQL 持久化保存（可命名），并可从已保存列表回… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-002 | 工具栏保存按钮拆分：主体 = 直接保存（有文件路径则写回磁盘；无路径等同另存为）；右侧下拉箭头 = 另存… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-EDIT-003 | 工具栏新增「编辑」按钮（下拉菜单入口），菜单包含：查找 / 替换、跳到指定行或列、缩进 / 反缩进选中文… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-004 | 编辑菜单 → 清除查询：一键清空当前页签 SQL | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-EDIT-005 | 工具栏与菜单的快捷键全覆盖：工具栏每个按钮都有快捷键，tooltip 显示按键；「帮助」面板列出完整快捷… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-EDIT-006 | Markdown 续行（同一由头）：① 无序列表（- / * / +）回车续同一符号；② 有序列表回车序… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-007 | 工作区 Markdown 的任务框勾选翻转（⌘L）（同一由头）：在 Markdown 文档里按 ⌘L —… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-008 | 注释切换（⌘/）：按当前语言的注释符给光标行加 / 取消行注释；多行选区 ⇒ 逐行处理且保持缩进；注释符… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-009 | 移行与复制行：⌥↑ / ⌥↓ 把当前行（或选中整段）整体上移 / 下移，光标与选区跟着走；⇧⌥↓ 向下复… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-010 | 编辑菜单 → 查找 / 替换：在当前 SQL 中查找与替换文本 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-EDIT-011 | 编辑菜单 → 跳到指定行或列：输入行号（可选列号）后光标定位并滚动到可见位置 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-012 | 跨文件内容搜索与替换（同「非常单薄」的量化结果：Core/WorkspaceSearch.swift 目… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-EDIT-013 | 工作区标头的搜索框（快速查找文件标题与内容关键字）（需求提出者 2026-09-30 原话：「works… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-EDIT-014 | 撤销语义粒度：一段连续输入合并成一次撤销（不逐字符），行级编辑（移行 / 注释切换 / 补全）各算一步；… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-015 | 整批撤回：一次任务内的多处文件改动可按批次一次撤回，只撤 Agent 改的、不动人手改的 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-016 | 多光标与列编辑：⌥ 拖拽 / ⌘D 增加光标，一次修改多处（进阶） | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-017 | 代码折叠：按语言块级规则折叠函数 / 块 / 区域，行号槽给折叠标记；折叠状态按文件在会话内记住；折叠不… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-018 | 编辑菜单 → 缩进 / 反缩进选中文本（多行按行处理） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-019 | 括号 / 引号自动配对与跳引号：打出 ( [ { " ' 反引号 ⇒ 自动补右半并把光标留在中间；光标已… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-EDIT-020 | 括号匹配高亮：光标紧邻括号时，与它配对的另一个括号同时点亮（走主题令牌，不写死颜色）；不配平 ⇒ 给告警… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-021 | 自动缩进与智能粘贴：回车时继承上一行缩进；{ / ( / [ 之后回车多一级、} 单独一行回退一级；粘贴… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-022 | 缩进检测与状态栏切换：打开文件时按内容判定软 / 硬 tab 与宽度（不靠扩展名猜），状态栏显示当前口径… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-023 | 编码与换行：按文件真实编码与换行符打开（UTF-8 / GB18030、LF / CRLF），保存时不悄… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-EDIT-024 | 大脚本保护：超长 SQL 暂停静态检查，避免输入卡顿 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-FS-001 | 工作区视图有自己的页签集，默认打开 Home 欢迎页：在活动栏切到「工作区」时，编辑区不再沿用数据库 S… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-FS-002 | 活动栏 + 工作区 Explorer：主窗口最左侧加一条窄的固定宽度活动栏（46pt）：上排切换「数据库… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-FS-003 | 工作区 Explorer 的文件操作（需求提出者 2026-09-30：「现在的工作区功能非常单薄」；现… | ⬜ | ⬜ | ⬜ | ✅ ⚠️ |
| FR-STD-WS-FS-004 | 新建文件：在工作区里新建空白文件或按模板新建，落在选中的目录下，输入名即建，重名要提示 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-FS-005 | 重命名：文件与目录就地重命名，输入即改；已打开的页签与引用同步跟着改 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-FS-006 | 删除：删除文件或目录进废纸篓（不是直接抹掉），可恢复；删除前显示将影响几个文件 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-FS-007 | 工具栏新增「打开文件」按钮：通过系统打开面板选择 SQL / 文本文件，内容载入新建页签；该页签默认不绑… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-FS-008 | 在工作区里点文件直接打开，并按文件类别匹配呈现：文本 / 代码文件在编辑器区打开；按扩展名（.sql /… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-FS-009 | 外部改动监听：文件被编辑器外的程序改动时，界面立即反映并提示重新载入或对比 | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-FS-010 | 工作区切换：可在多个已知工作区之间切换，同一时刻只有一个活动工作区（不做并发多根） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-HELP-001 | 工具栏新增「帮助」按钮（问号图标），承载帮助入口；具体内容待定，先放置占位 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-LIC-001 | 工作区里的授权呈现（同一能力点 4.1.35 的界面侧，与上面五条同节、不另立节）：由授权决定哪些入口出… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-NAV-001 | 语法着色：关键字 / 函数 / 字符串 / 注释 / 数字 / 引用标识符分别配色（运算符保持默认色） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-002 | 多语言关键字高亮方案（语言表可扩展 + 每语言一套高亮规则 + 颜色走主题令牌）：① 语言表可扩展 ——… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-NAV-003 | SQL 自动补全（关键字 + 内建函数） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-004 | 自动补全接线与扩展：补全在编辑器内真的可触发（FR-STD-WS-NAV-003 的 SQL 关键字 /… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-NAV-005 | 片段模板（snippets）：按语言给片段（SQL 的 select / join 骨架、Markdow… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-NAV-006 | 悬停文档与跳转到定义（词法级起步）：悬停给一句话说明 + 定义位置；点 / 快捷键跳到定义（先做同文件符… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-NAV-007 | 客户端静态检查：未闭合字符串、未闭合块注释、未闭合 dollar-quote、括号不配平 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-008 | 静态检查基于当前方言的关键字与函数表 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-009 | 服务器端语法检查：「检查」按钮对可 EXPLAIN 的语句执行 EXPLAIN，不真正执行 DML | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-010 | 检查结果：通过显示「已检查 N 条，跳过 M 条」；失败最多显示 3 条错误 + 余量提示 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-011 | 修改 SQL 后清空上一次检查结果 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-012 | 静态检查结果上屏（诊断）：把 FR-STD-WS-NAV-007 的检查结论画到编辑器上 —— 出问题的… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-NAV-013 | 编辑菜单 → 格式化 SQL：对当前 SQL 做关键字大写、子句换行与缩进 | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-NAV-014 | 代码格式化能力：对当前工作区文件按语言格式化（编辑器菜单 / 快捷键入口），格式化前后可撤销、结果与原文… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-TOOL-001 | 底部终端面板：主窗口底部可拖拽 / 可折叠的面板，内嵌本机交互式 shell（真 PTY + VT100… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-TOOL-002 | 工作区下方面板（应用级通用面板）：页签为 问题 / 输出 / 终端 / 调试控制台；外层页签条（问题 /… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-TOOL-003 | 调试器：经 DAP 接入既有调试器，支持断点、单步、变量查看（不自研调试协议） | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-UI-001 | 多页签：新建（⌘T）、切换、关闭；至少保留一个页签 （v3.0 扩写）支持多窗口：同一连接可在多个窗口并… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-UI-002 | 新建查询页签的编号在应用生命周期内单调递增（1、2、3…），不受页签被关闭、重命名或切换连接影响；从文件… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-UI-003 | 关闭有未保存改动的文件页签：确认，不阻塞（需求提出者 2026-10-03 原话：「文件打开后被修改，点… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-UI-004 | 会话恢复（同「非常单薄」的量化结果：App/WorkspaceTabsModel.swift 里没有恢复… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-UI-005 | 命令面板：⌘K 唤起，可搜索并执行「新建查询 / 执行 / 检查 / 格式化 / 导出 / 切换连接 /… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-UI-006 | 窗口标题跟着活动栏走 + 标题栏居中的搜索栏：主窗口标题随活动栏当前视图变化（Doyah Studio … | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ✅ ⚠️ |
| FR-STD-WS-UI-007 | SQL 编辑区与结果区之间提供可拖拽分隔条，用户可实时调整两区高度（放大 / 缩小结果区） | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-UI-008 | 主题与字体：浅色 / 深色跟随系统或手动指定，编辑器等宽字体与字号可调 | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-UI-009 | 外观配置：主题（配色方案）+ 强调色：主题跟随系统外观（浅色原生精致 / 深色专业暗色）；主题（配色方案… | ✅ | ⬜ ⚠️ | ⬜ ⚠️ | ✅ |
| FR-STD-WS-UI-010 | 页签条的高度不由内容决定（2026-10-20 从概要设计 §3.30 回流）：应用内 chrome 行… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-UI-011 | 编辑面的底色与字色只用主题令牌（2026-10-20 从概要设计 §3.31 回流）：凡是能编辑多行文本… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-VCS-001 | Git 只读与差异：显示当前工作区的分支、改动文件清单与逐行差异（不做提交 / 推送 / 合并 / 切分… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-VCS-002 | 差异视图：对 Git 工作区的改动可逐个文件看逐行 +/-，可忽略空白、可折叠上下文、大文件按需渲染；差… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-WEB-001 | 内嵌浏览器页签（工作区，完整浏览器）：在工作区开一个可关闭的浏览页签（与 Home、文件页签同一类，不是… | 🟡 | ⬜ ⚠️ | ⬜ ⚠️ | ⬜ ⚠️ |
| FR-STD-WS-WEB-002 | 工作区编辑器的 Markdown 预览（需求提出者 2026-09-30 原话：「工作区的编辑器还要带 … | ⬜ | ⬜ | ⬜ | ✅ ⚠️ |
| FR-STD-WS-WEB-003 | 网页文件不是只能看源码：.html / .htm 打开后可在编辑器内切换「预览」（与 FR-STD-WS… | ⬜ | ⬜ | ⬜ | ⬜ |
| FR-STD-WS-WEB-004 | 站点兼容：对站点呈现常规浏览器身份：浏览器页签对站点而言是一个常规浏览器，不是「某个应用的内嵌面板」——… | ⬜ | ⬜ | ⬜ | ⬜ |
<!-- END platform-parity -->

**FR-STD-DB-DATA-002 按条件浏览 / 计数清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：语句生成有 16 项单测，且两种形状的真实语句已在 217 上跑通（`Scripts/test-table-structure.sh` 第 3.5 步）。
> 下面这些是面板交互与"拒绝得是否讲理"的部分。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 右键一张表 → 「按条件浏览…」 | 面板打开；预览里是 `SELECT * FROM … LIMIT 200 OFFSET 0;`；面板上写明「条件会发给数据库」 |
| 2 | WHERE 里填 `id > 0`，ORDER BY 填 `id DESC` | 预览即时变成 `WHERE id > 0 ORDER BY id DESC LIMIT 200 OFFSET 0;`（顺序不能乱） |
| 3 | 点「浏览」 | 新页签出现该语句并**自动执行**；结果区显示命中行 |
| 4 | 点「统计行数」 | 新页签出现 `SELECT count(*) FROM … WHERE …;` 并执行；结果区显示行数（语句里**没有** ORDER BY） |
| 5 | WHERE 里写 `a = 1; DROP TABLE t` | 预览显示拒绝原因、**两个按钮都禁用**；点不动（绝不下发多语句） |
| 6 | WHERE 里粘 `id > 0 ORDER BY id`（ORDER BY 框留空） | 自动拆开：预览里 WHERE 与 ORDER BY 各就各位，只有一个 ORDER BY |
| 7 | ORDER BY 框也填上内容再重复上一步 | 提示两处都写了 ORDER BY，按钮禁用（不生成两个 ORDER BY） |
| 8 | WHERE 里写 `status = 'a;b'` | 同样被拒绝（条件框里出现分号一律拒绝 —— 宁可让人改写，也不猜） |
| 9 | 行数填 -5、偏移填 0 | 预览里被夹到 `LIMIT 0`，不生成非法语句 |

**FR-STD-DB-DDL-003 表设计器清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：结构读取已在真机核对（`Scripts/test-table-structure.sh`），差异计算与 ALTER 生成有 12 项单测。
> 下面这些是**必须有人点一遍**的部分 —— 尤其是"改完到底有没有生效"与"失败时会不会谎报成功"。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 在测试库选中一张表 → 右键「修改表结构…」 | 面板打开，列出全部列及其类型 / 可空 / 主键 / 默认值；**加载失败时给可读错误**，不显示成空表 |
| 2 | 加一列（如 `extra text`）+ 改一列类型 + 勾掉某列的「可空」 | 右下预览**实时**跟着变，且只包含真正改动的列（没改的列不应出现在 ALTER 里） |
| 3 | 点「应用」→ 回到对象树刷新 | 结构确实变了（列出现 / 类型变了 / 该列不再允许 NULL）；状态栏写「已修改 N 处」 |
| 4 | 改一处**非法**内容（如列名留空、类型清空） | 应用按钮禁用并指明问题；预览处也说清楚，而不是等执行报错 |
| 5 | 故意让中间一条 ALTER 失败（例如把列类型改成不兼容的类型） | 报错**指明是第几条**；对象树仍刷新（前面的语句可能已生效），**不谎报成功** |
| 6 | 新建表：填表名 + 两列（一列主键） | 预览是完整的 `CREATE TABLE`（主键写成 `PRIMARY KEY`，主键列强制 `NOT NULL`）；执行后表出现在对象树里 |
| 7 | 对视图 / 序列节点找「修改表结构…」 | 不出现该项（该动作只对表可用） |
| 8 | 面板里「索引」区：既有索引都列出来了（含 `t_pkey`） | 取消勾选某个自建索引 → 预览出现 `DROP INDEX …`，破坏性提示里也列出它 |
| 9 | 加一条索引：名字 + 列（逗号分隔）+ 勾「唯一」+ 条件（如 `email IS NOT NULL`） | 预览出现 `CREATE UNIQUE INDEX … WHERE email IS NOT NULL;`；应用后索引真的存在（回对象树刷新后重开面板能看到） |
| 10 | 「外键与约束」区：加一条约束，定义填 `CHECK (age > 0)` | 预览出现 `ALTER TABLE … ADD CONSTRAINT … CHECK (age > 0);`；应用后生效 |
| 11 | 加一条外键：本表列 `owner_id` → 引用表 `u`、引用列 `id`，`ON DELETE` 选 `CASCADE` | 预览里的语句含 `ON DELETE CASCADE`；应用后生效 |
| 12 | 试着取消勾选**主键** | 勾选框禁用并提示「主键不在此处删除（请用 SQL）」—— 不给误点的机会 |
| 13 | 同时做「删一个索引 + 加一列 + 加一条索引」并应用 | 预览里语句**顺序**是：删索引 → 加列 → 建索引（先腾地方、再改结构、最后建依赖）；应用后全部生效 |
| 14 | 故意把新索引的列留空 | 该行被忽略（不生成半截语句）；若名字非空但列空则预览不出现它 |

**FR-STD-DB-META-011 视图 / 函数 DDL 清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：查询构造与装配由 12 项单测覆盖，**真机取回与装配已用 `Scripts/test-object-ddl.sh` 验过**（退出码 0）。
> 下面这几步是界面呈现的部分 —— 菜单项在不在、内容有没有进编辑器。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 连上 217，展开一张有视图的 schema，右键**视图** | 菜单里有「查看建表 DDL」；点它 → 新页签出现 `CREATE OR REPLACE VIEW "schema"."视图名" AS …`，**只有一条语句、只有一个结尾分号** |
| 2 | 右键一个**函数** | 同样有该项；点它 → 新页签出现 `CREATE OR REPLACE FUNCTION …`（GBase 上应为 `SHOW CREATE FUNCTION` 的结果） |
| 3 | 找一个**同名重载**的函数（两个不同参数列表） | 新页签里**两个定义都在**（空行分隔）—— 只出现一个就是漏了重载 |
| 4 | 右键**序列**或 **schema** 节点 | 不出现「查看建表 DDL」（该动作只对表 / 视图 / 函数可用） |
| 5 | 对同一个视图连点两次 | 每次都是同样内容（元数据查询无副作用）；编辑器里**没有任何自动执行** |

**FR-STD-DB-EXEC-007 事务模式清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：状态机的时机判断由 16 项单测覆盖（`TransactionSessionTests`）；
> 下面这些是**必须有人点一遍**才能确认的部分（按钮启用态、徽标呈现、真实回滚是否真的没写进去）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 新建页签，看工具栏事务控件 | 停在「自动提交」；没有提交 / 回滚按钮，也没有徽标 |
| 2 | 切到「手工事务」 | **不立刻**出现「事务进行中」（懒开启）；提交 / 回滚按钮此时禁用 |
| 3 | 执行一条 `SELECT 1` | 出现徽标「事务进行中 · 已执行 1 条」；提交 / 回滚变成可用 |
| 4 | 再执行一条 `SELECT 2` | 徽标条数变 2（同一事务内） |
| 5 | 点「提交」 | 徽标消失；状态栏写「事务已提交」 |
| 6 | 在测试库建一张表 → 插入一行 → **不提交**，另开一个连接（或另一个客户端）查这张表 | **看不到**那一行（事务确实没提交）—— 这是本清单最关键的一步 |
| 7 | 回来点「回滚」 | 徽标消失；表**不存在**（DDL 也一起回滚了） |
| 8 | 开一条事务后执行一条会报错的语句（如重复主键 / 语法错） | 徽标变成红色「事务已失败 —— 只能回滚」；提交按钮禁用；再执行别的语句被拒并提示「事务已失败，请先回滚」 |
| 9 | 点「回滚」后再执行正常语句 | 恢复可用（重新 BEGIN） |
| 10 | 开一条事务（有徽标），切到**另一个连接**再切回来 | 状态栏提示「连接或数据库已切换：未提交的事务已回滚」；徽标消失 |
| 11 | 开一条事务，然后直接改该连接的配置（或删除连接） | 同样提示已回滚；不出现「已提交」的假提示 |
| 12 | 开一条事务，尝试把开关切回「自动提交」 | **被拒**并提示「请先提交或回滚」；开关仍停在手工事务 |
| 13 | 提交 / 回滚一条事务后，观察 Output 日志与查询历史 | 事务命令与语句都留痕；历史里失败的那条不是成功记录 |

**FR-STD-DB-RES-007 / 09 / 10 结果区客户端视图清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：排序 / 筛选 / 分页的**纯逻辑**由 39 项单测覆盖（`ResultGridStateTests` 15、
> `SQLFilterInjectionTests` 13、`ResultFilterSQLTests` 11）；
> 下面这些是**必须有人点一遍**才能确认的部分（表头指示器、筛选条的输入体验、分页与复制的对应关系、生成 WHERE 是否插对位置）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 对 `SELECT * FROM 一张有数字列与文本列的表` 执行，点**文本列**表头 | 按本地化自然序升序（`item2` 在 `item10` 前）；表头出现升序指示器 |
| 2 | 再点同一列 | 反转成降序，指示器方向跟着变 |
| 3 | 第三次点同一列 | 排序消失，**回到服务端返回的原始顺序**（不是停在降序） |
| 4 | 点**数字列**表头 | 按数值排序（`2` 在 `10` 前），**不是**字符串序 |
| 5 | 按住 Shift 点第二列 | 该列成为次要排序键；结果区左侧出现带序号的可点排序键（表头指示器只表达第一键） |
| 6 | 点排序键上的 × / 排序键区的清除按钮 | 对应键被移除；主键保留 |
| 7 | 点「+」加一条筛选：列＝文本列、运算符＝包含、值填一个子串 | 行数立即减少；**页码回到第 1 页**；结果区出现「仅对已加载的 N 行生效（客户端排序 / 筛选）」 |
| 8 | 把运算符改成「为空」 | 值输入框消失（该运算符不需要值）；NULL 行与空字符串行都命中 |
| 9 | 再加一条条件并清掉其中一条 | 两条是 AND 关系；清掉一条后另一条仍生效 |
| 10 | 每页行数切到 `50`，翻到第 2 页 | 页码显示「第 2 / M 页 · 共 K 行」；翻页后**选中一行按 ⌘C**，粘贴出来的是**当前页那一行**（不是原始顺序里的行） |
| 11 | 把每页行数改成「全部」 | 不再显示分页条，整段显示 |
| 12 | 筛选状态下点「用筛选条件生成 WHERE」 | **不自动执行**；编辑器末尾（或 `ORDER BY` / `LIMIT` 之前）出现 `WHERE …`，状态栏提示「请过目后再执行」 |
| 13 | 编辑器里先写 `SELECT 'where' AS x FROM t;` 再点生成 | 条件插在分号之前，**不**因为字符串里出现 where 就拒绝 |
| 14 | 编辑器里写 `… WHERE a = 1` 再点生成 | **不合并**：状态栏提示「已有 WHERE，请手动并进去」，原语句一字未改 |
| 15 | 编辑器里写两条语句（`SELECT 1; SELECT 2;`）再点生成 | 给出「请先只保留要重新查询的那一条」的可读提示，原语句未改 |
| 16 | 重新执行查询（换结果集） | 上一次的排序 / 筛选 / 分页全部归零（新数据不该套用旧条件） |
| 17 | 对同一张表加 `LIMIT 20` 执行后再筛一次 | 提示里的行数就是**已加载的 20 行**（客户端筛选不查库 —— 这是 R-021 要讲清的事） |


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

## 7 待补材料

| 材料 | 建议位置 | 状态 |
|---|---|---|
| 概要设计文档（原《需求分析与概要设计 v1.2》未纳入本工程） | `Docs/Doyah产品概要设计说明书.md` | ✅ 已交付（v2.0：架构分层、数据流、模块清单、ADR-01 ~ 15、并发与取消语义） |
| 端到端测试用例（按 UC-01 ~ UC-20 展开） | `Docs/测试用例.md` | ✅ 已交付（v2.0：TC-01 ~ TC-63、AC-ALL-GATE-REL-04 验收清单、缺陷回归模板） |
| PostgreSQL / GBase 兼容性测试矩阵 | `Docs/兼容性矩阵.md` | ✅ 已交付（v2.0，T-14；12–15 / 17 行待有实例时用回归脚本补测） |
| 发布包签名方案（当前 ad-hoc，正式发布需 Developer ID + 公证） | `Docs/发布方案.md` | ✅ 已交付（v2.0：签名 / 公证 / 装订步骤、12 项发布前检查） |
| GBase 8a 驱动技术验证记录 | `Docs/GBase-技术验证.md` | ✅ 已交付验证计划与检查表（v2.0，T-15）；驱动实现与实测待 GBase 8a 实例 |


## 8 进展记录

| 日期 | 变化 | 说明 |
|---|---|---|
| 2026-10-20 | 建账 | 本文件首版：从需求规格说明书迁出 393 条状态（FR 335 · NFR 46 · AC 12），原书不再写状态。 |

## 9 已知卡点

| 卡点 | 影响 | 登记处 |
|---|---|---|
| `pg_stat_statements` 未装（`rolsuper=false`） | 数据库面慢查询统计拿不到 | 派单 `T-20261018-206` |
| Linux 端未开工 | 跨端条目停在 ⬜ | 需求规格说明书 §3.1.3 |

## 10 历史任务清单（2026-09-20 · 2026-09-21 夜）

> **这两张表是执行记录，不是需求** —— 2026-10-20 从《需求规格说明书》§10.7 / §10.7.1 整段迁来（原文搬运，只改了节号）。条目里的 `T-*` 号属当时的派单体系；现在的派单在 `~/.dsh/projects/doyah-dispatch/`。
> **别再往这里加新任务**：新活在派单里开，这里只做存档。


### 10.1 开发任务列表（2026-09-20）

> 规则：任务完成后同时更新对应需求的状态列与 10.2 追溯表；任务编号 `T-xx` 只增不删；已完成任务保留并勾选。

**本次新增需求的任务拆解**

- [x] **T-01 国际化（中文 / 英文切换）（开发完成）** → 需求：NFR-ALL-GATE-LANG-03（依赖 NFR-ALL-GATE-LANG-02）
  - [x] `Core/Localization.swift`：`AppLanguage` + `LKey`（110 个文案键）+ 中 / 英文案表 + 格式化
  - [x] `App/LocalizationManager.swift`：读写 UserDefaults，默认跟随系统（`AppLanguage.systemDefault`）
  - [x] 入口：菜单「语言 / Language」→ 简体中文 / English 选择
  - [x] 全量替换：`App/` 下 0 条硬编码中文界面文案（含 AppState 状态文案、ErrorPresenter、SQLLinter 诊断）
  - [x] 切换即时生效：根视图按 `.id(language)` 整体重建；日期格式按语言 Locale
  - [x] 单测：`Tests/LocalizationTests.swift` 6 项（key 两种语言齐全 / 无缺失 / 格式化 / 诊断语言）
  - [ ] 真实库手工回归：切英文后逐页检查无中文残留、重启保持（并入 AC-ALL-GATE-REL-04）
- [x] **T-02 编辑区 / 结果区可拖拽分隔（开发完成）** → 需求：FR-STD-WS-UI-007
  - [x] `QueryEditorView` 改用 `VSplitView`（自带拖拽分隔条）
  - [x] 两区最小高度 120 pt（`idealHeight` 260），窗口缩放时由 split 自行分配
  - [ ] （可选）拖拽比例持久化到 UserDefaults —— 暂不做，保留为后续可选项
  - [ ] 真实库手工回归：拖动分隔条实时改变结果区高度（并入 AC-ALL-GATE-REL-04）
- [x] **T-03 对象树持续下钻（开发完成，待真实库验收）** → 需求：FR-STD-DB-META-006 / FR-STD-DB-META-001 / FR-STD-DB-META-007、R-012
  - [x] 代码定位：旧 UI 在 `List` 行内嵌套 `DisclosureGroup`，第 3 层起不可靠；服务层四层映射本身正常
  - [x] 修复：`App/Views/ObjectTreeView.swift` 重写为**扁平化树**（自维护展开状态 + 缩进行），任意层级可展开
  - [x] 结构升级：根节点改为**服务器**，服务器下是**数据库**；展开非当前库时按需建立该库的独立连接并缓存（FR-STD-DB-META-007，App 与 CLI 均已实现）
  - [x] 空态 / 失败态：空 schema 显示「该 schema 下暂无表 / 视图」，失败可读且可重试；新增刷新按钮
  - [x] 服务层回归：`Tests/MetadataServiceTests.swift` 8 项（含空 schema、服务器 → 数据库）；本地链路新增 4 条断言（服务器根 / 数据库列表 / 空 schema / 双库按需连接），当前 25/25
  - [ ] 真实库验收：确认服务器节点下能看到多个数据库；分别展开到 schema / 表 / 列；在查询区执行 `SELECT table_schema, table_name FROM information_schema.tables ORDER BY 1, 2;` 交叉确认
- [x] **T-04 保存查询 SQL（开发完成）** → 需求：FR-STD-WS-EDIT-001、FR-STD-ALL-DATA-004
  - [x] `SavedQuery` 模型（id / name / connectionID / database / sql / savedAt）
  - [x] `SavedQueryStore`：JSON + 原子写，存 Application Support（沙箱容器），不含密码；3 项单测
  - [x] `QueryToolbar` 在执行按钮之前新增保存按钮（`bookmark`）+ 已保存列表（`list.bullet`）
  - [x] 保存交互：命名保存（默认取 SQL 首行）；重名提示「覆盖保存」
  - [x] 回填交互：已保存列表 → 载入当前页签；（可选）删除
  - [ ] 真实库手工回归：保存 → 重启 App → 回填；确认 `saved-queries.json` 无密码字段（并入 AC-ALL-GATE-REL-04）
- [x] **T-05 服务器 / 数据库选择栏（开发完成）** → 需求：FR-STD-DB-CONN-015、FR-STD-DB-CONN-016
  - [x] 新增 `App/Views/QueryContextBar.swift`：服务器下拉（已保存连接）+ 数据库下拉
  - [x] 数据库枚举走方言：PG `pg_database` + `has_database_privilege(current_user, datname, 'CONNECT')`；GBase `SHOW DATABASES`
  - [x] 权限：仅展示当前登录用户可见 / 可连接的数据库（无权限库不出现）
  - [x] 连接策略：按 (connectionID, database) 缓存独立 `DatabaseService`；查询 / 语法检查在所选库执行
  - [x] 与左侧连接列表双向联动（同一 `selectedConnectionID`）
  - [ ] 真实库手工回归：切换数据库后 `SELECT current_database()` 与所选一致；切换服务器后对象树刷新（并入 AC-ALL-GATE-REL-04）

- [x] **T-16 页签编号单调递增（已实现）** → 需求：FR-STD-WS-UI-002
  - [x] `Core/TabNumberGenerator.swift`（只增不减，初始 1）
  - [x] `AppState.tabNumbers` + `newQueryTab()` / `init()` 使用生成器，替换原来的 `tabs.count + 1`
  - [x] `Tests/TabNumberGeneratorTests.swift` 3 项（连续递增 / 关闭后不回退 / 生成器独立）
  - [ ] 手工回归：新建（查询 1、2）→ 关掉查询 1 → 再新建应为「查询 3」（并入 AC-ALL-GATE-REL-04）
- [x] **T-17 打开文件 → 新页签（开发完成）** → 需求：FR-STD-WS-FS-007
  - [x] 工具栏「打开文件」按钮（`folder` 图标）+ `NSOpenPanel`（.sql / .txt / 文本）
  - [x] 新建页签：标题 = 文件名、`connectionID = nil`、记录 `fileURL`
  - [x] 工作区允许「无连接页签」渲染编辑器；页签上显示「未绑定连接」提示
  - [x] 读取失败（编码 / 权限）给出可读错误；PDF/RTF 等非文本格式明确拒绝
  - [ ] 验收：打开文件 → 新页签显示内容 → 编辑不改原文件；执行时提示先选连接
- [x] **T-18 保存 / 另存为（开发完成）** → 需求：FR-STD-WS-EDIT-002
  - [x] 保存按钮主体 = 直接保存：有 `fileURL` 写回，无 `fileURL` 走另存为
  - [x] 保存按钮右侧下拉箭头（`chevron.down`）→ 菜单「另存为…」
  - [x] `NSSavePanel` 默认文件名 = 页签标题，扩展名 .sql
  - [x] 成功后更新页签标题与 `fileURL`；失败给出可读错误；保存后未保存标记清零
  - [x] （建议）页签标题用「•」标记未保存改动
- [x] **T-19 编辑菜单（六项功能）（开发完成）** → 需求：FR-STD-WS-EDIT-003 ~ FR-STD-WS-NAV-013
  - [x] 工具栏「编辑」按钮 + 下拉菜单入口
  - [x] 查找 / 替换：接入系统 Find Bar（`usesFindBar` + `performFindPanelAction`）
  - [x] 跳到指定行 / 列：输入框 + 越界处理 + 滚动定位
  - [x] 缩进 / 反缩进选中文本（4 空格）（未选中时作用于当前行）；缩进单位定稿
  - [x] 清除查询（支持 ⌘Z 撤销），同步清理诊断 / 检查结果
  - [x] 格式化 SQL：保守规则已实现 + 4 项单测（大小写 / 换行 / 缩进），失败保持原文
  - [x] 需要给 `SQLEditorView` 建立「编辑器命令」通道（工具栏 → 当前 NSTextView）
- [x] **T-20 帮助按钮（占位）（开发完成）** → 需求：FR-STD-WS-HELP-001
  - [x] 工具栏问号按钮（`questionmark.circle`），点击暂不执行动作或显示「帮助内容待补充」
  - [x] 预留后续挂载：快捷键说明 / 使用文档 / 关于

**既有待办汇总（v1.3 之前遗留，v2.0 收口）**

- [x] **T-06 删除连接二次确认（已完成）** → 需求：FR-STD-DB-CONN-009 / R-009
  - [x] `ConnectionListView` 增加 `@State pendingDeletion` + `confirmationDialog`
  - [x] 提示文案明示「连带删除钥匙串密码且不可撤销」，删除为 destructive 角色，另有取消按钮
  - [x] 确认后走原逻辑：Keychain 密码 → 连接缓存（`invalidateService`）→ 配置落盘
  - [x] R-009 关闭；手工验收：右键删除 → 出现确认框 → 取消不删除、确认才删除
- [x] **T-07 表单校验复用 `ConnectionConfig.isValid`（已完成）** → 需求：FR-STD-DB-CONN-003 / R-010
  - [x] 表单 `isValid` 改为「端口先独立解析 + `makeConfiguration().isValid`」，单一事实来源
  - [x] 端口非数字 / 越界（≤0 或 >65535）时校验失败，「测试连接 / 保存」禁用
  - [x] 模型层规则由 `Tests/ConnectionConfigTests.swift` 覆盖；R-010 关闭
- [x] **T-08 服务端查询取消（已完成）** → 需求：FR-STD-DB-EXEC-018 / R-002
  - [x] 连接成功后查询并缓存 `SELECT pg_backend_pid()`
  - [x] `PostgresService.cancel()` 用**独立连接**执行 `SELECT pg_cancel_backend(pid)`（同连接会排队，无法中断当前语句）
  - [x] 取消只终止语句、不断开连接；失败仅记日志，不影响本地 Task 取消路径
  - [x] 本地链路用例 7 实测：`SELECT pg_sleep(30)` 在 1 s 后被取消，错误信息 `canceling statement due to user request`（链路 25/25）；R-002 关闭
- [x] **T-09 结果导出 CSV / JSON（已完成）** → 需求：FR-STD-DB-RES-010
  - [x] `Core/ResultExporter.swift`：CSV（RFC 4180 转义、CRLF、可选 UTF-8 BOM）、JSON（columns / rows / rowCount / affectedRows、重复列名后缀、NULL 与空串区分）
  - [x] 结果区右上角导出菜单（CSV / JSON）→ `NSSavePanel`（按扩展名限制类型，默认文件名取页签文件名）
  - [x] 无结果集且无影响行数时提示「没有可导出的数据」；写盘失败给出可读错误
  - [x] `Tests/ResultExporterTests.swift` 10 项（BOM / 转义 / 无列 / 重复列 / 转义字符 / 影响行数 / 分派）
- [x] **T-10 SQL 补全接入编辑器（已完成）** → 需求：FR-STD-WS-NAV-003
  - [x] `SQLEditorView.Coordinator` 实现 `textView(_:completions:forPartialWordRange:indexOfSelectedItem:)`
  - [x] 候选项 = `SQLCompleter.suggestions(for:dialect:)`（当前连接方言的关键字 + 内建函数，最多 20 条）
  - [x] 触发方式：F5 / Esc（系统）与 ⌃Space（`SQLTextView.keyDown`）
  - [x] 补全范围按 SQL 标识符（字母 / 数字 / `_`）计算，`my_table` 不被切断
- [x] **T-11 查询历史（已完成）** → 需求：FR-STD-DB-SESS-001
  - [x] `AppState.queryHistory`（内存，最多 50 条）+ `recordHistory` / `clearQueryHistory` / `loadHistory`
  - [x] 成功与失败都记录（✓ / ✗ + 耗时），连续重复执行只刷新最新一条
  - [x] 工具栏时钟菜单：最近 20 条摘要，点击回填当前页签，支持清空
  - [x] 按 FR-STD-ALL-DATA-002 不落盘（隐私优先）；退出应用即清空
- [x] **T-12 影响行数 command tag（已完成）** → 需求：FR-STD-DB-EXEC-013 / R-001
  - [x] `PostgresService.reportsAffectedRows(_:)` 判定 `INSERT / UPDATE / DELETE`（跳过前置注释、排除 `RETURNING`）
  - [x] 该类语句走 EventLoopFuture 路径，从 `PostgresQueryMetadata.rows` 读取行数
  - [x] 写入 `QueryResult.affectedRows` + 发出 `.affectedRows` 事件：状态栏「第 N 条语句影响 M 行」、结果区「影响 M 行」、CLI `affectedRows: M`
  - [x] `Tests/PostgresServiceTests.swift` 3 项判定单测 + 链路用例 6（INSERT 3 / UPDATE 2 / DELETE 1）；R-001 关闭
  - [ ] 已知边界：`WITH … UPDATE`、`COPY`、DDL 不返回影响行数（PostgreSQL 协议本身不提供或 PostgresNIO 不解析），已记入 `Docs/兼容性矩阵.md`
- [x] **T-13 记忆上次选中连接（已完成）** → 需求：FR-STD-DB-CONN-010
  - [x] 选择变化即写入 `UserDefaults`（`settings.selectedConnectionID`）
  - [x] 启动时恢复：仅当该连接仍存在；否则回退列表首条（删除连接场景不残留悬空 ID）
  - [ ] 手工验收：选中第 2 条连接 → 退出 → 重新打开仍是第 2 条（并入 AC-ALL-GATE-REL-04）
- [x] **T-14 PostgreSQL 12–18 多版本回归（方案与实测已交付，12–15 / 17 待实例）** → 需求：NFR-ALL-GATE-COMP-001
  - [x] 实测：PostgreSQL 16.2（本地 pgserver，25 项链路全通过）、18.6（真机，对象树 / 查询 / 跨库 / 取消已验）
  - [x] 逐项复核版本敏感点并给出最低支持版本（`pg_backend_pid` 8.1+、`pg_cancel_backend` 8.1+、`has_database_privilege` 8.1+、`information_schema` 7.4+、dollar-quoting 8.0+、`RETURNING` 8.2+、SCRAM 10+）
  - [x] 新增一键回归脚本 `Scripts/test-postgres-version-matrix.sh`（连接 / DML 影响行数 / 服务端取消 / 对象树 / 跨库）→ 输出可直接粘贴进矩阵的行
  - [x] `Docs/兼容性矩阵.md` 记录已测 / 未测与复核结论
  - [ ] 12–15 / 17：待有实例（本机 / Docker / 测试环境）后执行脚本补测，逐行改为实测值
- [ ] **T-15 GBase 8a 驱动实现（驱动层待做，排期最后）** → 需求：FR-STD-DB-DRV-009、NFR-ALL-GATE-COMP-002
  - [x] 方言层就绪：`GBaseDialect`（`SHOW DATABASES`、反引号标识符、limit 语法）、`StatementSplitter` 支持客户端 `DELIMITER`，单测覆盖
  - [x] 验证计划与检查表：`Docs/GBase-技术验证.md`（连接参数、认证插件、`SHOW DATABASES` / `information_schema` 探查、类型映射、中文与 NULL、分号与存储过程、取消与超时）
  - [ ] 驱动层：新增 `GBaseService`（基于 MySQLNIO）+ 依赖与镜像配置 —— **阻塞条件：当前环境无 GBase 8a 实例，无法验证认证插件与行为差异**
  - [ ] 实测：待用户提供可达的 GBase 8a 地址 / 账号（只需只读账号）后执行验证清单
- [ ] **T-60 MySQL 驱动实现与版本窗口实测（净新增；待依赖选型与实例）** → 需求：FR-STD-DB-DRV-010、NFR-ALL-GATE-COMP-003、R-022
  - [ ] **依赖选型（前置）**：确认引入 `MySQLNIO` —— 版本锁定 + 许可登记进 `THIRD-PARTY-NOTICES.md`（参考 FR-STD-DB-DRV-008 对 PostgresNIO 的做法）；属需求提出者待定的「依赖选型」事项
  - [ ] `DatabaseType` 新增 `mysql` 档：默认端口 3306、显示名、默认 SSL 模式与 schema 联动（FR-STD-DB-CONN-001 / FR-STD-DB-CONN-002 的类型联动依赖它）
  - [ ] 方言层抽出 `MySQLDialect`，并让 `GBaseDialect` 在其上扩展 —— 两者共用 MySQL 协议系的反引号引用 / `SHOW DATABASES` / `DELIMITER`，避免两套并行维护
  - [ ] `MySQLService`（连接 / 流式执行 / 取消 / 元数据）+ `DatabaseServiceFactory` 接线，替换现有的 `NotImplementedDatabaseService(driverName: "MySQLNIO")` 占位
  - [ ] **版本窗口实测**：按 NFR-ALL-GATE-COMP-003 逐版本跑（连接与版本号 / 多语句与中文与 NULL / DML 影响行数 / 服务端取消 / 对象树 / 跨库），每版一行记入 `Docs/兼容性矩阵.md` §2；**无实例的版本登记为阻塞，不得默认通过**
  - [ ] 同步更新 `Docs/兼容性矩阵.md`（现标题与 §1 只覆盖 PostgreSQL / GBase 8a），以及 `Docs/GBase-技术验证.md` 中与 MySQL 共用的部分
  - **阻塞条件（2026-09-23 登记）**：需**覆盖窗口内多个大版本的 MySQL 实例**；依赖选型需需求提出者确认
- [ ] **T-61 记忆层 S2：归档派生索引（纯本地统计，不依赖模型端点）** → 需求：FR-AGT-KNOW-MEM-001
  - [ ] `Core/QueryMemory.swift`：从归档 `.sql` 派生的查询记忆 —— **两级指纹分开**：粗指纹（结构骨架，用于聚类与频次）与精指纹（原文，用于「同一条」计数），**不混用**（硬骨头 H1）
  - [ ] 索引落 Application Support（`query-memory-index.json`），且**纯派生**：删掉后能从归档文件完整重建 —— **事实源是归档文件、索引只是缓存**（设计见《产品能力规划说明书》§4.4）
  - [ ] 记忆的键**必须含连接**：按连接 / 环境隔离，每个登录用户各有各的记忆（同一句 SQL 在别的连接上不出现）
  - [ ] 单测：重建一致性（删索引 → 重建 → 条目与频次相同）、跨连接不串味、归档为空时不报错、记忆里**不含结果集行数据**
- [ ] **T-62 记忆层 S4 第一档：编辑器补全** → 需求：FR-AGT-KNOW-MEM-001
  - [ ] 补全候选接 `QueryMemory`，**只来自当前连接**；从没跑过任何 SQL 的连接上空候选且不报错
  - [ ] 实测（App 内探针）：跑过 N 条 SQL 后的候选数、换连接后候选清空、删索引后重建候选恢复
- [ ] **T-63 记忆层 S3：参数化与例行候选（只建议，不自动建任务）** → 需求：FR-AGT-KNOW-MEM-004
  - [ ] 参数槽位识别：把同一条 SQL 的不同取值归并成带槽位的模板；槽位**可人工订正**（把误判的常量标回字面量）
  - [ ] 四条统计判据（跨天频次 / 跨越天数 / 时刻集中度 / 是否只改参数）**全满足**才升格为「例行候选」；**信息不足时宁可不升格**（硬骨头 H3，取保守侧）
  - [ ] 前提缺口：`SQLArchiveEntry` 目前只留首次 / 最近执行时间与当天次数，**没有每次执行的时刻** —— 要判「是不是每天同一时间来」必须先用 `-- 执行时刻:` 补上（**已决定暂不加**，见 §4.4 已知缺口）；只有「跨天频次 / 跨越天数」两维时不构成升格
  - [ ] 单测：一次性排障脚本不得升格、跨天规律脚本可升格、人工否决**长期生效**
- [ ] **T-64 记忆层治理：可检视 / 可删除 / 可解释 + 环境层与通用层分层** → 需求：FR-AGT-KNOW-MEM-002
  - [ ] 记忆浏览（原文 / 频次 / 来源连接）、单条删除、一键清空、「本次执行不记录」
  - [ ] 删除 / 清空**立即生效**且可验证（重建索引后不再出现）；每条记忆都能回答「为什么记了它 / 为什么它被忘了」
  - [ ] 环境层（库表名 / 数据分布 / 这条在哪跑的，严格隔离）与通用层（方言写法 / 命名习惯 / 改写经验）分离；**通用层提升前过脱敏检查**，不得携带具体库表名与数据值
  - [ ] 生命周期**按类型分**，不按固定天数一刀切（「一年一次但关键」的巡检脚本不得被清）
- [ ] **T-65 活动栏 + 工作区 Explorer（FR-STD-WS-FS-002）** → 需求：FR-STD-WS-FS-002
  - [x] **活动栏**（已完成 2026-09-23）：最左侧 46pt 固定宽度，上排「数据库 / 工作区」+ 底部「设置 / 账户」；选中态 = 左侧 2pt 强调条 + 图标提亮（不铺背景）
  - [x] **工作区选择器**（已完成）：`NSOpenPanel` 选目录 → 安全作用域书签（复用 `SecureDirectoryAccess` / `DirectoryBookmarkStore`，单独存 `workspace-bookmark.json`，免得污染数据任务与查询归档的授权列表）
  - [x] **文件树**（已完成）：单层懒加载（展开才读子目录），忽略 `.build` / `node_modules` / `.git`；不跟随符号链接（避免环）
  - [x] **接入既有占位**（部分完成）：`TerminalWorkingDirectory.resolve(workspace:)` 已传入工作区（实测终端启动目录 = 工作区）；**SQL 归档默认目录仍待办**
  - [x] **授权状态常显**（已完成）：底部一行显示「已授权 / 书签失效 / 未授权」+ 补救动作（与 `DirectoryAccessStatus` 六态同源）
  - [x] 单测（已完成）：书签往返、失效回退、路径净化（不得逃出工作区）、忽略名单匹配 —— `Tests/ActivityBarTests.swift`（10 项：切换项与动作分离、id 稳定、序号、回退）+ `Tests/WorkspaceTreeTests.swift`（含**真实 Foundation 书签往返** 2 项与树逻辑 11 项）
  - [x] **收尾实测**（App 内启动探针，验证后已删除）：13 项全过 —— **展开两层**（`Core/Deep/agentDeep.swift` 以 depth 2 出现，正是上一轮漏过的那条路径）、第二层 URL 解析正确、搜索命中且相对路径相对根、空白查询退出搜索、归档来源 = 工作区且落在 `queries/`、单独指定优先于工作区、两者都没有时明确为 none
  - [ ] 智能体文件作用域以工作区为界（**等模型端点**：现在接上无法端到端验证）
  - [x] 实测（App 内启动探针，验证后已删除）：18 项全过 —— 选目录后授权有效、`workspace-bookmark.json` 落盘、**重新加载（模拟重启）后仍恢复工作区**、忽略名单与隐藏文件、展开一层出现 depth 1、目录 URL 落在工作区内、相对路径越界被拒、**终端启动目录 = 工作区**、清空后回到未授权
- **说明（2026-09-23 登记）**：T-61 ~ T-64 **不需要模型端点与可达实例**（纯本地 + 纯统计），与 T-60 / T-15 的阻塞条件无关，可随时开工；**当前仅登记，未开工**
- [x] **T-21 配套文档补齐（已完成）** → 需求：10.6 待补充材料
  - [x] `Docs/Doyah产品概要设计说明书.md`：架构分层、数据流、模块清单、ADR-01 ~ 15、并发与取消语义
  - [x] `Docs/测试用例.md`：TC-01 ~ TC-63（54 条功能 + 9 条非功能）、AC-ALL-GATE-REL-04 验收清单、缺陷回归模板
  - [x] `Docs/兼容性矩阵.md`：实测记录 + 版本敏感点复核 + 补测流程（T-14 交付物）
  - [x] `Docs/GBase-技术验证.md`：差异对照、实现方案、16 项验证清单（T-15 交付物）
  - [x] `Docs/发布方案.md`：签名 / 公证 / 装订流程 + 12 项发布前检查
  - [x] `Scripts/check-doc-tables.py`：文档表格列数校验（防止脚本改表导致错位），已纳入维护约定
- [x] **T-22 中文输入法光标缺陷修复（已完成）** → 缺陷：BUG-005（用户反馈）
  - [x] 根因定位：① 组字期间 `textDidChange` 就把未提交文本写进绑定；② SwiftUI 回写时用 `textView.string = text` 整段替换（重置输入上下文 / 撤销栈）；③ 提交回调栈里同步重设全量文本属性
  - [x] 修复：`Core/EditorTextSync.swift` 判定「是否外部改动」；组字期间绝不回写；外部改动改用 `textStorage.replaceCharacters` + `didChangeText`；高亮统一延后到下一个 runloop
  - [x] 单测：`Tests/EditorTextSyncTests.swift` 8 项（组字不回写 / 滞后旧值不回写 / 编辑器自身变化不回写 / 外部改动回写 / 回写后基准更新 / 连续输入 / 首次渲染 / 空页签载入）
  - [ ] 手工回归：拼音 / 五笔 / 日文输入法下「打几个字 → 回车 → 继续输入英文」光标不跳（并入 AC-ALL-GATE-REL-04，见 TC-64）
- [x] **T-23 连接显示名括注登录用户名（已完成）** → 需求：FR-STD-DB-CONN-011（用户新增）
  - [x] `ConnectionConfig.displayTitle(untitled:)`：`名称 (用户名)`，空名称走占位文案、空用户名不产生空括号
  - [x] 接入侧边栏连接行、查询上下文栏服务器选择器、删除确认框
  - [x] 单测 3 项（`Tests/ConnectionConfigTests.swift`）
  - [ ] 手工确认：列表中显示为 `DemoPG (postgres)`，重启后一致（并入 AC-ALL-GATE-REL-04，见 TC-65）
- [x] **T-24 对象树右键菜单（第一期：服务器节点）（开发完成）** → 需求：FR-STD-DB-META-010（用户新增）
  - [x] 菜单项：连接（已连接时禁用）/ 断开（未连接时禁用）/ 编辑连接…（复用连接表单 `.sheet`）/ 新建数据库…（**按权限呈现**）
  - [x] 权限探测：`SQLDialect.databaseCreationPrivilegeQuery()`；PG 用 `SELECT (rolsuper OR rolcreatedb) FROM pg_roles WHERE rolname = current_user`；GBase 暂返回 nil（待实例验证后实现 `SHOW GRANTS` 解析）
  - [x] 三态处理：`PrivilegeProbe.databaseCreationAllowed(from:)`，`true` 才呈现；`false`/`nil`（无权限 / 未知 / 探测失败）不呈现
  - [x] 建库：`CreateDatabaseSheet` 命名 + 本地预校验（首字符字母或下划线、可含数字/`_`/`$`、≤63 字节、Unicode 字母允许）→ `CREATE DATABASE <方言转义名>` → 刷新数据库下拉与对象树（`metadataRevision`）
  - [x] 单测 9 项（三态解析 / 名称校验 / 方言查询与转义）；链路用例 8（`--can-create-database` → 建库 → `--tree` 出现新库）
  - [x] 断开语义：释放该连接的全部服务实例（含跨库按需连接）并清空权限结论；对象树保留已加载内容，再次展开时按需重连
  - [ ] 手工回归：右键服务器节点验证四项菜单、无权限账号下不出现「新建数据库…」、建库后列表刷新（见 TC-67 ~ TC-69）
  - [ ] 后续需求（本期不做）：数据库 / schema / 表节点的右键菜单（新建 schema、新建表、删除、刷新等）

---

**本轮（v2.3，接替会话）新增需求的任务拆解**

> 说明：本轮为**夜间接管施工**，按用户要求**不执行任何编译与测试**（编译 / 打包会触发钥匙串访问）。因此下方「已完成」指**代码与单测已写完**，不等于已通过验证；验证统一收口到 T-41。

- [x] **T-25 结果集客户端排序 / 筛选 / 分页（Core 完成，UI 待接）** → 需求：FR-STD-DB-RES-011 ~ FR-STD-DB-RES-009
  - [x] `Core/ResultView.swift`：`ResultSortDescriptor` / `ResultFilter` / `ResultPage`；稳定排序（同值行不乱跳）、数字感知比较（`2 < 10`）、本地化自然序（`item2 < item10`）、NULL 语义（默认 NULLS LAST，只在「为空」下匹配筛选）
  - [x] 单测 22 项（`Tests/ResultViewTests.swift`：排序 7 / 筛选 8 / 分页 5 / 数值与比较 2）
  - [ ] `ResultGrid` / `ResultTableView` 接入：表头点击排序、筛选条、分页控件
  - [ ] 「当前条件是客户端过滤」提示 + 「用当前条件生成 WHERE 重新查询」入口（R-021）
- [x] **T-26 导出格式扩展（已完成）** → 需求：FR-STD-DB-RES-012
  - [x] `ResultExporter`：新增 `tsv` / `markdown` / `insertStatements`；INSERT 按列 `typeName` 决定是否加引号（数值 / 布尔不加，解析失败退回字符串）、`'` 翻倍转义、表名与列名走方言引用
  - [x] `text(for:format:tableName:dialect:)` 统一分派；`AppState.exportResult` 传入页签名与连接方言
  - [x] 导出菜单新增「TSV / Markdown 表格 / INSERT 语句」三项 + 3 条本地化文案（中英齐备）
  - [x] 单测 11 项（TSV 2 / Markdown 3 / INSERT 4 / 分派与格式元数据 2）
  - [ ] 导出 INSERT 前让用户确认表名（当前取页签标题；未绑定文件时用 `table_name` 占位）
- [x] **T-27 表结构与 SQL 生成（Core 完成）** → 需求：FR-STD-DB-DATA-003、FR-STD-DB-DDL-001、FR-STD-DB-DDL-002
  - [x] `Core/SQLGenerator.swift`：`selectRows` / `countRows` / `selectTemplate` / `insertTemplate` / `createTable` / `dropTable` / `truncateTable` / `explain`
  - [x] 单测 18 项（`Tests/SQLGeneratorTests.swift`）
  - [ ] 接入表节点右键菜单与「结构」页签（见 T-36）
- [ ] **T-28 表数据浏览入口（待做）** → 需求：FR-STD-DB-DATA-001、FR-STD-DB-DATA-002、FR-STD-DB-META-012
  - [ ] 双击表 / 视图节点 → 新建页签并自动执行 `selectRows`（默认 200 行）
  - [ ] 表节点右键菜单：浏览前 N 行 / 生成 SELECT / 生成 INSERT / 复制限定名
  - [ ] WHERE / ORDER BY 条件输入（服务端执行）+ 一键 `count(*)`
- [x] **T-29 执行计划解析（Core 完成，面板 UI 待接）** → 需求：FR-STD-DB-DIAG-001、FR-STD-DB-DIAG-002
  - [x] `Core/ExplainPlan.swift`：文本计划（缩进层级 / `cost=` / `actual time=` / `loops=` / 明细行挂载 / 箭头前缀剥离）与 `FORMAT JSON` 计划树两套解析，统一扁平节点模型
  - [x] 摘要：节点数、规划 / 执行耗时、全表扫描处数、最贵节点、最慢节点
  - [x] `SQLGenerator.explain`：`ANALYZE` / `BUFFERS` / `FORMAT JSON` 组合，GBase 自动降级为普通 `EXPLAIN`
  - [x] 单测 14 项（`Tests/ExplainPlanTests.swift`）
  - [ ] 计划面板：缩进树、最慢 / 最贵节点高亮、查看原文、导出
  - [ ] `ANALYZE` 会真正执行语句，必须二次确认
  - [ ] 慢查询排行（`pg_stat_statements`，缺扩展 / 权限时明确提示）
- [x] **T-30 会话监控与终止（Core 完成，UI 待接）** → 需求：FR-STD-DB-SESS-002、FR-STD-DB-SESS-003
  - [x] 方言层：`serverActivityQuery()`（PG `pg_stat_activity`，时间列转 text、`left(query, 500)`；GBase `SHOW PROCESSLIST`）、`cancelSessionStatement` / `terminateSessionStatement`（PG `pg_cancel_backend` / `pg_terminate_backend`；GBase `KILL QUERY` / `KILL`），并为其它方言提供返回 nil 的默认实现
  - [x] `Core/SessionMonitor.swift`：列名兼容 `pid/Id`、`usename/User`、`datname/db`、`query/Info` 两套命名；时间戳多形态解析与「已运行时长」；排序为等待 → 活跃 → 空闲；无 pid 行丢弃
  - [x] 单测 11 项（`Tests/SessionMonitorTests.swift`）
  - [ ] 监控窗口：列表 + 刷新 + 「取消语句 / 终止会话」（二次确认）
  - [ ] 按权限隐藏不可用动作（R-020）
- [x] **T-31 结果集内联编辑（FR-STD-DB-DATA-004）**：**2026-09-29 人工点验通过 ✅**（值编辑器 FR-STD-DB-DATA-005 仍待做）
  - [ ] 前置：单表 + 主键 / 唯一键检测，不具备时禁用编辑并说明原因
  - [ ] 变更暂存 → 预览 DML → 单事务提交；并发用原值做乐观锁（R-019）
  - [ ] 行详情侧栏 / JSON 值格式化
- [ ] **T-32 高危语句保护 Safe Mode（待做）** → 需求：FR-STD-DB-EXEC-017
  - [ ] 静态判定：无 `WHERE` 的 `UPDATE` / `DELETE`、`DROP`、`TRUNCATE`
  - [ ] 二次确认（可跳过）+ 只读 / 生产标签连接强制确认
- [ ] **T-33 运行范围控制（待做）** → 需求：FR-STD-DB-EXEC-006
  - [ ] 「执行当前语句 / 执行选中」入口（⌘↩ 与 ⌘⇧↩）
  - [ ] 用 `StatementSplitter` 边界反查光标所在语句
- [ ] **T-34 事务模式 UI（待做）** → 需求：FR-STD-DB-EXEC-007（复用 FR-STD-DB-EXEC-015 的事务 API）
  - [ ] 自动提交开关 + 提交 / 回滚按钮 + 事务状态指示
  - [ ] 切连接 / 切库时提示未提交事务，明确事务归属
- [ ] **T-35 全库对象搜索（待做）** → 需求：FR-STD-DB-META-015
  - [ ] 一次元数据查询（表 / 视图 / 列 / 函数）+ 客户端过滤 + 命中跳转
- [ ] **T-36 对象 DDL 查看与表节点菜单（待做）** → 需求：FR-STD-DB-META-011、FR-STD-DB-META-012、FR-STD-DB-DDL-003
  - [ ] 「查看 DDL」：PG `pg_get_viewdef` / `pg_get_functiondef` / 列与约束拼装；GBase `SHOW CREATE TABLE`（待实例验证）
  - [ ] 表节点右键菜单：清空 / 删除 / 复制 DDL（删除类需二次确认）
  - [ ] 表结构编辑器（进阶，依赖更完整的元数据）
- [ ] **T-37 连接组织与只读（待做）** → 需求：FR-STD-DB-CONN-012 ~ FR-STD-DB-CONN-014、FR-STD-DB-CONN-005、FR-STD-DB-CONN-006
  - [ ] `ConnectionConfig` 新增**可选**字段（分组 / 颜色 / 环境标签 / 只读 / 启动 SQL / 心跳间隔），保证旧 `connections.json` 仍可解码
  - [ ] 只读连接在执行前拦截写语句；启动 SQL 在连接建立后执行
  - [ ] 连接 URL 解析 / 生成（密码不落配置文件）
- [ ] **T-38 沙箱架构选型：SSH 隧道与备份恢复（前置决策，待做）** → 需求：FR-STD-DB-CONN-020、FR-STD-DB-IO-003、R-018
  - [ ] 在「应用内自实现（COPY 流 + 纯 Swift 隧道）/ 引导用户在自己终端执行 / 非沙箱分发」之间定稿，写入 `Docs/发布方案.md` 并形成 ADR
  - [ ] 选型定稿前**不实现** FR-STD-DB-IO-003 与 FR-STD-DB-CONN-020，避免返工
- [ ] **T-39 流式导入导出（待做）** → 需求：FR-STD-DB-IO-002、FR-STD-DB-IO-006、FR-STD-DB-RES-013
  - [ ] `COPY … TO STDOUT` / `COPY … FROM STDIN` 流式管线（文件落在客户端）
  - [ ] 导入列映射与类型推断 + 「将写入 N 行」预览
- [ ] **T-40 效率与外观（待做）** → 需求：FR-STD-WS-UI-005 ~ FR-STD-WS-EDIT-016、FR-STD-DB-RES-006
  - [ ] 命令面板（⌘K）与命令注册表
  - [ ] 主题 / 字体；「复制为多种格式」
- [ ] **T-41 本轮交付的验证（未执行，需用户在场）** → 需求：FR-STD-ALL-BLD-003、FR-STD-ALL-BLD-004
  - [ ] `./Scripts/verify-core.sh`：预期由 89 项增至 **165 项**（新增 76 项）
  - [ ] `./Scripts/test-local-query-path.sh`：回归 28 项，确认 `ResultExporter` 改动未影响链路
  - [ ] `python3 Scripts/check-doc-tables.py`：文档表格列数校验（本轮改了 7 处表格）
  - [ ] `./Scripts/build-app.sh` + 启动冒烟：导出菜单三项、`SQLDialect` 默认实现、`AppState.exportResult` 新参数
  - [ ] **本轮未执行以上任何一条**（编译 / 打包会触发钥匙串访问，用户已在夜间明确禁止）

---
---
---

### 10.2 夜间自主开发任务清单（2026-09-21 23:30 → 2026-09-22 06:00）

> 授权：需求提出者授权夜间**自主连续开发**，期间不做任何需要人工确认的动作；**凡需确认的事项只登记、不执行**（见文末「留待确认」）。
> 规则：每个任务完成即 ① 跑 `Scripts/verify-core.sh` 全绿 → ② 补 / 改单测 → ③ 更新对应需求状态列 → ④ 单独 git 提交。

| 任务 | 内容 | 对应需求 | 验收要点 |
|---|---|---|---|
| **T-42** ✅ 完成 2026-09-21 23:4x | 库属性管理 Core：`ALTER DATABASE`（owner / 库级参数 / 连接限制）与 `DROP DATABASE` 的 SQL 生成 + 库名校验 | FR-STD-DB-SESS-006 | 单测 ≥4 项；非法库名被拒绝；**实测：`verify-core.sh` 178/178 全绿（+13 项单测）** |
| **T-43** ✅ 完成 2026-09-22 | 权限管理 Core：对象权限查询 SQL、`GRANT` / `REVOKE` 生成（库 / schema / 表 / 序列） | FR-STD-DB-SESS-005 | 单测 ≥5 项；语句含正确限定名；**实测：191/191 全绿（+13 项单测）** |
| **T-44** ✅ 完成 2026-09-22 | 锁与阻塞链 Core：方言查询 `pg_locks` + `pg_blocking_pids()`、结果模型与解析 | FR-STD-DB-DIAG-005 | 单测 ≥4 项（含无锁空结果、等待链解析）；**实测：200/200 全绿（+9 项单测）** |
| **T-45** ✅ 完成 2026-09-22 | 备份扩写：`pg_dumpall` 命令行生成（集群级） | FR-STD-DB-IO-003（扩写） | 单测 ≥3 项；参数安全；**实测：211/211 全绿（+11 项单测）** |
| **T-46** ✅ 完成 2026-09-22 | 结构与 DDL 扩写：索引 / 外键的 `CREATE` / `DROP` 生成 | FR-STD-DB-DDL-003（扩写） | 单测 ≥5 项；**实测：223/223 全绿（+12 项单测）** |
| **T-47** ✅ 完成 2026-09-22 | 大结果流式落盘：导出改流式写文件，不驻留全量内存 | FR-STD-DB-RES-013 | 单测 ≥3 项（分块 / 中断清理）；**实测：263/263 全绿（+18 项单测）** |
| **T-48** ✅ 完成 2026-09-22 | 智能体接入配置 Core：端点 / 模型名 / 超时 / 配额模型 + Key 入 Keychain + 总开关 | FR-AGT-LINK-CHAN-001、NFR-ALL-GATE-AI-002 | 单测 ≥6 项；关闭开关不外发；**实测：287/287 全绿（+24 项单测）** |
| **T-49** ✅ 完成 2026-09-22 | 智能体安全护栏 Core：高危语句识别与拦截、外部内容标记为不可信 | FR-AGT-GUARD-PERM-004、AC-ALL-GATE-AI-02/04 | 单测 ≥6 项（无 `WHERE` 的 UPDATE/DELETE、DROP、TRUNCATE、注入样本）；**实测：317/317 全绿（+30 项单测）** |
| **T-50** ✅ 完成 2026-09-22 | 自然语言→SQL 通道：`LLMClient` 协议抽象 + 请求构造 + 响应解析（**结果不自动执行**） | FR-AGT-CORE-LOOP-001、NFR-ALL-GATE-AI-001 | 单测 ≥5 项（假后端；请求体不含结果集）；**实测：341/341 全绿（+24 项单测）** |
| **T-51** ✅ 完成 2026-09-22 | 审批与审计 Core：动作记录模型 + 审批状态机 + 审计导出（不含密钥） | FR-AGT-GUARD-PERM-001、NFR-ALL-GATE-AI-003 | 单测 ≥5 项；**实测：358/358 全绿（+17 项单测）** |
| **T-54** ✅ 完成 2026-09-22 | specs → 数据任务模型 + 调度骨架（一次性 / 周期、执行历史） | FR-AGT-PLAN-PLAN-002、FR-AGT-TOOL-SCHED-001 | 单测 ≥6 项；错过窗口有提示；**实测：383/383 全绿（+25 项单测）** |
| **T-55** ✅ 完成 2026-09-22 | 目录导出：安全作用域书签封装（未授权给可读错误） | FR-AGT-CORE-LOOP-003 | 单测 ≥3 项 + 构建通过；**实测：378/378 全绿（+17 项单测）** |
| **T-56** ✅ 完成 2026-09-22 | 数据生成 / 合成数据 Core：按 specs 生成行（同 seed 可复现） | FR-AGT-CORE-LOOP-002 | 单测 ≥4 项；**实测：399/399 全绿（+21 项单测）** |
| **T-52** ✅ 完成 2026-09-22 | UI 接线：服务器节点菜单「库属性…」「删除数据库…」+ 权限 / 锁面板 | FR-STD-DB-SESS-005/05、FR-STD-DB-DIAG-005 | 构建通过 + 手工回归清单登记；**实测：429/429 全绿（+15 项单测）、`build-app.sh` 退出码 0；清单见下** |
| **T-53** ✅ 完成 2026-09-22 | 对象树按类型 / schema 分组视图 | FR-STD-DB-META-008 | 构建通过 + 分组映射单测；**实测：414/414 全绿（+15 项单测）、`build-app.sh` 退出码 0** |
| **T-57** ✅ 完成 2026-09-22 | 智能体审批与审计界面接线：审计面板（筛选 / 清空二次确认 / 导出 JSON·CSV）+ 只读模式与白名单配置 + 逐次审批单接到智能体路径 | FR-AGT-GUARD-PERM-001、NFR-ALL-GATE-AI-003、AC-ALL-GATE-AI-02/03 | 构建通过 + 闸门 / 过滤 / 导出脱敏纯逻辑单测（40 项）；**实测：519/519 全绿（+40 项单测）、`build-app.sh` 退出码 0；手工回归清单见下** |
| **T-58** ✅ 完成 2026-09-22 | 数据任务界面接线：任务编辑器（specs + 源 / 转换 / 目标 / 调度 / 导出）+ 保存前试运行预览 + specs→定义模型通道 + App 侧调度 tick（错过窗口不补跑）+ 产物导出到安全作用域目录（NSOpenPanel + 书签） | FR-AGT-PLAN-PLAN-002、FR-AGT-TOOL-SCHED-001、FR-AGT-CORE-LOOP-003 | 构建通过 + 编译/校验/导出/状态映射纯逻辑单测（44 项）；**实测：519 → 563 tests，0 failures、`build-app.sh` 退出码 0；手工回归清单见下** |

**执行顺序**：T-42 → T-43 → T-44 → T-45 → T-46 → T-47 → T-48 → T-49 → T-50 → T-51 → T-54 → T-55 → T-56 → T-52 → T-53 → T-57 → T-58
（Core 与可单测者优先；UI 类置后，时间不足则留待白天）

**留待确认（夜间不执行，仅登记）**
1. 智能体真实端到端联调：需要你提供模型端点与 API Key
2. 多窗口（FR-STD-WS-UI-001 扩写）、Excel 导出 / 导入（FR-STD-DB-RES-014 / FR-STD-DB-IO-007）：涉及依赖选型（库体积与许可）
3. 发布链路：Developer ID 签名、公证、分发形态
4. 真机 / 真实数据库回归：需要可达的 PostgreSQL 实例（T-52 的四个面板见下方清单；T-57 的审批 / 审计面板见文末清单）

**T-52 手工回归清单（需可达的 PostgreSQL 实例，尚未执行）**

前置：连接一个 PostgreSQL 12+ 实例，且当前账号可建库（或改用超级用户）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 对象树服务器节点右键 →「库属性…」 | 弹窗显示目标库名与实时预览语句；未填任何项时提示「尚未填写任何改动」且执行按钮不可用 |
| 2 | 填「连接数上限 → 5」并执行 | 预览出现 `ALTER DATABASE ... WITH CONNECTION LIMIT 5;`；执行后状态栏提示成功，数据库列表与对象树刷新 |
| 3 | 连接数上限填 `abc` | 明确提示输入不合法、执行按钮禁用（**不得**静默当作「不修改」） |
| 4 | 右键 →「删除数据库…」，不输库名 | 「删除」按钮不可用 |
| 5 | 输入**不匹配**的库名 | 按钮仍不可用 |
| 6 | 输入**完全匹配**的库名后删除 | 弹出语句为 `DROP DATABASE IF EXISTS ...;`；成功后库从列表消失 |
| 7 | 另开会话连上目标库，再执行删除 | 报错被翻成「该库仍有其他会话连接……请先断开这些连接再试」（而不是服务端英文原文） |
| 8 | 尝试删除当前连接的库 | 提示「不能删除当前连接的数据库」 |
| 9 | 右键 →「权限…」，角色填当前用户并查询 | 列出已授权限，按对象分组；`is_grantable` 的行单独标注 |
| 10 | 面板内组装 `SELECT ON table public.<某表> → 某角色` | 预览区域出现对应 `GRANT ... TO ...;`；点击「授予」后重新查询能看到该权限 |
| 11 | 权限关键字填 `ALL, SELECT` | 预览报非法、两个按钮都禁用（`ALL` 不得与其他混用） |
| 12 | 右键 →「锁与阻塞…」（无并发时） | 显示「当前没有检测到锁等待」 |
| 13 | 会话 A：`BEGIN; UPDATE t SET ...;`（不提交）；会话 B：`UPDATE` 同一行 | 面板出现一行：被阻塞 pid = B、阻塞者 pid = A，含锁模式与已等待秒数；点「定位阻塞者」高亮 A 行 |
| 14 | 用无 `pg_monitor` 的普通账号查看 | 面板仍能列出 pid 与锁，其他会话语句文本为空，并常驻显示权限说明 |
| 15 | GBase 8a 连接上尝试「权限…」/「锁与阻塞…」 | 给出「当前方言不支持……」的可读提示，而不是静默空白 |

**FR-STD-WS-EDIT-005 快捷键人工确认清单（需在有图形界面的机器上逐条按一遍，尚未执行）**

> 说明：快捷键的**编译期**正确性由构建保证（`AppShortcut` 是唯一来源），
> 但「按下是否真的触发」依赖菜单/响应链，必须在真实窗口里按一遍才算数。

| # | 按键 | 期望 |
|---|---|---|
| 1 | ⌘↩ | 执行当前页签（按当前运行范围）；执行中按钮转灰、停止转红 |
| 2 | ⌘. | 停止正在执行的查询 |
| 3 | ⇧⌘E | 触发语法检查（EXPLAIN） |
| 4 | ⌘O / ⌘S / ⇧⌘S | 打开文件 / 保存到文件 / 另存为 |
| 5 | ⌘D / ⇧⌘D | 保存当前查询到「已保存」/ 打开已保存列表 |
| 6 | ⇧⌘H | 打开查询历史 |
| 7 | ⌘F / ⌥⌘F / ⌘L | 查找 / 替换 / 跳到行列 |
| 8 | ⌘] / ⌘[ | 缩进 / 反缩进选中文本 |
| 9 | ⇧⌘K / ⇧⌘F | 清除查询 / 格式化 |
| 10 | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 | 运行范围切到 整篇 / 光标所在语句 / 选中片段；菜单里勾选随之移动 |
| 11 | ⌥⌘S / ⌥⌘W | 高危语句保护开关 / 「每次写入都确认」开关 |
| 12 | ⇧⌘/ | 打开快捷键帮助面板，且面板内容与实际按键一致 |
| 13 | 全部按键试完 | **不发生冲突**：没有两个动作抢同一个组合，也没有覆盖系统级快捷键（⌘Q/⌘W/⌘H/⌘M/⌘,） |
| 14 | ⌘K | **不应有任何反应**（该组合预留给尚未实现的命令面板 FR-STD-WS-UI-005） |
| 15 | ⇧⌘P | 打开执行计划面板；面板里「ANALYZE」开关**默认关闭**，打开后出现醒目警告 |
| 16 | ⇧⌘A | 打开「审批与审计」面板；该组合未与其它动作冲突，且出现在快捷键帮助面板里 |

**FR-STD-DB-DATA-001 / FR-STD-DB-META-012 手工验收清单（需真实 PostgreSQL 实例与图形界面，尚未执行）**

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 对象树里**双击**一张表节点 | 新建页签并填入 `SELECT * FROM "schema"."表" LIMIT 200 OFFSET 0;`，**不自动执行** |
| 2 | **双击**表节点的展开箭头区域 | 仍是展开 / 收起（单击语义不被双击吞掉） |
| 3 | **双击**一个视图节点 | 同样生成浏览语句 |
| 4 | 双击一个**库 / schema** 节点 | 无动作（不生成语句、不报错） |
| 5 | 右键**表**节点 | 菜单含：浏览前 200 行 / 生成 SELECT 模板 / 生成 INSERT 模板 / 复制限定名 / 查看建表 DDL / 生成清空语句 / 生成删除语句 |
| 6 | 右键**视图**节点 | 菜单含：浏览前 200 行 / 生成 SELECT 模板 / 复制限定名；**不含** INSERT 模板与 DDL（视图暂不支持） |
| 7 | 右键**列**节点 | 菜单只有「复制列名」 |
| 8 | 右键**服务器 / 库 / schema** 节点 | 仍是原菜单（连接 / 断开 / 编辑连接 / 库属性…），不出现表节点菜单 |
| 9 | 生成 SELECT 模板 | 语句按列名列全，且列名带方言引号 |
| 10 | 生成 INSERT 模板 | 语句含括号列清单与 `?` 占位符；**不执行** |
| 11 | 复制限定名 → 粘贴 | 得到 `"schema"."表"`（带引号，可直接粘进 SQL） |
| 12 | 查看建表 DDL | 生成的 `CREATE TABLE` 中，**原表为 NOT NULL 的列带 `NOT NULL`**、可空列不带 |
| 13 | 生成清空 / 删除语句 | 只把 `TRUNCATE TABLE …;` / `DROP TABLE IF EXISTS …;` 写进新页签；**不执行**，无任何确认弹窗（因为没执行） |
| 14 | 在编辑器里手动执行第 13 步的删除语句 | 被 Safe Mode 拦下并弹出风险确认（与 FR-STD-DB-EXEC-017 清单第 4、5 项一致） |
| 15 | 断开连接后右键表节点 | 给出可读提示，不崩溃 |


**清单 C2：对象树下钻与跨库（FR-STD-DB-META-001 / FR-STD-DB-META-006 / FR-STD-DB-META-007，需真实 PostgreSQL 实例与图形界面，尚未执行）**

补这份清单的原因：上面清单 C 是**双击语义**清单，15 步里没有一步覆盖"逐层展开 / 空 schema 文案 / 加载失败 / 跨库失败隔离"，
而 FR-STD-DB-META-001 / 09 / 10 三条的阻塞条件都写着"见清单 C" —— **那个指向是落空的**（2026-09-23 取证发现）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 连上实例，展开服务器节点 | 列出当前用户可连接的数据库（按 CONNECT 权限过滤） |
| 2 | 依次展开 库 → schema → 表 → 列（共 4 层点击） | 每层都能继续展开；**列右侧显示类型名**；叶子节点无展开箭头 |
| 3 | 造一个空 schema 后展开它 | 显示「该 schema 下暂无表 / 视图」，不报错、不卡住 |
| 4 | 展开一个**连不上**的库（`ALTER DATABASE x ALLOW_CONNECTIONS false`） | 只有该节点显示失败占位与可读原因，**其它库仍可正常展开**；收起再展开该节点会重查 |
| 5 | 点全局刷新（或根级重试） | 缓存清空并重查根节点；已展开层级回到初始态 |
| 6 | 断开连接后再连 | 对象树重置，不残留上一次的库 / 表 |

**已知的界面缺口（取证时读码发现，点界面时请一并确认）**：① 单节点失败**没有就地重试**，只能收起再展开；
② 跨库连接失败的文案当前是 `PSQLError(...)` 兜底串（见 **R-038**），与"可读错误"不符。

**FR-STD-DB-DIAG-001 真实库验收清单（需 PostgreSQL 实例与图形界面，尚未执行）**

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 对 `SELECT * FROM 一张大表` 点工具栏「执行计划」 | 弹出面板，计划树出现；全表扫描节点**橙色高亮**并标注 |
| 2 | 观察摘要行 | 含节点数、规划 / 执行耗时、全表扫描处数、最慢节点 |
| 3 | 打开「使用 JSON 格式」再分析 | 计划树结构与文本格式一致（两种解析结果应一致） |
| 4 | 打开「执行 ANALYZE」 | 出现醒目警告；面板顶部提示它**会真正执行语句** |
| 5 | 用 `EXPLAIN ANALYZE` + 一条 **UPDATE** 验一次 | 数据**确实被修改** —— 以此确认警告不是吓唬人（请在测试库上做） |
| 6 | 编辑器里放两条语句后分析 | 只分析第一条，并提示「只分析了第一条」 |
| 7 | 对 `CREATE TABLE x(...)` 分析 | 给出「该语句不支持执行计划」的可读提示，不静默空白 |
| 8 | 断开连接后分析 | 给出可读提示，不崩溃 |

**T-57 智能体审批与审计手工回归清单（需图形界面 + 可达 PostgreSQL 实例，尚未执行）**

> 说明：闸门 / 过滤 / 导出脱敏等纯逻辑已由 40 项单测覆盖；
> 下面这些是**必须有人点一遍**才能确认的部分（弹窗呈现、菜单响应、真实执行与库权限）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 菜单「智能体 → 审批与审计…」（或 ⇧⌘A） | 面板打开；标题、五个列头（时间 / 连接 / 语句 / 模型 / 结果状态）与「只读模式」「白名单」都能看到 |
| 2 | 面板里只读模式**保持开启**，到「用自然语言生成 SQL…」生成一条 `DROP TABLE …` 并点「提交审批…」 | 面板**不弹**审批单，提交处显示「安全护栏已拒绝：当前为只读模式……」；审计表里出现一条「被护栏拒绝」记录，选中后能看到风险点原文 |
| 3 | 面板里关掉只读模式并「保存策略」 | 出现橙色的「只读模式已关闭」警告；「智能体设置…」面板保存配置后重开本面板，开关仍是关闭状态（**配置确实落盘**） |
| 4 | 再生成一条 `DROP TABLE …` 并「提交审批…」 | 弹出审批单：显示完整语句、连接 / 库 / 模型、「DROP 会删除对象」风险点；此时**数据库里什么都没发生** |
| 5 | 审批单上点「拒绝」 | 审批单关闭；审计表里该动作出现「已拒绝」；库里仍无变化 |
| 6 | 再提交一次，点「批准并执行」 | 语句真的在目标库执行；审计表出现「已执行」；若执行报错则记「执行失败」并把错误写进附注 |
| 7 | 提交后**直接关掉审批单**（不点批准 / 拒绝） | 面板的「待审批」区里仍然列出该动作（关窗 ≠ 批准），点「查看…」能重新打开审批单 |
| 8 | 待审批存在时退出 App 再启动，打开本面板 | 「待审批」区仍列出该动作（按审计日志恢复），可继续批准 / 拒绝 |
| 9 | 生成一条 `SELECT …` 并「提交审批…」 | 不需要审批：语句进新页签，**不自动执行**；审计表记一条「已批准」（`decidedBy = auto`） |
| 10 | 白名单勾上「数据变更」并保存，只读模式关闭，提交一条干净的 `INSERT` | 不再弹审批单（白名单免除审批）；勾回「结构变更」后 `CREATE TABLE` 仍会弹审批单 |
| 11 | 白名单里找不到「无法识别的语句」可勾 | 白名单选项只有五类，无法归类的语句永远要审批 |
| 12 | 点「导出 JSON…」/「导出 CSV…」并选路径 | 文件写出成功；CSV 用 Excel 打开中文不乱码；两份文件里都**没有** API Key / 口令片段（可用 `grep -i 'sk-\|bearer\|password'` 自查） |
| 13 | 点「清空审计…」 | 先弹二次确认；取消则什么都不发生；确认后记录清空，并提示「已清空审计记录」 |
| 14 | 生成 SQL 时把只读模式开回，重复第 2 步 | 仍是可读拒绝原因，且**不建审批单**（审计里不应出现「待批准」） |
| 15 | 未连接数据库时提交一条写语句 | 给出可读错误（不是静默失败、不是崩溃） |


**T-58 数据任务手工回归清单（需图形界面 + 可达 PostgreSQL 实例 + 可用模型端点，尚未执行）**

> 说明：SQL 编译、投影与写入语句、文件名净化、调度判定到界面状态的映射、specs→定义的 JSON 解析等纯逻辑
> 已由 44 项单测覆盖；下面这些**必须有人点一遍**才能确认（弹窗、菜单响应、真实写库、沙箱下的书签持久化）。

| # | 步骤 | 期望结果 |
|---|---|---|
| 1 | 菜单「智能体 → 数据任务…」（或 ⇧⌘T） | 面板打开；左列表、编辑器、试运行、调度状态、执行历史五块都在；快捷键帮助面板里能看到同一条 ⇧⌘T |
| 2 | 点「新建任务」，只填 specs 不填表名 | 「问题」区逐条列出「数据来源表不能为空。」「目标表不能为空。」；**保存按钮禁用** |
| 3 | 填源表 / 目标表 / 源列后再点「试运行」 | 出现分步说明、只取 10 行的 `SELECT`、以及写入语句与护栏判定；**没有对数据库发起任何写操作** |
| 4 | 改一个字段（例如目标表名）再直接点「保存」 | 保存按钮已被禁用，并提示「保存前必须先试运行一次」（改了就要重新试运行） |
| 5 | 写入模式选「覆盖」并试运行 | 预览里出现 `TRUNCATE TABLE ...;`，并有橙色「覆盖模式会先清空目标表」告警 |
| 6 | 写入模式选「更新插入」但不填冲突键 | 问题区提示必须指定冲突键列，保存禁用 |
| 7 | 只读模式（默认）下点「现在执行…」 | **不弹审批单**，显示「安全护栏拒绝了这次执行：当前为只读模式……」，执行历史多一条「失败」记录 |
| 8 | 到「审批与审计…」关掉只读模式并保存策略，再点「现在执行…」 | 弹出既有审批单（含完整 `INSERT ... SELECT` 语句与「这是写操作」风险点）；**此时库里什么都没发生** |
| 9 | 审批单点「批准并执行」 | 目标表数据真的变化；执行历史出现「成功」+ 写入行数 + 耗时；若配了导出目录，产物文件出现在该目录 |
| 10 | 「导出目录」点「选择目录…」并选一个空目录 | 目录状态显示为绿色「导出目录：<路径>」；点「写入验证文件」后该目录出现一份 `*-preview-*.txt` |
| 11 | 退出 App 再启动，打开面板看同一个任务 | 导出目录仍是那个路径（**沙箱下验证 `bookmarks.app-scope` 生效**）；书签过期时显示橙色提示与补救建议 |
| 12 | 把已授权目录改名 / 删除后再点「写入验证文件」 | 显示「授权目录已不存在：<路径>」+「请重新选择」，**不静默失败、不崩溃** |
| 13 | 建一个周期任务（间隔 60 秒，首次执行时间设为 1 分钟前），保持面板打开 | 状态在「等待 → 到点/错过」之间切换；`nextRun` 正确；**同一个计划时刻不会被重复执行**（历史里不会每 30 秒多一条） |
| 14 | 把首次执行时间设为 10 分钟前 | 显示橙色「晚了约 N 分钟，请确认是否现在执行。」，**且不会自动开跑**；点「现在执行…」才走第 8~9 步的审批流程 |
| 15 | 点「停用」，等过一个计划时刻 | 状态变「已停用」，不再排期；手动「现在执行…」仍可用；点「恢复」后重新排期 |
| 16 | 断开数据库连接后点「现在执行…」 | 给出可读提示「请先连接一个数据库再执行任务。」，不崩溃 |
| 17 | 「由规格说明生成…」填一段自然语言（需模型端点与 API Key） | 先看到将要外发的提示词全文；生成后定义回填编辑器、**未保存也未执行**；定义有问题时问题区列出，保存仍禁用 |


## 11 能力点覆盖台账（2026-10-19 · 重排与登记后）

> 这张表回答一个问题：**能力书里的每个能力点，在需求书里有没有对应条目**（以及反过来）。
> 2026-10-20 从《需求规格说明书》§9.12 整段迁来 —— 它是**核对表**，不是需求，所以归计划书。

> **这份台账回答一个问题**：能力书里的每个能力点，在本文件里有没有**可验收条目**。
> **口径**：条目存在且验收要点可机械判 = 覆盖；只有描述无条目 = 缺；域在别的仓 = 移交。
> 本节随 `FR-*` 条目变动而更新，**不重复能力书的边界**。

### 11.1 按产品分区的覆盖

| 分区（本文件） | 能力书对应 | 能力点 | 本文件条目 | 判断 |
|---|---|---|---|---|
| 3.2 Doyah Agent | 第三章 | 50 | `FR-AGT-LINK-CHAN-001` ~ `FR-AGT-QUAL-VERIFY-004`（67 条） | **覆盖 50 / 50**（2026-10-20 补齐 15 条；补 LOOP-009 单次任务预算 1 条） |
| 3.3 Doyah Studio · 工作区 | 4.1 | 38 | `FR-STD-WS-UI-001`~`07` · `09` · `12`~`72`（69 条） | **38 / 38**（看差异、授权与版本已各自立条，不再指路） |
| 3.4 Doyah Studio · 数据库 | 4.2 | 34 | `FR-CONN`20 · `FR-EXEC`17 · `FR-RES`14 · `FR-META`15 · `FR-DATA`6 · `FR-DDL`5 · `FR-DIAG`5 · `FR-SESS`5 · `FR-DRV`9 · `FR-EDIT`4（共 106 条） | **34 / 34**（对话式诊断 / 任务定义 / 审批 / 执行回执已在节内立条；4.2.35 命令行出口归 §3.1.4） |
| 3.5 Doyah Notes | 第五章 | 15 | `FR-NTS-NOTE-CAPTURE-001` ~ `FR-NTS-NOTE-PRIVACY-001`（11 条）· `FR-NTS-TODO-LIST-001` ~ `FR-NTS-TODO-LINK-001`（8 条） | **覆盖 15 / 15**（笔记 11 点 + 待办 4 点；待办 2026-10-20 归位） |
| 3.6 Doyah Retro | 第六章 | 18 | `FR-RTR-MKT-FEED-001` ~ `FR-RTR-REV-AI-001`（82 条） | **18 / 18 每点都有条目**（2026-10-20 归位；回测与验证拆为回测引擎 / 验证与样本；归位表暂定） |
| 3.1.1 工程与工具链 | —— | —— | `FR-STD-ALL-BLD-001` ~ `009`（9 条） | 构建与工程纪律 |
| 3.1.2 授权与版本 | —— | —— | `FR-STD-ALL-LIC`01 ~ `05`（5 条） | Studio 授权：一套覆盖三块能力位（移动端不在管辖） |
| 3.1.3 插件装配 | —— | —— | `FR-STD-ALL-PLUG`01 ~ `08`（**8 条**） | Studio 宿主侧装配与边界（不借 Agent 插件 3.6.4） |
| 3.1.4 命令行出口 | —— | —— | `FR-STD-ALL-CLI-001` ~ `005`（5 条） | 无 UI 也能验证与执行 |
| 第七章 非目标 | 第七章 | 10 条 | —— | **不需条目**：非目标是「明确不做」 |

### 11.2 本批新登记的条目

| 能力点 | 条目 | 内容 |
|---|---|---|
| 3.2.2 主动澄清 · 3.2.3 计划修订 | `FR-AGT-PLAN-CLAR-001` · `FR-AGT-PLAN-PLAN-004` | 先问再动 · 改计划要说为什么 |
| 3.3.2 灵魂 | `FR-AGT-GUARD-SOUL-001` | L0 / L1 / L2 分层，L0 优先；含密钥形态拒绝载入 |
| 3.5.2 ~ 3.5.6 检索与多模态 | `FR-AGT-TOOL-INGEST-001` ~ `39` | 网络检索 / 文档解析 / 图像理解 / 语音输入 / 语音输出 |
| 3.5.7 界面操作 | `FR-AGT-TOOL-SYS-001` | 驱动本机界面，每步可见可中断，危险点击走审批 |
| 3.5.8 子任务委派 | `FR-AGT-TOOL-SYS-002` | 独立上下文、汇总标来源 |
| 3.5.9 模型多档 | `FR-AGT-TOOL-MODEL-001` | 档位能力标注，降档缩水要说出来 |
| 3.7.4 中途干预 | `FR-AGT-UX-CONV-007` | 插话最多再跑一步就转向 |
| 3.7.5 主动通知 · 3.7.6 求助通道 | `FR-AGT-UX-CONV-008` · `FR-AGT-UX-CONV-009` | 长任务完成 / 出错 / 需人决定时的告知 · 求助要写明要什么 |
| 3.3.4 隔离执行 · 3.1.2 及时刹停 | `FR-AGT-GUARD-PERM-003` · `FR-AGT-CORE-LOOP-007` | 受限环境 · 伤害性动作**前置**停 |
| 3.7.8 多端一致性 | `FR-AGT-UX-SYNC-001` | 壳不同、内容同 |
| 3.9 可运营 | `FR-AGT-OPS-OBS-001` ~ `49` | 可观测 / 可配置 / 可评测 |
| 4.1.15 Git 状态 · 4.1.16 看差异 | `FR-STD-WS-VCS-001` | 只读，界面无写操作入口 |
| 4.1.29 调试器 | `FR-STD-WS-TOOL-003` | DAP 接入，不自研协议 |
| 4.1.31 许愿式编程 | `FR-STD-WS-AI-002` | 整仓范围多轮读写，交付前给差异 |
| 4.1.14 撤回 | `FR-STD-WS-EDIT-015` | 按批次撤回，不动人手改的行 |
| 4.1.32 外部改动监听 · 4.1.33 工作区切换 | `FR-STD-WS-FS-009` · `FR-STD-WS-FS-010` | 外部改动即刻提示 · 单活动工作区 |
| 5.2.1 ~ 5.2.4 待办 | `FR-NTS-TODO-LIST-001` ~ `FR-NTS-TODO-LINK-001`（8 条） | 清单 / 日历 / 完成与改期 / 与笔记互转；承接 `FR-NOTE-27`、`FR-NOTE-36~39` |
| 5.1.1 ~ 5.1.11 | `FR-NTS-NOTE-CAPTURE-001` ~ `11` | 与能力书第五章逐点对应（捕获 / 编辑 / 附件 / 检索 / 整理 / 版本 / 删除 / 同步 / 冲突合并 / 导出 / 私密） |
| 6.1.3 数据健康 · 6.2.2 ~ 6.2.4 · 6.2.6 | `FR-RTR-RSR-FEATURE-001` ~ `04` · `FR-RTR-MKT-HEALTH-003` | 特征模型 / 选股筛选 / 回测验证 / 历史情形（**不预测未来**）/ 数据健康 |
| 6.3.1 工作流编排 · 6.3.2 内置 skill · 6.4.4 AI 复盘 | `FR-RTR-FLOW-ORCH-001` ~ `04` | 可复用流水线 / 行业口径固化 / 挂在原始记录上的复盘稿 |

### 11.3 仍待处理的三类

| 类别 | 内容 | 处置 |
|---|---|---|
| **能力点 ↔ 条目不是一一对应** | 51 条覆盖 49 点：`FR-AGT-LINK-CHAN-001~31` 里含非线性能力的条目（如「回边三件」「门控」各覆盖多点），`FR-AGT-PLAN-CLAR-001~51` 才是一点一条 | 台账按「域覆盖」判，不强行 1:1 —— 1:1 会逼出空条目 |
| **Notes 两侧同文** | 本节 11 条与 Notes 仓能力书第五章必须**内容相同**，只允许顺序不同 | 每次改一边，必须在同一提交里改另一边；由 `Scripts/check-notes-capability-sync.py` 守（同时覆盖 Retro ↔ Retro 仓） |
| **Retro 的编号沿用旧号** | `FR-R-*` 是 Retro 仓原编号（跨仓收归），在 §3.6 内按能力分组而非按 R-xx 顺序 | 编号不动；分组只影响阅读顺序 |

### 11.4 反查：有条目、能力书无对应能力

| 条目域 | 是什么 | 为什么不进能力书 |
|---|---|---|
| `FR-STD-ALL-BLD-001` ~ `09` | 构建与工具链 | 工程纪律，用户在功能里看不到 |
| `FR-STD-ALL-CLI-001` ~ `05` | 命令行验收口径 | 能力书只写「终端壳」这个能力，参数与退出码属需求 |
| `FR-STD-DB-DRV-005` ~ `09` | 驱动与方言契约 | 契约面属概要设计 |
| `FR-MAINT` / `FR-PERF` / `FR-COMP` / `NFR-*` | 维护性 / 性能 / 兼容性 | 质量属性，能力书按能力叙述不按质量叙述 |

**这不是漏洞**：三类都需要一个登记处，本文件就是那个登记处。

## 12 已验证环境与联调记录（2026-09-20）

> 从《需求规格说明书》§10.4 整段迁来：这是**执行记录**（在哪台机器、哪个版本上跑通什么），不是需求。


**开发机**

| 项 | 值 |
|---|---|
| 机型 | Apple M5 Pro（arm64） |
| 系统 | macOS 27.0 |
| Xcode | 27.0（27A266a） |
| Swift | Xcode 27 自带工具链（语言模式 5.10） |
| XcodeGen | 2.46.0（`~/tools/xcodegen-dist/xcodegen/bin/xcodegen`） |
| 依赖 | PostgresNIO 1.33.1 + 12 个传递依赖（`Package.resolved` 锁定） |

**真实服务器（PostgreSQL）**

| 项 | 值 |
|---|---|
| 版本 | PostgreSQL 18.6（x86_64-windows） |
| 地址 | `192.0.2.10:5432`（客户端 `192.0.2.20`） |
| 库 / 用户 | `postgres` / `postgres` |
| SSL | `disable` |
| 关键前置 | `pg_hba.conf` 必须放行客户端 IP（曾因写成 `192.0.2.2/32` 报 `28000`） |
| 验证结果 | CLI 与 App「测试连接」均成功，能执行查询并返回结果 |

**本地回归（无需外部数据库）**

| 项 | 值 |
|---|---|
| 内置数据库 | pgserver 0.1.4（PostgreSQL 16.2，aarch64-apple-darwin） |
| 端口 / 数据目录 | `55432` / `~/tools/pgdata-querytest` |
| 回归结果 | `test-local-query-path.sh` 28/28（新增用例 6「DML 影响行数」、用例 7「服务端取消」、用例 8「建库权限与建库」）；`verify-core.sh` 89/89（新增 `ResultExporterTests` 10 项、`PostgresServiceTests` 影响行数判定 3 项、`EditorTextSyncTests` 8 项、`ConnectionConfigTests` 显示名 3 项、`PrivilegeProbeTests` 9 项） |
| 版本矩阵回归 | `test-postgres-version-matrix.sh` 16/16（对任意 PG 实例跑连接 / 中文与 NULL / DML 影响行数 / 服务端取消 / 对象树 / 跨库，并输出矩阵行） |
| App 打包 | `build-app.sh` 产出 `dist/DoyahStudio.app`，ad-hoc 签名（含 sandbox + network.client），可启动；启动后 `settings.selectedConnectionID` 正常写入（T-13 实测） |
| 真机验证（18.6） | 连接 / 查询 / 对象树 / 跨库 / DML 影响行数 / 服务端取消均通过；`Docs/兼容性矩阵.md` 记录 |

**受限命令行环境注意事项**

- `xcode-select` 指向 CommandLineTools 时，构建需显式 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- SwiftPM 需 `--disable-sandbox`；SwiftUI 宏需要 `-Xfrontend -disable-sandbox`。
- 依赖解析走 `Scripts/setup-package-mirrors.sh`（gitclone.com 镜像 + 本地 Vendor 包）。
- Xcode 命令行在只读缓存环境可能因 manifest 缓存不可写而失败；此环境下改用 SwiftPM 目标 / `build-app.sh` 验证。

## 13 驱动适配要点：GBase 8a

> 从《需求规格说明书》§10.3 整段迁来：这是**适配结论与待实测项**（第三列就是状态）。方言契约本身见《Doyah 产品概要设计说明书》§3.19。


| 项 | 结论 / 待确认 | 当前状态 |
|---|---|---|
| 线协议 | MySQL 协议族（不是 PostgreSQL 协议） | 驱动候选 MySQLNIO，未接入 |
| 默认端口 | 5258 | ✅ `DatabaseType.gbase8a.defaultPort` |
| 标识符引用 | 反引号 `` ` `` | ✅ `GBaseDialect.quoteIdentifier` |
| 分页语法 | `LIMIT offset, count` | ✅ `GBaseDialect.limitClause` |
| 元数据 | `SHOW DATABASES` / `SHOW TABLES [FROM db]` / `DESC <table>` | ✅ 方言 SQL 已实现，驱动未实现 |
| 数据库/版本查询 | `SELECT DATABASE()` / `SELECT VERSION()` | ✅ 方言已实现 |
| 版本号格式 | 形如 `8.6.2.11` | ✅ `parseServerVersion` |
| 语句分隔 | 客户端 `DELIMITER` 指令；存储过程体内含分号 | ✅ `StatementSplitter` + 单元测试 |
| `END$` / `END $` | 不得改写原文（`DELIMITER $` 后用 `END$` 结束） | ✅ 单元测试覆盖 |
| 事务 | 能力较弱，需实测 `BEGIN/COMMIT/ROLLBACK` | ⬜ 待实测 |
| 认证插件 | `mysql_native_password` 与 `caching_sha2_password` 支持情况未知 | ⬜ 待实测（R-004） |
| 方言特性位 | `featureSet` 不声明 schemas / transactions | ✅ 与设计一致 |
| 技术验证序列 | `SELECT VERSION(); SHOW DATABASES; SHOW TABLES; DESC <table>; SELECT * FROM information_schema.tables LIMIT 1; DELIMITER $ ... END $ ... CALL ...` | ⬜ 待执行 |

## 变更记录

| 版本 | 日期 | 变更摘要 | 作者 |
|---|---|---|---|
| **v0.28** | 2026-10-20 | **台账 +4（契约回流）**：`FR-STD-WS-UI-010`（页签条高度不由内容决定）· `FR-STD-WS-UI-011`（编辑面底色字色只用主题令牌）· `FR-AGT-TOOL-MODEL-002`（档位端点与模型名可预填且可改）· `NFR-ALL-GATE-USE-005`（走不动的动作必须挑三种处置之一）—— 四条均来自概要设计 §3.30 / §3.31 / §3.32 / §3.26 的契约回流，状态起于 ⬜ 未开始；`§5 矩阵` 与 `§11 覆盖台账` 计数同批跟版。 | `hugehippo` |
| **v0.27** | 2026-10-20 | **台账与覆盖台账跟需求书对齐** —— ①§3 台账 21 行的层次/优先级与需求书不一致（`FR-AGT-GUARD-SOUL-001` 账『常用增强』书『基线必备』、8 行 NOTE 优先级为空等）→ **以需求书为准**改齐；②§11 覆盖台账 5 处：Notes 11 点/11 条 → **15 点/19 条**、数据库 33 → **34**（4.2.35 命令行出口归 §3.1.4）、共性两行旧式缩写 `FR-BLD`/`FR-CLI` → 五段式全号、11.2 补待办四点。 | `hugehippo` |
| **v0.26** | 2026-10-20 | **台账 +1**：`FR-AGT-CORE-LOOP-009`（单次任务预算 150 步 / 256K，能力书 3.1.1）；版本列记 `未排期`；§2 分区 Agent 50 / 67；§5 矩阵重生成为 **376 条**。 | `hugehippo` |
| **v0.25** | 2026-10-20 | **描述跟版** —— §3.1.2 / §3.1.3 名称与能力书对齐；「跨产品共通授权 / 跨产品装配」的说法纠正为 **Studio 专属**（一套许可证覆盖三块能力位、宿主侧装配不借 Agent 插件）；台账领域列同批。 | `hugehippo` |
| **v0.24** | 2026-10-20 | **编号跟版** —— §3.1 的 41 条由 `FR-ALL-ALL-*` 改回 `FR-STD-ALL-*`（Studio 专属，非全产品共性）；台账、§5 矩阵同批；版本口径未动。 | `hugehippo` |
| **v0.23** | 2026-10-20 | **补录待办需求** —— §3 台账增 8 行（`FR-NTS-TODO-*`），`版本` 记 `未排期`、口径写明「版本规划待概要设计完成后统一排」；§5 矩阵随生成器重写为 375 条。 | `hugehippo` |
| **v0.22** | 2026-10-20 | **台账编号跟版** —— 共性需求由 `FR-STD-ALL-*` 改 `FR-ALL-ALL-*`，§3 台账与 §10 矩阵同批改；版本口径与归属未动（版本规划待概要设计完成后另做）。 | `hugehippo` |
| **v0.21** | 2026-10-20 | **台账编号跟版** —— §3 台账 425 行与 §10 矩阵的需求编号随五段式换代全量改；版本口径、alpha / v1.1+ 归属未变。 | `hugehippo` |
| **v0.20** | 2026-10-20 | **能力点编号跟版** —— 能力书 4.1.9 自动归档判为数据库侧能力（移到 4.2.34），4.1.10~4.1.38 整体降一号；§10 五行引用（Git 状态 / 看差异 / 调试器 / 许愿式编程 / 撤回 / 外部改动监听 / 工作区切换）同批改为新号并补全名称。 | `hugehippo` |
| **v0.19** | 2026-10-20 | **§3 台账升为「版本范围台账」** —— 增 `版本`（`v0.1.0-alpha` / `v1.0` / `v1.1+` / `未排期` 四档）与 `版本口径`（为什么不在本版）两列，425 行逐条落定：alpha 350 条、v1.1+ 75 条。依据 = 人类主人令 2026-10-20「这个问题完全可以通过版本计划来解决，制定不同版本应该具备的能力和需求就 OK」。旧做法（需求行内写 `[alpha 不含]` 括注 + 独立账 `Scripts/alpha-fr-dispositions.json`）退役并入本表；接替判据 `Scripts/check-version-scope.py`（8 例自测）。 | `hugehippo` |
| **v0.18** | 2026-10-20 | **§3 台账「优先级」列修复（290 / 425 行）** —— 2026-10-20 状态列迁出时，把旧状态串（`⬜ ⚠️` 200 行 / `⬜` 90 行）写进了「优先级」格，导致这 290 行的优先级丢失。按《Doyah产品需求规格说明书》的「层次 / 优先级」两列逐条回填（先 216 行、再补 Retro 74 行），**425 行现在全部合法**（高 / 中 / 低 / — / 低（排期最后））；`层次` / `状态` / `状态原值` 三列一字未动。由头：把状态一致性判据改读本台账时，解析器按列位读状态，才发现这一列是脏的。 | `hugehippo` |
| **v0.17** | 2026-10-20 | **Linux 归属改挂 `hugehippo`（人类主人：「linux归大河马」）** —— ① `Docs/平台实现状态.json` 的 `platforms.linux.owner` 由 `babyhippo` 改为 `hugehippo`（补 2026-10-15 拍板依据「Linux 与 macOS 底层血缘更近」）；② §5 平台矩阵随之重生成（Linux 列维护者一行跟版）；③ 判据 `Scripts/check-exclusive-sections.py` 的演员名表同批跟版（`hugehippo` = macos/ios/watchos/**linux**、`babyhippo` = android），自测 45/45 通过。 | `hugehippo` |
| **v0.16** | 2026-10-20 | **§5 平台等价矩阵重跑**（两书交叉核对的连带项）—— 矩阵停留在 342 条的旧读数，已在盘上过期 **25 条**（实测 367 条）；按生成器重写整节，判据 `gen-platform-parity.py --check` 转绿。同批把生成文案里的死链「取自 §10.1 索引」改为「取自《需求规格说明书-需求索引》」（索引已外置），`Docs/平台实现状态.json` 的 `_comment` 同口径。 | `hugehippo` |
| **v0.15** | 2026-10-20 | 台账 419 → **425**（+6 补齐条目，全部 ⬜）；§11.1 覆盖数跟到拆点后的点数（3.1 4/4 · 3.3 38/38 · 3.4 33/33）。 | `hugehippo` |
| **v0.14** | 2026-10-20 | Retro 能力点 17 → **18**：`6.2.4 回测与验证` 拆成 `6.2.4 回测引擎`（过程正确）与 `6.2.5 验证与样本`（结论成立），`6.2.5 研报生成`→`6.2.6`、`6.2.6 历史情形`→`6.2.7`；§11.1 与 §11.2 引用跟版。 | `hugehippo` |
| **v0.13** | 2026-10-20 | §11.1 的 3.6 行改为「17 / 17」（Retro 82 条按语义归位后，17 个能力点全部有条目，此前 5 个空点已消除）。 | `hugehippo` |
| **v0.12** | 2026-10-20 | 两书对账跟版：台账 `FR-NOTE-*` 补零 11 处；§11.1 覆盖口径改为「能力点是否都有落脚」（36/36 · 28/28 · 49/49 · 11/11 · 12 有点 + 5 无条目）。 | `hugehippo` |
| **v0.11** | 2026-10-20 | 台账 400 → **419**（+`FR-AGT-CORE-SESS-001~66`、`FR-STD-WS-FS-004~72`，全部 ⬜ 未开工）；§11.1 覆盖数改为「能力书有点」口径（49/49 · 34/36 · 24/28 · 11/11 · 12/17）。 | `hugehippo` |
| **v0.10** | 2026-10-20 | §11.1 覆盖数改成实测（Agent 34/49 · 工作区 28/34 · 数据库 23/27 · Notes 11/11 · Retro 12/17），并把「未覆盖的点」指到需求书各节末；3.3 条目范围随 SQL 工作台迁移更新。 | `hugehippo` |
| **v0.9** | 2026-10-20 | ① §5 平台等价矩阵按新索引文件重生成（342 条；引用随需求书附录前移改为 `§9.2`）；② 文内 `需求书 §9.3` → `§9.2`。台账与状态未改。 | `hugehippo` |
| **v0.8** | 2026-10-20 | 需求书章号重排后的引用跟版（`§10.9` → `§9.3`、`§0.4` → `§1.4` 等），台账与状态一字未改。 | `hugehippo` |
| **v0.7** | 2026-10-20 | 新增 **§12 已验证环境与联调记录**（原需求规格说明书 §10.4）、**§13 驱动适配要点：GBase 8a**（原 §10.3，含待实测项；方言契约见《概要设计》§3.19）。两者都是**执行记录**，不是需求。 | `hugehippo` |
| **v0.6** | 2026-10-20 | ① 新增 **§11 能力点覆盖台账**（原《需求规格说明书》§10.12，61 行整段迁来，子节改 11.1~11.4）：它是「能力点 ↔ 需求条目」的核对表，不是需求；② 域标签跟 SRS 新节号（`3.1.1 工程与工具链` / `3.1.2 授权与许可` / `3.1.3 插件装配`）；③ 已知卡点里「需求规格说明书 §3.7」→ `§3.1.3`。 | `hugehippo` |
| **v0.5** | 2026-10-20 | ① 新增 **§10 历史任务清单**（开发任务列表 2026-09-20 / 夜间任务清单 09-21 夜，448 行从需求规格说明书 §10.7 / §10.7.1 原文搬来）；② 台账 395 → **400**：补 `FR-STD-ALL-LIC-001~05`（授权与许可，状态 🟡：代码与 23 项单测在，未人工验收）。 | `hugehippo` |
| **v0.4** | 2026-10-20 | `FR-STD-WS-WEB-003` 条文改判（编辑器内预览为主、浏览器页签为辅），台账摘要跟版；状态仍 ⬜。 | `hugehippo` |
| **v0.3** | 2026-10-20 | 台账 393 → **395**：新增 `FR-STD-WS-WEB-003`（本机网页文件在浏览器页签打开）、`FR-STD-WS-WEB-004`（站点兼容：常规浏览器身份），两条均 ⬜ 未开工，无排期。 | `hugehippo` |
| **v0.2** | 2026-10-20 | **扩容为四块台账**：新增 §4 里程碑与迭代（原 SRS §8）、§5 平台实现状态（原 SRS §10.10，机械生成）、§6 当前能力快照（原 SRS §2.4）、§7 待补材料（原 SRS §10.6）；进展记录与已知卡点顺延为 §8 / §9。**内容为原文搬运**，只改节号。 | `hugehippo` |
| **v0.1** | 2026-10-20 | 首版：四件文档分工、状态口径、需求状态台账、进展记录、已知卡点。 | `hugehippo` |
