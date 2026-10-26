# Doyah产品详细设计说明书 · Linux

> **版本** v1.0.4（2026-10-26 编号改为「冻结段 + 流水」三段式：`v1.0.NNN`，NNN 上限 999，满了冻结为 v1.1）；承接历史流水 v1.0.3；本版按 `detail-design-spec-writing` 体裁全量重写 —— §0.1 矩阵由 15 行区间行拆到逐条款 78 行、§3 由 13 节散文改为 21 节逐函数七段契约、§5.3 拆 9 个组件六态小节并新增 §5.8 界面用例表、新增 §4.4 状态覆盖清单、§11 增 `DETAIL_GAP` / `DETAIL_CONFLICT` 登记、§12 版本簿记归位、原 §12 已知坑移 §13。上游 = `Docs/Doyah产品概要设计说明书.md` v1.0.15。

> v1.0.3（2026-10-21 订正：Linux 是 PC 全量端（Studio + Notes + Retro + Agent + 授权），Retro 同属桌面端、与 Studio 同）

> v1.0.0（2026-10-14 骨架落地：开工方案 + 构建入口 + 应用工程骨架 + 前端同源装配，派单 `T-20261014-016`）

## 0. 文档元信息与追溯关系

- 项目/功能名称：Doyah · Linux 端全部能力（全量 PC 端：Studio 工作区与数据库 / Notes / Retro 宿主 / Agent 在 Studio 内的表现 / 授权呈现）
- 文档版本：v1.0.4（正文任何改动必须同步本节与 §12；三段式流水，第三段 +1）
- 实现范围：`Platform/linux/`（本仓盘上 25 件：构建入口、`src-tauri/` 应用工程骨架、`src-tauri/Core/` 领域层、`src-tauri/Cli/` 无界面入口、`src-tauri/Platform/Linux/` 平台适配层、`Tools/check-linux-skeleton.py` 本端判据）+ 同源面 `Platform/windows/App/`（前端与命令层，本端只引用不改）
- 上游依据：
  - 概要设计说明书：`Docs/Doyah产品概要设计说明书.md` v1.0.15（§1.3 边界、§1.4 平台矩阵、§3–§12 契约、§15 笔记域、§16 复盘域、§18–§19 域契约、第四章平台差异表）
  - 需求规格书：`Docs/Doyah产品需求规格说明书.md` v1.0.431（§1.8.1 平台口径、§3.5 Notes 段、§4 非功能 47 条、§9.2 平台差异登记表）
  - 能力规划书：`Docs/Doyah产品能力规划说明书.md` v1.0.252（§1 平台与产品线定位、P6 重量级运行时口径）
  - 设计规范（视觉）：`Docs/design/terminal-palette.json` + `Docs/规范/界面设计节-写作规范.md`（视觉参数唯一出处，本文件只写落点）
- 本文件性质：**概要设计的实现级展开。** 概要设计说「不许做什么」，本文件说「具体怎么做、做完怎么证明」。本文件允许出现平台名、类型名、文件路径与库版本。
- 优先级：需求规格书 > 概要设计 > 本详细设计 > 现有代码。
- 冲突处理：本文件与概要设计冲突时，以概要设计的「禁止」条款为准，Agent 输出 `DESIGN_CONFLICT`，不得自行裁决。
- 禁止行为：
  - 不得在本文件未定义的函数/组件中新增公开行为。
  - 不得修改 §1.3 禁止文件，不得引入 §1.1 基线外依赖（含语言包、系统命令、脚本工具）。
  - 不得修改测试断言、跳过测试或放宽校验来适配实现。
  - 不得把 Linux 自用实现的选型写回跨端契约（平台口径只有概要设计 §1.4 与第四章两处出处）。

### 0.1 概设—详设追溯矩阵

> 每一行 = 概要设计一条契约 → 本文件一个落点节 → 一个实现单元 → 至少一个真实存在的测试 ID。概设条款一律拆到单条，「同上」「见概设」「§4.1–§4.4」这类区间行在本表一律不出现。测试 ID 的定义面只有三处：§4.4、§5.8、§9.2。

| 概设章节 | 概设条款摘要 | 详设落点 | 实现单元 | 测试用例 ID |
|---|---|---|---|---|
| 概要设计 第四章（平台差异表） | WebView 运行时依赖：装得上、缺运行时给可读提示与补救指引，不静默失败 | 3.5、3.1 | `probe_webview`、`startup_report` | `T-3.5-01`、`T-3.1-02` |
| 概要设计 第四章（平台差异表） | 起壳前置：承载面缺失必须非零退出，不白屏、不静默失败 | 3.2、6.4 | `run` | `T-3.2-01`、`T-6.4-01` |
| 概要设计 第四章（平台差异表） | 窗口与信息架构、空·载入·失败三态随宿主一致 | 5.2、1.1 | `tauri.conf.json` 窗口段 | `UI-5.2-01` |
| 概要设计 第四章（平台差异表） | 凭据存储：不落配置、重启可恢复、可明确清除；无密钥环不回落明文 | 3.6、3.21、8.1 | `probe_secret_service`、`SecretStore` | `T-3.6-01`、`T-3.21-01`、`T-8.1-01` |
| 概要设计 第四章（平台差异表） | 沙箱与权限模型：最小权限、被拒时给可读原因 | 8.2、1.1 | `capabilities/default.json` | `T-8.2-01` |
| 概要设计 第四章（平台差异表） | 配置与数据目录：XDG 逻辑分区一致、损坏时保留原文件 | 3.18、4.2 | `paths::app_home` | `T-3.18-01`、`T-3.18-02`、`T-4.2-01` |
| 概要设计 第四章（平台差异表） | 打包与分发：deb / AppImage、图标同一品牌图形、身份四项随包走 | 3.20 | `Platform/linux/build.sh` | `T-3.20-04`、`T-3.14-01` |
| 概要设计 第四章（平台差异表） | 构建可复现：非 Linux 宿主如实拒绝、同源前端缺失即拒 | 3.20 | `build.sh` 退出码 2 / 4 | `T-3.20-02`、`T-3.20-03`、`T-4.4-06` |
| 概要设计 第四章（平台差异表） | 内嵌终端：真交互式 shell，禁只读日志冒充终端 | 3.7、5.1 | `probe_pty` | `T-3.7-01` |
| 概要设计 第四章（平台差异表） | 通知与深色跟随：不打扰用户、可关闭 | 3.8、5.4 | `probe_notifications`、主题值表 | `T-3.8-01` |
| 概要设计 第四章（平台差异表） | 剪贴板与拖放：复制语义一致 | 3.9 | `probe_clipboard` | `T-3.9-01` |
| 概要设计 第四章（平台差异表） | 托盘等可选面缺失不阻塞启动 | 3.10、3.11 | `probe_tray`、`missing` | `T-3.10-01`、`T-3.11-01`、`T-4.4-05` |
| 概要设计 第四章（平台差异表） | 内嵌浏览器：默认不加载远程内容、出网进统一外发日志 | 5.1、11 | 未建（§11 第 2 条登记） | 人工点验 |
| 概要设计 第四章（平台差异表） | 笔记存储引擎：独立数据家、附件不进 BLOB、trigram 检索 | 4.5 | 笔记数据家（`Platform/windows/App/src/plugins/notes/` 宿主装配） | `T-4.5-02`、`T-4.5-04` |
| 概要设计 §1.3 | 边界判据：平台中立层禁引界面框架；界面层不持连接/事务/文件句柄 | 1.1、2.3 | `Availability`、`Tools/check-linux-skeleton.py` | `T-2.3-01` |
| 概要设计 §1.4 | Linux = 全量 PC 端（Studio/Notes/Retro/Agent/授权），禁写成其它端的子集 | 1.4、2.1 | 本端能力面清单 | `T-2.1-01` |
| 概要设计 §1.5 | 分册只裁剪不增删；平台与产品线口径直引 §1.4，不自行推导 | 1.4 | 本文件 §1.4 声明 | `T-2.1-01` |
| 概要设计 §2 | 总则 2：新增依赖先入允许清单；总则 4：不得新增状态或流转 | 1.1、4.4 | 工作区依赖清单、状态覆盖表 | `T-4.4-07` |
| 概要设计 §2 | 总则 6：每个页签/视图实现六态，缺一即缺陷 | 5.3 | 九组件六态表 | `UI-5.3-01` |
| 概要设计 §2 | 总则 7：信息不足或冲突即停手输出 `BLOCKED`；总则 8：完成后逐条自检出证据 | 11、10.2 | 偏离处理表、自检表 | 自检输出 |
| 概要设计 §3 | 20 个组件的必须做/禁止做；同源命令层唯一，本端不另长一份 | 2.1、3.19、4.7 | `doyah_studio_shell::attach`、`doyah-studio-shell` | `T-2.1-02`、`T-3.19-01`、`T-4.7-01` |
| 概要设计 §3 | Agent 四类组件（命令执行/代码执行/工具目录/并行编排）在本端的落点 | 4.7 | 同源 `Platform/windows/Db/src/agent*.rs` | `T-4.7-02` |
| 概要设计 §3 | 授权判定：能力位离线可校验、入口可见性只一处、到期降级不锁数据 | 5.1、6.1 | 同源能力层 + 视图清单 | `UI-5.1-02` |
| 概要设计 §4.1 | 连接建立四类行为；凭据不入请求体；不自动重试认证失败 | 3.21、4.7 | `SecretStore::get` | `T-3.21-02` |
| 概要设计 §4.2 | 删除连带清凭据；重复删报「已不存在」；执行中禁删 | 3.21、4.7 | `SecretStore::delete` | `T-3.21-01` |
| 概要设计 §4.3 | 选区判定、按文本顺序逐条执行、多结果集全保留 | 4.7 | 同源执行面（`Db` 领域层） | `T-4.7-03` |
| 概要设计 §4.4 | 服务端真取消、连接仍可用、重复取消返回同一结局 | 4.7 | 同源执行面 | `T-4.7-04` |
| 概要设计 §4.5 | 层级按数据库类型给出；刷新不清选择；禁伪造占位节点 | 5.3.5 | `Platform/windows/App/src/shell/SideBar.vue` | `UI-5.3.5-01` |
| 概要设计 §4.6 | 前 N 行在服务端过滤；无主键不给行编辑；影响 0 行报冲突 | 5.3.3 | `Platform/windows/App/src/views/DatabaseView.vue` | `UI-5.3.3-01` |
| 概要设计 §4.7 | 未预览不得执行；删表带「存在才删」；禁把 DDL 当普通查询 | 5.3.3、4.3 | `DatabaseView.vue` 的 DDL 分支 | `UI-5.3.3-02`、`T-4.3-01` |
| 概要设计 §4.8 | 流式写文件；目标已存在必询问；部分失败列明细 | 5.3.7 | `BackupDialog.vue`、`RestoreDialog.vue` | `UI-5.3.7-01` |
| 概要设计 §4.9 | 终止会话需二次确认并说明后果；权限不足上浮原话 | 4.7、5.1 | 会话视图（同源） | `T-4.7-05` |
| 概要设计 §4.10 | 行数据须确认并留痕；禁投递凭据与连接串原文 | 5.3.6 | `Platform/windows/App/src/shell/ChatPanel.vue` | `UI-5.3.6-02` |
| 概要设计 §5.1 | 连接配置字段与允许读写方；不含口令本体 | 4.1、4.2、5.3.4 | 配置分区 + 凭据引用 | `T-4.1-01`、`T-4.1-02`、`UI-5.3.4-01` |
| 概要设计 §5.2 | 执行记录按天一份、同 SQL 只计次数、归档失败不回滚业务 | 4.2 | 同源 `archive` 落盘 | `T-4.2-02` |
| 概要设计 §5.3 | 任务定义字段（目标库/读写模式/影响行数上限/是否需审批） | 4.2 | 任务配置件 | `T-4.2-03` |
| 概要设计 §5.4 | 审批单与回执；预估取不到写「未接」，禁编造 | 5.3.6、4.4 | `ChatPanel.vue` 审批卡 | `UI-5.3.6-01` |
| 概要设计 §6.1 | 连接状态机闭集；禁「失败 → 已连接」跳转 | 4.4 | 连接态 | `T-4.4-01` |
| 概要设计 §6.2 | 语句执行状态机闭集；禁「已取消 → 已完成」 | 4.4 | 执行事件 | `T-4.4-02` |
| 概要设计 §6.3 | 审批单闭集；禁「已拒绝/已过期 → 已批准」 | 4.4 | 审批判决 | `T-4.4-03` |
| 概要设计 §6.4 | 查询页签闭集；执行中不可关闭；恢复不重放语句 | 4.4 | 页签模型 | `T-4.4-04` |
| 概要设计 §7.1 | 查询全链的调用顺序与失败处理表 | 4.3 | 伪代码 §4.3 第 1 段 | `T-4.3-01` |
| 概要设计 §7.2 | 结构变更：生成 → 预览 → 二次确认 → 执行 | 5.3.3、5.6 | `DatabaseView.vue` DDL 分支 | `UI-5.6-02` |
| 概要设计 §7.3 | 外部改动提示二选一；保存失败不清脏标记 | 4.7 | 同源 `fs.rs` | `T-4.7-06` |
| 概要设计 §8.1 | 界面范围与边界；禁新增未登记入口、禁新界面库 | 5.1 | 视图清单 | `UI-5.1-01` |
| 概要设计 §8.2 | 八类页面/视图职责与禁止呈现项 | 5.1、5.3.1 | 视图清单表、启动前置面 | `UI-5.3.1-01` |
| 概要设计 §8.3 | 导航允许四条与禁止跳转 | 5.7 | 活动栏路由 | `UI-5.7-02` |
| 概要设计 §8.4 | 界面六态必须呈现与禁止行为 | 5.3 | 九组件六态表 | `UI-5.3-01` |
| 概要设计 §8.5 | 校验通过前禁提交；不可逆操作二次确认；禁 toast 承载决策 | 5.6 | 事件绑定表 | `UI-5.6-01` |
| 概要设计 §8.6 | 表单字段校验规则与错误定位位置 | 5.7 | 表单校验表 | `UI-5.7-01` |
| 概要设计 §8.7 | 八个界面动作 → 接口映射与禁止行为 | 5.6 | 动作映射表 | `UI-5.6-02` |
| 概要设计 §8.8 | 字段级/页面级/服务器错误呈现规则 | 6.1 | 错误映射与呈现路径 | `T-6.1-01` |
| 概要设计 §8.9 | 键盘路径成套、读屏语义、快捷键只在一处定义 | 5.7 | 命令目录（同源） | `UI-5.7-03` |
| 概要设计 §8.10 | 界面契约验收八条判据 | 5.8 | 界面用例表 | `UI-5.8-01` |
| 概要设计 §8.11 | 行首栏字形/一个字号/状态行字段序/九个开关/主题按角色 | 5.4 | `ChatPanel.vue`、主题值表 | `UI-5.4-01` |
| 概要设计 §9 | 21 个错误码 + 四级兜底禁令 + 日志必记禁记 | 6.2、6.3 | 错误映射、日志字段 | `T-6.2-01`、`T-6.3-01` |
| 概要设计 §10 | 12 条被拒绝的替代方案 | 1.1 | — | 静态检查 |
| 概要设计 §11 | 非功能：性能/安全/并发/依赖清单/部署运行约束 | 7.1、7.2、8.3 | 并发表、外发日志 | `T-7.1-01`、`T-7.2-01`、`T-8.3-01` |
| 概要设计 §11.4 | 47 条非功能需求的设计归属 | 2.2、7.1 | 注入点表 | `T-2.2-01` |
| 概要设计 §11.4 | 方言与版本探测（兼容三件）：取值三档可判、认不出即最小假设 | 3.3、3.12、3.13 | `Availability`、`capabilities` | `T-3.3-01`、`T-3.12-01`、`T-3.13-01` |
| 概要设计 §12 | 设计合规验收十条 | 10.2 | — | 自检输出 |
| 概要设计 §12 | 验收可机械核：交付物身份四项与身份卡可逐字节比对 | 3.14、3.15 | `ArtifactIdentity`、`IdentityError` | `T-3.14-02`、`T-3.15-01` |
| 概要设计 §15.1 | 快速捕获：触发即编辑、空标题可存、断网可记 | 4.5 | `NotesView.vue` 宿主装配 | `T-4.5-01`、`UI-5.3.8-01` |
| 概要设计 §15.6 | 私密保护与加密边界：私密条目任何出口排除 | 4.5、8.3 | 笔记模块 | `T-4.5-03` |
| 概要设计 §15.9 | 删除进回收站；彻底清除二次确认 | 4.5 | 笔记模块 | `T-4.5-05` |
| 概要设计 §16.1 | 复盘定时触发与缺期 | 4.6 | 复盘插件槽位 | `T-4.6-01` |
| 概要设计 §16.2 | 复盘流水线编排 | 4.6 | 复盘插件槽位 | `T-4.6-02` |
| 概要设计 §16.10 | AI 复盘稿 | 4.6 | 复盘插件槽位 | `T-4.6-03` |
| 概要设计 §16.18 | 周报生成与投递 | 4.6 | 复盘插件槽位 | `T-4.6-04`、`UI-5.3.9-01` |
| 概要设计 §18.6 | 权限与审批：需审批动作逐条列出；子执行体不得代签 | 5.3.6、4.4 | 审批呈现 | `UI-5.3.6-01` |
| 概要设计 §18.23 | 可观测：每个动作一条追加式审计，带错误码与关键标识 | 6.3 | 审计日志 | `T-6.3-01` |
| 概要设计 §19.1 | 命令行出口：单进程、无 TTY 非交互、三档退出码、口令不入参 | 3.16、3.17 | `Platform/linux/src-tauri/Cli/src/main.rs` | `T-3.16-01`、`T-3.16-02`、`T-3.17-01` |
| 概要设计 §19.2 | 插件装配：同进程模块、清单唯一源；Linux 笔记离线、零 IPC | 4.5、2.3 | 插件清单 | `T-4.5-01`、`T-2.3-01` |
| 概要设计 §19.9 | 诊断读数：计划/摘要/慢查询；缺数写「未接」 | 4.7 | 同源诊断面 | `T-4.7-07` |
| 概要设计 第四章（平台差异表） | 平台能力六项一次探完、缺项可筛、顺序与冻结表一致 | 3.4、3.1、5.3.2 | `probe_all`、`startup_report`、能力面 | `T-3.4-01`、`T-3.1-01`、`UI-5.3.2-01` |
| 概要设计 第四章（平台差异表） | 命令层与插件只挂一次：同源挂载是唯一入口，重复注册即失败 | 3.2、3.19 | `run`、`attach` | `T-3.2-02` |
| 概要设计 第四章（平台差异表） | 打包成功须打印身份四项（目录 / 标签 / `sha256` / 构建时刻） | 3.20 | `build.sh` 收尾打印 | `T-3.20-01` |
| 概要设计 §7.1 | 同源执行面的状态与派生值单向下发（界面不重算、不双写） | 5.5 | 同源装配层 | `UI-5.5-01` |

矩阵数据行：78 行。概设侧逐条覆盖面 = §1.3 / §1.4 / §1.5 / §2 总则 2·4·6·7·8 / §3（含 §3.1 浏览页签另见 §11 第 2 条）/ §4.1–§4.10 / §5.1–§5.4 / §6.1–§6.4 / §7.1–§7.3 / §8.1–§8.11 / §9 / §10 / §11 / §11.4 / §12 / §15.1·§15.6·§15.9 / §16.1·§16.2·§16.10·§16.18 / §18.6 / §18.23 / §19.1·§19.2·§19.9 / 第四章平台差异表。**未进本表的概设节**（§15 其余 11 节、§16 其余 14 节、§18 其余 21 族、§19 其余 6 节）不是漏落：它们的业务判据在 `notes` / `retro` 分册三书与 `Db` 领域层自跑，本端只承接宿主装配与平台面，清单与理由见 §11 第 7 条。

---

## 1. 平台基线与实现范围

### 1.1 平台基线（Agent 不得更换）

> 依据：需求书 §1「原生体验」条（判据 = 不打包浏览器内核、不使用 Electron / JVM；系统自带 WebView 合规）+ 概要设计第四章 P-26 + 本仓盘上实物（`Platform/linux/src-tauri/Cargo.toml`）。

| 项 | 取值 | 版本约束 | 改动方式 |
|---|---|---|---|
| 语言（外壳与领域层） | Rust，edition 2021 | Tauri 2 需 Rust ≥ 1.77 | 需人类主人批准 |
| 界面承载 | Tauri 2 + 系统 WebView = WebKitGTK 4.1（`webkit2gtk-4.1`） | 随发行版；`pkg-config` 探测 | 需人类主人批准 |
| 前端 | Vue 3 + TypeScript，与 Windows 侧**同一套**（`Platform/windows/App/`） | 同源 `package-lock.json` | 需人类主人批准 |
| 包管理器 | npm（同源面里是 `package-lock.json`，不是 pnpm） | Node ≥ 20 | 需人类主人批准 |
| 打包形态 | `.deb` + `.AppImage`（`bundle.targets`） | Tauri bundler 2 | 需人类主人批准 |
| 领域层依赖 | 零第三方（`src-tauri/Core/Cargo.toml` 的 `dependencies` 段为空） | 新增即 `T-2.3-01` 判红 | 需人类主人批准 |
| 平台适配层依赖 | 零第三方（本片）；真绑定只许加在 `src-tauri/Platform/Linux/Cargo.toml` | 同上 | 需人类主人批准 |
| 测试 | `cargo test`（各 crate 内联 `cfg(test)` 测试模块） | — | 需人类主人批准 |
| 本端判据 | `python3 Platform/linux/Tools/check-linux-skeleton.py`（A–E 五条，rc 0 / 1） | — | 需人类主人批准 |
| 构建入口 | `Platform/linux/build.sh`（依赖探测 + 构建 + 打包 + 身份四项） | 退出码 0/1/2/3/4 见 §3.20 | 需人类主人批准 |
| 数据落点 | `$XDG_DATA_HOME/doyah-studio`，无该变量时 `$HOME/.local/share/doyah-studio` | XDG 基础目录规范 | 需人类主人批准 |
| 版本控制 | 只读展示（禁提交/推送/合并/切分支） | — | — |

