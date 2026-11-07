import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「当前轮用户问题吸顶一行」的端上判据（详设 §3.34，900×620 真视图）。
///
/// ## 主人原话（beta1.0.4 真机）
///
/// > 「用户发出的问题被滚动的输出冲掉了，有时候要滚到前面去才能看到。
/// >  应该跟 hermes 一样：如果输出的文字太多，用户这句话就挂在最顶端。」
///
/// ## 为什么量得到（而不是靠人拖滚动条）
///
/// 判定要的两个量都在**内容坐标**里，由 AppKit 视图报出来：
/// · `ScrollOffsetSpy.onOffsetFromTop`（视口顶在内容里的位置）；
/// · `StickyQuestionAnchor`（当前轮那条提问的顶边在内容里的位置）。
/// 探针把 `NSScrollView` 滚到指定偏移（`NSClipView.scroll(to:)` + `reflectScrolledClipView`，
/// 与 `T-3.33-13` 同一手法），等 SwiftUI 布局落定后读几何 —— 生产与判据读的是同一份读数。
///
/// ## 五条判据（都能判红）
///
/// ① 300 行输出 ⇒ 用户提问滚出可视区时，条高 > 0 且 == 一行（20pt），视口从条底边起（内容不被盖）；
/// ② 滚回顶部 ⇒ 条高 == 0（反例：一直显示 ⇒ 判红）；
/// ③ 点条 ⇒ 落点 == 那条消息的顶端（±2pt；反例：滚到页面顶部 ⇒ 判红）；
/// ④ 条在时，思考区 / 工具块的**行高逐点不变**，只有外层视口少一行；
/// ⑤ 长问题（> 200 字、带换行）⇒ 条仍是一行、高不变。
///
/// ## 边界（如实登记）
///
/// · SwiftUI `Text` 在这台宿主里不落成 `NSTextField`（同 `ExecutionReceiptPaneProbeTests`）⇒
///   条的高度读的是它的**点击面 `NSButton` 的 frame 高**（那一面铺满条）；
/// · 折叠/展开动作在离屏宿主里点不动（`DialogActionRowProbeTests`）⇒ 条上的点击走
///   **真 `NSButton`** 的 `performClick(nil)`（生产里点它、探针里点它，同一条 action）；
/// · 行内文字内容由纯函数判（`AgentStickyQuestion.lineText`），不在探针里比字形；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 端上探针的同一纪律：取证才跑，门禁不跑。
final class AgentChatStickyQuestionProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    /// 真机那种「输出把问题冲掉」的量级。
    static let outputLines = 300

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "吸顶条判据要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    static let plainQuestion = "用户发出的问题被滚动的输出冲掉了，有时候要滚到前面去才能看到。"

    /// 200 字以上、且带换行的问题（契约⑤：条仍要一行）。
    static let longQuestion = "用户发出的问题被滚动的输出冲掉了，有时候要滚到前面去才能看到。\n"
        + String(repeating: "应该跟 hermes 一样：如果输出的文字太多，用户这句话就挂在最顶端。", count: 6)
        + "\n最后一行：问题到这里结束。"

    static func output(lines: Int = outputLines) -> String {
        (1...max(1, lines)).map { "第 \($0) 行：这是很长的一段输出，一直往下长，把上面那句提问顶出屏幕。" }
            .joined(separator: "\n")
    }

    /// 三轮对话：上一轮（占位）+ **当前轮**（提问 + 300 行输出）。
    /// 为什么要有上一轮：契约③ 要求「落点是那条消息的顶部，不是页面顶部」——
    /// 只有当前轮提问**不在内容最上面**时，两种落点才分得开。
    static func messages(question: String, outputLines: Int = outputLines) -> [AgentChatMessage] {
        [
            .init(role: .user, text: "上一轮：这个仓库里 Agent 的结论为什么被折叠了？"),
            .init(role: .assistant, text: "上一轮的回答很短，只占一行。"),
            .init(role: .user, text: question),
            .init(role: .assistant, text: output(lines: outputLines)),
        ]
    }

    static func steps(_ count: Int = 12) -> [AgentChatStep] {
        (0..<count).map { AgentChatStep(index: $0 + 1, status: .done, tools: ["read_file"]) }
    }

    // MARK: - 判据函数（真实读数与反例读数**共用同一套**，反例才证明判据有牙齿）

    /// ① 条出现时：高 > 0、== 一行、≤ 28pt，且视口从条底边起（内容一行都不被盖）。
    static func barShownViolations(barHeight: CGFloat,
                                   barFrame: CGRect,
                                   viewportFrame: CGRect) -> [String] {
        var issues: [String] = []
        let line = AgentStickyQuestion.barHeight
        guard barHeight > 0.5 else {
            return ["提问已滚出可视区，吸顶条高 \(barHeight)pt ⇒ 条没出现"]
        }
        if abs(barHeight - line) > 0.5 {
            issues.append("吸顶条高 \(barHeight)pt ≠ 一行 \(line)pt ⇒ 条不是一行")
        }
        if barHeight > 28 {
            issues.append("吸顶条高 \(barHeight)pt > 上限 28pt")
        }
        // 内容区（视口）的上沿必须**等于**条的底边：差 > 1pt 就是盖住或留空档。
        let inset = viewportFrame.minY - barFrame.maxY
        if abs(inset) > 1 {
            issues.append("内容区上沿与条底边差 \(Int(inset.rounded()))pt（应 0）⇒ 内容被条盖住 / 留了空档")
        }
        return issues
    }

    /// ② 滚回顶部（提问重新可见）⇒ 条高 == 0。
    static func barGoneViolations(barHeight: CGFloat) -> [String] {
        guard barHeight > 0.5 else { return [] }
        return ["滚回顶部后吸顶条仍高 \(barHeight)pt ⇒ 同一条问题在屏幕上出现两次"]
    }

    /// ③ 点条之后的落点：与那条消息的顶端差 ≤ 2pt。
    static func jumpViolations(landedOffset: CGFloat, questionTop: CGFloat) -> [String] {
        let delta = abs(landedOffset - questionTop)
        guard delta > 2 else { return [] }
        return ["点吸顶条后落在 \(landedOffset)pt，那条提问的顶端在 \(questionTop)pt"
                + "（差 \(delta)pt > 2pt）⇒ 没滚回问题顶部"]
    }

    /// ④ 行高：条在 / 条不在，两边的行视口高度**逐点相同**。
    static func reflowViolations(withBar: [CGFloat], withoutBar: [CGFloat]) -> [String] {
        guard withBar.count == withoutBar.count else {
            return ["条在时读到 \(withBar.count) 个内部滚动容器、条不在时 \(withoutBar.count) 个 ⇒ 结构变了"]
        }
        var issues: [String] = []
        for (index, (lhs, rhs)) in zip(withBar, withoutBar).enumerated() where abs(lhs - rhs) > 0.5 {
            issues.append("第 \(index + 1) 个行内容高：条在 \(lhs)pt / 条不在 \(rhs)pt ⇒ 吸顶让行重排了")
        }
        return issues
    }

    /// ⑤ 长问题：条高仍是一行。
    static func oneLineViolations(height: CGFloat) -> [String] {
        let line = AgentStickyQuestion.barHeight
        guard height > line + 0.5 else { return [] }
        return ["长问题让条长到 \(height)pt（一行 = \(line)pt）⇒ 问题换行把条撑高了"]
    }

    // MARK: - 读数

    @MainActor
    private struct Reading {
        var barHeight: CGFloat = 0
        var barFrame: CGRect = .zero
        var viewportFrame: CGRect = .zero
        /// 视口顶在内容坐标里的位置（= 距内容顶的偏移）。
        var offsetFromTop: CGFloat = 0
        var documentHeight: CGFloat = 0
        /// 当前轮提问的顶边：内容坐标 / 相对视口顶（负数 = 已滚出视口顶）。
        var questionTopInContent: CGFloat?
        var questionVisualTop: CGFloat?
        /// 宿主里所有滚动容器的高度（判据④ 拿它比行高）。
        var scrollViewHeights: [CGFloat] = []
    }

    @MainActor
    private func transcriptScroll(_ live: UISnapshot.LiveHost<AnyView>) -> NSScrollView? {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
            .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
    }

    @MainActor
    private func read(_ live: UISnapshot.LiveHost<AnyView>) -> Reading {
        var reading = Reading()
        reading.scrollViewHeights = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSScrollView.self, in: live.hosting)
            .map { $0.bounds.height }
            .sorted()
        guard let scroll = transcriptScroll(live), let document = scroll.documentView else { return reading }
        let clip = scroll.contentView
        reading.documentHeight = document.bounds.height
        reading.viewportFrame = live.hosting.convert(scroll.bounds, from: scroll)
        let flipped = document.isFlipped
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        reading.offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)

        if let button = UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentStickyClickButton.self,
                                                               in: live.hosting).first {
            reading.barFrame = live.hosting.convert(button.bounds, from: button)
            reading.barHeight = reading.barFrame.height
        }
        if let anchor = UISnapshot.LiveHost<AnyView>.findViews(ofType: StickyQuestionRowMarker.self,
                                                               in: live.hosting).first {
            let frame = live.hosting.convert(anchor.bounds, from: anchor)
            reading.questionVisualTop = frame.minY - reading.viewportFrame.minY
            reading.questionTopInContent = (reading.questionVisualTop ?? 0) + reading.offsetFromTop
        }
        return reading
    }

    /// 把对话区滚到「距内容顶 `offset` pt」（超界自动夹到最大偏移）。
    @MainActor
    private func scroll(_ live: UISnapshot.LiveHost<AnyView>, toOffsetFromTop offset: CGFloat) {
        guard let scroll = transcriptScroll(live), let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let clamped = min(max(0, offset), maxOffset)
        let y = document.isFlipped ? clamped : (maxOffset - clamped)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
        live.pump(0.25)
    }

    @MainActor
    private func makePage(_ messages: [AgentChatMessage], isRunning: Bool = false) -> UISnapshot.LiveHost<AnyView> {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "sticky-probe",
                                   state: AgentChatState(
                                    messages: messages,
                                    steps: Self.steps(),
                                    endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"),
                                    isRunning: isRunning))
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.3)
        return live
    }

    // MARK: - ① / ② / ⑤ 出现、消失、一行

    @MainActor
    func testStickyBarAppearsWhenTheQuestionScrollsOutAndGoesAwayAtTheTop() {
        let live = makePage(Self.messages(question: Self.plainQuestion))
        defer { live.window.contentView = nil }

        // 滚到底（300 行输出的位置）。
        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)
        let bottom = read(live)
        print("🧪 ① 滚到底：偏移 \(bottom.offsetFromTop)pt / 文档高 \(bottom.documentHeight)pt"
              + " / 提问在内容 \(bottom.questionTopInContent.map { "\($0)pt" } ?? "（行已回收）")"
              + " / 相对视口 \(bottom.questionVisualTop.map { "\($0)pt" } ?? "（行已回收）")")
        print("🧪 ① 吸顶条：高 \(bottom.barHeight)pt（一行 = \(AgentStickyQuestion.barHeight)pt）"
              + " / 条 frame \(NSStringFromRect(bottom.barFrame)) / 视口 \(NSStringFromRect(bottom.viewportFrame))")

        XCTAssertGreaterThan(bottom.offsetFromTop, 60,
                             "滚到底后偏移只有 \(bottom.offsetFromTop)pt ⇒ 300 行没真滚出去")
        XCTAssertTrue(bottom.questionVisualTop.map { $0 < 0 } ?? true,
                      "滚到底后提问顶端相对视口 \(bottom.questionVisualTop ?? .nan)pt ⇒ 它还在可视区里，判据没测到该测的场景")
        let shownIssues = Self.barShownViolations(barHeight: bottom.barHeight,
                                                  barFrame: bottom.barFrame,
                                                  viewportFrame: bottom.viewportFrame)
        print("🧪 ① 判定：" + (shownIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + shownIssues.joined(separator: "；")))
        XCTAssertTrue(shownIssues.isEmpty, shownIssues.joined(separator: "；"))

        // 反例①：条压根没出现（改前的形态）⇒ 同一套判据必须报红。
        let missing = Self.barShownViolations(barHeight: 0, barFrame: .zero, viewportFrame: .zero)
        print("🧪 反例①（条不出现）：" + (missing.isEmpty ? "假绿 ❌" : "判红 ✅ — \(missing[0])"))
        XCTAssertFalse(missing.isEmpty, "条不出现判据仍绿 ⇒ 判据没有牙齿")

        // 反例①b：条盖住内容（视口仍从顶格起）⇒ 必须报红。
        let covering = Self.barShownViolations(
            barHeight: AgentStickyQuestion.barHeight,
            barFrame: CGRect(x: 0, y: 0, width: 900, height: 20),
            viewportFrame: CGRect(x: 0, y: 0, width: 900, height: 480)
        )
        print("🧪 反例①b（条压在第一行字上）：" + (covering.isEmpty ? "假绿 ❌" : "判红 ✅ — \(covering[0])"))
        XCTAssertFalse(covering.isEmpty, "条盖住内容判据仍绿 ⇒ 判据没有牙齿")

        // ② 滚回顶部 ⇒ 提问重新可见 ⇒ 条必须消失。
        scroll(live, toOffsetFromTop: 0)
        let top = read(live)
        print("🧪 ② 滚回顶部：偏移 \(top.offsetFromTop)pt / 条高 \(top.barHeight)pt"
              + " / 提问相对视口 \(top.questionVisualTop.map { "\($0)pt" } ?? "nil")")
        XCTAssertGreaterThanOrEqual(top.questionVisualTop ?? .infinity, -0.5,
                                    "滚回顶部后提问仍在视口之外（\(top.questionVisualTop ?? .nan)pt）⇒ 没真正回到顶部")
        let goneIssues = Self.barGoneViolations(barHeight: top.barHeight)
        print("🧪 ② 判定：" + (goneIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + goneIssues.joined(separator: "；")))
        XCTAssertTrue(goneIssues.isEmpty, goneIssues.joined(separator: "；"))

        // 反例②：条一直显示 ⇒ 必须报红。
        let always = Self.barGoneViolations(barHeight: AgentStickyQuestion.barHeight)
        print("🧪 反例②（滚回顶部条仍挂着）：" + (always.isEmpty ? "假绿 ❌" : "判红 ✅ — \(always[0])"))
        XCTAssertFalse(always.isEmpty, "条一直显示判据仍绿 ⇒ 判据没有牙齿")
    }

    /// ⑤ 长问题（> 200 字、带换行）⇒ 条仍是一行、高不变。
    @MainActor
    func testLongQuestionStillTakesOneLine() {
        let live = makePage(Self.messages(question: Self.longQuestion))
        defer { live.window.contentView = nil }
        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)
        let reading = read(live)

        // 条上的字是一行化之后的（纯函数判内容），高度由真视图判。
        let line = AgentStickyQuestion.lineText(Self.longQuestion)
        print("🧪 ⑤ 长问题（\(Self.longQuestion.count) 字、含换行）：条高 \(reading.barHeight)pt"
              + " / 一行化后 \(line.count) 字且无换行 = \(!line.contains("\n"))")
        XCTAssertGreaterThan(reading.barHeight, 0, "长问题下条没出现 ⇒ 这一条判的是空")
        XCTAssertFalse(line.contains("\n"), "长问题一行化之后仍带换行 ⇒ 条会长成多行")
        let issues = Self.oneLineViolations(height: reading.barHeight)
        print("🧪 ⑤ 判定：" + (issues.isEmpty ? "绿 ✅" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

        // 反例⑤：不折行的长问题（改前形态 = 直接 `Text(longQuestion)`）⇒ 必须报红。
        let raw = UISnapshot.LiveHost(AnyView(Text(Self.longQuestion)
            .font(Theme.font(.mono))
            .frame(width: 868, alignment: .leading)
            .padding(.horizontal, Spacing.l)), size: CGSize(width: 900, height: 400))
        defer { raw.window.contentView = nil }
        let rawHeight = raw.hosting.fittingSize.height
        let rawIssues = Self.oneLineViolations(height: rawHeight)
        print("🧪 反例⑤（长问题不折行，\(Self.longQuestion.count) 字）：\(rawHeight)pt ⇒ "
              + (rawIssues.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(rawIssues.isEmpty, "不折行的长问题判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ③ 点条 ⇒ 回到那条消息的顶部

    @MainActor
    func testClickingTheBarReturnsToTheQuestionTop() {
        let live = makePage(Self.messages(question: Self.plainQuestion))
        defer { live.window.contentView = nil }

        // 先在顶部读一次「那条提问的顶端在内容里的位置」（此时那一行一定物化，读数最准），
        // 再滚到底（那一行会被回收，读不到坐标）去点条。
        scroll(live, toOffsetFromTop: 0)
        let atTop = read(live)
        guard let questionTop = atTop.questionTopInContent else {
            return XCTFail("滚到顶部仍没读到提问的内容坐标 ⇒ 夹具没挂上那一行的标记")
        }
        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)

        let before = read(live)
        XCTAssertGreaterThan(before.barHeight, 0, "滚到底后没有吸顶条 ⇒ 这一条判的是空")

        let buttons = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentStickyClickButton.self, in: live.hosting)
        guard let button = buttons.first else {
            return XCTFail("没找到吸顶条的点击面（NSButton）⇒ 判据点不到它")
        }
        button.performClick(nil)          // 真点击路径（生产里点它走同一条 action）
        live.pump(0.6)

        let after = read(live)
        let expected = questionTop
        print("🧪 ③ 点条前：偏移 \(before.offsetFromTop)pt / 提问顶端 \(expected)pt"
              + " → 点条后：偏移 \(after.offsetFromTop)pt / 提问相对视口 "
              + "\(after.questionVisualTop.map { "\($0)pt" } ?? "nil") / 条高 \(after.barHeight)pt")

        let issues = Self.jumpViolations(landedOffset: after.offsetFromTop, questionTop: expected)
        print("🧪 ③ 判定：" + (issues.isEmpty ? "绿 ✅" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        // 落点之后那条提问就在视口顶端（±2pt）：这是「不是页面顶部」的直接读数。
        if let visualTop = after.questionVisualTop {
            XCTAssertEqual(visualTop, 0, accuracy: 2,
                           "点条后提问顶端相对视口 \(visualTop)pt（应 0）")
        }
        // 回到它之后条自己消失（提问又看得见了）。
        XCTAssertTrue(Self.barGoneViolations(barHeight: after.barHeight).isEmpty,
                      "滚回提问后条还挂着 ⇒ 同一条问题双显")

        // 反例③：改成滚到**页面顶部**（偏移 0）⇒ 必须报红。
        let red = Self.jumpViolations(landedOffset: 0, questionTop: expected)
        print("🧪 反例③（点条只滚到页面顶部，落点 0pt ≠ 提问顶端 \(expected)pt）："
              + (red.isEmpty ? "假绿 ❌" : "判红 ✅ — \(red[0])"))
        XCTAssertFalse(red.isEmpty, "落点错成页面顶部判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ④ 条在时，行不许重排

    /// 真行（思考区 200pt 展开 + 工具块 238pt 展开）挂在**同一份**生产布局里，条开 / 关两遍。
    private struct RowsFixture: View {
        let stickyText: String?

        static let narration = "我先读一下 Core/AgentChat.swift 和 Core/AgentDisplayPreferences.swift，"
            + "看看折叠是在哪一层做的，再决定改哪里。"
        static let tools = (0..<300).map { "▸ read_file · Core/File\($0).swift  ✓ · 0.2s" }
            .joined(separator: "\n")

        var body: some View {
            AgentStickyQuestionColumn(
                sticky: stickyText.map { AgentStickyQuestion(messageID: UUID(), index: 0, text: $0) },
                onActivate: {}
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.hair) {
                        AgentThinkingZone(text: Self.narration, phase: .running, manual: nil,
                                          steps: 12, elapsedSeconds: 18.4, highlight: nil,
                                          language: .simplifiedChinese) { _ in }
                        AgentToolBlockView(text: Self.tools, expanded: true, highlight: nil,
                                           language: .simplifiedChinese) {}
                    }
                    .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
                }
            }
        }
    }

    @MainActor
    func testStickyBarDoesNotReflowTheRows() {
        let withBar = UISnapshot.LiveHost(AnyView(RowsFixture(stickyText: Self.plainQuestion)),
                                          size: Self.pageSize)
        let withoutBar = UISnapshot.LiveHost(AnyView(RowsFixture(stickyText: nil)), size: Self.pageSize)
        defer {
            withBar.window.contentView = nil
            withoutBar.window.contentView = nil
        }
        withBar.pump(0.25)
        withoutBar.pump(0.25)

        let rowsWithBar = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSScrollView.self, in: withBar.hosting).map { $0.bounds.height }.sorted()
        let rowsWithoutBar = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSScrollView.self, in: withoutBar.hosting).map { $0.bounds.height }.sorted()
        print("🧪 ④ 滚动容器高（带条）\(rowsWithBar) / （不带条）\(rowsWithoutBar)"
              + "（行 = 思考视口 \(AgentThinkingZone.contentMaxHeight)pt + 工具行体 \(AgentToolBlockView.bodyMaxHeight)pt）")

        // 行高逐点相同：去掉最外层（外层视口本来就要少一行）。
        let outerWith = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSScrollView.self, in: withBar.hosting)
            .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })?
            .bounds.height ?? 0
        let outerWithout = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSScrollView.self, in: withoutBar.hosting)
            .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })?
            .bounds.height ?? 0
        let innerWith = rowsWithBar.filter { $0 < outerWith - 0.5 }
        let innerWithout = rowsWithoutBar.filter { $0 < outerWithout - 0.5 }
        let issues = Self.reflowViolations(withBar: innerWith, withoutBar: innerWithout)
        print("🧪 ④ 行内容高：带条 \(innerWith) / 不带条 \(innerWithout)；外层视口 \(outerWith) → \(outerWithout)"
              + "（差 \(outerWithout - outerWith)pt，应 = 一行 \(AgentStickyQuestion.barHeight)pt）")
        print("🧪 ④ 判定：" + (issues.isEmpty ? "绿 ✅" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertEqual(innerWith.count, 2, "应读到 2 个行内容（思考视口 + 工具行体），实测 \(innerWith.count)")
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        XCTAssertEqual(outerWithout - outerWith, AgentStickyQuestion.barHeight, accuracy: 0.5,
                       "条把外层视口从 \(outerWithout)pt 变成 \(outerWith)pt（应正好少一行）")

        // 整页读数（真 `AgentChatView`）：条只吃视口、不碰内容 —— 视口高正好少一行，
        // 内容一侧（`documentHeight`）只作参考打印：`LazyVStack` 的未物化行按估值算，
        // 滚动位置不同 ⇒ 估值不同 ⇒ 文档高本来就会变（如实登记，不作为判据）。
        let live = makePage(Self.messages(question: Self.plainQuestion))
        defer { live.window.contentView = nil }
        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)
        let atBottom = read(live)
        scroll(live, toOffsetFromTop: 0)
        let atTop = read(live)
        print("🧪 ④ 整页：滚到底（条在）视口高 \(atBottom.viewportFrame.height)pt / 文档高（参考）"
              + "\(atBottom.documentHeight)pt；滚回顶部（条不在）视口高 \(atTop.viewportFrame.height)pt"
              + " / 文档高（参考）\(atTop.documentHeight)pt")
        XCTAssertGreaterThan(atBottom.barHeight, 0, "整页读数里条没出现 ⇒ 这一条判的是空")
        XCTAssertEqual(atTop.viewportFrame.height - atBottom.viewportFrame.height,
                       AgentStickyQuestion.barHeight, accuracy: 0.5,
                       "条把视口从 \(atTop.viewportFrame.height)pt 变成 \(atBottom.viewportFrame.height)pt"
                           + "（应正好少一行 \(AgentStickyQuestion.barHeight)pt）")
        // 条的下沿 = 视口上沿（内容从条下面起，一行都不被盖）。
        XCTAssertEqual(atBottom.viewportFrame.minY, atBottom.barFrame.maxY, accuracy: 1,
                       "视口上沿 \(atBottom.viewportFrame.minY)pt ≠ 条底边 \(atBottom.barFrame.maxY)pt")

        // 反例④：行高被吸顶挤变（思考视口 178 → 174、工具行体 216 → 212）⇒ 必须报红。
        let red = Self.reflowViolations(withBar: [174, 212], withoutBar: [178, 216])
        print("🧪 反例④（条把行挤短）：" + (red.isEmpty ? "假绿 ❌" : "判红 ✅ — \(red[0])"))
        XCTAssertFalse(red.isEmpty, "行高变了判据仍绿 ⇒ 判据没有牙齿")
    }
}
