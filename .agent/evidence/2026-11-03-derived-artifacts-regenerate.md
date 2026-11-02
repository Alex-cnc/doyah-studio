# 派生件重出 + 生成器口径跟拍板 · 2026-11-03（无台账行）

条目：**无**（不改任何需求状态）。本片清的是闭环里「真值源改了而产出件没重出」那一族（上一跳三分标注的根因族 ③，3 处），外加它带出来的一处夹具失效。

判据：
$ python3 Scripts/gen-studio-win-align.py --check && python3 Scripts/gen-platform-parity.py --check && python3 Scripts/gen-platform-board.py --check
✅ Windows 对齐件与现状一致（411 条需求；落点 Docs/archive/root-20261026/平台对齐-Studio-Windows对macOS.md）
✅ 平台等价矩阵与现状一致（411 条；平台列 4）
✅ 《任务清单·按平台》§1/§2/§3 与真源重算一致（411 条需求 · 4 端 · 82 个（产品线, 域）· macOS 309✅/15🟡/85⬜）

$ python3 Scripts/gen-platform-parity.py --self-test  ⇒ ✅ 11/11（真仓库 5 份真源逐字节未变）
$ python3 Scripts/gen-platform-board.py --self-test    ⇒ ✅ 9/9（四份真源 + 看板逐字节未变）
$ ./Scripts/verify-all.sh --keep-going
   合计：项块 19 个 · 失败 10 项（共 29 处）· 平台跳过 0 项 · 未执行项 = 无
   （上一跳同口径 10 项 / 31 处 ⇒ 净减 2 处；三处派生件由红转绿，无新增红）

反例三段（前两段在 `/tmp/winalign-probe` 临时根里做，真仓一字未动；第三段改后按字节还原）：
① 台账把 `FR-STD-DB-META-002` 状态改成 `🟠` ⇒ rc=1「状态格取值非法（'🟠'）」—— 收了 `➖`≠放水
② 同一格改成 `✅` ⇒ rc=0，该行读作 `✅ / — / ⬜`，且「不适用」条数 2 → 1 —— 这一格真被消费
③ board 第 ⑥ 例夹具改回旧字面锚点 `、\`FR-STD-` ⇒ 自检 rc=1「夹具目标不在看板里」；`sha256` 还原后 9/9

提交：本片唯一提交 = 引入本文件的提交（取法 `git log -1 --format=%h -- .agent/evidence/2026-11-03-derived-artifacts-regenerate.md`）；不写死 sha（amend 会作废）
未验证（≠通过）：真鼠标未点（三件都是派生件，判据在生成器与 `--check`）· `平台实现状态.json` 的 Linux/watchOS 列仍是显式 0 条（对侧未开）· 跑完后仍剩 **28 处**红（29 处里扣掉靠 `shared-surface:` 转绿的 `check-path-ownership`），本片一处未修 · `check-menu-language.py` / `check-board-parity` / `check-release-version --self-test` 等仍在红 · `gen-studio-win-align.py` 仍无 `--self-test` 族（反例是手跑）
