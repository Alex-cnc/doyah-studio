# D2-1 · `FR-NTS-ALL-HOME-001` 首页可配置（默认落页）· 2026-11-02

## 落法（四件，全部在盘上）
- `Plugins/Notes/Sources/NoteLandingPage.swift`（新）：**只有两个取值**（原值 `todo` / `notes`，契约钉死）、键 `notes.home` 一处、`resolve(stored:)` 一处解析（没存过 / 空串 / 认不出 ⇒ `defaultPage` = 待办）、`load` / `store` 一处读写入口。
- `App/AppState.swift`：`noteLandingPage` 在 `init` 里读一次（= 一次冷启动）；`notesModule` 初值**由它派生**（原来写死的 `= .notes` 删掉）；写入口只有 `setNoteLandingPage`（不跳页 / 不动库 / 不动当前屏）；`setNotesModule` 不写回偏好。
- 设置面板 = `App/Views/AppearanceSheet.swift` 新增「笔记首屏」段（二选一 segmented，`notes-landing-picker`）+ 语言表两键两语（`notesLandingSection` / `notesLandingHint`）。macOS 唯一的设置面板就是「外观…」⇒ 按契约「设置页『通用 / 外观』组、不进关于页」落这里。
- 顺带清存量：`Scripts/check-note-module-isolation.py` 的 `NOTE_SOURCES` 补登 8 件（含本片新文件 + 之前一直报漏登的 7 件，逐件核过 `import` 面只有 Foundation）⇒ 该门禁 **8 条红 → rc=0**；`Scripts/core-localization-english.json` 给 `SELECT uid FROM notebook` 补一条 `kind: sql` ⇒ 棘轮 B 回到 rc=0。

## 判据（命令 + 读数尾部）
```
$ python3 Scripts/ledger-row.py FR-NTS-ALL-HOME-001
FR-NTS-ALL-HOME-001 ✅（2026-11-02 D2 落 macOS 端：…）

$ DEVELOPER_DIR=… swift test --filter NoteLandingPageTests
Executed 7 tests, with 0 failures (0 unexpected) in 0.047 (0.048) seconds

$ bash Scripts/verify-core.sh
ℹ️ Core 单测 5348 项（已写入 …/.build/core-test-count.txt）   # 5341 → +7，0 失败

$ bash Scripts/verify-ui-interactions.sh
✓ 133 条都真跑过（十九批）、都以 passed 收尾、没有跳过

$ python3 Scripts/check-doc-*.py / check-{status-consistency,plan-coverage,status-gap,agents-index,core-localization,note-module-isolation,design-tokens,panel-root-frames,literal-language,copy-emphasis,palette-wiring}.py
全 rc=0；`check-doc-numbers` 三向 5348（台账 ↔ 实测 ↔ AGENT-SPEC.md 两处同批改数）
$ python3 Scripts/plan-batches.py --version 0.7.0 --check
✅ 批次队列一致（2 条待办，台账复算一致）
```

## 反例（三段，判红后 `sha256` 逐字节还原 `2fca23b7…` / `bfa60b34…`）
- `defaultPage` 改成 `.notes` ⇒ ② 判红 **4 断言**（nil / 空串 / 坏值 / 全新域全变笔记）。
- `setNotesModule` 里补一句 `NoteLandingPage.store(…)` ⇒ ⑤ 判红 **1 例**（`notes.home` 被写回 = 记住上次所在页）。
- `AppState.init` 里把 `notesModule` 写回 `.notes` ⇒ ② 冷启动那半判红 **2 断言**（未设置 / 坏值都落笔记）。

## 未验证（≠ 通过）
- **整个 App 的首屏仍是活动栏记忆**（`ui.activityBarItem`，属 `FR-EDIT-32`）：本条只管**笔记区首屏**，不承诺「开机自动进笔记」。这条口径写进台账判据格与测试头注。
- 真鼠标点设置面板那枚二选一**未点**（机械证据在 `AppState` 方法层 + 纯值 + 源锚点）。
- ④「不牵连提醒 / 同步 / 私密」只到**源锚点**（`setNoteLandingPage` 函数体里无那三条链路的符号）；真通知中心在 `swift test` 宿主里会崩（见 `TodoCalendarEntriesProbeTests` 头注），故到点提醒未实测。
- 移动三端未动：Android 详设 §3.9 的实现在 Notes 仓（本仓无平台源码），iOS / 鸿蒙未实现 —— 端间差异须按 `FR-NTS-ALL-PARITY-001` 在《平台对齐-移动端-以安卓为基准》登记。
- `check-book-subset` / `check-format-arguments` 是本跳**未动**的存量红（前者点名能力书 §5.3.3 与全量书的分册口径，后者 227 > 188 的登记预算；逐条核过，报的点名不在本片改动面上）。

提交：见本轮提交（`D2 第二条 FR-NTS-ALL-HOME-001 …`）
