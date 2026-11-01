# 检查点

- 队列：`.agent/batches.yaml`（**5 批 / 23 条待办**，源自台账未闭 DB 行，2026-11-01 重出；`plan-batches.py --check` 已过）
- 已完成：**12 / 35**（`B1` 四条 + `B2` 四条全收口：TASK-001 / TASK-002 / TASK-003 / IO-002、RES-006 / 007 / 008 / **009 / 011 / 013 / 014**、META-006）
- **下一批：`B3 元数据面`**（`FR-STD-DB-META-002` 树形结构 / `META-007` 跨库浏览 / `META-008` 分组视图 / `META-011` 查看 DDL / `META-015` 全库对象搜索）
  - `B2` 四条证据同一份 `.agent/evidence/2026-11-01-B2.md`
  - 前四片证据：`.agent/evidence/2026-11-01-B1-TASK-002-META-006.md`（TASK-002 / META-006）· `-B1-TASK-001.md` · `-B1-TASK-003.md` · `-B1-IO-002.md`
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳读数：`verify-ui-interactions.sh` **76 条全绿 / 无跳过 / 源锚点全在**（62 → 76，本片 7 + 3 + 4 例）；`swift test` **5059 例 / 0 失败**（Core 桶；13 skipped = 端上探针默认 XCTSkip —— 那 76 条挂在 `DoyahUISnapshotTests` 桶里，不进 5059）；文档门禁七道 rc=0
- **本跳的结构改动**：① 分页条整条 SwiftUI → AppKit（`ResultPagerControlsView`：`NSPopUpButton` + 四枚 `NSButton` + 两句 `NSTextField`），档位清单收进 `Core/ResultView.pageSizeChoices`，标注键 `resultPageClientOnlyNote`；② `AppState.exportResultStreaming` 拆出可注入 `service:` / `dialect:` 的**唯一落地口** + `onReport:` 交写盘读数（与 `streamTable` 同一口径）
- **本跳抓出的存量红**（不是本批引入）：`AgentApprovalDecisionProbeTests.testTheSheetUsesThatRowAndWiring` 与源锚点里「审批单里要有 `AgentApprovalDecisionRow(`」—— 上一片把那一行收进 `AgentApprovalDecisionWiring` 之后，这条钉钉的是**旧形状**，成了永远判红；已改成反向钉（审批单**不许**自己拼那一行）并同批复绿。**上一跳报的「62 条全绿」因此是漏跑的读数**（那一跳只跑了 `swift test` 与文档门禁）
- 覆盖边界（本片）：真鼠标手感 / 掉帧归人工 · Excel / Numbers / WPS 真打开 xlsx 归人工 · 真库游标语义与 12 万行内存峰值归 R-036 已记的 CLI 实测 · 分页是**客户端**分页、压根不发语句
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改了 App 源码，`dist/` 未重建）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
