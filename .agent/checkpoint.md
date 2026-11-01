# 检查点

- 队列：`.agent/batches.yaml`（**1 批 / 3 条待办**，2026-11-02 B6 收口后 `plan-batches.py --write` 重出；B7 起头）
- 已完成：**31 / 35**（`B1` 四条 + `B2` 四条 + `B3` 四条 + `B4` 四条 + `B5` 六条 + `B6` 五条：DATA-002 / DATA-005 / DATA-006 / DDL-003 / DDL-004）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：`B7` 连接与驱动**（`FR-STD-DB-CONN-012` 连接分组 · `CONN-020` SSH 隧道 · `DRV-009` GBase 8a 驱动；出口 = 3 行两列全 ✅，SSH 隧道允许只落「本机无跳板机」的如实未知）
  - `B6` 证据：`.agent/evidence/2026-11-02-B6.md`；`B5` 两片 `2026-11-02-B5.md` / `2026-11-01-B5.md`；`B4` 在 `2026-11-01-B4.md`；`B3` / `B2` / `B1` 各自同日文件
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh` ⇒ **5065 例 / 13 skipped / 0 失败** · `verify-ui-interactions.sh` ⇒ **115 条全绿 / 无跳过 / 源锚点全在**（106 → 115）· 文档门禁五道 rc=0（`check-doc-tables` 74 文件 / `check-doc-numbers` 三向一致 / `check-plan-coverage` / `check-status-consistency` 471 条 / `check-version-scope`）
- **本跳是「接手续跑」**：B6 的实现面由上一跳（PID 43753，做完未提交即退出，锁陈旧 75 分钟后被接管）留在工作区；本跳做的事 = 逐条核盘 + 补 `AGENT-SPEC.md:236` 里陈旧的 5059（`check-doc-numbers` 判红处）+ 三段反例复跑 + 证据与本片提交
- **B6 两条口径**：① **不许猜列类型** —— `TableDesignChangeSet.statements` / `createTablePlan` 对空类型整批拒绝，`TableDesign.blankColumn()` 不预填 `text`（原先写死，会生成 `ALTER TABLE t ALTER COLUMN c TYPE ;`）；② 外键跳转入口**存在元数据才露**（`ForeignKeyNavigation.entryVisible` 一处判定 + `AppState.ensureForeignKeyColumns` 缓存），不再给一个点下去只说「这一列没有外键」的菜单项
- **B6 反例三段（本跳真跑）**：去掉 `hasExplicitType` 守卫 ⇒ 2 红 · `blankColumn` 预填 `text` ⇒ 3 红 · 外键元数据不落缓存 ⇒ 1 红；还原后 `shasum` 逐字节一致（`TableDesign.swift` 71c6f07c… · `AppState.swift` 9456a4a9…），三套 23 tests / 0 failures
- 覆盖边界（本片）：**217 真库 0 次**（无 217 可达连接 ⇒ 真读数记「未知」）· 真鼠标点一次右键菜单由人承担 · 版面归快照层
- 存量红（不是本跳引入）：`check-core-localization.py` 38 项 · `check-format-arguments.py` 20 条 · `check-doc-layout.py` 18 条 · `run-manual-verification-probes.sh` 无 filter 整条 8 失败
