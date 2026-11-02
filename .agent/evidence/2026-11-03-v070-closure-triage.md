# v0.7.0 收口 + 存量红三分标注 · 2026-11-03

条目：**无台账行**（收口跳，不改任何需求状态）
判据：

```
$ python3 Scripts/plan-batches.py --check
ℹ️ 判据 F 覆盖 27/28 条 blocked；未经规则表核对（跨版携带，只判非空不判逐字）：FR-NTS-NOTE-ORG-002
✅ 批次队列一致（0 条待办，台账复算一致）

$ ./Scripts/verify-all.sh --keep-going          # 日志 .build/verify-all-20261103-033109.log
   第 18 项  ❌ 失败
   第 19 项  ✅ 通过
   合计：项块 19 个 · 失败 10 项（共 31 处）· 平台跳过 0 项
   覆盖面：**项块 10 项红之外，其余项都跑了**（未执行项 = 无）；平台跳过 0 项（跳过 ≠ 通过）。

$ python3 Scripts/check-self-test-counts.py     # 全量重跑（不是 --no-run），.build/self-test-counts-rerun.log
   族 56 个 / 例数合计 1074 / 锚点命中 86 处 / 无锚点但写了理由的族 14 个
❌ 判红 14 处：cli-failure-readability · effective-language · empty-action-buttons（+ neg）·
   notes-offline · release-version · terminal-tabs · vendored-sqlite · result-scroll-ledger ·
   editor-surface-tokens · agent-provider-presets · plugin-assembly-gate · tri-repo-parity · note-storage-unity
   ⇒ 自检族 **14 红 / 42 绿**（上一片记的「8 族红」是旧读数，已过期）
```

三分标注（逐条单跑一次 = 同一棵树上的第二次读数，`.build/triage-20261103-041019.tsv`）：

- **确定性失败 = 31 处 / 10 项**（单跑 rc 与全量逐处相同，无一复绿）
- **抖动 = 1 条族外**：`SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything`
  —— 本轮全量**未出现**（上一跳 11 项/33 处 → 本跳 10 项/31 处，差的正是它），单族历史连跑 0/1/1
- **未复现 = 0**（没有一条给不出复现步骤）

根因分五族（下次动手按族清，不按项清）：

1. **自检「绿对照」红 = 真仓库本身红**（5 处）：`check-editor-surface-tokens --self-test`（绿对照：真仓库副本应全过）· `check-agent-provider-presets --self-test`（末例）· `check-terminal-tabs --self-test`（例 1 绿路基线）· `check-tri-repo-parity --self-test`（例 20）· `check-plugin-assembly`（例 20）⇒ 先把真红清掉，这 5 处自己绿。
2. **真产品面红**（12 处）：`check-format-arguments` **230 处 > 预算 190** + 25 条占位符对账 · `check-terminal-tabs`（Core 里出现中文字面量：`AgentClarificationGate.swift`「查」/ `AgentCodeRunner.swift`）· `check-editor-surface-tokens` 4 项（`App/Views/QuickCaptureSheet.swift:36` 在编辑面修饰链上写 `.scrollContentBackground(.hidden)`）· `check-notes-offline` 21 处 · `check-note-module-isolation` · `check-empty-action-buttons` · `check-sidebar-collapse-state` · `check-end-sheets`。
3. **生成物没重出**（3 处，一条命令可清）：`gen-platform-parity --check` / `gen-studio-win-align --check` / `gen-platform-board --check` 全部「真源改了而看板没重生成」。
4. **夹具锚点失效 / 脚本崩**（4 处）：`check-release-version --self-test` **rc=2**（`build-app.sh` 里找不到 `<string>3</string>`）· `check-board-parity` **Traceback**（状态格整段 `✅（…）` 当键）· `check-vendored-sqlite --self-test` **Traceback** · `check-note-storage-unity --self-test`。
5. **跨仓快照落后**（1 处）：`check-tri-repo-parity` 期望 `Scripts/check-path-ownership.py` = `248ab90e…`，实测 `3a774482…`（本侧改过、快照没跟）。

第 11 项（`check-menu-language`）单列：两档都「三次都没成：等了 120 秒没等到 dump」。手工复现同一形状 ——
`DOYAH_MENU_DUMP=/tmp/x.txt DOYAH_MENU_DUMP_DELAY=8 DOYAH_MENU_DUMP_OPEN=1 dist/DoyahStudio.app/Contents/MacOS/DoyahStudio -AppleLanguages "(en)" -app.language en`
⇒ 30 s 内无 dump，stderr 只有 `sandbox_extension_issue_file_to_process failed … (Operation not permitted)`。
**判在「真启动取证」这一层，不是菜单文案**（产品结论未判）。

提交：见本节所在 commit
未验证：第 11 项产品侧菜单文案（取证层就没跑出来）；31 处红**一处未修**（本跳只分类、不改判据）；14 族红的根因只到脚本层（没逐族进源码定位）
