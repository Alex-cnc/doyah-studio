# §7.1 卡点表收口 + 门禁看住它 · 2026-11-03

条目：`FR-AGT-LINK-EXT-001` / `FR-AGT-LINK-EXT-002`（已收口，从 §7.1「剩余」移到「已收口留痕」）·
`FR-AGT-UX-CONV-001` / `FR-AGT-PLAN-PLAN-001`（卡点话改口，状态列未动）
判据：

```sh
$ python3 Scripts/check-blocker-table.py
✅ §7.1 卡点表 = 台账未闭集合（§3 台账 471 行 / FR-AGT 未双 ✅ 8 条 / 卡点表 8 行 / 表头「剩余 8 条」）   rc=0
$ python3 Scripts/check-blocker-table.py --self-test
自测通过（5/5 例）   rc=0        # 全绿 / 已收口仍留表 / 表头数不符 / 未闭漏登 / 台账行数不足
$ 真台账负例：把已收口的 FR-AGT-LINK-EXT-001 塞回 §7.1（--root 夹具）
❌ [已收口仍留表] 这些号在 §3 已双 ✅：FR-AGT-LINK-EXT-001（移到「已收口留痕」）   rc=1
$ python3 Scripts/check-release-version.py
✅ 发布产物版本号三处逐字一致 + 生成物与 project.yml 不漂移（比对点 17 处）   RESULT: OK
$ ./Scripts/verify-all.sh --keep-going
合计：项块 19 个 · 失败 4 项（共 6 处）· 平台跳过 0 项   rc=1
  第 3 项 format-arguments（230 处 > 预算 190）+ button-icon-only（Notes 面板 7 处）= **存量**（HEAD 00ed502e 另建 worktree 复跑同红）
  第 4 项 req-index 已转绿（重生成 .build/derived/requirement-index.jsonl，488 条）
  第 11 项 menu-language 两档 dump 未产出（三次 ×120 s 超时）—— 与本次改动无关，见「未验证」
  第 16 项 path-ownership 需 shared-surface 登记 ⇒ 已写进提交信息，单跑 `check-path-ownership` rc=0
提交：96c90cdf
未验证：第 11 项 menu-language 的 dump 为什么没出来（本跳后台复跑一次，读数见 checkpoint）·
217 真 PG 上的模型诊断端到端未跑（CONV-001 / PLAN-001 的剩余卡点）· 面板界面入口未点
