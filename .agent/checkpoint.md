# 检查点

updated: 2026-10-29T06:12

## 现状

- 循环卡 = `.agent/loop-card.md`（**2026-10-28 20:08 主人改成接力制**：一轮收尾即 `cronjob_manage action=run job_id=e98fad41f72d`
  点火下一轮；定时器 5 分钟一跳只做兜底；不再按剩余条数自调阶梯）。**本会话无 `cronjob_manage` 工具** ⇒ 接力改用 CLI
  `hermes cron run e98fad41f72d`（同一效果：下一跳调度器拉起），详见 loop-card 的「节奏」段。
- 队列唯一来源 = `Docs/Doyah产品开发计划任务清单-macOS端.md`（`FR-STD-*` 里实现为 `⬜`／`🟡`）；`.agent/plan.yaml` 已停用。
- 最近读数（2026-10-29 **R61**）：`verify-core` **4804 项 / 0 failures**（4776 → +28 = `Tests/SnippetTemplateTests` 23 例 + `Tests/SnippetTemplateSourceTests` 5 例）；五门 + `check-format-arguments` rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`dafed86a`**（构建时刻 2026-10-29T06:04:40+0800；二进制 101,996,672 字节；同标签 05:45:45 那份 `50553049` 出在发布说明含片补本条之前 ⇒ 作废）。
  台账本条：`FR-STD-WS-NAV-005`（片段模板）实现 ⬜ → **🟡**（**界面已接线**：两个编辑器的 `insertTab` 次序 会话 → 灰字 → 片段 → 缩进；差人工点一次 —— 打 `select` 按 Tab 出骨架且光标在第一个占位符 / 再按 Tab 依次跳、填完回缩进 / 字符串与注释里不展开 / `selects` 不展开）、判据 ⬜ → **✅**（23 + 5 例，反例六段各判红后逐字节还原）；分族读数（逐行实数）⇒ ✅ 127 / 🟡 79 / ⬜ 7 = 213。
  **下一项**：高档与中档都只剩「人工点验 / 陈旧标记归正」⇒ ① `FR-STD-WS-NAV-004` 走陈旧标记归正（不加用例）；② 或低档三个真 ⬜：`FR-STD-WS-FS-010`（多工作区切换）/ `FR-STD-WS-NAV-006`（悬停 + 跳定义）/ `FR-STD-WS-EDIT-014`（撤销粒度）。
  ⚠️ 同批改写 `Tests/IndentProfileTests` 的「Tab 三个动作」锚点（现为四分支、次序写死；理由写在该用例注释里）—— 不是放宽。
- 最近读数（2026-10-29 **R60**）：`verify-core` **4776 项 / 0 failures**（4760 → +16 = `Tests/ObjectTreeRetryTests` 11 例 + `Tests/ObjectTreeRetrySourceTests` 5 例）；五门 + `check-format-arguments` rc 全 0；包 `dist/DoyahStudio-beta1.0.app` sha256 **`50553049`**（构建时刻 2026-10-29T05:45:45+0800；二进制 101,914,144 字节；同标签 05:45:26 那份 `164a7fe0` 出在发布说明含片补本条之前 ⇒ 作废）。
  台账本条：`FR-STD-DB-META-006`（③ 失败在该节点可重试）实现 🟡（**界面已接线**：失败那一行红字旁有「重试」，判定与计划同出 `Core/ObjectTreeRetry`；差人工点一次 —— 连不上的库展开看入口 / 点了旧红字先消失再重取 / 在途时入口消失）、判据 🟡 → **✅**（11 + 5 例，反例六段各判红后逐字节还原）；分族读数不变 ⇒ ✅ 127 / 🟡 78 / ⬜ 8 = 213。
  **下一项**：台账高档里已无「机械可推进」的 ⬜（`META-006` 只剩人工点验、`META-007` 的机器面早已在 `TestsUISnapshot/CrossDatabaseBrowseProbeTests`、`NAV-004` 判据列与备注互证属「陈旧标记归正」）⇒ 下一轮建议：① `FR-STD-WS-NAV-004` 走**陈旧标记归正**（只翻判据列 + 补登记用例数与文件名，不加用例、测试总数不变）；② 或中档找真有机械缺口的：`FR-STD-DB-META-011`（查看对象 DDL）/ `FR-STD-DB-META-015`（全库对象搜索）/ `FR-STD-DB-DATA-002`（一键 count）—— 取之前先 `grep` 源码看机械判据还差哪一半。
- 最近读数（2026-10-29 **R59**）：`verify-core` **4760 项 / 0 failures**（4746 → +14 = `Tests/AgentBatchRevertTests` 9 例 + `Tests/AgentBatchRevertSourceTests` 5 例）；五门 rc 全 0；`check-format-arguments` rc 0（占位符调用点 453 处）；包 `dist/DoyahStudio-beta1.0.app` sha256 **`a120a874`**（构建时刻 2026-10-29T05:28:14+0800；二进制 101,829,696 字节；同标签 05:25:26 那份 `20adc61a` 出在补发布说明含片之前 ⇒ 作废）。
  台账本条：`FR-STD-WS-EDIT-015` 实现 🟡 保持（**界面已接线**，差人工点一次：改两个文件点整批撤回 / 撤前手工改一个看「没动」/ 点「撤销这次撤回」回到 Agent 版）、判据列补实证（9 + 5 例）；分族读数不变 ⇒ ✅ 127 / 🟡 78 / ⬜ 8 = 213（本条实现档没动）。
  ⚠️ 同批修正 `plan` 的口径：同一路径多次写入时**前像取最早那份、摘要取最新那份**（原来整条换成后一条 ⇒ 一批里改两次只撤得掉最后一次写，与「一次撤回把所有改动还原」相反）；那条判据随之改写并已验能判红。
  ⚠️ `check-core-localization` / `check-literal-language` 本轮仍红，但已在干净工作树 `/tmp/r59-base`（= HEAD）复跑对照：`新增` 条目集合逐条相同（34 条 / 1 条），**不是本批的账**。
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

**1. 台账高档里还能机械推进的那几条** —— 取之前先读该行备注，确认缺的是「机械可跑的那一半」还是「只差人点」：
`FR-STD-DB-META-006`（对象树下钻：备注写「界面未点（展开 / 空态 / 失败态）」⇒ 先 grep 源码看这三步的机械判据还缺哪一半）·
`FR-STD-DB-META-007`（跨库浏览：备注写「失败隔离与重试步骤待人工点验」⇒ 同上，先看机械面）·
`FR-STD-WS-NAV-004`（补全接线：行内灰字与行为判据按备注已全绿 ⇒ 若只是判据列陈旧，就走「陈旧标记归正」，只翻标记不加用例）。
备选：`FR-STD-DB-DIAG-006` · `FR-STD-WS-LIC-001`／`-002` · 低档四条（`FS-010` / `NAV-006` / `NAV-005` / `EDIT-014`）。
⚠️ `WS-TOOL-003`（DAP）/ `WS-AI-001`（编辑区 AI）纵切过大，排后。
⚠️ 存量红六条要清得单开一条活（清单见 loop-card），别混进功能片。
