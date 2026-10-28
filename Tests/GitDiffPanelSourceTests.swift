import XCTest
@testable import DoyahCore

/// `FR-STD-WS-VCS-002` 的**接线判据**（源树）：开关真的传到了 git，画的行真的走呈现层。
///
/// 为什么这些要用源树判据钉：Core 的纯函数判据全绿，界面照样可能「开关亮着、差异没变」
/// （视图没把 request 交给 probe），或者「分页写了但视图还在直接铺 `hunk.lines`」
/// —— 那两件事在单测里一个字都看不见。
final class GitDiffPanelSourceTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释 —— 这几份文件的文档注释里满是「`-w`」这种例子，
    /// 不剥就会把注释当成接线（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testProbePassesTheRequestInsteadOfHardcodingSwitches() throws {
        let probe = try source("App/GitWorktreeProbe.swift")
        XCTAssertTrue(probe.contains("request.applying(to:"),
                      "开关只能由 GitDiffRequest 插进参数（一处拼装）")
        XCTAssertFalse(probe.contains("\"-w\""),
                       "probe 里不许自己写 `-w` —— 那会绕开 request，开关就成了摆设")
        XCTAssertFalse(probe.contains("\"-U"),
                       "probe 里不许自己写 `-U`（同上）")
    }

    func testModelReloadsWhenTheSwitchesChange() throws {
        let model = try source("App/GitChangesModel.swift")
        XCTAssertTrue(model.contains("func setIgnoresWhitespace("))
        XCTAssertTrue(model.contains("func setContextLines("))
        XCTAssertTrue(model.contains("GitWorktreeProbe.loadDiff(root: root, entry: entry, staged: staged,"),
                      "取数那一路必须带上 request")
        XCTAssertTrue(model.contains("request: request"))
        // 换口径要**重新取一次**（`-w` 是 git 算的，不是本地过滤）。
        XCTAssertTrue(model.contains("reloadForRequestChange()"))
    }

    func testPanelRendersThroughThePresentationLayer() throws {
        let panel = try source("App/Views/GitChangesPanel.swift")
        XCTAssertTrue(panel.contains("model.presentation(for:"))
        XCTAssertTrue(panel.contains("case .fold(let fold):"))
        XCTAssertTrue(panel.contains("case .more(let hidden):"))
        XCTAssertTrue(panel.contains("model.setIgnoresWhitespace"))
        XCTAssertTrue(panel.contains("model.setContextLines"))
        // 反向：视图不许再直接铺 `hunk.lines`（那样按需渲染就只是写在 Core 里的字）。
        XCTAssertFalse(panel.contains("ForEach(Array(hunk.lines.enumerated())"),
                       "差异正文必须走呈现层，直接铺 hunk.lines 会把「按需渲染」变成一句空话")
    }

    func testPanelExplainsWhitespaceOnlyEmptyState() throws {
        let panel = try source("App/Views/GitChangesPanel.swift")
        XCTAssertTrue(panel.contains("L(.gitDiffEmptyAfterWhitespace)"),
                      "忽略空白把整份差异吃光时，要说清是这个开关造成的")
    }
}
