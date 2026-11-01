# 检查点

- 队列：`.agent/batches.yaml`（**0 条待办**，2026-11-02 B7 收口后 `plan-batches.py --write` 重出）；`plan.yaml` = 34 done + 1 blocked
- 已完成：**34 / 35**（B1–B7 七批；最后一批 = `CONN-012` 连接分组 / `CONN-020` SSH 隧道 / `DRV-009` GBase 8a 驱动）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：无**（队列已空 ⇒ 本批即收口；`META-002` 仍 blocked，等实例）
- `B7` 证据：`.agent/evidence/2026-11-02-B7.md`；`B6` 证据 `2026-11-02-B6.md`；`B5` 两片 `2026-11-02-B5.md` / `2026-11-01-B5.md`；`B4` 在 `2026-11-01-B4.md`；`B3` / `B2` / `B1` 各自同日文件
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh` ⇒ **5078 例 / 13 skipped / 0 失败**（+13 = 隧道归因 5 · 接线锚点 4 · 运行时 4）· `verify-ui-interactions.sh` ⇒ **116 条全绿 / 无跳过 / 源锚点全在**（115 → 116）· `test-mysql-driver.sh` ⇒ 8 段全 ✅ · 文档门禁五道 rc=0（`check-doc-tables` 74 文件 / `check-doc-numbers` 三向一致 5078 / `check-plan-coverage` 471 / `check-status-consistency` 471 / `check-version-scope`）
- **B7 三件真改动**：① `CONN-012` 的探针（折叠状态活过活动栏切换）一直**没接进** `verify-ui-interactions.sh`（115 条里 0 条）⇒ 接进去，判据才每批真跑；② `CONN-020` 判据 ② 有真缺口 —— 隧道断了只报「连接已断开」，新增 `Core/SSHTunnelDiagnosis`（只有「配了隧道 + 隧道真死」才归因）+ `SSHTunnelProcess.markDeadIfExited`（`ssh` 被外部杀掉时状态停在 `.ready` 的洞）+ `AppState.tunnelAwareMessage`（先改判 → 再归因 → 再作废这条连接）；③ `DRV-009` 用假 MySQL 服务器真跑线协议（第 8 段专判 GBase 档五条读数）
- **同批修一处派生脚本的读数错**：`Scripts/plan-batches.py` 把 `blocked` 也算进「已收口 N 条」（`s != "todo"`）⇒ 队列空时会把 `META-002` 说成已收口；改成只数 `done`，blocked 单列
- 覆盖边界（本片）：真跳板机握手 0 次 · 真 GBase 8a 实例 0 次 · 217 真库 0 次 ⇒ 三处记「未知」，不是「通过」；真鼠标点分组三角 / 真跳板机联调由人承担
- 存量红（不是本跳引入）：`check-sidebar-collapse-state.py` 2 项（`App/Views/AgentChatView.swift` 的 `@State collapsedToolBlocks` 未登记豁免）· `test-sidebar-collapse-state.py` 夹具前提不成立（`ConnectionListView` 分组头改成 `ConnectionGroupHeader` 后夹具没跟）· `check-core-localization.py` 38 项 · `check-format-arguments.py` 20 条 · `check-doc-layout.py` 18 条 · `run-manual-verification-probes.sh` 无 filter 整条 8 失败
