# 判据维护 · 自检「绿对照」族（真仓库红 ⇒ 自检跟着红）· 2026-11-03

条目：无（判据维护跳 · 台账行不变；队列仍 0 todo / 28 blocked 全卡外部）
判据：

```
$ python3 Scripts/check-editor-surface-tokens.py                    # 4 处红 → rc=0
$ python3 Scripts/check-editor-surface-tokens.py --self-test        # 25/25
$ python3 Scripts/check-agent-provider-presets.py                   # 1 处红 → rc=0
$ python3 Scripts/check-agent-provider-presets.py --self-test       # 15/15
$ python3 Scripts/check-terminal-tabs.py                            # 30 处红 → rc=0
$ python3 Scripts/check-terminal-tabs.py --self-test                # 25/25
$ python3 Scripts/check-result-scroll-ledger.py                     # 4 处红 → rc=0
$ python3 Scripts/check-result-scroll-ledger.py --self-test         # 18/18
$ python3 Scripts/check-tri-repo-parity.py                          # 1 处红 → rc=0
$ python3 Scripts/check-tri-repo-parity.py --self-test              # 20/20
$ python3 Scripts/check-note-module-isolation.py                    # 1 处红 → rc=0
$ python3 Scripts/check-plugin-assembly.py                          # 1 处红 → rc=0（+ --self-test 15/15）
$ python3 Scripts/check-vendored-sqlite.py --self-test              # 夹具崩 → 25/25
$ python3 Scripts/check-note-storage-unity.py --self-test           # 例 5 崩 → 7/7
$ python3 Scripts/check-end-sheets.py                               # 1 处红 → rc=0
$ python3 Scripts/check-empty-action-buttons.py                     # 2 处红 → rc=0（+ test 11/11）
$ python3 Scripts/check-sidebar-collapse-state.py                   # 1 处红 → rc=0
$ python3 Scripts/check-effective-language.py                       # 1 处红 → rc=0
$ swift test --filter "NotesUndoAndLongDocumentProbeTests|WorkspaceFileOpenGuardProbeTests|WorkspaceHomeProbeTests|WorkspaceImageRoutingProbeTests"
   Executed 21 tests, with 0 failures (0 unexpected)
```

读数尾部：

```
✅ 编辑面的底色与字色只用主题令牌…（编辑面 10 处全部挂 .editorSurface() · 台账 8 份文件）
✅ A 唯一出处：提供商宿主名在产品源面…面外命中 6 份全部在册
✅ 终端多会话（页签）判据通过：Core API 锚点 21 处 / 界面接线锚点 59 处 / 文案键 12 个（中英齐）
✓ 台账自洽：上界都有来源…探针都挂在取证脚本上（FILTER= 清单 82 条 / 盘上 83 份，豁免 1 份）
✅ 副本身份对账通过：比成 2 处（4 处不在盘上、未比）
✅ 笔记模块解耦门禁通过（36 个笔记源文件…）
✅ 插件装配链门禁通过（6 组判据）
✅ 负例自检通过（25 例：篡改 23 条全部被抓 + 对手臂 2 条不误报）
自检：7 例全过
✅ 端级对账通过：任务清单六端各一份…
✅ 空数据按钮处置逐条对账通过（守卫 50 条 / 台账 50 条）
✅ 侧边栏折叠状态：判据全过
✅ 语言来源门禁通过：除例外（系统菜单 / 根视图重建 / 菜单勾选态）外，一律走 effectiveLanguage
```

提交：`6abecaf5`（8 族收口 + 3 项判据自伤 + 1 条真缺陷）· `b9e940e0`（ssh 端口占用误归 processExited → portInUse，verify-core 5361 项 0 失败）· `53a0f84f`（`Address already in use` 进 Core 英文串台账，kind = driverMessage）

未验证（≠ 通过）：
- R-037 存量债 **30 处 / 30 份 Core 文件**本跳**一处未修**，只登记进 `Scripts/terminal-tabs-han-baseline.json` 先红基线（R-037 全局收口属别单）；堵的是"新增件再悄悄添债"。
- 三仓同源副本只有本仓在盘 ⇒ `check-tri-repo-parity` 比成 2 处、**4 处跳过**（Notes / Retro 是否同源未判；`--require-all` 会判红）。
- 4 份探针接进 `FILTER=` 后，只在**单族**里实跑过（21 例 0 失败）；整卷 `verify-ui-interactions` 的读数见全量那一行，未逐条核多出来的探针。
- `check-end-sheets` 的负例是在临时副本上手跑的（两个方向），未进 `check-self-test-counts` 台账（该脚本仍无自检族）。
- 真鼠标未点（本轮零界面新增，改的都是判据 / 台账 / 一处导出语言取值）。

## 全量读数与三分标注（本跳实跑）

```
$ ./Scripts/verify-all.sh --keep-going    # 日志 .build/verify-20261103-072640.log
   合计：项块 19 个 · 失败 4 项（共 7 处）· 平台跳过 0 项
   · 第 3 项 check-core-localization.py / --self-test（本跳自己引入的英文串，事后已登记 ⇒ 单跑 rc=0 · 17/17）
   · 第 3 项 check-format-arguments.py（230 处 > 预算 190）
   · 第 3 项 check-button-icon-only.py（NotesPanel 22 处未过）
   · 第 4 项 check-self-test-counts.py（2 族：cli-failure-readability / notes-offline）
   · 第 10 项 check-notes-offline.py（22 处未登记）
   · 第 11 项 check-menu-language.py（真启动 dump 等不到）
```

上一跳基线（`.build/verify-20261103-055409.log`）：**9 项 / 26 处** ⇒ 本跳 **4 项 / 7 处**
（core-localization 那 2 处是本跳自己引入、已当场登记修掉 ⇒ 账面应为 **4 项 / 5 处**，
**修后未重跑全量**，不按推算报绿）· **净减 5 项 / 19 处，新冒 1 处（已修）**。

三分标注（余红，给下一跳）：
- **确定性失败 4 项 / 5 处**：`check-format-arguments`（230 > 预算 190，25 条占位符对账）·
  `check-button-icon-only`（`NotesPanel.swift` 22 处「既不是图标也没登记」）·
  `check-notes-offline`（22 份笔记源文件没进 `scope`/`outOfScope`）· 连带 `check-self-test-counts`
  的 2 族（cli-failure-readability 有 2 条自伤 + notes-offline runner 红）· `check-menu-language`
  （真启动两档都等不到 dump —— 在「真启动取证」这一层，菜单文案未判）。
- **抖动 0**：`SSHTunnelRuntimeTests` 那条本跳查实为**确定性**（连跑三档都红），已按 next_try 修掉
  （ssh 的 `Address already in use` 归 `.portInUse`）。
- **未复现 0**（没有一条给不出复现步骤）。
