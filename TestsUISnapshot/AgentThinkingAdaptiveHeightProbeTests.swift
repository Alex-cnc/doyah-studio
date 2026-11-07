import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **思考区高度 = min(内容实测高, 上限)** 的端上判据（详设 §3.37，900×620 真视图）。
///
/// ## 主人原话（beta1.0.8 真机）
///
/// > 「现在又变成了 thinking/tools 等区域是固定高度，中间空一个大空白区域，
/// >  只有等返回最终结论之后才能填满，这个给人感受不好。」
///
/// 即：为压住 beta1.0.4 的「高度一个 token 抖一次」把展开态钉成恒 200pt，代价是内容
/// 只有一两行时下面空一大块。正解是**高度 = min(内容实测高, 200)**，并且内容高**按整行
/// 向上取**（`AgentThinkingViewport.quantizedContentHeight`）—— 只在跨过行高倍数时变，
/// 两个反例（抖 / 空白）在同一条口径下都关掉。
///
/// ## 五条判据（每条都带反例读数，反例与真读数走**同一套**判定函数）
///
/// ① 1 行思考 ⇒ 区高 ≈ 1 行（实测 **42pt** = 抬头 20 + 发丝 2 + 一行 20，明显 < 200）；
/// ② 3 行 / 8 行 ⇒ 区高随行数**递增**；
/// ③ 60 行 ⇒ **恰为上限 200pt** + 内部滚动（文档高 > 视口）；
/// ④ 流式 300 次追加 ⇒ 区高**单调不减**，**变化次数 ≤ 行数**（反例：300 次各变一次 ⇒ 判红）；
/// ⑤ 无空白：区高 − (抬头 + 发丝 + 内容实测高) **< 一个行高**（内容未超上限时）。
///
/// ## 读数从哪来（不是推算）
/// · 区高 = 真宿主视图树里 `AgentThinkingZoneMarker.frame.height`（那个锚就是区的 frame）；
/// · 内容实测高 = 区里那格 `NSScrollView` 的 `documentView.bounds.height`；
/// · 视口高 = 同一格的 `contentView.bounds.height`。
///
/// 锚与滚动容器的取法沿用 `AgentTurnThinkingZoneProbeTests`（外层对话区也是滚动容器，
/// 所以要取「包着段锚的最内层」那一个）。默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）。
final class AgentThinkingAdaptiveHeightProbeTests: XCTestCase {

    static let width: CGFloat = 900

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "自适应高度要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    @MainActor
    final class Harness: ObservableObject {
        @Published var text: String
        @Published var phase: AgentThinkingPhase
        @Published var manual: Bool?

        init(text: String = "", phase: AgentThinkingPhase = .running, manual: Bool? = nil) {
            self.text = text
            self.phase = phase
            self.manual = manual
        }
    }

    struct HarnessView: View {
        @ObservedObject var model: Harness
        var body: some View {
            AgentThinkingZone(text: model.text,
                              phase: model.phase,
                              manual: model.manual,
                              steps: 1,
                              elapsedSeconds: 18.4,
                              highlight: nil,
                              language: .simplifiedChinese) { expanded in
                model.manual = expanded
            }
        }
    }

