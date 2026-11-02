# 判据债第一片（Notes 8 条）· 2026-11-02

条目：FR-NTS-NOTE-FORMAT-001 / SEARCH-001 / ORG-001 / VERSION-001 / TRASH-001 / SYNC-001 / EXPORT-001 / PRIVACY-001

判据：
$ python3 Scripts/check-status-gap.py
  扫描面：台账 §3 全部行，跳过 `FR-RTR-*` ⇒ 实扫 389 行（判据为 `—` 的 1 行按不适用计数）
  ❌ 有 8 行实现已 ✅、判据还没跟上：FR-STD-WS-UI-008 / EDIT-016 / WEB-001 / FS-001 / FS-008 / NAV-002 / NAV-014 / AI-001
  （本片前是 16 行：Notes 8 + WS 8）
$ DEVELOPER_DIR=… swift test --filter "<Note* 15 族>"
  Executed 195 tests, with 0 failures        （NoteBodyTests 39 / NotebookTests 26 / NoteNavigationTests 23 / NotebookStorageTests 15 / NotePresentationTests 13 / NoteSyncTests 13 / NoteSyncConflictResolutionTests 12 / NoteDataBoundaryTests 11 / NotebookEditStorageTests 10 / NoteSyncAuthTests 8 / NotePrivacyTests 7 / NoteDeletionTombstoneTests 7 / NoteVersionTests 6 / NoteSyncTokenRefreshTests 5 / NotebookTests 26）
$ DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter "Notes*ProbeTests|NoteSearchProbeTests"
  NoteSearchProbeTests 5 · NotesEditorFormatProbeTests 12 · NotesSearchRevealProbeTests 3 · NotesShelfProbeTests 5 ⇒ 25 例 / 0 失败 / 0 skipped
$ python3 Scripts/check-doc-tables.py        ✅ 表格校验通过（74 个文件）
$ python3 Scripts/check-doc-numbers.py       ❌ 1 项（仅 [checkScriptParity]：check-status-gap.py 未接进 verify-all.sh —— 本片前就有）
$ python3 Scripts/check-status-consistency.py / check-plan-coverage.py / check-version-scope.py / check-doc-invariants.py / check-doc-layout.py / check-doc-versions.py  rc=0

提交：26579a0a

未验证：
- 6 条降为 🟡 的要点是**按要求书要点逐条核过的「不存在」**，不是没找：语义检索 / 笔记归档 / 回收站恢复 / 备份包与导入还原 均 `grep` 为 0；万行级性能与「撤销按段落」无探针。
- `NoteSyncE2ETests` 11 例要真云端，本轮未跑（未执行 ≠ 通过）。
- WS 那 8 条未动（本片只做 Notes 侧）；`check-status-gap.py` 仍未接进 `verify-all.sh`。
- 真鼠标点验未做。
