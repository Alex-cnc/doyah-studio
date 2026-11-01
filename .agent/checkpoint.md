# 检查点

- 队列：`.agent/batches.yaml`（7 批 / **29 条待办**，源自台账 35 条未闭 DB 行，2026-11-01 重出；`plan-batches.py --check` 已过）
- 已完成：**6 / 35**
- **下一批：`B1` 余 2 条**（`FR-STD-DB-TASK-002` 高危审批 / `FR-STD-DB-META-006` 对象树下钻重试）
  - `FR-STD-DB-TASK-003`（回执页三枚动作）证据 `.agent/evidence/2026-11-01-B1-TASK-003.md`
  - `FR-STD-DB-TASK-001`（工具栏「任务」菜单：`Core/SQLTaskMenuPlan` + `SQLTaskAppKitMenu` + 6 例探针）证据 `.agent/evidence/2026-11-01-B1-TASK-001.md`
  - `FR-STD-DB-IO-002`（整表 / 整库导出真落文件：假 `DatabaseService` + 真 `streamTable` + 5 例探针；**顺带修掉空表落空文件那个真缺陷**）证据 `.agent/evidence/2026-11-01-B1-IO-002.md`
  - **下一跳先做的事**：剩下两条的入口**还是 SwiftUI 控件** ⇒ 离屏里点不到 —— `TASK-002` 的审批单两枚动作（`DialogActionButton` = SwiftUI `Button`）、`META-006` 的「重试」文字按钮；都先按 `PanelIconButton` / `SQLTaskMenuButton` 的办法换真 AppKit 控件，再按「真点击 → 判 `AppState` 状态」的办法量
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳提交：见 `.agent/evidence/2026-11-01-B1-TASK-001.md` 与 `.agent/evidence/2026-11-01-B1-IO-002.md`
- 本跳读数：`verify-ui-interactions.sh` **53 条全绿 / 无跳过 / 源锚点全在**（42 → 53，本跳两片各 6 / 5 例）；`swift test` **5059 例 / 0 失败**（13 skipped = 端上探针默认 XCTSkip）；九道文档门禁 rc=0（含 `check-version-scope`）
- 覆盖边界（本跳两片）：TASK-001 不真弹菜单 · 保存表单字段归 `SQLTaskDefinitionTests`；IO-002 保存面板 / 选目录面板没点 · 不是真数据库 · 内存峰值不断言 · 敏感列口径待主人拍板
- 一条判不红的（如实登记）：IO-002 去掉 `writer?.abort()` 判不红 —— `ResultStreamWriter.deinit` 也清临时文件，探针分不出是谁清的
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改了 App 源码，`dist/` 未重建）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
