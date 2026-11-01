# 文档判据维护跳 · 2026-11-02
条目：无台账行（`.agent/batches.yaml` 0 条 todo；本跳做的是判据维护，不动任何状态位）
判据：
$ python3 Scripts/check-doc-layout.py
== Docs/Doyah产品能力规划说明书.md｜1779 行｜标题 209 个｜cap   [1..9] 全 0
== Docs/Doyah产品需求规格说明书.md｜2465 行｜标题 226 个｜req   [1..9] 全 0
== Docs/Doyah产品概要设计说明书.md｜2448 行｜标题 142 个｜design [1..9] 全 0
✓ 三书九轮全清        （改前：❌ 7 条 —— 能力书 3 / 需求书 3 / 概设 1）

负例（故意改坏再跑，跑完删 .build/neg/）：
$ python3 Scripts/check-doc-layout.py .build/neg/cap.md --mode cap
  [2] 标题 · L1497 「5.3.3 Notes 作为独立产品的形态（[产品特有]）」→ 汉字 13 超 6
  [8] 平台名 · 正文平台名「iOS」  ⇒ rc=1，2 条
$ python3 Scripts/check-doc-layout.py .build/neg/design.md --mode design --srs … --allow-platform
  [1] 结构 · L900 过短节「13. 变更与偏离处理」102 字  ⇒ rc=1，1 条

$ python3 Scripts/check-doc-invariants.py
✓ 5 条铁律全部成立        （改前：✗ 1/5 ——「变更记录」仍出现；负例：往概设尾插
   `## 14.x 变更记录` ⇒ rc=1 点行 2449，还原后 sha256 一致复绿）
$ python3 Scripts/check-req-index.py
✓ requirement-index.jsonl 与正文一致（488 条）   （需求书判据列改字 ⇒ 重生成后一致）
$ 其余八道 rc=0：check-doc-tables 74 文件 · check-doc-numbers 三向 · check-plan-coverage 471 ·
  check-status-consistency 471 · check-version-scope 471 · check-doc-versions 17 份 ·
  check-agents-index 15 条 · check-platform-neutrality 严格档 0
提交：3fd8c9ab
未验证：verify-all.sh --keep-going 18 项红 11 项 —— 逐项对过 HEAD 基线（临时 worktree + 同一份
  .build/derived）：check-end-sheets 的 Android 一条、四道派生台账门（parity / win-align /
  board / board-parity 的 KeyError）在 HEAD 同样红（存量）；第 16 项在 verify-all 的
  `macos,watchos` 口径下把契约层新增行判红，显式 `DOYAH_SIDE=hugehippo` ⇒ 受检 37 行全绿
  （pre-commit 用的正是 hugehippo）。真机点验 0 次 / 217 真库 0 次。
