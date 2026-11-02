# 门禁债 · 菜单识别表（编辑菜单四条 AI 辅助 + 慢查询排行）· 2026-11-02

条目：**无台账行**（修的是判据覆盖面缺口，不是需求实现；台账书头 v1.0.154）
改了什么：`Core/MenuLocalization.swift` 的 `menuKeys` 补登 `.editAssistActionExplain` / `-Rewrite` / `-Complete` / `-FixError` / `.slowQueryTitle`（键名没有 `menu` 前缀 ⇒ 原来既没被那条「按前缀筛」的测试筛到，运行时也认不出 ⇒ 切语言后停在启动语言）；新增 `Tests/MenuLocalizationTests.testEveryCommandMenuItemKeyIsRegistered`（扫 `App/DoyahStudioCommands.swift` 里每个当标题用的 `L(.key)`，按**菜单项来源**判，不按命名前缀判）。

判据（同一台机 · 旧包 → 新包）：
```
$ python3 Scripts/check-menu-language.py --app <旧包 beta1.0.backup-20261102-215137>   # 反例（红侧）
      A/C/B 各：条目 80/117/117 · 识别 71/108/108 · 未覆盖 5/5/5
❌ 菜单栏这一层没过（40 条）：Explain Selection / Rewrite as Described / Complete from Context /
   Fix the Error / Slow query ranking / 慢查询排行 —— 逐条点名（五项 × A/C/B 三段 × 两档）   rc=1
$ python3 Scripts/check-menu-language.py
      A：条目 80 / 识别 76 / 认不出 4 / 停启动语言 0 / 未覆盖 0
      C：条目 117 / 识别 113 / 认不出 4 / 停启动语言 0 / 未覆盖 0（B 段同 C）
✅ 两档三段的每一项都跟当前界面语言同语；认不出的项都在豁免里；展开族一条不少   rc=0
$ python3 Scripts/check-menu-language.py --self-test   ⇒ 自检 19 例：19 通过 / 0 失败
$ DEVELOPER_DIR=… swift test --filter MenuLocalizationTests
   改前（判据已加、键未登记）：Executed 13 tests, with 1 failure ——
     未登记 ["editAssistActionComplete","editAssistActionExplain","editAssistActionFixError","editAssistActionRewrite","slowQueryTitle"]
   改后：Executed 13 tests, with 0 failures（12 → 13 例）
$ ./Scripts/verify-core.sh   ⇒ Executed 5326 tests, with 13 tests skipped and 0 failures
$ ./Scripts/verify-all.sh --keep-going
   第 11 项 ✅ 通过；合计：项块 19 个 · 失败 10 项（共 27 处）· 平台跳过 0 项；未执行项 = 无
   与上一跳 .build/verify-all-20261102-item19.log 逐项比对：只有第 11 项 ❌ → ✅、28 处 → 27 处，
   其余 10 项逐项相同 ⇒ 那些存量红不是本片引入（本轮**未**在 HEAD 工作树复跑，只做逐项比对）
文档门禁：invariants / tables / numbers / plan-coverage / status-consistency / version-scope /
   doc-versions / doc-layout rc=0 · `check-status-gap` 0 行（不适用 4 行逐条点名）·
   `plan-batches --version 0.6.0 --check` rc=0（0 todo / 18 blocked）
提交：PLACEHOLDER_SHA
未验证：真鼠标点这五条菜单项未点（判据走真启动 dump 的 A/C/B 三段，不是人眼）· 切语言后的人工观感未看 ·
   表里仍「认不出」的 4 条属豁免类（语言显示名 / 应用显示名 / 窗口标题）· 10 项存量红未修
