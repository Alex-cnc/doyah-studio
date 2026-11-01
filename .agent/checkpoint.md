# 检查点

- 队列：`.agent/batches.yaml`（**2 批 / 8 条待办**，2026-11-02 B5 收口后 `plan-batches.py --write` 重出；B6 起头）
- 已完成：**26 / 35**（`B1` 四条 + `B2` 四条 + `B3` 四条 + `B4` 四条 + `B5` 六条：SESS-002 / SESS-003 / SESS-004 / DIAG-003 / DIAG-004 / **DIAG-006**）
- 阻塞：**1**（`FR-STD-DB-META-002` GBase 8a 树形结构 —— 本机无 GBase 8a 实例 ⇒ 端到端 0 次；next_try = 拿到 GBase 8a 测试实例后补端到端）
- **下一批：`B6` 数据编辑与表结构**（`FR-STD-DB-DATA-002` count(*) · `DATA-005` 单元格编辑器 · `DATA-006` 外键导航 · `DDL-003` 结构编辑器 · `DDL-004` Schema 对比；出口 = 5 行两列全 ✅，DDL 生成用例含「不许猜列类型」反例）
  - `B5` 证据：`.agent/evidence/2026-11-02-B5.md`（DIAG-006）；前一片 `2026-11-01-B5.md`（SESS-002/003/004 · DIAG-003/004）；`B4` 在 `2026-11-01-B4.md`；`B3` / `B2` / `B1` 各自同日文件
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`swift test --filter ObjectDiagnosisProbeTests` ⇒ **Executed 8 tests, 0 failures**；`verify-core.sh` **5059 例 / 13 skipped / 0 失败** · `verify-ui-interactions.sh` **106 条全绿 / 无跳过 / 源锚点全在**（98 → 106）；文档门禁七道 rc=0（`check-core-localization` 38 项 / `check-format-arguments` 20 条 / `check-doc-layout` 18 条仍存量红）
- **本跳新增**：`Core/DiagnosisScope.swift`（连接上下文收成一个值：连接 / 库 / 对象 / 最近一次执行读数 + 按对象类型的统计查询 + 取证计划）· `Core/DiagnosisObjectLinks.swift`（长名优先 + 词边界的切段，`doyah-object://` 身份链接）· `App/Views/DiagnosisLinkedText.swift`（`AttributedString` + `OpenURLAction`，不弹浏览器）· `TestsUISnapshot/ObjectDiagnosisProbeTests` **8 例**
- **本跳接线**：`AppState.beginObjectDiagnosis` 一处带入上下文 + `jumpToDiagnosisObject` 发一次性跳转请求；两套右键菜单（AppKit / SwiftUI）都加「诊断这个对象…」；`ObjectTreeView` 收请求后逐级展开并选中（找不到如实报）；`DiagnosisPanel` 加上下文区 + 结论改可点
- **本跳的两条口径**：① 对象诊断**不塞整实例的锁查询**（`pg_locks` 挂在这张表下会被读成「这张表在等锁」）；② 「被拒 / 未发出」的那一跑**不算执行读数**（`LastExecution(receipt:)` 只认 succeeded / failed）
- **本跳反例三段**（各判红后 `shasum` 逐字节还原）：统计不按对象收窄（2 红）· 去掉词边界（1 红）· 被拒的那一跑当成执行读数（1 红）
- 覆盖边界（本片）：**217 真库 0 次**（连接超时 ⇒ 统计 / 最近一次执行的真读数记「未知」）· 真鼠标点一下结论里的链接由人承担 · 树展开后的版面归快照层
- 存量红（不是本跳引入）：`check-core-localization.py` 38 项（基线 101 文件 / 954 行本身通过，棘轮 B 的英文展示文案）· `check-format-arguments.py` 20 条（tableExport* / ResultPager，本批未触）· `check-doc-layout.py` 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）· `run-manual-verification-probes.sh` 无 filter 整条 8 失败（与本批无关）
