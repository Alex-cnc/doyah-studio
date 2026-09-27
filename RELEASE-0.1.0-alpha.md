# Doyah Studio · v0.1.0-alpha 发布说明（macOS · 数据库模块）

> 需求提出者 2026-09-28 拍板：**数据库模块先发第一个 alpha**；优先级随之排定 **① 工作区模块（高）→ ② Doyah Notes（中）→ ③ Doyah Retro（低）**。
> 本文件是这一版的**范围口径**：能做什么、明确不做什么、怎么装、证据在哪。

| 项 | 值 |
| --- | --- |
| 版本 | **v0.1.0-alpha** |
| 日期 | 2026-09-28 |
| 构建产物 | `dist/DoyahStudio.app`，**release 构建**（`./Scripts/build-app.sh release`，131 s 编完），`CFBundleShortVersionString` = **0.1.0**（构建脚本里的数值版本；发布标签 `v0.1.0-alpha` 是它的 alpha 标记） |
| 目标端 | macOS（沙箱构建 `dist/DoyahStudio.app`；非沙箱构建用 `DOYAH_NO_SANDBOX=1`） |
| 范围 | **数据库模块**（工作区 / 笔记两块不在本版的判定范围） |
| 判定口径 | `./Scripts/alpha-main-chain.sh` **本机段全绿 ⇒ alpha 功能面达成** |
| 本轮判定（2026-09-28 06:31 CST） | **达成** —— 本机段 **21 段全绿**；预期红 3 条（其中 `schema-diff` 本轮实测**转绿**，基线待更新）；环境段 7 条逐条写明「alpha 不含」 |

## 一、这一版能做什么（主链，均已在真库上跑过）

1. **连接**：连本机 / 远程 PostgreSQL，失败态给可读原因（不是裸驱动码）
2. **对象树**：服务器 → 库 → schema → 表 → 列（含类型）逐层钻取
3. **写与执行 SQL**：参数化查询、执行计划、结果集
4. **结果集**：客户端排序 / 筛选 / 分页、复制为多格式、行详情（宽表 / 长 JSON / NULL 与空串可分）、外键跳转
5. **导出**：整表导出、结果集导出 **xlsx**（产物用另一份实现拆开核对）
6. **表结构**：表设计器改列并实时预览 DDL
7. **写回**：结果集内联编辑（主键定位、一批一事务、提交前预览 DML）
8. **导入**：CSV / JSON / **Excel（.xlsx）**（引号内逗号换行 / BOM / CRLF / NULL 与空串都不读错位）
9. **事务与合成数据**：失败不留半截状态；同 seed 可复现

## 二、alpha **明确不含**（不是缺陷，是范围）

| 类 | 条目 | 为什么 |
| --- | --- | --- |
| 无实例 | `FR-META-02` / `FR-DRV-08`（GBase 8a）、`FR-DRV-09`（MySQL 真机） | 本机没有 GBase 8a 实例、没有 MySQL/MariaDB 二进制（协议接线已用假服务器验过） |
| 无扩展 | `FR-DIAG-03` 慢查询排行 | 本机 pgserver 精简构建**没有扩展目录**，`pg_stat_statements` 装不上 |
| 沙箱限制 | `FR-CONN-18` SSH 隧道、`FR-IO-04` 备份恢复 | 沙箱下不能起子进程；放宽与否**待需求提出者拍板** |
| vendor 未实现 | `FR-IO-02` `COPY … TO STDOUT`、`FR-DATA-05` 的 bytea 显示 | 需改 vendored 驱动，有回归风险，单列排期 |
| 需 217 现场 | **（本行已于 2026-09-28 循环 L-62 按实测修订）** 原列六项：对象 DDL / 流式导出 / 表结构索引外键 / 数据库统计 / 服务器对象 / 维护任务。**实测**：前三项对应的四条脚本（`test-object-ddl` / `test-cursor-export` / `test-table-index-fk` / `test-table-structure`）**已改走共用入口 ⇒ 本机档实跑全绿并进 alpha 主链本机段**（不再是「需 217 现场」）；后三项**本来就有本机档**（数据库统计 / 服务器对象在 `Scripts/run-real-db-evidence.sh` 的 `session` 档、维护任务在 alpha 主链本机段）⇒ 原行把它们算进来是**表述不准**。仍真正卡 217 / 实例的见上四行（无实例 / 无扩展 / 沙箱限制 / vendor 未实现）与「基线既定红」那一行 | ~~217 的 `pg_hba.conf` 未放行本机（`28000`），需 DBA 加一行~~ → 修订后**只剩上四行**才需要环境；本行不再单列 |
| 基线既定红 | `object-search` / `session-management` / `schema-diff` | 实测即红且原因已登记在 `Scripts/real-db-evidence-baseline.json`，转绿要点名 |
| 需求侧缺口 | NFR ⬜ 2 条、AC ⬜ 4 条 | 见 `Docs/需求规范书.md` §10 索引，alpha 后处理 |

