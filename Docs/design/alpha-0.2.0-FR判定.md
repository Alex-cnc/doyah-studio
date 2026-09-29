# `v0.2.0-alpha` 范围账 —— FR 🟡 逐条判定

> **这份文件是什么**：`python3 Scripts/report-requirements.py` 盘点出的 **FR 🟡 48 条**，
> 逐条给出「这条算不算 `v0.2.0-alpha` 的范围」的判定与理由。发布说明（仓根
> `RELEASE-0.2.0-alpha.md` / `Docs/alpha-0.2.0-发布说明.md`）的「明确不做什么」一节**直接引用本表**，
> 不再另抄一份。
>
> **口径**（队列 **L-69** 条件 ③，与 `v0.1.0-alpha` 那次逐字一致）：能机器验的**补证据**
> （脚本 + 断言数，可复跑）；不能机器验的（需人工点击 / 需真机 / 需外部实例）**逐条标
> `[alpha 不含]`**；**状态格仍 🟡 不改 ✅** —— 不把「没验」当成「验过了」。
>
> **台账与判据**：`Scripts/alpha-fr-dispositions.json`（唯一事实来源）＋
> `Scripts/check-alpha-fr-dispositions.py`（接在闭环**第 5 项**，项数仍十八）。复跑：
> `python3 Scripts/check-alpha-fr-dispositions.py`（含 `--self-test` 11 例负例）。
> 判据 = 台账 ↔ SRS **双向**对账 / 标记逐字对上 / 原因档在词表内 / 每条至少一个**存在的**证据指针 / 空跑防护。

## 判定结果一览

| 档位 | 条数 | 含义 |
|---|---|---|
| `ui-click` | **33** | 界面点击 / 观感只能人工 |
| `environment` | **6** | 本机物理不可能 |
| `device-instance` | **6** | 需真机 / 外部实例 / 外部软件（`FR-IO-04` 2026-09-29 由 `needs-decision` 转入 —— 拍板已下，残项只剩 217 专用库的真实还原） |
| `not-implemented` | **2** | 本 alpha 明确不含的未做功能 |
| `needs-decision` | **0** | 等需求提出者拍板（唯一那条 `FR-IO-04` 于 2026-09-29 拍板「改非沙箱」后转入 `device-instance`） |
| `open-defect` | **1** | 点验发现的缺陷（已开队列条） |
| **合计** | **48** | = FR 🟡 48 条（`FR-DRV-09` 已 ✅，不在其中；`FR-EXEC-15` / `FR-EXEC-17` / `FR-DDL-05` / `FR-DATA-04` 2026-09-28 ~ 09-29 销账）|

> **2026-09-28 销账**：**`FR-EXEC-15`（事务回滚 / 提交）、`FR-EXEC-17`（参数绑定的注入面）与 `FR-DDL-05`（ER 图面板观感）人工点验通过**（SRS **v3.268 / v3.269 / v3.270** 已由 🟡 转 ✅）⇒ 从本表与 `Scripts/alpha-fr-dispositions.json` 里**删除**（销账，不留陈旧条目）。本表 48 条、非环境 **43** 条；**2026-09-29 又销 `FR-DATA-04`**（结果集内联编辑，人工点验「过」）—— 合计 49 → 48、`ui-click` 34 → 33、非环境 44 → 43。判据 `check-alpha-fr-dispositions.py` 会替我们把这件事判住（「修好了要销账」）。

> **如实记一处数字纠正**：队列 **L-69** 原文写「**46** 条非环境 🟡」—— 那是 52 − 6（含当时已 ✅ 的
> `FR-DRV-09`）；按 🟡 实况算，带 `[alpha 不含]` 的只有 **5** 条 ⇒ **非环境 47 条**。本轮按实测走 **47**。
>
> **沿用与新增**：环境档 5 条是 `v0.1.0-alpha` 那次（`v3.252`）手加的标记，本轮**沿用原文**；
> 其余 **47 条**是本轮判定后新加（`FR-EDIT-29` 同时含沙箱限制与未做功能，归 `environment` 档并在标记里写明两因）。
>
> **2026-09-29 更新（开发循环第 95 轮，队列 `L-92`）**：需求提出者拍板「**改非沙箱，先验证功能**」⇒ 三条与沙箱绑定的残项**随拍板消解** —— `FR-CONN-18` 只剩真跳板机握手、`FR-EDIT-29` 去掉沙箱那一因（`^C` 另有机器判据）、`FR-IO-04` 由 `needs-decision` 转 `device-instance`（只剩 217 专用库的真实还原）。**条目数不变（50）**，变的是原因；`Docs/需求规范书.md` **v3.278** 三处状态格与台账 `Scripts/alpha-fr-dispositions.json` 已同步，判据 `check-alpha-fr-dispositions.py` 逐字对账通过。

## 逐条判定