概要设计 §10 的 12 条被拒绝方案在本端的禁止项：

| 概设 §10 被拒绝方案 | 本端禁止项 | 检查方式 |
|---|---|---|
| 只读连接给「仍然执行」 | 禁止任何绕过只读判定的入口；本端不得为它加平台分支 | 代码检索 `rg -n '仍然执行' Platform/linux` 为空 + `UI-5.3.3-01` |
| 用 `EXPLAIN ANALYZE` 估行数 | 仅允许 `EXPLAIN (FORMAT JSON)` | 代码检索 `rg -n 'EXPLAIN ANALYZE' Platform/linux` 为空 |
| 行数用表总行数或本地猜测 | 取不到即写「未接」，不报 0 | `UI-5.3.6-01` |
| 写语句自动重试 | 禁止对写语句自动重试；本端不得在承载层加重试中间件 | 代码检索 `rg -n 'retry' Platform/linux/src-tauri/src` 为空 + `T-4.7-03` |
| 界面层缓存数据库服务对象 | 服务按「连接 + 库」唯一，落点在同源外壳；本端不另建连接池 | 评审 + `UI-5.5-01` |
| 整表读进内存导出 | 必须流式写文件 | 代码检索 + `UI-5.3.7-01` |
| 多语句并发执行 | 按文本顺序逐条 | `T-4.7-03` |
| 未授权入口显示灰色 | 未授权即不出现（不是灰掉） | `UI-5.1-02` |
| 到期锁死数据 | 到期只降级入口，数据可开可导出 | `UI-5.1-02` |
| 结果行数据默认投给助理 | 必须显式确认并留痕 | `UI-5.3.6-02` |
| 把实现读数写进契约 | 读数只进台账（`Platform/linux/README.md` 与计划书），本文件不写用例数 | 评审 |
| 只读日志面板冒充终端 | 终端必须真交互（PTY） | `T-3.7-01` |

### 1.2 必须修改/新增的文件

| 文件路径 | 操作 | 用途 | 允许修改的符号 | 对应概设条款 |
|---|---|---|---|---|
| `Platform/linux/src-tauri/Core/src/capability.rs` | 修改 | 能力取值三档与能力名表 | `Availability`、`CAPABILITY_NAMES` | 概要设计 第四章平台差异表 |
| `Platform/linux/src-tauri/Core/src/artifact.rs` | 修改 | 交付物身份四项与拒收理由 | `ArtifactIdentity`、`IdentityError` | 概要设计 §12 |
| `Platform/linux/src-tauri/Core/src/lib.rs` | 修改 | 领域层版本口径与模块出口 | `PRODUCT_VERSION`、`mod artifact`、`mod capability` | 概要设计 §12 |
| `Platform/linux/src-tauri/Platform/Linux/src/lib.rs` | 修改 | 六项能力探测与缺项过滤 | `CapabilityProbe`、`probe_all`、`missing`、`probe_*` | 概要设计 第四章平台差异表、§11.4 |
| `Platform/linux/src-tauri/Platform/Linux/src/secret_store.rs` | 新增 | 密钥环真绑定（Secret Service） | `SecretStore`、`StoreError` | 概要设计 第四章 P-02 |
| `Platform/linux/src-tauri/Platform/Linux/Cargo.toml` | 修改 | 适配层依赖唯一入口 | `dependencies` 段 | 概要设计 第四章 P-26 |
| `Platform/linux/src-tauri/src/lib.rs` | 修改 | 起壳前置检查、能力 DTO、同源挂载 | `run`、`startup_report`、`capabilities`、`CapabilityDto`、`StartupReport` | 概要设计 第四章 P-26、§3 |
| `Platform/linux/src-tauri/Cli/src/main.rs` | 修改 | 无界面入口与退出码表 | `main`、`report_capabilities` | 概要设计 §19.1 |
| `Platform/linux/src-tauri/Cargo.toml` | 修改 | 工作区成员与外壳依赖 | `workspace` 段、`dependencies` 段、`features` 段 | 概要设计 §3 |
| `Platform/linux/src-tauri/tauri.conf.json` | 修改 | 窗口尺寸、CSP、打包目标 | `app.windows`、`app.security.csp`、`bundle` | 概要设计 第四章 P-01 / P-08 |
| `Platform/linux/src-tauri/capabilities/default.json` | 修改 | 最小能力集（逐项登记） | `permissions` | 概要设计 第四章 P-11 |
| `Platform/linux/build.sh` | 修改 | 构建入口与五档退出码 | `deps_report`、`build_and_package`、`probe_cmd`、`probe_pc` | 概要设计 第四章 P-08 / P-26 |
| `Platform/linux/Tools/check-linux-skeleton.py` | 修改 | 本端判据 A–E 五条 | `run_checks`、`check_workspace`、`check_core_boundary`、`check_frontend_reuse`、`check_build_entry`、`self_test`、`main` | 概要设计 §1.3、§12 |
| `Platform/linux/README.md` | 修改 | 骨架台账与未接网清单 | 全文 | 概要设计 §12 |

### 1.3 禁止修改的文件

- `Platform/macOS/`：对侧端实现，本侧不改、不判红
- `Platform/windows/App/src/`：同源前端，归 Windows 侧；跨端改动走 `shared_ledger` 派单，不在本端直接改
- `Platform/windows/App/src-tauri/`：同源命令层，本端只引用挂载入口与数据家路径，不改其行为
- `Platform/windows/Db/src/`：同源能力层（含 `agent*.rs`），本端只承接承载与取值
- `Platform/linux/src-tauri/Cargo.lock`：锁文件只由 cargo 生成，手改即「基线外依赖」嫌疑
- `Platform/linux/src-tauri/gen/`：Tauri 构建期生成物，手改下次构建即被覆盖
- `Platform/linux/src-tauri/icons/`：品牌资产（同一品牌图形、同一图标名），禁自绘或另存一套
- `Docs/Doyah产品概要设计说明书.md`：契约层归契约所有者；本文件无权改概设口径
- `Scripts/`：共享判据面，改动需 `shared_ledger` 登记（含各判据脚本的文件清单）

### 1.4 本文件不覆盖的内容

- 跨端行为判据（在概要设计 §3–§12 与第四章平台差异表）；进度与状态（开发计划书）；测试读数（台账）。
- 同源面的实现细节：前端视图（`Platform/windows/App/src/`）、命令层（`Platform/windows/App/src-tauri/`）、能力层（`Platform/windows/Db/`）的逐函数契约不在本文件，本端只定「怎么用、不许改什么」。
- 笔记与复盘两域的业务判据（概要设计 §15 其余 11 节、§16 其余 14 节）：在 `notes` / `retro` 分册三书自跑，本端只承接宿主装配（§4.5 / §4.6）。
- macOS / Windows 实现（各自的详细设计文件）。
- 平台与产品线口径不在本文件推导：一律直引概要设计 §1.4 矩阵（Studio / Notes / Retro / Agent / 授权 = PC 三端全量）与第四章平台差异表；本端不得写成其它端的子集，也不得自行新增 `P-*` 差异条目（新增须两侧同批登记，否则 `check-p-parity.py` 判红）。

---
## 2. 分层与模块

依赖单向，四层加一层本端领域层：

| 层 | 落点 | 职责 | 线程模型 |
|---|---|---|---|
| 界面层 | `Platform/windows/App/src/`（与 Windows 侧同源，由 WebKitGTK 承载） | 渲染、快捷键、命令面板、六态呈现 | WebKitGTK 主循环（界面线程） |
| 装配层 | 同源 `Platform/windows/App/src-tauri/src/` + 本端 `Platform/linux/src-tauri/src/lib.rs` | 承接界面意图、调能力层、把值分发回界面线程 | 主线程 |
| 能力层 | 同源 `Platform/windows/Db/src/`（含 `agent*.rs`） | 数据库执行、元数据、导入导出、助理、诊断 | 无 UI 依赖；阻塞工作不在界面线程 |
| 领域层（本端） | `Platform/linux/src-tauri/Core/src/` | 纯逻辑：能力取值三档、交付物身份四项 | 无 UI、无平台能力、无第三方依赖 |
| 平台适配层（本端） | `Platform/linux/src-tauri/Platform/Linux/src/` | 只有这一层谈 Linux 专有面（WebView / 密钥环 / PTY / 通知 / 剪贴板 / 托盘） | 按调用方 |

### 2.1 组件 → 实现单元

| 概设组件 | 实现单元 | 类型 | 所属文件 | 可见性 | 允许调用方 |
|---|---|---|---|---|---|
| 平台能力表 | `probe_all`、`missing` | function | `Platform/linux/src-tauri/Platform/Linux/src/lib.rs` | 公开 | 外壳 `startup_report`、CLI |
| 能力取值 | `Availability` | enum + impl | `Platform/linux/src-tauri/Core/src/capability.rs` | 公开 | 适配层、CLI、外壳 |
| 能力名表 | `CAPABILITY_NAMES` | const | `Platform/linux/src-tauri/Core/src/capability.rs` | 公开 | 适配层、外壳、判据 |
| 交付物身份 | `ArtifactIdentity`、`IdentityError` | struct + enum | `Platform/linux/src-tauri/Core/src/artifact.rs` | 公开 | 构建入口、CLI、测试 |
| 起壳与前置检查 | `run`、`startup_report`、`capabilities` | function | `Platform/linux/src-tauri/src/lib.rs` | 公开 | `main`、CLI 期自检 |
| 凭据存取 | `SecretStore`（trait） | trait | `Platform/linux/src-tauri/Platform/Linux/src/secret_store.rs`（新增） | 公开 | 装配层（同源连接面经注入） |
| 连接管理 / 驱动与方言 / 执行与事务 / 结果集 / 元数据 / 结构变更 / 导入导出 / 会话 / 诊断 / 任务与审批 / 审计 / 助理桥 / 授权判定 / 工作区文件 / 编辑器 / 页签 / 搜索面板 / 下方面板 / Git 只读 | 同源命令层与能力层（`doyah-studio-shell`、`doyah-studio-db`） | 引用，不复制 | `Platform/windows/App/src-tauri/`、`Platform/windows/Db/src/` | 只读引用 | 同源装配层 |
| 内嵌终端 | `probe_pty` + 同源 `pty.rs` | function | `Platform/linux/src-tauri/Platform/Linux/src/lib.rs` | 公开 | 外壳、CLI |

概要设计 §3 的「禁止做」在本端的实现级禁令：

- 界面层禁止 `import` 驱动实现：本端 `src-tauri/src/lib.rs` 不得出现 `doyah_studio_db::` 的驱动类型；判据 `rg -n 'doyah_studio_db::' Platform/linux/src-tauri/src` 只允许命中 `agent_settings` 一类值类型（当前为空）。
- 任意组件禁止跨层持有连接句柄、事务句柄、文件句柄：本端只递值（`CapabilityDto` / `StartupReport` / `ExitCode`），不持有任何句柄。
- 方言分支禁止散进本端：`Platform/linux/src-tauri/Platform/Linux/` 与 `Core/` 不得出现 SQL 方言判断（`postgres`/`mysql`/`gbase` 关键字）；判据 `rg -ni 'postgres|mysql|gbase' Platform/linux/src-tauri/{Core,Platform}` 为空。
- 本端禁止另长命令层：`invoke_handler` 与插件只许由同源 `attach` 设置一次；判据 = 检索 `Platform/linux/src-tauri/src` 时**非注释行**命中 0（当前命中只出现在 `//` 与 `//!` 注释里，是口径说明不是注册）。
- 能力探测禁止副作用：`probe_*` 只读文件系统与环境变量，禁起子进程、禁发网络、禁写盘（§3.4–§3.10）。
- 能力层禁止回调界面刷新：同源面的刷新路径由装配层折叠值，本端不注册任何界面回调。

### 2.2 注入点与可替换依赖

| 依赖 | 注入方式（三选一，写死） | 注入点 | 测试替身 | 禁止做法 |
|---|---|---|---|---|
| 数据家路径 | 环境变量（XDG）+ 形参 | `paths::app_home()` 读 `XDG_DATA_HOME` / `HOME`；测试用临时 `XDG_DATA_HOME` | 临时目录 | 在 `Platform/Linux/` 里硬编码 `~/.local/share/doyah-studio` |
| 凭据存储 | 构造函数参数（trait 对象） | `SecretStore` 由装配层构造后注入；`InMemorySecretStore` 只测试态 | `InMemorySecretStore` | 业务代码直连 D-Bus；无密钥环时落明文文件 |
| 平台能力探测 | 纯函数（无注入，输入只有文件系统与环境变量） | `probe_*` 的输入面 = `/usr/lib`、`pkg-config` 说明文件、`DBUS_SESSION_BUS_ADDRESS` / `SHELL` / `DISPLAY` / `WAYLAND_DISPLAY` | 夹具目录 + 环境变量置空 | 在探测里起 `pkg-config` 子进程之外的任何进程；探测里发网络 |
| 时钟 | 形参 | `ArtifactIdentity::new(..., built_at)` 的 `built_at` 由构建入口给 | 固定串 | 领域层内部取当前时间 |
| 内容哈希 | 形参（由构建入口算） | `ArtifactIdentity::new(..., sha256)` | 固定 64 位十六进制串 | 领域层读盘算哈希 |
| 进程出口 | 返回值 `ExitCode` | `Cli::main`、`report_capabilities` 返回 `ExitCode` | 直接断言返回值 | 库函数里 `std::process::exit`（唯一例外 = `run` 的承载面缺失分支） |

- 三选一的落地口径：**主注入手段 = 构造函数参数**（凡有实现的依赖）；**环境变量**只用于「进程启动时已定、运行期不变」的数据家路径；**无注入**只用于纯探测函数，其可替换性靠环境变量与夹具目录成立。
- 禁止在 `Core/` 里做 IO：`Core/src/*.rs` 不出现 `std::fs`、`std::env`、`std::process`（判据 `rg -n 'std::(fs|env|process)' Platform/linux/src-tauri/Core/src` 为空）。

### 2.3 目录与命名约束

- 新增文件目录：领域层只进 `Core/src/`；平台能力只进 `Platform/Linux/src/`；无界面入口只进 `Cli/src/`；跨 crate 集成测试只进 `src-tauri/tests/`（新增时同批登记 §1.2 与 §9.1）。
- 单元测试与被测同文件（内联 `cfg(test)` 测试模块），测试名以行为命名（`unrecognized_value_falls_back_to_unknown_not_missing`），不以序号命名。
- 命名：crate 前缀 `doyah-studio-`；模块与函数 `snake_case`；类型 `UpperCamelCase`；常量 `SCREAMING_SNAKE`；能力名统一取自 `CAPABILITY_NAMES`，任何位置不得另起一套名字（`webview` 不许写成 `webkit`）。
- 前端同源：`Platform/linux/` 下**不得**出现 `App/` 或 `dist/`；`tauri.conf.json` 的 `frontendDist` 必须指到 `Platform/windows/App/dist`（判据 D 条）。
- 插件清单唯一来源：同源 `Platform/windows/App/src/plugins/registry.ts`；本端不得另立插件清单或插件目录。
- 禁止跨层引用：`Core/` 不得引 GUI/平台 crate（`tauri`、`gtk*`、`gdk*`、`webkit2gtk`、`keyring`、`portable-pty` 等，判据 B / C 条）；`Platform/Linux/` 不得引 `tauri`；`Cli/` 不得引 GUI 面。
- 判据：`python3 Platform/linux/Tools/check-linux-skeleton.py` rc=0（A 判据面 / B 依赖面 / C 源码面 / D 前端同源 / E 构建入口形状）。

---

## 3. 函数/方法级契约

> 每节 = 一个公开函数或一个公开入口。七段齐：前置条件 / 后置条件 / 错误契约表 / 禁止行为 / 并发·幂等·事务 / 日志字段 / 测试 ID。错误契约表是本节唯一表格，逐行必须有「可重试」判定。本文件不定义的函数不得实现。

### 3.1 `startup_report() -> StartupReport`

- 所属单元：`Platform/linux/src-tauri/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（WebView 运行时依赖）
- 用途：起壳前算出承载面可用性与缺项清单，供 `run()` 决定「起壳 / 打印补救指引并非零退出」。

**前置条件**
- 调用方不要求宿主已装 WebKitGTK（缺前置也要能算出结论）。
- 环境变量可读；`/usr/lib`、`/usr/lib64`、`/lib` 至少一个可读（读不到按 `missing` 记，见 §11 第 1 条）。

**后置条件**
- `webview_ready` 仅当 `webview` 项取值为 `present` 时为真；`unknown` 与 `missing` 一律为假。
- `missing` 的项名序列 = `missing(&probe_all())` 的项名，顺序与 `CAPABILITY_NAMES` 一致。
- `guidance` 与 `missing` **等长且逐项对应**（同一索引指的是同一项）。
- 无副作用：不写盘、不建目录、不发网络、不改环境变量、不起进程。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 承载面缺失 | 不适用（返回值表达） | `webview_ready = false`，`missing` 含 `webview` | 是（装好前置后重跑，1 次人工） | 禁止把「没探到」写成 `webview_ready = true` |
| 可选面缺失（托盘一类） | 不适用 | `webview_ready = true`，`missing` 含该项 | 不适用（不阻塞启动） | 禁止因可选面缺失而返回 `webview_ready = false` |
| 非 Linux 宿主 | 不适用 | `webview_ready = false` | 否 | 禁止为「反正要上 Linux」报 `present`（假绿） |
| 依赖超时 | 不适用（同步只读探测，无网络） | 不适用 | 不适用 | 禁止给探测加轮询或超时重试 |

**禁止行为**
- 禁止在探测链里发网络、起子进程（除 `pkg-config` 之外）。
- 禁止在本函数内 `exit`：退出由 `run()` 一处决定。
- 禁止把 `unknown` 归入 `missing`（过滤只在 `missing()` 一处，§3.11）。
- 禁止捕获探测失败后返回「全 present」冒充正常。

**并发 / 幂等 / 事务**
- 纯读；并发调用互不影响。同一宿主同一时刻结论恒定（前置装/卸之后才变）。
- 无事务概念；不缓存结论（缓存会让「装好前置仍报缺」）。

**日志字段**
- 必记：`webview_ready`、`missing_count`、`missing_names`。
- 禁记：环境变量原值（`DBUS_SESSION_BUS_ADDRESS` 可含用户标识）、宿主家目录绝对路径。

**测试 ID**：`T-3.1-01`（正例：结论与探测事实一致）、`T-3.1-02`（反例：承载面缺失 ⇒ 非零退出且给指引）

### 3.2 `run()`

- 所属单元：`Platform/linux/src-tauri/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（缺运行时给可读提示、不静默失败）、§3（命令层唯一）
- 用途：起壳。承载面缺失即打印可读提示并**非零退出**；否则把同源命令层挂上后进入事件循环。

**前置条件**
- `main` 已把控制权交给本函数（`src/main.rs` 只调它）。
- 同源 crate `doyah-studio-shell` 已作为本 crate 依赖（`Cargo.toml` 里 `doyah-studio-shell = { path = "../../windows/App/src-tauri" }`）。

**后置条件**
- `startup_report().webview_ready == false` 且缺项含 `webview` ⇒ 逐条打印 `guidance` 后 `exit(1)`，**不进入事件循环**。
- `webview_ready == true` ⇒ 打印可选面提示（stderr）后进入事件循环；进入前只调一次 `doyah_studio_shell::attach(tauri::Builder::default())`。
- `attach` 的返回值直接 `.run(generate_context!())`；失败打印错误后 `exit(1)`。
- 不重复注册插件、不设第二个 `invoke_handler`。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 承载面缺失 | 不适用（进程退出码 `1`） | 打印指引后 `exit(1)` | 是（装前置后重跑） | 禁止白屏启动；禁止当成成功退出 |
| 同源命令层挂载失败 | 不适用（进程退出码 `1`） | 打印 `tauri::Error` 原文后 `exit(1)` | 是（重跑 1 次） | 禁止吞掉错误继续跑 |
| 插件/命令重复注册 | 不适用（启动期报错） | 由 `attach` 一侧单点设置，本函数不再注册 | 不适用 | 禁止本端再 `.plugin(...)` / `invoke_handler(...)` |
| 依赖超时 | 不适用（无网络） | 不适用 | 不适用 | 禁止在启动链路加重试掩盖挂载失败 |

**禁止行为**
- 禁止在本函数里改窗口尺寸、CSP、打包目标（那些在 `tauri.conf.json`，属配置不属代码）。
- 禁止为「让界面先出来」跳过承载面检查。
- 禁止 `unwrap()` 启动链路：失败必须打印可读原因并给出下一步。

**并发 / 幂等 / 事务**
- 进程内单次调用；重复调用无意义（第二次会二次挂载插件而报错），因此 `main` 只许调一次。
- 无事务；不持有跨进程状态。

**日志字段**
- 必记：`webview_ready`、`event_loop_entered`、`attach_result`。
- 禁记：窗口几何以外的用户数据；环境变量原值。