    /// **反例的形态**：改前（beta1.0.4~1.0.7）的「恒 200pt」—— 抬头 20 + 发丝 2 + 定高视口 178。
    struct LegacyFixedHeightZone: View {
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: AgentThinkingViewport.hairGap) {
                Text("▾ Thinking")
                    .font(Theme.font(.mono))
                    .frame(height: AgentThinkingViewport.collapsedHeight)
                ScrollView(.vertical) {
                    Text(text)
                        .font(Theme.font(.mono))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: AgentThinkingViewport.viewportHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AgentThinkingViewport.totalHeight, alignment: .topLeading)
            .background(AgentThinkingZoneAnchor(tokens: -1))
        }
    }

    /// `n` 行短句（每行都在 900pt 宽里只占一视觉行）。
    static func lines(_ n: Int) -> String {
        (1...max(1, n)).map { "第 \($0) 行：读一下这个文件。" }.joined(separator: "\n")
    }

    // MARK: - 判定函数（真读数与反例共用）

    /// ① 一行内容：区高必须 ≈ 一行、明显小于上限。
    static func singleLineViolations(height: CGFloat) -> [String] {
        var issues: [String] = []
        let expected = AgentThinkingViewport.expandedHeight(contentHeight: 15)   // 42pt
        if abs(height - expected) > 0.5 {
            issues.append("一行思考的区高 \(height)pt ≠ 一行档 \(expected)pt")
        }
        if height >= AgentThinkingViewport.totalHeight - 0.5 {
            issues.append("一行思考的区高 \(height)pt 顶到了上限 \(AgentThinkingViewport.totalHeight)pt ⇒ 固定高度没去掉")
        }
        return issues
    }

    /// ② 递增：行数多的必须更高。
    static func monotoneGrowthViolations(heights: [CGFloat]) -> [String] {
        var issues: [String] = []
        for index in 1..<heights.count where heights[index] <= heights[index - 1] {
            issues.append("第 \(index + 1) 档 \(heights[index])pt 没比第 \(index) 档 \(heights[index - 1])pt 高 ⇒ 高度不跟行数走")
        }
        return issues
    }

    /// ③ 超上限：恰为 200pt（不许超、也不许留余量）+ 内部滚动。
    static func capViolations(height: CGFloat, viewport: CGFloat, document: CGFloat) -> [String] {
        var issues: [String] = []
        if abs(height - AgentThinkingViewport.totalHeight) > 0.5 {
            issues.append("60 行内容的区高 \(height)pt ≠ 上限 \(AgentThinkingViewport.totalHeight)pt")
        }
        if document <= viewport {
            issues.append("文档高 \(document)pt ≤ 视口 \(viewport)pt ⇒ 内部滚动没生效")
        }
        return issues
    }

    /// ④ 流式：单调不减 + **变化次数 ≤ 内容行数**。
    static func streamingViolations(heights: [CGFloat], rows: Int) -> [String] {
        guard let first = heights.first, heights.count > 1 else {
            return ["样本不足（\(heights.count) 个）⇒ 判据没量到东西"]
        }
        var issues: [String] = []
        var changes = 0
        for index in 1..<heights.count {
            let delta = heights[index] - heights[index - 1]
            if delta < -0.5 {
                issues.append("第 \(index) 次追加后高度从 \(heights[index - 1])pt 掉到 \(heights[index])pt ⇒ 高度会缩")
            }
            if abs(delta) > 0.5 { changes += 1 }
        }
        if changes > rows {
            issues.append("300 次追加里高度变了 \(changes) 次 > 内容行数 \(rows) ⇒ 逐 token 在变（按行量化的口径没生效）")
        }
        if abs((heights.last ?? 0) - first) < 0.5 && rows > 2 {
            issues.append("整段流式高度一动没动（\(first)pt）⇒ 内容长了高度没长")
        }
        return issues
    }

    /// ⑤ 无空白：区高 − 自然高 < 一个行高。
    static func blankViolations(height: CGFloat, content: CGFloat) -> [String] {
        let natural = AgentThinkingViewport.collapsedHeight + AgentThinkingViewport.hairGap + content
        let blank = height - natural
        guard blank >= AgentThinkingViewport.lineHeight else { return [] }
        return ["区高 \(height)pt − 自然高 \(natural)pt = \(blank)pt ≥ 一行 \(AgentThinkingViewport.lineHeight)pt ⇒ 留了空白"]
    }

    // MARK: - 宿主

    @MainActor
    private func host(text: String,
                      phase: AgentThinkingPhase = .running,
                      manual: Bool? = nil) -> (UISnapshot.LiveHost<AnyView>, Harness) {
        let harness = Harness(text: text, phase: phase, manual: manual)
        let live = UISnapshot.LiveHost(
            AnyView(HarnessView(model: harness)
                .frame(width: Self.width, alignment: .topLeading)),
            size: CGSize(width: Self.width, height: 620)
        )
        live.settle()
        live.pump(0.15)
        return (live, harness)
    }

    /// 让实测高的回传（`ContentHeightSpy` 下一拍）落地，再读一次。
    @MainActor
    private func settleHeight(_ live: UISnapshot.LiveHost<AnyView>) {
        live.settle()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        live.settle()
    }

    @MainActor
    private func zoneHeight(_ live: UISnapshot.LiveHost<AnyView>) -> CGFloat {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentThinkingZoneMarker.self, in: live.hosting)
            .first?.frame.height ?? 0
    }

    /// 思考区里**最内层**那格 `NSScrollView`（外层对话区也是滚动容器，必须排掉）。
    @MainActor
    private func zoneScroll(_ live: UISnapshot.LiveHost<AnyView>) -> NSScrollView? {
        let hasSegment = { (scroll: NSScrollView) in
            !UISnapshot.LiveHost<AnyView>.findViews(ofType: AgentThinkingSegmentMarker.self, in: scroll).isEmpty
        }
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
            .first { scroll in
                guard hasSegment(scroll) else { return false }
                return !UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: scroll)
                    .filter { $0 !== scroll }
                    .contains(where: hasSegment)
            }
    }

    // MARK: - ① 1 行 ⇒ 区高 ≈ 一行

    @MainActor
    func testOneLineContentTakesOneLine() {
        let (live, _) = host(text: "读一下这个文件。")
        defer { live.window.contentView = nil }
        settleHeight(live)

        let height = zoneHeight(live)
        let issues = Self.singleLineViolations(height: height)
        print("🧪 ① 一行思考（900×620 真视图）：区高 \(height)pt"
              + "（一行档 \(AgentThinkingViewport.expandedHeight(contentHeight: 15))pt / 上限 \(AgentThinkingViewport.totalHeight)pt）"
              + (issues.isEmpty ? " ⇒ 贴着内容收 ✅" : " ⇒ " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

        // 反例：把同一条内容挂进改前的「恒 200pt」形态 ⇒ 同一套判据必须报红。
        let legacy = UISnapshot.LiveHost(
            AnyView(LegacyFixedHeightZone(text: "读一下这个文件。")
                .frame(width: Self.width, alignment: .topLeading)),
            size: CGSize(width: Self.width, height: 620)
        )
        legacy.settle()
        legacy.pump(0.15)
        defer { legacy.window.contentView = nil }
        let legacyHeight = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentThinkingZoneMarker.self, in: legacy.hosting).first?.frame.height ?? 0
        let legacyIssues = Self.singleLineViolations(height: legacyHeight)
        print("🧪 反例①（改前恒 200pt）：区高 \(legacyHeight)pt ⇒ "
              + (legacyIssues.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(legacyIssues.isEmpty, "改前形态（\(legacyHeight)pt）判据仍然绿 ⇒ ① 没有牙齿")
    }

    // MARK: - ② 3 行 / 8 行 ⇒ 递增

    @MainActor
    func testHeightGrowsWithLineCount() {
        var readings: [(lines: Int, height: CGFloat, content: CGFloat)] = []
        for count in [1, 3, 8] {
            let (live, _) = host(text: Self.lines(count))
            defer { live.window.contentView = nil }
            settleHeight(live)
            let content = zoneScroll(live)?.documentView?.bounds.height ?? 0
            readings.append((count, zoneHeight(live), content))
        }
        let heights = readings.map(\.height)
        let issues = Self.monotoneGrowthViolations(heights: heights)
        print("🧪 ② 行数 → 区高：" + readings.map { "\($0.lines) 行 \($0.height)pt" }.joined(separator: " / ")
              + (issues.isEmpty ? " ⇒ 递增 ✅" : " ⇒ " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        XCTAssertLessThan(heights.last ?? 0, AgentThinkingViewport.totalHeight,
                          "8 行就顶到上限 \(AgentThinkingViewport.totalHeight)pt ⇒ 判据分不出递增")
    }

    // MARK: - ③ 60 行 ⇒ 恰为上限 + 内部滚动

    @MainActor
    func testLongContentStopsAtCapAndScrolls() {
        let (live, _) = host(text: Self.lines(60))
        defer { live.window.contentView = nil }
        settleHeight(live)
        guard let scroll = zoneScroll(live) else {
            return XCTFail("思考区里没有内部滚动容器 ⇒ 超上限之后内容无处可滚")
        }
        let height = zoneHeight(live)
        let viewport = scroll.contentView.bounds.height
        let document = scroll.documentView?.bounds.height ?? 0
        let issues = Self.capViolations(height: height, viewport: viewport, document: document)
        print("🧪 ③ 60 行：区高 \(height)pt / 视口 \(viewport)pt / 文档 \(document)pt"
              + (issues.isEmpty ? " ⇒ 卡上限 + 内部滚 ✅" : " ⇒ " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
    }

    // MARK: - ④ 流式 300 次追加：单调不减、变化次数 ≤ 行数

    @MainActor
    func testStreamingHeightIsMonotoneAndChunky() {
        let (live, harness) = host(text: "")
        defer { live.window.contentView = nil }

        // **一次追加一小截、不换行**：这是端点真实的增量粒度（几个字一次），
        // 也是「高度会不会逐 token 变」最严的形态 —— 行数几乎不涨，未量化的高度却每次都在涨。
        var heights: [CGFloat] = []
        for _ in 0..<300 {
            harness.text += "读一下这个文件。"
            settleHeight(live)
            heights.append(zoneHeight(live))
        }
        // 内容行数（判据的分母）= 末态文档高 / 行高。
        let content = zoneScroll(live)?.documentView?.bounds.height ?? 0
        let rows = max(1, Int((content / AgentThinkingViewport.lineHeight).rounded(.up)))
        let changes = zip(heights, heights.dropFirst()).filter { abs($1 - $0) > 0.5 }.count
        let issues = Self.streamingViolations(heights: heights, rows: rows)
        print("🧪 ④ 300 次追加（每次 8 字、不换行）：首 \(heights.first ?? 0)pt / 末 \(heights.last ?? 0)pt"
              + " / 变化 \(changes) 次 / 内容 \(content)pt = \(rows) 行"
              + (issues.isEmpty ? " ⇒ 单调且不逐 token 抖 ✅" : " ⇒ " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        XCTAssertGreaterThan(changes, 0, "高度一次都没变 ⇒ 判据没量到增长")
        XCTAssertLessThanOrEqual(changes, rows,
                                 "高度变了 \(changes) 次 > 内容 \(rows) 行 ⇒ 又变成逐 token 抖")

        // 反例④：同一套判据喂「每次追加都变 0.6pt」的样本序列（同样 300 次追加）
        // ⇒ 必须判红。这正是未量化（`maxHeight` 那版）的读数形状。
        let perToken = (0..<300).map { 62 + CGFloat($0) * 0.6 }
        let red = Self.streamingViolations(heights: perToken, rows: rows)
        print("🧪 反例④（300 次各变 0.6pt / 内容 \(rows) 行）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "逐 token 抖的样本判据仍然绿 ⇒ ④ 没有牙齿")
    }

    // MARK: - ⑤ 无空白

    @MainActor
    func testNoBlankGapUnderShortContent() {
        for count in [1, 3, 8] {
            let (live, _) = host(text: Self.lines(count))
            defer { live.window.contentView = nil }
            settleHeight(live)
            let height = zoneHeight(live)
            let content = zoneScroll(live)?.documentView?.bounds.height ?? 0
            let issues = Self.blankViolations(height: height, content: content)
            let blank = height - (AgentThinkingViewport.collapsedHeight
                                  + AgentThinkingViewport.hairGap + content)
            print("🧪 ⑤ \(count) 行：区高 \(height)pt / 内容 \(String(format: "%.1f", content))pt"
                  + " / 空白余量 \(String(format: "%.1f", blank))pt（阈值 一行 \(AgentThinkingViewport.lineHeight)pt）"
                  + (issues.isEmpty ? " ✅" : " ⇒ " + issues.joined(separator: "；")))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        }

        // 反例⑤：把「恒 200pt」的读数喂同一套判据（1 行内容 ⇒ 空白 ≈ 160pt）⇒ 判红。
        let red = Self.blankViolations(height: AgentThinkingViewport.totalHeight, content: 16)
        print("🧪 反例⑤（恒 200pt + 一行内容 16pt）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "固定高度的读数判据仍然绿 ⇒ ⑤ 没有牙齿")
    }

    // MARK: - ⑥ 阶段形态：运行中贴着长、终态一行让位，且**只跳一次**

    /// 运行中：过程区展开、高度跟着内容长（> 一行，贴着长）；终态：思考区折成 **20pt 一行**，
    /// 运行中 → 终态全过程**只有一次**高度跳变（不许反复抖）。
    @MainActor
    func testPhaseTransitionCollapsesOnceToASingleRow() {
        let (live, harness) = host(text: Self.lines(5))
        defer { live.window.contentView = nil }
        settleHeight(live)
        let running = zoneHeight(live)
        XCTAssertGreaterThan(running, AgentThinkingViewport.collapsedHeight + AgentThinkingViewport.hairGap + 20,
                             "运行中 5 行内容才 \(running)pt ⇒ 过程区没展开 / 没贴着内容长")

        harness.phase = .finished
        var samples: [CGFloat] = [running]
        for _ in 0..<12 {
            settleHeight(live)
            samples.append(zoneHeight(live))
        }
        let changes = zip(samples, samples.dropFirst()).filter { abs($1 - $0) > 0.5 }.count
        let landed = samples.last ?? 0
        print("🧪 ⑥ 运行中 \(running)pt → 终态采样 \(samples.dropFirst().map { Int($0.rounded()) })"
              + " ⇒ 跳变 \(changes) 次 / 落点 \(landed)pt"
              + (changes == 1 && abs(landed - AgentThinkingViewport.collapsedHeight) <= 0.5 ? " ✅" : " ⇒ ❌"))
        XCTAssertEqual(changes, 1, "运行中→终态高度变了 \(changes) 次（应恰好 1 次）⇒ 还在抖")
        XCTAssertEqual(landed, AgentThinkingViewport.collapsedHeight, accuracy: 0.5,
                       "终态思考区不是一行 20pt")
    }

    /// 终态的工具区也是一行 20pt（`▾ Tool calls (n) ~N tokens` 折叠态）。
    @MainActor
    func testTerminalToolRowIsOneLine() {
        let live = UISnapshot.LiveHost(
            AnyView(AgentToolCallsSummaryRow(count: 3,
                                             tokens: 42,
                                             texts: ["▸ read_file · A.swift", "▸ read_file · B.swift"],
                                             expanded: false,
                                             highlight: nil,
                                             language: .simplifiedChinese) {}
                .frame(width: Self.width, alignment: .topLeading)),
            size: CGSize(width: Self.width, height: 200)
        )
        live.settle()
        live.pump(0.1)
        defer { live.window.contentView = nil }
        let height = UISnapshot.LiveHost<AnyView>
            .findViews(ofType: AgentTurnUsageRowMarker.self, in: live.hosting)
            .first { $0.kind == .toolCalls }?.frame.height ?? 0
        print("🧪 ⑥b 终态工具区：Tool calls 行高 \(height)pt（应 20pt）")
        XCTAssertEqual(height, AgentThinkingViewport.collapsedHeight, accuracy: 0.5,
                       "终态工具区不是一行 20pt")
    }
}
