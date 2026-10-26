# Doyah产品开发计划任务清单 · Windows 端

> **版本** v0.1（2026-10-26 首建）
> **身份**：本端任务清单，与《Doyah产品详细设计说明书-Windows.md》**一一对应**（人类主人 2026-10-26 令：任务清单按端分册，不设产品级总单）。
> **取数口径**：本端状态取 `Docs/平台实现状态.json` 的 `windows` 列（显式登记 159 条）；未登记的行**不在本端清单里**，不拿 macOS 状态顶替。

## 0. 元信息

| 项 | 值 |
|---|---|
| 端 | Windows（babyhippo 侧实现） |
| 对标详设 | `Docs/Doyah产品详细设计说明书-Windows.md`（v0.3，219 行） |
| 开发宿主 | Windows 主机 / Swift-Win 栈（详设 §2 分层） |
| 本端状态登记 | `Docs/平台实现状态.json` → `platforms.windows.overrides`（159 条） |

## 1. 基线读数

| 项 | 值 |
|---|---|
| 本端登记需求 | **159** 条 |
| ✅ / 🟡 / ⬜ | 152 / 7 / 0 |
| 未登记 | 其余需求未做 Windows 适用性判定（**不等于不适用**，属未登记，见 §4） |

## 2. 需求状态台账（Windows · 159 条）