**测试 ID**：`T-3.2-01`（反例：缺承载面 ⇒ 退出码 1 且 stderr 含补救指引）、`T-3.2-02`（反例：本端源码不出现第二次插件/命令挂载）

### 3.3 `capabilities() -> Vec<CapabilityDto>`

- 所属单元：`Platform/linux/src-tauri/src/lib.rs` ｜ 对应概设条款：概要设计 §11.4（兼容三件：版本与方言探测）、第四章平台差异表
- 用途：把六项探测结论摊成前端/CLI 可消费的形状（名 + 取值串 + 一句可读提示）。

**前置条件**
- `CAPABILITY_NAMES` 六项已冻结（顺序：`webview`、`secret-service`、`pty`、`notifications`、`clipboard`、`tray`）。

**后置条件**
- 返回数组长度恒为 6，顺序与 `CAPABILITY_NAMES` 一致。
- 每项 `state` ∈ {`present`、`missing`、`unknown`} 三档之一（第四种取值出现即越界）。
- 每项 `guidance` 非空（缺项给补救指引、在项给「探到了什么」）。
- 与 `probe_all()` 逐项同名同取值（本函数只做形状转换，不改判）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 某项探测取值越界 | 不适用（不变量） | 由单测断言拦截，不产生第四档 | 不适用 | 禁止为未知取值临时加第四档 |
| 探测读不到目录 | 不适用 | 该项按 `missing` 返回并带指引 | 是（修权限后重跑） | 禁止静默返回空数组 |
| 依赖超时 | 不适用（无网络） | 不适用 | 不适用 | 禁止在转换层加 IO |

**禁止行为**
- 禁止在本函数里重新探测（必须复用 `probe_all()` 的一次结论，否则同一屏两次结论会不一致）。
- 禁止按平台分支过滤项（前端只渲染取值，不做「若是 Linux 则…」）。
- 禁止把 `guidance` 写成空串或纯符号。

**并发 / 幂等 / 事务**
- 纯函数式包装，可并发；同一次宿主状态下结论恒定；无事务。

**日志字段**
- 必记：`capability_count`、`missing_names`。
- 禁记：`guidance` 全文之外的用户环境细节。

**测试 ID**：`T-3.3-01`（DTO 名序 = 冻结表，取值只许三档）

### 3.4 `probe_all() -> Vec<CapabilityProbe>`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表、§11.4
- 用途：六项能力一次探完，顺序即契约（CLI 表格与判据都按这个顺序读）。

**前置条件**
- 宿主环境变量可读；不要求任何前置已安装。

**后置条件**
- 返回长度恒为 6，顺序 = `CAPABILITY_NAMES`。
- 每项 `name` 取自冻结表（不得另起名），`guidance` 非空。
- 无副作用：只读文件系统与环境变量。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 某项探测内部读盘失败 | 不适用 | 该项按 `missing` 返回 + 指引 | 是（修权限后重跑） | 禁止 panic；禁止返回 `present` |
| 环境变量缺失 | 不适用 | 对应项按语义给 `missing` 或 `unknown` | 否 | 禁止用默认值假装环境正常 |
| 依赖超时 | 不适用（同步只读） | 不适用 | 不适用 | 禁止加超时/重试包装 |

**禁止行为**
- 禁止增删项或改顺序（前端与判据都读同一张表）。
- 禁止在探测里起进程、发网络、写盘。
- 禁止把六个 `probe_*` 的结果在别处二次拼装（顺序只在这里定）。

**并发 / 幂等 / 事务**
- 纯读，可并发；同一宿主状态下结论恒定；无事务。

**日志字段**
- 必记：`probe_count`、`state_histogram`（三档各几项）。
- 禁记：各项 `guidance` 里的系统路径之外的用户信息。

**测试 ID**：`T-3.4-01`（六项顺序 = 冻结表，且每项带非空指引）

### 3.5 `probe_webview() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（WebView 运行时）
- 用途：判定系统 WebView（WebKitGTK 4.1）是否在盘上，缺则给一行能照做的补救指引。

**前置条件**
- 无（探测本身不依赖前置）。

**后置条件**
- 判据 = 共享库 `libwebkit2gtk-4.1.so*` 命中 `/usr/lib`、`/usr/lib64`、`/lib` 或架构目录之一，**或** `pkg-config` 说明文件 `webkit2gtk-4.1.pc` 在盘上 ⇒ `present`。
- 两者都不在 ⇒ `missing`，`guidance` 含包名与安装命令（Debian / Ubuntu 口径）。
- `state` 不出第三档以外的取值；不写盘。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 库与 `pkg-config` 说明都不在 | 不适用 | `missing` + 装包指引 | 是（装好后重跑） | 禁止把缺失报成 `unknown` 后继续起壳 |
| 非 Linux 宿主（开发机） | 不适用 | `missing`（如实，不乐观） | 否 | 禁止因「目标平台是 Linux」报 `present` |
| 目录读不了 | 不适用 | 按 `missing` 处理并给指引 | 是（修权限） | 禁止吞掉读目录错误返回 `present` |
| 依赖超时 | 不适用（不做版本查询，见 §11 第 1 条） | 不适用 | 不适用 | 禁止手写 FFI 或 `dlopen` 去问版本 |

**禁止行为**
- 禁止在本片接 `webkit2gtk` 版本查询（未接网清单第 3 项；接入前 `present` 的语义只是「前置在盘上」）。
- 禁止手写 FFI（`extern "C"`、`#[link(`、`libc::`）——平台适配层同样受此约束。
- 禁止扫描用户目录里的私有 WebView 副本（本端不打包浏览器内核）。

**并发 / 幂等 / 事务**
- 纯读，可并发；同一宿主状态下结论恒定；无事务。

**日志字段**
- 必记：`capability = webview`、`state`、`hit_path`（命中库或 `pkg-config` 说明文件的目录，非用户目录）。
- 禁记：用户家目录路径。

**测试 ID**：`T-3.5-01`（非 Linux 宿主只许报 `missing`，不许假绿）

### 3.6 `probe_secret_service() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（凭据存储：无密钥环如实报错、不回落明文）
- 用途：判定系统密钥环（Secret Service）是否可用，缺则给装包指引，并把「不回落明文」写进提示。

**前置条件**
- 无。

**后置条件**
- 会话总线存在（`DBUS_SESSION_BUS_ADDRESS` 已设）**且** `org.freedesktop.secrets.service` 在 `/usr/share/dbus-1/services/` ⇒ `present`。
- 总线缺失 ⇒ `missing`，`guidance` 明说「无密钥环可用：凭据功能如实报错、不回落明文」。
- 总线在但服务文件缺 ⇒ `missing`，`guidance` 给装包命令（GNOME Keyring / KWallet 二选一）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无会话总线 | 不适用 | `missing` + 「不回落明文」说明 | 是（进图形会话后重跑） | 禁止回落到文件明文存储 |
| 服务文件缺失 | 不适用 | `missing` + 装包指引 | 是（装好后重跑） | 禁止假定「有总线就有密钥环」 |
| 依赖超时 | 不适用（只查文件与环境变量，不调 D-Bus） | 不适用 | 不适用 | 禁止在探测里真调 Secret Service 接口 |

**禁止行为**
- 禁止在探测阶段做真实凭据读写（那是 §3.21 的事）。
- 禁止把「服务文件在」当成「接口可用」（同 §3.5 的口径：本片只判存在性）。
- 禁止降级到明文文件并把状态报成 `present`。

**并发 / 幂等 / 事务**
- 纯读，可并发；结论恒定；无事务。

**日志字段**
- 必记：`capability = secret-service`、`state`、`session_bus_present`、`service_file_present`。
- 禁记：总线地址原文（可能含用户标识）。

**测试 ID**：`T-3.6-01`（无总线 ⇒ `missing` 且提示含「不回落明文」）

### 3.7 `probe_pty() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（内嵌终端：真交互式 shell）
- 用途：判定内嵌终端能否起（解释器在不在），缺则明说「内置终端不可用，界面按取值灰着」。

**前置条件**
- 无。

**后置条件**
- `$SHELL` 非空且指向的解释器在盘上 ⇒ `present`。
- `$SHELL` 未设或不在盘上、而 `/bin/sh` 在盘上 ⇒ `present`，`guidance` 明写「按兜底取 `/bin/sh`」。
- 两者都不可用 ⇒ `missing`（内置终端不可用，不阻塞启动）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| `$SHELL` 指向不存在的路径 | 不适用 | 兜底 `/bin/sh` ⇒ `present` | 不适用 | 禁止把兜底说成「用户 shell 可用」 |
| `$SHELL` 与 `/bin/sh` 都不可用 | 不适用 | `missing` + 「终端不可用」说明 | 是（装 shell 后重跑） | 禁止仍报 `present` 让界面画一个起不来的终端 |
| 依赖超时 | 不适用（只查路径存在性） | 不适用 | 不适用 | 禁止真起 PTY 来「试一下」（PTY 真绑定未落，见 §10.1 第 3 项） |

**禁止行为**
- 禁止在探测里 `fork` 子进程、禁止读 `/dev/pts` 判可用性（同 §3.5 的只判存在性口径）。
- 禁止把「解释器在」写成「PTY 可用」；措辞必须区分（见 §13 第 2 条）。
- 禁止接受相对路径的 `$SHELL` 值（只认绝对路径）。

**并发 / 幂等 / 事务**
- 纯读，可并发；结论恒定；无事务。

**日志字段**
- 必记：`capability = pty`、`state`、`interpreter_source`（`shell` / `fallback`）。
- 禁记：用户 shell 的完整路径所属用户名。

**测试 ID**：`T-3.7-01`（`$SHELL` 缺 ⇒ 兜底 `/bin/sh` 且提示写明走了兜底）

### 3.8 `probe_notifications() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（通知：不打扰用户、可关闭）
- 用途：判定 freedesktop 通知通道在不在，缺则如实降级（不静默丢通知）。

**前置条件**
- 无。

**后置条件**
- 会话总线在 **且** `org.freedesktop.Notifications.service` 在盘上 ⇒ `present`。
- 否则 ⇒ `missing`，`guidance` 明写「通知如实降级并说明（不静默丢）」。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 通知服务缺失 | 不适用 | `missing` + 降级说明 | 是（装通知服务后重跑） | 禁止静默丢通知且不说明 |
| 无会话总线 | 不适用 | `missing` | 是（进图形会话后重跑） | 禁止直接跳过该项（六项必须齐） |
| 依赖超时 | 不适用（只查文件） | 不适用 | 不适用 | 禁止在探测里真发一条通知 |

**禁止行为**
- 禁止发测试通知（会打扰用户）。
- 禁止把通知缺失计入「阻塞启动」的判据（只有 `webview` 阻塞）。

**并发 / 幂等 / 事务**
- 纯读，可并发；结论恒定；无事务。

**日志字段**
- 必记：`capability = notifications`、`state`。
- 禁记：无额外用户数据。

**测试 ID**：`T-3.8-01`（服务缺失 ⇒ `missing` 且带降级说明）

### 3.9 `probe_clipboard() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（剪贴板与拖放：复制语义一致）
- 用途：判定剪贴板通道属于 X11 还是 Wayland；两者都没有时报 `unknown`（问不出来），不报 `missing`。

**前置条件**
- 无。

**后置条件**
- `WAYLAND_DISPLAY` 已设 ⇒ `present`，`guidance` 标「Wayland 会话」。
- 否则 `DISPLAY` 已设 ⇒ `present`，`guidance` 标「X11 会话」。
- 两者都没设 ⇒ `unknown`（问不出来，不是「不支持」），不得计入缺项。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无图形会话变量 | 不适用 | `unknown` + 「按 unknown 渲染」说明 | 是（进图形会话后重跑） | 禁止报 `missing`（那会把「没探到」说成「不支持」） |
| 两者同时存在 | 不适用 | 按 Wayland 优先 ⇒ `present` | 不适用 | 禁止在同一次结论里给两个档位 |
| 依赖超时 | 不适用 | 不适用 | 不适用 | 禁止真读写剪贴板来验证 |

**禁止行为**
- 禁止把剪贴板可用性当成数据正确性的前提（复制失败的提示走 §6.1 的错误呈现）。
- 禁止在探测里读取剪贴板内容（可能含用户数据）。

**并发 / 幂等 / 事务**
- 纯读，可并发；结论恒定；无事务。

**日志字段**
- 必记：`capability = clipboard`、`state`、`session_kind`（`wayland` / `x11` / `none`）。
- 禁记：剪贴板内容。

**测试 ID**：`T-3.9-01`（无 `DISPLAY` / `WAYLAND_DISPLAY` ⇒ `unknown`，且不计入缺项）

### 3.10 `probe_tray() -> CapabilityProbe`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（托盘为可选面）
- 用途：判定托盘指示器库在不在；缺则不打托盘，且**不阻塞启动**。

**前置条件**
- 无。

**后置条件**
- `libayatana-appindicator3.so*` 在库目录 ⇒ `present`。
- 否则 ⇒ `missing`，`guidance` 明写「可选面，不阻塞启动；降级形态待定（§11 第 3 条）」。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 托盘库缺失 | 不适用 | `missing` + 「不阻塞启动」说明 | 是（装库后重跑） | 禁止把它算进阻塞启动的判据 |
| 目录读不了 | 不适用 | `missing` + 指引 | 是（修权限） | 禁止吞错后报 `present` |
| 依赖超时 | 不适用 | 不适用 | 不适用 | 禁止在探测里初始化托盘 |

**禁止行为**
- 禁止为托盘缺失自造降级行为（降级形态是待定项，§11 第 3 条）。
- 禁止把托盘项从六项表里删掉（表是冻结的）。

**并发 / 幂等 / 事务**
- 纯读，可并发；结论恒定；无事务。

**日志字段**
- 必记：`capability = tray`、`state`。
- 禁记：无额外用户数据。

**测试 ID**：`T-3.10-01`（缺库 ⇒ `missing` 且不影响 `webview_ready`）

### 3.11 `missing(probes) -> Vec<&CapabilityProbe>`

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/lib.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（缺项如实、不假绿）
- 用途：只挑出「确实缺」的项，供 CLI 退出码与启动前置共用同一处过滤。

```text
pub fn missing(probes: &[CapabilityProbe]) -> Vec<&CapabilityProbe>
```

**前置条件**
- 入参来自 `probe_all()`（顺序与六项表一致）；允许传空切片（返回空向量）。

**后置条件**
- 返回只含 `state == Missing` 的项；`present` 与 `unknown` 都不出现。
- 顺序与入参一致（不重排）；不复制元素（返回引用）。
- 空入参 ⇒ 空返回（不恐慌）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 入参含 `unknown` 项 | 不适用 | 该项**不**出现在返回值里 | 不适用 | 禁止把 `unknown` 算成缺项（会把「问不出来」判成「不支持」） |
| 空入参 | 不适用 | 返回空向量 | 不适用 | 禁止用 `unwrap()` 取首项 |
| 依赖超时 | 不适用（纯内存过滤） | 不适用 | 不适用 | 禁止在过滤时重新探测 |

**禁止行为**
- 禁止在调用方各写一份过滤（否则退出码与启动前置会给出两种结论）。
- 禁止在此处排序或去重（顺序是契约）。

**并发 / 幂等 / 事务**
- 纯函数，无共享状态；同一入参结论恒定；无事务。

**日志字段**
- 必记：`input_count`、`missing_count`。
- 禁记：无。

**测试 ID**：`T-3.11-01`（三档混合入参 ⇒ 只返回 `missing` 项，`unknown` 不算缺）

---
### 3.12 `Availability::parse(raw: &str) -> Self`

- 所属单元：`Platform/linux/src-tauri/Core/src/capability.rs` ｜ 对应概设条款：概要设计 §11.4（兼容三件：取值三档可判）
- 用途：把取值串解析成三档枚举；**认不出即 `Unknown`**（最小假设档，既不许读成「有」也不许读成「没有」）。

**前置条件**
- `raw` 允许任意字符串（含空串、含大小写混排、含首尾空白）。

**后置条件**
- `"present"`（大小写不敏感、两端空白裁掉）⇒ `Present`；`"missing"` ⇒ `Missing`。
- 其余一切输入（含空串、`"yes"`、`"unknown"` 之外的拼写）⇒ `Unknown`。
- 不做 IO、不做本地化、不记日志（领域层无副作用）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 认不出的取值 | 不适用（返回值表达） | `Unknown` | 是（调用方换取值串） | 禁止回落到 `Missing`（会把「没探到」说成「系统不支持」） |
| 空串 / 纯空白 | 不适用 | `Unknown` | 否 | 禁止 panic 或返回 `Present` |
| 大小写混排 | 不适用 | 按小写归一后判定 | 不适用 | 禁止要求调用方预转小写 |

**禁止行为**
- 禁止新增第四档（三档是跨端契约，新增先改概要设计）。
- 禁止在解析时读环境变量或文件（领域层零 IO，§2.2）。
- 禁止把 `"unknown"` 解析成 `Missing`。

**并发 / 幂等 / 事务**
- 纯函数；同输入同输出；无事务、无共享状态。

**日志字段**
- 必记：无（领域层不写日志；观测点在调用方）。
- 禁记：入参原文（可能来自环境变量）。

**测试 ID**：`T-3.12-01`（三档正例 + 认不出 ⇒ `Unknown` 的反例）

### 3.13 `Availability::as_str(self) -> &'static str`

- 所属单元：`Platform/linux/src-tauri/Core/src/capability.rs` ｜ 对应概设条款：概要设计 §11.4
- 用途：把三档回写成取值串，保证「写出去的与读进来的同一张表」。

**前置条件**
- 无（`self` 是枚举值，三档闭集）。

**后置条件**
- `Present` ⇒ `"present"`、`Missing` ⇒ `"missing"`、`Unknown` ⇒ `"unknown"`（小写、无空格）。
- 与 `parse` 往返一致：`parse(as_str(v)) == v` 对三档全部成立。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 新增枚举档但未加映射 | 不适用（编译期） | 编译失败（`match` 穷尽性） | 不适用 | 禁止用 `_ => "unknown"` 兜住未映射的档 |
| 大小写/空格漂移 | 不适用 | 由往返单测拦 | 不适用 | 禁止在别处再拼一份取值串 |

**禁止行为**
- 禁止在 CLI、外壳、判据里各自手写 `"present"` 字面量（一律经本函数）。
- 禁止返回本地化文案（取值串是机器读的，文案在 `guidance`）。

**并发 / 幂等 / 事务**
- 纯函数；无状态；无事务。

**日志字段**
- 必记：无。禁记：无。

**测试 ID**：`T-3.13-01`（三档往返一致）

### 3.14 `ArtifactIdentity::new(directory: &str, label: &str, sha256: &str, built_at: &str) -> Result<Self, IdentityError>`

- 所属单元：`Platform/linux/src-tauri/Core/src/artifact.rs` ｜ 对应概设条款：概要设计 §12（交付物身份四项与判据可机检）
- 用途：把交付物身份四项一起校验、一起收下；任何一项坏即整份拒收（不许半份身份卡）。

**前置条件**
- 四个入参都来自构建入口的实测值（`directory` / `label` 由打包产物给、`sha256` 由 `sha256sum` 给、`built_at` 由入口取时刻）。

**后置条件**
- 收下时：`directory`、`label`、`built_at` 均为裁剪两端空白后的值；`sha256` 归一为小写、长度 64、全十六进制。
- 拒收时：返回 `IdentityError` 的具体变体，不产生半份结构体。
- 不读盘、不算哈希（哈希由调用方给，领域层零 IO）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 目录为空/纯空白 | `IdentityError::EmptyDirectory` | `Err` | 是（补齐入参） | 禁止用 `.` 顶替空目录 |
| 标签（包文件名）为空 | `IdentityError::EmptyLabel` | `Err` | 是（补齐入参） | 禁止自造 `doyah.deb` 一类占位名 |
| `sha256` 非 64 位十六进制 | `IdentityError::MalformedSha256` | `Err` | 是（重算哈希） | 禁止截断或补零凑 64 位 |
| 构建时刻为空 | `IdentityError::EmptyBuiltAt` | `Err` | 是（重取时刻） | 禁止用当前时间顶替（会把不可复现写进身份卡） |

**禁止行为**
- 禁止把四项分开校验后「先返回部分身份」。
- 禁止在此处补时间戳、补哈希、补文件名——缺什么就拒什么。
- 禁止接受大写哈希原样存下（必须小写归一，否则同一产物两份身份卡）。

**并发 / 幂等 / 事务**
- 纯函数；同样入参同样结论；无事务。

**日志字段**
- 必记：`accepted`、`error_variant`（拒收时）。
- 禁记：`directory` 的用户家目录绝对路径（身份卡本身写盘，日志不必重复）。

**测试 ID**：`T-3.14-01`（四项齐 + 大写哈希 ⇒ 归一为小写）、`T-3.14-02`（逐项坏 ⇒ 对应变体拒收，不产生结构体）

### 3.15 `ArtifactIdentity::identity_card(&self) -> String`

- 所属单元：`Platform/linux/src-tauri/Core/src/artifact.rs` ｜ 对应概设条款：概要设计 §12
- 用途：生成身份卡正文（四行中文键名，与构建入口收尾打印同款），随包走。

**前置条件**
- `self` 由 `new` 产出（四项已校验）。

**后置条件**
- 输出恰四行，顺序固定：`目录=` / `标签=` / `sha256=` / `构建时刻=`，每行一项、行尾换行。
- 与 `build.sh` 收尾打印的四行**逐字节同款**（同一份形状，不许两处各拼一套）。
- 不含凭据、连接串、构建机用户名。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 字段含换行 | 不适用（`new` 已裁剪空白） | 输出仍为四行 | 不适用 | 禁止在卡片里插自定义标题行或分隔线 |
| 交付物缺项 | 不适用 | `new` 阶段已拒收，本函数拿不到这样的 `self` | 不适用 | 禁止在本函数里做二次校验并静默跳过坏项 |

