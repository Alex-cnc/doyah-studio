import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **思考区流式输出的几何判据**（详设 §3.33.2 ② / ③ / ④）。
///
/// ## 由头（人类主人 2026-11-07 真机 beta1.0.4）
///
/// > 「思考过程中，流式输出让滚动条很闪，不像 hermes 的输出这么丝滑」
///
/// ## 判据（每条都带反例读数）
///
/// ② **高度按整行阶梯长、到上限为止**（§3.37 起取代「定高 200」）：200 段增量过程中逐次采样整块高度 ——
///    单调不减、全部落在「抬头 22 + 整行 20 的整数倍」格点上、最高 = 200pt（上限）、变化次数远小于段数；
///    反例（改前形态 `ScrollView.frame(maxHeight: 178)`）高度每段都变一点 ⇒ 判红；
/// ③ **条件跟随**：贴着底时新内容到达 ⇒ 内部偏移跟到底；**模拟用户上滚**后新增内容 ⇒
///    偏移**一动不动**（反例：无条件跟随时偏移被拽回底部）；
/// ④ **三态高度**：运行中 ↔ 终态 ↔ 手动展开来回切，采样到的整块高度只取 **内容档 / 200 / 20**，
///    没有中间值（反例：`.animation` 改同一对高度 ⇒ 采得到中间档）。
///
/// ## 读数从哪来（不是推算）
/// · 整块高 = **真宿主视图的 frame 高**（`NSHostingView` 缩到内容尺寸，实测 200.0pt；
///   `GeometryReader` + 偏好回传在离屏宿主里收不到值 —— 实测恒为 0，故不用它）；
/// · 内部偏移 = 那一格 `NSScrollView` 的 clip `bounds.origin`（按 `isFlipped` 归一成「距顶」）。
///
/// ## 边界（如实登记）
/// · 折叠 / 展开是 `onTapGesture`（不落成 `NSButton`）⇒ 这里靠 `phase` / `manual` 直接挂起来；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 取证才跑，门禁不跑。
final class AgentThinkingFlowProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 400)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "思考区流式探针要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// 驱动思考区的一台小机器：文本 / 相位 / 手动态都可以中途改（**同一个宿主实例**，
    /// 这样才能判「内容变了高度变不变」；重建视图等于把 `@State` 也重置了）。
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
                              steps: 12,
                              elapsedSeconds: 18.4,
                              highlight: nil,
                              language: .simplifiedChinese) { _ in }
        }
    }

    /// 改前形态（反例②）：内容格是 `maxHeight`，`ScrollView` 内容短时缩到内容高。
    struct LegacyThinkingShape: View {
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text("▾ 思考过程 · 12 步 · 18.4s")
                    .font(Theme.font(.mono))
                    .frame(height: Metrics.listRowHeight)
                ScrollView(.vertical) {
                    Text(text)
                        .font(Theme.font(.mono))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200 - Metrics.listRowHeight - Spacing.hair)
            }
        }
    }

    // MARK: - 读数

    @MainActor
    private func host(_ content: AnyView) -> UISnapshot.LiveHost<AnyView> {
        // **宽度钉死**：`NSHostingView` 会缩到内容的 fitting 尺寸，空内容时整块只剩 16pt 宽
        // （实测），于是文字被挤成一字一行、滚动读数全失真。真机上这一格在满宽的
        // `VStack` 里，所以探针也必须给它满宽。
        let pinned = AnyView(content.frame(width: Self.pageSize.width, alignment: .topLeading))
        let live = UISnapshot.LiveHost(pinned, size: Self.pageSize)
        live.settle()
        live.pump(0.15)
        return live
    }

    /// 重排一次（顺带让运行循环跑一小拍），读**整块高度**：真宿主视图的 frame 高。
    @MainActor
    @discardableResult
    private func sampleHeight(_ live: UISnapshot.LiveHost<AnyView>) -> CGFloat {
        live.settle()
        RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        live.settle()
        return live.hosting.frame.height
    }

    @MainActor
    private func zoneScrollView(_ live: UISnapshot.LiveHost<AnyView>) -> NSScrollView? {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting).first
    }

    /// 归一化成「距顶偏移」（与 `ScrollOffsetSpy` 同一口径）。
    @MainActor
    private func offsetFromTop(_ scroll: NSScrollView) -> CGFloat {
        let content = scroll.documentView?.bounds.height ?? 0
        let viewport = scroll.contentView.bounds.height
        let maxOffset = max(0, content - viewport)
        let flipped = scroll.documentView?.isFlipped ?? true
        return flipped ? scroll.contentView.bounds.origin.y : (maxOffset - scroll.contentView.bounds.origin.y)
    }

    /// 一段思考（≈ 40 字：200 段之后足够把 178pt 的视口撑爆）。
    private func thinkingLine(_ index: Int) -> String {
        "第 \(index) 步：读一下 Core/AgentChat.swift，看流式在哪一层刷。\n\n"
    }

    /// 旧口径读高度：`NSHostingView` 900×4000 → `fittingSize`（内容**自己**想占多高）。
    ///
    /// 为什么反例必须用这个口径：`ScrollView` 在活宿主里会被分到 178pt 的满高，
    /// 看不出「内容短时缩到内容高」；而改前那份形状（`maxHeight`）正是靠
    /// 「按内容理想高度量」才暴露的（上一轮 `T-3.33-06` 的 37pt 也是这么量的）。
    @MainActor
    private func fittingHeight<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: Self.pageSize.width, alignment: .topLeading))
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 4000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    /// 判据② 的本体（§3.37 起）：**高度只能按整行阶梯增长，到上限为止** ——
    /// 既不许「定高留白」，也不许「每段都变一点」（beta1.0.4 的抖动）。
    private func steppedViolations(samples: [CGFloat], rows: Int) -> [String] {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else {
            return ["一个样本都没采到 ⇒ 判据没量到东西"]
        }
        var issues: [String] = []
        let cap = AgentThinkingViewport.totalHeight
        let header = AgentThinkingViewport.collapsedHeight + AgentThinkingViewport.hairGap
        let step = AgentThinkingViewport.lineHeight
        if samples.contains(where: { $0 > cap + 0.5 }) {
            issues.append("采样里出现 \(samples.max() ?? 0)pt > 上限 \(cap)pt")
        }
        if last < first - 0.5 {
            issues.append("高度从 \(first)pt 掉到 \(last)pt ⇒ 越流越矮")
        }
        for value in samples where value < cap - 0.5 {
            let offGrid = abs(((value - header) / step).rounded() * step + header - value)
            if offGrid > 0.5 {
                issues.append("\(value)pt 不在「抬头 \(header) + 整行 \(Int(step))pt」的格点上 ⇒ 高度没按整行量化")
                break
            }
        }
        var changes = 0
        for index in 1..<samples.count where abs(samples[index] - samples[index - 1]) > 0.5 { changes += 1 }
        if changes > rows {
            issues.append("高度变了 \(changes) 次 > 内容行数 \(rows) ⇒ 每段都在变（逐 token 抖）")
        }
        return issues
    }

    // MARK: - ② 流式：按整行阶梯长到上限，然后停住

    @MainActor
    func testViewportGrowsByRowsAndStopsAtCap() {
        let harness = Harness()
        let live = host(AnyView(HarnessView(model: harness)))
        defer { live.window.contentView = nil }

        var heights: [CGFloat] = []
        for index in 0..<200 {
            harness.text += thinkingLine(index)
            heights.append(sampleHeight(live))
        }
        let minHeight = heights.min() ?? 0
        let maxHeight = heights.max() ?? 0
        let changes = zip(heights, heights.dropFirst()).filter { abs($1 - $0) > 0.5 }.count
        let issues = steppedViolations(samples: heights, rows: 200 * 2)
        print("🧪 ② 流式（§3.37）：200 段增量逐次采样 \(heights.count) 次 ⇒ 首 \(heights.first ?? 0)pt"
              + " / min \(minHeight)pt / max \(maxHeight)pt / 变化 \(changes) 次 / 末段文本 \(harness.text.count) 字"
              + (issues.isEmpty ? " ⇒ 按行阶梯长到上限 ✅" : " ⇒ \(issues.joined(separator: "；"))"))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
        XCTAssertLessThan(minHeight, AgentThinkingViewport.totalHeight,
                          "第一段就已经是 \(minHeight)pt ⇒ 高度没跟着内容收（又回到定高）")
        XCTAssertEqual(maxHeight, AgentThinkingViewport.totalHeight, accuracy: 0.5,
                       "内容 5000+ 字也没顶到上限 \(AgentThinkingViewport.totalHeight)pt")
        XCTAssertLessThanOrEqual(changes, heights.count / 3,
                                 "高度变了 \(changes) 次 / 采样 \(heights.count) 次 ⇒ 每段都在变")
        XCTAssertGreaterThan(harness.text.count, 5_000, "夹具的思考只有 \(harness.text.count) 字 ⇒ 撑不满视口")

        // 视口是真的在滚：内容高 ≫ 视口高。
        guard let scroll = zoneScrollView(live) else {
            return XCTFail("思考区里没找到内部滚动容器（NSScrollView）⇒ 上限是不是把滚动也一起丢了")
        }
        let contentHeight = scroll.documentView?.bounds.height ?? 0
        print("🧪 ② 内部滚动：文档高 \(contentHeight)pt / 视口高 \(scroll.contentView.bounds.height)pt"
              + " / 文档宽 \(scroll.documentView?.bounds.width ?? 0)pt"
              + " / flipped \(scroll.documentView?.isFlipped ?? true)")
        XCTAssertEqual(scroll.contentView.bounds.height, AgentThinkingViewport.viewportHeight, accuracy: 0.5,
                       "内容格不是 178pt")
        XCTAssertGreaterThan(contentHeight, AgentThinkingViewport.viewportHeight * 2,
                             "内容 \(contentHeight)pt 撑不出内部滚动 ⇒ 判据没测到真场景")
    }

    /// 反例②：改前形态（`maxHeight`）⇒ **同一套判据**必须报红。
    ///
    /// 两个不同的缺陷各有一条反例，别混在一起：
    /// · 本条 = beta1.0.4 那版（`ScrollView.frame(maxHeight: 178)`）⇒ 高度**每段都变一点**、
    ///   且不落在整行格点上 ⇒ `steppedViolations` 判红；
    /// · 「定高 200 留白」那版的反例在 `AgentThinkingAdaptiveHeightProbeTests` 判据①（200pt ⇒ 判红）。
    ///
    /// 新形态的正样本走**活宿主**（`testViewportGrowsByRowsAndStopsAtCap`）：
    /// `fittingHeight` 那条路对异步实测（`ContentHeightSpy` 下一拍）量不到 —— 同步建 `NSHostingView`
    /// 时回调还没发生，量出来恒是「抬头 22pt」（实测），拿它当对照会得出假结论。
    @MainActor
    func testLegacyMaxHeightViewportGrowsAndIsJudgedRed() {
        var legacyHeights: [CGFloat] = []
        var text = ""
        for index in 0..<40 {
            text += thinkingLine(index)
            legacyHeights.append(fittingHeight(LegacyThinkingShape(text: text)))
        }
        let changes = zip(legacyHeights, legacyHeights.dropFirst()).filter { abs($1 - $0) > 0.5 }.count
        let header = AgentThinkingViewport.collapsedHeight + AgentThinkingViewport.hairGap
        let step = AgentThinkingViewport.lineHeight
        let offGrid = legacyHeights.filter { value in
            value < AgentThinkingViewport.totalHeight - 0.5
                && abs(((value - header) / step).rounded() * step + header - value) > 0.5
        }.count
        let issues = steppedViolations(samples: legacyHeights, rows: 80)
        print("🧪 反例②（maxHeight 旧形态）：\(Array(legacyHeights.prefix(6)).map { Int($0.rounded()) }) … →"
              + " \(legacyHeights.max() ?? 0)pt（首段 \(legacyHeights.first ?? 0)pt / 变化 \(changes) 次"
              + " / 脱离整行格点 \(offGrid) 档）"
              + " ⇒ " + (issues.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(issues.isEmpty,
                       "旧形态（高度 \(legacyHeights.first ?? 0) → \(legacyHeights.max() ?? 0)pt）判据仍然绿 ⇒ 判据没有牙齿")
        XCTAssertGreaterThanOrEqual(offGrid, 3,
                                    "旧形态里脱离整行格点的只有 \(offGrid) 档 ⇒ 夹具没复现「连续随手长」的形态")
    }

    // MARK: - ③ 条件跟随：只有贴底才跟

    @MainActor
    func testFollowOnlyWhenPinnedToBottom() {
        let harness = Harness()
        let live = host(AnyView(HarnessView(model: harness)))
        defer { live.window.contentView = nil }

        // 先灌满到能滚（空文本时这一格根本不存在，滚动容器也就还没有）。
        for index in 0..<30 { harness.text += thinkingLine(index) }
        live.pump(0.1)
        guard let scroll = zoneScrollView(live) else {
            return XCTFail("思考区里没找到内部滚动容器")
        }

        let contentHeight = scroll.documentView?.bounds.height ?? 0
        let viewportHeight = scroll.contentView.bounds.height
        let maxOffset = max(0, contentHeight - viewportHeight)
        let pinnedOffset = offsetFromTop(scroll)
        let pinnedDistance = AgentScrollFollow.distanceToBottom(contentHeight: contentHeight,
                                                                viewportHeight: viewportHeight,
                                                                offsetFromTop: pinnedOffset)
        print("🧪 ③ 铺满后：内容 \(contentHeight)pt / 视口 \(viewportHeight)pt / 偏移 \(pinnedOffset)pt"
              + "（最大 \(maxOffset)pt）⇒ 距底 \(pinnedDistance)pt"
              + " / flipped \(scroll.documentView?.isFlipped ?? true)")

        // ① 贴底态：再来一段 ⇒ 偏移跟到底（距底 0）。
        harness.text += thinkingLine(31)
        live.pump(0.1)
        let followedOffset = offsetFromTop(scroll)
        let followedDistance = AgentScrollFollow.distanceToBottom(contentHeight: scroll.documentView?.bounds.height ?? 0,
                                                                  viewportHeight: viewportHeight,
                                                                  offsetFromTop: followedOffset)
        print("🧪 ③ 贴底态新增一段：偏移 \(followedOffset)pt ⇒ 距底 \(followedDistance)pt")
        XCTAssertLessThan(followedDistance, 1,
                          "贴着底时新增内容没跟到底（距底 \(followedDistance)pt）⇒ 自动跟随坏了")

        // ② 模拟**用户上滚**：走 NSClipView 的真滚动接口（不是改 `@State` 骗自己）。
        let topOrigin = (scroll.documentView?.isFlipped ?? true) ? 0 : maxOffset
        scroll.contentView.scroll(to: NSPoint(x: 0, y: topOrigin))
        scroll.reflectScrolledClipView(scroll.contentView)
        live.pump(0.1)
        let userOffset = offsetFromTop(scroll)
        let userDistance = AgentScrollFollow.distanceToBottom(contentHeight: scroll.documentView?.bounds.height ?? 0,
                                                              viewportHeight: viewportHeight,
                                                              offsetFromTop: userOffset)
        print("🧪 ③ 用户上滚后：偏移 \(userOffset)pt ⇒ 距底 \(userDistance)pt")

        // ③ 上滚态再来三段 ⇒ **偏移一动不动**（跟随停手）。
        for index in 32..<35 { harness.text += thinkingLine(index) }
        live.pump(0.1)
        let afterUserScroll = offsetFromTop(scroll)
        print("🧪 ③ 上滚态新增三段：偏移 \(userOffset)pt → \(afterUserScroll)pt"
              + (abs(afterUserScroll - userOffset) < 0.5 ? " ⇒ 停手 ✅" : " ⇒ 被拽回底部 ❌"))
        XCTAssertEqual(afterUserScroll, userOffset, accuracy: 0.5,
                       "用户往上翻之后偏移从 \(userOffset)pt 变成 \(afterUserScroll)pt ⇒ 自动跟随在抢控制权")
    }

    // MARK: - ④ 三态切换只取两档高度

    @MainActor
    func testTriStateSwitchSamplesOnlyTwoHeights() {
        let harness = Harness(text: (0..<20).map { thinkingLine($0) }.joined(),
                              phase: .running, manual: nil)
        let live = host(AnyView(HarnessView(model: harness)))
        defer { live.window.contentView = nil }

        var samples: [CGFloat] = []
        func observe(_ label: String) {
            var local: [CGFloat] = []
            for _ in 0..<6 {   // 6 拍 ≈ 100ms —— 有动画的话这段时间里一定落在中间值
                let height = sampleHeight(live)
                local.append(height)
                samples.append(height)
            }
            print("🧪 ④ \(label)：采样 \(local.map { Int($0.rounded()) })")
        }

        observe("运行中（默认展开）")
        harness.phase = .finished          // 终态 ⇒ 自动折一行
        observe("终态（自动折一行）")
        harness.manual = true              // 手动展开 ⇒ sticky
        observe("终态 + 手动展开")
        harness.manual = false             // 手动收起
        observe("终态 + 手动收起")
        harness.phase = .running
        harness.manual = nil
        observe("回到运行中")

        let allowed = [AgentThinkingViewport.totalHeight, AgentThinkingViewport.collapsedHeight]
        let strays = samples.filter { value in !allowed.contains { abs($0 - value) <= 0.5 } }
        let unique = Set(samples.map { Int($0.rounded()) }).sorted()
        print("🧪 ④ 三态来回切：采样 \(samples.count) 次，取到的档位 \(unique)pt"
              + (strays.isEmpty ? " ⇒ 只有两档 ✅" : " ⇒ 中间值 \(strays) ❌"))
        XCTAssertTrue(strays.isEmpty, "三态切换采到中间高度 \(strays) ⇒ 高度在逐帧插值（有动画）")
        XCTAssertEqual(unique, [20, 200], "取到的档位 \(unique) ≠ 只有 20 / 200")

        // 反例④：**同一套判据**喂一条「正在插值」的样本序列（200 → 168 → 92 → 20）⇒ 必须判红。
        //
        // 为什么不真挂一个 `.animation` 控件来当反例：离屏宿主**没有 display link**，
        // `.animation` 会直接跳到终态（实测 6 拍全是 20）—— 那会让反例「假绿」，
        // 反而证明不了判据。插值在真机上确实存在（每帧一个中间高度），所以这里在
        // **判据函数**上验：中间值一旦出现，同一套判据就要报红。
        let interpolating: [CGFloat] = [200, 168, 92, 40, 20]
        let midSamples = interpolating.filter { value in !allowed.contains { abs($0 - value) <= 0.5 } }
        print("🧪 反例④（一条正在插值的样本序列 \(interpolating.map { Int($0) })）：中间值 \(midSamples.count) 个 ⇒ "
              + (midSamples.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(midSamples.isEmpty, "插值样本判据抓不到 ⇒ ④ 的判据没有牙齿")
    }
}
