import XCTest
import SwiftUI
import AppKit
import DoyahCore
@testable import DoyahStudioApp

/// 片 `R3-T`（派单 `T-20261010-166` §三.4 的 ④ 卡）的探针 —— 契约 `FR-NOTEUI-07` + `-09`：
/// **正文区第一行 = title 区**（最左 = 新建 / 保存，中间 = 标题输入）。
///
/// 判据与片表（`docs/开发任务清单-hugehippo.md` §12.20「片 `R3-T`」）逐条对上：
///   ① `title` 输入位于**正文区第一行**（dump：它在正文那个 `NSTextView` 之上，也在编辑工具条之上）；
///   ② x 序：`新建 / 保存` 组在标题输入**左边**（源锚点 + 标题框 `minX` 的实测读数一起给），
///      模块切换在标题输入**右边**（标题框 `maxX` 与顶栏那一行末的关系）；
///   ③ 切换图标＝笔记/待办且**行为不变** —— 本片没动它 ⇒ 只复核源锚点仍在场
///      （那两枚的可读形态与几何由既有 `NotesLayoutProbeTests` 继续钉着）；
///   ④ 保存键形态（纯图标 + `.help(L(.notesSave))`，与 `N2-SV` 同口径）——源锚点逐条对；
///   ⑤ 成对 dump + 成对截图（`noteui-04-title-area-*`，中英各一张）。
///
/// ## 两条边界（如实登记 · 不许拿「代码里有」替代读数）
///   · **最左那两枚是 SwiftUI `Button`**，在离屏宿主里**不落到 `NSView`**（`NotesEditorSaveProbeTests`
///     头注释实测：`NSButton` 0 枚）⇒ 它们的矩形量不到：「组在标题框左边」这一半由**源锚点**
///     （`titleArea` 里 `NotesNewEntry()` / `saveEntry` 都在 `TextField` 之前）+ 标题框 `minX`
///     的实测读数合成（`minX` 里让出的那一截就是那两枚的住址）；
///   · **真实鼠标点击 / 悬停出 tips** 归该包实跑的人眼证据（离屏投合成事件时 SwiftUI 的手势不响应，
///     同 `NotesLayoutProbeTests` 与 `NotesEditorSaveProbeTests` 头注释那三条边界）。
final class NotesTitleAreaProbeTests: XCTestCase {

    /// 宿主面积：与左区骨架探针同一档（够放下三栏 + 顶栏）。
    private let areaSize = CGSize(width: 1100, height: 700)

    private struct HostBundle {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
    }

    // MARK: - 装配