**禁止行为**
- 禁止在此函数里读环境或时钟（身份卡只反映 `self`）。
- 禁止本地化键名（键名是判据锚点，改键名等于改判据）。
- 禁止输出 JSON / YAML 形态（口径是四行纯文本，解析方按行读）。

**并发 / 幂等 / 事务**
- 纯函数；同一 `self` 输出逐字节一致；无事务。

**日志字段**
- 必记：`card_bytes`。禁记：卡片正文（正文已写进文件，日志重复即泄露构建机路径）。

**测试 ID**：`T-3.15-01`（四行顺序与键名固定，与 `build.sh` 收尾格式一致）

### 3.16 `main() -> ExitCode`（`doyah-studio-cli`）

- 所属单元：`Platform/linux/src-tauri/Cli/src/main.rs` ｜ 对应概设条款：概要设计 §19.1（命令行出口：单进程、无 TTY 非交互、失败可判）
- 用途：无界面入口。子命令 `capabilities`（可带 `--json`） 出平台能力表；`version` 出进程内版本口径；其余一律用法错。

**前置条件**
- 不要求图形环境、不要求 TTY（无 TTY 时不得等待输入）。
- 参数只认 `capabilities`、`version`、`-h`/`--help`；`capabilities` 额外只认 `--json`。

**后置条件**
- `capabilities`：走 §3.17，退出码 0（无缺项）或 2（有缺项）。
- `version`：打印 `PRODUCT_VERSION` 后返回 0。
- 空参数或 `-h`/`--help`：打印用法后返回 0。
- 认不出的子命令/参数：stderr 打可读原因（子命令还带用法），返回 1。
- 输出只走 stdout（正常结果）与 stderr（诊断），两者不混。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 认不出的子命令 | 不适用（退出码 `1`） | stderr 原因 + 用法 | 是（改参数） | 禁止返回 0；禁止把错误混进 stdout |
| `capabilities` 带多余参数 | 不适用（退出码 `1`） | stderr 点名多余参数 | 是（去掉参数） | 禁止忽略多余参数照跑 |
| 有缺项 | 不适用（退出码 `2`） | stderr 点名缺项，`unknown` 不计入 | 是（补齐前置） | 禁止把「有缺项」报成「跑失败」（两者分档） |
| 无 TTY | 不适用 | 非交互直接出结果 | 不适用 | 禁止等待输入 |

**禁止行为**
- 禁止把口令放进命令行参数或输出（本命令不吃凭据参数，也不得新增）。
- 禁止在此入口里起 GUI 或要求 `DISPLAY`。
- 禁止为本命令引第三方依赖（`--json` 手写输出，保证任何宿主可跑）。

**并发 / 幂等 / 事务**
- 单进程单次执行；同一宿主状态下输出恒定（`host` 字段随机器名）；无事务。

**日志字段**
- 必记：`subcommand`、`exit_code`、`missing_count`（能力表时）。
- 禁记：环境变量原值、宿主家目录。

**测试 ID**：`T-3.16-01`（`capabilities` 有缺项 ⇒ 退出码 2 且逐项点名）、`T-3.16-02`（认不出的子命令 ⇒ 退出码 1 + 用法）

### 3.17 `report_capabilities(json: bool) -> ExitCode`

- 所属单元：`Platform/linux/src-tauri/Cli/src/main.rs` ｜ 对应概设条款：概要设计 §19.1、第四章平台差异表
- 用途：把六项能力摊成文本表或 JSON，并按「有无缺项」返回 0 / 2。

**前置条件**
- 由 `main` 在参数校验通过后调用；`probes` 必须是 `probe_all()` 的一次结论。

**后置条件**
- 文本形态：表头一行（取值 `present` / `missing` / `unknown`）+ 六行（名、取值、指引），顺序 = `CAPABILITY_NAMES`。
- JSON 形态：顶层 `host`（机器名，取不到写 `unknown`）+ `capabilities` 数组，每项三字段 `name` / `state` / `guidance`；字符串按 JSON 规则转义。
- 无缺项 ⇒ 返回 `ExitCode::SUCCESS`；有缺项 ⇒ stderr 打「缺 N 项：…（`unknown` 不计入缺失）」后返回 2。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 有 `missing` 项 | 不适用（退出码 `2`） | stderr 点名 + 计数 | 是（补齐前置） | 禁止把缺项藏进正常输出后返回 0 |
| 只有 `unknown` 项 | 不适用（退出码 `0`） | 正常输出 | 不适用 | 禁止把 `unknown` 计入缺失 |
| JSON 转义遇到引号/换行 | 不适用 | 按 JSON 规则转义（`\"`、`\n`、`\\`） | 不适用 | 禁止输出不成 JSON 的文本（会让下游解析全挂） |
| `HOSTNAME` / `COMPUTERNAME` 都取不到 | 不适用 | `host` 写 `unknown` | 不适用 | 禁止读 `/etc/hostname` 之外的用户文件 |

**禁止行为**
- 禁止在本函数里重新探测（一次结论只摊一次）。
- 禁止为 JSON 引第三方序列化库（零依赖是 §1.1 基线）。
- 禁止把 `guidance` 里的包名改成「联系管理员」一类无信息文案。

**并发 / 幂等 / 事务**
- 单进程；同一宿主状态下输出恒定；无事务。

**日志字段**
- 必记：`format`（`text` / `json`）、`missing_count`、`exit_code`。
- 禁记：`host` 之外的机器标识。

**测试 ID**：`T-3.17-01`（`--json` 形状可解析、字段齐、转义正确）

### 3.18 `paths::app_home() -> PathBuf`（同源，本端只读引用）

- 所属单元：`Platform/windows/App/src-tauri/src/paths.rs` ｜ 对应概设条款：概要设计 第四章平台差异表（配置与数据目录：XDG）
- 用途：算出应用数据家。Windows 走 `%APPDATA%\DoyahStudio`；**本端走 XDG**：`$XDG_DATA_HOME/doyah-studio`，无该变量时 `$HOME/.local/share/doyah-studio`。

**前置条件**
- 由同源装配层调用；本端不复制该实现，只按此契约消费其返回值。
- 允许环境变量缺失（缺了要落到下一档，不许落到当前目录冒充正常）。

**后置条件**
- `XDG_DATA_HOME` 非空 ⇒ `$XDG_DATA_HOME/doyah-studio`。
- 否则 `HOME` 非空 ⇒ `$HOME/.local/share/doyah-studio`。
- 两者都取不到 ⇒ 退回当前目录（并在界面上把路径显示出来，不静默丢数据）。
- 目录名带连字符（`doyah-studio`），与 Windows 侧 `DoyahStudio` **不强行统一**。
- 不创建目录（存在性不保证；写前由调用方 `create_dir_all`）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| `XDG_DATA_HOME` 未设 | 不适用 | 落 `$HOME/.local/share/doyah-studio` | 不适用 | 禁止落当前目录（换目录启动就全不见） |
| 两个变量都未设 | 不适用 | 当前目录 + 界面显示路径 | 是（设环境变量后重跑） | 禁止 panic；禁止静默吞掉 |
| 变量为空串 | 不适用 | 视同未设，落下一档 | 不适用 | 禁止拼出 `//doyah-studio` 一类畸形路径 |

**禁止行为**
- 禁止在本端（`Platform/Linux/`、`Core/`）再算一次数据家路径（两处算 = 两处漂）。
- 禁止把数据家写进 `tauri.conf.json` 的固定相对路径。
- 禁止把笔记数据家嵌套进工程数据家（P-15：平级独立）。

**并发 / 幂等 / 事务**
- 纯函数（只读环境变量）；同环境同结论；无事务。

**日志字段**
- 必记：`resolved_from`（`xdg` / `home` / `fallback`）。
- 禁记：完整绝对路径中的用户名段。

**测试 ID**：`T-3.18-01`（三档：设 XDG / 只设 HOME / 都不设）、`T-3.18-02`（本端不出现第二处路径拼接）

### 3.19 `doyah_studio_shell::attach(builder) -> builder`（同源，本端只读引用）

- 所属单元：`Platform/windows/App/src-tauri/src/lib.rs` ｜ 对应概设条款：概要设计 §3（组件调用规则与命令面唯一）
- 用途：把同源命令层、状态与插件面挂到 Tauri builder 上。**这是本端唯一的挂载入口**。

**前置条件**
- 只许调一次，且必须在 `.run()` 之前。
- 本端不得在此之前 `.plugin(...)` 或 `invoke_handler(...)`（重复注册会启动期报错；第二个 `invoke_handler` 会静默覆盖第一个）。

**后置条件**
- 返回同一个 `builder`（链式），命令面 = 同源 `generate_handler!` 的注册全集（本端不增不减；条数以同源源码为唯一出处，不在本书写死）。
- 插件实例只装一次（`dialog` 等），权限由 `capabilities/default.json` 的逐项登记决定。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 本端已注册过插件/命令 | 不适用（启动期报错） | `attach` 或 `run` 失败，进程退出 1 | 否（改代码） | 禁止用 `try_attach` 一类吞错重试 |
| 能力清单与插件不匹配 | 不适用（build 期报错） | `tauri-build` 报 `Permission … not found` | 是（对齐清单后重建） | 禁止把 `dialog:default` 换成整包权限图省事 |
| 依赖超时 | 不适用（构建期问题） | 不适用 | 不适用 | 禁止在运行期动态补挂插件 |

**禁止行为**
- 禁止在本端复制一份命令层（「另长一份」是概设 §3 的禁止项）。
- 禁止改同源 `attach` 的行为（§1.3 禁止文件）。
- 禁止为本端新增 tauri 命令（新增命令属跨端契约变更，走 `shared_ledger`）。

**并发 / 幂等 / 事务**
- 启动期单次；调用两次即启动失败（这是保护，不是缺陷）；无事务。

**日志字段**
- 必记：`attach_ok`、`command_count`（取同源注册项数，只记数不记名）。
- 禁记：命令参数、用户数据。

**测试 ID**：`T-3.19-01`（本端源码不出现 `invoke_handler` / `.plugin(`，挂载点唯一）

### 3.20 `Platform/linux/build.sh`（构建入口）

- 所属单元：`Platform/linux/build.sh` ｜ 对应概设条款：概要设计 第四章平台差异表（打包与分发、构建可复现）、§12
- 用途：一条命令完成「依赖探测 → 前端装配（同源 `npm ci`）→ 构建打包（`cargo tauri build`）→ 打印交付物身份四项」。

**前置条件**
- `--deps` 只读探测：不写盘、不装包。
- 构建路径要求 `uname -s` == `Linux`、`src-tauri/` 在盘上、同源面 `Platform/windows/App/package.json` 在盘上。
- 同源面 `node_modules` 不在盘上时先 `npm ci`（在**同源目录**里装，不在本端装）。

**后置条件**
- 退出码按表返回（0/1/2/3/4），且与结论一一对应。
- 构建成功时在 `src-tauri/target/release/bundle/` 下产出 `.deb` 与/或 `.AppImage`，并逐包打印四行：`目录=` / `标签=` / `sha256=` / `构建时刻=`（与 §3.15 同款）。
- 本端不产生 `App/` 或 `dist/` 副本（前端同源，判据 D 条）。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| `--deps` 有缺项 | 不适用（退出码 `1`） | 逐项 `MISS` + 一行 apt 参考命令 | 是（装包后重跑） | 禁止把缺项报成成功（rc=0） |
| 非 Linux 宿主 | 不适用（退出码 `2`） | 打印「如实拒绝构建」并指向对应端入口 | 否（换宿主） | 禁止在本机假装能构建 |
| `src-tauri/` 不在盘上 | 不适用（退出码 `3`） | 打印「应用骨架未落地」 | 是（补齐骨架） | 禁止当成脚本自身故障 |
| 同源前端缺失 | 不适用（退出码 `4`） | 打印「同源面不在盘上 ⇒ 前端同源前提不成立」 | 是（补齐同源面） | 禁止另存一份前端顶上 |
| 未知参数 | 不适用（退出码 `4`） | 打印未知参数 + 用法 | 是（改参数） | 禁止忽略未知参数照跑 |

**禁止行为**
- 禁止在本端 `dist/` 或 `App/` 下复制前端产物（同源性是硬契约）。
- 禁止在 `--deps` 里装包（探测只读）。
- 禁止把 `pkg-config` 探测写成「能编译就算齐」——缺 `webkit2gtk-4.1` 必须点名。
- 禁止省略失败路径的退出码（`set -e` + 显式 `return` 双写）。

**并发 / 幂等 / 事务**
- 单次串行执行；同时跑两份会争同一 `target/` 目录 ⇒ 不做并发保护，但必须由 `cargo` 自身报错而非静默产出坏包。
- `--deps` 可重复跑（幂等）；构建重复跑结论一致（除时间戳与哈希）。

**日志字段**
- 必记：`host_uname`、`deps_missing_count`、`bundle_targets`、`artifact_label`、`artifact_sha256`、`built_at`。
- 禁记：同源面的 `node_modules` 路径、用户家目录、任何凭据。

**测试 ID**：`T-3.20-01`（打包成功 ⇒ 退出码 0 且打印身份四项）、`T-3.20-02`（非 Linux 宿主 ⇒ 退出码 2）、`T-3.20-03`（同源前端缺失 ⇒ 退出码 4）、`T-3.20-04`（`--deps` 缺项 ⇒ 退出码 1 且逐项点名）

### 3.21 `SecretStore`（新增，密钥环真绑定）

- 所属单元：`Platform/linux/src-tauri/Platform/Linux/src/secret_store.rs`（**新增**）｜ 对应概设条款：概要设计 第四章平台差异表（凭据存储）、§4.1、§4.2
- 用途：凭据只经系统密钥环（Secret Service）存取；**无密钥环时如实报错、不回落明文**。三个方法构成闭集，不提供第四种入口。

**前置条件**
- `connection_id` 非空且来自已保存的连接（标识稳定）。
- 适配层依赖只许加在 `src-tauri/Platform/Linux/Cargo.toml`（`keyring` crate 一类），且必须先在 §1.2 与本行登记。

**后置条件**
- `set(id, secret)` 成功 ⇒ 该条目的凭据可被 `get(id)` 取回逐字节相同；写失败 ⇒ 返回 `Err`，且磁盘上不出现任何明文副本。
- `get(id)` 有条目 ⇒ `Ok(Some(secret))`；无条目 ⇒ `Ok(None)`（**不是** `Err`，也不是空串）。
- `delete(id)` 成功 ⇒ 之后 `get(id)` 为 `Ok(None)`；条目本就不存在 ⇒ `Ok(())`（删除幂等）。
- 三方法都不写配置文件、不进日志、不进模型上下文。

**错误契约**

| 场景 | 错误码 | 抛出 / 返回 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 无可用密钥环（`probe_secret_service` 为 `missing`） | `StoreError::NoKeyring` | `Err(NoKeyring)` | 是（装密钥环后重试） | 禁止回落到明文/混淆文件；禁止返回 `Ok(None)` 冒充「没存过」 |
| `connection_id` 为空 | `StoreError::EmptyId` | `Err(EmptyId)` | 是（补 id） | 禁止用空 id 建条目 |
| 后端拒绝（锁定 / 权限） | `StoreError::Backend(msg)` | `Err(Backend(原话))` | 是（解锁后重试 1 次） | 禁止把原话改写成「未知错误」 |
| 后端超时 | `StoreError::Backend(msg)` | `Err(Backend(含耗时))` | 是（重试 1 次，退避 300 ms） | 禁止超时后当作「无凭据」继续连接 |

**禁止行为**
- 禁止在任何路径上落明文口令（含 `~/.config`、`$XDG_DATA_HOME`、当前目录）。
- 禁止把口令写进错误信息、日志、审计、导出包。
- 禁止把 `NoKeyring` 降级成「空口令尝试连接」（概设 §4.1 明令禁止）。

**并发 / 幂等 / 事务**
- 以 `connection_id` 为幂等键：同一 id 的重复 `set` 覆盖为最后一次、重复 `delete` 都返回 `Ok`。
- 后端调用串行（同一时刻一个 Secret Service 请求），不并发打同一密钥环。
- 无事务概念：`set` 与 `delete` 各自原子；与「写连接清单」不组成跨存储事务，因此删除连接时必须**先清凭据再删清单**，清失败即报 `CRED_PURGE_FAILED` 并明说残留位置。

**日志字段**
- 必记：`connection_id`（标识，非口令）、`op`（`set` / `get` / `delete`）、`outcome`、`elapsed_ms`。
- 禁记：口令本体、密钥环条目属性全名、后端返回的原始报文（可能含路径）。

**测试 ID**：`T-3.21-01`（存/取/清往返：`set`→`get` 相同、`delete` 后为 `None`、重复删不报错）、`T-3.21-02`（无密钥环 ⇒ `Err(NoKeyring)` 且盘上无明文副本）

---
## 4. 数据与状态

### 4.1 内部结构映射

| 概设实体/字段 | 本端类型 | 关键字段 | 可变性 / 序列化契约 | 对应概设条款 |
|---|---|---|---|---|
| 能力取值 | `Availability`（enum） | `Present` / `Missing` / `Unknown` | 不可变；序列化为 `"present"` / `"missing"` / `"unknown"`（小写，经 `as_str` 一处出口） | 概要设计 §11.4 |
| 能力探测结论 | `CapabilityProbe`（struct） | `name: &'static str`、`state: Availability`、`guidance: &'static str` | 不可变；`name` 取自 `CAPABILITY_NAMES`，`guidance` 非空 | 概要设计 第四章平台差异表 |
| 能力 DTO（前端/CLI 形状） | `CapabilityDto`（struct, `Serialize`） | `name`、`state`、`guidance` | 不可变；JSON 字段名即字段名，`state` 用取值串（不用数字码） | 概要设计 §11.4 |
| 启动前置报告 | `StartupReport`（struct, `Serialize`） | `webview_ready: bool`、`missing: Vec<&'static str>`、`guidance: Vec<&'static str>` | 不可变；`missing` 与 `guidance` 等长同序；空数组写 `[]` 不写 `null` | 概要设计 第四章平台差异表 |
| 交付物身份 | `ArtifactIdentity`（struct） | `directory`、`label`、`sha256`（小写 64 位十六进制）、`built_at` | 不可变；文本卡片四行纯文本（键名固定，见 §3.15） | 概要设计 §12 |
| 连接配置（同源） | `ConnectionConfig`（同源类型） | 名称/类型/主机/端口/库名/用户名/凭据引用/SSL/超时/`schemaVersion` | 可写方 = 连接管理；**不含口令本体**；日期 `ISO8601`，缺省用 `null` 不用空串 | 概要设计 §5.1 |
| 凭据（本端） | `SecretStore` 条目 | 键 = 连接标识；值 = 口令 | 只经 §3.21 三方法；不落配置文件、不进日志 | 概要设计 第四章平台差异表 |
| 执行记录（同源） | 归档文件行 | 归档日 / SQL 文本 / 连接标识 / 目标库 / 时刻 / 耗时 / 重复次数 | 只增不改；按天一份；同一条 SQL 只累计次数 | 概要设计 §5.2 |
| 任务定义与审批回执（同源） | 任务配置件 + 追加式记录 | 目标库 / 读写模式 / 影响行数上限 / 是否需审批；回执读数 | 布尔显式 `true`/`false`；回执已脱敏；预估缺失写「未接」 | 概要设计 §5.3、§5.4 |

- 序列化契约（跨端同源，本端不得另立一套）：
  - JSON 字段名 = 类型字段名（不另起驼峰/下划线别名）；时间一律 `ISO8601`；空值用 `null`，空集合用 `[]`。
  - 取值串只有三档，且只能由 `Availability::as_str` 产出（§3.13）；任何位置手写 `"present"` 字面量即判红。
  - 布尔字段必须显式写 `true` / `false`，禁写 `1` / `0` / `"yes"`。
- 禁止行为：
  - 禁止 DTO 暴露能力探测的内部实现字段（`hit_path`、`session_bus_present` 一类只进日志，不进 DTO）。
  - 禁止把口令、凭据引用原文、完整连接串放进任何结构体的可序列化分支。
  - 禁止在 `Core/` 里引 `serde`（领域层零第三方依赖，序列化在适配层/外壳做）。

### 4.2 存储契约

| 存储 | 落点 | 主键 / 唯一 | 约束 | 允许写入方 | 迁移策略 |
|---|---|---|---|---|---|
| 连接清单 | `app_home()/connections.json`（同源） | 连接标识 | 名称同工作区唯一；端口 1–65535；`schemaVersion` 非空；原子替换写 | 连接管理（同源） | `schemaVersion` 升级一次，旧文件先备份再写 |
| 查询归档 | `app_home()/queries/<YYYY-MM-DD>.sql`（同源） | 日期 + 序号 | 只增不改；日期键校验（`YYYY-MM-DD`）；不跨日追加 | 执行路径（同源） | 只增不改 |
| 审计账本 | `app_home()/agent-audit.json`（同源，与配置同目录的第三份文件） | 追加序号 | 追加式账本，不删不改；坏 JSON 读成空账并如实报；不含口令与结果行数据 | 审计（同源） | 只增不改 |
| 凭据 | 系统密钥环（Secret Service） | 连接标识 | 键 = 连接标识；无密钥环即报错（不落明文） | §3.21 `SecretStore` | 无迁移（条目随连接删） |
| 笔记库（独立数据家） | 平级独立目录（不嵌套在工程数据家内） | 笔记标识 | SQLite + WAL；附件不进 BLOB；`PRAGMA user_version` 记 schema 版本；迁移一次性且旧文件留档 | 笔记模块 | 幂等升级，旧文件留 `.migrated` |
| 交付物身份卡 | 随包（构建产物旁） | 包标签 | 四行纯文本；`sha256` 小写 64 位 | `build.sh` 收尾（§3.20） | 不适用（每包一份） |
| 构建产物 | `src-tauri/target/release/bundle/{deb,appimage}` | 包文件名 | 不手工改；不手工重算哈希 | `cargo tauri build` | 不适用（可清理重建） |

