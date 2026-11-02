# 判据 F 闭环（无台账行 · 门禁接线）· 2026-11-03

条目：无（不改任何需求状态符号；把上一片新增的判据 F 接进闭环第 5 项）
判据：
$ python3 Scripts/plan-batches.py --check
ℹ️ 判据 F 覆盖 27/28 条 blocked；未经规则表核对（跨版携带，只判非空不判逐字）：FR-NTS-NOTE-ORG-002
✅ 批次队列一致（0 条待办，台账复算一致）
rc=0

$ # 反例 A：手改 .agent/plan.yaml 里 AC-ALL-GATE-REL-004 的 next_try 一句
$ python3 Scripts/plan-batches.py --check
✗ next_try 与规则表不一致：AC-ALL-GATE-REL-004（派生件落后或被手改 ⇒ 跑 --emit-plan 重出）
ℹ️ 判据 F 覆盖 27/28 条 blocked；未经规则表核对（跨版携带，只判非空不判逐字）：FR-NTS-NOTE-ORG-002
rc=1

$ # 反例 B：同一个坏派生件，把第 5 项的命令块从 verify-all.sh 原样抽出执行
$ awk '/^echo "==> 5\/19/{f=1;next} /^echo "==> 6\/19/{f=0} f' Scripts/verify-all.sh > /tmp/item5-block.sh
$ bash -c 'set -euo pipefail; source /tmp/item5-block.sh'
（前四条判据全绿：状态一致性 471 / 版本范围 8 例自检 / 台账↔索引 · §4.2 判据 E 自检 6/6）
✗ next_try 与规则表不一致：AC-ALL-GATE-REL-004（派生件落后或被手改 ⇒ 跑 --emit-plan 重出）
rc=1
$ git checkout -- .agent/plan.yaml && sha256sum .agent/plan.yaml
5b38829357fdb3419be4f38667be34b90d64900f0a2db42eada48b1758c73b69  .agent/plan.yaml   # 与改前逐字节一致
$ bash -c 'set -euo pipefail; source /tmp/item5-block.sh'   ⇒ rc=0（复绿）

$ ./Scripts/verify-all.sh --keep-going
合计：项块 19 个 · 失败 11 项（共 33 处）· 平台跳过 0 项
   第 5 项  ✅ 通过（新接线在内：判据 F 覆盖 27/28 读数为它打印的那一行）
   第 19 项 ✅ 通过
覆盖面：**项块 11 项红之外，其余项都跑了**（未执行项 = 无）
与上一跳基线（10 项 / 32 处）差 1 项 1 处 = 第 1 项，唯一失败
`SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything`
（`portInUse(50506)` 期望，实测 `processExited("ssh 已退出：… OSError: [Errno 48] Address already in use")`）
单族连跑 3 次 ⇒ 0 / 1 / 1 failures ⇒ 存量抖动，本片未碰隧道。

提交：6b321eae 之后的一笔（见 git log --grep「判据 F 接进闭环」）
未验证：
- 第 1–4 / 6–19 项**未在坏派生件下**逐项复跑；反例 B 抽的是第 5 项那 37 行命令块（同一批命令行、同一个
  `set -euo pipefail`），不是整条 `verify-all.sh` 的一次红跑。
- 跨版携带那条（`FR-NTS-NOTE-ORG-002`）**只判 non-empty、不判逐字** —— 它没有规则表条目，覆盖范围已由
  运行时那行 `ℹ️` 逐条点名，不静默算通过。
- 第 1 项那次失败**没修**（抖动，`ssh` 的 `Address already in use` 未归因成 `portInUse`，属既有 next_try）。