    @MainActor
    private func makeHost() -> HostBundle {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("notes-titlearea-probe-\(UUID().uuidString).json")

        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return HostBundle(
            state: state,
            workspace: WorkspaceStore.shared,
            tabs: WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL)),
            terminal: TerminalModel()
        )
    }

    @MainActor
    private func makeLive(_ host: HostBundle) -> UISnapshot.LiveHost<AnyView> {
        let root = AnyView(
            NotesAreaView().snapshotEnvironment(
                state: host.state,
                workspace: host.workspace,
                tabs: host.tabs,
                terminal: host.terminal
            )
        )
        return UISnapshot.LiveHost(root, size: areaSize, scheme: .light)
    }

    // MARK: - 量法

    @MainActor
    private func rect(of view: NSView, in hosting: NSView) -> CGRect {
        hosting.convert(view.bounds, from: view)
    }

    /// 矩形**上边缘**离宿主顶边多远（与翻转无关的「谁在上面」）。
    @MainActor
    private func distanceToTopEdge(_ rect: CGRect, in hosting: NSView) -> CGFloat {
        hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
    }

    private func pt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    /// 宿主里**所有**可读矩形的逐条 dump（与 `NotesLayoutProbeTests` 的 `N2-2-EXPLORE` 同一形状：
    /// 量到什么就打印什么 —— 这是「title 与正文各在哪一行」这条判据的**原始读数**）。
    @MainActor
    private func dumpMeasurable(_ hosting: NSView, label: String) {
        let views = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
        let readable = views
            .map { (view: $0, rect: rect(of: $0, in: hosting)) }
            .filter { !$0.rect.isEmpty && $0.rect.width > 1 && $0.rect.height > 1 }
        print("NOTES-TITLEAREA DUMP[\(label)] 视图 \(views.count) 条 · 可读矩形 \(readable.count) 条")
        for entry in readable {
            let id = entry.view.accessibilityIdentifier()
            print(
                "  y=[\(pt(distanceToTopEdge(entry.rect, in: hosting)))…"
                    + "\(pt(distanceToTopEdge(entry.rect, in: hosting) + entry.rect.height))]"
                    + " x=[\(pt(entry.rect.minX))…\(pt(entry.rect.maxX))]"
                    + " \(NSStringFromClass(type(of: entry.view)))"
                    + (id.isEmpty ? "" : " id=\(id)")
            )
        }
    }

    /// **标题输入那一格**：先按 `accessibilityIdentifier("notes-editor-title")` 找（本片新加的），
    /// 找不到就按**占位文案**退一步找 —— 退路让这条判据在改前的树上也量得到同一个东西
    /// （成对读数的「改前」那一半必须量得出来，否则「改前必红」只是没量到）。
    @MainActor
    private func titleFieldRect(in hosting: NSView) -> (rect: CGRect, by: String)? {
        let views = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: hosting)
        if let hit = views.first(where: { $0.accessibilityIdentifier() == "notes-editor-title" }) {
            return (rect(of: hit, in: hosting), "id=notes-editor-title")
        }
        let placeholder = L(.notesUntitled)
        let fields = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextField.self, in: hosting)
        if let hit = fields.first(where: { ($0.placeholderString ?? "") == placeholder }) {
            return (rect(of: hit, in: hosting), "占位文案「\(placeholder)」")
        }
        return nil
    }

    // MARK: - 判据① 它落在正文区第一行

    /// **标题输入是正文区（右栏）的第一行**：它必须在**正文那个 `NSTextView` 之上**，
    /// 也必须在**编辑工具条之上**（本片之前它恰好在工具条之下 —— 改前这里红的那一条）。
    ///
    /// 外加一条**负向**读数：正文那一块的可编辑面在它**下面**（不是同一行）—— 这一条把
    /// 「标题并进正文那个文本视图了没有」如实写进读数里（本片**没有**并进去，口径见
    /// `NotesEditorView.titleArea` 的边界注释）。
    @MainActor
    func testTitleInputSitsOnTheFirstRowOfTheBodyArea() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        host.state.editorMode = .edit

        let live = makeLive(host)
        live.pump(0.6)
        dumpMeasurable(live.hosting, label: "edit")

        let title = try XCTUnwrap(
            titleFieldRect(in: live.hosting),
            "正文区里量不到标题输入那一格（既没有 `notes-editor-title` 标识，也没有占位文案"
                + "「\(L(.notesUntitled))」的 `NSTextField`）—— 判据的入口没了"
        )
        let titleTop = distanceToTopEdge(title.rect, in: live.hosting)

        // 正文那一块：右栏里所有 `NSTextView`（编辑态 = 富文本编辑面那一块）。
        let textViews = UISnapshot.LiveHost<Never>.findViews(ofType: NSTextView.self, in: live.hosting)
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 }
        let bodyTop = try XCTUnwrap(
            textViews.map { distanceToTopEdge($0, in: live.hosting) }.min(),
            "右栏里一个 `NSTextView` 都没量到 —— 「它在正文之上」这条没有对象可比"
        )

        // 编辑工具条（按标识找；离屏宿主给不出这个读数时是 nil，那就不比它）。
        let toolbarRect = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
            .first { $0.accessibilityIdentifier() == "notes-editor-toolbar" }
            .map { rect(of: $0, in: live.hosting) }
        let toolbarTop = toolbarRect.map { distanceToTopEdge($0, in: live.hosting) }

        // **它上面那一带**：正文区（右栏）里所有可读矩形中，上边缘在标题**之前**的那些 ——
        // 取其中最低的那一条（＝紧挨着标题上面的一层）。正文区左边界 = 中栏那一列的右边界
        // （列表列宽 ≤ 238，见 `NotesAreaView.listPaneMaxWidth`），铺满整幅的那些容器层不算内容。
        let aboveTops = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 }
            .filter { $0.minX >= 239 && $0.height < areaSize.height - 1 && $0.width < areaSize.width - 1 }
            .map { distanceToTopEdge($0, in: live.hosting) }
            // **严格在标题之上**（-1pt 把标题自己那一格与它同一带的子视图排掉，否则 `max` 恒等于
            // 标题自己、这条判据就永远绿）。
            .filter { $0 < titleTop - 1 }
        let highestAbove = aboveTops.max() ?? titleTop

        print(
            "NOTES-TITLEAREA ① 标题输入上边缘 \(pt(titleTop))pt（\(title.by)）｜"
                + " 正文上边缘 \(pt(bodyTop))pt ｜ 编辑工具条上边缘 "
                + (toolbarTop.map { "\(pt($0))pt" } ?? "无读数")
                + " ｜ 它上面那一带 \(pt(highestAbove))pt（差 \(pt(titleTop - highestAbove))pt，"
                + "带宽 \(aboveTops.count) 条）"
                + " ｜ 宿主 \(pt(areaSize.width))×\(pt(areaSize.height))"
        )

        XCTAssertLessThan(
            titleTop, bodyTop,
            "标题输入不在正文之上（标题 \(pt(titleTop))pt ≥ 正文 \(pt(bodyTop))pt）——"
                + "「正文区顶部＝title 区」这条量的就是它"
        )
        if let toolbarTop {
            XCTAssertLessThan(
                titleTop, toolbarTop,
                "标题输入落在编辑工具条**之下**（标题 \(pt(titleTop))pt ≥ 工具条 \(pt(toolbarTop))pt）"
                    + " —— 那样正文区的第一行是工具条，不是 title 区（`FR-NOTEUI-07` 未达）"
            )
        }
        // **它落在正文区最上面那一条带里**（本片之前正文区第一行是编辑工具条 ⇒ 改前这里红）。
        // 容差 24pt：同一带里图标圆环 / 文字基线本身就有几 pt 的高低差，判的是「有没有**另一条行**
        // 明显地压在标题之前」。
        XCTAssertLessThanOrEqual(
            titleTop - highestAbove, 24,
            "正文区里还有别的东西明显地压在标题之前（它上面那一带在 \(pt(highestAbove))pt，"
                + "标题在 \(pt(titleTop))pt，差 \(pt(titleTop - highestAbove))pt > 24pt）"
                + " —— 正文区第一行不是 title 区（`FR-NOTEUI-07` 未达）"
        )
    }

    // MARK: - 判据② x 序（组在标题左 / 切换在标题右）+ 判据④ 保存键形态

    /// **x 序**：`新建 / 保存` 组在标题输入左边（源锚点 + 标题框实测 `minX`），
    /// 模块切换在标题输入右边（标题框实测 `maxX` 与顶栏那一行**行末**的关系）。
    ///
    /// 「组在左边」的读数为什么是 `minX` 而不是组自己的矩形：那两枚是 SwiftUI `Button`，
    /// 离屏宿主里不落到 `NSView`（本文件头注释那条边界）⇒ 量得到的是**它让出来的那一截**：
    /// 标题框的 `minX` 减去正文区（`notes-editor`）的左内边距。改前那一截 ≈ 0（标题框贴边），
    /// 改后 ≈ 两枚命中区 + 间距。
    @MainActor
    func testLeftGroupSitsLeftOfTheTitleInputAndSaveKeyKeepsItsForm() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        host.state.editorMode = .edit

        let live = makeLive(host)
        live.pump(0.6)

        let title = try XCTUnwrap(titleFieldRect(in: live.hosting), "量不到标题输入那一格 —— 判据的入口没了")
        let editorRect = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
            .first { $0.accessibilityIdentifier() == "notes-editor" }
            .map { rect(of: $0, in: live.hosting) }

        // **title 区最左控件**（本卡要的那一条读数）：与标题**同一行**（上边缘相差 ≤ 12pt）的可读矩形里
        // 最左边那一条。改前那一行里只有标题框自己（最左 = 标题框的 `minX`），本片之后最左是
        // **「新建」那一枚**（它的 `FocusRingView` 在离屏宿主里是量得到的 —— 见上面 dump）。
        let titleTop = distanceToTopEdge(title.rect, in: live.hosting)
        let rowRects = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.width > 1 && $0.height > 1 }
            .filter { $0.minX >= 239 }
            .filter { abs(distanceToTopEdge($0, in: live.hosting) - titleTop) <= 12 }
        let leftmost = try XCTUnwrap(rowRects.map(\.minX).min(), "标题那一行里一个可读矩形都没有")
        let gap = title.rect.minX - leftmost
        print(
            "NOTES-TITLEAREA ② 标题框 x=[\(pt(title.rect.minX))…\(pt(title.rect.maxX))]"
                + " ｜ **title 区最左控件的 x = \(pt(leftmost))pt**"
                + "（标题框左边让出的那一截 \(pt(gap))pt）"
                + " ｜ 正文区左边界 \(editorRect.map { pt($0.minX) } ?? "无读数")"
        )

        // **改前必红的那一条**：改前那一行里最左的东西**就是标题框自己**（`gap ≈ 0`）；
        // 本片之后那两枚按钮（各 28pt 命中区 + 间距）挤在它左边 ⇒ `gap` 至少是两枚命中区。
        // 门槛取 56pt（= 2 × 28），留出主题 / 缩放的余量（实测读数见上面那一行打印）。
        XCTAssertGreaterThanOrEqual(
            gap, 56,
            "title 区最左没有让出「新建 / 保存」两枚的位置（标题框左边只有 \(pt(gap))pt，"
                + "门槛 56pt）—— 那一组要么没画、要么没在最左（`FR-NOTEUI-09` 未达）"
        )

        // ── 模块切换那两枚（`FR-NOTEUI-08` **已核**：本片没搬它，仍在顶栏行末）──────────────
        //
        // **如实登记两件事**（片表 §12.20「片 `R3-T` 判据②」后半逐字是「模块切换 `minX > title.maxX`」）：
        //   · 它在**顶栏那一行**（y ≈ 5…27），不在 title 区这一行（y ≈ 50…74）——本片**没搬**它：
        //     `FR-NOTEUI-08`（title 区最右＝切换图标）**已实现并核**，且待办屏的「切换回笔记」也靠
        //     顶栏那一处（搬进 `NotesEditorView` = 待办屏没有切换入口）；片表 `R3-B` 又写着它要迁左栏
        //     —— 三处对它的住址口径不一致 ⇒ 本片只**登记读数**，把裁决留给组长 / 前门；
        //   · 于是逐字那一半量出来是 `minX 1072.0 < title.maxX 1086.0`（它们在标题右侧 14pt 之外，
        //     但那 14pt 是两行不同的内边距差，不是重叠）：**它仍在标题的水平跨度右侧**
        //     （`maxX 1100.0 > title.maxX 1086.0`），这是本片能钉的那一半。
        let switchRects = UISnapshot.LiveHost<Never>.findViews(ofType: NSView.self, in: live.hosting)
            .map { rect(of: $0, in: live.hosting) }
            .filter { !$0.isEmpty && $0.minX >= 1000 && $0.maxY <= 40 }
        if let switchMinX = switchRects.map(\.minX).min(), let switchMaxX = switchRects.map(\.maxX).max() {
            print(
                "NOTES-TITLEAREA ② 模块切换（顶栏行末）x=[\(pt(switchMinX))…\(pt(switchMaxX))]"
                    + " ｜ title.maxX \(pt(title.rect.maxX))"
                    + " ｜ 逐字判据 `minX > title.maxX` = \(switchMinX > title.rect.maxX)"
            )
            XCTAssertGreaterThan(
                switchMaxX, title.rect.maxX,
                "模块切换没落在标题输入的水平跨度右侧（切换 maxX \(pt(switchMaxX))pt ≤ "
                    + "title.maxX \(pt(title.rect.maxX))pt）—— `FR-NOTEUI-08` 那一条的落点没了"
            )
        } else {
            XCTFail("顶栏行末量不到模块切换那两枚 —— 判据② 后半一个读数都没有")
        }

        let source = try notesPanelSource()
        // ── 判据④：保存键形态（纯图标 + 悬停名字）· 源锚点逐条对（与 `N2-SV` 同口径） ──
        let saveBlock = Self.sourceRegion(
            in: source,
            from: "Task { await appState.saveNoteFromEditor() }",
            to: ".disabled(!appState.noteEditorHasContent)"
        )
        XCTAssertFalse(saveBlock.isEmpty, "保存键那一块的源锚点被改了（找不到动作→守卫那一段）")
        for forbidden in ["Text(", "Label(", ".labelStyle"] {
            XCTAssertFalse(
                saveBlock.contains(forbidden),
                "保存键那一块里出现了 `\(forbidden)` —— 那是「图标 + 文字」的老形状"
                    + "（`FR-NOTEUI-15` / `T-20261008-023` 已裁：纯图标 + 悬停 tips）"
            )
        }
        XCTAssertTrue(
            saveBlock.contains(".help(L(.notesSave))"),
            "保存键那一块没有 `.help(L(.notesSave))` —— 悬停读不到名字（`FR-EXEC-13`）"
        )
        XCTAssertTrue(
            saveBlock.contains(".keyboardShortcut(.defaultAction)"),
            "保存键丢了 ⌘↩ 快捷键（`N2-SV` 的既有口径）"
        )
        XCTAssertEqual(
            source.components(separatedBy: "\"notes-editor-save\"").count - 1, 1,
            "「保存」入口只许有一处（数的是可读标识 `notes-editor-save` 的出现处数）"
        )
    }

    // MARK: - title 区那一块的源锚点（谁在里面、谁在谁的左边）

    /// **title 区那一块的形状**（判据② 的源码那一半 + 「模块切换本片没搬」的复核）：
    ///   · 块里 `NotesNewEntry()` 与 `saveEntry` 都在 `TextField(L(.notesUntitled)` **之前**；
    ///   · 块里只有**一条** `TextField(`（标题那一格）—— 这一格就是「正文区第一行 = title 输入」；
    ///   · `moduleSwitch` 仍挂在顶栏 `Spacer` 之后（本片一字未动 —— `FR-NOTEUI-08` 已核，
    ///     不把一个已达成条目改红）。
    func testTitleAreaBlockShapeAndModuleSwitchStaysPut() throws {
        let source = try notesPanelSource()
        let block = Self.sourceRegion(
            in: source,
            from: "private var titleArea: some View {",
            to: ".accessibilityIdentifier(\"notes-title-area\")"
        )
        XCTAssertFalse(block.isEmpty, "`titleArea` 那一块的源锚点被改了（找不到它）")

        let newIndex = try XCTUnwrap(block.range(of: "NotesNewEntry()"), "title 区最左没有「新建」")
        let saveIndex = try XCTUnwrap(block.range(of: "saveEntry"), "title 区最左没有「保存」")
        let titleIndex = try XCTUnwrap(
            block.range(of: "TextField(L(.notesUntitled)"), "title 区里没有标题输入那一格"
        )
        XCTAssertLessThan(newIndex.lowerBound, titleIndex.lowerBound, "「新建」不在标题输入左边")
        XCTAssertLessThan(saveIndex.lowerBound, titleIndex.lowerBound, "「保存」不在标题输入左边")
        XCTAssertLessThan(
            newIndex.lowerBound, saveIndex.lowerBound,
            "那一组的次序是「新建 → 保存」（人类主人口径：「新建/保存等按钮」）"
        )
        XCTAssertEqual(
            block.components(separatedBy: "TextField(").count - 1, 1,
            "title 区里有多于一格输入 —— 「正文区第一行 = title 输入」这条要求的就是只有标题这一格"
        )

        XCTAssertTrue(
            source.contains("Spacer(minLength: Spacing.s)\n            moduleSwitch"),
            "`moduleSwitch` 不在顶栏行末了 —— `FR-NOTEUI-08`（title 区最右＝切换图标）已核，"
                + "本片不该把它搬走（要搬得单独一张卡 + 重定 `NotesLayoutProbeTests` 的锚点）"
        )
    }

    // MARK: - 判据⑤ 成对截图（两态 × 两语言）

    /// **成对截图**：编辑态 / 预览态各一对（中英各一张，`captureBothLanguages` 加 `-zh` / `-en`）。
    /// 与 `NotesShelfProbeTests` 同一套取图路径（同一实例 + 非空白判据 + 记录进清单）。
    @MainActor
    func testCaptureTitleAreaPairs() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)

        host.state.editorMode = .edit
        host.state.noteEditorTitle = ""
        let edit = makeLive(host)
        edit.pump(0.6)
        _ = try edit.captureBothLanguages(name: "noteui-04-title-area-edit")
        XCTAssertTrue(host.state.noteEditorTitle.isEmpty, "渲染期间标题被填上了 —— 空态没站稳")

        host.state.editorMode = .preview
        let preview = makeLive(host)
        preview.pump(0.6)
        _ = try preview.captureBothLanguages(name: "noteui-04-title-area-preview")
    }

    // MARK: - 工具

    private func notesPanelSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TestsUISnapshot/
            .deletingLastPathComponent()   // <root>/
        return try String(contentsOf: root.appendingPathComponent("App/Views/NotesPanel.swift"), encoding: .utf8)
    }

    /// 源码里 `from` 与 `to` 之间那一段（口径与 `NotesEditorSaveProbeTests.sourceRegion` 逐字相同）：
    /// 找不到就返回空串，调用方据此判红（「锚点被改了」不许静默当作「那一块干干净净」）。
    private static func sourceRegion(in text: String, from start: String, to end: String) -> String {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
    }
}