| 编号 | 域 | 剩余（残项） | 档 | 可复跑证据 |
|---|---|---|---|---|
| **FR-AI-03** | 3.12 AI 智能体 | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 | `device-instance` | `Scripts/run-no-endpoint-evidence.sh`、`Scripts/test-diagnosis.sh` |
| **FR-AI-04** | 3.12 AI 智能体 | 真实模型端点未接（需端点与凭据）；界面入口待人工点验 | `device-instance` | `Scripts/run-no-endpoint-evidence.sh`、`Scripts/test-maintenance.sh` |
| **FR-AI-07** | 3.12 AI 智能体 | 合成数据面板界面点击待人工点验（真机往返已验） | `ui-click` | `Scripts/test-synthetic-data.sh` |
| **FR-AI-10** | 3.12 AI 智能体 | host 方向仍为批处理式且 resources/read 未做；真 MCP 对端待外部实例 | `not-implemented` | `Scripts/run-no-endpoint-evidence.sh`、`Scripts/test-mcp.sh` |
| **FR-AI-11** | 3.12 AI 智能体 | 界面点击待人工点验 | `ui-click` | `Scripts/test-spec-versioning.sh` |
| **FR-AI-12** | 3.12 AI 智能体 | 注入端到端未验（缺模型端点与实例）；连接权限的客户端校验未做 | `device-instance` | `Scripts/alpha-main-chain-v0.2.sh` |
| **FR-AI-14** | 3.12 AI 智能体 | 界面点击待人工点验 | `ui-click` | `Scripts/test-routine-candidates.sh` |
| **FR-AI-15** | 3.12 AI 智能体 | 界面点击待人工点验 | `ui-click` | `Scripts/test-memory-governance.sh` |
| **FR-CONN-15** | 3.1 连接与凭据 | 2026-09-27 点验未过：折叠状态活不过一次活动栏切换，已开队列 L-59，修完复验 | `open-defect` | `Scripts/test-connection-groups.sh` |
| **FR-CONN-18** | 3.1 连接与凭据 | 仅剩真跳板机的真实握手待环境（「沙箱下不能起 ssh」2026-09-29 随拍板消解：默认构建即非沙箱） | `environment` | `Scripts/test-ssh-tunnel.sh` |
| **FR-DATA-02** | 3.5 数据编辑与写回 | 界面呈现待人工点验 | `ui-click` | `Scripts/test-table-structure.sh` |
| **FR-DATA-05** | 3.5 数据编辑与写回 | 界面点击待人工点验 | `ui-click` | `Scripts/test-row-detail.sh` |
| **FR-DATA-06** | 3.5 数据编辑与写回 | 界面点击待人工点验 | `ui-click` | `Scripts/test-fk-navigation.sh` |
| **FR-DDL-03** | 3.6 表结构与 DDL | 界面呈现待人工点验 | `ui-click` | `Scripts/test-table-index-fk.sh` |
| **FR-DDL-04** | 3.6 表结构与 DDL | 界面点击待人工点验 | `ui-click` | `Scripts/test-schema-diff.sh` |
| **FR-DIAG-03** | 3.7 性能与诊断 | 本机 pgserver 精简构建无扩展目录 → pg_stat_statements 装不上 | `environment` | `Scripts/test-slow-queries.sh` |
| **FR-DIAG-04** | 3.7 性能与诊断 | 界面点击待人工点验 | `ui-click` | `Scripts/test-database-stats.sh` |
| **FR-DRV-08** | 3.10 驱动与方言兼容 | 无 GBase 8a 实例（方言层与驱动已实现，未端到端验） | `environment` | `Scripts/test-mysql-driver.sh` |
| **FR-EDIT-25** | 3.2 SQL 编辑与执行 | 界面点击待人工点验 | `ui-click` | `Scripts/check-palette-wiring.py`、`Scripts/test-command-palette.sh` |
| **FR-EDIT-26** | 3.2 SQL 编辑与执行 | 主题三态 / 字体字号观感需人工看一眼 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-EDIT-27** | 3.2 SQL 编辑与执行 | 界面点击待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-EDIT-29** | 3.2 SQL 编辑与执行 | sixel / kitty 图形未做；界面未人工验收（多会话页签的界面与判定均已交付、待点验）；「沙箱下 ^C 不可靠」2026-09-29 随拍板消解 —— 改成**机器判据**（`TestsUISnapshot/TerminalInterruptProbeTests.swift`） | `environment` | `Scripts/build-app.sh`、`Scripts/test-terminal-modes.sh`、`Scripts/test-terminal-palette.sh` |
| **FR-EDIT-34** | 3.2 SQL 编辑与执行 | GUI 点击与下载观感待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-EDIT-35** | 3.2 SQL 编辑与执行 | 界面切换与点击待人工点验 | `ui-click` | `Scripts/verify-core.sh` |
| **FR-EDIT-36** | 3.2 SQL 编辑与执行 | 界面点击待人工点验 | `ui-click` | `Scripts/test-workspace-editor.sh`、`Scripts/verify-all.sh` |
| **FR-IO-02** | 3.9 导入导出与备份 | vendor 驱动只实现 CopyFrom，缺 COPY … TO STDOUT | `environment` | `Scripts/test-cursor-export.sh`、`Scripts/test-table-export.sh` |
| **FR-IO-03** | 3.9 导入导出与备份 | 界面点击待人工点验 | `ui-click` | `Scripts/test-copy-import.sh`、`Scripts/test-data-import.sh` |
| **FR-IO-04** | 3.9 导入导出与备份 | 仅剩 217 专用库的真实还原待外部实例（「沙箱下起子进程的临时例外」2026-09-29 随拍板消解） | `device-instance` | `Scripts/build-app.sh`、`Scripts/test-backup-restore.sh` |
| **FR-IO-05** | 3.9 导入导出与备份 | 界面点击待人工点验 | `ui-click` | `Scripts/test-restore-resume.sh` |
| **FR-IO-06** | 3.9 导入导出与备份 | 界面点击待人工；真实软件（Excel / Numbers）产出的文件待人工 | `ui-click` | `Scripts/make-xlsx-fixtures.py`、`Scripts/test-data-import.sh`、`Scripts/test-xlsx-import.sh` |
| **FR-META-02** | 3.4 对象浏览与元数据 | 无 GBase 8a 实例 → 端到端 0 次 | `environment` | `Scripts/alpha-main-chain-v0.2.sh` |
| **FR-META-09** | 3.4 对象浏览与元数据 | 界面未点（展开 / 空态 / 失败态三步已在待人工验收清单 §5） | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-META-10** | 3.4 对象浏览与元数据 | 失败隔离与重试步骤待人工点验 | `ui-click` | `Scripts/test-connection-errors.sh` |
| **FR-META-12** | 3.4 对象浏览与元数据 | 界面点击待人工点验 | `ui-click` | `Scripts/test-object-search.sh` |
| **FR-META-13** | 3.4 对象浏览与元数据 | 界面呈现待人工确认 | `ui-click` | `Scripts/test-object-ddl.sh` |
| **FR-META-15** | 3.4 对象浏览与元数据 | 界面点击待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-PLUG-05** | 3.13 插件装配 | 验收要点 ①③④未做（源码只在公司机器，按平台口径非本侧） | `not-implemented` | `Scripts/check-notes-offline.py`、`Scripts/test-notes-offline-gate.py` |
| **FR-PLUG-08** | 3.13 插件装配 | 界面点击点验待人工；打包项按平台口径非本侧 | `ui-click` | `Scripts/check-note-search-route.py`、`Scripts/test-note-search-route.py`、`Scripts/verify-all.sh` |
| **FR-RES-07** | 3.3 结果集与导出 | 大表实测待人工（NFR-PERF-02 的阻塞） | `device-instance` | `Scripts/alpha-main-chain-v0.2.sh` |
| **FR-RES-08** | 3.3 结果集与导出 | 界面点击待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-RES-09** | 3.3 结果集与导出 | 界面点击待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-RES-10** | 3.3 结果集与导出 | 界面点击待人工点验 | `ui-click` | `Scripts/alpha-main-chain-v0.2.sh`、`Scripts/make-ui-snapshots.sh` |
| **FR-RES-12** | 3.3 结果集与导出 | 界面粘贴待人工点验 | `ui-click` | `Scripts/test-result-copy.sh` |
| **FR-RES-13** | 3.3 结果集与导出 | 界面点击待人工点验 | `ui-click` | `Scripts/test-cursor-export.sh` |
| **FR-RES-14** | 3.3 结果集与导出 | Excel / Numbers 打开需人工（外部软件） | `device-instance` | `Scripts/test-xlsx-export.sh` |
| **FR-SESS-01** | 3.8 会话与服务器管理 | 界面点击待人工点验 | `ui-click` | `Scripts/test-session-management.sh` |
| **FR-SESS-02** | 3.8 会话与服务器管理 | 界面点击待人工点验 | `ui-click` | `Scripts/test-session-management.sh` |
| **FR-SESS-03** | 3.8 会话与服务器管理 | 界面点击待人工点验 | `ui-click` | `Scripts/test-server-objects.sh` |

## 怎么复跑这本账

```bash
# 1) 盘点（本表的条目来源）
python3 Scripts/report-requirements.py
# 2) 范围账判据（台账 ↔ 需求规范书双向对账 + 负例自检）
python3 Scripts/check-alpha-fr-dispositions.py
python3 Scripts/check-alpha-fr-dispositions.py --self-test
# 3) 三模块主链（条件 ①，机器可验部分真跑）
./Scripts/alpha-main-chain-v0.2.sh
```

## 边界（本表不做的事）

- **不把 🟡 改成 ✅**：判定只分「含证据」与「`[alpha 不含]`」，状态位留给真正验过的那一刻。
- **不追点验**：界面点击 / 观感项一律标 `[alpha 不含]`，点验批次照旧按人工节奏走
  （清单见 `Docs/design/待人工验收清单.md`）。
- **不代替发布说明**：本表给的是**逐条理由**，发布说明给的是**面向使用者的范围口径**，两者引用关系单向（说明 → 本表）。

