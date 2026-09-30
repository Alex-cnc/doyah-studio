import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 数据库侧 **SQL 编辑器的行号列**（队列 `L-111`）—— App 内探针，开发循环第 121 轮。
///
/// ## 判什么（条目原文那一格的人话）
///
/// 「**SQL 编辑器（数据库侧）行号列**」+「复用同一套 `Core/CodeLines` 口径 + 同一个绘制件，
/// **不新造第二套行号逻辑**」—— 后半句才是这条里真正值钱的一半：只加一列**很容易**，
/// 但「两处各画一套」的下场是同一个文件在两个编辑器里行号不一致、一处改口径另一处忘了跟。
///
/// ## 怎么判
///
/// 前半（口径）在 Core（`CodeLines`，15 项单测）；这里判三件**只有把真视图跑起来才知道**的事：
/// ① 列真的**落到排版上** —— 正文起点右移到列宽之后（不是只算了个不用的数）；
/// ② 列真的**画到像素上** —— 列区里有墨，且行数从 9 → 151 时同一块列区画出来的东西**变了**；
/// ③ 两个编辑器**同一个件** —— 同样行数下，工作区编辑器与 SQL 编辑器的列宽、正文起点**逐个相等**
///   （这一条是「不许新造第二套」的回归钉；谁再各画一套，宽窄一不一样当场见分晓）。
///
/// ## 口径与边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`），跑法 `./Scripts/run-manual-verification-probes.sh`；
/// · 图片**语言无关**（画面里只有 SQL 文本与数字行号）⇒ 不按语言各出一张；
/// · 判得到「视图把列画成什么样」，判不到「人眼看着舒不舒服」—— 观感仍归人工点验；
/// · 数字与正文的**基线对齐**只判了「列宽按当前字体实量、正文起点等于列宽」，
///   逐像素的字形对齐没有断言（那属于读图）。
final class SQLLineNumberProbeTests: XCTestCase {

    // MARK: - 宿主与夹具

    private struct Harness: View {
        /// 权威副本（模拟 `AppState.tabs[i].sql`）。
        let text: String
        let tabID = UUID()
        /// 编辑器缓冲（队列 `L-148`）：与产品接线同形 —— 每键只写它，不写全局 `AppState`。
        @StateObject private var buffer = QueryEditorBuffer()
        var body: some View {
            SQLEditorView(
                text: buffer.displayText(for: tabID, authoritative: text),
                databaseType: .postgresql,
                diagnostics: [],
                tabID: tabID,
                onTextChange: { buffer.noteEdit($0, for: tabID) }
            )
        }
    }

    private struct WorkspaceHarness: View {
        @State var text: String
        var body: some View {
            CodeEditorView(
                tabID: UUID(),
                text: text,
                language: .sql,
                onTextChange: { _ in },
                onSave: {},
                onFormat: {}
            )
        }
    }

    /// `n` 行、末尾带换行 ⇒ **逻辑行数 = n + 1**（口径 ②：末尾行终止符多一个空行，光标能停在它上面）。
    private static func document(_ lines: Int) -> String {
        (1...lines).map { "select \($0) as col_\($0);" }.joined(separator: "\n") + "\n"
    }

    /// 1 位数的列（9 行 ⇒ `CodeLines.count` = 9）+ 3 位数的列（150 行 ⇒ 151）。
    private static let shortSQL = document(8)
    private static let longSQL = document(150)

