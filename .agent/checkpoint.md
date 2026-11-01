# 检查点

- 队列：`.agent/plan.yaml`（35 项，源自台账 35 条未闭 DB 行，2026-11-01 生成）
- 已完成：2 / 35
- **下一项：`FR-STD-DB-RES-008`**（结果面·客户端筛选：每列可加条件 —— 包含 / 不包含 / 等于 / 大于 / 小于 / 为空；Core 侧 `ResultFilter` 已有规则与单测，缺口同 007：界面点击与筛选条一次都没量过）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）已落盘
- 本跳完成：`FR-STD-DB-RES-007`（客户端排序）—— 台账两列双 ✅，证据 `.agent/evidence/2026-11-01-FR-STD-DB-RES-007.md`
  - 同批修两处真缺陷：Shift 加次要键认错列（读 `sortDescriptors.first`）· 取消排序后表格不重载（首末行摘要）
  - `verify-ui-interactions.sh` 现 **29 条**（六批）全绿 / 无跳过 / 源锚点全在；全量单测 `Executed 5054 tests … 0 failures`（13 条 skipped = 端上探针默认 XCTSkip）
- 未验证：无
- 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改 Core/App 源码与探针，没有重建 `dist/`；下跳若要求出包需补）
