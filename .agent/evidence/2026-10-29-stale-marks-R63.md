# R63 · 2026-10-29 · 陈旧标记归正（8 条判据列 🟡 → ✅）

轮次：R63（条号 = 台账里 8 行，主条 `FR-STD-WS-NAV-004`）
性质：**只翻标记、不加用例**（Core 代码与测试零改动）

## 1. 取活依据

`loop-card.md` R62 段的「下一条活 ①」：`FR-STD-WS-NAV-004` 走陈旧标记归正。
扫描全表（213 行 `FR-STD-*`）后，同类陈旧共 8 行：判据列 🟡 而备注/用例已在盘上。

## 2. 实测（先数用例，再逐套件跑）

```
grep -c '    func test' Tests/<file>.swift          # 静态条数
swift test --filter <Suite>                         # 实测读数（DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer）
```

| 台账条 | 套件 | 静态 | 实测读数 |
|---|---|---|---|
| FR-STD-WS-NAV-004 | InlineGhostCompletionTests | 18 | Executed 18 tests, with 0 failures |
| FR-STD-WS-NAV-004 | InlineGhostSQLTests | 12 | Executed 12 tests, with 0 failures |
| FR-STD-WS-NAV-004 | InlineGhostPathTests | 16 | Executed 16 tests, with 0 failures |
| FR-STD-WS-FS-009 | WorkspaceChangeScopeTests | 9 | Executed 9 tests, with 0 failures |
| FR-STD-WS-EDIT-013 | WorkspaceHeaderSearchTests | 12 | Executed 12 tests, with 0 failures |
| FR-STD-WS-UI-003 | WorkspaceClosePolicyTests | 10 | Executed 10 tests, with 0 failures |
| FR-STD-WS-EDIT-006 / 007 | MarkdownEditingTests | 18 | Executed 18 tests, with 0 failures |
| FR-STD-WS-EDIT-019 | CodeAutoPairingTests | 21 | Executed 21 tests, with 0 failures |
| FR-STD-WS-EDIT-008 | CodeCommentToggleTests | 12 | Executed 12 tests, with 0 failures |

九个 `--filter` 全部 `rc=0`。

## 3. 界面接线旁证（判据 ✅ / 实现 🟡 的依据）

```
grep -rl <Core 类型> App/ Platform/macOS/
InlineGhostCompletion  → App/Views/CodeEditorView.swift App/Views/GhostTextOverlay.swift
WorkspaceChangeScope   → App/WorkspaceStore.swift
WorkspaceHeaderSearch  → App/WorkspaceStore.swift App/Views/WorkspaceExplorerView.swift App/Views/WorkspaceHeaderSearch.swift App/Views/SearchPresentation.swift
WorkspaceClosePolicy   → App/Views/WorkspaceTabStrip.swift App/WorkspaceTabsModel.swift
MarkdownListEditing    → App/Views/CodeEditorView.swift
CodeAutoPairing        → App/Views/CodeEditorView.swift
CodeCommentToggling    → App/Views/CodeEditorView.swift:1085
```

## 4. 三处旧数字按实测改登记（旧说法作废、不删行）

- `FR-STD-WS-EDIT-013`：「30 条 Core 判据」⇒ 实测 `WorkspaceHeaderSearchTests` **12 例**（旧数字对不上任何单一文件）。
- `FR-STD-WS-UI-003`：「8 例」⇒ 实测 **10 例**。
- `FR-STD-WS-EDIT-006`：「17 例」⇒ 实测 **18 例**。

## 5. 如实下调一处

`FR-STD-WS-FS-009` 实现列 **✅ → 🟡**：该行备注自己写着「剩：界面点验（真正在外部改一个文件看树不塌、页签提示）」，
与口径 2「不能自己判的一律留 🟡、不假装完成」相抵。功能未退，只是标记改回如实 —— 这也是实现族 ✅ 127 → 126 的唯一原因。

## 6. 收尾读数

```
bash Scripts/verify-core.sh
rc=0
ℹ️ Core 单测 4825 项（.build/core-test-count.txt = 4825 tests）   # 与 R62 同值：本轮零新增用例

python3 Scripts/check-doc-numbers.py     rc=0  ✅ 文档数字对账通过（命中 118 处）
python3 Scripts/check-doc-tables.py      rc=0  ✅ 表格校验通过（71 个文件）
python3 Scripts/check-doc-versions.py    rc=0  ✅ 版本纪律通过（17 份）
python3 Scripts/check-doc-invariants.py  rc=0  ✅ 5 条铁律全部成立
python3 Scripts/check-version-scope.py   rc=0  ✅ 版本范围校验通过（台账 462 条）
python3 Scripts/check-format-arguments.py rc=0 ✅ 占位符 ↔ 实参对账通过（453 处）
```

分族读数（逐行实数）⇒ 实现 **✅ 126 / 🟡 81 / ⬜ 6 = 213**；判据 **✅ 158 / 🟡 48 / ⬜ 6 / — 1 = 213**。

## 7. 产物

本轮**零源码 / 零资源改动**（只动 `Docs/` 台账与本目录留档）⇒ 未重建 `.app`，产物沿用
`dist/DoyahStudio-beta1.0.app` sha256 **`594b301e`**（构建时刻 2026-10-29T06:22:20+0800）。
同标签下未再出过第二份，无需作废任何一份。
