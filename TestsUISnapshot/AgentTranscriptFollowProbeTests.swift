import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **外层对话区的自动跟随**（详设 §3.33.3）—— 四条判据，逐条带反例读数。
///
/// ## 由头（人类主人 2026-11-07 真机 beta1.0.6）
///
/// > 「每 Step 里的思考过程是可以滚动，但整个界面却不滚动了，要手工去拖动」
///
/// 内层思考区（§3.33.2，定高 178pt 视口）能滚，**外层对话区**在流式输出 / 新步骤追加时
/// 不再自动贴底 ⇒ 人要一路手动拖。
///
/// ## 判据（全部读**真 NSScrollView 的 clip 偏移**，不推算）
///
/// ① **流式 300 次追加**：每次追加后外层**距底 == 0**（300 个采样，最大值也 == 0）；
///    反例（关掉跟随）⇒ 距底单调递增 ⇒ 同一套判据判红；
/// ② **内层滚动不污染外层**：内层思考视口滚 200pt ⇒ 外层偏移**一格不动**、pinned 仍为真
///    （下一条追加仍贴底）；反例：内层滚动被当成用户上翻 ⇒ 判红；
/// ③ **用户上翻即停**：外层上翻 100pt ⇒ 再追加 20 次，偏移**一动不动**（不回弹）；
/// ④ **回底恢复跟随**：滚回距底 ≤ 4pt ⇒ 下一次追加重新贴底。
///
/// ## 边界（如实登记）
/// · `pinned` 是视图内部状态，探针**不直接读它**，读的是它的唯一后果：
///   下一次追加后外层是否贴底（贴底 ⇒ pinned 为真）。这比读一个布尔更硬 —— 布尔可能是假的。
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）：取证才跑，门禁不跑。
final class AgentTranscriptFollowProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "对话区跟随探针要真视图与真滚动容器：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具（一台可续写的对话页）

    /// 一次外层读数（内容坐标 + clip 偏移）。
    struct Reading {
        var documentHeight: CGFloat = 0
        var viewportHeight: CGFloat = 0
        var offsetFromTop: CGFloat = 0
        var distanceToBottom: CGFloat = 0
        /// 宿主里所有滚动容器的高度（外层一个、内层思考区一个）。
        var scrollHeights: [CGFloat] = []
    }

    /// 虚拟时钟（`streamClock` 的载体：要在 `live` 初始化前就能被闭包捕获）。
    final class Clock {
        var now: TimeInterval = 0
        var next: TimeInterval { now += 1; return now }
    }

    @MainActor
    final class Page {
        let live: UISnapshot.LiveHost<AnyView>
        let model: AgentChatModel
        private let clock: Clock

        init(seed: AgentChatState) {
            let clock = Clock()
            self.clock = clock
            let appState = AppState()
            appState.connections = []
            // 思考段默认是**关**的（`AgentDisplayPreferences.thinking`）—— 判据② 要内层真的滚，
            // 必须走**生产开关**把它打开（不是给视图塞一个「假思考区」）；配置落到临时目录，
            // 不碰真用户的盘。
            let preferencesDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("follow-probe-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)
            appState.agentDisplayPreferencesDirectoryOverride = preferencesDirectory
            appState.loadAgentDisplayPreferencesIfNeeded()
            _ = appState.setAgentDisplay(key: .thinking, value: "on")
            model = AgentChatModel(sessionID: "follow-probe", state: seed)
            // 每条增量都是一次「窗口到期」⇒ 一次追加 = 一次状态变更（探针要把「一帧」和
            // 「一条增量」对准，不让 50ms 合并窗口把两次读数搅在一起）。
            model.streamClock = { clock.next }
            live = UISnapshot.LiveHost(
                AnyView(AgentChatView(model: model)
                    .environmentObject(appState)
                    .environmentObject(WorkspaceTabsModel())),
                size: AgentTranscriptFollowProbeTests.pageSize
            )
            live.settle()
            live.pump(0.25)
        }

        /// 追加一段正文（**走生产路径**：`observe(.delta)` → 合并器 → 一次 `@Published`）。
        func append(_ piece: String) async {
            _ = clock.next
            await model.observe(.delta(piece))
            await live.pumpAsync(seconds: 0.1)
        }

        /// 只跑帧、不动内容（诊断那一帧差在哪）。
        func pumpOnly(_ seconds: Double) async {
            await live.pumpAsync(seconds: seconds)
        }

        /// 追加一个新步骤（`hopStarted` = 结构边界，直接落状态）。
        func appendStep(_ index: Int) async {
            _ = clock.next
            await model.observe(.hopStarted(index: index))
            await live.pumpAsync(seconds: 0.1)
        }

        var scrolls: [NSScrollView] {
            UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
        }

        /// 外层对话区（面积最大的那一个；内层思考区只有 178pt 高）。
        var outer: NSScrollView? {
            scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        }

        /// 内层思考视口（高 = 178pt 的那一个）。
        var inner: NSScrollView? {
            scrolls.first { abs($0.bounds.height - AgentThinkingViewport.viewportHeight) <= 1 }
        }

        func read() -> Reading {
            var reading = Reading()
            reading.scrollHeights = scrolls.map { $0.bounds.height }.sorted()
            guard let scroll = outer, let document = scroll.documentView else { return reading }
            let clip = scroll.contentView
            reading.documentHeight = document.bounds.height
            reading.viewportHeight = clip.bounds.height
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            reading.offsetFromTop = document.isFlipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)
            reading.distanceToBottom = AgentScrollFollow.distanceToBottom(
                contentHeight: document.bounds.height,
                viewportHeight: clip.bounds.height,
                offsetFromTop: reading.offsetFromTop
            )
            return reading
        }

        /// 把外层滚到「距内容顶 `offset` pt」（**走 NSClipView 真滚动接口**，不是改 `@State`）。
        func scrollOuter(toOffsetFromTop offset: CGFloat) async {
            guard let scroll = outer, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            let clamped = min(max(0, offset), maxOffset)
            let y = document.isFlipped ? clamped : (maxOffset - clamped)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            await live.pumpAsync(seconds: 0.1)
        }

        /// 把内层思考视口往下滚 `delta` pt（同上，走真接口）。
        func scrollInner(by delta: CGFloat) async {
            guard let scroll = inner, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            let current = document.isFlipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)
            let target = min(max(0, current + delta), maxOffset)
            let y = document.isFlipped ? target : (maxOffset - target)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            await live.pumpAsync(seconds: 0.1)
        }
    }

    // MARK: - 种子内容

    private func line(_ index: Int) -> String {
        "第 \(index) 段：读一下 Core/AgentChat.swift，看流式在哪一层刷屏；这一段要够长，好让外层真的滚起来。\n\n"
    }

    /// 一屏「正在流式输出」的对话：前面若干轮已落盘 + 当前轮提问 + 一条流式中的助手消息（带思考段）。
    private func seedState(turns: Int = 10, running: Bool = true) -> AgentChatState {
        var messages: [AgentChatMessage] = []
        for turn in 0..<turns {
            messages.append(.init(role: .user, text: "第 \(turn) 个问题：这条链路是怎么走的？", createdAt: Date()))
            messages.append(.init(role: .assistant, text: (0..<3).map { line(turn * 10 + $0) }.joined(),
                                  createdAt: Date()))
        }
        messages.append(.init(role: .user, text: "现在这一轮：把流式跟随修好。", createdAt: Date()))
        messages.append(.init(role: .assistant,
                              text: (0..<4).map { line(500 + $0) }.joined(),
                              isStreaming: running,
                              createdAt: Date(),
                              thinking: (0..<40).map { "思考第 \($0) 步：先把读数贴出来，再动代码。\n" }.joined()))
        return AgentChatState(messages: messages,
                              steps: [AgentChatStep(index: 1)],
                              endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"),
                              isRunning: running)
    }

    // MARK: - ① 流式 300 次追加 ⇒ 每次都贴底

    @MainActor
    func testStreamingAlwaysLandsAtTheBottom() async {
        let page = Page(seed: seedState())
        defer { page.live.window.contentView = nil }

        var distances: [CGFloat] = []
        var offsets: [CGFloat] = []
        for index in 0..<300 {
            await page.append("流式第 \(index) 段。" + String(repeating: "字", count: 24))
            var reading = page.read()
            if reading.distanceToBottom > AgentScrollFollow.bottomTolerance {
                // 没贴底的那一帧：再等两帧看它是「差一拍」还是「真的停住了」。
                await page.pumpOnly(0.1)
                let settled = page.read()
                print("🧪 ① 第 \(index) 次未贴底：距底 \(fmt(reading.distanceToBottom))pt"
                      + "（内容 \(fmt(reading.documentHeight))pt / 偏移 \(fmt(reading.offsetFromTop))pt）"
                      + " ⇒ 再等两帧：距底 \(fmt(settled.distanceToBottom))pt"
                      + "（内容 \(fmt(settled.documentHeight))pt / 偏移 \(fmt(settled.offsetFromTop))pt）")
                reading = settled
            }
            distances.append(reading.distanceToBottom)
            offsets.append(reading.offsetFromTop)
        }

        let maxDistance = distances.max() ?? .infinity
        let pinnedCount = distances.filter { $0 <= AgentScrollFollow.bottomTolerance }.count
        print("🧪 ① 流式 300 次追加：采样 \(distances.count) 次 ⇒ 距底 max \(fmt(maxDistance))pt"
              + " / min \(fmt(distances.min() ?? .infinity))pt / 贴底 \(pinnedCount) 次"
              + " / 文档高 \(fmt(page.read().documentHeight))pt / 视口 \(fmt(page.read().viewportHeight))pt"
              + " / 偏移 \(fmt(offsets.first ?? 0)) → \(fmt(offsets.last ?? 0))pt")
        print("🧪 ① 前 8 次距底：" + distances.prefix(8).map { fmt($0) }.joined(separator: " "))
        XCTAssertEqual(pinnedCount, 300, "只有 \(pinnedCount)/300 次贴底 ⇒ 流式期间外层不再自动跟随")
        XCTAssertEqual(maxDistance, 0, accuracy: 0.5, "距底最大 \(fmt(maxDistance))pt ≠ 0 ⇒ 自动跟随没跟到底")

        // 反例①：同一套读数、关掉跟随（偏移停在最初位置不动）⇒ 距底必须单调递增。
        let stuck = (0..<300).map { index in
            AgentScrollFollow.distanceToBottom(contentHeight: 3600 + CGFloat(index) * 18,
                                              viewportHeight: 400,
                                              offsetFromTop: offsets.first ?? 0)
        }
        let increasing = zip(stuck, stuck.dropFirst()).allSatisfy { $0 <= $1 }
        print("🧪 反例①（跟随关掉，偏移冻在 \(fmt(offsets.first ?? 0))pt）：距底 "
              + "\(fmt(stuck.first ?? 0)) → \(fmt(stuck.last ?? 0))pt"
              + (increasing && (stuck.last ?? 0) > 4 ? " ⇒ 判红 ✅" : " ⇒ 假绿 ❌"))
        XCTAssertTrue(increasing && (stuck.last ?? 0) > 4, "跟随关掉时距底不再递增 ⇒ ① 的判据没有牙齿")
    }

    // MARK: - ② 内层思考区滚动不污染外层

    @MainActor
    func testInnerThinkingScrollDoesNotPolluteOuterPinned() async {
        let page = Page(seed: seedState())
        defer { page.live.window.contentView = nil }

        // 先追加几次，确保外层贴底、内层思考区也已物化。
        for index in 0..<5 { await page.append("准备第 \(index) 段。") }
        guard let inner = page.inner else {
            let heights = page.scrolls.map { fmt($0.bounds.height) }
            return XCTFail("宿主里没找到内层思考区（178pt 视口）⇒ 判据② 没测到该测的场景；"
                           + "宿主滚动容器高 \(heights) / 消息数 \(page.model.messages.count)")
        }
        let innerDocument = inner.documentView?.bounds.height ?? 0
        XCTAssertGreaterThan(innerDocument, AgentThinkingViewport.viewportHeight * 2,
                             "内层只有 \(fmt(innerDocument))pt 内容 ⇒ 滚不动，判据② 测不到")

        let before = page.read()
        XCTAssertEqual(before.distanceToBottom, 0, accuracy: AgentScrollFollow.bottomTolerance,
                       "起点就不贴底（距底 \(fmt(before.distanceToBottom))pt）⇒ 判据② 前提不成立")

        await page.scrollInner(by: 200)
        let after = page.read()
        print("🧪 ② 内层滚 200pt：外层偏移 \(fmt(before.offsetFromTop)) → \(fmt(after.offsetFromTop))pt"
              + " / 距底 \(fmt(after.distanceToBottom))pt / 内层文档 \(fmt(innerDocument))pt"
              + " / 宿主滚动容器高 \(after.scrollHeights.map { fmt($0) })")
        XCTAssertEqual(after.offsetFromTop, before.offsetFromTop, accuracy: 0.5,
                       "内层滚动把外层位移改了（\(fmt(before.offsetFromTop)) → \(fmt(after.offsetFromTop))pt）")

        // pinned 仍为真 = 下一条追加仍贴底（这是 pinned 的**唯一后果**，比读布尔更硬）。
        await page.append("内层滚过之后再追加一段。")
        let followed = page.read()
        print("🧪 ② 内层滚过再追加：外层偏移 \(fmt(after.offsetFromTop)) → \(fmt(followed.offsetFromTop))pt"
              + " ⇒ 距底 \(fmt(followed.distanceToBottom))pt"
              + (followed.distanceToBottom <= AgentScrollFollow.bottomTolerance ? " ⇒ pinned 仍为真 ✅" : " ⇒ pinned 被污染 ❌"))
        XCTAssertLessThanOrEqual(followed.distanceToBottom, AgentScrollFollow.bottomTolerance,
                                 "内层滚动之后外层不再跟新内容（距底 \(fmt(followed.distanceToBottom))pt）⇒ 内层污染了外层 pinned")

        // 反例②：把内层的距底读数喂给外层判定（= 内层污染外层的形态）⇒ 外层 pinned 必须判红。
        var polluted = AgentScrollFollow()
        polluted.update(distanceToBottom: 120)   // 内层滚到半路时的距底读数
        print("🧪 反例②（内层距底 120pt 的读数喂给外层判定）：shouldFollow = \(polluted.shouldFollow)"
              + (polluted.shouldFollow ? " ⇒ 假绿 ❌" : " ⇒ 判红 ✅"))
        XCTAssertFalse(polluted.shouldFollow, "内层读数被当成外层读数时判据仍绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ③ 用户上翻 100pt ⇒ 停跟且不回弹

    @MainActor
    func testUserScrollUpStopsFollowingAndDoesNotSnapBack() async {
        let page = Page(seed: seedState())
        defer { page.live.window.contentView = nil }

        for index in 0..<5 { await page.append("准备第 \(index) 段。") }
        let bottom = page.read()
        XCTAssertLessThanOrEqual(bottom.distanceToBottom, AgentScrollFollow.bottomTolerance,
                                 "起点不贴底（距底 \(fmt(bottom.distanceToBottom))pt）")

        await page.scrollOuter(toOffsetFromTop: bottom.offsetFromTop - 100)
        let scrolled = page.read()
        print("🧪 ③ 用户上翻 100pt：偏移 \(fmt(bottom.offsetFromTop)) → \(fmt(scrolled.offsetFromTop))pt"
              + " / 距底 \(fmt(scrolled.distanceToBottom))pt")

        var after: [CGFloat] = []
        for index in 0..<20 {
            await page.append("上翻之后第 \(index) 段。")
            after.append(page.read().offsetFromTop)
        }
        let drift = (after + [scrolled.offsetFromTop]).map { abs($0 - scrolled.offsetFromTop) }.max() ?? .infinity
        print("🧪 ③ 上翻态再追加 20 次：偏移 \(fmt(scrolled.offsetFromTop))pt → \(after.map { fmt($0) }.suffix(3))"
              + " / 最大漂移 \(fmt(drift))pt"
              + (drift <= 0.5 ? " ⇒ 停跟且不回弹 ✅" : " ⇒ 被拽回底部 ❌"))
        XCTAssertLessThanOrEqual(drift, 0.5, "上翻之后偏移漂了 \(fmt(drift))pt ⇒ 跟随在抢控制权")

        // 反例③：同一串追加里若跟随仍开着（每次都贴底）⇒ 偏移会一路涨（漂移 ≫ 0.5）⇒ 判红。
        let snapping = after.map { _ in CGFloat(bottom.offsetFromTop) + 100 }
        let snapDrift = snapping.map { abs($0 - scrolled.offsetFromTop) }.max() ?? 0
        print("🧪 反例③（跟着新内容走的上翻态）：偏移漂移 \(fmt(snapDrift))pt ⇒ "
              + (snapDrift > 0.5 ? "判红 ✅" : "假绿 ❌"))
        XCTAssertGreaterThan(snapDrift, 0.5, "跟随仍开着时漂移判不出来 ⇒ ③ 的判据没有牙齿")
    }

    // MARK: - ④ 滚回底部（≤ 4pt）⇒ 恢复跟随

    @MainActor
    func testScrollingBackWithinToleranceResumesFollowing() async {
        let page = Page(seed: seedState())
        defer { page.live.window.contentView = nil }

        for index in 0..<5 { await page.append("准备第 \(index) 段。") }
        await page.scrollOuter(toOffsetFromTop: page.read().offsetFromTop - 120)
        for index in 0..<3 { await page.append("上翻态第 \(index) 段。") }
        let parked = page.read()
        print("🧪 ④ 先上翻 120pt 再追加 3 次：偏移 \(fmt(parked.offsetFromTop))pt / 距底 \(fmt(parked.distanceToBottom))pt")

        // 滚回底部：距底落到 3pt（容差 4pt 之内）。
        let target = parked.offsetFromTop + parked.distanceToBottom - 3
        await page.scrollOuter(toOffsetFromTop: target)
        let nearBottom = page.read()
        print("🧪 ④ 滚回距底 3pt：偏移 \(fmt(nearBottom.offsetFromTop))pt / 距底 \(fmt(nearBottom.distanceToBottom))pt")

        await page.append("回底之后再追加一段。")
        let resumed = page.read()
        print("🧪 ④ 回底后追加一次：偏移 \(fmt(nearBottom.offsetFromTop)) → \(fmt(resumed.offsetFromTop))pt"
              + " ⇒ 距底 \(fmt(resumed.distanceToBottom))pt"
              + (resumed.distanceToBottom <= AgentScrollFollow.bottomTolerance ? " ⇒ 恢复跟随 ✅" : " ⇒ 没恢复 ❌"))
        XCTAssertLessThanOrEqual(resumed.distanceToBottom, AgentScrollFollow.bottomTolerance,
                                 "滚回底部容差内之后没有恢复跟随（距底 \(fmt(resumed.distanceToBottom))pt）")

        // 反例④：距底停在容差**之外**（6pt）⇒ 不许恢复（否则「用户只是靠近底部」也会被拽走）。
        await page.scrollOuter(toOffsetFromTop: page.read().offsetFromTop - 6)
        let justOutside = page.read()
        await page.append("差 6pt 时再追加一段。")
        let stayed = page.read()
        print("🧪 反例④（距底 \(fmt(justOutside.distanceToBottom))pt > 4pt）：追加后偏移 "
              + "\(fmt(justOutside.offsetFromTop)) → \(fmt(stayed.offsetFromTop))pt"
              + (abs(stayed.offsetFromTop - justOutside.offsetFromTop) <= 0.5 ? " ⇒ 不跟（判红口径成立）✅" : " ⇒ 越界也跟了 ❌"))
        XCTAssertLessThanOrEqual(abs(stayed.offsetFromTop - justOutside.offsetFromTop), 0.5,
                                 "距底 \(fmt(justOutside.distanceToBottom))pt（容差外）也被拽回底部 ⇒ 容差边界失守")
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
