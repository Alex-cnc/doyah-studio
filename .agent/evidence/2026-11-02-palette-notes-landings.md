# 2026-11-02 · 判据维护第十二片：笔记面 6 条命令的落点（不是「没落点」，是「落点看不见」）

- 队列状态：`.agent/plan.yaml` = **0 todo / 1 blocked**（`FR-STD-DB-META-002` GBase 8a 无实例）⇒ 本跳继续脚本级维护。
- 上一跳留下的 next_try：判 `PaletteWiringProbeTests` 那 6 条笔记命令「是否真有落点」。**判完的结论：有落点，但只在笔记面看得见。**

## 一、判的过程（先查再改，不猜）

1. 清单 ↔ 分派器：`AppCommandCatalog.all()` 里有这 6 条，`performPaletteCommand` 里也有 6 个 case —— 静态接线是通的。
2. 状态 ↔ 视图：`notesScope` ← `Plugins/Notes/Views/NotesPanel.swift:805`（左栏选中态）；`notesSearchScope` ← `:1401`（`Picker` 选中）；`pendingContainerEdit` ← `:702`（`.sheet(isPresented:)`）；`editorMode` ← `:864` / `:882`。**四个状态都有视图读**，不是当年那种「设了没人看的标志位」。
3. 但**命令挂在全局面板上**：`CommandPaletteView.commandMatches` 直接吃 `AppCommandCatalog.all()`，不按活动面 / 档位过滤。Ultra 档（工作区 + 数据库 + 笔记三块都在）下，人站在数据库面 ⌘K 搜「笔记」→ 点「新建笔记」⇒ 分派器只改笔记面的状态，**屏幕上什么都不动**。这是一族「点了没反应」，只是这次藏在「状态确实变了」后面 —— 静态判据第 3 项（只看「有没有人读」）和探针旧落点表（没登记）都看不见它。
4. 实测取证（临时探针，跑完即删）：`.standard` 档只含笔记（`visible=[notes, retro]`），站在数据库面这件事在那一档构造不出来；`.ultra` 下 `selectedActivityItem` 停在 `database`，6 条命令执行后 `activity` 仍是 `database`。

## 二、改了什么

1. **产品侧一处前置**（`App/AppState.swift`）：新增 `enterNotesAreaForNotesCommand()` —— 不含笔记的档位（Pro）照实说 `L(.licenseNotesNotIncluded)`（与 `openNotes()` 同一口径），否则 `selectActivityItem(.notes)`。6 个 case 各加一句 `guard ... else { return }`，动作本体一行未改（仍调 `beginNewNote()` / `beginNewNotebook()` / `selectNotesScope(_:)` 这些既有入口）。
2. **探针落点表**（`TestsUISnapshot/PaletteWiringProbeTests.swift`）：新增 `NotesLanding`（`newNoteDraft` / `notebookCreation` / `searchScope` / `scope`）与 `Landing.notes(_:)`，6 条登记进 `wiring`（34 → **40** 条）；驱动 `driveNotesCommand` 起点固定在**数据库面**（Ultra 档），**先把「有没有被带到笔记面」判成断言的一半**，再判命令自己的状态。`newNotebook` 两档如实分判：有架 ⇒ `pendingContainerEdit.mode == .createNotebook`；一个架都没有 ⇒ 不许弹落不了地的框，必须说 `NotebookCreation.noShelfKey`。
3. **静态判据**（`Scripts/check-palette-wiring.py`）：`PROBE_FLOOR` 34 → 40、`CATALOG_FLOOR` 39 → 40（按实测跟版）、`KNOWN_WIRING_GAPS` **清零**（陈旧登记棘轮逼出来的销账）；`run_checks` 增 `gaps` 注入参数 —— 登记表空了就没法用真表证明棘轮还活着，改由自检注入「真缺 ⇒ 放行 / 陈旧 ⇒ 判红」两条夹具；`--self-test` 13 → **14 例**。
4. **派生物跟版**：`Scripts/verify-all.sh` 第 9 项注释（例数 + 落点表 40 = 清单 40）、`Scripts/self-test-counts.json`（cases 14 / why / 锚点）。
5. **文档一处如实回写**：`Docs/design/待人工验收清单.md` 那行「33 条命令 / 17 个标志位」→「40 条命令 / 18 个标志位」，并补一句这 6 条判两件事（被带到笔记面 + 自己的状态）。

## 三、判据读数（命令原文与尾部）

- `swift test --filter PaletteWiringProbeTests`（`DOYAH_UI_SNAPSHOT=1`）⇒ `Executed 2 tests, with 0 failures`（修前 `testEveryCommandHasARegisteredLanding` 红：未登记 6 条）。
- `python3 Scripts/check-palette-wiring.py` ⇒ `✅ 命令面板接线校验通过（命令清单 40 条全部有处理、关键词无空）`；赋值审计 22 处 / 20 个名字（`is` 前缀 18 / 其它状态 2）；**落点表对账：探针 40 条 ↔ 清单 40 条 · 未登记差集 0 条 · 已登记缺口 0 条**。
- `python3 Scripts/check-palette-wiring.py --self-test` ⇒ **14 条中 14 条达到预期**（修前 13 例；新增两例：登记真缺 `plantedGap` ⇒ 不报红 / 登记陈旧 `help` ⇒ 报红）。
- 负例两段（改坏 ⇒ 必须红 ⇒ 还原逐字节一致）：
  - 撤掉 `newNote` 的前置（保留 `beginNewNote()`）⇒ `1 failure`：`("database") is not equal to ("notes") - 「newNote」在数据库面点下去必须把人带到笔记面`。
  - 落点登记由 `.notes(.scope(.favorites))` 改成 `.notes(.scope(.all))` ⇒ `1 failure`：`("favorites") is not equal to ("all") - 「noteFavorites」必须把一级导航切到 all`。
  - 还原后 `sha256`：`AppState.swift 918c43ed…`、`PaletteWiringProbeTests.swift ce86c6a0…`（与改前一致），复跑 `Executed 2 tests, with 0 failures`。
