# 检查点

updated: 2026-10-29T04:52

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d`
  点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。**本会话无 `cronjob_manage` 工具** ⇒ 接力改用 CLI
  `hermes cron run e98fad41f72d`（同一效果：下一跳调度器拉起），详见 loop-card 的「节奏」段。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-29 **R58**）：`verify-core` **4746 项 / 0 failures**（4720 → +26 = `Tests/GitDiffRequestTests` 8 例
  + `Tests/GitDiffPresentationTests` 14 例 + `Tests/GitDiffPanelSourceTests` 4 例）；五门 rc 全 0；
  `check-format-arguments` 也回绿（同批把 R57 留下的 8 条真红修掉：回执四处模板串 → 值格式闭包）；
  包 `dist/DoyahStudio-beta1.0.app` sha256 **`2d2ad6b8`**（构建时刻 2026-10-29T04:40:27+0800；二进制 101,684,272 字节；
  同标签 04:20:28 那份 `eb3d368f` ⇒ 作废）。台账本条迁移：`FR-STD-WS-VCS-002` 实现 ⬜ → **🟡**
  （差人工点一次：忽略空白归零 / 上下文 40 行的折行与展开 / 上万行文件一屏不卡）、判据 ⬜ → **✅**（8 + 14 + 4 例）；
  分族读数 ⇒ ✅ 127 / 🟡 78 / ⬜ 8 = 213。
  ⚠️ 存量红六条已与基线 `874a3e48` 逐条对照确认「本循环未加重」（清单见 loop-card 的 R58 段）。
- 最近读数（2026-10-29 **R57**）：`verify-core` **4720 项 / 0 failures**（4691 → +29 = `Tests/ExecutionReceiptTests` 25 例
  + `Tests/ExecutionReceiptSourceTests` 4 例）；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`eb3d368f`**
  （构建时刻 2026-10-29T04:20:28+0800；二进制 101,402,080 字节；同标签 03:50:45 那份 `eb4400b1` ⇒ 作废）。
  台账本条迁移：`FR-STD-DB-TASK-003` 实现 ⬜ → **🟡**（差人工点一次：四项读数 / 报错语句也有回执 / 只读连接被拦下读「未发出」/ 复制与导出）、
  判据 ⬜ → **✅**（25 + 4 例）；分族读数三格按逐行实数重取 ⇒ ✅ 127 / 🟡 77 / ⬜ 9 = 213。
  同批修红一条：`Scripts/empty-action-button-dispositions.json` 的 `saveCurrentQuery` 视图锚点（第五十批改形后没跟版）。
- 最近读数（2026-10-29 **R56**）：`verify-core` **4691 项 / 0 failures**（4678 → +13 = `Tests/TextFileFormatTests` 10 例
  + `Tests/TextFileFormatSourceTests` 3 例）；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`eb4400b1`**
  （构建时刻 2026-10-29T03:50:45+0800；二进制 101,083,184 字节；同标签 03:50:18 那份 `5b394798` 出在写发布说明之前 ⇒ 作废）。
  台账本条迁移：`FR-STD-WS-EDIT-023` 实现 ⬜ → **🟡**（差人工点一次：CRLF 文件的状态栏读数 / 改一行保存后 `git diff` 只一行 /
  切到 GB18030 保存后文件仍是 GB18030）、判据 ⬜ → **✅**（10 + 3 例）。分族读数三格按逐行实数重取 ⇒ ✅ 127 / 🟡 76 / ⬜ 10 = 213。
  同批修红一条：`Scripts/check-language-registry.py` 补登记 R55 新增的 `Core/CodeFolding.swift`（该门禁自 R55 起一直红着）。
- 上一轮读数（2026-10-29 **R55**）：`verify-core` **4678 项 / 0 failures**（4644 → +34 = `Tests/CodeFoldingTests` 28 例
  + `Tests/CodeFoldingSourceTests` 6 例）；五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`8b9e7517`**
  （构建时刻 2026-10-29T03:31:27+0800；二进制 100,957,904 字节）。台账本条迁移：`FR-STD-WS-EDIT-017` 实现 ⬜ → **🟡**
  （差人工点一次：小三角折 / 再点展开 / 切页签再回来仍折着 / ⌘F 仍能搜到块里的字）、判据 ⬜ → **✅**（28 + 6 例）。
  同批把「FR-STD 分族读数」三格按逐行实数重取 ⇒ ✅ 127 / 🟡 75 / ⬜ 11 = 213（旧格 127 / 72 / 14 差 2 行属早先漂移）。
- 上一轮读数（2026-10-29 R54）：`verify-core` **4644 项 / 0 failures**（4619 → +25 = `Tests/IndentProfileTests`）；
  五门 rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`3d375723`**（构建时刻 2026-10-29T03:11:58+0800；
  同标签更早那份 `0201eef7` 出在改发布说明之前、回执不含本批 ⇒ 作废）。
  台账本条迁移：`FR-STD-WS-EDIT-022` 实现 ⬜ → **🟡**（差人工看一眼状态栏那一格与硬 tab 显示宽度）、判据 ⬜ → **✅**（25 例）。
- 上一轮读数（2026-10-29 R53）：4619 / 0 failures（+15 = `Tests/HTMLPreviewTests`）· 包 `febe616d` ·
  `FR-STD-WS-WEB-003` 实现 🟡 / 判据 ✅。
- 再上一轮（R52）：4604 / 0 failures（+23）· 包 `13a099ae`；R51：4581 / 0 failures · 包 `f9e3f40b`。
- ⚠️ 口径不一（R53 记下的）：R52 记的「✅ 127 / 🟡 72 / ⬜ 14」与全表重算的「✅ 210 / 🟡 96 / ⬜ 97」不是同一套口径，
  待统一后再报总数（各轮只报本条迁移）。

## 下一项

**1. 台账高档里「判据还 🟡」的那几条优先** —— 先读该行备注确认缺的是「机械可跑的那一半」还是「只差人点」，
再按「判据可机械跑」取一条：`FR-STD-DB-META-007`（跨库浏览：`(连接, 数据库)` 按需建连 + 一个库失败只影响该节点 · 高）·
`FR-STD-WS-EDIT-015`（整批撤回：按批次一次撤回，只撤 Agent 改的、人手的改动不被覆盖 · 高）·
`FR-STD-WS-NAV-004`（补全接线：三类来源 + 不吞正常输入 + 与着色共用一份语言表 · 高）。
备选：`FR-STD-DB-DIAG-006` · `FR-STD-WS-LIC-001` · 低档四条（`FS-010` / `NAV-006` / `NAV-005` / `EDIT-014`）。
⚠️ `WS-TOOL-003`（DAP）/ `WS-AI-001`（编辑区 AI）纵切过大，排后。
⚠️ 存量红六条要清得单开一条活（清单见 loop-card），别混进功能片。
