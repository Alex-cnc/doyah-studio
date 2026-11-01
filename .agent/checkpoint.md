# 检查点

- 队列：`.agent/plan.yaml`（35 项，源自台账 35 条未闭 DB 行，2026-11-01 生成）
- 已完成：3 / 35
- **下一项：`FR-STD-DB-RES-009`**（结果面·分页控制条：每页行数 50 / 100 / 200 / 500 / 1000；Core 的 `ResultGridState.setPageSize` 与 `ResultPage` 已有单测，缺口同 007 / 008：界面点击一次都没量过 —— 分页条上的控件同样要先确认是「真控件」才量得到）
- 底座：`Scripts/ledger-row.py`（所有 done_when 共用）已落盘
- 本跳完成：`FR-STD-DB-RES-008`（客户端筛选）—— 台账两列双 ✅，证据 `.agent/evidence/2026-11-01-FR-STD-DB-RES-008.md`
  - 同批修两处真缺陷：筛选条只在 `isClientViewActive` 时才渲染（「+ 加条件」入口成死路）· 点「+」当场清空整张表（`contains ""` 不匹配任何行）
  - 列 / 运算符从 SwiftUI `Menu` 换成真 `NSPopUpButton`（`Menu` 的菜单项只在弹出那一刻才建，探针量不到）
  - `verify-ui-interactions.sh` 现 **35 条**（七批）全绿 / 无跳过 / 源锚点全在；全量单测 `Executed 5059 tests … 0 failures`（13 条 skipped = 端上探针默认 XCTSkip）；八道文档门禁全 rc=0
- 未验证：无
- 未执行（≠ 通过）：`Scripts/build-app.sh` 出包（本跳改 App/Core 源码与探针，没有重建 `dist/`；下跳若要求出包需补）
- 覆盖边界（008）：真鼠标点开菜单的弹出动画 / 拖选文本证不住；条右侧「清空全部条件 / 生成 WHERE」两颗仍是 SwiftUI `.plain` 按钮，点击量不到（规则有 Core 单测）