**状态口径**：以上条目在需求书里仍是 🟡，**不改成 ✅**（`v3.252` 给其中 6 条打了 `**[alpha 不含]**` 标注）—— 只把「未验证」与「已验」分开，不假装已验。

## 三、怎么装怎么跑

```bash
cd ~/.dsh/projects/DoyahStudio
./Scripts/build-app.sh                 # 沙箱构建（默认）→ dist/DoyahStudio.app
DOYAH_NO_SANDBOX=1 ./Scripts/build-app.sh   # 本机自用非沙箱构建
open dist/DoyahStudio.app
```

**许可证**（三档呈现）：沙箱构建的数据目录在容器里，许可证要放这里 ——
`~/Library/Containers/studio.doyah.DoyahStudio/Data/Library/Application Support/DoyahStudio/license.doyahlicense`
（非沙箱构建则是 `~/Library/Application Support/DoyahStudio/license.doyahlicense`）。
换档一行命令：`bash ~/.doyah-license/换档.sh ultra|pro|standard|tampered|none`，再点菜单「Doyah Studio → 版本与许可证…」→「重新读取许可证」（不用重启）。
**没放许可证 = Standard（只剩笔记）**，这是设计行为。自查：`tail -3 <数据目录>/startup.log`。

## 四、证据在哪

| 证据 | 命令 / 位置 |
| --- | --- |
| alpha 主链（本机段 + 预期红 + 环境段） | `./Scripts/alpha-main-chain.sh` → `.build/alpha-0.1.0/主链证据.md` |
| 工程闭环（18 项） | `./Scripts/verify-all.sh` |
| Core 单测 | `swift test`（Core 2000+ 项） |
| 需求完成度（机械派生） | `python3 Scripts/report-requirements.py`（DB 域 FR 139 条：✅97 / 🟡42 / ⬜0） |
| 人工点验清单 | `Docs/design/待人工验收清单.md`（已关：许可证 Standard 档、`R-60` 中性归因） |

## 五、已知问题

- 沙箱构建下 `^C` 打断前台作业不可靠（属分发路线，不算缺陷）
- 沙箱构建看不到 `~/.ssh` 之外的路径，SSH 隧道只在非沙箱构建可用
- 许可证篡改会降级到 Standard（设计如此，笔记数据不锁）
- `Docs/design/开发循环-任务队列.md` 与 spec 台账是**本机文件**（gitignore），不入库

## 六、下一步

1. 工作区模块补到与数据库模块同等程度（**优先级 高**，`FR-EDIT-32/35/36`）
2. 把本版「明确不含」的 6 类逐条转正：GBase/MySQL 实例、`pg_stat_statements`、沙箱放宽（等你拍板）、vendor 两处
3. 收清 🟡 里剩下的验收类条目（人工点验清单）
