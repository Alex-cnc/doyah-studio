import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **笔记搜索 = 一枚图标 + 点击浮出的搜索框**（`FR-NOTEUI-04` · 派单 `T-20261010-166` §三.1 ①②③④）。
///
/// ## 由头（人类主人 2026-10-10 原话逐字）
///
/// 「**笔记搜索不要那么大一个框子，有个搜索图标就行，用户点击时再出现框子，跟工作区的搜索
/// 保持相同设计语言。**」
///
/// 改前实况（真机实拍 2026-10-10 20:08）：左区顶部那一行上**常驻**着一个输入框
/// （占位「搜索标题 / 正文 / 标签」）+ 右侧的作用域下拉 —— 一行里那一格是宽度主项
/// （片 `N2-2` 判据④：它一项就占掉 200pt）。
///
/// ## 判据（§三.1 逐条落成可跑断言 · 每条都印读数）
///
/// · **① 无常驻搜索框**：默认（收起）态下，活宿主**左区顶部操作行**那一条带里
///   `NSTextField` **0 个** —— 「元素 dump 无 field 常驻」量到的就是它；
/// · **② 点图标后 field 出现、输入即过滤**：走产品那一条入口 `AppState.revealNoteSearch()`
///   （图标按钮接的就是它，源锚点见 ④）之后，同一条带里 `NSTextField` **≥1 个**，
///   其中一个的占位**逐字等于** `L(.notesSearchPlaceholder)`；
///   输入即过滤那一半判的是**产品自己的线**：`notesQuery` 一改，`AppState.searchNotes()`
///   就把可见列表换掉（走真库；口径见 `Scripts/check-note-search-route.py`）；
/// · **③ 点外部 / ESC 收起**：收起态与展开态**成对**（同一条带里 0 个 → ≥1 个 → 0 个），
///   且收起 = `AppState.collapseNoteSearch()`（**收框 + 清词**同一处）；
/// · **④ 与工作区搜索同一呈现函数 / 同一图标形制**：
///   · **同一呈现函数** —— 两个面的框都由 `App/Views/SearchPresentation.swift` 的 `SearchField`
///     画出来（源锚点：`WorkspaceHeaderSearch.swift` 与 `NotesPanel.swift` 里各有一处
///     `SearchField {`），且**量出来的框高逐个相等**（同一段壳 = 同一个高度）；
///   · **同一图标形制** —— 图标符号只有一个出处 `SearchPresentation.symbolName`
///     （`magnifyingglass`），收起态那枚按钮与展开态框内那枚放大镜引用的是**同一个常量**。
///
/// ## 量法（与 `NotesLayoutProbeTests` / `TodoDetailSearchProbeTests` 同一套活宿主）
///
/// `UISnapshot.LiveHost` 把一个**不上屏**的 `NSWindow` + `NSHostingView` 架起来（`1100×700`，
/// 与 `NotesLayoutProbeTests.areaSize` 同值），泵几轮让布局落地，然后在同一坐标系里逐条量
/// `NSView` 的矩形 —— **不渲染位图、不开真窗口抢前台、不需要人在场**。
///
/// 「左区顶部操作行那一条带」的取法：**宿主上缘往下 60pt**（那一行自己只有 ~30pt，
/// 下面紧跟着分隔线与三栏；三栏里最上面那件控件也在这以下）。这条带里出现的一切
/// `NSView` 都进 dump（读数即证据），判据只在其中的 `NSTextField` 上。
///
/// ## 能判红（否则「量不到」会被读成「都对」）
///
/// 反例 = **改动前那一版**：那时收起态就是常驻输入框 ⇒ 判据 ① 当场红（同一条带里
/// `NSTextField` = 1 个）。这也是本探针的两个读数必须**不相同**的理由 —— 若两次都量到 0 个
/// （比如量法挑错了带），判据 ② 会红，不会静默通过。
///
/// ## 边界（如实登记）
///
/// · **点图标那一下真鼠标不在判据面里**：走的是图标按钮接的那个入口
///   （`AppState.revealNoteSearch()`，源锚点钉住「按钮 → 它」这一环）——
///   与 `NotesLayoutProbeTests` 登记的边界同源（离屏宿主里 SwiftUI 手势不响应合成事件）；
/// · **ESC / 点外部**这两条路同理：判到的是「收起这一个入口把两态收回去」
///   （`collapseNoteSearch()` 被三条路共用），键盘 / 鼠标那一环由真机点验补；
/// · 不判观感（圆角 / 描边好不好看）—— 那是并排截图给人看的那一半；
/// · 不碰用户数据：笔记库由 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录（没设就跳过）。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录>
///   swift test --filter NotesSearchRevealProbeTests`
final class NotesSearchRevealProbeTests: XCTestCase {

