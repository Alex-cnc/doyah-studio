# 判据维护第八片（无台账行 · 脚本级）· 2026-11-02

队列空（34 done / 1 blocked）⇒ 继续逐族清自检红。本片清 4 族，其中 **2 族是真仓库红**（不是夹具漂移）。

## 1. palette-wiring —— 真仓库红：`slowQuery` 有面板、没落点

B5 批次上盘 `FR-DIAG-03` 慢查询排行时，`AppCommandCatalog` 加了 `slowQuery`、`performPaletteCommand`
里 `case "slowQuery": isSlowQueryPresented = true`、`MainWindow` 也 `.sheet(isPresented:)` —— 界面全在，
**唯独探针落点表没登记**，于是 `TestsUISnapshot/PaletteWiringProbeTests.swift` 的
`testEveryCommandHasARegisteredLanding` 一直是红的，而它要 `DOYAH_UI_SNAPSHOT=1` 才跑 ⇒ 每轮门禁看不见。

修法：落点表是真的少了这一条，补进去（不是登记豁免）——`Flag` 加 `slowQuery`（`isSlowQueryPresented`）、
`isOn` 加一档、`wiring` 加 `("slowQuery", .panel(.slowQuery))`；`PROBE_FLOOR` 33 → 34 同步跟版。

```
$ python3 Scripts/check-palette-wiring.py | tail -1
   落点表对账：探针 34 条 ↔ 清单 40 条 · 未登记差集 0 条 · 已登记缺口 6 条
$ python3 Scripts/check-palette-wiring.py --self-test | tail -1
负例自检：13 条中 13 条达到预期
```

负例（撤掉那一行落点 ⇒ 必须红，且下限也兜住）：
```
   命令「slowQuery」在清单里，但探针落点表…**未登记**它（未登记差集 1 条：['slowQuery']）
   落点表只读到 33 条（下限 34）—— 面被掏空不许当通过
```
还原后 rc=0。行为面也真跑过：

```
$ DOYAH_UI_SNAPSHOT=1 swift test --filter PaletteWiringProbeTests
error: … XCTAssertTrue failed - 这 6 条命令没人登记落点…["newNote","newNotebook","noteAllNotes",
       "noteFavorites","noteSearchScopeAll","noteSearchScopeCurrent"]      ← 既有 6 条（已登记缺口），
       **不含 slowQuery** ⇒ 新补的这条落点真的被驱动到了；testEveryCommandLandsItsRegisteredEffect 通过
```

## 2. panel-root-frames —— 真仓库红：台账落后 14 个视图文件

```
（视图文件 118 个 / 固定尺寸 frame 46 处（面板根 26 · 装饰 20） / 台账 39 条）
❌ 台账 scannedFiles = 104，实测 118 / totals.frames = 41，实测 46 …
   未登记：DebugPanelView:32 · EditAssistSheet:26 · SlowQueryPanel:32 · QQQRLoginSheet:41/36
```
5 处固定尺寸 frame 早就上盘、台账一条没记（含 `FR-STD-WS-TOOL-003` 调试面板、`FR-STD-WS-AI-001` 编辑辅助）。
逐条按源码写意图：三个面板根里 `DebugPanelView` / `EditAssistSheet` 显式写了 `alignment: .topLeading`
（路线 `explicit-alignment`，逐字对账），`SlowQueryPanel` 排行那一路是 `ScrollView` 且三态分支显式
`maxHeight: .infinity` ⇒ `content-stretches`；两张二维码图（232 / 208）是装饰。台账 `scannedFiles` 与
`totals` 同批跟版。

```
$ python3 Scripts/check-panel-root-frames.py | tail -2
（面板根路线分布：content-stretches 19 / explicit-alignment 7）
✅ 面板根 frame 对齐纪律通过（每一处固定尺寸都在台账里，面板根的意图都有盘上锚点）
$ python3 Scripts/check-panel-root-frames.py --self-test | tail -1
✅ 负例自检：19 条中 19 条达到预期
```
负例（临时台账删掉 `SlowQueryPanel` 那条）⇒ `❌ 不通过（3 处）` 并点名 `SlowQueryPanel.swift:32`。

## 3. editor-line-numbers —— 夹具锚点失效

`final class SQLTextView: NSTextView {` 在加 `UndoScopedEditor` 一致性后变成
`final class SQLTextView: NSTextView, UndoScopedEditor {` ⇒ 自测第一条断言就 Traceback。锚点改成前缀
`final class SQLTextView: NSTextView`，并把坏样本改成在类声明**之前**插一个 `extension`（不再依赖继承列表写法，
产物仍是合法 Swift）。

```
$ python3 Scripts/check-editor-line-numbers.py --self-test | tail -1
自检：10 例，10 达标，0 失败
$ python3 Scripts/check-editor-line-numbers.py | tail -1
✓ 编辑面台账自洽：… 扫描范围 App/**/*.swift：168 份源文件（下限 90） / 6 个编辑面（下限 2）
```

## 4. script-portability —— 夹具硬钉文件名，三例整组哑火

例 2 锚 `check-doc-versions.py` 里 `relative = identity_text(path.relative_to(root))` 这一行，该处早已改走
`identity_text` ⇒ 例 2「准备失败」，例 5/6/7 也都指着同一文件 ⇒ 实际只跑 6/8 例。改成在副本里**现找**第一个
真带 `.relative_to(…).as_posix()` 的行，把它换成 `str(…)`，三例的豁免目标也用这同一个文件 ⇒ 盘上写法再变不哑火。

```
$ python3 Scripts/check-script-portability.py --self-test | tail -1
自检：例数 8 / 通过 8 / 失败 0
$ python3 Scripts/check-script-portability.py | tail -1
✅ 脚本可跨平台：… （99 个脚本 / 33049 代码行；形状红线命中 0 处）
```

## 提交与未验证

- 提交：见本次 commit（`Scripts/` × 3、`TestsUISnapshot/` × 1、`Scripts/panel-root-frames.json`）
- `swift test` ⇒ **Executed 5078 tests, with 13 tests skipped and 0 failures**（另有一次同命令报
  `1 failure` 未抓到失败名，重跑两次均 0 failure ⇒ 记「疑似抖动、未定位」，不当通过）
- 文档门禁五道 rc=0（tables 74 文件 / numbers 三向 / plan-coverage / status-consistency / version-scope）
- 未验证：`check-self-test-counts` 全跑读数见 checkpoint（同跳实测）；真机点验 0 次、217 真库 0 次；
  `DOYAH_UI_SNAPSHOT=1` 全量探针未跑（只筛 `PaletteWiringProbeTests` 一族，且该族既有 6 条笔记缺口仍红）
