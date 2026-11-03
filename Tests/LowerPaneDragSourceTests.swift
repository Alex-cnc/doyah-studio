import XCTest
@testable import DoyahCore

/// `FR-STD-WS-TOOL-001` 的**接线判据**（源树）：拖动的每一帧真的没有在写模型。
///
/// `LowerPaneDragSession` 判的是纯逻辑（见 `LowerPaneDragTests`）；但「视图有没有按它用」
/// 是另一件事 —— Core 全绿而视图仍在 `onChanged` 里每帧写 `AppState`，屏幕照样闪。
/// 这条判据就钉住那一处：
/// ① `LowerPaneSection` 里写 `appState.lowerPaneHeight` 的地方**只有一处**（`commitDrag`，松手时）；
/// ② 拖动回调（`onDrag`）里一个字都不许写模型、不许碰 `UserDefaults`；
/// ③ 把手自己不许持有高度、不许写模型（它只交位移与松手两条回调）。
///
/// 反例（改回去就红）：把 `appState.lowerPaneHeight = next` 挪回 `onDrag` 闭包 ⇒ ① 红（两处）。
final class LowerPaneDragSourceTests: XCTestCase {

    /// 找不到锚点就**判红**（不许静默跳过 —— 空转的判据比没有判据更糟）。
    private struct MissingAnchor: Error, CustomStringConvertible {
        let anchor: String
        var description: String { "判据要跟着改：源树里找不到「\(anchor)」" }
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释（含 `///` 文档注释）—— 这一段文档里满是「每帧写模型 / UserDefaults」
    /// 这类词，不剥就会把注释当成接线（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 抠出 `from` 起点到 `to` 起点之间那一段。
    private func region(_ text: String, from: String, to: String) throws -> Substring {
        guard let start = text.range(of: from) else { throw MissingAnchor(anchor: from) }
        guard let end = text.range(of: to, range: start.upperBound..<text.endIndex) else {
            throw MissingAnchor(anchor: to)
        }
        return text[start.lowerBound..<end.lowerBound]
    }

    /// ① 写 `lowerPaneHeight` 的地方**只有一处**，而且必须在 `commitDrag()` 里（松手那一下）。
    func testTheModelIsWrittenOnlyOnceOnRelease() throws {
        let window = try source("App/Views/MainWindow.swift")
        let section = try region(window, from: "struct LowerPaneSection", to: "struct LowerPaneResizeHandle")
        let writes = section.components(separatedBy: "appState.lowerPaneHeight =").count - 1
        XCTAssertEqual(writes, 1,
                       "`lowerPaneHeight` 只许在松手时写一次；每帧写一次 = 整个窗口每帧重算（那就是「闪」）")

        let commit = try region(window, from: "private func commitDrag()", to: "struct LowerPaneResizeHandle")
        XCTAssertTrue(commit.contains("appState.lowerPaneHeight ="),
                      "唯一那次写必须落在 `commitDrag()` 里")
    }

    /// ② 拖动回调里**一个字都不许写模型 / 不许碰 `UserDefaults`** —— 只许更新临时值。
    func testTheDragCallbackNeverTouchesTheModel() throws {
        let window = try source("App/Views/MainWindow.swift")
        let onDrag = try region(window, from: "onDrag: { translation in", to: "onEnd: { commitDrag() }")
        XCTAssertTrue(onDrag.contains("drag.update("),
                      "拖动回调必须走过程账（`drag.update`）：一帧只更新临时值")
        XCTAssertFalse(onDrag.contains("appState.lowerPaneHeight ="),
                       "拖动中不许写模型（每帧一次 `@Published` = 全窗口每帧重算）")
        XCTAssertFalse(onDrag.contains("appState.isLowerPaneVisible ="),
                       "拖动中不许写可见性（值没变也发 `objectWillChange`；拖过下限时还会每帧互翻）")
        XCTAssertFalse(onDrag.contains("UserDefaults"),
                       "拖动中不许落盘（每帧写一次 `UserDefaults` 是最没必要的 IO）")
    }

    /// ③ 把手只交两条回调：不持有高度、不写模型、不动磁盘。
    func testTheHandleOnlyReportsTranslationAndRelease() throws {
        let window = try source("App/Views/MainWindow.swift")
        let handle = try region(window, from: "struct LowerPaneResizeHandle",
                                to: "private struct SidebarResizeDivider")
        XCTAssertTrue(handle.contains("let onDrag: (CGFloat) -> Void"),
                      "把手只收「本帧位移」这一条回调")
        XCTAssertTrue(handle.contains("let onEnd: () -> Void"),
                      "把手只收「松手」这一条回调（落点唯一）")
        XCTAssertFalse(handle.contains("appState"),
                       "把手不许碰模型 —— 起点与落点都在 `LowerPaneSection` 那一层")
        XCTAssertFalse(handle.contains("UserDefaults"), "把手不许落盘")
        XCTAssertFalse(handle.contains("DragOrigin"),
                       "引用盒那套起点记账已经挪进 `LowerPaneDragSession`，不许两头各记一份")
    }

    /// ④ 旧的「每帧 `commit`」那条路不许回来（那个方法一出现就意味着又长回了 `MainWindow` 里）。
    func testThePerFrameSectionIsGone() throws {
        let window = try source("App/Views/MainWindow.swift")
        XCTAssertFalse(window.contains("sectionWithLowerPane"),
                       "原来的 `sectionWithLowerPane` 是每帧写模型的那条路，不许回来")
        XCTAssertTrue(window.contains("LowerPaneSection(content: QueryWorkspaceView())"),
                      "数据库段要用新的分段视图")
        XCTAssertTrue(window.contains("LowerPaneSection(content: WorkspaceAreaView())"),
                      "工作区段要用新的分段视图")
    }
}