| 编号 | 需求摘要 | 所属域 / 章节 | Windows 状态 |
|---|---|---|---|
| FR-AGT-GUARD-PERM-001 | 执行审批与审计：智能体发起的写操作 / DDL / 外部动作逐次审批（可配置只读模式 | 3.2 Doyah Agent | 🟡 |
| FR-AGT-LINK-CHAN-001 | 模型接入配置：可配置模型服务（本地 / 远端，OpenAI 兼容端点）、模型名、AP | 3.2 Doyah Agent | 🟡 |
| FR-STD-ALL-BLD-001 | 从声明式工程描述生成构建工程，可重复生成（生成器属平台实现） | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-002 | 生成后自动修复本地包 product 关联（避免 Missing package p | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-003 | Core 逻辑单元测试可一条命令运行 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-004 | 不打开 Xcode 也能产出可运行的 .app | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-005 | 提供依赖镜像脚本应对国内网络 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-006 | 提供本地端到端链路验证（无需外部数据库） | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-007 | 提供真实 PostgreSQL 连接验证脚本 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-008 | 工程可被命令行构建工具直接编译（不依赖图形 IDE） | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-BLD-009 | 配套文档随代码同步维护，需求变更可追溯 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-CLI-001 | 提供 DoyahCLI，可在无 UI 环境下验证连接与执行 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-CLI-002 | 支持环境变量连接参数：PGHOST/PGPORT/PGUSER/PGPASSWORD | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-CLI-003 | 支持 -c "SQL" 执行任意 SQL | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-CLI-004 | 支持 --tree 打印对象树，--columns 附带列类型 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-CLI-005 | 失败时返回非零退出码，便于脚本判定 | 3.1.1 工程与工具链 | ✅ |
| FR-STD-ALL-PLUG-001 | 笔记插件以同进程内模块装配（不做独立进程 + IPC、不做可卸载组件包） | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-002 | 活动栏出现「笔记」一项 | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-003 | 宿主向插件单向传上下文（当前连接、库 / 表、选中 SQL） | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-004 | 笔记数据落在本工程数据家之外（独立目录），备份与清理策略各自独立 | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-006 | 许可证一套覆盖三个能力位（开发工作区 / 智能数据库助理 / 笔记），不做插件独立授 | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-007 | 允许插件复用宿主词法层（CodeSyntax / CodeLexer / CodeC | 3.1.3 插件装配 | ✅ |
| FR-STD-ALL-PLUG-008 | 桌面各端笔记存储统一到本地 SQLite（2026-09-27 拍板 Q23）：主存 | 3.1.3 插件装配 | ✅ |
| FR-STD-DB-CONN-001 | 新建连接：名称、数据库类型、主机、端口、数据库名、用户名、密码、SSL 模式、超时 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-002 | 数据库类型切换时，默认端口、默认 SSL 模式、默认 schema 自动联动 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-003 | 配置校验：名称、主机、端口（1–65535）、用户名非空 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-004 | 连接配置带 schemaVersion，为将来配置格式升级预留迁移能力 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-005 | 连接 URL 导入 / 导出：支持 postgres://user@host:por | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-006 | 连接保活心跳：空闲连接按间隔发送轻量查询，避免被防火墙 / 中间件掐断长连接 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-007 | 以列表展示全部已保存连接，可选中，选中项作为后续执行 / 元数据的上下文 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-008 | 编辑连接：不得出现「点编辑却弹出新建、字段为空」 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-009 | 删除连接：需二次确认，并同时清理系统凭据存储中的密码与连接缓存 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-010 | 记忆上次选中的连接，重启后恢复该选中项 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-011 | 连接在界面上的显示名 = 名称 (登录用户名)：连接名后括注登录账号，用于侧边栏连接 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-012 | 连接分组 / 文件夹：连接可归入自定义分组，侧边栏按组折叠展示，便于按「项目 / 环 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-013 | 连接颜色与环境标签：可为连接指定颜色与「生产 / 预发 / 测试」标签，侧边栏与查询 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-014 | 只读连接与启动 SQL：可把连接标记为只读（客户端拒绝执行写语句） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-015 | 查询工具栏上方提供「当前服务器」选择器：枚举已保存连接（名称 + 地址），切换后作为 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-016 | 服务器选择器右侧提供「当前数据库」下拉框：枚举当前服务器上当前登录用户有权限访问的数 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-017 | 密码存入系统凭据存储，不写入配置文件 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-018 | 编辑连接时密码留空 = 保持原密码不变 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-019 | 密码等敏感输入使用 ASCII 安全字段，避免输入法干扰 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-CONN-021 | 「测试连接」真实连接服务器，返回 server_version / 当前库 / 当前 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-001 | 对象树双击表 / 视图节点 → 新建页签并执行「浏览前 N 行」（SELECT * | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-002 | 表行数统计与条件过滤入口：一键 count(*) | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-003 | 生成 SQL 模板：按表结构生成 SELECT 列清单与 INSERT … VALU | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-004 | 结果集内联编辑（改单元格 / 新增行 / 删除行），提交前预览将执行的 DML，确认 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-005 | 单行详情 / 单元格值编辑器：宽表与长 JSON 竖排查看，JSON 值格式化显示 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DATA-006 | 外键引用导航：由单元格 / 行跳转到被引用表并自动带入条件 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DDL-001 | 由列定义生成 CREATE TABLE（列名 + 类型 + NOT NULL），用于 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DDL-002 | 生成 DROP TABLE / TRUNCATE TABLE（DROP 默认带 IF | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DDL-003 | 表结构编辑器：可视化增删列、改类型、加索引与约束，并实时对照将要执行的 DDL （v | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DDL-004 | Schema 对比与同步：对比两个库 / 两个连接的结构差异并生成同步脚本 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DDL-005 | ER 图 / 关系图：由外键生成可视化关系图 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DIAG-001 | 执行计划查看：对当前 SQL 执行 EXPLAIN（可选 ANALYZE / BUF | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DIAG-002 | 计划摘要：顶部一行给出节点数、规划 / 执行耗时、全表扫描处数、最慢节点，一眼看出瓶 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DIAG-003 | 慢查询排行：pg_stat_statements 按总耗时 / 平均耗时 / 调用次 | 3.4 Doyah Studio · 数据库 | 🟡 |
| FR-STD-DB-DIAG-004 | 数据库统计面板：表大小、索引命中率、连接数、缓存命中率等 pg_stat_* 指标 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DIAG-005 | 锁与阻塞链定位：基于 pg_locks + pg_blocking_pids() 展 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-001 | SQL 方言协议：标识符引用、分页子句、库/模式/表/列清单、版本号查询与解析、关键 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-002 | 语句拆分按方言：PostgreSQL 跳过 dollar-quote | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-003 | 拆分器只识别边界，不改写 SQL 原文 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-004 | 字符串、注释、dollar-quote 内的分号不得触发拆分 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-005 | 定义稳定的 DatabaseService 协议：连接、断开、执行（流式事件）、取消 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-006 | 执行结果以事件流返回：started / resultSet / affectedR | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-007 | 工厂按数据库类型返回实现 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-008 | PostgreSQL 驱动使用成熟的协议实现，版本固定（依赖锁文件 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-009 | GBase 8a 驱动实现（复用 MySQL 协议系的协议实现，具体库属平台实现） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-DRV-010 | MySQL 驱动实现：DatabaseType 新增 mysql 档（默认端口 33 | 3.4 Doyah Studio · 数据库 | 🟡 |
| FR-STD-DB-EXEC-002 | 按当前连接与上下文栏所选数据库执行 SQL，支持多语句 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-003 | 每条语句按顺序执行，逐条上报执行状态 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-004 | 同一连接的并发执行复用同一个连接，避免重复握手 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-005 | 空 SQL 或未选连接时给出明确提示而非静默失败 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-006 | 执行目标判定：有选区只跑选中的那段，没有选区跑整篇 —— 自动判定，不需要用户先设「 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-007 | 事务模式：提供「自动提交」开关与提交 / 回滚按钮 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-008 | 查询参数：SQL 中可用 :name / $1 占位符，执行前弹窗填值并做类型化转义 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-009 | 多结果集：全部保留，可通过下拉选择器切换查看 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-010 | 显示行数 × 列数与耗时 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-011 | 显示 SQL 错误详情，可选中复制 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-012 | 执行中的页签不可关闭 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-013 | 执行返回「影响行数」（DML command tag） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-014 | 执行入口为工具栏图标按钮（绿色实心三角形 ▶），不使用文字按钮 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-015 | 提供事务 API：beginTransaction / commit / rollb | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-016 | 查询工作区提供图标按钮工具栏，承载常见数据库客户端操作（执行 / 停止 / 检查，后 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-017 | 高危语句保护（Safe Mode）：对不带 WHERE 的 UPDATE / DEL | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-EXEC-018 | 「停止」取消当前执行 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-IO-001 | 结果集导出：CSV / JSON / TSV / Markdown / INSERT | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-IO-002 | 客户端侧整表 / 整库导出：走 COPY <表> TO STDOUT 流式写文件 | 3.4 Doyah Studio · 数据库 | 🟡 |
| FR-STD-DB-IO-003 | 备份 / 恢复：封装 pg_dump / pg_restore（plain / cu | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-IO-004 | 备份文件恢复到指定库（pg_restore 的 --clean / --sectio | 3.4 Doyah Studio · 数据库 | 🟡 |
| FR-STD-DB-IO-005 | 导出 CSV 的文本编码可选：UTF-8（带 BOM，默认）/ GB18030（GB | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-IO-006 | CSV / JSON 导入：COPY … FROM STDIN 流式导入 + 列映射 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-IO-007 | Excel（.xlsx）导入映射向导 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-001 | PostgreSQL 树形结构：服务器 → Database → Schema → | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-003 | 懒加载：仅展开节点时查询下一层 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-004 | 自动过滤系统 schema（information_schema、pg_catalo | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-005 | 节点类型区分图标（库 / 模式 / 表 / 视图 / 列 / 函数） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-006 | 对象树必须支持持续下钻：从服务器节点开始，Database → Schema → T | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-007 | 跨数据库浏览：服务器节点展开后列出当前用户可连接的数据库 | 3.4 Doyah Studio · 数据库 | 🟡 |
| FR-STD-DB-META-008 | 对象树按类型 / schema 分组视图：可在「层级视图」与「按类型分组」之间切换 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-009 | 列节点显示数据类型 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-010 | 对象树右键菜单（第一期：仅服务器节点）：右键「服务器」节点提供 ① 连接、② 断开、 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-011 | 查看对象 DDL：表 / 视图 / 函数节点右键「查看 DDL」，展示等价建对象语句 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-012 | 表 / 视图 / 列节点右键菜单（第二期）：浏览前 N 行、生成 SELECT / | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-013 | 元数据查询有行数上限保护（10,000 行） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-014 | 元数据加载失败给出错误提示，不阻塞 UI | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-META-015 | 全库对象搜索：输入名称片段即跨 schema / 跨库匹配表、视图、列、函数，命中结 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-001 | 结果表格使用平台原生表格控件桥接，支持大结果集滚动 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-002 | 列宽按内容估算，可拖动调整，可重排列顺序 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-003 | 支持多选行，⌘C 与右键菜单复制 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-004 | NULL 与空字符串可区分显示 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-005 | 二进制 / 复杂类型单元格转为可读字符串 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-006 | 复制为多种格式：复制即带表头，或直接是 Markdown / INSERT 文本（不 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-007 | 客户端排序：点表头按列排序，支持多列（次要排序键）、升降序切换、NULL 位置固定 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-008 | 客户端筛选：每列可加条件（包含 / 不包含 / 等于 / 大于 / 小于 / 为空 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-009 | 分页控制条：选择每页行数（50 / 100 / 200 / 500 / 1000）， | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-010 | 结果导出为 CSV / JSON 文件 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-011 | 结果集分页 / 虚拟滚动超大数据量 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-012 | 导出扩展格式：TSV（表格软件友好）、Markdown 表格（贴文档 / 工单）、S | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-013 | 超大结果集流式落盘：导出直接写文件，不把全量结果驻留内存 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-RES-014 | 结果集导出 Excel（.xlsx） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-SESS-001 | 查询历史（按连接记录，可回填） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-SESS-002 | 服务器会话列表：展示当前实例的会话（进程号 / 用户 / 数据库 / 客户端地址 / | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-SESS-003 | 取消 / 终止会话：对选中会话执行「取消当前语句」（PG pg_cancel_bac | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-SESS-005 | 权限管理：查看角色对库 / schema / 表 / 序列的已授权限 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-DB-SESS-006 | 库属性管理：ALTER DATABASE（owner / 库级参数 / 连接限制）与 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-EDIT-002 | 工具栏保存按钮拆分：主体 = 直接保存（有文件路径则写回磁盘 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-EDIT-004 | 编辑菜单 → 清除查询：一键清空当前页签 SQL | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-EDIT-005 | 工具栏与菜单的快捷键全覆盖：工具栏每个按钮都有快捷键，tooltip 显示按键 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-EDIT-010 | 编辑菜单 → 查找 / 替换：在当前 SQL 中查找与替换文本 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-EDIT-012 | 跨文件内容搜索与替换（同「非常单薄」的量化结果：Core/WorkspaceSear | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-EDIT-013 | 工作区标头的搜索框（快速查找文件标题与内容关键字）（需求提出者 2026-09-30 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-EDIT-024 | 大脚本保护：超长 SQL 暂停静态检查，避免输入卡顿 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-FS-001 | 工作区视图有自己的页签集，默认打开 Home 欢迎页：在活动栏切到「工作区」时，编辑 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-FS-002 | 活动栏 + 工作区 Explorer：主窗口最左侧加一条窄的固定宽度活动栏（46pt | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-FS-003 | 工作区 Explorer 的文件操作（需求提出者 2026-09-30：「现在的工作 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-FS-007 | 工具栏新增「打开文件」按钮：通过系统打开面板选择 SQL / 文本文件，内容载入新建 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-FS-008 | 在工作区里点文件直接打开，并按文件类别匹配呈现：文本 / 代码文件在编辑器区打开 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-HELP-001 | 工具栏新增「帮助」按钮（问号图标），承载帮助入口 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-001 | 语法着色：关键字 / 函数 / 字符串 / 注释 / 数字 / 引用标识符分别配色（ | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-002 | 多语言关键字高亮方案（语言表可扩展 + 每语言一套高亮规则 + 颜色走主题令牌）：① | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-NAV-003 | SQL 自动补全（关键字 + 内建函数） | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-007 | 客户端静态检查：未闭合字符串、未闭合块注释、未闭合 dollar-quote、括号不 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-008 | 静态检查基于当前方言的关键字与函数表 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-009 | 服务器端语法检查：「检查」按钮对可 EXPLAIN 的语句执行 EXPLAIN，不真 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-010 | 检查结果：通过显示「已检查 N 条，跳过 M 条」 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-011 | 修改 SQL 后清空上一次检查结果 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-013 | 编辑菜单 → 格式化 SQL：对当前 SQL 做关键字大写、子句换行与缩进 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-NAV-014 | 代码格式化能力：对当前工作区文件按语言格式化（编辑器菜单 / 快捷键入口），格式化前 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-TOOL-001 | 底部终端面板：主窗口底部可拖拽 / 可折叠的面板，内嵌本机交互式 shell（真 P | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-TOOL-002 | 工作区下方面板（应用级通用面板）：页签为 问题 / 输出 / 终端 / 调试控制台 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-UI-001 | 多页签：新建（⌘T）、切换、关闭 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-UI-002 | 新建查询页签的编号在应用生命周期内单调递增（1、2、3…），不受页签被关闭、重命名或 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-UI-003 | 关闭有未保存改动的文件页签：确认，不阻塞（需求提出者 2026-10-03 原话：「 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-UI-004 | 会话恢复（同「非常单薄」的量化结果：App/WorkspaceTabsModel.s | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-UI-005 | 命令面板：⌘K 唤起，可搜索并执行「新建查询 / 执行 / 检查 / 格式化 / 导 | 3.4 Doyah Studio · 数据库 | ✅ |
| FR-STD-WS-UI-006 | 窗口标题跟着活动栏走 + 标题栏居中的搜索栏：主窗口标题随活动栏当前视图变化（Doy | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-UI-009 | 外观配置：主题（配色方案）+ 强调色：主题跟随系统外观（浅色原生精致 / 深色专业暗 | 3.3 Doyah Studio · 工作区 | ✅ |
| FR-STD-WS-WEB-002 | 工作区编辑器的 Markdown 预览（需求提出者 2026-09-30 原话：「工 | 3.3 Doyah Studio · 工作区 | ✅ |