- 事务边界：一次业务动作一个事务；归档与审计属「动作后置」，失败只报「记录未落盘」，**不回滚已成功的业务执行**（概要设计 §5.2 禁止项）。
- 跨存储顺序：删除连接必须**先清凭据再删清单**；清凭据失败即报 `CRED_PURGE_FAILED` 并明说残留位置（禁止只删列表项留凭据）。
- 配置写入原子：清单用「临时文件 + 原子替换」，半写会丢全部连接；损坏时给可读错误并**保留原文件**（不静默重建）。
- 迁移只增不改：本端不新增迁移目录；笔记库迁移在同源笔记模块内，历史条目禁止编辑。
- 本端自有落点只有两处：密钥环条目（§3.21）与构建产物/身份卡（§3.20）；其余存储全部落同源面（本端只消费路径）。

### 4.3 核心算法（伪代码级）

- 对应概设：概要设计 第四章平台差异表（起壳前置）与 §3（组件调用规则）。

```text
输入：宿主环境（库目录、环境变量）
1  probes ← probe_all()                     # 六项，顺序 = CAPABILITY_NAMES，只读
2  report ← startup_report()                 # webview_ready 只认 webview 项 == present
3  若 report.webview_ready 为假：
4      逐条打印 report.guidance（stderr）
5      退出码 1，不进入事件循环              # 不白屏、不静默失败
6  逐条打印可选面提示（stderr，不阻塞）
7  attach(builder) 一次                     # 命令层/插件只挂一次
8  builder.run()                            # 失败打印原话并退出码 1
```

- 对应概设：概要设计 §7.1（查询执行全链）——**本端承接方式 = 只读引用同源实现，不改语义**。

```text
输入：编辑器文本 T、选区 S、连接 C、目标库 DB、事务模式 M
1  若 C 未连接 → EXEC_NO_CONNECTION 并停
2  Q ← S 非空 ? S : T                       # 有选区只跑选区
3  若 Q 为空 → EXEC_EMPTY_SQL 并停
4  D ← 只读/高危判定                        # 拒绝即停；需确认则等人确认
5  按文本顺序逐条执行，逐条上报「第 N 条」
6  失败即停在当条，上浮原文与序号，事务标记未知
7  全部完成 → 汇总行列数与耗时 → 写归档与审计
```

- 对应概设：概要设计 §12（验收可机检）——交付物身份四项的生成顺序。

```text
输入：打包产物路径 P
1  标签 ← basename(P)
2  哈希 ← sha256(P)（构建入口算，领域层只收值）
3  时刻 ← 入口取当前时刻（ISO8601）
4  id ← ArtifactIdentity::new(dirname(P), 标签, 哈希, 时刻)
5  若 id 为 Err → 打印对应变体并退出非零     # 缺什么拒什么，不补默认值
6  打印 id.identity_card()                   # 四行，与身份卡逐字节同款
```

### 4.4 状态覆盖清单

| 状态机 | 当前 → 目标 | 触发 | guard / 抛出 | 所在函数 | 测试 ID |
|---|---|---|---|---|---|
| 连接（同源） | 失败 → 已连接 | 直接置已连接 | **禁止**跳转；必须经「连接中」再握手 | 同源连接面 | `T-4.4-01` |
| 语句执行（同源） | 已取消 → 已完成 | 置已完成 | **禁止**；重跑是一次新执行 | 同源执行面 | `T-4.4-02` |
| 审批单（同源） | 已拒绝 / 已过期 → 已批准 | 置已批准 | 判决不可翻；过期按拒绝处置 | 审批呈现（§5.3.6） | `T-4.4-03` |
| 查询页签（同源） | 执行中 → 已关闭 | 关闭请求 | 拒绝并提示「执行中，请先停止」 | 页签模型（同源） | `T-4.4-04` |
| 能力取值（本端） | `unknown` → `missing` / `present` | 任意调用方按需归类 | **禁止**；三档闭集，`unknown` 不许被读成「有」或「没有」 | `Availability::parse`、`missing` | `T-4.4-05` |
| 构建/启动退出码（本端） | 任意 → 0/1/2/3/4 之外 | 新增返回路径 | **禁止**；新增码必须先改本节与 §3.20 表 | `build.sh`、`run`、`Cli::main` | `T-4.4-06` |
| 全部枚举（本端与同源） | 新增未列出状态 / 绕过 guard | 直接赋值 | **禁止**；`match` 必须穷尽，`_ =>` 兜住枚举即判红 | `Availability`、`IdentityError` | `T-4.4-07` |

- 闭集约束：`Availability` 三档、`IdentityError` 四变体、退出码五档都是闭集；新增档位必须先改概要设计对应节（能力三档 = §11.4 探测口径；退出码 = 第四章平台差异表）再改代码。
- 同源四台状态机（连接 / 执行 / 审批 / 页签）的**流转语义不在本端定义**，本端只承接其呈现与承载；本端不得新增事件、不得在承载层补写状态。
- 本端两档闭集（能力取值、退出码）的 guard 全部落在 §3.12 / §3.11 / §3.20 / §3.16 四处的错误契约表里，不另设隐藏分支。

### 4.5 笔记域（概要设计 §15 的本端承接面）

本端对笔记域的职责是**宿主装配 + 平台面**，不实现业务判据；下列六面是本端必须保证的边界：

- **离线装配**：笔记随包同进程装配（`Platform/windows/App/src/plugins/notes/`，经同源 `registry.ts` 登记），数据只落本机 SQLite，进程内零跨进程通信、零网络出口（概要设计 §19.2 第 5 条）。
- **独立数据家**：笔记库与工程数据家（`app_home()`）**平级独立**，不嵌套；备份与清理各自独立（P-15）。
- **捕获不阻塞**（对应概要设计 §15.1）：捕获路径不依赖网络与账号；断网时状态是「待同步」而不是「失败」；空标题可存（首页文本，空则「无标题」）。
- **附件不进库**（对应概要设计 §15.2）：库内只存引用（标识、原文件名、字节数、摘要），字节在文件系统；引用解析不到必须显示「文件不在了」并给原文件名，不画空白框。
- **检索如实报路**（对应概要设计 §15.7）：检索覆盖标题/正文/标签；中文走 trigram，查询串 < 3 字按子串兜底并**标注走了哪条路**；「没跑成」不得显示成「没找到」。
- **私密与回收站**（对应概要设计 §15.6 / §15.9）：私密条目在本端可用，但任何出口（导出 / 日志 / 崩溃报告 / 模型上下文）一律排除；删除进回收站，彻底清除二次确认。
- 本端不做：笔记正文格式、待办与日历、历史版本、同步与冲突合并的业务判据（在 `notes` 分册三书自跑）。这些节在本矩阵里没有行，理由登记在 §11 第 7 条。

### 4.6 复盘域（概要设计 §16 的本端承接面）

- 定位：复盘是**可独立分发的桌面产品**，Linux 与 macOS / Windows 同为一等目标端（能力书 §1「桌面，与 Studio 同」；概要设计 §1.4）。
- 本端只做宿主：`Platform/windows/App/src/plugins/retro/`（`RetroView.vue` + 块文档/期次索引/排序偏好）由本端承载，**插件槽位装配**与**单向上下文**是本端的责任。
- 实现本体在 `retro` 仓（`platform/` 现只有 `macos`、`windows` 两棵树）——**Linux 树待建**，属实现缺口而非文档缺口，登记 §10.1 第 5 项。
- 契约承接面四节：定时触发与缺期（§16.1）、流水线编排（§16.2）、AI 复盘稿（§16.10）、周报生成与投递（§16.18）——本端保证「槽位可挂、失败可见、数据家隔离、只走交换面」四条。
- 禁止：把复盘算法写进界面层或本端领域层；复盘插件反向依赖 Studio 装配层；周报直写对方库（只走交换面）；宿主向复盘数据家回写。
- 判据：`T-4.6-01`–`T-4.6-04`（本端用例 = 槽位与装配面；业务判据在 `retro` 分册自跑）。

### 4.7 同源能力层继承边界（本端只读引用）

本端与 Windows 侧**共用同一套**命令层与能力层（`doyah-studio-shell` / `doyah-studio-db`），因此下列契约在本端的落地方式是「不改语义地承接」：

| 契约面 | 同源落点 | 本端责任 | 本端禁止 |
|---|---|---|---|
| 连接 / 删除 / 执行 / 取消 | `Platform/windows/App/src-tauri/src/connections.rs`、`postgres.rs`、`query.rs` | 提供凭据（§3.21）与数据家（§3.18）；呈现错误 | 另建连接池；在承载层加重试；改写 SQL 或方言判断 |
| 元数据 / 结构变更 / 导入导出 / 会话 / 诊断 | 同源 `src/` 各模块 + `Db/src/` | 呈现六态与错误、绑事件 | 在界面层直连驱动；把方言分支写进本端 |
| 工作区文件与外部改动 | 同源 `fs.rs` + `workspace/` | 提供目录与权限模型（Linux 无沙箱，P-11 / P-18） | 静默覆盖被外部改过的文件 |
| Agent 四类组件（命令执行 / 代码执行 / 工具目录 / 并行编排） | 同源 `Db/src/agent*.rs` 与宿主运行时 | 提供承载与平台能力（PTY / 剪贴板 / 通知取值） | 在本端重写命令执行；为 Linux 单独放宽沙箱 |
| 助理桥与审批 | 同源 `ChatPanel.vue` + 审批路径 | 呈现审批卡与回执 | 允许子执行体代签；把行数据默认投递 |

- 本端只对**平台面**负责：WebView 承载、密钥环、PTY、通知、剪贴板、托盘（六项取值），以及打包与身份四项。
- 判据：`T-4.7-01`（本端不复制命令层）、`T-4.7-02`（Agent 四组件落点在同源，本端无实现）、`T-4.7-03`（逐条顺序与多结果集由同源保证，本端不得插入并发）、`T-4.7-04`（取消语义同源）、`T-4.7-05`（会话终止二次确认呈现）、`T-4.7-06`（外部改动二选一）、`T-4.7-07`（诊断缺数写「未接」）。

---
## 5. 界面实现

> 本节只写实现落点与六态；视觉参数（颜色 / 尺寸 / 间距 / 字号）一律见设计规范与主题值表。界面语汇、层次规则、九个显示开关**只有一处出处 = 概要设计 §8.11**，本书只做「映射到本端落点」，不重新定义。

### 5.1 视图与组件落点

| 概设视图（概要设计 §8.2） | 本端落点 | 依赖接口 | 备注 |
|---|---|---|---|
| 查询页签 | `Platform/windows/App/src/views/DatabaseView.vue`（同源） | 概要设计 §4.3 / §4.4 | 执行/停止按钮状态互换；编辑器与结果区同源 |
| 结果区 | `DatabaseView.vue` 内结果网格 + `src/grid/` | 概要设计 §4.3 / §4.8 | 多结果集切换器、导出入口；虚拟化由 `src/grid/windowing.ts` |
| 连接表单 | `Platform/windows/App/src/shell/ConnectionDialog.vue`（同源） | 概要设计 §4.1 | 类型切换联动默认端口与 SSL；凭据由本端 §3.21 提供 |
| 连接清单 | `src/shell/SideBar.vue` 连接分组 + `connectionDisplay.ts` | 概要设计 §4.1 / §4.2 | 删除二次确认并明说连带删凭据 |
| 对象树 | `src/shell/SideBar.vue`（同源） | 概要设计 §4.5 / §4.6 | 刷新不清选中；层级随类型 |
| 表设计 | `src/views/DatabaseView.vue` DDL 分支 + `SchemaDiffPanel.vue` | 概要设计 §4.7 | 预览与执行是两个动作 |
| 导入导出 | `src/shell/BackupDialog.vue`、`src/shell/RestoreDialog.vue` | 概要设计 §4.8 | 部分失败列明细 |
| 会话视图 | `src/views/DatabaseView.vue` 的管理面（IPC `admin_sessions`） | 概要设计 §4.9 | 四项读数 + 确认终止；诊断读数走 `src/shell/DiagnosisDialog.vue`（挂在查询页签工具条，不是独立视图） |
| 对话页签 | `src/shell/ChatPanel.vue`（同源） | 概要设计 §4.10 / §4.3 | 工具卡片可展开；审批卡内联 |
| 审批单 | `ChatPanel.vue` 审批卡 + `AgentAuditDialog.vue` | 概要设计 §5.4 / §18.6 | 逐条列语句与目标库；预估缺数写「未接」 |
| 下方面板 | `src/shell/BottomPanel.vue`（同源） | 概要设计 §3 | 终端页签须真 PTY（本端 §3.7 提供取值） |
| 浏览页签 | **未建**（同源面无浏览器视图） | 概要设计 §3.1 | 登记 §11 第 2 条；入口不得先出现 |
| 笔记面 | `src/plugins/notes/NotesView.vue`（同源，离线装配） | 概要设计 §15 / §19.2 | 数据只落本机 SQLite；活动栏入口 |
| 复盘面 | `src/plugins/retro/RetroView.vue`（同源，宿主槽位） | 概要设计 §16 | 业务实现待 `retro` 仓 Linux 树 |
| 启动前置面（本端独有） | `Platform/linux/src-tauri/src/lib.rs` 的 `run` + `startup_report` | 概要设计 第四章平台差异表 | 无 GUI 元素：stderr 提示 + 退出码 |
| 平台能力面（本端独有） | `Platform/linux/src-tauri/Cli/src/main.rs` 的 `capabilities` 子命令 | 概要设计 §11.4 | 文本表 / `--json` 两形态 |

- 视图清单外的入口一律不得新增：同源 `src/shell/commands.ts` 的命令目录与本书 §5.1 必须是同一集合；本端不注册任何前端路由。
- 本端独有的两个「面」（启动前置面、平台能力面）都不是 GUI 组件，落点是进程出口与 CLI 输出——**不得**为它们在前端另外画一个面板（那是第 4 个入口，超出概要设计 §8.2 清单）。

### 5.2 根视图分栏骨架与窗口承载

本端窗口由 `Platform/linux/src-tauri/tauri.conf.json` 声明，界面在此窗口的 WebKitGTK 视图里渲染同源前端：

```text
Window(label=main, 1280x800, min 960x600, resizable)
└─ WebKitGTK view  ← frontendDist = Platform/windows/App/dist（同源，不另存）
   └─ App.vue（活动栏 / 侧栏 / 内容列 / 下方面板，信息架构随概要设计 第四章 P-01）
```

| # | 纪律 | 落点 / 判据 |
|---|---|---|
| 1 | 壁纸只在窗口根部铺一次，任何列/面板不得再铺 | 同源 `src/theme/` 的根容器；判据 `UI-5.2-01` |
| 2 | 侧栏可见性由活动项派生（笔记/复盘屏收起外层侧栏） | 同源 `src/shell/activityBarStore.ts`；不得交给容器代管 |
| 3 | 浮层不参与布局（挂覆盖层，浮出与收起时内容区宽度逐点相同） | 同源浮层组件；判据见 §5.4 |
| 4 | 窗口最小尺寸 960×600，缩放时三栏比例不崩 | `tauri.conf.json` 的 `minWidth` / `minHeight` |
| 5 | 深色跟随系统（WebKitGTK 的 `prefers-color-scheme`），不做应用内自选暗色 | 同源 `src/theme/index.ts` + 主题值表 |
| 6 | 快捷键与 Windows 端同键位；冲突处逐条登记，不另立一套 | 同源命令目录（唯一出处）；判据 `UI-5.7-03` |

- 承载面缺失时**没有窗口**：本端不提供「半残界面」，直接按 §3.2 的非零退出路径给出指引（这是与 macOS 侧最大的形态差异，理由 = 不打包浏览器内核，无法降级）。
- `tauri.conf.json` 的三处硬约束：`app.security.csp` 不得放宽到允许远程脚本（`connect-src` 只许 `ipc:` 与 `http://ipc.localhost`）；`bundle.targets` 只许 `deb` 与 `appimage`；`build.frontendDist` 只许指同源面。

### 5.3 组件级六态契约

> 六态 = 加载中 / 空数据 / 错误 / 权限不足 / 提交中 / 部分失败。每个组件六行齐；「禁止渲染」列逐行给出**必须为空**的渲染结果，任一行留空即判缺陷（`UI-5.3-01`）。同源组件的实现落点写在文件那一侧，本端负责「承载 + 取值 + 判据」。

#### 5.3.1 启动前置面 `StartupGate`

- 对应概设条款：概要设计 第四章平台差异表（缺运行时给可读提示）、§8.2
- 输入：`startup_report()` 的三个字段；内部状态：无（一次性函数，纯派生）
- 出口：stderr 文本 + 进程退出码（不是 GUI 组件）

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 探测为同步只读，无中间态 | 无（探测期间不输出半截结论） | 进度条、动画、`正在检测…` 占位（同步调用不需要） |
| 空数据 | `missing` 为空且 `webview_ready` 为真 | 无（静默进入事件循环） | 空提示面板、`全部就绪` 一类横幅 |
| 错误 | `webview_ready == false` | 逐条 `guidance` + 一行「装好前置后重试」+ 退出码 1 | 白屏窗口；伪造的「离线模式」 |
| 权限不足 | 库目录不可读导致探测失败 | 「读不到库目录」+ 需要的最小权限 + 退出码 1 | 把权限问题报成「未安装」 |
| 提交中 | 不适用（无提交语义） | 不适用 | 任何「正在提交」态（本面无写操作） |
| 部分失败 | `webview` 在、其他项缺 | `webview_ready = true` + 逐条可选面提示（stderr） | 因可选面缺失而拒绝启动 |

- 副作用：无（不写盘、不发网络）。禁止行为：不得为本面增加 GUI 弹窗（它是进程出口，不是视图）。

#### 5.3.2 平台能力面 `CapabilitySurface`

- 对应概设条款：概要设计 §11.4、第四章平台差异表
- 输入：`probe_all()` 一次结论；内部状态：`json: bool`（只影响输出形态）

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 同步探测，无中间态 | 一次性完整表（六行） | 半张表（先出三行再补三行） |
| 空数据 | 六项恒存在（表是冻结的） | 不适用（不存在空表） | 空表头；`(无能力)` 一类文案 |
| 错误 | 探测内部读盘失败 | 该项按 `missing` 显示 + 装包指引 | 隐藏失败项；把失败项从表里删掉 |
| 权限不足 | 库目录不可读 | 「读不到目录」指引 + 该项按 `missing` | 报成 `present`；静默跳过 |
| 提交中 | 不适用（只读面） | 不适用 | 「正在写入」态（本面无写操作） |
| 部分失败 | 有 `missing` 项但 `unknown` 不计入 | 表 + stderr「缺 N 项：…（`unknown` 不计入缺失）」+ 退出码 2 | 缺项时返回 0；把 `unknown` 计入缺项 |

- 副作用：无。禁止行为：不得在 `--json` 里省略 `guidance`（前端/判据要读）；不得为本面新增子命令。

#### 5.3.3 查询页签 `DatabaseView`

- 对应概设条款：概要设计 §4.6 / §4.7 / §8.4 / §8.7
- 输入（同源 props）：当前连接与库、页签标识；内部状态（实测名）：`dialogOpen`、`formReady`、`problemSummary`、`browseError`、`ioOpen`、`page`、`pageSize`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 执行中态（同源执行事件） | 执行按钮换停止 + 逐条进度 | 空白结果区；允许重复点执行 |
| 空数据 | 结果为空且无错误 | 空态文案 + 「执行当前 SQL」引导 | 错误件；无说明的空白页 |
| 错误 | 同源错误件（含语句序号与原文） | 原因 + 序号 + 可复制原文 + 重试入口 | 静默失败；空结果冒充成功 |
| 权限不足 | 只读连接遇写语句（判定在同源能力层） | 只读原因 + 涉事语句 | 灰色「仍然执行」入口；先渲染再报错 |
| 提交中 | 保存/导出进行中 | 按钮进行中态 + 禁用 | 重复发起第二次保存 |
| 部分失败 | 多语句汇总含失败条 | 逐条列成功/失败 + 行数 | 整体报成功；丢失败条 |

- 副作用：执行成功写归档与审计（同源）；取消写「已取消」结局。禁止行为：失败后清空编辑器；只改界面状态冒充取消；把多结果集折叠成一个；把 DDL 当普通查询静默执行。

#### 5.3.4 连接表单 `ConnectionDialog`

- 对应概设条款：概要设计 §4.1 / §5.1 / §8.6
- 输入：模式（新建/编辑）、既有连接配置；内部状态：同源表单草稿与字段错误分支

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 试探连接进行中 | 试探进度 + 表单禁用 | 无反馈地卡住按钮 |
| 空数据 | 无已接入类型（不应发生） | 「无可用类型」+ 引导 | 空下拉可提交 |
| 错误 | 字段错误分支 / 试探失败 | 字段下方错误 + 原因原话 | 只弹全局提示 |
| 权限不足 | 无**密钥环**时填凭据 | 「无密钥环 ⇒ 装 GNOME Keyring / KWallet」+ 禁用保存 | 允许保存后落明文；静默降级成文件存储 |
| 提交中 | 保存进行中 | 按钮进行中态 + 禁用 | 重复提交产生两份连接 |
| 部分失败 | 清单写入成功但凭据写入失败 | 「凭据未能保存」+ 残留位置 + 清理入口 | 报「保存成功」；只回滚一半且不告知 |

