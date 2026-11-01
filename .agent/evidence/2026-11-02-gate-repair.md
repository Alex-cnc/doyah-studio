# 判据维护 · 2026-11-02（空队列跳）

条目：无台账行（v0.3.0 队列 0 条 todo；本片只修两条**判据自身**的坏处，不改任何产品行为、不动台账状态位）

## 1. `Scripts/test-sidebar-collapse-state.py` 整套负例停在第 7 条

由头：第 7 条把「`if section.isUngrouped {` 的下一行是 `Text(title)`」写进了夹具前提，B7 把那一行换成
`groupHeader(title:count:id:)` 之后 `edit()` 断言崩掉 ⇒ **第 8–23 条（含两条空跑防护）从此一次没跑过**，
而文档里一直写着「23 例」。

修法：注入口只钉 `if section.isUngrouped {` 这一行（分支首行 = 门禁自己的判据输入 `UNGROUPED_GUARD`），
不再连带下一行。

## 2. `Scripts/check-sidebar-collapse-state.py` 行号误报 + 同一条报两遍

由头：`view_local_collections()` 对每个 `@State` 行拼 3 行窗口，命中后把名字记在**窗口起始行**。`AgentChatView`
里 `copiedMessageID`（:67）与 `collapsedToolBlocks`（:69）上下相邻 ⇒ 同一条声明报两次（:67 与 :69），
其中 :67 指着一行无关代码。照它去改会改错行。

修法：折行只向下拼，遇到下一条 `@State` 即停；命中时行号取 `var` 真正落的那一行。
另加负例第 10 条（相邻两条 `@State` + 折行声明）把「一条声明只报一条、行号指向声明本身」钉住。

判据：
$ python3 Scripts/test-sidebar-collapse-state.py
  ✅ 未分组那一段加了折叠 ⇒ 判红
  ✅ `App/AppState.swift` 不在 ⇒ 判红（空跑不许通过）
  ✅ `sectionView` 改名（判据取不到输入）⇒ 判红
  ✅ 相邻两条 `@State`：一条声明只报一条、行号指向声明那行（折行的按 `var` 那行）⇒ 判红且不误报
  结果：24 通过 / 0 未达预期        （修前：Traceback，停在 7/23）

$ python3 Scripts/check-sidebar-collapse-state.py
  ❌ 折叠状态归属门禁未通过（1 项）：
     - App/Views/AgentChatView.swift:69：视图里出现 `@State` 折叠状态 `collapsedToolBlocks` …
  rc=1                              （修前：2 项，:67 与 :69 同一条）

红 / 绿成对（同一夹具、只换解析器）：
  旧：AgentChatFixtureView.swift:4（错行）+ AgentChatFixtureView.swift:5 ⇒ 2 条
  新：AgentChatFixtureView.swift:5 ⇒ 1 条

$ python3 Scripts/check-doc-tables.py / check-doc-numbers.py / check-plan-coverage.py / check-status-consistency.py / check-version-scope.py
  五道 rc=0（74 文件 · 三向一致 · 471 条 · 471 条 · 471 条）

提交：见下一片「证据补记提交号」

未验证：
- `AgentChatView.collapsedToolBlocks` 仍红的**那一条是真缺陷**（`WorkspaceAreaView.content` 的
  `else if let tab = tabs.selectedTab` 分支里创建 ⇒ 切页签回来整个重建、收起态归零），但修它要把
  `collapsedToolBlocks` / `expandedToolBlocks` / `expandedPreview` 三个集合上移并按会话淘汰，
  属产品改动、且台账里没有对应行 ⇒ 本片**不擅自动**，留给主人排进下一版队列。
- 真机鼠标点三角：0 次（不在本片范围）。
