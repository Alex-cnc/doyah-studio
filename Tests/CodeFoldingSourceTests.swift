import XCTest

/// `FR-STD-WS-EDIT-017` 的**源树判据**：折叠必须真的接到界面上，而且**不许改文本**。
///
/// ## 为什么要有这一条
///
/// Core 侧（`CodeFolding` + `FoldState`）全绿只说明「算得对」；如果行号槽没画标记、
/// 点标记没人接、模型不给视图展示面 —— 产品侧就是**一条也折不起来**，而 Core 判据一条都不会红。
/// 同族教训见 `Tests/WorkspaceFileMoveSourceTests`、`Tests/DialogButtonSourceTests`。
///
/// 反过来的那一半同样重要：需求 ④ 写着「折叠不改变文本内容与撤销栈」。最省事的实现是
/// **把文本换成一份「折起来版」的字符串** —— 那样一折一展就把模型、搜索、撤销全污染了。
/// 所以这里有一条反向判据：折的那条路里**不许出现任何写文本的调用**。
final class CodeFoldingSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        // 空跑防护：读到的必须真是那份文件，不是空壳。
        XCTAssertGreaterThan(body.count, 4000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 行号槽：画标记 + 命中判定 + 标记列只在有标记时占位。
    func testGutterDrawsMarkersAndHitsThem() throws {
        let body = try text("App/Views/LineNumberGutter.swift")
        for anchor in [
            "private(set) var foldMarkers: [Int: Bool]",
            "static let markerWidth: CGFloat",
            "func applyFoldMarkers(",
            "private func drawFoldMarker(isFolded:",
            "func foldMarkerLine(at point: NSPoint",
            "hasMarkers ? markerWidth : 0",
            "if let folded = foldMarkers[index + 1]"
        ] {
            XCTAssertTrue(body.contains(anchor), "行号槽缺少折叠标记锚点：\(anchor)")
        }
        // 反向：标记列的宽度必须跟着「有没有标记」走（否则纯文本的行号列无端宽一截）。
        XCTAssertTrue(
            body.contains("Self.width(digits: digits, hasMarkers: !foldMarkers.isEmpty)"),
            "列宽必须按「有没有标记」算"
        )
    }

    /// 编辑器：点标记 → 折 / 展；展示面变了才重设；内容稳定后通知模型重算。
    func testEditorWiresGutterClickAndPresentation() throws {
        let body = try text("App/Views/CodeEditorView.swift")
        for anchor in [
            "var foldPresentation: WorkspaceTabsModel.FoldPresentation",
            "var onToggleFold: ((Int) -> Void)?",
            "var onCaretEnteredFoldedBlock: ((Int) -> Void)?",
            "var onDocumentSettled: (() -> Void)?",
            "if let line = gutter.foldMarkerLine(at: point, of: self)",
            "onToggleFold?(line)",
            "gutter.applyFoldMarkers(markers, to: self)",
            "applyFoldCollapse()",
            "parent.onDocumentSettled?()",
            "parent.onCaretEnteredFoldedBlock?(line)"
        ] {
            XCTAssertTrue(body.contains(anchor), "编辑器缺少折叠接线锚点：\(anchor)")
        }
    }

    /// 需求 ④ 的反向判据：折的那条路里**一个字都不许写回文本**（不换字符串、不删字符）。
    func testFoldingNeverRewritesTheText() throws {
        let body = try text("App/Views/CodeEditorView.swift")
        guard let start = body.range(of: "func applyFoldCollapse()") else {
            return XCTFail("没找到 `applyFoldCollapse()` —— 折叠的落地函数不在盘上")
        }
        guard let end = body.range(of: "\n    /// 点在行号槽的**标记列**上", range: start.upperBound..<body.endIndex) else {
            return XCTFail("没找到 `applyFoldCollapse` 的结束位置（判据的解析面变了）")
        }
        let collapsePath = String(body[start.lowerBound..<end.lowerBound])
        XCTAssertGreaterThan(collapsePath.count, 200, "截出来的函数体太短，扫描面可疑")
        for forbidden in ["replaceCharacters", "insertText", "shouldChangeText", "string ="] {
            XCTAssertFalse(
                collapsePath.contains(forbidden),
                "折叠的落地路径里出现了写文本的调用（\(forbidden)）—— 需求 ④ 要的是「不改内容」"
            )
        }
        // 正向：它确实只改属性（段落样式 + 透明前景），这正是「藏起来但不删」的做法。
        XCTAssertTrue(collapsePath.contains("addAttributes(invisible, range: range)"))
        XCTAssertTrue(collapsePath.contains("minimumLineHeight = 1"))
        // 而且**不许** `invalidateLayout`：非连续布局下它会把可见区判成「没排过」⇒ 编辑区整块不画。
        XCTAssertFalse(collapsePath.contains("invalidateLayout"), "折叠落地不许作废布局（本仓栽过）")
    }

    /// 模型：状态挂在页签上、写入口唯一、三个失效点都在。
    func testModelOwnsFoldStateAndTransitions() throws {
        let body = try text("App/WorkspaceTabsModel.swift")
        for anchor in [
            "struct FoldPresentation",
            "@Published private(set) var foldPresentations",
            "func foldPresentation(for tabID: UUID) -> FoldPresentation",
            "func toggleFold(tabID: UUID, line: Int)",
            "func unfoldAroundCaret(tabID: UUID, line: Int)",
            "func refreshFolds(tabID: UUID)",
            "tabs[index].folds = next",
            "tab.folds.reconciled(with: projection)"
        ] {
            XCTAssertTrue(body.contains(anchor), "页签模型缺少折叠锚点：\(anchor)")
        }
    }

    /// 页签视图真的把展示面与三条回投都接上了（否则模型算得再对也到不了屏幕）。
    func testAreaViewPassesPresentationAndCallbacks() throws {
        let body = try text("App/Views/WorkspaceAreaView.swift")
        for anchor in [
            "foldPresentation: tabs.foldPresentation(for: tab.id)",
            "onToggleFold: { line in tabs.toggleFold(tabID: tab.id, line: line) }",
            "onCaretEnteredFoldedBlock: { line in tabs.unfoldAroundCaret(tabID: tab.id, line: line) }",
            "onDocumentSettled: { tabs.refreshFolds(tabID: tab.id) }"
        ] {
            XCTAssertTrue(body.contains(anchor), "工作区视图缺少折叠接线：\(anchor)")
        }
    }

    /// 状态住在**页签**上（`WorkspaceTab.folds`），而不是视图的 `@State`
    /// （本仓在侧边栏折叠状态上栽过一次：视图被重建 = 用户的选择当场归零）。
    func testFoldStateLivesOnTheTabNotInTheView() throws {
        let tab = try text("Core/WorkspaceTab.swift")
        XCTAssertTrue(tab.contains("public var folds: FoldState"))
        let view = try text("App/Views/CodeEditorView.swift")
        XCTAssertFalse(view.contains("@State private var fold"), "折叠状态不许住在视图的 @State 里")
        XCTAssertFalse(view.contains("@State var fold"), "折叠状态不许住在视图的 @State 里")
    }
}