- 副作用：保存走同源连接清单 + 本端 §3.21 凭据写入；删除时**先清凭据再删清单**。禁止行为：明文口令回显；用空口令尝试连接；端口越界静默夹取。

#### 5.3.5 对象树 `SideBar`

- 对应概设条款：概要设计 §4.5 / §8.4
- 输入：当前连接；内部状态：展开集合与选中标识（刷新不清）

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 节点级加载中 | 该节点转圈（不阻塞整棵树） | 整棵树清空后重画 |
| 空数据 | 该层确无子节点 | 「(空)」 | 错误件；伪造占位节点 |
| 错误 | 该节点取数失败 | 节点级错误 + 重试入口 | 显示空树冒充「没有对象」 |
| 权限不足 | 服务端拒绝读该层 | 明说缺什么权限 + 补救动作 | 把库画成空库 |
| 提交中 | 不适用（树无写操作） | 不适用 | 「正在保存」一类态 |
| 部分失败 | 同层部分节点取不到 | 成功节点照常 + 失败节点标出 | 整层丢弃 |

- 副作用：展开走同源元数据接口（读幂等，并发展开合并）。禁止行为：刷新清空用户选择；把不同方言层级强行统一；伪造「加载中」以外的占位节点。

#### 5.3.6 对话与审批 `ChatPanel`

- 对应概设条款：概要设计 §4.10 / §5.4 / §18.6 / §8.4
- 输入：工作区与连接上下文；内部状态（实测名）：`sending`、`partial`、`deciding`、`pendingDecisions`、`brokenSessions`、`sessionsProblem`、`writes`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `sending == true` | 流式正文 + 工具块折叠头 + 中断入口 | 空白消息区；允许重复发送 |
| 空数据 | 无会话且无消息 | 空态文案 + 「开始对话」引导 | 伪造的历史消息 |
| 错误 | `sessionsProblem` 非空 | 原因 + 坏会话数（`brokenSessions`）+ 跳过说明 | 静默跳过坏会话不计数 |
| 权限不足 | 审批被拒 / 能力位不足 | 明说缺什么（授权位 / 服务器权限）+ 怎么给 | 灰掉的「批准」按钮 |
| 提交中 | `deciding == true` | 审批卡按钮进行中 + 禁用 | 重复提交同一审批单 |
| 部分失败 | `partial` 非空（流式中途断） | 已收内容 + 「未闭合」标记 + 重试 | 把半截回答显示成完整回答 |

- 副作用：审批动作留痕（同源审计）；上下文投递写一条审计。禁止行为：把结果行数据默认投递；让子执行体代签；用 toast 承载需要决策的错误；把「花费（货币）」写进状态行。

#### 5.3.7 导入导出 `BackupDialog` / `RestoreDialog`

- 对应概设条款：概要设计 §4.8 / §8.4
- 输入：来源（结果集/表/库）、格式、目标路径；内部状态：任务进度与逐项结局

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 任务进行中 | 已写行数与进度 + 取消入口 | 无进度的假进度条 |
| 空数据 | 来源结果集为空 | 「没有可导出的行」+ 引导 | 生成空文件后报成功 |
| 错误 | 格式不支持 / 路径不可写 | 原因 + 保留用户选择 + 重试 | 生成不支持格式的空文件 |
| 权限不足 | 目标目录未授权（Linux 无沙箱，走路径权限） | 明说哪个目录不可写 + 换目录动作 | 静默换到别处写 |
| 提交中 | 写入进行中 | 按钮进行中态 + 禁用二次点击 | 重复点击产生两个同名包 |
| 部分失败 | 部分行/文件失败 | 成功项与失败项分别列出 + 计数 | 整体报成功；失败留半成品不说 |

- 副作用：流式写文件（禁整表进内存）。禁止行为：目标已存在时静默覆盖；导出含凭据或敏感字面量；失败后留下半成品不告知。

#### 5.3.8 笔记面 `NotesView`

- 对应概设条款：概要设计 §15.1 / §19.2（Linux 离线装配）
- 输入：工作区上下文（只传文本与标识）；内部状态：同源笔记视图的列表与编辑态

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | 笔记库打开中 | 列表骨架 + 禁用新建 | 空白页（用户会以为库丢了） |
| 空数据 | 库里确无条目 | 空态文案 + 「新建一条」引导 | 错误件；假条目 |
| 错误 | 库文件损坏 / 打不开 | 「库打不开」+ 原文件保留位置 + 重试 | 静默重建空库覆盖原文件 |
| 权限不足 | 库目录不可读 | 明说目录与所需权限 | 显示成空库 |
| 提交中 | 自动保存进行中 | 保存态指示（不阻塞输入） | 弹模态打断输入 |
| 部分失败 | 附件引用缺失 | 「文件不在了」+ 原文件名 | 画空白框；静默删引用行 |

- 副作用：写只落本机 SQLite（独立数据家）。禁止行为：进程内发起任何网络请求；把笔记数据写进工程数据家；把私密条目带进导出/日志/崩溃报告。

#### 5.3.9 复盘面 `RetroView`

- 对应概设条款：概要设计 §16.1 / §16.2 / §16.10 / §16.18
- 输入：期次与包路径；内部状态（实测名）：`loading`、`reportLoading`、`importing`、`batchImporting`、`query`、`mediaTrouble`、`filtered`

| 状态 | 实现落点 | 必须渲染 | 禁止渲染 |
|---|---|---|---|
| 加载中 | `loading` / `reportLoading` | 期次骨架 + 报告区占位 | 空白周报区冒充「本期无内容」 |
| 空数据 | 该期无包 | 「本期无包」+ 导入引导 | 伪造的期次卡片 |
| 错误 | 包读取失败 / 格式不认 | 原因 + 包名 + 重试 | 静默跳过坏包 |
| 权限不足 | 包目录不可读 | 明说目录与所需权限 | 显示成空列表 |
| 提交中 | `importing` / `batchImporting` | 导入进度 + 禁用二次导入 | 重复导入产生重复期次 |
| 部分失败 | `mediaTrouble` 非空 | 逐条列媒体缺失项 + 计数 | 整体报成功；静默丢媒体 |

- 副作用：只读包与写本地偏好；业务实现待 `retro` 仓 Linux 树。禁止行为：把复盘算法写进本端界面层；宿主向复盘数据家回写；周报直写对方库。

### 5.4 版式语汇与浮层（映射概要设计 §8.11，不重新定义）

> 语汇、层次规则、九个显示开关的**唯一出处 = 概要设计 §8.11**（跨端契约）。本节只做「本端落在哪、判据是什么」，任何一条都不在此重述取值。

| 概要设计 §8.11 条目 | 本端落点 | 判据 |
|---|---|---|
| ① 版式语汇（行首 `>` / 顶格正文 / 工具块 `└─ ▼` / 条目 `├─ ⏺` / 发丝分隔 / 只给要人动手的卡描边） | 同源 `src/shell/ChatPanel.vue` 的消息渲染段 | `UI-5.4-01`（逐条比对，六项全合规） |
| ② 三条硬纪律（一个字号 / 等宽字形替代图标 / 同一条信息只画一次） | 同源 `src/theme/` 令牌 + `ChatPanel.vue` | `UI-5.4-01`；另 `src/theme/theme.test.ts` |
| ③ 骨架三部件（滚动正文 / 输入行永不随滚动 / 状态行分段纯函数 / 块行数分配纯函数） | 同源 `BottomPanel.vue`、`StatusBar.vue`、`src/grid/windowing.ts` | 纯函数单测：`src/grid/windowing.test.ts`、`src/shell/StatusBar.mount.test.ts` |
| ④ 状态行字段序（`就绪/运行中`、模型、已用/窗口、进度条百分比、缓存命中、速率、语音状态；无读数整段不出现） | 同源 `StatusBar.vue` 的分段纯函数 | `UI-5.4-01`；花费（货币）不进状态行 |
| ⑤ 九个显示开关（流式输出 / 紧凑模式 / 显示思考段 / 时间戳 / 工具进度 / 状态指示字形 / 长消息预览 / 运行底栏元数据 / 运行中提交） | 同源 `src/shell/appearance.ts` + `agentSettings.ts` | 键名、默认值、取值域三样与概要设计 §8.11 表逐字一致；`src/shell/appearance.test.ts` |
| ⑥ 主题与皮肤（按角色组织、明暗独立求值、只写覆盖项、不开放外部样式注入、品牌文案只从语言表取） | 同源 `src/theme/` + `src/i18n/`；本端只跟随系统明暗 | `src/theme/theme.test.ts`、`src/i18n/index.test.ts`；本端不新增主题文件 |

浮层三类（本端落点，衬底取值仍按概要设计 §8.11 的层次规则，不在此重述不透明度）：

| 类型 | 用在哪（本端） | 落点 |
|---|---|---|
| 浮层（paper） | 期次浮层、行内悬停菜单 | 同源浮层组件挂覆盖层，不进布局流 |
| 面板（panel） | 结果面板、审批卡 | `DatabaseView.vue` 结果区、`ChatPanel.vue` 审批卡 |
| 对话框（sheet / dialog） | 连接表单、导入导出、设置 | `ConnectionDialog.vue`、`BackupDialog.vue`、`RestoreDialog.vue`、`AgentSettingsDialog.vue` |

**四条硬纪律（本端执行口径）**：压住内容的层必须不透明；不透明不等于纯色黑（取值按概要设计 §8.11 与主题值表）；浮层不参与布局；入口悬停浮出且同一条动作只画一次。图标按钮只许出现在主界面（活动栏 / 工具条 / 行内悬停），对话框与表单一律用文字按钮。

---
### 5.5 状态与数据流

- 单一数据源：页签、结果集、连接态、审批单都在同源装配层持有；本端不持有任何界面可写副本。本端自有的可写状态只有两处：环境变量派生的数据家路径（只读算出）与 §3.21 的密钥环条目。
- 单向派生：行数、耗时、可编辑判定、能力取值一律由装配层/探测层算一次后下发；视图只读，不重算、不双写。
- 刷新路径：能力层事件 → 装配层折叠值 → 界面线程更新；本端不注册轮询定时器（`rg -n 'setInterval|setTimeout' Platform/linux/src-tauri/src` 为空）。
- 缓存失效：对象树按「连接 + 库」缓存，连接断开或结构变更成功后整体失效；能力取值**不缓存**（缓存会导致「装好前置仍报缺」）。
- 跨页签共享：同一「连接 + 库」共享一个服务实例（同源 `ensureService` 语义），本端不得为页签各建一条连接。
- 派生纯函数：状态行分段、块行数分配、能力取值串都是纯函数（给定输入唯一输出），必须单测；带副作用的派生一律判红。

### 5.6 事件绑定与动作映射

| 界面动作 | 事件处理器（同源） | 调用接口 | 成功行为 | 失败行为 | 禁止行为 |
|---|---|---|---|---|---|
| 点执行 | 查询页签执行入口 | 同源执行面（概要设计 §4.3） | 逐条上报 + 结果区渲染 + 写归档 | 错误件 + 保留 SQL | 失败后清空编辑器 |
| 点停止 | 工具栏停止入口 | 同源取消面（概要设计 §4.4） | 状态「已取消」+ 连接仍可用 | 明说服务端拒绝原话 | 只改界面状态 |
| 保存连接 | 表单提交 | 同源连接清单 + 本端 §3.21 写凭据 | 清单刷新 + 选中保持 | 字段级错误；凭据失败明说残留 | 静默丢配置；先删后写 |
| 删除连接 | 清单删除项 | 本端 §3.21 `delete` + 同源清单删除 | 条目消失 + 清理项清单 | `CRED_PURGE_FAILED` + 残留位置 | 无确认删除；留凭据 |
| 展开节点 | 对象树展开 | 同源元数据（概要设计 §4.5） | 渲染下一层 | 节点级错误 + 重试 | 显示空树冒充无对象 |
| 行写回 | 结果区编辑提交 | 同源行写回（概要设计 §4.6） | 逐行结局 | 冲突行明示 + 保留输入 | 影响 0 行当成功 |
| 生成脚本 | 表设计入口 | 同源结构变更（概要设计 §4.7） | 展示脚本 + 待确认 | 明说缺什么 | 直接执行 DDL |
| 导出 | 结果区导出入口 | 同源导出（概要设计 §4.8） | 进度 + 完成 + 文件大小 | 部分成功列明细 | 失败留半成品不说 |
| 终止会话 | 会话视图终止项 | 同源会话面（概要设计 §4.9） | 结局 + 刷新列表 | 权限原话 | 无确认终止 |
| 投递上下文 | 对话页签投递 | 同源助理桥（概要设计 §4.10） | 摘要可核对 | 拒绝并说明需确认 | 静默投递行数据 |
| 查能力表 | `doyah-studio-cli capabilities` | 本端 §3.17 | 表 / JSON + 退出码 0 | 缺项 + 退出码 2 | 缺项返回 0 |
| 起壳 | 进程启动 | 本端 §3.2 | 进入事件循环 | 指引 + 退出码 1 | 白屏启动 |

- 通用禁令：不可逆操作（删连接、删表、清表、终止会话、高危写）必须先二次确认并说明后果；需要用户决策的错误不得用 toast 承载；未授权入口不出现（不是灰掉）；失败一律保留用户输入。

### 5.7 表单校验与导航权限落点

| 表单/字段 | 前端校验（同源） | 后端校验 | 错误定位位置 | 禁止行为 |
|---|---|---|---|---|
| 连接名称 | 非空、同工作区唯一 | 同左 | 字段下方 | 仅前端校验 |
| 主机 | 非空 | 同左 | 字段下方 | 前端拼连接串 |
| 端口 | 整数，先解析再校验 1–65535 | 同左 | 字段下方 | 越界静默夹取 |
| 用户名 | 非空 | 非空 | 字段下方 | 空口令尝试连接 |
| 凭据 | 密钥环可用性先判（本端 §3.6 取值） | 由 §3.21 落库 | 字段下方 | 无密钥环仍允许保存 |
| SQL 文本 | 非空 | 非空 + 目标库一致 | 编辑器下方错误件 + 消息面 | 空执行静默通过 |
| 导出格式 | 取值为支持集合 | 同左 | 字段下方 | 生成不支持格式的空文件 |
| 导入目标 | 目标存在必须询问 | 同左 | 顶部汇总 + 字段 | 静默覆盖既有表 |

| 起点 | 触发 | 终点 | 前置条件 | 禁止行为 |
|---|---|---|---|---|
| 活动栏 | 点「数据库」 | 查询页签 | 有可用连接（无连接先给建连引导） | 直接报错 |
| 对象树节点 | 双击表 | 新查询页签（浏览前 N 行） | 连接已就绪 | 未连接时打开空页签 |
| 查询页签 | 执行成功 | 同页签结果区 | 至少一条语句完成 | 自动跳到别的页签 |
| 会话视图 | 终止会话 | 同视图 | 已二次确认 | 未确认离开 |
| 对话页签 | 点写操作卡片 | 审批卡 | 该动作需审批 | 越过审批直接执行 |
| 活动栏 | 点「笔记」/「复盘」 | 笔记面 / 复盘面 | 有能力位（未授权则入口不存在） | 先渲染再报错 |

- 路由守卫落点：入口可见性只有一处判据（同源 `activityBarStore.ts` + 命令目录）；本端不得再判一次，也不得按平台分支隐藏入口。
- 未授权处理：入口不渲染；到期只降级入口，数据可开可导出（禁锁死用户数据）。
- 可访问性落点：每个视图的主动作有键盘路径；容器、按钮、输入框、状态提示带可读名称；空 / 加载 / 错误三态有文字表述；同一动作的文案、图标、快捷键、禁用条件只在同源命令目录定义一次。
- 禁止：新增未列出的路由或入口；未确认离开导致未保存内容丢失；同一入口在两处各判权限；占用系统级快捷键。

### 5.8 界面测试契约

| 用例 ID | 类型 | 覆盖条款 | Given | When | Then |
|---|---|---|---|---|---|
| `UI-5.1-01` | 路由清单 | 概要设计 §8.1 / §8.2 | 同源命令目录与本文件 §5.1 视图清单 | 遍历所有可打开入口 | 差集 0：无清单外入口，无清单内缺失入口 |
| `UI-5.1-02` | 职责与禁止呈现 | 概要设计 §8.2 | 八类视图各打开一次 | 逐视图核对呈现项 | 口令 / 连接串原文 / 未授权入口出现 0 次 |
| `UI-5.2-01` | 承载骨架 | 概要设计 第四章平台差异表 | 1280×800 与 960×600 两档窗口 | 缩放并折叠侧栏 | 壁纸只铺一次；三栏比例不崩；最小尺寸生效 |
| `UI-5.3-01` | 六态总表 | 概要设计 §8.4 | 九个组件各造六态夹具 | 逐态渲染 | 六态齐；九张表的「禁止渲染」列逐行为空 |
| `UI-5.3.1-01` | 启动前置面 | 概要设计 第四章平台差异表 / §8.2 | 缺 `webkit2gtk-4.1` 的宿主 | 起壳 | stderr 含补救指引；退出码 1；无窗口出现 |
| `UI-5.3.2-01` | 平台能力面 | 概要设计 §11.4 | 六项探测一在五缺 | 跑 `capabilities` 与 `--json` | 六行齐、指引非空、退出码 2；`unknown` 不计入缺项 |
| `UI-5.3.3-01` | 查询页签六态 | 概要设计 §4.6 / §8.4 | 六态夹具（含无主键结果集） | 逐态渲染 | 无主键时行编辑入口不出现；0 行写回报冲突 |
| `UI-5.3.3-02` | DDL 预览闸 | 概要设计 §4.7 / §7.2 | 已生成脚本未预览 | 点执行 | 被拒并展示脚本；服务端未收语句 |
| `UI-5.3.4-01` | 连接表单六态 | 概要设计 §4.1 / §8.6 | 六态夹具（含无密钥环） | 逐态渲染 | 无密钥环时保存禁用且给装包指引；校验未过零请求 |
| `UI-5.3.5-01` | 对象树六态 | 概要设计 §4.5 / §8.4 | 已展开并选中的树 | 刷新 | 选中不变；无伪造占位节点；空层显示「(空)」 |
| `UI-5.3.6-01` | 审批六态 | 概要设计 §5.4 / §6.3 / §18.6 | 待审 / 已拒 / 已过期 / 无记录四夹具 | 逐态渲染与批准 | 已拒与已过期不可批准；预估缺失显示「未接」 |
| `UI-5.3.6-02` | 上下文投递 | 概要设计 §4.10 | 含结果行数据的上下文 | 未确认投递 | 被拒并说明需确认；审计 0 条 |
| `UI-5.3.7-01` | 导入导出六态 | 概要设计 §4.8 / §8.4 | 目标已存在 / 部分行失败 | 导入导出 | 先询问；成功与失败项分别列出 |
| `UI-5.3.8-01` | 笔记面六态 | 概要设计 §15.1 / §19.2 | 离线宿主 + 六态夹具 | 逐态渲染并断网捕获 | 断网可记且状态为「待同步」；零网络出口 |
| `UI-5.3.9-01` | 复盘面六态 | 概要设计 §16.1 / §16.18 | 缺包 / 坏包 / 媒体缺失三夹具 | 逐态渲染 | 坏包被标出不被跳过；媒体缺失逐条列出 |
| `UI-5.4-01` | 版式语汇 | 概要设计 §8.11 | 一屏真实对话（含工具块与状态行）+ 聊浮层 | 逐条比对本节 §5.4 六行 | 行首栏字形 / 唯一字号 / 状态行字段序 / 无通栏卡片 / 无货币金额 五项全合规 |
| `UI-5.5-01` | 状态与数据流 | 概要设计 §7.1 | 同连接两个页签并发操作 | 同时执行并改能力前置 | 无轮询；派生值只算一次；能力取值不缓存 |
| `UI-5.6-01` | 交互规则 | 概要设计 §8.5 | 五类不可逆动作 | 逐个触发 | 每次都先确认并说明后果；需决策错误不走 toast |
| `UI-5.6-02` | 动作映射 | 概要设计 §8.7 / §7.2 | 十二行动作表 | 逐行制造失败 | 失败保留用户输入，无一条冒充成功 |
| `UI-5.7-01` | 表单校验 | 概要设计 §8.6 | 八行字段表 | 逐字段注入非法值 | 错误定位到字段；端口越界不夹取 |
| `UI-5.7-02` | 导航 | 概要设计 §8.3 | 六条允许流转 + 三条非法跳转 | 逐条触发 | 非法跳转被拒并给理由 |
| `UI-5.7-03` | 可访问性 | 概要设计 §8.9 | 两档明暗 × 各视图 | 纯键盘 + 读屏走一遍 | 焦点可见；三态有文字；快捷键只在命令目录一处 |
| `UI-5.8-01` | 覆盖率 | 概要设计 §8.10 | 本表与 §0.1 矩阵的 UI 行 | 双向比对 | 矩阵每个 UI 行在本表有用例；本表无用例游离 |

