import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **「一轮一个思考区」的端上判据**（详设 §3.33.4，900×620 真视图）。
///
/// ## 主人原话（beta1.0.7 真机）
///
/// > 「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」
///
/// 契约（§3.33.4）：一轮 = 一个思考区；区内按步分**轻段**（一行发丝 + 极小字「第 N 步」）；
/// 整体定高 200pt + 内部滚动；折 / 展**一次作用于整轮**；工具块按调用各自成块，不并进思考区。
///
/// ## 五条判据（每条都带反例读数，反例与真读数走**同一套**判定函数）
///
/// ① 5 步、每步一段思考 ⇒ 页面上 `AgentThinkingZone` 实例数 == **1**（反例：改前按 step
///    分块 ⇒ **5** ⇒ 判红）；
/// ② 该区整块高 == **200pt**（内容再多也不变），内容视口 == **178pt** 且文档高 > 视口
///    （内部滚动可达末尾：滚到底后距底 0pt）；
/// ③ 顺序保真：区里 5 个段锚按文档坐标（上→下）排序 == **[1,2,3,4,5]**，且各段文本首句就是
///    「第 N 步」（反例：倒序/打乱 ⇒ 序列 ≠ 1…5 ⇒ 判红）；
/// ④ 折一次 ⇒ 整轮变 **20pt 一行**；再展开 ⇒ 回到 **200pt**（反例：按 step 分块时点一次只折
///    其中一块 ⇒ 页面上仍有 5 个区 / 折完总高 100pt ⇒ 判红）；
/// ⑤ 工具块仍为 **5 个**、各自 **20pt** 摘要，且思考区文本里一条工具行都没有（不被吞并）。
///
/// ## 读数从哪来（不是推算）
/// · 实例数 / 行高 = 真宿主视图树里的**锚视图**（`AgentThinkingZoneMarker` /
///   `AgentThinkingSegmentMarker` / `AgentToolBlockMarker`，零行为）。SwiftUI `Text` 在这台
///   宿主里不落 `NSTextField`（本仓已登记的边界），数折头就得靠这类显式记号；
/// · 内部滚动 = 那一格 `NSScrollView` 的 `documentView` 高与 clip 高。
///
/// ## 边界（如实登记）
/// · 折叠动作是 `onTapGesture`（离屏宿主点不动）⇒ ④ 用**同一个回调**的入口（`manual`）挂起来：
///   生产里点抬头调 `onToggle`，探针里把 `onToggle` 的结论直接喂回去 —— 高度判定读的是同一份
///   渲染代码；
/// · 探针默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 取证才跑，门禁不跑。
final class AgentTurnThinkingZoneProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    static let stepCount = 5

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "一轮一个思考区要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// 第 `step` 步的过程独白（≈ 3 行：五段一定撑爆 178pt 的视口）。
    static func stepText(_ step: Int) -> String {
        "第 \(step) 步：我先读一下 Core/File\(step).swift 和 Core/AgentChat.swift，"
            + "看看第 \(step) 段思考落在哪一层、由谁归并，再决定改哪里。"
            + "这一步的结论是：段边界只留发丝，不留第二层折叠头。"
    }

    static func toolLine(_ step: Int) -> String {
        "▸ read_file · Core/File\(step).swift  ✓ · 0.5s"
    }

    /// 真机那一轮：五步过程（每步后面跟一次工具调用）+ 末条结论。
    static func messages(steps: Int = stepCount, toolsEveryStep: Bool = true) -> [AgentChatMessage] {
        var messages: [AgentChatMessage] = [.init(role: .user, text: "多个步骤的思考应该合一起，现在分成一块一块的。")]
        for step in 1...steps {
            messages.append(.init(role: .assistant, text: stepText(step)))
            if toolsEveryStep || step == 1 {
                messages.append(.init(role: .tool, text: toolLine(step)))
            }
        }
        messages.append(.init(role: .assistant, text: "改完了：整轮一个思考区，工具块各自还在。"))
        return messages
    }

    /// **改前形态**的块清单：一条助手消息一块，末条结论若只有结论就不产块 ——
    /// 这正是 `AgentChatView` 改前在逐条消息的 `ForEach` 里调 `thinkingZone(message:)` 的语义
    /// （每块只管自己那一条消息的 `thinkingParts`）。
    static func legacyBlocks(_ messages: [AgentChatMessage]) -> [String] {
        let finals = AgentChatTurnShape.finalAssistantIndices(in: messages)
        return messages.enumerated().compactMap { index, message in
            AgentTurnThinking.segmentText(of: message,
                                          isFinalAssistant: finals.contains(index),
                                          includeReasoning: false)
        }
    }

    struct LegacyPerStepThinking: View {
        let texts: [String]
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                    AgentThinkingZone(text: text,
                                      phase: .finished,
                                      manual: nil,
                                      steps: 1,
                                      elapsedSeconds: 18.4,
                                      highlight: nil,
                                      language: .simplifiedChinese) { _ in }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 折 / 展的小机器：`manual` 与 `onToggle` 同一条路（生产里点抬头调的就是它）。
    @MainActor
    final class FoldHarness: ObservableObject {
        @Published var segments: [AgentThinkingSegment]
        @Published var phase: AgentThinkingPhase
        @Published var manual: Bool?

        init(segments: [AgentThinkingSegment], phase: AgentThinkingPhase = .finished, manual: Bool? = nil) {
            self.segments = segments
            self.phase = phase
            self.manual = manual
        }
    }

    struct FoldHarnessView: View {
        @ObservedObject var model: FoldHarness
        var body: some View {
            AgentThinkingZone(segments: model.segments,
                              phase: model.phase,
                              manual: model.manual,
                              steps: model.segments.count,
                              elapsedSeconds: 18.4,
                              highlight: nil,
                              language: .simplifiedChinese) { expanded in
                // 与生产同一条路：点抬头 = 改这一轮的手动态（**整轮**，不是某一段）。
                model.manual = expanded
            }
        }
    }

    // MARK: - 判据函数（真读数与反例读数共用）

    /// ① 一轮一个区：页面上 `AgentThinkingZone` 实例数必须是 1。
    static func zoneCountViolations(count: Int, expected: Int = 1) -> [String] {
        guard count != expected else { return [] }
        return ["页面上有 \(count) 个思考区（应 \(expected) 个）⇒ 一轮的思考没合并成一个区"]
    }

    /// ② 定高 200pt、视口 178pt、内部可滚。
    static func viewportViolations(height: CGFloat, viewport: CGFloat, document: CGFloat) -> [String] {
        var issues: [String] = []
        if abs(height - AgentThinkingViewport.totalHeight) > 0.5 {
            issues.append("思考区整块高 \(height)pt ≠ 定高 \(AgentThinkingViewport.totalHeight)pt")
        }
        if abs(viewport - AgentThinkingViewport.viewportHeight) > 0.5 {
            issues.append("内容视口高 \(viewport)pt ≠ \(AgentThinkingViewport.viewportHeight)pt")
        }
        if document <= viewport {
            issues.append("文档高 \(document)pt ≤ 视口 \(viewport)pt ⇒ 五段内容根本撑不出内部滚动，判据没测到真场景")
        }
        return issues
    }

    /// ③ 顺序保真：按文档坐标排序的段号必须等于 1…N。
    static func orderViolations(observed: [Int], expected: [Int]) -> [String] {
        guard observed != expected else { return [] }
        return ["段序 \(observed) ≠ 步序 \(expected) ⇒ 读到的顺序与步序不一致"]
    }

    /// ④ 折 / 展作用于整轮：一个区、20pt ↔ 200pt。
    static func foldViolations(count: Int, height: CGFloat, expected: CGFloat, label: String) -> [String] {
        var issues = zoneCountViolations(count: count)
        if abs(height - expected) > 0.5 {
            issues.append("\(label)：整轮高 \(height)pt ≠ \(expected)pt ⇒ 折一次没作用于整轮")
        }
        return issues
    }

    /// ⑤ 工具块：5 个、各 20pt。
    static func toolViolations(count: Int, heights: [CGFloat], expectedCount: Int) -> [String] {
        var issues: [String] = []
        if count != expectedCount {
            issues.append("工具块 \(count) 个 ≠ \(expectedCount) 个 ⇒ 被思考区吞并了")
        }
        let strays = heights.filter { abs($0 - AgentToolBlockView.collapsedHeight) > 0.5 }
        if !strays.isEmpty {
            issues.append("工具块高 \(strays) ≠ 一行 \(AgentToolBlockView.collapsedHeight)pt")
        }
        return issues
    }

    // MARK: - 宿主

    /// 一页真 `AgentChatView`（900×620）。显示开关走独立的临时目录，不碰真用户配置。
    @MainActor
    private func withPage<T>(_ messages: [AgentChatMessage],
                             isRunning: Bool = false,
                             _ body: (UISnapshot.LiveHost<AnyView>) throws -> T) rethrows -> T {
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent("turn-thinking-probe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store) }

        let appState = AppState()
        appState.connections = []
        appState.agentDisplayPreferencesDirectoryOverride = store
        appState.loadAgentDisplayPreferencesIfNeeded()
        let model = AgentChatModel(sessionID: "turn-thinking-probe",
                                   state: AgentChatState(
                                    messages: messages,
                                    steps: (0..<Self.stepCount).map {
                                        AgentChatStep(index: $0 + 1, status: .done, tools: ["read_file"])
                                    },
                                    endpoint: .ready(model: "deepseek-v4-flash",
                                                     endpoint: "api.deepseek.com"),
                                    isRunning: isRunning))
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.2)
        defer { live.window.contentView = nil }
        // **滚回顶部再读数**：运行中的那一页会自动贴底，而 `LazyVStack` 会回收滚出视口的行
        // （实测：贴底时顶部的过程块整块被回收 ⇒ 记号 0 个，判据会误判成「没有区」）。
        // 读「顶部这几行」的判据必须把它们物化出来 —— 这一步只动外层滚动位置，不改任何一行。
        scrollToTop(live)
        return try body(live)
    }

    /// 把外层对话区滚回顶部（`LazyVStack` 只有物化过的行才有真视图）。
    @MainActor
    private func scrollToTop(_ live: UISnapshot.LiveHost<AnyView>) {
        let scrolls = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
        guard let outer = scrolls.max(by: {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }) else { return }
        let flipped = outer.documentView?.isFlipped ?? true
        outer.contentView.scroll(to: NSPoint(x: 0, y: flipped ? 0 : (outer.documentView?.bounds.height ?? 0)))
        outer.reflectScrolledClipView(outer.contentView)
        live.pump(0.15)
    }

    @MainActor
    private func zoneMarkers(_ live: UISnapshot.LiveHost<AnyView>) -> [AgentThinkingZoneMarker] {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentThinkingZoneMarker.self, in: live.hosting)
    }

    @MainActor
    private func toolMarkers(_ live: UISnapshot.LiveHost<AnyView>) -> [AgentToolBlockMarker] {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentToolBlockMarker.self, in: live.hosting)
    }

    /// 思考区里那一格 `NSScrollView`：**最内层**、且包着段锚的那个。
    ///
    /// 为什么要「最内层」：外层对话区也是 `NSScrollView`，它的 `documentView` 子树里照样
    /// 躺着段锚（实测先命中它 ⇒ 读到视口 390.5pt 而不是 178pt）。判据要的是**思考区自己**
    /// 那一格，所以取「它自己有段锚、而它内部的滚动容器都没有段锚」的那一个。
    @MainActor
    private func zoneScroll(_ live: UISnapshot.LiveHost<AnyView>) -> NSScrollView? {
        let hasSegment = { (scroll: NSScrollView) in
            !UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentThinkingSegmentMarker.self, in: scroll).isEmpty
        }
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
            .first { scroll in
                // 注意：`findViews` 会把 `scroll` **自己**也算进去 ⇒ 必须排掉，否则每一条
                // 都「内部还有包着段锚的滚动容器」，永远选不出最内层（实测直接返回 nil）。
                guard hasSegment(scroll) else { return false }
                return !UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: scroll)
                    .filter { $0 !== scroll }
                    .contains(where: hasSegment)
            }
    }

    /// 区里的段号，按**文档坐标上→下**排序（= 读者看到的顺序）。
    @MainActor
    private func segmentStepsInReadingOrder(_ scroll: NSScrollView) -> [Int] {
        let root = scroll.documentView ?? scroll
        let markers = UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentThinkingSegmentMarker.self, in: root)
        let pairs = markers.map { marker -> (step: Int, y: CGFloat) in
            (marker.step, root.convert(marker.bounds, from: marker).midY)
        }
        return pairs.sorted { $0.y < $1.y }.map(\.step)
    }

    // MARK: - ① 5 步 ⇒ 页面上 1 个思考区

    @MainActor
    func testFiveStepsRenderExactlyOneThinkingZone() {
        let messages = Self.messages(steps: 5)
        let count = withPage(messages, isRunning: true) { zoneMarkers($0).count }
        let issues = Self.zoneCountViolations(count: count)
        print("🧪 ① 五步一轮（真 AgentChatView 900×620）：页面上思考区 \(count) 个"
              + (issues.isEmpty ? " ⇒ 合一个 ✅" : " ⇒ \(issues.joined(separator: "；"))"))

        // 反例：改前形态（一条消息一块）在同一套判据下必须报红。
        let legacy = UISnapshot.LiveHost(
            AnyView(Self.LegacyPerStepThinking(texts: Self.legacyBlocks(messages))
                .frame(width: Self.pageSize.width, alignment: .topLeading)),
            size: Self.pageSize
        )
        legacy.settle()
        legacy.pump(0.2)
        defer { legacy.window.contentView = nil }
        let legacyCount = zoneMarkers(legacy).count
        let legacyIssues = Self.zoneCountViolations(count: legacyCount)
        print("🧪 反例①（改前按 step 分块）：思考区 \(legacyCount) 个 ⇒ "
              + (legacyIssues.isEmpty ? "假绿 ❌" : "判红 ✅"))

        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        XCTAssertFalse(legacyIssues.isEmpty,
                       "改前形态（\(legacyCount) 个区）判据仍然绿 ⇒ 判据没有牙齿")
        XCTAssertEqual(legacyCount, 5, "反例应有 5 个区（五步五块），实得 \(legacyCount) 个")
    }

    // MARK: - ② 定高 200pt + 内部滚动到末尾

    @MainActor
    func testZoneIsFixed200ptWithInnerScrollToTheEnd() {
        let messages = Self.messages()
        withPage(messages, isRunning: true) { live in
            guard let marker = zoneMarkers(live).first else {
                return XCTFail("页面上没有思考区 ⇒ ② 无从量起")
            }
            let height = marker.frame.height
            guard let scroll = zoneScroll(live) else {
                return XCTFail("思考区里没有内部滚动容器 ⇒ 200pt 定高把滚动也一起丢了")
            }
            let viewport = scroll.contentView.bounds.height
            let document = scroll.documentView?.bounds.height ?? 0
            let maxOffset = max(0, document - viewport)

            // 滚到底：内部滚动**真的能到末尾**（不是被裁掉）。
            let flipped = scroll.documentView?.isFlipped ?? true
            scroll.contentView.scroll(to: NSPoint(x: 0, y: flipped ? maxOffset : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            live.pump(0.1)
            let origin = scroll.contentView.bounds.origin.y
            let reachedTop = flipped ? origin : (maxOffset - origin)
            let distanceToBottom = max(0, maxOffset - reachedTop)

            let issues = Self.viewportViolations(height: height, viewport: viewport, document: document)
            print("🧪 ② 思考区：整块 \(height)pt / 视口 \(viewport)pt / 文档 \(document)pt"
                  + " / 滚到底距底 \(distanceToBottom)pt（flipped \(flipped)）"
                  + (issues.isEmpty && distanceToBottom < 1 ? " ⇒ 定高 200 + 内部可滚到底 ✅"
                     : " ⇒ " + (issues + (distanceToBottom < 1 ? [] : ["滚不到末尾（距底 \(distanceToBottom)pt）"]))
                     .joined(separator: "；")))

            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertLessThan(distanceToBottom, 1,
                              "内部滚动到了 \(reachedTop)pt / 最大 \(maxOffset)pt ⇒ 末尾那段读不到")
        }
    }

    // MARK: - ③ 顺序保真：1→5

    @MainActor
    func testSegmentOrderFollowsStepOrder() {
        let messages = Self.messages()
        withPage(messages, isRunning: true) { live in
            guard let scroll = zoneScroll(live) else {
                return XCTFail("没有内部滚动容器 ⇒ 段锚找不到")
            }
            let observed = segmentStepsInReadingOrder(scroll)
            let expected = Array(1...5)
            let issues = Self.orderViolations(observed: observed, expected: expected)

            // 文本序列（同一份聚合数据）：每段的开头就是「第 N 步」。
            let zone = AgentTurnThinking.zones(in: messages, includeReasoning: false).first
            let prefixes = zone?.segments.map { String($0.text.prefix(5)) } ?? []
            print("🧪 ③ 段锚（文档坐标上→下）\(observed) / 段文本开头 \(prefixes)"
                  + (issues.isEmpty ? " ⇒ 顺序保真 ✅" : " ⇒ \(issues.joined(separator: "；"))"))

            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertEqual(prefixes, ["第 1 步", "第 2 步", "第 3 步", "第 4 步", "第 5 步"],
                           "段文本序列 \(prefixes) 与步号不一致")

            // 反例：倒序喂同一套判据 ⇒ 必须报红。
            let red = Self.orderViolations(observed: Array(expected.reversed()), expected: expected)
            print("🧪 反例③（段序 \(Array(expected.reversed()))）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
            XCTAssertFalse(red.isEmpty, "倒序样本判据仍然绿 ⇒ ③ 没有牙齿")
        }
    }

    // MARK: - ④ 折一次 = 折整轮

    @MainActor
    func testOneToggleFoldsTheWholeRound() {
        let segments = (1...5).map { AgentThinkingSegment(step: $0, text: Self.stepText($0)) }
        let harness = FoldHarness(segments: segments, phase: .finished, manual: nil)
        let live = UISnapshot.LiveHost(AnyView(FoldHarnessView(model: harness)
                                                .frame(width: Self.pageSize.width, alignment: .topLeading)),
                                       size: CGSize(width: Self.pageSize.width, height: 400))
        live.settle()
        live.pump(0.15)
        defer { live.window.contentView = nil }

        func sample(_ label: String, expected: CGFloat) -> [String] {
            live.settle()
            live.pump(0.1)
            let count = zoneMarkers(live).count
            let height = zoneMarkers(live).first?.frame.height ?? 0
            let issues = Self.foldViolations(count: count, height: height, expected: expected, label: label)
            print("🧪 ④ \(label)：区 \(count) 个 / 整轮高 \(height)pt"
                  + (issues.isEmpty ? " ✅" : " ⇒ \(issues.joined(separator: "；"))"))
            return issues
        }

        // 终态默认折成一行（20pt）。
        let folded = sample("终态（默认折一行）", expected: AgentThinkingViewport.collapsedHeight)
        // 点一次展开 ⇒ 整轮 200pt（不是「某一段展开」）。
        harness.manual = !AgentThinkingFold.isExpanded(phase: harness.phase, manual: harness.manual)
        let expanded = sample("点一次展开", expected: AgentThinkingViewport.totalHeight)
        // 再点一次 ⇒ 整轮回到一行。
        harness.manual = !AgentThinkingFold.isExpanded(phase: harness.phase, manual: harness.manual)
        let refolded = sample("再点一次收起", expected: AgentThinkingViewport.collapsedHeight)

        XCTAssertTrue((folded + expanded + refolded).isEmpty, (folded + expanded + refolded).joined(separator: "；"))

        // 反例：按 step 分块时，同一套「整轮」判据读到 5 个区 ⇒ 判红。
        let legacy = UISnapshot.LiveHost(
            AnyView(Self.LegacyPerStepThinking(texts: Self.legacyBlocks(Self.messages()))
                .frame(width: Self.pageSize.width, alignment: .topLeading)),
            size: CGSize(width: Self.pageSize.width, height: 2000)
        )
        legacy.settle()
        legacy.pump(0.2)
        defer { legacy.window.contentView = nil }
        let legacyMarkers = zoneMarkers(legacy)
        let legacyTotal = legacyMarkers.reduce(0) { $0 + $1.frame.height }
        let red = Self.foldViolations(count: legacyMarkers.count,
                                      height: legacyTotal,
                                      expected: AgentThinkingViewport.collapsedHeight,
                                      label: "反例（按 step 分块）")
        print("🧪 反例④（五块各自 20pt，点哪块折哪块）：区 \(legacyMarkers.count) 个 / 合计 \(legacyTotal)pt ⇒ "
              + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "按 step 分块的形态判据仍然绿 ⇒ ④ 没有牙齿")
    }

    // MARK: - ⑤ 工具块不变

    @MainActor
    func testToolBlocksStaySeparate() {
        let messages = Self.messages(steps: 5)
        withPage(messages, isRunning: true) { live in
            let markers = toolMarkers(live)
            let heights = markers.map(\.frame.height)
            let issues = Self.toolViolations(count: markers.count, heights: heights, expectedCount: 5)

            let zoneText = AgentTurnThinking.zones(in: messages, includeReasoning: false).first?.text ?? ""
            let leaked = zoneText.contains("read_file")
            print("🧪 ⑤ 工具块 \(markers.count) 个 / 行高 \(heights.map { Int($0.rounded()) })"
                  + " / 思考区里混进工具行 \(leaked)"
                  + (issues.isEmpty && !leaked ? " ⇒ 工具各自成块 ✅" : " ⇒ "
                     + (issues + (leaked ? ["思考区吞了工具行"] : [])).joined(separator: "；")))

            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertFalse(leaked, "思考区文本里出现了工具行 ⇒ 动作与思考混在一起了")
        }
    }
}

// MARK: - 三行汇总（§3.33.4 契约六~八）：三条端上判据 + 反例

extension AgentTurnThinkingZoneProbeTests {

    /// 一轮结束时「这类过程信息只允许三行」的机械读数：按行种取锚。
    @MainActor
    func usageRows(_ live: UISnapshot.LiveHost<AnyView>,
                   kind: AgentTurnUsageRowMarker.Kind) -> [AgentTurnUsageRowMarker] {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentTurnUsageRowMarker.self, in: live.hosting)
            .filter { $0.kind == kind }
    }

    /// 判据 A：「Thinking 行 / Tool calls 行 / Σ 行」各**恰好一行**。
    static func rowCountViolations(thinking: Int, toolCalls: Int, total: Int) -> [String] {
        var issues: [String] = []
        if thinking != 1 { issues.append("Thinking 行 \(thinking) 行（应 1 行）⇒ 又出现多块思考") }
        if toolCalls != 1 { issues.append("Tool calls 行 \(toolCalls) 行（应 1 行）") }
        if total != 1 { issues.append("Σ 行 \(total) 行（应 1 行）") }
        return issues
    }

    /// 判据 B：Thinking 行画出来的 token 数 == 合并后那个区的 token 合计（±0）。
    static func thinkingTokenViolations(shown: Int, merged: Int) -> [String] {
        guard shown != merged else { return [] }
        return ["Thinking 行写 \(shown) tokens，合并后的区是 \(merged) tokens（差 \(shown - merged)）⇒ 抬头与区不是同一份"]
    }

    /// 判据 C：Σ == thinking + tools + output（三行**各自画出来的数** + 输出段）。
    static func totalViolations(thinking: Int, tools: Int, output: Int, total: Int) -> [String] {
        guard total != thinking + tools + output else { return [] }
        return ["Σ 行 \(total) ≠ thinking \(thinking) + tools \(tools) + output \(output)"
                + " = \(thinking + tools + output) ⇒ 合计口径不对"]
    }

    // MARK: A 一轮 5 步 + 1 次工具 ⇒ 三行各恰好一行

    @MainActor
    func testOneRoundEndsWithExactlyThreeSummaryRows() {
        // 主人给的形态：一轮 5 步、1 次工具调用。
        let messages = Self.messages(steps: 5, toolsEveryStep: false)
        withPage(messages, isRunning: false) { live in
            let thinkingRows = zoneMarkers(live).count
            let toolRows = usageRows(live, kind: .toolCalls).count
            let totalRows = usageRows(live, kind: .total).count
            let issues = Self.rowCountViolations(thinking: thinkingRows,
                                                 toolCalls: toolRows,
                                                 total: totalRows)
            print("🧪 A 一轮结束（5 步 + 1 次工具）：Thinking 行 \(thinkingRows) / Tool calls 行 \(toolRows)"
                  + " / Σ 行 \(totalRows)"
                  + (issues.isEmpty ? " ⇒ 三行各一行 ✅" : " ⇒ \(issues.joined(separator: "；"))"))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

            // 三行都是**折起来的一行**（20pt），不是「一块一块」。
            let heights = [zoneMarkers(live).first?.frame.height,
                           usageRows(live, kind: .toolCalls).first?.frame.height,
                           usageRows(live, kind: .total).first?.frame.height].compactMap { $0 }
            print("🧪 A 三行行高 \(heights.map { Int($0.rounded()) })（折叠态应各 20pt）")
            XCTAssertEqual(heights.count, 3, "三行没凑齐：\(heights)")
            XCTAssertTrue(heights.allSatisfy { abs($0 - AgentThinkingViewport.collapsedHeight) <= 0.5 },
                          "终态三行行高 \(heights) ≠ 各一行 \(AgentThinkingViewport.collapsedHeight)pt")
        }

        // 反例：改前形态（一条消息一块）⇒ Thinking 行 5 行 ⇒ 同一套判据判红。
        let legacy = UISnapshot.LiveHost(
            AnyView(Self.LegacyPerStepThinking(texts: Self.legacyBlocks(messages))
                .frame(width: Self.pageSize.width, alignment: .topLeading)),
            size: self.pageSizeForLegacy
        )
        legacy.settle()
        legacy.pump(0.2)
        defer { legacy.window.contentView = nil }
        let legacyThinking = zoneMarkers(legacy).count
        let legacyIssues = Self.rowCountViolations(thinking: legacyThinking,
                                                   toolCalls: usageRows(legacy, kind: .toolCalls).count,
                                                   total: usageRows(legacy, kind: .total).count)
        print("🧪 反例A（一条消息一块）：Thinking 行 \(legacyThinking) / Tool calls 行 0 / Σ 行 0 ⇒ "
              + (legacyIssues.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(legacyIssues.isEmpty, "改前形态（\(legacyThinking) 行 Thinking）判据仍然绿 ⇒ A 没有牙齿")
    }

    var pageSizeForLegacy: CGSize { CGSize(width: 900, height: 2000) }

    // MARK: B Thinking 行 == 合并后区的 token 合计

    @MainActor
    func testThinkingRowTokensEqualMergedZone() {
        let messages = Self.messages(steps: 5, toolsEveryStep: false)
        let zone = AgentTurnThinking.zones(in: messages, includeReasoning: false).first
        let merged = zone.map { AgentTokenEstimator.tokens($0.text) } ?? -1
        let usage = AgentTurnUsageReader.usage(in: messages, includeReasoning: false)[0]

        withPage(messages, isRunning: false) { live in
            let shown = zoneMarkers(live).first?.tokens ?? -1
            let issues = Self.thinkingTokenViolations(shown: shown, merged: merged)
            print("🧪 B Thinking 行画的是 \(shown) tokens / 合并后的区 \(merged) tokens"
                  + " / 输出段 \(usage?.outputTokens ?? -1) tokens"
                  + (issues.isEmpty ? " ⇒ 同一个数 ✅" : " ⇒ \(issues.joined(separator: "；"))"))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertGreaterThan(shown, 0, "Thinking 行是 \(shown) ⇒ 读数没接上（写死 / 空值）")
            XCTAssertNotEqual(shown, usage?.outputTokens ?? -2,
                              "Thinking 行等于输出段的 token 数 ⇒ 抬头拿错了源")

            // 反例：把「输出段」的数当成 Thinking 行 ⇒ 同一套判据报红。
            let red = Self.thinkingTokenViolations(shown: usage?.outputTokens ?? -1, merged: merged)
            print("🧪 反例B（Thinking 行写输出段的数 \(usage?.outputTokens ?? -1)）⇒ "
                  + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
            XCTAssertFalse(red.isEmpty, "拿错源的读数判据仍然绿 ⇒ B 没有牙齿")
        }
    }

    // MARK: C Σ == thinking + tools + output

    @MainActor
    func testTotalRowEqualsItsThreeParts() {
        let messages = Self.messages(steps: 5, toolsEveryStep: false)
        let output = AgentTurnUsageReader.usage(in: messages, includeReasoning: false)[0]?.outputTokens ?? -1
        withPage(messages, isRunning: false) { live in
            let thinking = zoneMarkers(live).first?.tokens ?? -1
            let tools = usageRows(live, kind: .toolCalls).first?.tokens ?? -1
            let total = usageRows(live, kind: .total).first?.tokens ?? -1
            let issues = Self.totalViolations(thinking: thinking, tools: tools, output: output, total: total)
            print("🧪 C Σ 行 \(total) / thinking 行 \(thinking) / tools 行 \(tools) / 输出段 \(output)"
                  + (issues.isEmpty ? " ⇒ Σ = thinking + tools + output ✅" : " ⇒ \(issues.joined(separator: "；"))"))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertGreaterThan(total, thinking, "Σ 没有把工具 / 输出那两段算进去")
            XCTAssertGreaterThan(tools, 0, "工具那一行是 0 tokens ⇒ 读数没接上")

            // 反例：Σ 只算输出（主人的原话：「反例：Σ 只算输出 ⇒ 判红」）。
            let red = Self.totalViolations(thinking: thinking, tools: tools, output: output, total: output)
            print("🧪 反例C（Σ 只算输出 \(output)）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
            XCTAssertFalse(red.isEmpty, "Σ 只算输出的样本判据仍然绿 ⇒ C 没有牙齿")
        }
    }
}
