# 检查点

- 队列：`.agent/batches.yaml`（**3 批 / 9 条待办**，2026-11-01 B5 前半收口后 `plan-batches.py --write` 重出；B5 只剩 `DIAG-006`）
- 已完成：**25 / 35**（`B1` 四条 + `B2` 四条 + `B3` 四条 + `B4` 四条 + **`B5` 五条：SESS-002 / SESS-003 / SESS-004 / DIAG-003 / DIAG-004**）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；层级映射由 `Tests/MetadataServiceTests` 5 例判，判据列留 🟡 不冒充 ✅。next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：`B5` 余项 `FR-STD-DB-DIAG-006`**（连接上下文里的诊断入口 —— 需求书 §3.4 原文有定义，台账目标列仍是 `—`，先补定义行再判：① 对象树右键可唤起且上下文自动带入；② 结论里的对象名可点击跳到对应节点；③ 无统计读数时明说「未取到」，不编）
  - `B5` 证据：`.agent/evidence/2026-11-01-B5.md`（`B4` 那份在 `2026-11-01-B4.md`；`B3` 在 `2026-11-01-B3.md`；`B2` 在 `2026-11-01-B2.md`；前四片 `-B1-*.md`）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`swift test --filter SessionDiagnosticsProbeTests` ⇒ **Executed 13 tests, 0 failures**；`verify-core.sh` **5059 例 / 13 skipped / 0 失败** · `verify-ui-interactions.sh` **98 条全绿 / 无跳过 / 源锚点全在**（85 → 98）；文档门禁七道 rc=0（`check-doc-layout` 仍 18 条存量）
- **本跳新增**：`TestsUISnapshot/SessionDiagnosticsProbeTests` **13 例**，覆盖五个面从「界面按下去」到「语句真的发出去」：会话列表（1 条查询 / 等待优先排序 / 无 pid 行丢弃）· 取消语句发 `pg_cancel_backend`（不是 terminate）· 终止自己的会话在发之前拒 · 服务端 `false` 如实报拒 · 服务器级对象三类各一条查询且写入语句逐字等于预览 · 只读连接发之前拒 · 统计面板四类各一条查询且零扫描给 `nil` 不是 0% · 慢查询三档排序 / 主版本选列名 / 缺扩展给安装步骤且不发查询 / 非 PG 直说 / 点一行只回填不执行
- **本跳新开的一处注入缝**（生产默认不变）：`AppState.serviceOverride` —— 五个只读面都从 `ensureService` 取服务，一处口子即可全部量到；命中时仍走同一收口（`serverInfos` 照样落版本），慢查询按主版本选列名因此也是真判
- **本跳新增的界面**：`App/Views/SlowQueryPanel.swift`（`DIAG-003` 之前**连界面都没有**，Core 逻辑只在诊断取证里用）+ 菜单与 ⌘K 入口 + 16 个语言键中英齐
- **本跳反例三段**（各判红后 `sha256` 逐字节还原）：`.cancel` 接成 terminate（4 红）· 列名写死 13+（2 红）· 扩展没装也当空排行（1 红）
- 覆盖边界（本片）：**217 真库 0 次**（`192.168.5.217:5432` 连接超时 ⇒ 会话 / 统计 / 慢查询真读数记「未知」）· **`pg_stat_statements` 真排行 0 次**（本机 pgserver 无扩展目录，装不上）· 面板版面与按钮灰显归快照层 · 真鼠标点一行由人承担
- 存量红（不是本跳引入）：`run-manual-verification-probes.sh` 无 filter 的整条 **8 失败 / 3 skipped / exit 1**（5 个用例：PaletteWiring 的 note 命令没登记落点 · RetroHost 判「2 包」而 `~/.dsh` 下已 5 包 · Notes 侧 3 例版面 / 保存态；**单独跑也红，与本批无关**）· `check-release-version.py` 报 10 处（xcodeproj 过期 / `dist/` 旧包 / `Docs/发布方案.md` 缺）· `check-shell-locale-safety.py` 报 `Scripts/hooks/install.sh:17` 一处裸 `$SRC`（不是本批文件）· `Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
