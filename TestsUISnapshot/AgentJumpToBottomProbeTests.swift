import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **「回到消息底部」的浮动入口**（详设 §3.39）—— 六条判据，全部读真视图（900×620）。
///
/// ## 主人原话（2026-11-08）
///
/// > 「用户拖动会话界面到上面去之后，在 This task 框上沿（会话对话框的最底部）出现一条
/// >  浮动的、可点击的文字「回到消息底部」，类似 DSH-tui 的效果」
///
/// ## 六条判据（都能判红）
///
/// ① 初始贴底 ⇒ 入口高 **0**（视图都不建）；
/// ② 上翻 100pt ⇒ 高 **20–24pt**，底边到对话区底边 == 块间距 **12pt**；
/// ③ 点它 ⇒ 距底 **0pt**、高 **0**，之后再追加 5 次**仍距底 0**（跟随真的恢复了）；
/// ④ 再上翻 ⇒ **再出现**（不是一次性）；
/// ⑤ 不遮正文：入口底边**不低于**最后一行的底边；贴底时正文尾部恒留的那条带
///    == 入口高 + 呼吸 + 块间距（39pt）；
/// ⑥ 与吸顶条共存：上翻时吸顶条 **20pt** 与入口 **22pt** 同时在场、互不重叠。
///
/// ## 边界（如实登记）
/// · 入口是**浮动**的：上翻之后经过入口那一条带的正文是**从它下面滚过去**的（半透明毛玻璃）——
///   判据⑤ 钉的是「**最后一行**永远不被压」与「正文尾部恒留了入口的位置」这两件事，
///   不是「任何偏移下都不与任何一行重合」（那只有把入口挤出视口才做得到，代价是视口永远矮一截）；
/// · **读数要走 `pumpAsync`**：本文件全是 `async` 用例，`RunLoop` 泵循环期间主队列块不落地
///   （§3.33.3 已登记），读数永远回不到宿主 ⇒ 入口不出现那种「假红」；
/// · 点击走**真 `NSButton`**（`AgentJumpToBottomClickButton.performClick(nil)`）——
///   SwiftUI `Button` 在离屏宿主里不落 `NSButton`（`DialogActionRowProbeTests` 已登记）；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）：取证才跑，门禁不跑。
final class AgentJumpToBottomProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    /// 真机那种「输出把界面顶上去」的量级。
    static let outputLines = 300

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

    final class Clock {
        var now: TimeInterval = 0
        var next: TimeInterval { now += 1; return now }
    }

    @MainActor
    final class Page {
        let live: UISnapshot.LiveHost<AnyView>
        let model: AgentChatModel
        private let clock = Clock()

        init(messages: [AgentChatMessage]) {
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
            self.live = UISnapshot.LiveHost(
                AnyView(AgentChatView(model: model)
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
        ///
        /// 不等就滚，常常滚在「文档还短」的那一拍上 ⇒ 滚到的是当时的底，下一拍长高、
        /// 状态机读成「贴底态的内容长高」⇒ 当场补跟回底部（第一版实测就是这么假红的）。
        /// 这里用 `pumpAsync`（让出主 actor），读数与布局的回写才会落地。
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
        var stickyHeight: CGFloat = 0
        var stickyFrame: CGRect = .zero
        var viewportFrame: CGRect = .zero
        var tailFrame: CGRect = .zero
        var documentHeight: CGFloat = 0
        var offsetFromTop: CGFloat = 0
        var distanceToBottom: CGFloat = 0
        var trailingBand: CGFloat = 0
        var composerTop: CGFloat?
    }

    @MainActor
    private func read(_ page: Page) -> Reading {
        var reading = Reading()
        guard let scroll = page.outer, let document = scroll.documentView else { return reading }
        let clip = scroll.contentView
        reading.documentHeight = document.bounds.height
        reading.viewportFrame = page.live.hosting.convert(scroll.bounds, from: scroll)
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
        if let bar = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentStickyClickButton.self, in: page.live.hosting).first {
            reading.stickyFrame = page.live.hosting.convert(bar.bounds, from: bar)
            reading.stickyHeight = reading.stickyFrame.height
        }
        if let tail = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentTranscriptTailMarker.self, in: page.live.hosting).first {
            reading.tailFrame = page.live.hosting.convert(tail.bounds, from: tail)
            // 尾随带：最后一行底边 → **内容底边**。内容底边在宿主坐标里 = 视口底 + 距底
            // （距底的定义就是这个）。不拿文档高去减：`LazyVStack` 对没物化的行只有估值，
            // 文档高会虚高一截，那个减法量出来的是「估值误差」不是「布局留的位」。
            if reading.tailFrame.height > 0.5 {
                reading.trailingBand = (reading.viewportFrame.maxY + reading.distanceToBottom)
                    - reading.tailFrame.maxY
            }
        }
        // 输入区上沿（多行编辑器那一格）：只作旁证打印，判定不读它。
        if let editor = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: NSTextView.self, in: page.live.hosting).first {
            reading.composerTop = page.live.hosting.convert(editor.bounds, from: editor).minY
        }
        return reading
    }

    /// 把对话区滚到「距内容顶 `offset` pt」（超界自动夹到最大偏移）。
    @MainActor
    private func scroll(_ page: Page, toOffsetFromTop offset: CGFloat) async {
        guard let view = page.outer, let document = view.documentView else { return }
        let clip = view.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let clamped = min(max(0, offset), maxOffset)
        let y = document.isFlipped ? clamped : (maxOffset - clamped)
        clip.scroll(to: NSPoint(x: 0, y: y))
        view.reflectScrolledClipView(clip)
        await page.live.pumpAsync(seconds: 0.3)
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

    /// ② 出现：高落在 20–24 的带里，且底边到对话区底边 == 块间距。
    static func appearViolations(height: CGFloat,
                                 buttonBottom: CGFloat,
                                 viewportBottom: CGFloat) -> [String] {
        var issues: [String] = []
        guard height > 0.5 else { return ["上翻之后入口高 \(height)pt ⇒ 入口没出现"] }
        if !(20...24).contains(height) {
            issues.append("入口高 \(height)pt 不在 20–24 的带里")
        }
        let gap = viewportBottom - buttonBottom
        if abs(gap - AgentJumpToBottom.bottomGap) > 1 {
            issues.append("入口底边到对话区底边 \(gap)pt ≠ 块间距 \(AgentJumpToBottom.bottomGap)pt")
        }
        return issues
    }

    /// ① / ③ 贴底（或点完）⇒ 高 0、距底 0。
    static func hiddenAndPinnedViolations(height: CGFloat, distanceToBottom: CGFloat) -> [String] {
        var issues: [String] = []
        if height > 0.5 { issues.append("贴底时入口仍高 \(height)pt ⇒ 该隐没隐") }
        if distanceToBottom > AgentScrollFollow.bottomTolerance {
            issues.append("贴底后距底 \(distanceToBottom)pt > 容差 \(AgentScrollFollow.bottomTolerance)pt")
        }
        return issues
    }

    /// ③ 点完之后的**跟随**：连续追加若干次，每次距底都必须是 0。
    static func followRestoredViolations(_ distances: [CGFloat]) -> [String] {
        guard !distances.isEmpty else { return ["没有采样 ⇒ 判的是空"] }
        let bad = distances.filter { $0 > AgentScrollFollow.bottomTolerance }
        guard !bad.isEmpty else { return [] }
        return ["点完之后追加 \(distances.count) 次，距底 "
                + bad.map { String(format: "%.1f", $0) }.joined(separator: "/")
                + "pt > 容差 ⇒ 跟随没恢复"]
    }

    /// ⑤ 不遮正文：入口底边不得低于最后一行的底边（预留言出的带里）。
    static func occlusionViolations(buttonBottom: CGFloat, lastLineBottom: CGFloat) -> [String] {
        let overlap = buttonBottom - lastLineBottom
        guard overlap > 0.5 else { return [] }
        return ["入口底边压过最后一行 \(String(format: "%.1f", overlap))pt ⇒ 遮正文"]
    }

    /// ⑤ **预留带恒在**：贴底时「最后一行底边 → 内容底边」必须正好是
    /// 入口高 + 呼吸 4 + 块间距 12（+ 1pt 记号）。
    ///
    /// 为什么不比文档总高：`LazyVStack` 会分几批物化行，文档高自己就会跳，那个读数分不清
    /// 「入口挤了正文」与「又物化了几行」。尾随带是**布局给的事实**：入口若只在出现时才补
    /// inset（条件式），贴底读数就会是 12 + 1。
    static func reservedBandViolations(measured: CGFloat, expected: CGFloat) -> [String] {
        // ±2pt：`LazyVStack` 对相邻行的位置有半行以内的估值误差（与 §3.34 的 28.5pt 同源，量级小得多）。
        guard abs(measured - expected) <= 2 else {
            return ["贴底时尾随带 \(measured)pt ≠ 预留带 \(expected)pt ⇒ 正文底部没有给入口留位"]
        }
        return []
    }

    /// ⑥ 与吸顶条共存：两者都在场、且不重叠。
    static func coexistViolations(stickyHeight: CGFloat,
                                  stickyFrame: CGRect,
                                  buttonHeight: CGFloat,
                                  buttonFrame: CGRect) -> [String] {
        var issues: [String] = []
        if stickyHeight <= 0.5 { issues.append("上翻时吸顶条没出现（高 \(stickyHeight)pt）") }
        if abs(stickyHeight - AgentStickyQuestion.barHeight) > 0.5 {
            issues.append("吸顶条高 \(stickyHeight)pt ≠ 一行 \(AgentStickyQuestion.barHeight)pt")
        }
        if buttonHeight <= 0.5 { issues.append("上翻时入口没出现（高 \(buttonHeight)pt）") }
        // 宿主坐标：y 越大越靠下。
        if buttonFrame.minY < stickyFrame.maxY - 0.5 {
            issues.append("入口上沿 \(buttonFrame.minY)pt 高于吸顶条下沿 \(stickyFrame.maxY)pt ⇒ 两者重叠")
        }
        return issues
    }

    // MARK: - ① 初始贴底 ⇒ 高 0 ／ ② 上翻 100pt ⇒ 22pt、间距 12pt ／ ④ 再上翻 ⇒ 再出现

    @MainActor
    func testAppearsOnScrollUpAndGoesAwayAtTheBottom() async {
        let page = Page(messages: Self.messages())
        defer { page.live.window.contentView = nil }
        await page.settleContent()

        // ① 初始（挂载即贴底）。
        let initial = read(page)
        print("🧪 ① 初始：距底 \(initial.distanceToBottom)pt / 入口高 \(initial.buttonHeight)pt"
              + " / 文档高 \(initial.documentHeight)pt / 视口 \(initial.viewportFrame.height)pt")
        let initialIssues = Self.hiddenAndPinnedViolations(height: initial.buttonHeight,
                                                           distanceToBottom: initial.distanceToBottom)
        print("🧪 ① 判定：" + (initialIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + initialIssues.joined(separator: "；")))
        XCTAssertTrue(initialIssues.isEmpty, initialIssues.joined(separator: "；"))

        // 反例①：贴底却仍挂着入口 ⇒ 同一套判据必须报红。
        let badInitial = Self.hiddenAndPinnedViolations(height: 22, distanceToBottom: 0)
        print("🧪 反例①（贴底仍挂 22pt）：" + (badInitial.isEmpty ? "假绿 ❌" : "判红 ✅ — \(badInitial[0])"))
        XCTAssertFalse(badInitial.isEmpty, "贴底仍挂着入口判据还绿 ⇒ 判据没有牙齿")

        // ② 上翻 100pt。
        await scrollUp(page, by: 100)
        let up = read(page)
        print("🧪 ② 上翻 100pt：距底 \(up.distanceToBottom)pt / 入口高 \(up.buttonHeight)pt"
              + " / 入口 frame \(NSStringFromRect(up.buttonFrame))"
              + " / 视口底 \(up.viewportFrame.maxY)pt / 入口底 \(up.buttonFrame.maxY)pt"
              + " / 间距 \(up.viewportFrame.maxY - up.buttonFrame.maxY)pt"
              + " / 输入区上沿 \(up.composerTop.map { String(format: "%.1f", $0) } ?? "nil")")
        XCTAssertGreaterThan(up.distanceToBottom, AgentJumpToBottom.appearDistance,
                             "上翻 100pt 后距底只有 \(up.distanceToBottom)pt ⇒ 没滚出去，判据测错了场景")
        let upIssues = Self.appearViolations(height: up.buttonHeight,
                                             buttonBottom: up.buttonFrame.maxY,
                                             viewportBottom: up.viewportFrame.maxY)
        print("🧪 ② 判定：" + (upIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + upIssues.joined(separator: "；")))
        XCTAssertTrue(upIssues.isEmpty, upIssues.joined(separator: "；"))

        // 反例②a：入口不出现；反例②b：压到输入区上去（间距 0）。
        let missing = Self.appearViolations(height: 0, buttonBottom: 0, viewportBottom: 620)
        print("🧪 反例②a（入口不出现）：" + (missing.isEmpty ? "假绿 ❌" : "判红 ✅ — \(missing[0])"))
        XCTAssertFalse(missing.isEmpty, "入口不出现判据仍绿 ⇒ 没有牙齿")
        let glued = Self.appearViolations(height: 22,
                                          buttonBottom: up.viewportFrame.maxY,
                                          viewportBottom: up.viewportFrame.maxY)
        print("🧪 反例②b（入口贴着底边、间距 0）：" + (glued.isEmpty ? "假绿 ❌" : "判红 ✅ — \(glued[0])"))
        XCTAssertFalse(glued.isEmpty, "间距 0 判据仍绿 ⇒ 没有牙齿")

        // ④ 先回到底部（入口消失），再上翻 ⇒ 必须**再出现**（不是一次性）。
        await scroll(page, toOffsetFromTop: .greatestFiniteMagnitude)
        let back = read(page)
        print("🧪 ④a 回到底部：距底 \(back.distanceToBottom)pt / 入口高 \(back.buttonHeight)pt")
        XCTAssertLessThanOrEqual(back.buttonHeight, 0.5,
                                 "回到底部后入口仍高 \(back.buttonHeight)pt ⇒ 该隐没隐")
        await scrollUp(page, by: 120)
        let again = read(page)
        print("🧪 ④b 再上翻 120pt：距底 \(again.distanceToBottom)pt / 入口高 \(again.buttonHeight)pt")
        let againIssues = Self.appearViolations(height: again.buttonHeight,
                                                buttonBottom: again.buttonFrame.maxY,
                                                viewportBottom: again.viewportFrame.maxY)
        print("🧪 ④ 判定：" + (againIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + againIssues.joined(separator: "；")))
        XCTAssertTrue(againIssues.isEmpty, againIssues.joined(separator: "；"))
    }

    // MARK: - ③ 点一下 ⇒ 距底 0、高 0、后续 5 次追加仍贴底

    @MainActor
    func testClickingReturnsToBottomAndRestoresFollowing() async {
        let page = Page(messages: Self.messages())
        defer { page.live.window.contentView = nil }

        await scrollUp(page, by: 200)
        let before = read(page)
        print("🧪 ③ 上翻 200pt：距底 \(before.distanceToBottom)pt / 入口高 \(before.buttonHeight)pt"
              + " / 文档高 \(before.documentHeight)pt / 视口 \(before.viewportFrame.height)pt")
        XCTAssertGreaterThan(before.buttonHeight, 0.5, "上翻 200pt 后没有入口 ⇒ 这一条判的是空")

        guard let button = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentJumpToBottomClickButton.self, in: page.live.hosting).first else {
            return XCTFail("没找到入口的点击面（NSButton）⇒ 判据点不到它")
        }
        button.performClick(nil)          // 真点击路径
        await page.live.pumpAsync(seconds: 0.5)

        let after = read(page)
        print("🧪 ③ 点一下：距底 \(before.distanceToBottom)pt → \(after.distanceToBottom)pt"
              + " / 入口高 \(before.buttonHeight)pt → \(after.buttonHeight)pt")
        let clickIssues = Self.hiddenAndPinnedViolations(height: after.buttonHeight,
                                                         distanceToBottom: after.distanceToBottom)
        print("🧪 ③ 判定（点完即贴底 + 入口隐去）："
              + (clickIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + clickIssues.joined(separator: "；")))
        XCTAssertTrue(clickIssues.isEmpty, clickIssues.joined(separator: "；"))

        // 跟随真的恢复了：连续追加 5 次，每一次都必须仍贴底。
        var distances: [CGFloat] = []
        for index in 0..<5 {
            await page.append("\n追加第 \(index + 1) 段：这一行会继续把内容往下撑。")
            distances.append(read(page).distanceToBottom)
        }
        print("🧪 ③ 后续 5 次追加的距底："
              + distances.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " pt")
        let followIssues = Self.followRestoredViolations(distances)
        print("🧪 ③ 判定（跟随已恢复）："
              + (followIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + followIssues.joined(separator: "；")))
        XCTAssertTrue(followIssues.isEmpty, followIssues.joined(separator: "；"))

        // 反例③：只滚一次、不恢复跟随（距底 12pt 那种）⇒ 同一套判据必须报红。
        let stale = Self.followRestoredViolations([0, 0, 12, 24, 36])
        print("🧪 反例③（只滚到底、跟随没恢复）：" + (stale.isEmpty ? "假绿 ❌" : "判红 ✅ — \(stale[0])"))
        XCTAssertFalse(stale.isEmpty, "跟随没恢复判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ⑤ 不遮正文（最后一行的底边在入口之上，且正文尾部恒留了入口的位置）

    @MainActor
    func testTheBarNeverCoversTheLastLine() async {
        let page = Page(messages: Self.messages())
        defer { page.live.window.contentView = nil }

        // ⑤b **预留带恒在**：一挂载就贴底，此刻「最后一行底边 → 对话区底边」= 预留 26 + 块间距 12
        // = 38pt（入口不显示，可它占的那条带一直在）。条件式 inset（入口出现时才补）会是 12pt。
        await page.settleContent()
        let initial = read(page)
        let expectedBand = AgentJumpToBottom.contentInset + AgentJumpToBottom.bottomGap
        print("🧪 ⑤ 贴底时尾随带（最后一行底边 → 对话区底边）= \(initial.trailingBand)pt"
              + " / 期望 \(expectedBand)pt（预留 \(AgentJumpToBottom.contentInset) + 块间距 "
              + "\(AgentJumpToBottom.bottomGap)）"
              + " / 最后一行底边 \(String(format: "%.1f", initial.tailFrame.maxY))pt"
              + " / 视口底 \(String(format: "%.1f", initial.viewportFrame.maxY))pt")
        let band = Self.reservedBandViolations(measured: initial.trailingBand, expected: expectedBand)
        print("🧪 ⑤ 判定（正文底部给入口留了位）："
              + (band.isEmpty ? "绿 ✅" : "红 ❌ — " + band.joined(separator: "；")))
        XCTAssertTrue(band.isEmpty, band.joined(separator: "；"))

        // 反例⑤b：条件式 inset（只在入口出现时才补 26pt）⇒ 尾随带 12pt ⇒ 判红。
        let conditional = Self.reservedBandViolations(measured: AgentJumpToBottom.bottomGap,
                                                      expected: expectedBand)
        print("🧪 反例⑤b（只在入口出现时才补 inset）："
              + (conditional.isEmpty ? "假绿 ❌" : "判红 ✅ — \(conditional[0])"))
        XCTAssertFalse(conditional.isEmpty, "条件式 inset 判据仍绿 ⇒ 判据没有牙齿")

        // ⑤a **不压最后一行**：距底 45pt（刚过出现门槛）时，最后一行还在视口下沿附近，
        // 入口也在场 —— 两者不许相交。
        await scrollUp(page, by: 45)
        let shown = read(page)
        XCTAssertGreaterThan(shown.buttonHeight, 0.5, "距底 45pt 时入口没出现 ⇒ 这一条判的是空")
        let lastLineBottom = shown.tailFrame.minY
        print("🧪 ⑤ 入口 frame \(NSStringFromRect(shown.buttonFrame))"
              + " / 最后一行底边 \(String(format: "%.1f", lastLineBottom))pt"
              + " / 入口底边 \(String(format: "%.1f", shown.buttonFrame.maxY))pt"
              + " / 留白 \(String(format: "%.1f", lastLineBottom - shown.buttonFrame.maxY))pt")
        let occlusion = Self.occlusionViolations(buttonBottom: shown.buttonFrame.maxY,
                                                 lastLineBottom: lastLineBottom)
        print("🧪 ⑤ 判定（不压最后一行）：" + (occlusion.isEmpty ? "绿 ✅" : "红 ❌ — " + occlusion.joined(separator: "；")))
        XCTAssertTrue(occlusion.isEmpty, occlusion.joined(separator: "；"))

        // 反例⑤a：把入口往下挪 20pt（= 没预留 inset 的形态）⇒ 必须压到正文。
        let covered = Self.occlusionViolations(buttonBottom: shown.buttonFrame.maxY + 20,
                                               lastLineBottom: lastLineBottom)
        print("🧪 反例⑤a（入口下移 20pt）：" + (covered.isEmpty ? "假绿 ❌" : "判红 ✅ — \(covered[0])"))
        XCTAssertFalse(covered.isEmpty, "入口压住正文判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ⑥ 与吸顶条共存

    @MainActor
    func testCoexistsWithTheStickyQuestionBar() async {
        let page = Page(messages: Self.messages())
        defer { page.live.window.contentView = nil }

        await scrollUp(page, by: 100)
        let reading = read(page)
        print("🧪 ⑥ 吸顶条高 \(reading.stickyHeight)pt frame \(NSStringFromRect(reading.stickyFrame))"
              + " / 入口高 \(reading.buttonHeight)pt frame \(NSStringFromRect(reading.buttonFrame))"
              + " / 视口 \(NSStringFromRect(reading.viewportFrame))")
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
