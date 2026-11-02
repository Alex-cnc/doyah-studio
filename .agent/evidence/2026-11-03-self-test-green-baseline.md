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

提交：`<sha>`

未验证（≠ 通过）：
- R-037 存量债 **30 处 / 30 份 Core 文件**本跳**一处未修**，只登记进 `Scripts/terminal-tabs-han-baseline.json` 先红基线（R-037 全局收口属别单）；堵的是"新增件再悄悄添债"。
- 三仓同源副本只有本仓在盘 ⇒ `check-tri-repo-parity` 比成 2 处、**4 处跳过**（Notes / Retro 是否同源未判；`--require-all` 会判红）。
- 4 份探针接进 `FILTER=` 后，只在**单族**里实跑过（21 例 0 失败）；整卷 `verify-ui-interactions` 的读数见全量那一行，未逐条核多出来的探针。
- `check-end-sheets` 的负例是在临时副本上手跑的（两个方向），未进 `check-self-test-counts` 台账（该脚本仍无自检族）。
- 真鼠标未点（本轮零界面新增，改的都是判据 / 台账 / 一处导出语言取值）。
