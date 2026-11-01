# 判据维护跳 · 2026-11-02（队列空 · 脚本级 · 第六片：文档门禁自检清红）

条目：无台账行（脚本级维护）。涉及 `Scripts/check-doc-q-series.py` · `Scripts/check-doc-tables.py` ·
`Scripts/self-test-counts.json` · `Scripts/doc-numbers.json` · `Scripts/verify-all.sh` · `AGENT-SPEC.md`。

## 这片修的是什么（两个族，四个红例）

上一片把「自检全跑只能记未知」修成「跑得完 ⇒ 18 族红」。本片按 checkpoint 的 next_try 从
`doc-q-series` / `doc-tables` 两族入手，红因全部是**夹具/台账与盘上事实脱钩**，不是判据本体坏：

1. `doc-q-series`：台账与三处文档都写「9 例 + 末例」，实跑只有 **7**（6 例 + 末例）。
   `git log` 定位 = `979e6d83`（2026-10-31 待拍板队列从《通用开发规范》§6 搬到《项目管理规范》§4）
   随搬家删掉两例而例数没跟版。删的两例里，**「关闭行（编号划掉）却写回 ⏳ 待拍板」属于误删** ——
   判据 C「关闭行成对」至今仍是**双向**的（`is_struck and not status_closed` 那一段还在判红），
   删了例子等于这一向再没人验。另一例「§4↔§6 同源」是真的没有判据对象了（`SEC4_HEAD = None`，
   对照表随文档拆分迁走）⇒ 如实记为**未覆盖**，不假装还在守。

2. `doc-tables` 自检 **14/17**，三个红例同一类陈旧：
   - 例 14 / 16 的夹具还锚「能力书里第一张表」，而能力书头表 2026-10-26 起是**元信息表**
     （文档编号 / 版本 / 定稿…）⇒ 改的是别人的表：表体被打断仍 `exit 0`（假绿）、
     缺一格报的是「列数 1 != 表头 2」而不是「格数不足 3」。
   - 例 4 硬钉「主开发机上 `Docs/开发记录-*.md` 应有 1 份」；那份记录随 2026-10-26 清根进了
     `Docs/archive/root-20261026/`，Docs 根实测 **0 份** ⇒ 长期判红，而门禁自己的口径写的是
     「通配匹配 0 份不判红，只显式打印份数」。

## 判据（命令原文 + 读数）

```
$ python3 Scripts/check-doc-q-series.py --self-test
✅ 例 6 报红并点名「编号已划掉」：关闭行只划掉编号、状态没写回 ✅
✅ 末例：真仓库 Docs/项目管理规范.md 逐字节未变（sha256 86dc97b827e3217b…）
自测：8/8 例符合预期            ← rc=0（修前 7/7 而台账写 9）

$ python3 Scripts/check-doc-tables.py --self-test
✅ 自检通过（17/17）            ← rc=0（修前 14/17，红 = 例 4 / 例 14 / 例 16）

$ python3 Scripts/check-doc-tables.py
ℹ️ 本机台账通配：Docs/开发记录-*.md → 本机 0 份（…主开发机上 0 份 = 文件被删或路径写错）
✅ 表格校验通过（74 个文件）      ← rc=0

$ python3 Scripts/check-doc-numbers.py
✅ 文档数字对账通过（台账 ↔ 实测 ↔ 文档 三向一致）   ← rc=0（落点命中 116 处 / 对侧独占节跳过 12 行）
$ python3 Scripts/check-doc-numbers.py --self-test
✅ 自测通过（44 例）              ← rc=0

$ python3 Scripts/check-self-test-counts.py --no-run
族 54 个 / 例数合计 1054 / 锚点命中 86 处 / 无锚点但写了理由的族 12 个   ← rc=0

$ python3 Scripts/check-self-test-counts.py        # 最终树上全跑（≈9 分钟）
族 54 个 / 例数合计 1054 / 锚点命中 86 处 / 无锚点但写了理由的族 12 个
❌ 判红 16 处（上一跳 18 ⇒ 本片清掉 doc-q-series / doc-tables）
  红：cli-failure-readability · core-localization · design-tokens · editor-line-numbers ·
      empty-action-buttons(+neg) · language-registry · literal-language · network-egress ·
      palette-wiring · panel-root-frames · release-version · result-scroll-ledger ·
      script-portability · terminal-tabs · tri-repo-parity            ← rc=1（16 红是**存量**，本片未碰）
```

## 红侧（改坏一处就必须变红，逐条还原后逐字节一致）

- `doc-q-series`：删掉「编号已划掉但状态未决」那一段判据 ⇒ **例 6 ❌「没报红/没点名」**、
  `7/8`；还原后 sha256 一致、复跑 8/8。
- `doc-tables`：同时撤掉「表体在此中断」报告 / 「格数不足」报告 / `split_row` 的转义识别 ⇒
  **例 14 ❌（判红了但没报「表体在此中断」与行号）/ 例 15 ❌（合法转义竖线被判红）/
  例 16 ❌（没报「格数不足 3」）**、`7/17`；还原后 sha256 一致、复跑 17/17。

## 顺带跟版（不跟版就自相矛盾）

- `Scripts/self-test-counts.json`：`doc-q-series` cases **9 → 8**（写清为什么是 8：补回一向、
  另一向无判据对象）；`floors.totalCases` **1055 → 1054**（台账合计按实跑改后重登记）。
- `Scripts/doc-numbers.json`：`doc-tables-files` 的落点 **69/1/70 → 74/0/74**，并**作废 4 条
  锚点**（`真仓库 N 份无跳过` / `收尾行应为 N 个文件（… + … 份通配）` / `真仓库 N 份命名文档应全在` /
  `✅ 表格校验通过（N 个文件）`）—— 自检例 4 改成「打印的份数 == 盘上实际匹配数」后那几处文本里
  不再有字面量，留着只会假装还在守。剩下 3 条带数字的落点（脚本 docstring / `verify-all.sh` 注释 /
  `AGENT-SPEC.md` §6）全改成当日实测值。
- `AGENT-SPEC.md` §6 两行（`q-series` 例数与 `doc-tables` 份数）同步。

提交：`14eb86cb`
未验证：全量 `verify-all.sh` 未复跑（本片只改 `Scripts/` + `AGENT-SPEC.md`，未碰 App/Core/Tests ⇒
代码套件记「未执行」，不是「通过」）；`check-self-test-counts` **全跑未跑**（读数为 `--no-run` 口径）；
真机点验 0 次；217 真库 0 次。
