# 检查点

- 队列：`.agent/batches.yaml`（**6 批 / 27 条待办**，源自台账未闭 DB 行，2026-11-01 重出；`plan-batches.py --check` 已过）
- 已完成：**8 / 35**（`B1` 四条全收口：TASK-001 / TASK-002 / TASK-003 / IO-002，外加 RES-006/007/008、META-006）
- **下一批：`B2 结果面收尾`**（`FR-STD-DB-RES-009` 分页控制条 / `RES-011` 分页与虚拟滚动 / `RES-013` 流式落盘 / `RES-014` 导出 xlsx）
  - `FR-STD-DB-TASK-002`（审批单两枚动作换真 `NSButton` + `AgentApprovalDecisionWiring` 一处接线 + `agentAuditLogOverride`）证据 `.agent/evidence/2026-11-01-B1-TASK-002-META-006.md`
  - `FR-STD-DB-META-006`（失败行与「重试」收进 `ObjectTreePlaceholderRow` + 两步收进 `Core/ObjectTreeRetry.apply`）同上
  - `FR-STD-DB-TASK-001` 证据 `.agent/evidence/2026-11-01-B1-TASK-001.md` · `FR-STD-DB-TASK-003` 证据 `.agent/evidence/2026-11-01-B1-TASK-003.md` · `FR-STD-DB-IO-002` 证据 `.agent/evidence/2026-11-01-B1-IO-002.md`
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`verify-ui-interactions.sh` **62 条全绿 / 无跳过 / 源锚点全在**（53 → 62，本片 4 + 5 例）；`swift test` **5059 例 / 0 失败**（13 skipped = 端上探针默认 XCTSkip）；文档门禁见提交信息
- **本跳抓出的坏判据**：源锚点字典里 `"App/AppState.swift"` 被登记两次（第八批 + 第十批）⇒ Python 静默丢掉先出现那份，第八批两条判据两批以来是死的；已合成一个键
- 覆盖边界（本片）：TASK-002 不是真数据库（「批准后按原序打上库」归 `run-manual-verification-probes.sh`）· 审批单本体不整张装宿主（要问优化器估影响面）· 逐条语句与行内红字读不出来（SwiftUI `Text` 不落 `NSTextField`）
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改了 App 源码，`dist/` 未重建）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
