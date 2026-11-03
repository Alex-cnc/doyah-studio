# 派生件归正（无台账行 · 队列 0 todo）· 2026-11-03

条目：无（队列 0 todo；本跳不认领需求，只把派生件与台账重新对齐）

## 为什么
上一跳（`check-menu-language` 收口）留下的三处 `verify-all` 红全起自**别的写者那 4 笔提交只改台账、没重出派生件**；上一跳不重出的理由是 `FR-NTS-NOTE-ORG-002` 口径当时正在被改写。本跳先核实**该前提已消失**：台账里 `ORG-002` / `AI-002` 已按主人 2026-11-03 令收口（`ledger-row.py` 两行都读 `✅`），`LANG-001` / `UI-001` 亦已收口 ⇒ 重出派生件此刻只是**把台账事实搬到看板**，不替别人拍板。

## 判据
$ python3 Scripts/gen-req-index.py && python3 Scripts/gen-platform-parity.py && \
  python3 Scripts/gen-studio-win-align.py && python3 Scripts/gen-platform-board.py && \
  python3 Scripts/plan-batches.py --version 0.7.0 --emit-plan --write
✓ requirement-index.jsonl 与正文一致（488 条）
✅ 平台等价矩阵与现状一致（411 条；平台列 4）
✅ Windows 对齐件与现状一致（411 条需求）
✅ 《任务清单·按平台》与真源重算一致（411 条需求 · 4 端 · 82 个（产品线, 域）· macOS 314✅/12🟡/85⬜）
✅ 已按台账重出 .agent/plan.yaml（0 条 todo / 17 条 blocked）

$ python3 Scripts/check-board-parity.py
✅ 《任务清单·按平台》与真源逐列一致（4 端 × 411 条需求 · §3 macOS ⬜ 85 条 + 🟡 12 条 · macOS 列 314 ✅）

$ ./Scripts/verify-all.sh --keep-going
合计：项块 19 个 · 失败 1 项（共 1 处）· 平台跳过 0 项
   第  1 项 ✅（Executed 5368 tests, with 16 tests skipped and 0 failures）
   第  3/4/7/11/18/19 项 ✅（第 11 项含真启动菜单语言 + 打包）
   第 16 项 ❌ —— 唯一红 = `Docs/archive/root-20261026/平台对齐-Studio-Windows对macOS.md` 属共享面，改动未在提交信息登记 `shared-surface:`（本跳工作树未提交造成，提交后单跑复验）

## 报数
- 队列 21 blocked → **17 blocked**（`AI-002` / `ORG-002` / `LANG-001` / `UI-001` 在台账已 ✅，不再当卡点携带）；0 todo 不变。
- 台账状态列**一字未改**；未闭数与 §2 计数照旧（本跳只动派生件）。

## 未验证
- 三条「已 ✅」的收口判据是别的写者的读数，本跳只核了 `ledger-row.py` 的 `✅` 与 `check-status-gap` rc=0，**没有重跑它们各自的测试族**。
- 第 16 项提交后单跑结果见本节追加（未跑 = 未知，不算通过）。
