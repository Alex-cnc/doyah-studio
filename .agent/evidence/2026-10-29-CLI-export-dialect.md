# R72 · CLI `export` 的方言判（`FR-STD-DB-IO-002` 收尾片）

- 日期：2026-10-29（第七十二批）· 仓库：`/Users/alex/dev/doyah/lead/studio` · 提交：见本节末「提交」
- 由头：R71 收尾时排下的下一条活「CLI `export` 的方言判」（每轮卡「下一条活 ①」）

## 1. 先核源码：记录里那句有一半不成立

| 记录里的说法 | 实测 | 结论 |
| --- | --- | --- |
| 「`--export` 在 MySQL / GBase 连接上也进得去」 | `CLI/main.swift:241` 的 `ConnectionConfig` 把 `dbType` 写成 `.postgresql`；`mysql` / `gbase8a` 子命令（`CLI/main.swift:197`）只认 `--sql` / `--json` | **走不到** MySQL：导出这条路今天只有 PG 入口 ⇒ 这句话要纠正 |
| 「方言钉死 `PostgresDialect()`」 | `CLI/main.swift:426`（旧）`dialect: PostgresDialect()`；`tableSelect` / `exportAllTables` / `exportQueryToFile` 三个入参都是具体类型 | 成立 |
| 「非 PG 连接会拼出 PG 语句」 | `CursorPaging` 只出 `BEGIN` / `DECLARE … CURSOR` / `FETCH FORWARD` / `CLOSE`；`TableExport.streamingSupported` 早就写着「只有 PG」 | 成立（潜伏缺陷：一旦接上非 PG 入口就中招） |
| `doyah mysql --export …` | 旧行为 = `--export` **被静默忽略**，rc=0、没有任何文件 | 成立（更该修：看起来成功的空操作） |

## 2. 改动面

- `Core/TableExport.swift`：新增 `StreamingDecision`（`.streaming` / `.rejected(Issue)`）与 `decision(for:)`；`streamingSupported(_:)` 改为它的投影（**一处口径**，GUI 与 CLI 同读）。
- `CLI/main.swift`
  - 导出出口把 `dbType: config.dbType` 交给命令（不再钉方言字面量）；
  - `runExportCommand(…, dbType:)`：`SQLDialectFactory.make(for: dbType)` 派生方言 + `TableExport.decision` 裁定，**在任何动作之前**判红并 `return 69`；
  - `tableSelect` / `exportAllTables` / `exportQueryToFile` 的方言入参 `PostgresDialect` → `any SQLDialect`；
  - `exportDialectMessage(_:)`：唯一一句话（缺服务端游标 / 一条语句都没发出去 / 今天可走 `mysql --sql … --json`）；
  - `runMySQLCommand`：**建连接之前**用同一句话拒绝 `--export` / `export`。
- `Tests/TableExportTests.swift` +7 · `Tests/CLIExportDialectSourceTests.swift` 7（新文件，源树判据）。

## 3. 读数

```
./Scripts/verify-core.sh                          → rc=0 · Executed 4936 tests, with 12 tests skipped and 0 failures
                                                     （.build/core-test-count.txt = 4936 tests；上一批 4922 → +14）
check-doc-numbers.py / check-doc-tables.py /
check-doc-versions.py / check-doc-invariants.py /
check-version-scope.py                            → rc=0 / 0 / 0 / 0 / 0
xcodegen generate                                 → rc=0
bash Scripts/build-app.sh                          → rc=0 · 包 be96b836f99fef817885663e95fdd45bbe1a88d8bc628df8b28bfdbd571421da
                                                     标签 beta1.0 · 构建时刻 2026-10-29T09:04:34+0800 · 102,922,608 字节
```

## 4. 反例（每条新判据都能判红，改坏后逐字节还原）

| 段 | 改坏的那一处 | 判红的用例 | 读数 |
| --- | --- | --- | --- |
| A | `decision` 一律返回 `.streaming` | `testDecisionRejectsMySQLWithItsOwnType` | rc=1 · 1 test / 2 failures |
| B | GBase 被当成 MySQL（`.rejected(.streamingUnsupported(.mysql))`） | `testRejectedDecisionsKeepTheTwoNonPostgresTypesApart` | rc=1 · 1 test / 1 failure |
| C | `streamingSupported` 自己再算一份（`dbType != .gbase8a`） | `testStreamingSupportedIsTheProjectionOfDecision` | rc=1 · 1 test / 1 failure |
| D | 限定名不按方言引号（硬写双引号） | `testDialectFollowsTheConnectionType` | rc=1 · 1 test / 2 failures |
| E | 出口把类型钉回字面量（`dbType: .postgresql`） | `testExportEntryPassesTheConnectionType` | rc=1 · 1 test / 1 failure |
| F | 删掉命令里的裁定（挪到动手之后） | `testTheGateRunsBeforeAnyWork` | rc=1 · 1 test / 1 failure |
| G | 删掉 `mysql` 子命令的拒绝 | `testMySQLSubcommandRefusesExportBeforeConnecting` | rc=1 · 1 test / 1 failure |

七段各自 `git checkout` 前先备份字节、还原后 sha256 与改前一致（脚本 `/Users/alex/.hermes/cache/scratch/r72_counterexamples.py`，段 E 因第一次锚点缩进不匹配单独重跑过一次）。
⚠️ 自记一笔：第一次跑段 E 时把 `dbType: config.dbType` 换成 `dialect: PostgresDialect()`，那是**编译错误**（不是判据抓到的），脚本在打印时抛异常、未走到还原那一步 ⇒ 手工改回后再用「钉字面量」这一版跑（能编译、由判据判红）。教训：反例要选**能编译**的改坏方式，且还原必须放 `finally`。

## 5. 端到端实测（真二进制，不连库）

```
$ ./.build/debug/DoyahCLI mysql --export --out /tmp/r72-export-probe/m.csv --host 127.0.0.1 --user root
MySQL 连接没有服务端游标（DECLARE / FETCH / CLOSE 是 PostgreSQL 语义），导出（--query / --table / --all-tables）今天只在 PostgreSQL 上可用。
这条命令一条语句都没有发出去，目标库没有任何改动。替代：先用 `mysql --sql "SELECT …" --json` 把结果取回来，再自行落盘。
rc=69
$ ./.build/debug/DoyahCLI gbase8a export --out /tmp/r72-export-probe/g.csv
GBase 8a 连接没有服务端游标（…同上…）
rc=69
$ ./.build/debug/DoyahCLI mysql --sql 'select 1'          # 反向对照：不带 --export 时行为不变
用法：mysql --connection <已保存连接名> 或 --host <h> … --json
rc=2
$ ls -A /tmp/r72-export-probe | wc -l
0
```

## 6. 未验证 / 已知边界（如实记）

- **PG 那一侧的导出没有重跑**：本轮改的是「方言怎么来」与「非 PG 怎么拒」，PG 路线的取数语义一个字没动；真跑要一台库（本机无），沿用 R69/R70 的真机读数（12 万行 / 27 MB，见需求规格 R-036）。
- **`check-format-arguments.py` 是存量红**（不在五门里，但收尾会看）：HEAD 干净树复跑同样红（`200 / 预算 188`、`<reason> 18 / max 17`、`<path> 3 / max 2`，13 条）⇒ 与本报无关，已登记进每轮卡「存量红」那一段。
- CLI 的 `export` 仍**只对 PG 开放**（MySQL / GBase 的替代路径是 `--sql` 取数）。要在那两家做流式导出得先有游标替代方案（新活，属另开一条）。
