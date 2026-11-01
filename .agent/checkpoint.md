# 检查点

- 队列：`.agent/batches.yaml`（7 批 / **30 条待办**，源自台账 35 条未闭 DB 行，2026-11-01 重出；`plan-batches.py --check` 已过）
- 已完成：**5 / 35**
- **下一批：`B1` 余 3 条**（`FR-STD-DB-TASK-002` 高危审批 / `FR-STD-DB-IO-002` 整表·整库导出 / `FR-STD-DB-META-006` 对象树下钻重试）
  - 第一片 `FR-STD-DB-TASK-003`（回执页三枚动作 + 复制 / 清空 / 导出全链），证据 `.agent/evidence/2026-11-01-B1-TASK-003.md`
  - 第二片 `FR-STD-DB-TASK-001`（工具栏「任务」菜单：`Core/SQLTaskMenuPlan` + `App/Views/SQLTaskAppKitMenu.swift` + 6 例探针），证据 `.agent/evidence/2026-11-01-B1-TASK-001.md`
  - **下一跳先做的事**（两片量到的同一类缺口）：剩下的入口**还是 SwiftUI 控件** ⇒ 离屏里点不到 —— `TASK-002` 的审批单两枚动作（`DialogActionButton` = SwiftUI `Button`）、`META-006` 的「重试」文字按钮，都得先按 `PanelIconButton` / `SQLTaskMenuButton` 的办法换真 AppKit 控件再量。`IO-002` 的入口是生产右键菜单（AppKit，已有探针），缺的是**真跑一次导出落文件** —— 本机无 PG，路子在「假 `DatabaseService` + 真 `streamTable` 写临时文件」（光标分页语句由假服务应答），不碰 217 真库
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生；台账一改先改 `.agent/plan.yaml` 的 status 再 `--write`）
- 本跳提交：见 `.agent/evidence/2026-11-01-B1-TASK-001.md`（代码 + 台账 + 队列 + 探针 + 证据）
- 本跳读数：`verify-ui-interactions.sh` **48 条全绿 / 无跳过 / 源锚点全在**（42 → 48）；`swift test` **5059 例 / 0 失败**（13 skipped = 端上探针默认 XCTSkip）；九道文档门禁 rc=0（含 `check-version-scope`）
- 覆盖边界（TASK-001）：不真弹菜单（`NSMenu.popUp` 模态，无人值守不该弹）· 保存表单字段与落盘归 `SQLTaskDefinitionTests` · 真鼠标点按钮那一跳由人承担
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（两片都改了 App 源码，`dist/` 未重建）；`Scripts/verify-all.sh` 全量未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` §14 交叉引用）