    @MainActor
    private func makeHost<V: View>(
        _ view: V,
        height: CGFloat = 260
    ) throws -> UISnapshot.LiveHost<V> {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("要 DOYAH_UI_SNAPSHOT=1（跑法 ./Scripts/run-manual-verification-probes.sh）")
        }
        let host = UISnapshot.LiveHost(view, size: CGSize(width: 640, height: height))
        host.pump(0.5)
        return host
    }

    /// 真编辑器（数据库侧）。
    @MainActor
    private func makeSQLHost(text: String) throws -> (host: UISnapshot.LiveHost<Harness>, textView: SQLTextView) {
        let host = try makeHost(Harness(text: text))
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: SQLTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 判据的入口没了"
        )
        XCTAssertEqual(textView.string, text, "编辑器里应当是夹具那段 SQL")
        return (host, textView)
    }

    /// 真编辑器（工作区侧，用来判「同一个件」）。
    @MainActor
    private func makeWorkspaceHost(text: String) throws -> (host: UISnapshot.LiveHost<WorkspaceHarness>, textView: CodeTextView) {
        let host = try makeHost(WorkspaceHarness(text: text))
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<WorkspaceHarness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "工作区编辑器不在宿主视图树里"
        )
        return (host, textView)
    }

    /// 列区条带（**设备像素**：列宽是点，图是 2 倍图）—— 右端留 3 像素，避开那条发丝线。
    private func gutterBand(of record: UISnapshot.Record, points: CGFloat) -> UISnapshot.Band? {
        let width = Int((points * 2).rounded()) - 3
        guard width > 0 else { return nil }
        return UISnapshot.columnBand(ofPNGAt: record.file, fromLeading: 0, width: width)
    }

    // MARK: - ① 列真的落到排版上（正文起点 = 列宽）

    @MainActor
    func testSQLEditorLineNumberColumnIsLaidOut() throws {
        XCTAssertEqual(CodeLines.count(in: Self.shortSQL), 9, "夹具：8 行 + 末尾换行 ⇒ 9 个逻辑行")
        XCTAssertEqual(CodeLines.gutterDigits(in: Self.shortSQL), 1)
        let (host, textView) = try makeSQLHost(text: Self.shortSQL)

        XCTAssertEqual(textView.gutter.lineCount, 9, "行数必须与 Core 口径一致（同一份 `CodeLines`）")
        XCTAssertEqual(
            textView.gutterWidth, LineNumberGutter.width(digits: 1), accuracy: 0.01,
            "列宽只许有一处算法（`LineNumberGutter.width(digits:)`）"
        )
        XCTAssertGreaterThan(textView.gutterWidth, 0, "文本进去之后列宽必须已经算过")
        XCTAssertEqual(
            textView.textContainerInset.width, textView.gutterWidth, accuracy: 0.01,
            "正文必须从列的右边开始（左留白 = 列宽）—— 否则数字会压在正文上"
        )
        XCTAssertEqual(
            textView.textContainerInset.height, LineNumberGutter.verticalInset, accuracy: 0.01
        )

        let record = try host.capture(name: "sql-line-numbers-9-lines")
        let band = try XCTUnwrap(gutterBand(of: record, points: textView.gutterWidth))
        XCTAssertGreaterThan(band.ink, 0, "列区里必须有墨 —— 「算了但不画」正是这条要挡的假绿")
    }

    // MARK: - ② 行数变了，列画出来的东西必须跟着变

    @MainActor
    func testLineNumbersReachPixelsAndWidenWithLineCount() throws {
        XCTAssertEqual(CodeLines.count(in: Self.longSQL), 151)
        XCTAssertEqual(CodeLines.gutterDigits(in: Self.longSQL), 3)

        let (shortHost, shortView) = try makeSQLHost(text: Self.shortSQL)
        let (longHost, longView) = try makeSQLHost(text: Self.longSQL)

        XCTAssertEqual(longView.gutter.lineCount, 151)
        XCTAssertEqual(longView.gutterWidth, LineNumberGutter.width(digits: 3), accuracy: 0.01)
        XCTAssertGreaterThan(
            longView.gutterWidth, shortView.gutterWidth,
            "三位数的列必须比一位数宽（列宽是按位数与当前字体的数字宽实量的，不是固定值）"
        )
        XCTAssertGreaterThan(
            longView.textContainerInset.width, shortView.textContainerInset.width,
            "列变宽必须真的把正文起点推右 —— 光算数不落排版等于没做"
        )

        let shortRecord = try shortHost.capture(name: "sql-line-numbers-9-lines-recheck")
        let longRecord = try longHost.capture(name: "sql-line-numbers-151-lines")

        // 同一块列区（按**较窄**的那条列取，两张图都在列内）：内容必须不同。
        let shortBand = try XCTUnwrap(gutterBand(of: shortRecord, points: shortView.gutterWidth))
        let longBand = try XCTUnwrap(gutterBand(of: longRecord, points: shortView.gutterWidth))
        XCTAssertGreaterThan(shortBand.ink, 0, "9 行那张的列区里要有墨")
        XCTAssertGreaterThan(longBand.ink, 0, "151 行那张的列区里要有墨")
        let diff = try XCTUnwrap(UISnapshot.differingPixels(shortBand, longBand))
        XCTAssertGreaterThan(
            diff, 0,
            "1 位与 3 位行号应当在同一块列区上画出不同的像素 —— 数字没随行数变就说明画的是别的什么"
        )
    }

    // MARK: - ③ 两个编辑器共用同一个绘制件（「不许新造第二套行号逻辑」的回归钉）

    @MainActor
    func testBothEditorsShareOneGutter() throws {
        let (_, sqlView) = try makeSQLHost(text: Self.shortSQL)
        let (_, codeView) = try makeWorkspaceHost(text: Self.shortSQL)

        XCTAssertEqual(codeView.gutter.lineCount, sqlView.gutter.lineCount)
        XCTAssertEqual(
            codeView.gutterWidth, sqlView.gutterWidth, accuracy: 0.01,
            "同样行数下两个编辑器的列宽必须逐个相等（同一件、同一字体）—— 各画一套这里就对不上"
        )
        XCTAssertEqual(
            codeView.textContainerInset.width, sqlView.textContainerInset.width, accuracy: 0.01
        )
        // 工作区侧那两个转发口子也不许漂（既有判据 `UISnapshotTests` 读的就是它们）。
        XCTAssertEqual(CodeTextView.gutterWidth(digits: 1), LineNumberGutter.width(digits: 1), accuracy: 0.01)
        XCTAssertEqual(CodeTextView.gutterWidth(digits: 3), LineNumberGutter.width(digits: 3), accuracy: 0.01)
    }

    /// 类级收尾：把这一遍拍的图写进 `manifest.json`。
    ///
    /// **不是可选项**：取证脚本的「跨清单判定」读的就是这份清单 —— 少了它，
    /// 单跑这一族时收尾会红在「manifest.json 没有」（第 121 轮实测）。
    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
        super.tearDown()
    }
}
