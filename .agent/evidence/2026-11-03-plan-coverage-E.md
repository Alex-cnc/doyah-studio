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

## 补记（同跳后半）：判据 E 接进闭环 + 全量读数

`Scripts/doc-numbers.json` 的 `exempt` 里原来登记着 `check-plan-coverage.py`（理由：「下一轮把它接进
verify-all，已登记为待办」）—— 判据在盘上却不在每轮跑的清单里 = 「有判据、没闭环」，§4.2 的 20 条漂移
就是这么发生的。本跳回收尾：

· `Scripts/verify-all.sh` **第 5 项**（原「需求状态一致性 + 版本范围」）改名为「文档口径对账（状态括注 /
  版本范围 / 台账↔需求索引覆盖 / §4.2 条数）」，并加两行 `check-plan-coverage.py` + `--self-test`。
  **项数仍是 19**（判据塞进既有项，不动项号硬编码 48 处 —— 接闸不必和重编号绑在一起）。
· `doc-numbers.json` 删掉那条豁免 ⇒ `check-doc-numbers` 读数「判据脚本 69 个：被闭环引用 **65**、登记豁免 **4**」。

读数（本跳实跑）：
$ python3 Scripts/check-doc-numbers.py  ⇒ rc=0（69 = 65 + 4 · 豁免 4 条全有效 / 死 0）
$ python3 Scripts/test-verify-all-gate.py ⇒ 夹具 **8/8** 达到预期（例 8 断言真仓 verify-all.sh 逐字节未变）
$ bash -n Scripts/verify-all.sh ⇒ ok
$ ./Scripts/verify-all.sh --keep-going ⇒ 项块 **19** · 失败 **10 项（31 处）** · 平台跳过 0 · **未执行项 = 无**；
  第 **5 项 ✅ 通过**（本跳新接的那两行在里面）· 第 19 项 ✅。红项清单：3 / 4 / 6 / 7 / 9 / 10 / 11 / 16 / 17 / 18。
  逐条核过：这 31 处命令**没有一条**落在本片改过的文件上（台账 / `check-plan-coverage.py` / `verify-all.sh` /
  `doc-numbers.json`），且与上一跳基线（10 项 / 31 处）**数目相同、项号相同** ⇒ 记「存量红，本片未新增」。
  其中第 18 项两处读数值得记：产物 Info.plist `CFBundleShortVersionString = 1.0.0` 与台账 `marketingVersion = 0.3.0`
  不一致；`check-release-version.py --self-test` 的夹具锚点 `<string>3</string>` 在 `build-app.sh` 里已经找不到。

未验证（补充）：全量 31 处红只做了「不在改动面上」的核对，**没有**逐条给出根因与修法（那是下一跳的活）。