## 3. 批次（按详设 §10 未实现位点）

| # | 位点 | 现状 | 契约 | 估时（分钟） | 状态 |
|---|---|---|---|---|---|
| W-1 | 行编辑错误两码 | 未实现 | 概设 §4.6 | 90 | ⬜ |
| W-2 | DDL 预览闸 | 未实现 | 概设 §4.7 | 120 | ⬜ |
| W-3 | 导入导出部分失败 | 未实现 | 概设 §4.8 | 90 | ⬜ |
| W-4 | 会话终止权限码 | 未实现 | 概设 §4.9 | 60 | ⬜ |
| W-5 | 授权能力位 | 未实现 | 概设 §3 | 120 | ⬜ |
| W-6 | Notes 功能本体 | 不在本端（宿主承载） | 概设 §15 | — | ➖ |

## 4. 阻塞与依赖

| # | 依赖 | 影响 |
|---|---|---|
| 1 | Windows 分端适用性登记未做完（159 / 397） | 本清单只覆盖已登记部分；未登记条目不在此列 |
| 2 | 契约层（概设）条款冻结在 hugehippo 侧 | W-1~W-5 的判据口径须等契约冻结 |

## 5. 交付定义（与 macOS 端同口径）

- 代码 + 判据 + 门禁全绿 + 出包四件齐，才算一条 ✅；「做了但没验」记 🟡。

## 6. 变更记录

| 版本 | 日期 | 变更内容 | 影响范围 |
|---|---|---|---|
| v0.1 | 2026-10-26 | 首建：从 `平台实现状态.json` 的 windows 列生成 159 条台账；批次取详设 §10 未实现位点 | 全部（骨架） |