测试禁止行为：禁止跳过用例 / 只跑一个 / `sleep` 等待 / 依赖真实网络与真实库 / 改动断言适配实现。界面用例的执行形态分两类：同源面已有 `*.mount.test.ts` 的组件跑同源用例（`ChatPanel.mount.test.ts`、`DatabaseView.mount.test.ts`、`BackupDialog.mount.test.ts`、`RestoreDialog.mount.test.ts`、`StatusBar.mount.test.ts` 等），本端独有面与承载面（`UI-5.2-01`、`UI-5.3.1-01`、`UI-5.3.2-01`）在 Linux 宿主上人工点验并留记录。

---
## 6. 错误映射与日志

### 6.1 错误码映射（概要设计 §9 的 21 码 → 本端落点）

| 概设错误码 | 本端落点 | 状态 |
|---|---|---|
| `CONN_INVALID_CONFIG` | 同源连接表单校验（`connectionDialog` 字段错误） | 已实现（同源） |
| `CONN_NO_CREDENTIAL` | 本端 §3.21 `StoreError::NoKeyring` → 表单「无密钥环」提示 | 契约已立，实现未跟（§10.1 第 2 项） |
| `CONN_UNREACHABLE` | 同源连接失败分类 | 已实现（同源） |
| `CONN_AUTH_FAILED` | 同源连接失败分类 | 已实现（同源） |
| `CONN_NOT_FOUND` | 同源清单查找（按「未连接」呈现） | 已实现（同源） |
| `CRED_PURGE_FAILED` | 本端 §3.21 `delete` 失败 + 残留位置上浮 | 契约已立，实现未跟（§10.1 第 2 项） |
| `EXEC_EMPTY_SQL` | 同源执行前校验 | 已实现（同源） |
| `EXEC_NO_CONNECTION` | 同源执行前校验 | 已实现（同源） |
| `EXEC_READONLY_DENIED` | 同源只读判定 → `UI-5.3.3-01` 的权限不足态 | 已实现（同源） |
| `EXEC_CONFIRM_REQUIRED` | 同源高危判定 → 二次确认 | 已实现（同源） |
| `EXEC_SERVER_ERROR` | 同源错误件（含序号与原文） | 已实现（同源） |
| `EXEC_CONNECTION_LOST` | 同源执行失败事件 | 已实现（同源） |
| `EXEC_CANCEL_ILLEGAL` | 同源取消结局 | 已实现（同源） |
| `META_UNSUPPORTED` | 同源层级差异说明 → 对象树节点级错误 | 已实现（同源） |
| `DATA_NO_PK` | 同源行写回前置（无主键即不开放入口） | 已实现（同源） |
| `DATA_WRITE_CONFLICT` | 同源行写回逐行结局 | 已实现（同源） |
| `DDL_PREVIEW_REQUIRED` | 同源结构脚本预览闸 → `UI-5.3.3-02` | 已实现（同源） |
| `IO_TARGET_EXISTS` | 同源导入目标询问 | 已实现（同源） |
| `IO_PARTIAL` | 同源导入逐批结局 → `UI-5.3.7-01` | 已实现（同源） |
| `SESS_KILL_DENIED` | 同源会话动作路径（原话上浮） | 已实现（同源） |
| `LIC_NO_CAPABILITY` | 入口可见性（未授权即不出现） | 已实现（同源） |

- 概要设计 §4.x 另有 10 个接口级码不在 §9 的 21 码清单内：`EXEC_CANCEL_FAILED`、`META_FAILED`、`DATA_WRITE_FAILED`、`DDL_CONFIRM_REQUIRED`、`DDL_FAILED`、`IO_FORMAT_UNSUPPORTED`、`SESS_NOT_FOUND`、`SESS_KILL_REQUIRED_CONFIRM`、`BRIDGE_ROW_DATA_REQUIRES_CONFIRM`、`BRIDGE_EMPTY_CONTEXT`。这 10 个码由同源面逐条落在各自错误契约里，本端不另立映射表，只承接呈现。
- 本端独有的错误面（不在 21 码内、不新增错误码）：`IdentityError` 四变体（§3.14）、`StoreError` 三变体（§3.21）、五档退出码（§3.20 / §3.16 / §3.2）。它们用返回值表达，不映射为业务错误码。
- 呈现规则：字段级错误呈现在字段附近；页面级错误呈现在结果区或页面顶部并带重试入口；服务器错误保留原文（可复制）并附语句序号与目标库；不可恢复错误阻断当前动作并给下一步。启动期与构建期错误不呈现为界面元素（无窗口），一律 stderr + 退出码（见 §6.4）。

### 6.2 四条禁止兜底在本端的实现级禁令

| 概设禁令（概要设计 §9） | 本端落点 | 判据 |
|---|---|---|
| 禁止返回空对象冒充成功 | `startup_report` 的 `webview_ready` 只在真探测到 `present` 时为真；`missing` 只在真无缺项时为空 | `T-6.2-01` 反例：探测读盘失败 ⇒ 报 `missing`，不得报 `webview_ready = true` |
| 禁止用默认值掩盖缺失 | 缺前置即 `missing`（不填默认路径、不填默认版本）；身份四项缺项即拒收；退出码不许用 0 兜 | `T-3.14-02`、`T-3.20-02` |
| 禁止捕获异常后不记录、不返回、不处理 | 每个 `Result` 分支必须「记 + 返」之一；`unwrap()` / `expect()` 只允许出现在单测与启动入口的 `generate_context!()` 一处 | 两次检索 `rg -n 'unwrap\('` 与 `rg -n 'expect\('`（范围 `Platform/linux/src-tauri`）逐条人工核 |
| 禁止把依赖失败降级为业务成功 | 无密钥环即报错（不落明文、不空口令连接）；探测读不到目录报 `missing` 并给指引 | `T-3.21-02`、`T-3.6-01` |

- 追加一条本端专有：**禁止把「未知」降级为「缺失」或「存在」**。`Availability::Unknown` 的唯一合法去向是「如实渲染为 unknown」，任何把它折叠成 `Present` / `Missing` 的分支都判红（`T-4.4-05`）。

### 6.3 日志字段

- 必记（按动作）：错误码或错误变体、连接标识（不记口令）、能力项名与取值、构建宿主 `uname`、退出码、耗时、结局。
- 禁记：口令、凭据引用原文、完整连接串、结果行数据、环境变量原值（`DBUS_SESSION_BUS_ADDRESS` / `HOME` 等）、用户家目录绝对路径。
- 落点：本端只往 **stderr** 与同源审计账本（`agent-audit.json`，追加式）两处写；本端不新建日志文件、不新建日志目录（避免第二套真源）。
- 写入失败不得吞掉：stderr 写失败时记计数并以退出码反映（构建入口路径）；审计写失败按「记录未落盘」上报，不回滚业务。
- 判据：`rg -n 'password|secret|passwd' Platform/linux/src-tauri/{Core,Platform,Cli}` 的命中只允许出现在类型名与提示文案里，不得出现在格式化输出语句中。

### 6.4 启动期与构建期错误（本端独有）

| 场景 | 呈现形态 | 退出码 | 可重试 | 禁止行为 |
|---|---|---|---|---|
| 缺 `webkit2gtk-4.1` | stderr 逐条 `guidance` + 「装好前置后重试」 | 1 | 是 | 白屏起窗口；静默降级成「无 WebView 模式」 |
| 同源命令层挂载失败 | stderr `tauri::Error` 原文 | 1 | 是（重跑 1 次） | 吞掉错误继续跑 |
| 依赖缺项（构建探测） | 逐项 `MISS` + 一行 apt 参考 | 1 | 是 | 缺项报 0 |
| 非 Linux 宿主 | 「如实拒绝构建」+ 指向对侧入口 | 2 | 否 | 在本机假装构建成功 |
| 应用骨架未落地 | 「应用骨架未落地」+ 指向 README | 3 | 是 | 当成脚本自身故障 |
| 同源前端缺失 / 未知参数 | 「前端同源前提不成立」/ 未知参数 + 用法 | 4 | 是 | 另存一份前端顶上 |
| CLI 用法错 | stderr 原因 + 用法 | 1 | 是 | 错误混进 stdout |
| CLI 有缺项 | stderr 逐项点名 | 2 | 是 | 报成「跑失败」（那是 1） |

- 判据：`T-6.4-01`（缺承载面 ⇒ 退出码 1 且 stderr 含包名）；`T-4.4-06`（退出码闭集，不出现第六个码）。

---

## 7. 并发与线程模型

### 7.1 并发模型与共享可变状态

| 约束 | 本端落法 |
|---|---|
| 界面状态只在界面线程改 | 同源装配层负责；本端不注册回调、不改 DOM |
| 起壳前探测不做并发 | `probe_all` 同步串行六项（每项只读几个路径，并发无收益且会打乱顺序契约） |
| 同一连接上的语句串行 | 同源执行面内部串行；本端不插入并发、不加线程池 |
| 凭据写入串行 | §3.21 后端调用串行，同一时刻只打一个 Secret Service 请求 |
| 构建入口单实例 | 同一 `target/` 目录不做并发保护，由 `cargo` 自身报错 |
| 禁止 | 事务中发外部网络调用；锁内慢操作；无界并发；在本端起常驻线程或定时器 |

### 7.2 事务边界与幂等

- 事务边界：一次业务动作一个事务（同源面）；本端无数据库事务，只有两处原子动作 —— 密钥环条目的写/删、构建产物的写。
- 幂等键：连接建立 = 连接标识；凭据 = 连接标识；取消 = 执行句柄；行写回 = 主键；审批 = 指纹；导入 = 目标表 + 批次序号（同源面）。
- 归档与审计属动作后置：失败只报「记录未落盘」，不回滚业务；写入原子（JSONL 追加 + 换行）。
- 探测幂等：六项探测可在任意时刻重复跑，结论只随宿主状态变化（不随时间、不随调用次数变化）。
- 禁止：事务进行中切换连接或目标库；把取消写进成功分支；对写语句自动重试；为「看起来快」把探测结果缓存起来。

---

## 8. 安全

### 8.1 鉴权与凭据落点

- 鉴权落点：能力层与驱动层判定（只读、能力位）；本端只呈现结果，**禁止**在前端或承载层做权限判断（概要设计 §8.5 禁止项）。
- 凭据：只经 §3.21 的 `SecretStore` 取用（Secret Service）；无密钥环即报错，**不回落明文**。口令不进日志、不进模型上下文、不进导出包、不进错误信息。
- 删除连接：先清凭据再删清单；清失败报 `CRED_PURGE_FAILED` 并明说残留位置。
- 到期与授权：能力位解析离线可校验，入口可见性只在同源一处判定；到期只降级入口，数据可开可导出（禁锁死用户数据）。
- 文件权限：数据家目录与笔记库按用户私有权限创建（0700 / 0600）；本端不主张更宽的权限。

### 8.2 输入校验与注入防护

- 输入校验位置：能力取值只经 `Availability::parse`（三档闭集）；身份四项只经 `ArtifactIdentity::new`（四项全校验）；CLI 参数白名单（子命令 + `--json`）。
- 注入防护：本端不拼 SQL、不起 shell 拼接命令；`build.sh` 的变量一律引用加引号，不 `eval`；Tauri 侧 CSP 固定为 `default-src 'self'`，`connect-src` 只许 `ipc:` 与 `http://ipc.localhost`。
- 页面不得触达客户端能力：能力集逐项登记（`capabilities/default.json` 只给 `core:default` 与 `dialog:default`），不给文件系统、shell、任意路径读写权限。
- 环境变量一律不可信：`SHELL` 只认绝对路径且在盘上；`DISPLAY` / `WAYLAND_DISPLAY` 只当存在性判据；`XDG_DATA_HOME` 只当路径前缀且不接受 `..` 段。
- 错误信息不泄露堆栈、连接串、凭据引用；构建失败打印 `cargo` / `tauri` 原话但不打印环境变量。

### 8.3 零外发与数据边界

- 外发面闭集：数据库连接（用户配置）、模型调用（用户配置）、已授权同步（笔记/授权判定）。除此三面，本端进程**零外发**：`probe_*` 不发网络、不起下载、不查更新。
- 判据：`rg -n 'reqwest|hyper|ureq|curl|wget' Platform/linux/src-tauri/{Core,Platform,Cli}` 为空；`rg -n 'http://|https://' Platform/linux/src-tauri` 只允许命中 `tauri.conf.json` 的 `$schema` / `devUrl` / `csp` 三处与 `gen/` 下的生成物。
- 结果行数据投递需显式确认并留痕（同源助理桥）；本端不得在日志、身份卡、错误信息里携带结果行数据。
- 私密条目（笔记）与凭据在**任何出口**排除：导出、审计、崩溃报告、模型上下文、构建产物身份卡。
- 本端不引常驻后台服务、不引消息队列、不引代理（概要设计 §11 依赖清单禁止项）。

---
## 9. 判据与测试

### 9.1 测试文件与组织

| 测试文件 | 被测单元 | 类型 | 必须覆盖的条款 |
|---|---|---|---|
| `Platform/linux/src-tauri/Core/src/capability.rs`（内联 `cfg(test)` 测试模块） | `Availability::parse` / `as_str`、`CAPABILITY_NAMES` | 单元 | §3.12、§3.13、§4.4（三档闭集） |
| `Platform/linux/src-tauri/Core/src/artifact.rs`（内联） | `ArtifactIdentity::new` / `identity_card` | 单元 | §3.14、§3.15 |
| `Platform/linux/src-tauri/Platform/Linux/src/lib.rs`（内联） | 六项 `probe_*`、`probe_all`、`missing` | 单元 | §3.4–§3.11 |
| `Platform/linux/src-tauri/Platform/Linux/src/secret_store.rs`（新增，内联） | `SecretStore` 三方法 | 单元（替身后端） | §3.21 |
| `Platform/linux/src-tauri/src/lib.rs`（内联） | `capabilities`、`startup_report` | 单元 | §3.1、§3.3 |
| `Platform/linux/src-tauri/Cli/src/main.rs` | `main` 分派与 `report_capabilities` | 契约（进程级） | §3.16、§3.17 |
| `Platform/linux/Tools/check-linux-skeleton.py` | 骨架 / 领域层边界 / 前端同源 / 构建入口 | 静态判据 | §2.3、§1.3 |
| `Platform/linux/build.sh` | 五档退出码与身份四项 | 入口判据 | §3.20 |
| `Platform/windows/App/src/**/*.mount.test.ts`（同源） | 界面六态与动作映射 | 组件（同源） | §5.3、§5.6、§5.8 |

### 9.2 必测用例清单（后端与本端入口）

| 用例 ID | 对应概设条款 | 对应详设契约 | Given | When | Then |
|---|---|---|---|---|---|
| `T-2.1-01` | 概要设计 §1.4 | §2.1 能力面清单 | 本端能力面清单与 §1.4 矩阵 | 逐格比对 | Linux 列五项（Studio/Notes/Retro/Agent/授权）都有落点或登记，无「本端不做」 |
| `T-2.1-02` | 概要设计 §3 | §2.1 禁令 | 全端源码 | 检索本端是否复制命令层 | `Platform/linux` 内无 `invoke_handler`、无数据库驱动依赖、无方言关键字 |
| `T-2.2-01` | 概要设计 §11.4 | §2.2 注入点 | 临时 `XDG_DATA_HOME` + 替身后端 | 跑 §3.18、§3.21 用例 | 全部可用替身驱动，不改生产代码 |
| `T-2.3-01` | 概要设计 §1.3 | §2.3 目录与命名 | 全端源码与 `Cargo.toml` | 跑骨架判据 A–E | rc=0；`Core` 第三方依赖 0 条；无 `App/`、`dist/` |
| `T-3.1-01` | 概要设计 第四章平台差异表 | §3.1 后置 | 任一宿主 | 调 `startup_report()` | `missing` 与 `guidance` 等长同序，`webview_ready` 与 `webview` 项取值一致 |
| `T-3.1-02` | 概要设计 第四章平台差异表 | §3.1 错误表 | 缺 `webkit2gtk-4.1` 的宿主 | 调 `run()` | 退出码 1；stderr 含包名与装包命令；未进入事件循环 |
| `T-3.2-01` | 概要设计 第四章平台差异表 | §3.2 错误表 | 缺承载面 | 起壳 | 退出码 1 且无窗口；提示逐条可照做 |
| `T-3.2-02` | 概要设计 §3 | §3.2 禁止行为 | 本端 `src-tauri/src` | 检索 `.plugin(` 与 `invoke_handler` | 非注释行命中 0 处（挂载只在同源 `attach`；注释里的说明不计） |
| `T-3.3-01` | 概要设计 §11.4 | §3.3 后置 | 任一宿主 | 调 `capabilities()` | 长度 6、顺序 = 冻结表、每项取值只许三档 |
| `T-3.4-01` | 概要设计 第四章平台差异表 | §3.4 后置 | 任一宿主 | 调 `probe_all()` | 六项顺序 = `CAPABILITY_NAMES`，每项 `guidance` 非空 |
| `T-3.5-01` | 概要设计 第四章平台差异表 | §3.5 后置 | 非 Linux 宿主（无 WebKitGTK） | 调 `probe_webview()` | 返回 `missing`（不假绿），带装包指引 |
| `T-3.6-01` | 概要设计 第四章平台差异表 | §3.6 后置 | 清空 `DBUS_SESSION_BUS_ADDRESS` | 调 `probe_secret_service()` | 返回 `missing`，指引含「不回落明文」 |
| `T-3.7-01` | 概要设计 第四章平台差异表 | §3.7 后置 | `SHELL` 指向不存在的路径 | 调 `probe_pty()` | 兜底 `/bin/sh` ⇒ `present`，指引写明走了兜底 |
| `T-3.8-01` | 概要设计 第四章平台差异表 | §3.8 后置 | 无通知服务文件 | 调 `probe_notifications()` | 返回 `missing`，指引含「如实降级并说明」 |
| `T-3.9-01` | 概要设计 第四章平台差异表 | §3.9 后置 | 无 `DISPLAY` / `WAYLAND_DISPLAY` | 调 `probe_clipboard()` | 返回 `unknown`；`missing()` 不把它计入缺项 |
| `T-3.10-01` | 概要设计 第四章平台差异表 | §3.10 后置 | 无 `libayatana-appindicator3` | 调 `probe_tray()` | 返回 `missing`；`startup_report().webview_ready` 不受影响 |
| `T-3.11-01` | 概要设计 第四章平台差异表 | §3.11 后置 | present / missing / unknown 各一项 | 调 `missing()` | 只返回 `missing` 那一项，顺序不变 |
| `T-3.12-01` | 概要设计 §11.4 | §3.12 后置 | 取值串 `present` / ` MISSING ` / `Unknown` / `yes` / 空串 | 调 `parse` | 前三者对应三档，后两者 ⇒ `Unknown` |
| `T-3.13-01` | 概要设计 §11.4 | §3.13 后置 | 三档各一 | `as_str` 后再 `parse` | 往返一致，取值串全小写 |
| `T-3.14-01` | 概要设计 §12 | §3.14 后置 | 四项齐 + 大写哈希 | 调 `ArtifactIdentity::new` | 收下且 `sha256` 归一为小写 64 位 |
| `T-3.14-02` | 概要设计 §12 | §3.14 错误表 | 逐项置空 / 哈希截断 / 哈希含非十六进制 | 调 `new` | 返回对应 `IdentityError` 变体，不产生结构体 |
| `T-3.15-01` | 概要设计 §12 | §3.15 后置 | 一份合法身份 | 调 `identity_card()` | 恰四行、键名固定、与 `build.sh` 收尾格式逐字节同款 |
| `T-3.16-01` | 概要设计 §19.1 | §3.16 后置 | 宿主缺若干前置 | 跑 `capabilities` | 退出码 2；stderr 逐项点名；`unknown` 不计入 |
| `T-3.16-02` | 概要设计 §19.1 | §3.16 错误表 | 子命令 `nope` | 跑 CLI | 退出码 1；stderr 含用法；stdout 为空 |
| `T-3.17-01` | 概要设计 §19.1 | §3.17 后置 | 含引号与换行的 `guidance` 场景 | 跑 `capabilities --json` | 输出可被 JSON 解析，三字段齐，转义正确 |
| `T-3.18-01` | 概要设计 第四章平台差异表 | §3.18 后置 | 三档环境（设 XDG / 只设 HOME / 都不设） | 调 `app_home()` | 分别得 XDG 档、HOME 档、当前目录档，不 panic |
| `T-3.18-02` | 概要设计 第四章平台差异表 | §3.18 禁止行为 | 本端源码 | 检索路径拼接 | `Platform/linux` 内除注释外无第二处 `doyah-studio` 路径拼接 |
| `T-3.19-01` | 概要设计 §3 | §3.19 后置 | 本端 `src-tauri/src` | 检索挂载点 | 只有一处调 `doyah_studio_shell::attach`，无第二个 `invoke_handler` |
| `T-3.20-01` | 概要设计 §12 | §3.20 后置 | Linux 宿主 + 依赖齐 | 跑 `build.sh` | 退出码 0；打印四行身份；`bundle/` 下有 deb 或 AppImage |
| `T-3.20-02` | 概要设计 第四章平台差异表 | §3.20 错误表 | 非 Linux 宿主 | 跑 `build.sh` | 退出码 2；打印「如实拒绝构建」与对侧入口 |
| `T-3.20-03` | 概要设计 第四章平台差异表 | §3.20 错误表 | 临时挪走同源 `package.json` | 跑 `build.sh` | 退出码 4；打印「前端同源前提不成立」 |
| `T-3.20-04` | 概要设计 第四章平台差异表 | §3.20 错误表 | 缺 `webkit2gtk-4.1` / `gtk+-3.0` | 跑 `build.sh --deps` | 退出码 1；逐项 `MISS` + apt 参考命令 |
| `T-3.21-01` | 概要设计 第四章平台差异表 | §3.21 后置 | 替身后端（内存） | `set` → `get` → `delete` → `get` | 第一次取回相同；删除后为 `None`；重复删不报错 |
| `T-3.21-02` | 概要设计 第四章平台差异表 | §3.21 错误表 | 无密钥环 | 调 `set` | 返回 `Err(NoKeyring)`；盘上无明文副本 |
| `T-4.1-01` | 概要设计 §5.1 | §4.1 序列化契约 | 一份能力 DTO 与一份启动报告 | 序列化再反序列化 | 字段名一致、取值串三档、空集合写 `[]` |
| `T-4.1-02` | 概要设计 §5.1 | §4.1 禁止行为 | 一份连接配置 | 检索可序列化分支 | 结构里无口令字段，无凭据原文 |
| `T-4.2-01` | 概要设计 第四章平台差异表 | §4.2 存储契约 | 三档环境 | 写一条配置后读回 | 落在 XDG 档；文件权限用户私有；损坏文件被保留 |
| `T-4.2-02` | 概要设计 §5.2 | §4.2 存储契约 | 同一 SQL 执行两次 | 读归档 | 一条记录、重复次数 2；归档失败不回滚业务 |
| `T-4.2-03` | 概要设计 §5.3 | §4.2 存储契约 | 任务定义（只读 + 行数上限） | 执行时参数与定义不一致 | 拒绝执行；上限越界拒绝 |
| `T-4.3-01` | 概要设计 §7.1 | §4.3 伪代码 | 两段 SQL + 一段选区 | 执行 | 有选区只跑选区；按文本顺序逐条上报；结果集全保留 |
| `T-4.5-01` | 概要设计 §15.1 / §19.2 | §4.5 离线装配 | 断网、无账号 | 捕获一条笔记 | 可保存可读；状态「待同步」非「失败」；零网络出口 |
| `T-4.5-02` | 概要设计 §15.2 | §4.5 附件 | 一条带附件的笔记 | 查库体积与引用 | 库内只有引用；字节在盘；同内容只一份 |
| `T-4.5-03` | 概要设计 §15.6 | §4.5 私密 | 一条私密条目 | 导出 / 查日志 / 查崩溃报告 | 三处均不含该条目任何字段 |
| `T-4.5-04` | 概要设计 §15.7 | §4.5 检索 | 中文查询 2 字与 5 字各一 | 检索 | 覆盖标题/正文/标签；2 字走子串兜底并标注；没跑成不等于没找到 |
| `T-4.5-05` | 概要设计 §15.9 | §4.5 回收站 | 删除一条笔记 | 看回收站与彻底清除 | 进回收站；彻底清除需二次确认 |
| `T-4.6-01` | 概要设计 §16.1 | §4.6 宿主 | 复盘插件槽位 | 挂载插件，缺一期数据 | 槽位可挂；缺期如实显示，不伪造 |
| `T-4.6-02` | 概要设计 §16.2 | §4.6 宿主 | 插件装配清单 | 装载复盘插件 | 单向上下文可传；插件不反向依赖装配层 |
| `T-4.6-03` | 概要设计 §16.10 | §4.6 宿主 | 一份复盘稿 | 打开 | 只读呈现；本端不写复盘数据家 |
| `T-4.6-04` | 概要设计 §16.18 | §4.6 宿主 | 一期周报包 | 打开与投递入口 | 只走交换面；不直写对方库 |
| `T-4.7-01` | 概要设计 §3 | §4.7 继承边界 | 本端源码 | 检索命令层复制 | 无复制；只调 `attach` 与 `app_home` |
| `T-4.7-02` | 概要设计 §3 | §4.7 继承边界 | Agent 四组件的落点 | 检索本端实现 | 本端无命令执行/代码执行/工具目录/并行编排实现文件 |
| `T-4.7-03` | 概要设计 §4.3 | §4.7 继承边界 | 三语句批 | 执行 | 逐条顺序；多结果集全保留；本端未插入并发 |
| `T-4.7-04` | 概要设计 §4.4 | §4.7 继承边界 | 执行中句柄 | 重复取消 | 同一结局；连接仍可用 |
| `T-4.7-05` | 概要设计 §4.9 | §4.7 继承边界 | 会话列表 | 点终止 | 先二次确认并说明后果；权限不足上浮原话 |
| `T-4.7-06` | 概要设计 §7.3 | §4.7 继承边界 | 磁盘被外部改动 | 保存与重载二选一 | 无静默覆盖；保存失败不清脏标记 |
| `T-4.7-07` | 概要设计 §19.9 | §4.7 继承边界 | 无统计读数的连接 | 打开诊断 | 缺数写「未接」，不报 0 |
| `T-6.1-01` | 概要设计 §8.8 / §9 | §6.1 映射表 | 21 码各造一次 | 触发并呈现 | 每码有落点与呈现形态；文案来自文案表 |
| `T-6.2-01` | 概要设计 §9 | §6.2 禁令 | 四类兜底场景 | 注入失败 | 四类均不被当成成功；空 `catch` 检索为空 |
| `T-6.3-01` | 概要设计 §9 / §18.23 | §6.3 日志 | 一次含凭据与结果的完整动作 | 查日志与审计 | 无口令、无连接串、无结果行数据；必记字段齐 |
| `T-6.4-01` | 概要设计 第四章平台差异表 | §6.4 错误表 | 缺承载面 | 起壳 | 退出码 1；stderr 含包名；无窗口 |
| `T-7.1-01` | 概要设计 §11 | §7.1 并发 | 同连接两个页签 | 同时执行 | 语句串行；服务实例唯一；本端无定时器/线程 |
| `T-7.2-01` | 概要设计 §11 | §7.2 幂等 | 手工事务进行中 | 切换连接 | 拒绝；归档失败只报「记录未落盘」 |
| `T-8.1-01` | 概要设计 第四章平台差异表 | §8.1 凭据 | 删除连接 | 观察凭据与日志 | 凭据条目清空；日志无口令与连接串 |
| `T-8.2-01` | 概要设计 第四章平台差异表 | §8.2 注入 | 含引号与分号的输入值 | 参数化执行；检查 CSP 与能力清单 | 值不参与语句拼接；CSP 未放宽；权限逐项登记 |
| `T-8.3-01` | 概要设计 §11 | §8.3 零外发 | 全端源码 | 检索网络库与 URL | `Core`/`Platform`/`Cli` 无网络库；URL 只命中 `devUrl` 与注释 |

