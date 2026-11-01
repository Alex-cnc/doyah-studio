# 检查点

- 队列：`.agent/batches.yaml`（7 批 / 31 条待办，源自台账 35 条未闭 DB 行，2026-11-01 重出；`plan-batches.py --check` 已过）
- 已完成：**4 / 35**
- **下一批：`B1` 余 4 条**（`FR-STD-DB-TASK-001` 任务定义 / `FR-STD-DB-TASK-002` 高危审批 / `FR-STD-DB-IO-002` 整表·整库导出 / `FR-STD-DB-META-006` 对象树下钻重试）
  - 第一片已收口 `FR-STD-DB-TASK-003`（回执页三枚动作 + 复制 / 清空 / 导出全链），证据 `.agent/evidence/2026-11-01-B1-TASK-003.md`
  - **下一跳先做的事**（第一片量到的）：TASK-001 的工具栏「任务」菜单、TASK-002 的审批单、META-006 的「重试」文字按钮**都还是 SwiftUI 控件** ⇒ 离屏里点不到；收口前先按 `PanelIconButton` 的办法把入口换成真 AppKit 控件（TASK-003 已示范一次）。IO-002 的入口是生产右键菜单（AppKit，已有探针），缺的是「真跑一次导出落文件」（要真库 / 本机 PG 档）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）+ `Scripts/plan-batches.py`（批次派生）
- 本跳提交：见 `.agent/evidence/2026-11-01-B1-TASK-003.md`（代码 + 台账 + 队列 + 探针 + 证据）
- 本跳读数：`verify-ui-interactions.sh` **42 条全绿 / 无跳过 / 源锚点全在**（35 → 42）；`verify-core` **5059 例 / 0 失败**（13 skipped = 端上探针默认 XCTSkip）；八道文档门禁 rc=0
- 覆盖边界（TASK-003）：模态保存面板没点（由人承担）· 回执正文逐字判不到（SwiftUI `Text` 不落 `NSTextField`）· 真鼠标拖选不在验收要点里
- 未验证 / 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改了 App 源码，`dist/` 未重建）；`Scripts/verify-all.sh` 全量 18 项未跑
- 存量红（不是本跳引入）：`Scripts/check-doc-layout.py` 报三书自审 18 条（全在 `Docs/Doyah产品概要设计说明书.md` 的 §14 交叉引用解析不到）
