import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **「回到消息底部」的入口**（详设 §3.39）—— 五条判据，全部读真视图（900×620）。
///
/// ## 主人原话（2026-11-08）
///
/// > 「用户拖动会话界面到上面去之后，在 This task 框上沿（会话对话框的最底部）出现一条
/// >  浮动的、可点击的文字「回到消息底部」，类似 DSH-tui 的效果」
///
/// ## 这一轮修的是什么
///
/// 上一版的入口**叠在正文上**（取证图上压住了最后可见的一行）。改成：入口占对话区底部
/// 一条**保留窄条**（滚动视口**下面的兄弟**，视口到条的上沿为止），并且
/// **入口不在时这条整个不存在（高 0，空间还给正文）**。
///
/// 「出现 ⇒ 视口矮一条 ⇒ 距底变大 ⇒ 关不掉」那条自激不成立：滚到内容底边时偏移被夹到
/// `内容高 − 视口高`，距底恒 0（本文件判据②/④ 量的就是这条）。
///
/// ## 五条判据（都能判红）
///
/// ① 入口出现时**正文一点没被吃**：`入口 ∩ 视口` 高 **0.0pt**（叠层方案 = 一个按钮高 22pt），
///    且「视口底部那一行」的可见高与**无入口基线**（同一条消息、同一个滚动位置、`jumpToBottomEntry: false`）
///    逐点相同；
/// ② 入口消失时保留条高 **0.0pt**，视口高 **回到无入口基线的那个数**（不是白留一条空带）；
/// ③ 点一下 ⇒ 距底 **0pt**、入口高 0、保留条 0、视口回到基线，随后连追加 5 次仍贴底；
/// ④ 出现 / 消失各只发生**一次**高度跳变：采样折叠后只有 2 个视口高，跳变量 == 保留条 40pt，
///    中间值 0 个（反例：三段采样判红）；
/// ⑤ 任何情况下**入口矩形与正文可视矩形不相交**（几何断言，带矩形坐标）。
///
/// ## 边界（如实登记）
/// · **读数要走 `pumpAsync`**：本文件全是 `async` 用例，`RunLoop` 泵循环期间主队列块不落地
///   （§3.33.3 已登记），读数永远回不到宿主 ⇒ 入口根本不出现（假红）；
/// · 点击走**真 `NSButton`**（`AgentJumpToBottomClickButton.performClick(nil)`）——
///   SwiftUI `Button` 在离屏宿主里不落 `NSButton`（`DialogActionRowProbeTests` 已登记）；
/// · 「视口底部那一行」是一个**几何带**（高 = 一个等宽行高，贴在视口底边），不是某一段文本
///   的 run：SwiftUI 的 `Text` 在 macOS 上不落 `NSView`，逐行矩形取不到。带是同一份判据在两态、
///   两个视图上用的同一个定义，所以「差多少」是真读数，不是推算；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）：取证才跑，门禁不跑。
final class AgentJumpToBottomProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    /// 真机那种「输出把界面顶上去」的量级（吸顶条也在场）。
    static let outputLines = 300
    /// 跳变采样那一族用「没有提问」的长输出：**没有提问就没有吸顶条**，
    /// 视口高在采样窗口里只会因为「保留条」变一次 —— 否则吸顶条的 20pt 会混进读数，
    /// 判据会误判成「中间值」（那是另一条契约的跳变，不是这条）。
    static let transitionLines = 60

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "入口判据要真视图与真滚动容器：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    static func output(lines: Int = outputLines) -> String {
        (1...max(1, lines)).map { "第 \($0) 行：这是很长的一段输出，一直往下长，把上面那句提问顶出屏幕。" }
            .joined(separator: "\n")
    }

    /// 一轮对话：用户提问 + 300 行输出（本轮提问会滚出视口顶 ⇒ 吸顶条也在场）。
    static func messages() -> [AgentChatMessage] {
        [
            .init(role: .user, text: "用户发出的问题被滚动的输出冲掉了，现在要能一键回到最新消息。"),
            .init(role: .assistant, text: output()),
        ]
    }

    /// 只有一条长回答、**没有提问**（⇒ 吸顶条不出现）：跳变采样用。
    static func questionFreeMessages(lines: Int = transitionLines) -> [AgentChatMessage] {
        [.init(role: .assistant, text: output(lines: lines))]
    }

    final class Clock {
        var now: TimeInterval = 0
        var next: TimeInterval { now += 1; return now }
    }

    @MainActor
    final class Page {
        let live: UISnapshot.LiveHost<AnyView>
        let model: AgentChatModel
        /// 这一页有没有「回到消息底部」入口（`false` = 无按钮基线）。
        let entryEnabled: Bool
        private let clock = Clock()

        init(messages: [AgentChatMessage], entry: Bool = true) {
            let appState = AppState()
            appState.connections = []
            let model = AgentChatModel(sessionID: "jump-probe",
                                       state: AgentChatState(
                                        messages: messages,
                                        steps: [],
                                        endpoint: .ready(model: "deepseek-v4-flash",
                                                         endpoint: "api.deepseek.com"),
                                        isRunning: false))
            // 每条增量 = 一次窗口到期（一次追加 = 一次状态变更），与 §3.33.3 的探针同一手法。
            model.streamClock = { [clock] in clock.next }
            self.model = model
            self.entryEnabled = entry
            self.live = UISnapshot.LiveHost(
                AnyView(AgentChatView(model: model, jumpToBottomEntry: entry)
                    .environmentObject(appState)
                    .environmentObject(WorkspaceTabsModel())),
                size: AgentJumpToBottomProbeTests.pageSize
            )
            live.settle()
        }

        var outer: NSScrollView? {
            UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
                .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        }

        /// 等内容**长完**再动手：`LazyVStack` 逐批物化行，文档高分几拍往上跳。
        func settleContent(tolerance: CGFloat = 0.5) async {
            var previous: CGFloat = -1
            for _ in 0..<30 {
                await live.pumpAsync(seconds: 0.12)
                let height = outer?.documentView?.bounds.height ?? 0
                if abs(height - previous) <= tolerance { return }
                previous = height
            }
        }

        /// 追加一段正文（**走生产路径**：`observe(.delta)` → 合并器 → 一次 `@Published`）。
        func append(_ piece: String) async {
            _ = clock.next
            await model.observe(.delta(piece))
            await live.pumpAsync(seconds: 0.12)
        }
    }

    // MARK: - 读数

    struct Reading {
        var buttonHeight: CGFloat = 0
        var buttonFrame: CGRect = .zero
        /// 保留窄条的高（条不在 ⇒ 视图不建 ⇒ 0）。
        var stripHeight: CGFloat = 0
        var stripFrame: CGRect = .zero
        var stickyHeight: CGFloat = 0
        var stickyFrame: CGRect = .zero
        /// 正文可视矩形（= `NSClipView` 的框，宿主坐标）。
        var viewportFrame: CGRect = .zero
        var tailFrame: CGRect = .zero
        var documentHeight: CGFloat = 0
        var offsetFromTop: CGFloat = 0
        var distanceToBottom: CGFloat = 0
        /// 一个等宽行高（判「视口底部那一行」用）。
        var lineHeight: CGFloat = 0
        /// 入口从可视正文区里**吃掉**的高度（`入口 ∩ 视口`）——叠层方案 = 一个按钮高。
        var contentEatenByEntry: CGFloat = 0
        /// 视口底部那一行的**可见高**（= 行高 − 被入口压掉的那截）。
        var lastLineVisibleHeight: CGFloat = 0
    }

    /// 一个等宽行高（与输入框同一份算法，不在这里另写一个数）。
    static var monoLineHeight: CGFloat {
        AgentComposerEditor.lineHeight(for: Theme.nsFont(.mono))
    }

    @MainActor
    private func read(_ page: Page) -> Reading {
        var reading = Reading()
        reading.lineHeight = Self.monoLineHeight
        guard let scroll = page.outer, let document = scroll.documentView else { return reading }
        let clip = scroll.contentView
        reading.documentHeight = document.bounds.height
        // 视口 = **clip**（可见内容区）的框，不是 `NSScrollView` 自己的框：
        // 后者底部比可见区多出 2pt（滚动条的边），拿它量「入口离视口/对话区底边多少」会差 2pt。
        reading.viewportFrame = page.live.hosting.convert(clip.bounds, from: clip)
        let flipped = document.isFlipped
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        reading.offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)
        reading.distanceToBottom = AgentScrollFollow.distanceToBottom(
            contentHeight: document.bounds.height,
            viewportHeight: clip.bounds.height,
            offsetFromTop: reading.offsetFromTop)

        if let button = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentJumpToBottomClickButton.self, in: page.live.hosting).first {
            reading.buttonFrame = page.live.hosting.convert(button.bounds, from: button)
            reading.buttonHeight = reading.buttonFrame.height
        }
        if let strip = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentJumpToBottomStripView.self, in: page.live.hosting).first {
            reading.stripFrame = page.live.hosting.convert(strip.bounds, from: strip)
            reading.stripHeight = reading.stripFrame.height
        }
        if let bar = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentStickyClickButton.self, in: page.live.hosting).first {
            reading.stickyFrame = page.live.hosting.convert(bar.bounds, from: bar)
            reading.stickyHeight = reading.stickyFrame.height
        }
        if let tail = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentTranscriptTailMarker.self, in: page.live.hosting).first {
            reading.tailFrame = page.live.hosting.convert(tail.bounds, from: tail)
        }

        // ① 正文被入口吃掉了多少 / 视口底部那一行还剩多高 —— **同一份定义量两态两视图**。
        reading.contentEatenByEntry = Self.intersection(reading.buttonFrame, reading.viewportFrame).height
        let lastLineBand = CGRect(x: reading.viewportFrame.minX,
                                  y: reading.viewportFrame.maxY - reading.lineHeight,
                                  width: reading.viewportFrame.width,
                                  height: reading.lineHeight)
        reading.lastLineVisibleHeight = lastLineBand.height
            - Self.intersection(reading.buttonFrame, lastLineBand).height
        return reading
    }

    static func intersection(_ a: CGRect, _ b: CGRect) -> CGRect {
        guard !a.isEmpty, !b.isEmpty else { return .zero }
        let rect = a.intersection(b)
        return rect.isNull ? .zero : rect
    }

    // MARK: - 滚动

    /// 把对话区滚到「距内容顶 `offset` pt」（超界自动夹到最大偏移）—— 同步版（采样窗口里用）。
    @MainActor
    private func jumpScroll(_ page: Page, toOffsetFromTop offset: CGFloat) {
        guard let view = page.outer, let document = view.documentView else { return }
        let clip = view.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let clamped = min(max(0, offset), maxOffset)
        let y = document.isFlipped ? clamped : (maxOffset - clamped)
        clip.scroll(to: NSPoint(x: 0, y: y))
        view.reflectScrolledClipView(clip)
    }

    @MainActor
    private func scroll(_ page: Page, toOffsetFromTop offset: CGFloat) async {
        jumpScroll(page, toOffsetFromTop: offset)
        await page.live.pumpAsync(seconds: 0.3)
    }

    /// 从**当前的底**往上退 `points` pt（同步版，采样窗口里用）。
    @MainActor
    private func jumpScrollUp(_ page: Page, by points: CGFloat) {
        guard let view = page.outer, let document = view.documentView else { return }
        let maxOffset = max(0, document.bounds.height - view.contentView.bounds.height)
        jumpScroll(page, toOffsetFromTop: maxOffset - points)
    }

    /// 从底往上退 `points` pt（先等内容长完，滚的才是真「距底」）。
    @MainActor
    private func scrollUp(_ page: Page, by points: CGFloat) async {
        await page.settleContent()
        guard let view = page.outer, let document = view.documentView else { return }
        let maxOffset = max(0, document.bounds.height - view.contentView.bounds.height)
        await scroll(page, toOffsetFromTop: maxOffset - points)
    }

    // MARK: - 判据函数（真读数与反例共用一套，反例才证明判据有牙齿）

    /// ① **入口不吃正文**：`入口 ∩ 视口` 必须是 0pt，且视口底部那一行的可见高与无入口基线相同。
    ///
    /// 叠层方案在这一条上的读数就是「差一个按钮高」：入口整个落在视口里 ⇒ 吃掉 22pt。
    static func textAreaViolations(eaten: CGFloat,
                                   buttonHeight: CGFloat,
                                   lastLineVisible: CGFloat,
                                   baselineLastLineVisible: CGFloat,
                                   lineHeight: CGFloat) -> [String] {
        var issues: [String] = []
        if eaten > 0.5 {
            issues.append("入口从可视正文区里吃掉 \(fmt(eaten))pt"
                          + "（入口高 \(fmt(buttonHeight))pt）⇒ 这就是叠层，正文被压住")
        }
        if abs(lastLineVisible - lineHeight) > 0.5 {
            issues.append("视口底部那一行可见高 \(fmt(lastLineVisible))pt ≠ 行高 \(fmt(lineHeight))pt")
        }
        if abs(lastLineVisible - baselineLastLineVisible) > 0.5 {
            issues.append("视口底部那一行可见高 \(fmt(lastLineVisible))pt ≠ 无入口基线 "
                          + "\(fmt(baselineLastLineVisible))pt")
        }
        return issues
    }

    /// ② **入口不在 ⇒ 保留条高 0、视口回到无入口基线**。
    static func hiddenStripViolations(stripHeight: CGFloat,
                                      viewportHeight: CGFloat,
                                      baselineViewportHeight: CGFloat) -> [String] {
        var issues: [String] = []
        if stripHeight > 0.5 {
            issues.append("入口不在时保留条仍高 \(fmt(stripHeight))pt ⇒ 白留一条空带")
        }
        if abs(viewportHeight - baselineViewportHeight) > 0.5 {
            issues.append("入口不在时视口高 \(fmt(viewportHeight))pt ≠ 无入口基线 "
                          + "\(fmt(baselineViewportHeight))pt ⇒ 空间没还回去")
        }
        return issues
    }

    /// ③ 点完 ⇒ 距底 0、入口消失、保留条 0、视口回到基线。
    static func clickViolations(distanceToBottom: CGFloat,
                                buttonHeight: CGFloat,
                                stripHeight: CGFloat,
                                viewportHeight: CGFloat,
                                baselineViewportHeight: CGFloat) -> [String] {
        var issues: [String] = []
        if distanceToBottom > AgentScrollFollow.bottomTolerance {
            issues.append("点完距底 \(fmt(distanceToBottom))pt > 容差 "
                          + "\(fmt(AgentScrollFollow.bottomTolerance))pt")
        }
        if buttonHeight > 0.5 { issues.append("点完入口仍高 \(fmt(buttonHeight))pt ⇒ 该隐没隐") }
        if stripHeight > 0.5 { issues.append("点完保留条仍高 \(fmt(stripHeight))pt ⇒ 空间没还回去") }
        if abs(viewportHeight - baselineViewportHeight) > 0.5 {
            issues.append("点完视口高 \(fmt(viewportHeight))pt ≠ 基线 "
                          + "\(fmt(baselineViewportHeight))pt")
        }
        return issues
    }

    /// ③ 点完之后的**跟随**：连续追加若干次，每次距底都必须在容差内。
    static func followRestoredViolations(_ distances: [CGFloat]) -> [String] {
        guard !distances.isEmpty else { return ["没有采样 ⇒ 判的是空"] }
        let bad = distances.filter { $0 > AgentScrollFollow.bottomTolerance }
        guard !bad.isEmpty else { return [] }
        return ["点完之后追加 \(distances.count) 次，距底 "
                + bad.map { fmt($0) }.joined(separator: "/")
                + "pt > 容差 ⇒ 跟随没恢复"]
    }

    /// ④ **出现 / 消失各只发生一次高度跳变**：把采样折叠相邻相同值（±0.5pt）之后
    /// 必须只剩 `from → to` 两个值，跳变量 == 保留条高，**一个中间值都不许有**。
    static func singleJumpViolations(samples: [CGFloat],
                                     from expectedFrom: CGFloat,
                                     to expectedTo: CGFloat) -> [String] {
        guard samples.count >= 2 else { return ["采样只有 \(samples.count) 个点 ⇒ 判的是空"] }
        var distinct: [CGFloat] = []
        for value in samples {
            if let last = distinct.last, abs(value - last) <= 0.5 { continue }
            distinct.append(value)
        }
        var issues: [String] = []
        let list = distinct.map { fmt($0) }.joined(separator: " → ")
        if distinct.count != 2 {
            issues.append("采样折叠后有 \(distinct.count) 个不同视口高（\(list)）⇒ 有中间值 / 来回跳")
        }
        guard let first = distinct.first, let last = distinct.last else {
            return issues.isEmpty ? ["采样折叠后为空"] : issues
        }
        if abs(first - expectedFrom) > 0.5 {
            issues.append("起点视口高 \(fmt(first))pt ≠ 期望 \(fmt(expectedFrom))pt（\(list)）")
        }
        if abs(last - expectedTo) > 0.5 {
            issues.append("终点视口高 \(fmt(last))pt ≠ 期望 \(fmt(expectedTo))pt（\(list)）")
        }
        let magnitude = abs(last - first)
        if abs(magnitude - AgentJumpToBottom.stripHeight) > 1 {
            issues.append("跳变量 \(fmt(magnitude))pt ≠ 保留条 \(fmt(AgentJumpToBottom.stripHeight))pt")
        }
        return issues
    }

    /// ⑤ **几何断言**：入口矩形与正文可视矩形**不相交**（相减 > 0.5pt 就算压住）。
    static func occlusionViolations(button: CGRect, viewport: CGRect) -> [String] {
        let overlap = intersection(button, viewport)
        guard overlap.height > 0.5 else { return [] }
        return ["入口 \(rect(button)) 与正文可视矩形 \(rect(viewport)) 相交 "
                + "\(rect(overlap))（高 \(fmt(overlap.height))pt）⇒ 会压住正文"]
    }

    /// ⑥ 与吸顶条共存：两者都在场、且不重叠。
    static func coexistViolations(stickyHeight: CGFloat,
                                  stickyFrame: CGRect,
                                  buttonHeight: CGFloat,
                                  buttonFrame: CGRect) -> [String] {
        var issues: [String] = []
        if stickyHeight <= 0.5 { issues.append("上翻时吸顶条没出现（高 \(fmt(stickyHeight))pt）") }
        if abs(stickyHeight - AgentStickyQuestion.barHeight) > 0.5 {
            issues.append("吸顶条高 \(fmt(stickyHeight))pt ≠ 一行 \(fmt(AgentStickyQuestion.barHeight))pt")
        }
        if buttonHeight <= 0.5 { issues.append("上翻时入口没出现（高 \(fmt(buttonHeight))pt）") }
        // 宿主坐标：y 越大越靠下。
        if buttonFrame.minY < stickyFrame.maxY - 0.5 {
            issues.append("入口上沿 \(fmt(buttonFrame.minY))pt 高于吸顶条下沿 "
                          + "\(fmt(stickyFrame.maxY))pt ⇒ 两者重叠")
        }
        return issues
    }

    static func fmt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    static func rect(_ value: CGRect) -> String {
        "{\(fmt(value.minX)), \(fmt(value.minY)), \(fmt(value.width)), \(fmt(value.height))}"
    }

    // MARK: - ① ② ⑤ 入口占保留条、不叠层、消失后高 0

    @MainActor
    func testTheEntryReservesAStripAndNeverCoversTheText() async {
        let page = Page(messages: Self.messages())
        let baselinePage = Page(messages: Self.messages(), entry: false)
        defer {
            page.live.window.contentView = nil
            baselinePage.live.window.contentView = nil
        }

        // ② 贴底（入口不在）：保留条 0、视口 == 无入口基线。
        await page.settleContent()
        await baselinePage.settleContent()
        let hidden = read(page)
        let baselineAtRest = read(baselinePage)
        print("🧪 ② 贴底：距底 \(Self.fmt(hidden.distanceToBottom))pt / 入口高 "
              + "\(Self.fmt(hidden.buttonHeight))pt / 保留条 \(Self.fmt(hidden.stripHeight))pt"
              + " / 视口 \(Self.fmt(hidden.viewportFrame.height))pt"
              + " / 基线视口 \(Self.fmt(baselineAtRest.viewportFrame.height))pt")
        let hiddenIssues = Self.hiddenStripViolations(
            stripHeight: hidden.stripHeight,
            viewportHeight: hidden.viewportFrame.height,
            baselineViewportHeight: baselineAtRest.viewportFrame.height
        )
        print("🧪 ② 判定（入口不在 ⇒ 高 0、空间还回去）："
              + (hiddenIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + hiddenIssues.joined(separator: "；")))
        XCTAssertTrue(hiddenIssues.isEmpty, hiddenIssues.joined(separator: "；"))

        // 反例②：入口不在却仍占一条 40pt（恒留空带）⇒ 必须判红。
        let bandKept = Self.hiddenStripViolations(
            stripHeight: AgentJumpToBottom.stripHeight,
            viewportHeight: hidden.viewportFrame.height - AgentJumpToBottom.stripHeight,
            baselineViewportHeight: baselineAtRest.viewportFrame.height
        )
        print("🧪 反例②（入口不在仍留 40pt 空带）："
              + (bandKept.isEmpty ? "假绿 ❌" : "判红 ✅ — \(bandKept[0])"))
        XCTAssertFalse(bandKept.isEmpty, "恒留空带判据仍绿 ⇒ 判据没有牙齿")

        // 上翻 100pt（入口出现）；基线页同一条消息、**同一个滚动位置**（它没有入口）。
        await scrollUp(page, by: 100)
        await page.settleContent()
        await scrollUp(baselinePage, by: 100)
        await baselinePage.settleContent()
        let shown = read(page)
        let baselineShown = read(baselinePage)
        print("🧪 ① 入口在场：入口 \(Self.rect(shown.buttonFrame)) / 正文可视矩形 "
              + "\(Self.rect(shown.viewportFrame)) / 保留条 \(Self.rect(shown.stripFrame))")
        print("🧪 ① 吃掉的可视正文高 \(Self.fmt(shown.contentEatenByEntry))pt / 视口底部那一行可见高 "
              + "\(Self.fmt(shown.lastLineVisibleHeight))pt（行高 \(Self.fmt(shown.lineHeight))pt）"
              + " / 基线同位置 \(Self.fmt(baselineShown.lastLineVisibleHeight))pt"
              + " / 距底 \(Self.fmt(shown.distanceToBottom))pt")
        XCTAssertGreaterThan(shown.buttonHeight, 0.5,
                             "上翻 100pt 时入口没出现 ⇒ 这一条判的是空")

        let textArea = Self.textAreaViolations(
            eaten: shown.contentEatenByEntry,
            buttonHeight: shown.buttonHeight,
            lastLineVisible: shown.lastLineVisibleHeight,
            baselineLastLineVisible: baselineShown.lastLineVisibleHeight,
            lineHeight: shown.lineHeight
        )
        print("🧪 ① 判定（入口不吃正文）："
              + (textArea.isEmpty ? "绿 ✅" : "红 ❌ — " + textArea.joined(separator: "；")))
        XCTAssertTrue(textArea.isEmpty, textArea.joined(separator: "；"))

        // 反例①：入口叠在视口底部内侧（= 上一版的写法，底边距底 12pt、高 22pt）⇒ 吃掉一个按钮高。
        let overlayButton = CGRect(x: shown.buttonFrame.minX,
                                   y: shown.viewportFrame.maxY - AgentJumpToBottom.bottomGap
                                      - AgentJumpToBottom.barHeight,
                                   width: shown.buttonFrame.width,
                                   height: AgentJumpToBottom.barHeight)
        let overlayEaten = Self.intersection(overlayButton, shown.viewportFrame).height
        let lastLineBand = CGRect(x: shown.viewportFrame.minX,
                                  y: shown.viewportFrame.maxY - shown.lineHeight,
                                  width: shown.viewportFrame.width,
                                  height: shown.lineHeight)
        let overlayLastLine = lastLineBand.height
            - Self.intersection(overlayButton, lastLineBand).height
        let overlayIssues = Self.textAreaViolations(
            eaten: overlayEaten,
            buttonHeight: overlayButton.height,
            lastLineVisible: overlayLastLine,
            baselineLastLineVisible: baselineShown.lastLineVisibleHeight,
            lineHeight: shown.lineHeight
        )
        print("🧪 反例①（入口叠在视口底部内侧）：吃掉 \(Self.fmt(overlayEaten))pt、"
              + "那一行可见高 \(Self.fmt(overlayLastLine))pt → "
              + (overlayIssues.isEmpty ? "假绿 ❌" : "判红 ✅ — \(overlayIssues[0])"))
        XCTAssertFalse(overlayIssues.isEmpty, "叠层写法判据仍绿 ⇒ 判据没有牙齿")

        // ⑤ 几何断言：入口矩形与正文可视矩形不相交。
        print("🧪 ⑤ 入口 \(Self.rect(shown.buttonFrame)) vs 正文可视 "
              + "\(Self.rect(shown.viewportFrame))，入口上沿在视口底之下 "
              + "\(Self.fmt(shown.buttonFrame.minY - shown.viewportFrame.maxY))pt")
        let occlusion = Self.occlusionViolations(button: shown.buttonFrame,
                                                 viewport: shown.viewportFrame)
        print("🧪 ⑤ 判定（不相交）：" + (occlusion.isEmpty ? "绿 ✅" : "红 ❌ — " + occlusion.joined(separator: "；")))
        XCTAssertTrue(occlusion.isEmpty, occlusion.joined(separator: "；"))

        // 反例⑤：入口抬 10pt 进视口（叠层写法）⇒ 必须判红。
        let intruding = shown.buttonFrame.offsetBy(dx: 0, dy: -10)
        let covered = Self.occlusionViolations(button: intruding, viewport: shown.viewportFrame)
        print("🧪 反例⑤（入口伸进视口 10pt）：" + (covered.isEmpty ? "假绿 ❌" : "判红 ✅ — \(covered[0])"))
        XCTAssertFalse(covered.isEmpty, "入口压住正文判据仍绿 ⇒ 判据没有牙齿")

        // 取证图（形态也看得到：胶囊 + 一行文案）—— 见 `testCaptureTheEntryInBothLanguages`。
    }

    // MARK: - 取证图（中英各一张）

    /// **中英各一张**：每张**重建一次视图树**（文案在 body 求值时才定语言）。
    ///
    /// 为什么不在一棵活宿主上切语言：`beginHostLanguage` 只改文案的取值语境，
    /// SwiftUI 不会因此重排 —— 上一版实测两张**逐字节相同**（都是宿主的英文），
    /// 「中文一张」是假的，语言覆盖门禁那一侧照样判红。
    @MainActor
    func testCaptureTheEntryInBothLanguages() async {
        for language in UISnapshot.coverageLanguages {
            _ = LocalizationManager.beginHostLanguage(language)
            let page = Page(messages: Self.messages())
            defer { page.live.window.contentView = nil }
            await page.settleContent()
            await scrollUp(page, by: 100)
            await page.live.pumpAsync(seconds: 0.3)
            try? page.live.capture(
                name: "agent-jump-to-bottom\(UISnapshot.languageSuffix(language))",
                language: language
            )
            LocalizationManager.endHostLanguage()
        }
    }

    // MARK: - ③ 点一下 ⇒ 距底 0、入口与保留条都归 0、后续 5 次追加仍贴底

    @MainActor
    func testClickingReturnsToBottomAndRestoresFollowing() async {
        let baselinePage = Page(messages: Self.messages(), entry: false)
        let page = Page(messages: Self.messages())
        defer {
            page.live.window.contentView = nil
            baselinePage.live.window.contentView = nil
        }
        await page.settleContent()
        await baselinePage.settleContent()
        let baseline = read(baselinePage)

        await scrollUp(page, by: 200)
        let before = read(page)
        print("🧪 ③ 上翻 200pt：距底 \(Self.fmt(before.distanceToBottom))pt / 入口高 "
              + "\(Self.fmt(before.buttonHeight))pt / 保留条 \(Self.fmt(before.stripHeight))pt"
              + " / 视口 \(Self.fmt(before.viewportFrame.height))pt")
        XCTAssertGreaterThan(before.buttonHeight, 0.5, "上翻 200pt 后没有入口 ⇒ 这一条判的是空")
        XCTAssertGreaterThan(before.stripHeight, 0.5, "入口在、保留条却是 0 ⇒ 入口没占位（又叠在正文上了）")

        guard let button = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentJumpToBottomClickButton.self, in: page.live.hosting).first else {
            return XCTFail("没找到入口的点击面（NSButton）⇒ 判据点不到它")
        }
        button.performClick(nil)          // 真点击路径
        await page.live.pumpAsync(seconds: 0.5)

        let after = read(page)
        print("🧪 ③ 点一下：距底 \(Self.fmt(before.distanceToBottom))pt → \(Self.fmt(after.distanceToBottom))pt"
              + " / 入口高 \(Self.fmt(before.buttonHeight))pt → \(Self.fmt(after.buttonHeight))pt"
              + " / 保留条 \(Self.fmt(before.stripHeight))pt → \(Self.fmt(after.stripHeight))pt"
              + " / 视口 \(Self.fmt(after.viewportFrame.height))pt（基线 "
              + "\(Self.fmt(baseline.viewportFrame.height))pt）")
        let clickIssues = Self.clickViolations(
            distanceToBottom: after.distanceToBottom,
            buttonHeight: after.buttonHeight,
            stripHeight: after.stripHeight,
            viewportHeight: after.viewportFrame.height,
            baselineViewportHeight: baseline.viewportFrame.height
        )
        print("🧪 ③ 判定（点完即贴底 + 入口与条都归 0）："
              + (clickIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + clickIssues.joined(separator: "；")))
        XCTAssertTrue(clickIssues.isEmpty, clickIssues.joined(separator: "；"))

        // 跟随真的恢复了：连续追加 5 次，每一次都必须仍贴底。
        var distances: [CGFloat] = []
        for index in 0..<5 {
            await page.append("\n追加第 \(index + 1) 段：这一行会继续把内容往下撑。")
            distances.append(read(page).distanceToBottom)
        }
        print("🧪 ③ 后续 5 次追加的距底："
              + distances.map { Self.fmt($0) }.joined(separator: " / ") + " pt")
        let followIssues = Self.followRestoredViolations(distances)
        print("🧪 ③ 判定（跟随已恢复）："
              + (followIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + followIssues.joined(separator: "；")))
        XCTAssertTrue(followIssues.isEmpty, followIssues.joined(separator: "；"))

        // 反例③：只滚一次、不恢复跟随（距底 12pt 那种）⇒ 同一套判据必须报红。
        let stale = Self.followRestoredViolations([0, 0, 12, 24, 36])
        print("🧪 反例③（只滚到底、跟随没恢复）：" + (stale.isEmpty ? "假绿 ❌" : "判红 ✅ — \(stale[0])"))
        XCTAssertFalse(stale.isEmpty, "跟随没恢复判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ④ 出现 / 消失各只发生一次高度跳变（采样无中间值）

    @MainActor
    func testAppearAndDisappearAreSingleHeightJumps() async {
        // 无提问夹具：没有吸顶条，采样窗口里视口高的唯一变化量就是保留条。
        let page = Page(messages: Self.questionFreeMessages(), entry: false)
        defer { page.live.window.contentView = nil }
        await page.settleContent()
        let atRest = read(page)
        print("🧪 ④ 基线（无入口）：视口 \(Self.fmt(atRest.viewportFrame.height))pt"
              + " / 距底 \(Self.fmt(atRest.distanceToBottom))pt")

        // 换成带入口的同一份消息。
        let livePage = Page(messages: Self.questionFreeMessages())
        defer { livePage.live.window.contentView = nil }
        await livePage.settleContent()
        let hiddenBefore = read(livePage)
        XCTAssertLessThanOrEqual(hiddenBefore.stripHeight, 0.5,
                                 "入口不该在贴底时占位（保留条 \(Self.fmt(hiddenBefore.stripHeight))pt）")

        // **出现**：从贴底一次滚到距底 60pt（> 门槛 40）—— 采样整个窗口。
        let appearSamples = await sampleViewport(livePage) {
            self.jumpScrollUp(livePage, by: 60)
        }
        let appeared = read(livePage)
        let expectedShown = hiddenBefore.viewportFrame.height - AgentJumpToBottom.stripHeight
        print("🧪 ④ 出现：采样 \(appearSamples.count) 点 → "
              + appearSamples.map { Self.fmt($0) }.joined(separator: " / "))
        print("🧪 ④ 出现后：入口高 \(Self.fmt(appeared.buttonHeight))pt / 保留条 "
              + "\(Self.fmt(appeared.stripHeight))pt / 视口 \(Self.fmt(appeared.viewportFrame.height))pt"
              + " / 距底 \(Self.fmt(appeared.distanceToBottom))pt")
        let appearIssues = Self.singleJumpViolations(samples: appearSamples,
                                                     from: hiddenBefore.viewportFrame.height,
                                                     to: expectedShown)
        print("🧪 ④ 判定（出现只跳一次）："
              + (appearIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + appearIssues.joined(separator: "；")))
        XCTAssertTrue(appearIssues.isEmpty, appearIssues.joined(separator: "；"))

        // 反例④：同样的起点与终点，但中间插一帧（逐帧插值的形态）⇒ 必须判红。
        let interpolated = [hiddenBefore.viewportFrame.height,
                            hiddenBefore.viewportFrame.height - 20,
                            expectedShown,
                            expectedShown]
        let interpolatedIssues = Self.singleJumpViolations(samples: interpolated,
                                                           from: hiddenBefore.viewportFrame.height,
                                                           to: expectedShown)
        print("🧪 反例④（出现时逐帧插值）："
              + (interpolatedIssues.isEmpty ? "假绿 ❌" : "判红 ✅ — \(interpolatedIssues[0])"))
        XCTAssertFalse(interpolatedIssues.isEmpty, "逐帧插值判据仍绿 ⇒ 判据没有牙齿")

        // **消失**：一次滚回内容底边 —— 距底必须真的回到 0（这条同时证明「关不掉」不成立）。
        let disappearSamples = await sampleViewport(livePage) {
            self.jumpScroll(livePage, toOffsetFromTop: .greatestFiniteMagnitude)
        }
        let gone = read(livePage)
        print("🧪 ④ 消失：采样 \(disappearSamples.count) 点 → "
              + disappearSamples.map { Self.fmt($0) }.joined(separator: " / "))
        print("🧪 ④ 消失后：距底 \(Self.fmt(gone.distanceToBottom))pt / 入口高 "
              + "\(Self.fmt(gone.buttonHeight))pt / 保留条 \(Self.fmt(gone.stripHeight))pt"
              + " / 视口 \(Self.fmt(gone.viewportFrame.height))pt（基线 "
              + "\(Self.fmt(atRest.viewportFrame.height))pt）")
        let disappearIssues = Self.singleJumpViolations(samples: disappearSamples,
                                                        from: expectedShown,
                                                        to: hiddenBefore.viewportFrame.height)
        print("🧪 ④ 判定（消失只跳一次）："
              + (disappearIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + disappearIssues.joined(separator: "；")))
        XCTAssertTrue(disappearIssues.isEmpty, disappearIssues.joined(separator: "；"))

        // 滚回底之后：距底 0、条归 0、视口回到无入口基线（「关不掉」那条死锁的反证）。
        let backIssues = Self.hiddenStripViolations(
            stripHeight: gone.stripHeight,
            viewportHeight: gone.viewportFrame.height,
            baselineViewportHeight: atRest.viewportFrame.height
        )
        print("🧪 ④ 判定（回到底部 ⇒ 条归 0、视口回基线）："
              + (backIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + backIssues.joined(separator: "；")))
        XCTAssertTrue(backIssues.isEmpty, backIssues.joined(separator: "；"))
        XCTAssertLessThanOrEqual(gone.distanceToBottom, AgentScrollFollow.bottomTolerance,
                                 "滚到内容底边后距底 \(Self.fmt(gone.distanceToBottom))pt "
                                 + "> 容差 ⇒ 消失条件不可达（入口会关不掉）")
    }

    /// 采样一段窗口里的**视口高**：先记一个点，执行动作，再逐帧（每 8ms 让出主 actor）记点。
    @MainActor
    private func sampleViewport(_ page: Page,
                                seconds: Double = 0.6,
                                action: () -> Void) async -> [CGFloat] {
        var samples: [CGFloat] = []
        page.live.settle()
        samples.append(read(page).viewportFrame.height)
        action()
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            page.live.settle()
            samples.append(read(page).viewportFrame.height)
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        page.live.settle()
        samples.append(read(page).viewportFrame.height)
        return samples
    }

    // MARK: - ⑥ 与吸顶条共存

    @MainActor
    func testCoexistsWithTheStickyQuestionBar() async {
        let page = Page(messages: Self.messages())
        defer { page.live.window.contentView = nil }

        await scrollUp(page, by: 100)
        let reading = read(page)
        print("🧪 ⑥ 吸顶条高 \(Self.fmt(reading.stickyHeight))pt \(Self.rect(reading.stickyFrame))"
              + " / 入口高 \(Self.fmt(reading.buttonHeight))pt \(Self.rect(reading.buttonFrame))"
              + " / 视口 \(Self.rect(reading.viewportFrame))")
        let issues = Self.coexistViolations(stickyHeight: reading.stickyHeight,
                                            stickyFrame: reading.stickyFrame,
                                            buttonHeight: reading.buttonHeight,
                                            buttonFrame: reading.buttonFrame)
        print("🧪 ⑥ 判定（共存、不重叠）：" + (issues.isEmpty ? "绿 ✅" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

        // 反例⑥：入口跑到吸顶条上面去了 ⇒ 必须报红。
        let overlap = Self.coexistViolations(stickyHeight: reading.stickyHeight,
                                             stickyFrame: reading.stickyFrame,
                                             buttonHeight: reading.buttonHeight,
                                             buttonFrame: CGRect(x: 0, y: reading.stickyFrame.minY,
                                                                 width: 100, height: 22))
        print("🧪 反例⑥（入口压在吸顶条上）：" + (overlap.isEmpty ? "假绿 ❌" : "判红 ✅ — \(overlap[0])"))
        XCTAssertFalse(overlap.isEmpty, "两者重叠判据仍绿 ⇒ 判据没有牙齿")
    }
}
