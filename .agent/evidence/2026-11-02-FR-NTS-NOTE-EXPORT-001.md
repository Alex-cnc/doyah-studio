# FR-NTS-NOTE-EXPORT-001 · 2026-11-02

条目：FR-NTS-NOTE-EXPORT-001（导出与迁移：Markdown / 纯文本 / 备份包 + 导入完整还原）
判据：
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NoteArchiveTests
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.059 (0.060) seconds
$ bash Scripts/verify-core.sh
	 Executed 5354 tests, with 13 tests skipped and 0 failures (0 unexpected) in 39.595 (39.961) seconds
$ bash Scripts/verify-ui-interactions.sh
	 Executed 133 tests, with 0 failures (0 unexpected) in 44.155 (44.184) seconds   （无 skipped）
$ python3 Scripts/ledger-row.py FR-NTS-NOTE-EXPORT-001
FR-NTS-NOTE-EXPORT-001 ✅
$ 文档门禁 invariants / tables / numbers / plan-coverage / status-consistency / version-scope / doc-layout / agents-index / status-gap / palette-wiring 全 rc=0
$ python3 Scripts/plan-batches.py --version 0.7.0 --check → rc=0（1 条待办）

反例（各判红后 `sha256` 逐字节还原）：
- 版本判据放宽（`header.formatVersion <= current` → `< 1000`）⇒ 版本拒绝那一例红（rc=1，sha256 `8498b2f5…` 还原）
- 标签不还原（`Set(entry.tags)` → `Set<String>()`）⇒ 往返那一例标签断言红（rc=1，`70c76e23…` 还原）
- 私密过滤拿掉（去掉 `AND is_private = 0`）⇒ 三形态/私密那一例 4 条断言红（rc=1，`70c76e23…` 还原）

未验证：附件字节不随包走（只有引用）· 历史版本 / 时间线 / 回收站不进包 ·
原归属笔记本不在目标库时落默认并计数（不假装一模一样）· 真鼠标点「笔记」菜单四项未点 ·
移动三端未动。存量红（本片未新增）：`check-format-arguments` 预算 229 > 190 与
`<line>` / `<loadedRowCount>` 处数超限、`check-book-subset` —— 逐条核过不在本片改动面上。