- `./Scripts/run-manual-verification-probes.sh`（全量）⇒ **418 例 / 4 skipped / 1 failure**（本片入场时那条确定性红 —— `testEveryCommandHasARegisteredLanding` —— 已消失；唯一剩下的红是既有夹具缺陷，见五）。
- `env -u DOYAH_UI_SNAPSHOT ./Scripts/verify-core.sh` ⇒ **5078 例 / 13 skipped / 1 failure**（唯一红 = `SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything` 抖动；单族连跑 3 次 `4 tests / 0 failures` 三次全绿 ⇒ 记「抖动」，与本片无关）。
- `python3 Scripts/check-self-test-counts.py --no-run` ⇒ 族 54 / 例数 **1055** / 锚点 **86** 处，无锚点但写了理由的族 12（修前 1054 / 86）。
- 文档门禁五道（`check-doc-invariants` / `check-doc-tables` / `check-doc-numbers` / `check-plan-coverage` / `check-status-consistency`）+ `check-agents-index` / `check-version-scope` ⇒ 全部 `rc=0`。
- `CommandPaletteTests` ⇒ `Executed 13 tests, with 0 failures`。

## 四、覆盖边界（如实登记）

- **真机判据 0 次**：探针驱动的是真 `AppState`（真接口、真分派器），但**没有真鼠标**在屏幕上点那 6 条；「人看见界面切过去」这一步仍是人工点验清单的活。
- **217 真库 0 次**：本片不碰数据库面。
- **笔记面内容那一半没判**：`newNote` 只判「新建态 + 可写 + 四格为空」，**不预置内容** —— 预置会让 `beginNewNote()` 的「切走即存」真往用户库里写一条（探针不碰用户数据）。
- `newNotebook` 在探针里走的是「库上一个架都没有」那一档（`AppState` 未 `reloadNotes()` ⇒ `directory.shelves` 为空）；「有架 ⇒ 弹框」那一支由条件分支守着，**本机未触发过**（要真库有架才走得到）。

## 五、本片没修、留给下一片的（如实列）

- `NotesEditorSaveProbeTests.testN24FailureIsVisibleAndNeverAPopup` —— 夹具把笔记库连目录一起改只读，`PRAGMA journal_mode = WAL` 需要写权限 ⇒ 后台 `reloadNotes()` 读不出来、`errorMessage` 被设成 `.notesFileUnreadable`，于是判据④「全程无弹窗」判红。**自动保存那条路本身是对的**（同一次 dump 里 `state=failed(SQLITE_READONLY …)`），要改的是夹具（只坏写、不坏读）。
- `SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything` —— 全量里偶尔红（期望 `portInUse(端口)`，实测 `processExited("ssh 已退出：… Address already in use")`），单族连跑三次全绿 ⇒ 归因链在「ssh 自己先退出」与「端口被占」之间的先后竞态，next_try = 归因处把 ssh 的 `Address already in use` 也判成 `portInUse`。
- 自检族存量 **8 族红**（`cli-failure-readability` / `core-localization` / `design-tokens` / `language-registry` / `network-egress` / `release-version` / `terminal-tabs` / `tri-repo-parity`）—— 本片没动它们，**全跑未复跑**，读数沿用第十片。

## 六、按 `.agent/rules.md`「判据维护跳的出口」收尾（人类主人 2026-11-02 07:55 令，落在本跳之后的 `d23f274d`）

- **净减红数 = +1**（本轮清掉的红 1 条 = 取证脚本里那条确定性红 `testEveryCommandHasARegisteredLanding`；本轮新冒出的红 0 条）。按 `d23f274d` 口径：本跳之后**不再开判据维护跳**，当跳转 v0.4.0。
- **剩余红三分标注**：
  - `确定性失败`（1）`NotesEditorSaveProbeTests.testN24FailureIsVisibleAndNeverAPopup` —— 复现步骤：`./Scripts/run-manual-verification-probes.sh --filter NotesEditorSaveProbeTests`，本跳跑了两次（全量一次 + 上面这条定向一次）**都红**；根因已定位：夹具把笔记库连目录一起改只读，`PRAGMA journal_mode = WAL` 需要写权限 ⇒ 后台 `reloadNotes()` 读不出来、`errorMessage` 被设成 `.notesFileUnreadable`，判据④「全程无弹窗」判红。**自动保存那条路本身是对的**（同一次 dump 里 `state=failed(SQLITE_READONLY …)`）。修法 = 夹具只坏写、不坏读。
  - `抖动`（1）`SSHTunnelRuntimeTests.testBusyPortFailsFastWithoutStartingAnything` —— 全量 `verify-core.sh` 里红一次；单族连跑 3 次 `Executed 4 tests, with 0 failures` 三次全绿 ⇒ 同一棵树重跑不复现。
  - `未复现`（1）`QueryHistoryPaneProbeTests.testClearAndDeleteBothWaitForConfirmation` —— 上一跳全量三遍绿、本跳全量一次绿，**给不出复现步骤**（根因仍未判）。
  - `未执行`（**不算通过**）自检族 8 红（`cli-failure-readability` / `core-localization` / `design-tokens` / `language-registry` / `network-egress` / `release-version` / `terminal-tabs` / `tri-repo-parity`）—— 本跳没复跑全跑，读数沿用第十片，不许当「抖动」也不许当「已清」。
