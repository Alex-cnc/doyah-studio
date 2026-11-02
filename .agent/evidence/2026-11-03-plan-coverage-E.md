# 2026-11-03 · §4.2 报数归正 + 判据 E（`check-plan-coverage.py`）

条目：**无台账行**（修的是报数口径与判据覆盖面，不是需求实现）。由来 = `.agent/checkpoint.md` 2026-11-02 记下的
「§4.2 报数差 +11」债 —— 当时只有手算留账、没有门禁守着。

改了什么：
· §4.2 六个里程碑条数按台账逐行复算改正：合计 46 → **26**（v0.2.0 0→2 · v0.3.0 22→0 · v0.4.0 1→3 ·
  v0.5.0 10→10（10/0）· v0.6.0 7→6 · v0.9.0 6→5）；头部未闭 117→**26**（🟡23→20 / ⬜94→6）；
  §2 ✅296→**361**、§3 🟡76→**20**、§4 ⬜17→**6**；粗估 60–110h → 12–23h（并写明 26 条全卡外部）。
· `Scripts/check-plan-coverage.py` 新增**判据 E**：`MILESTONES` 前缀表 = §4.2「内容」列口径；
  ① 未闭行必须**恰好**落一个里程碑（无孤儿 / 无重复）；② §4.2 每行「条数（🟡 / ⬜）」；
  ③ 头部「当前未闭 N 条（🟡 a + ⬜ b」；④ `§2 ✅ N` / `§3 🟡 N` / `§4 ⬜ N` 三个标题，全部 == 复算值。
  另加 `--self-test`（6 例，内存里改文本，真仓零改动）。

判据：
$ python3 Scripts/check-plan-coverage.py
— 需求分析索引 471 条 · 一单台账 471 条 · 空壳 0 行
— 台账逐行复算（非 FR-RTR）：✅ 361 · 🟡 20 · ⬜ 6 · ➖ 2 · 未闭 26 · 未闭未归堆 0
— §4.2 六个里程碑：v0.2.0 2（2 / 0） · v0.3.0 0（0 / 0） · v0.4.0 3（2 / 1） · v0.5.0 10（10 / 0） · v0.6.0 6（5 / 1） · v0.9.0 5（1 / 4）
✅ 台账与索引一一对应；无空壳行；需求规格说明书正文无状态符号；§4.2 条数与台账逐行复算一致  ⇒ rc=0
$ python3 Scripts/check-plan-coverage.py --self-test
判据 E 自检 6/6 通过  ⇒ rc=0
$ for s in check-doc-tables check-doc-numbers check-doc-invariants check-status-consistency check-version-scope \
    check-doc-layout check-agents-index check-status-gap check-doc-versions; do python3 Scripts/$s.py; done
九道全部 rc=0 · `python3 Scripts/plan-batches.py --version 0.7.0 --check` ⇒ ✅ 批次队列一致（0 条待办）rc=0

反例两段（判红后 `sha256` 逐字节还原 `4e26350c79f1…`，`shasum -a 256` 前后一致）：
① §4.2 v0.4.0 条数 3 → 1 ⇒ rc=1 点名「§4.2 v0.4.0 条数写 1（2 / 1），台账逐行复算是 3（2 / 1）」；
② 把 `FR-NTS-NOTE-ORG-002` 状态 ⬜ → ✅（假收口）⇒ rc=1 点名四条（§4.2 v0.4.0 / 头部 26→25 / §2 361→362 / §4 ⬜ 6→5）。

提交：见 `git log -1 --format=%h`（「§4.2 报数归正 + 判据 E」）

未验证：§3「三类成因」分档表仍是 2026-11-01 对 76 条的历史分档（成因归类要人手逐条判，机器判不了；
已在表下写明停更，判据 E 只管条数与归属）· 本族未登记进 `Scripts/self-test-counts.json`（登记要另配锚点，
不在本片范围）· 全量 `verify-all.sh` 本轮未跑（只跑文档门禁九道 + 本判据 + 批次对账；本片零 Swift 改动）。