### 9.3 判据怎么跑

| 场景 | 命令 | 期望 |
|---|---|---|
| 本端判据（骨架 / 边界 / 同源） | `python3 Platform/linux/Tools/check-linux-skeleton.py` | rc=0；`--self-test` 全过 |
| 领域层与适配层单测 | `cargo test -p doyah-studio-core -p doyah-studio-linux-platform -p doyah-studio-linux-cli --offline` | 全绿（读数进台账，本文件不写用例数） |
| 依赖探测 | `bash Platform/linux/build.sh --deps` | Linux 宿主且依赖齐 ⇒ rc=0；缺项 ⇒ rc=1 且逐项点名 |
| 出包 | `bash Platform/linux/build.sh` | Linux 宿主 ⇒ rc=0 + 四行身份；非 Linux ⇒ rc=2 |
| 文档表格 | `python3 Scripts/check-doc-tables.py` | rc=0 |
| 文档结构 | `python3 Scripts/check-doc-layout.py` | 三书九轮读数与改动前一致（本文件不在该脚本受检清单内） |
| 本文件自检 | `python3 ~/.hermes/skills/software-development/detail-design-spec-writing/scripts/audit_lld.py Docs/Doyah产品详细设计说明书-Linux.md --hld Docs/Doyah产品概要设计说明书.md --repo .` | 硬失败 0 |

---

## 10. 合规自检

### 10.1 未实现位点（代码现状，不是文档缺口）

| 位点 | 现状 | 契约要求 |
|---|---|---|
| 探测「探不动」与「不在」分档 | 六项里只有剪贴板用 `unknown`；其余读盘失败一律按 `missing` 报 | §3.1 / §3.5–§3.10 的错误表；建议补条款见 §11 第 1 条 |
| 密钥环真绑定（`SecretStore`） | **未落**：`Platform/Linux/src/` 下无 `secret_store.rs`，凭据功能无实现 | §3.21 三方法 + 取/存/清三条判据（§11 第 1 条 `CONTRACT_DEVIATION`） |
| WebKitGTK 真绑定 | 只做存在性探测；`present` 语义 = 「前置在盘上」≠「接口可用」 | §3.5 禁止手写 FFI；版本查询未接（README 未接网清单第 3 项） |
| PTY 真绑定（`portable-pty`） | 只探解释器存在性；无真 PTY、无屏幕模型接线 | §3.7；`P-05` / `P-17` 的屏幕语义待实现片 |
| 复盘 Linux 树 | `retro` 仓 `platform/` 只有 `macos`、`windows` 两棵树 | §4.6 宿主槽位可挂；业务实现在 `retro` 仓 |
| 内嵌浏览器视图 | 同源面无浏览器视图；入口未出现（不是灰掉） | 概要设计 §3.1；本端登记 §11 第 2 条 |
| `.desktop` 集成（文件关联 / 图标 / 菜单项） | 未做；安装包内无 `.desktop` 逐项对账 | README 未接网清单第 6 项 |
| 本端判据接进本仓闭环 | `Scripts/verify-all.sh` 尚未调用本端判据（共享面需登记） | README 未接网清单第 7 项 |
| 真构建与安装包 | 非 Linux 宿主上从未成功出包（`build.sh` 如实 rc=2） | §3.20 四档交付物身份 |

### 10.2 逐条自检

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | §1.2 每个「修改」路径真实存在 | 过 | 13 条修改路径逐条 `ls` 在盘；1 条标「新增」（`secret_store.rs`） |
| 2 | §1.2 与 §1.3 路径集合交集为空 | 过 | 集合比对，交集 0（`Platform/windows/App/src-tauri/` 只在 §1.3） |
| 3 | 每个公开函数七段齐 | 过 | §3.1–§3.21 各含前置/后置/错误契约表/禁止行为/并发幂等/日志/测试 ID |
| 4 | 每张错误表有「可重试」列且逐行有判定 | 过 | `audit_lld.py` 的 C01 读数 0 |
| 5 | 21 个错误码都有落点或标「未实现」 | 过 | §6.1 表 21 行，其中 2 行标「契约已立实现未跟」 |
| 6 | 九个组件六态齐且「禁止渲染」非空 | 过 | §5.3.1–§5.3.9；U01 读数 0 |
| 7 | 矩阵无空「落点/测试 ID」 | 过 | §0.1 78 行全填（人工点验行按 allowlist 记） |
| 8 | 测试 ID 无悬空 | 过 | `audit_lld.py` 的 T01 读数 0 |
| 9 | 测试 ID 无孤儿 | 过 | `audit_lld.py` 的 T02 读数 0 |
| 10 | 未引入 §1.1 禁止项 | 过 | 12 条静态检查逐条检索为空（§1.1 表最右列） |
| 11 | 状态机未新增状态、未绕过 guard | 过 | §4.4 七行 + 闭集约束段；`T-4.4-07` |
| 12 | 落点节引用全部解析得到 | 过 | `audit_lld.py` 的 M04 读数 0 |
| 13 | 概设契约节按 §0.1 声明覆盖 | 过 | §0.1 末段列出未进表节次与理由（§11 第 7 条） |
| 14 | 无禁用词、无占位符 | 过 | `audit_lld.py` 的 W01 / P01 读数 0 |

---

## 11. 偏离处理与登记

| 信号 | 触发条件 | 动作 |
|---|---|---|
| `DETAIL_GAP` | 本文件未覆盖的公开行为 | 取最小假设继续，并登记到本节表 |
| `DETAIL_CONFLICT` | 与代码现状冲突 | 停工，报人类主人 |
| `CONTRACT_DEVIATION` | 偏离 §3 / §5.3 契约 | 等确认 |
| `PLATFORM_CHANGE` | 需要更换本端基线（Tauri 2 / WebKitGTK / 同源前端） | 停工 |
| `DESIGN_CONFLICT` | 与概要设计冲突 | 以概要设计的「禁止」为准，不自行裁决 |

已登记的 `DETAIL_GAP`（概要设计未定义、本文件按最小假设落地）：

| # | 未覆盖点 | 所做选择 | 影响范围 | 建议补的条款 |
|---|---|---|---|---|
| 1 | 能力探测无法区分「探不动」（读不到库目录 / 无权限）与「确实不在」 | 除剪贴板外一律按 `missing` 报并给补救指引（宁严不宽：缺它起不来） | §3.1、§3.5–§3.10 | 概要设计 第四章 P-26 补一句「探测失败与确实缺失必须分档，失败不得报成缺失」 |
| 2 | 内嵌浏览器视图在本端未建时的界面表现 | 入口不出现（不是灰掉），不画空容器 | §5.1、§5.3.1 | 概要设计 §3.1 补「未建端的入口不出现」 |
| 3 | 托盘缺失时的降级形态（无托盘能否退出 / 关窗是否退出） | 不打托盘，不阻塞启动；关窗即退出（不驻留托盘） | §3.10、§5.2 | 概要设计 第四章 P-12 补「无托盘端的窗口关闭语义」 |
| 4 | 构建产物的签名与校验（`deb` 签名 / AppImage 校验档） | 首版不做签名，只出 `sha256` 与身份卡 | §3.20 | 发布方案与 第四章 P-08 补签名要求 |
| 5 | `capabilities --json` 的字段集（`host` 之外还要不要时间与版本） | 只出 `host` 与 `capabilities` 两块，不编造读数 | §3.17 | 概要设计 §19.1 补 CLI 输出字段清单 |
| 6 | 能力取值是否可缓存（性能 vs 正确性） | 不缓存（缓存会让「装好前置仍报缺」） | §5.5 | 概要设计 §11.4 补「兼容性探测的时效口径」 |
| 7 | 笔记域 11 节 + 复盘域 14 节 + Agent 内核 21 族 + 补遗 6 节未进本矩阵 | 只承接宿主装配与平台面，业务判据在分册三书自跑；理由与清单写进 §0.1 末段 | §0.1、§4.5、§4.6 | 各分册（`notes` / `retro`）补对应端详设，或本文件下版收编 |

已登记的 `CONTRACT_DEVIATION`（契约已立、实现未跟 —— 关闭判据是测试转绿）：

| # | 条款 | 现状 | 关闭判据 |
|---|---|---|---|
| 1 | §3.21 `SecretStore` 三方法 | 契约已写，`Platform/Linux/src/secret_store.rs` 未建；凭据功能当前无实现 | `T-3.21-01` / `T-3.21-02` 转绿（替身后端 + 无密钥环两条） |
| 2 | §3.5 / §3.7 / §3.9 的 `present` 语义 | 现为「前置在盘上」，不是「接口可用」；版本查询与真 PTY 未接 | 接 `webkit2gtk` 版本查询 + `portable-pty` 后各补一条端上判据，并把语义写回本节 |

已登记的 `DETAIL_CONFLICT`（与代码现状冲突，须人类主人裁决，Agent 不得自行改设计或改代码）：

| # | 冲突点 | 代码现状 | 契约要求 | 处置 |
|---|---|---|---|---|
| 1 | 代码注释引用的概要设计节号已失效 | `Platform/linux/README.md`、`build.sh`、`src-tauri/*/Cargo.toml` 与各 `.rs` 注释引用「概要设计 §8.6.1 / §8.6.3 / §8.6.4 / §8.6.6」「§2 GUI 框架行」「§9.3.1 后端同源」；现行概要设计里 §8.6 是「表单与校验契约」、§2 是「Agent 执行总则」、§9.3.1 不存在 | 本文件引用一律用现行节号（§1.4 / 第四章平台差异表 / §11.4 / §3） | 以现行概要设计为准；代码注释随对应实现片订正（**不改契约口径**）。本行保留留痕，避免下一位 Agent 去改概要设计迁就注释 |
| 2 | 代码注释里的命令面条数已过时 | `Platform/linux/src-tauri/src/lib.rs` 与 `Cargo.toml` 注释写「132 条命令」，而同源 `generate_handler!` 的注册项已多于该数 | 本文件不写死条数，只写「同源注册全集」（§3.19 后置） | 条数不属契约（读数只进台账）；注释随实现片订正，本行留痕 |

---

## 12. 版本口径与本版改动面

- 本书版本 = 三段式 `v1.0.4`：`v<冻结段>.<次>.<流水>`，正文任何改动只 +1 第三段，满 999 冻结为 `v1.1`（其后 `v1.1.NNN`）。版本身份的判据 = `Scripts/check-doc-versions.py`（头部 20 行内出现三段式、第三段 ≤ 999）。
- **书里不记改动台账**（2026-10-26 人类主人令：「每次推送都会有 Git 记录……不要把 Git 的修改记录放到活书里」）。逐轮改了什么看 git 提交；判据 = `Scripts/check-doc-versions.py` 与 `Scripts/check-doc-invariants.py` —— 该台账节的名字在书里一个字都不许出现（标题、正文引用、附录目录都算），所以本节连字样都不写。头部那三行版本引文只承载**版本身份**（冻结段起点与上一版号），不是改动台账。
- 本版（v1.0.4）的改动面（只列面，不列逐条流水）：
  - 追溯矩阵：由 15 行区间行拆到 78 行逐条款（概设 §1.3–§12 + 第四章平台差异表 + §15/§16/§18/§19 的本端承接节）。
  - 函数契约：§3 由 13 节散文改为 21 节逐函数七段契约（能力探测 6 项、取值 2 项、身份 2 项、起壳 3 项、CLI 2 项、数据家与挂载 2 项、构建入口 1 项、凭据 1 项）。
  - 界面：§5.3 拆 9 个组件六态小节；新增 §5.8 界面用例表（23 条）；版式语汇改为「映射概要设计 §8.11」而非重定义。
  - 新增：§4.4 状态覆盖清单、§6.4 启动/构建期错误、§9.2 用例表（65 行）、§10.1 未实现位点、§11 三类偏离登记。
  - 簿记修正：头部 `v1.0.3` 与正文「文档版本：v1.1」互相矛盾，统一按三段式 `v1.0.4` 归位；原 §12 已知坑移 §13。
  - 影响的概设条款：§1.3–§12、§15.1/§15.6/§15.9、§16.1/§16.2/§16.10/§16.18、§18.6/§18.23、§19.1/§19.2/§19.9、第四章平台差异表。影响的详设单元：全部 §3 函数、§5.3 九组件、§6.1 映射表、§4.4 状态表。

---

## 13. 本端已知坑（必须先读）

### 13.1 平台名与「自用第三端」的历史口径已作废

需求书里「Linux 自用第三端 = 本仓选定」一句已于 2026-10-14 作废（令：Linux 由小河马负责的）；现行口径 = 概要设计 §1.4 的「PC 三端全量」+ 第四章 P-26。写本端条款时**不许**再把 Linux 当「只做 Notes」或「降级子集」，也不许把「自用」当放宽沙箱与权限的理由。

### 13.2 `present` 只等于「前置在盘上」，不等于「接口可用」

六项探测全部是存在性检查（库文件、`pkg-config` 说明、环境变量、服务文件），没有一处真调接口。因此：`webview present` 只说明 WebKitGTK 装上了，不代表能起；`pty present` 只说明解释器在，不代表能起终端。任何把 `present` 读成「功能可用」的判断都是假绿（§3.5 禁止行为、§11 `CONTRACT_DEVIATION` 第 2 条）。

### 13.3 非 Linux 宿主上跑本端判据的两个必然读数

`build.sh` 在非 Linux 宿主上必然 rc=2（如实拒绝），`probe_webview` 必然 `missing`。这两条**不是缺陷**，是本端「不假装能构建」的设计。要真验构建与打包，必须到 Linux 宿主或公司环境的验机机上跑，并把读数记进台账而不是写进本文件的契约里。

### 13.4 前端同源的三条边界

① 本端不许出现 `App/` 或 `dist/`（判据 D 条）；② `frontendDist` 只能指 `../../windows/App/dist`；③ 前端改动一律走 Windows 侧，本端只跟随。踩过一次的形态：为「先让界面出来」在本端复制一份前端，结果两套界面各自漂，判据红了两周没人认领。

### 13.5 能力名表是冻结表

`CAPABILITY_NAMES` 六项的顺序与拼写（`webview`、`secret-service`、`pty`、`notifications`、`clipboard`、`tray`）是 CLI 输出、判据、前端渲染三处的共同锚点。改名或调序会让三处同时静默错位（`capabilities` 输出看起来仍然「有六行」）。新增一项必须先改本节与概要设计 §11.4 的口径，再改代码。

### 13.6 文档门禁的四条本端口径

① `audit_lld.py` 的测试 ID 定义面只认 §4.4 / §5.8 / §9.2 三节正文 —— 用例只写进 §9.1 会被算成悬空，必须落 §9.2；② `check-doc-tables.py` 会把「表格后紧跟一行普通散文」判成续行，每张表后必须留空行，且**表格单元格里不许出现竖线**（正则交替式 `a|b` 会把单元格切碎，写成两条检索命令）；③ `check-doc-layout.py` 的受检清单是三书（能力书 / 需求书 / 概设），本文件不在其中，它的读数是别的书的读数，不许拿来当本文件的证据；④ 判据里的检索命令要写清「非注释行」——本端源码注释里就含 `invoke_handler` / `.plugin(` 这类说明文字，裸 `rg` 会把口径说明算成违规命中。
