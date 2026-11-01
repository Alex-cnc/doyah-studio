import XCTest
@testable import DoyahCore

/// `FR-STD-DB-META-006` ③ 的**接线判据**（源树）：失败那一行真的挂上了重试入口，且判定只有一份。
///
/// 为什么要源树判据：Core 的纯函数全绿，界面照样可能「根本没有这一枚按钮」——
/// 正是本循环里反复出现的「Core 有代码、界面上点不到」那一档（实现只能标 🟡）。
/// 反过来，视图若自己再写一遍「有没有错误 / 在不在途」，就会出现**第二个判定源**：
/// 按钮在、点了没反应，或者重试之后旧红字还在。
final class ObjectTreeRetrySourceTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释 —— 这几处的文档注释里满是「错误 / 在途 / 重试」这类词，
    /// 不剥就会把注释当成接线（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// 失败分支必须把重试入口传进那一行（不带这一处，界面上就没有重试）。
    func testTheFailureRowPassesARetryEntry() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        guard let failureBranch = view.range(of: "} else if let error = row.error {") else {
            return XCTFail("失败分支不见了（这条判据要跟着改，别让它空转）")
        }
        let tail = view[failureBranch.upperBound...].prefix(600)
        XCTAssertTrue(tail.contains("retry: retryAction(for: row)"),
                      "失败那一行必须把重试入口传给渲染 —— 否则界面上仍然只有一个红字、没有出路")
    }

    /// 出不出入口必须问 Core（一处判定），视图不许自己写「有没有错误 / 在不在途」。
    func testTheViewAsksCoreInsteadOfDecidingLocally() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("ObjectTreeRetry.evaluate("),
                      "入口的判定必须走 Core 的 `evaluate`（同一份判定也决定点了做什么）")
        XCTAssertTrue(view.contains(".affordsRetry"),
                      "视图只读判定结果，不自己再判一遍")
        XCTAssertFalse(view.contains("retryAction(for: row, "),
                       "不许给判定加第二套参数（等于另开一份口径）")
    }

    /// 重试必须走**与用户手点同一条取数路**（`loadChildren`），不许另拼一次取数。
    func testRetryReusesTheSameLoadPath() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        guard let start = view.range(of: "private func performRetry("),
              let end = view.range(of: "private func loadChildren(of object:") else {
            return XCTFail("`performRetry` 与 `loadChildren` 都得在（缺一处这条判据就失效）")
        }
        let body = view[start.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("await loadChildren(of: object)"),
                      "重试要落在 `loadChildren` 上 —— 缓存、错误显示、「空结果不算查过」三条口径都挂在它上面")
        XCTAssertFalse(body.contains("loadMetadataChildren"),
                      "重试自己再取一次数 = 第二条取数路（缓存与错误会分叉）")
        XCTAssertFalse(body.contains("expandedIDs.remove"),
                      "重试不许靠「折起来再展开」实现（树会跳一下，且用户看到的是自己没做的动作）")
    }

    /// **先清旧错误、再取数**：反过来的话，点击到落地之间那一行还是上一轮的红字。
    ///
    /// 2026-11-01（B1 第四片）：这两步从视图的 `performRetry` 搬进了 `Core/ObjectTreeRetry.apply`
    /// （探针要读得出顺序 ⇒ 它不能只活在 `@State` 上）。判据跟着形状搬，盯的仍是同一件事：
    /// 视图把两个回调交给 `apply`，而 `apply` 按计划里的 `steps` 顺序走。
    func testStaleErrorIsClearedBeforeLoading() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        guard let start = view.range(of: "private func performRetry("),
              let end = view.range(of: "private func loadChildren(of object:") else {
            return XCTFail("`performRetry` 与 `loadChildren` 都得在（缺一处这条判据就失效）")
        }
        let body = view[start.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("ObjectTreeRetry.apply("),
                      "两步执行不再走 Core 的 `apply` ⇒ 顺序又只有视图自己知道（判据读不到）")
        XCTAssertTrue(body.contains("clearError: { errors[$0] = nil }"),
                      "`clearError` 没接到 `errors` 上（点完重试旧红字还在）")

        let core = try source("Core/ObjectTreeRetry.swift")
        guard let apply = core.range(of: "public static func apply("),
              let clear = core.range(of: "clearError(plan.nodeID)", range: apply.upperBound..<core.endIndex),
              let load = core.range(of: "loadChildren(plan.nodeID)", range: clear.upperBound..<core.endIndex)
        else { return XCTFail("`apply` 里的两步不见了") }
        XCTAssertTrue(clear.lowerBound < load.lowerBound,
                      "清错误必须在取数**之前**（否则用户点了以后看到的是同一句旧红字）")
        // 计划本身也必须是这个顺序（两处同源才叫「顺序即口径」）。
        XCTAssertTrue(core.contains("steps: [.clearError, .loadChildren]"),
                      "计划里的两步顺序变了")
    }

    /// 入口是**文字**按钮且带提示：一枚孤零零的 ↻ 在红字旁边指什么，得靠悬停才知道；
    /// 而纯图标按钮要另配 help / 无障碍标签（本仓有专门的门禁查这条）。
    ///
    /// 2026-11-01（B1 第四片）：这一行搬进 `App/Views/ObjectTreePlaceholderRow.swift`、按钮换成真
    /// `NSButton`（`.help` / `.accessibilityLabel` 两个 SwiftUI 修饰符对应到 `toolTip` /
    /// `setAccessibilityLabel`）。判据跟着形状搬 —— 盯的仍是「文字来自语言表 + 悬停与读屏都有」。
    func testTheEntryIsALabelledTextButton() throws {
        let row = try source("App/Views/ObjectTreePlaceholderRow.swift")
        guard let retry = row.range(of: "if let retry {") else {
            return XCTFail("重试入口不见了")
        }
        let body = row[retry.upperBound...].prefix(200)
        XCTAssertTrue(body.contains("L(.commonRetry)"), "按钮文字走语言表（不许写死一句中文）")

        XCTAssertTrue(row.contains("button.toolTip = title"), "要有悬停提示")
        XCTAssertTrue(row.contains("button.setAccessibilityLabel(title)"), "读屏也要念得出这枚按钮")
        XCTAssertTrue(row.contains("underlineStyle"), "文字按钮要带下划线（看起来才像「可点的链接」而不是一句灰字）")
    }
}
