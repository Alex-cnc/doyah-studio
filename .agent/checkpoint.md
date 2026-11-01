# 检查点

- 队列：`.agent/batches.yaml`（**3 批 / 14 条待办**，2026-11-01 B4 收口后重出；`plan-batches.py --write` 已过）
- 已完成：**20 / 35**（`B1` 四条 + `B2` 四条 + `B3` 四条 + **`B4` 四条：IO-003 / IO-004 / IO-006 / IO-007**）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；层级映射由 `Tests/MetadataServiceTests` 5 例判，判据列留 🟡 不冒充 ✅。next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：`B5 会话与诊断`**（`SESS-002` 会话列表 · `SESS-003` 取消 / 终止 · `SESS-004` 服务器级对象 · `DIAG-003` 慢查询 · `DIAG-004` 统计面板 · `DIAG-006` 待补定义）
  - `B4` 证据：`.agent/evidence/2026-11-01-B4.md`（`B3` 那份在 `2026-11-01-B3.md`；`B2` 在 `2026-11-01-B2.md`；前四片 `-B1-*.md`）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`swift test --filter BackupRestoreImportProbeTests` ⇒ **Executed 9 tests, 0 failures**；`run-manual-verification-probes.sh` **两遍各 9 例 / 0 失败 / 0 跳过**；`verify-core.sh` **5059 例 / 13 skipped / 0 失败** · `verify-ui-interactions.sh` **85 条全绿 / 无跳过 / 源锚点全在**（76 → 85，本批 9 例已接进这个入口）；四个真机脚本 `test-data-import.sh` / `test-copy-import.sh` / `test-xlsx-import.sh` 各 exit 0，`test-backup-restore.sh` §4 本机 16.2 往返全绿（§1/§3 的 217 段连接超时 ⇒ 记「未知」）；文档门禁八道 rc=0
- **本跳新增**：`TestsUISnapshot/BackupRestoreImportProbeTests` **9 例** —— 走生产入口 `runBackupPlan` / `runRestoreSections` / `startTableImport`，用假 `ExternalProcessRunner`（记 argv / 环境变量）与假 `DatabaseService`（记语句与 COPY 负载，负载用产品 `CopyTextFormat.unescape` 解回逐格比）；已接进 `run-manual-verification-probes.sh` 的 FILTER + 存在性核对
- **本跳新开的两处注入缝**（生产默认不变）：`AppState.backupRunner`、`AppState.importServiceOverride` —— 之前 `BackupExecutor()` 与 `ensureService()` 都写在方法体里，探针没处注入，这才是四条长期挂 🟡 的真因
- **本跳反例四段**（各判红后 `sha256` 逐字节还原）：`--format` → `--formats`（1 红）· 数据段失败后仍往下跑（6 红）· `SET search_path` 去掉方言引号（1 红）· xlsx 读丢一行（2 红）
- **同批修的存量红**：`Scripts/lib/test-env.sh` 的 `lsof` 在端口空着时退出码 1，被 `set -euo pipefail` 放大成**整个探针脚本 0 字节输出 / exit 1**（看着像「探针红了」，其实是那一行把脚本带走）⇒ 补 `|| true`
- 覆盖边界（本片）：GUI 侧真起 `pg_dump` / `pg_restore` 那一跳由 CLI 脚本判（同一份 `BackupExecutor`，只是 runner 不同）· 模态面板（保存 / 打开 / 选目录 / 二次确认）没点 · 面板里打字与列映射下拉不在探针内 · 真实软件产出的 xlsx 待人工 · **217 上的真实备份 / 还原记「未知」**（本轮 192.168.5.217:5432 连接超时）
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳只动了探针缝与探针，未重建 `dist/`）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`run-manual-verification-probes.sh` 无 filter 的整条 **8 失败 / 3 skipped / exit 1**（5 个用例：PaletteWiring 的 note 命令没登记落点 · RetroHost 判「2 包」而 `~/.dsh` 下已 5 包 · Notes 侧 3 例版面 / 保存态；**单独跑也红，与本批无关**）· `check-release-version.py` 报 10 处（xcodeproj 过期 / `dist/` 旧包 / `Docs/发布方案.md` 缺）· `check-shell-locale-safety.py` 报 `Scripts/hooks/install.sh:17` 一处裸 `$SRC`（不是本批文件）· `Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