    /// 宿主尺寸：与 `NotesLayoutProbeTests.areaSize` 同一个（三栏骨架的最小整窗内容宽）。
    private static let areaSize = CGSize(width: 1100, height: 700)

    /// 「左区顶部操作行」那一条带的高度（pt）：宿主上缘往下这么多。
    private static let actionRowBand: CGFloat = 60

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本探针要起真 `AppState`（它读笔记库）⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
        )
    }

    /// 同一族的收尾（队列 `L-185` ①）：单跑一族探针时没有别人替它写清单。
    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 装配

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("noteui-01-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    @MainActor
    private func environment<V: View>(_ view: V, _ host: Host) -> some View {
        view.snapshotEnvironment(
            state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
        )
    }

    /// 笔记区那一份**真内容**（`NotesAreaView`：左区顶部操作行 + 三栏）。
    @MainActor
    private func notesArea(_ host: Host) -> AnyView {
        AnyView(environment(NotesAreaView(), host))
    }

    /// 工作区标头那枚**搜索呈现函数**的消费者（`FR-EDIT-44` 那个框）。
    @MainActor
    private func workspaceSearch(_ host: Host) -> AnyView {
        AnyView(environment(WorkspaceHeaderSearch(), host))
    }

    // MARK: - 元素 dump（那一条带里的每一件都读出来）

    /// 一条 dump 记录：类名 + 标识 + 在宿主坐标系里的矩形。
    private struct Row {
        let className: String
        let identifier: String
        let rect: CGRect
    }

    /// 宿主上缘往下 `band` 那一条带里所有 `NSView`（排除宿主自己）—— 读数即证据。
    @MainActor
    private func dumpActionRow(_ hosting: NSView, band: CGFloat = NotesSearchRevealProbeTests.actionRowBand) -> [Row] {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
            .filter { $0 !== hosting }
            .compactMap { view in
                let rect = hosting.convert(view.bounds, from: view)
                guard !rect.isEmpty, rect.width > 1, rect.height > 1 else { return nil }
                let top = hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
                guard top >= -1, top <= band else { return nil }
                return Row(
                    className: NSStringFromClass(type(of: view)),
                    identifier: view.accessibilityIdentifier(),
                    rect: rect
                )
            }
            .sorted { $0.rect.minX < $1.rect.minX }
    }

    /// 那一条带里的输入框（`NSTextField`）—— 判据只落在它身上。
    ///
    /// **要剔掉占位标签**：SwiftUI 的输入框在 AppKit 树里会多带一个
    /// `NSTextFieldSimpleLabel`（画占位文字的那一件，`NSTextField` 的子类）——
    /// 它的占位读法与输入框自己一样、矩形也贴着，混进来会让「框高」这个读数忽大忽小。
    @MainActor
    private func fieldsInActionRow(_ hosting: NSView) -> [NSTextField] {
        UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: hosting)
            .filter { !NSStringFromClass(type(of: $0)).contains("SimpleLabel") }
            .filter { field in
                let rect = hosting.convert(field.bounds, from: field)
                guard !rect.isEmpty, rect.height > 1 else { return false }
                let top = hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
                return top >= -1 && top <= Self.actionRowBand
            }
    }

    /// 一段文本控件在宿主坐标系里的矩形（几何判据读的是它，不是控件自己的 `frame`）。
    @MainActor
    private func rect(of view: NSView, in hosting: NSView) -> CGRect {
        hosting.convert(view.bounds, from: view)
    }

    private func pt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    private func describe(_ rows: [Row]) -> String {
        rows.map { "\($0.className)[\($0.identifier)] x=[\(pt($0.rect.minX))…\(pt($0.rect.maxX))] h=\(pt($0.rect.height))" }
            .joined(separator: " ｜ ")
    }

    /// **改前那一版的复刻件**（`N2-LW` 那条判据的同一个做法）：左区顶部操作行里的
    /// **常驻**搜索框 + 作用域下拉 —— 与卡上登记的现状（真机实拍 2026-10-10 20:08）同形。
    ///
    /// 为什么必须有它：判据 ① 说的是「改后那条带里 0 个输入框」——若量法自己恒读 0
    /// （带挑错了 / 找错了控件类），这句话就没有内容。复刻件用**同一条量法**量出 **1 个**，
    /// 于是「改前 1 → 改后 0」这一对读数才是判得动的。
    @MainActor
    private func legacyTopRow(_ host: Host) -> AnyView {
        AnyView(
            environment(
                HStack(spacing: Spacing.s) {
                    ToolbarIconButton(systemName: "plus", help: "新建") {}
                    ToolbarIconButton(systemName: "pencil", help: "编辑") {}
                    ToolbarIconButton(systemName: "trash", help: "删除") {}
                    // 改前那一格：**常驻**输入框（`.roundedBorder` + `maxWidth: 200`）+ 作用域下拉。
                    TextField(L(.notesSearchPlaceholder), text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Picker("", selection: .constant(NotesSearchScope.current)) {
                        Text(L(.notesSearchScopeCurrent)).tag(NotesSearchScope.current)
                        Text(L(.notesSearchScopeAll)).tag(NotesSearchScope.all)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.leading, Spacing.s)
                .padding(.vertical, Spacing.xs),
                host
            )
        )
    }

    // MARK: - ① ② ③：两态成对读数（同一条带：0 个 → ≥1 个 → 0 个）

    /// **收起态（默认）没有常驻输入框；点图标之后框子出现；收起之后它又没了。**
    ///
    /// 三个读数都在**同一条带、同一个宿主实例**上量出来 ⇒ 判据自足，不靠回执里手抄一个数。
    /// 断言形状与反例见类头注释（改动前那一版第 ① 步当场红）。
    @MainActor
    func testNoteSearchIsAnIconUntilClicked() async throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 笔记区渲染不出来")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        XCTAssertFalse(
            host.state.noteSearchRevealed,
            "前置：搜索那一格必须是**默认收起**的（`FR-NOTEUI-04`：无常驻搜索框）"
        )

        // 夹具一条笔记（走产品自己的库）：下面「输入即过滤」那半要有一个**非零的基准**
        // —— 库里一条都没有时，「查不到 ⇒ 0 条」是恒真的，判不出东西。
        _ = try await NoteLibrary.defaultLibrary().upsert(
            NoteDraft(title: "noteui-04 探针夹具", body: "这条只有探针会写")
        )
        await host.state.reloadNotes()

        let live = UISnapshot.LiveHost(notesArea(host), size: Self.areaSize)
        live.pump(0.6)

        // ── 改前那一版（复刻件）：同一条量法必须先量出 **1 个** 常驻输入框 ────────────────
        let legacyLive = UISnapshot.LiveHost(
            legacyTopRow(host), size: CGSize(width: 420, height: 40)
        )
        legacyLive.pump(0.4)
        let legacyRows = dumpActionRow(legacyLive.hosting)
        let legacyFields = fieldsInActionRow(legacyLive.hosting)
        print("NOTES-SEARCH-REVEAL 改前（复刻件）· 同一量法：输入框 \(legacyFields.count) 个 ｜ dump：\(describe(legacyRows))")
        XCTAssertEqual(
            legacyFields.count, 1,
            "改前那一版的复刻件没量出常驻输入框（实测 \(legacyFields.count) 个）——"
                + "量法自己挑错了带 / 控件类，下面那条「收起态 0 个」说明不了任何事"
        )

        // ── ① 收起态：那一条带里**一个输入框都没有** ───────────────────────────────
        let collapsedRows = dumpActionRow(live.hosting)
        let collapsedFields = fieldsInActionRow(live.hosting)
        print("NOTES-SEARCH-REVEAL ① 收起态 · 左区顶部操作行 dump（\(collapsedRows.count) 件）：\(describe(collapsedRows))")
        XCTAssertTrue(
            collapsedFields.isEmpty,
            "收起态下左区顶部那一行里还有 \(collapsedFields.count) 个输入框 —— 「有个搜索图标就行」没落地"
                + "（常驻搜索框就是改动前那一版：占位「\(collapsedFields.first?.placeholderString ?? "-")」）"
        )

        // ── ② 点图标（= 产品自己的入口）⇒ 框子出现 ────────────────────────────────
        host.state.revealNoteSearch()
        live.pump(0.6)
        let revealedRows = dumpActionRow(live.hosting)
        let revealedFields = fieldsInActionRow(live.hosting)
        print("NOTES-SEARCH-REVEAL ② 展开态 · 左区顶部操作行 dump（\(revealedRows.count) 件）：\(describe(revealedRows))")
        XCTAssertFalse(
            revealedFields.isEmpty,
            "点了搜索图标之后那一条带里一个输入框都没有 —— 框子没浮出来"
                + "（带内 \(revealedRows.count) 件：\(describe(revealedRows))）"
        )
        let placeholder = L(.notesSearchPlaceholder)
        XCTAssertTrue(
            revealedFields.contains { $0.placeholderString == placeholder },
            "浮出来的框子占位不是「\(placeholder)」（实测：\(revealedFields.map { $0.placeholderString ?? "-" })）"
        )
        // 两个读数必须**不相同**：否则「收起态 0 个」可能只是这条量法永远量不到东西。
        XCTAssertNotEqual(
            collapsedFields.count, revealedFields.count,
            "收起态与展开态量到同一个数（\(collapsedFields.count)）⇒ 这一对读数是恒真的"
        )

        // ── ②′ 输入即过滤：词一改，可见列表跟着换（产品自己那条线） ─────────────────
        host.state.notesQuery = "noteui-04-不存在这个词"
        await host.state.searchNotes()
        let filtered = host.state.visibleNotes.count
        host.state.notesQuery = ""
        await host.state.searchNotes()
        let unfiltered = host.state.visibleNotes.count
        print("NOTES-SEARCH-REVEAL ②′ 输入即过滤：查不到的词 ⇒ 可见 \(filtered) 条 ｜ 清空 ⇒ \(unfiltered) 条")
        XCTAssertGreaterThan(unfiltered, 0, "清空搜索词之后可见列表还是 0 条 —— 基准不成立（夹具没进库？）")
        XCTAssertEqual(filtered, 0, "搜索框里的词改了，可见列表没跟着换 —— 「输入即过滤」没落地")

        // ── ③ 收起（ESC / 点外部共用这一个入口）⇒ 框子回去 ────────────────────────
        host.state.notesQuery = "noteui-04-不存在这个词"
        host.state.collapseNoteSearch()
        live.pump(0.6)
        let afterCollapseRows = dumpActionRow(live.hosting)
        let afterCollapseFields = fieldsInActionRow(live.hosting)
        print("NOTES-SEARCH-REVEAL ③ 收起后 · 左区顶部操作行 dump（\(afterCollapseRows.count) 件）：\(describe(afterCollapseRows))")
        XCTAssertFalse(host.state.noteSearchRevealed, "收起之后展开态还立着")
        XCTAssertEqual(host.state.notesQuery, "", "收起只收了框、没清词 —— 列表会继续按一个看不见的词过滤")
        XCTAssertTrue(
            afterCollapseFields.isEmpty,
            "收起之后那一条带里还剩 \(afterCollapseFields.count) 个输入框 —— 「点外部 / ESC 收起」没落地"
        )
        XCTAssertNotEqual(
            revealedFields.count, afterCollapseFields.count,
            "展开态与收起后量到同一个数（\(revealedFields.count)）⇒ 这一对读数也是恒真的"
        )

        try writeEvidence("search-reveal-dump", [
            "legacyRowFieldCount": legacyFields.count,
            "collapsedRowCount": collapsedRows.count,
            "collapsedFieldCount": collapsedFields.count,
            "revealedRowCount": revealedRows.count,
            "revealedFieldCount": revealedFields.count,
            "revealedPlaceholders": revealedFields.map { $0.placeholderString ?? "-" },
            "afterCollapseFieldCount": afterCollapseFields.count,
            "filteredCount": filtered,
            "unfilteredCount": unfiltered,
            "legacyDump": legacyRows.map(describeRow),
            "collapsedDump": collapsedRows.map(describeRow),
            "revealedDump": revealedRows.map(describeRow),
            "afterCollapseDump": afterCollapseRows.map(describeRow),
        ])
    }

    private func describeRow(_ row: Row) -> String {
        "\(row.className)[\(row.identifier)] x=[\(pt(row.rect.minX))…\(pt(row.rect.maxX))] "
            + "y=[\(pt(row.rect.minY))…\(pt(row.rect.maxY))]"
    }

    // MARK: - ④：同一呈现函数 / 同一图标形制

    /// **两个面的框子是同一段代码画出来的**（判据 §三.1 ④）。
    ///
    /// 两半：
    ///   · **源锚点**：`App/Views/SearchPresentation.swift` 是唯一出处
    ///     （`SearchField` + `SearchPresentation.symbolName`），
    ///     `WorkspaceHeaderSearch.swift` 与 `NotesPanel.swift` 里各有一处 `SearchField {` ——
    ///     **画「放大镜 + 圆角底 + 描边」那段代码在 `App/Views/` 里只出现一次**；
    ///   · **几何同形**：两个面渲染出来的输入框**高度逐点相等**（同一个壳 = 同一个高度；
    ///     若哪一面自己又画了一套填充 / 内边距，高度当场就分家）。
    @MainActor
    func testSearchChromeIsTheSameFunctionOnBothFaces() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)

        // ── 源锚点：唯一出处 + 两个消费者 ──────────────────────────────────────────
        let presentation = try source("App/Views/SearchPresentation.swift")
        for anchor in [
            "enum SearchPresentation",
            "static let symbolName = \"magnifyingglass\"",
            "struct SearchField<Content: View>: View",
            "struct SearchRevealButton: View",
        ] {
            XCTAssertTrue(presentation.contains(anchor), "呈现函数里找不到锚点 `\(anchor)`")
        }
        XCTAssertEqual(
            presentation.components(separatedBy: "RoundedRectangle(cornerRadius: Radius.control, style: .continuous)").count - 1,
            2,
            "搜索框的壳（圆角底 + 描边）在呈现函数里应当正好两处（底一次、描边一次）"
        )
        for file in ["App/Views/WorkspaceHeaderSearch.swift", "App/Views/NotesPanel.swift"] {
            let text = try source(file)
            XCTAssertTrue(
                text.contains("SearchField {"),
                "`\(file)` 没用上唯一的搜索框呈现函数（`SearchField {`）—— 两个面会各画一份"
            )
        }
        // 笔记面那两态的**接线**（探针驱动的是 `AppState` 上那两个入口，所以「图标按钮接的就是它」
        // 这一环必须钉住 —— 与 `NotesLayoutProbeTests` 判「点界面那枚按钮」同一条纪律）。
        let panel = try source("App/Views/NotesPanel.swift")
        for anchor in [
            "SearchRevealButton(help: L(.notesSearchPlaceholder))",
            "appState.revealNoteSearch()",
            "appState.collapseNoteSearch()",
            ".onKeyPress(.escape)",
        ] {
            XCTAssertTrue(panel.contains(anchor), "`App/Views/NotesPanel.swift` 里找不到锚点 `\(anchor)`")
        }
        // 「第二套框」的负向断言：这两个面里都不该再自己画那个圆角底 / 描边。
        for file in ["App/Views/WorkspaceHeaderSearch.swift", "App/Views/NotesPanel.swift"] {
            let text = try source(file)
            XCTAssertFalse(
                text.contains("Image(systemName: \"magnifyingglass\")"),
                "`\(file)` 里又自己画了一枚放大镜 —— 图标形制必须只有一处（`SearchPresentation.symbolName`）"
            )
        }
        // 图标符号的**唯一出处**：这两个面里都不许再写死那个符号（其它面 —— 待办日历、
        // 对象树、命令面板 —— 各有自己的 FR，不在本片范围，原样不动）。
        let literalOnTheseFaces = try appViewFilesContaining("\"magnifyingglass\"")
            .filter { ["App/Views/NotesPanel.swift", "App/Views/WorkspaceHeaderSearch.swift"].contains($0) }
        XCTAssertTrue(
            literalOnTheseFaces.isEmpty,
            "这两个面里还写死了放大镜符号：\(literalOnTheseFaces) —— 图标形制必须只有一处"
                + "（`SearchPresentation.symbolName`）"
        )

        // ── 几何同形：两个面的输入框高度逐点相等 ──────────────────────────────────
        host.state.revealNoteSearch()
        let notesLive = UISnapshot.LiveHost(notesArea(host), size: Self.areaSize)
        notesLive.pump(0.6)
        let notesFields = fieldsInActionRow(notesLive.hosting)
        let notesField = try XCTUnwrap(
            notesFields.first { $0.placeholderString == L(.notesSearchPlaceholder) },
            "笔记面展开态里没量到那个框子（实测 \(notesFields.map { $0.placeholderString ?? "-" })）"
        )

        let workspaceLive = UISnapshot.LiveHost(
            workspaceSearch(host), size: CGSize(width: 360, height: 260)
        )
        workspaceLive.pump(0.6)
        let workspaceFields = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: workspaceLive.hosting)
            .filter { !NSStringFromClass(type(of: $0)).contains("SimpleLabel") }
        let workspaceField = try XCTUnwrap(
            workspaceFields.first { $0.placeholderString == L(.workspaceHeaderSearchPlaceholder) },
            "工作区标头那枚框子没量到（实测 \(workspaceFields.map { $0.placeholderString ?? "-" })）"
        )

        let notesFieldRect = rect(of: notesField, in: notesLive.hosting)
        let workspaceFieldRect = rect(of: workspaceField, in: workspaceLive.hosting)
        let notesHeight = notesFieldRect.height
        let workspaceHeight = workspaceFieldRect.height
        print(
            "NOTES-SEARCH-REVEAL ④ 几何同形：笔记面框高 \(pt(notesHeight))pt（\(NSStringFromClass(type(of: notesField)))）"
                + " ｜ 工作区标头框高 \(pt(workspaceHeight))pt（\(NSStringFromClass(type(of: workspaceField)))）"
        )
        XCTAssertGreaterThan(notesHeight, 4, "笔记面那个框子量出来的高度不合理（\(pt(notesHeight))pt）")
        XCTAssertEqual(
            notesHeight, workspaceHeight, accuracy: 0.5,
            "两个面同一个呈现函数，框高却不一样（笔记面 \(pt(notesHeight))pt / 工作区 \(pt(workspaceHeight))pt）"
                + " —— 有一面在自己画壳"
        )

        try writeEvidence("search-chrome-parity", [
            "notesFieldHeight": Double(notesHeight),
            "workspaceFieldHeight": Double(workspaceHeight),
            "viewsContainingMagnifyingglassLiteral": literalOnTheseFaces,
        ])
    }

    // MARK: - 成对截图（给人判的那一半）

    /// **成对截图**：收起态 / 展开态（笔记面）与工作区标头那枚框子，各出中英两张。
    ///
    /// 三种图落在 `DOYAH_SNAPSHOT_DIR`（与其余取证图同一处）：
    ///   · `noteui-04-notes-search-collapsed{-zh,-en}` —— 收起态：那一行上只有图标；
    ///   · `noteui-04-notes-search-revealed{-zh,-en}` —— 展开态：框子浮出来（并排看同一行）；
    ///   · `noteui-04-workspace-search-field{-zh,-en}` —— 工作区标头那枚框子（同一呈现函数）。
    ///
    /// **为什么用 `writeBothLanguages`（每遍重建视图树）而不是活宿主那套 `captureBothLanguages`**：
    /// 那套是给「同一个实例 + 跨时刻」的仪器图用的，语言只包在同一棵已经画好的树上（本片实测：
    /// 中英两张**逐字节相同** —— 语言到不了像素）。这三张判的正是**文案差异**（占位 /
    /// 列表头部那几句），必须让每一遍**重新构造**视图树。
    @MainActor
    func testPairedScreenshots() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)

        try UISnapshot.writeBothLanguages("noteui-04-notes-search-collapsed", size: Self.areaSize) {
            notesArea(host)
        }

        host.state.revealNoteSearch()
        try UISnapshot.writeBothLanguages("noteui-04-notes-search-revealed", size: Self.areaSize) {
            notesArea(host)
        }

        try UISnapshot.writeBothLanguages(
            "noteui-04-workspace-search-field", size: CGSize(width: 360, height: 200)
        ) {
            workspaceSearch(host)
        }

        print("NOTES-SEARCH-REVEAL 🖼 三种图（中英各一）落 \(UISnapshot.outputDirectory.path)")
    }

    // MARK: - 证据与源码

    private func writeEvidence(_ name: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("noteui-04-\(name).json"),
            options: .atomic
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// `App/Views/` 里含某个字面量的文件（相对路径升序）—— 「唯一出处」那一条判据靠它。
    private func appViewFilesContaining(_ needle: String) throws -> [String] {
        let views = repoRoot().appendingPathComponent("App/Views")
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files
            .filter { try String(contentsOf: $0, encoding: .utf8).contains(needle) }
            .map { "App/Views/\($0.lastPathComponent)" }
            .sorted()
    }
}
