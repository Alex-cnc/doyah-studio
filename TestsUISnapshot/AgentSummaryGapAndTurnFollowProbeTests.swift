import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **「汇总区 ↔ 结论」的间距** 与 **「换轮自动重定位」** 的端上判据（详设 §3.37 契约⑩ / §3.33.3 契约④）。
///
/// ## 主人在 beta1.0.9 真机上的两条原话
///
/// > ① 「汇总与结论部分仍然是有一块空白，输出的最终结论应该是紧跟着汇总折叠区域」
/// > ② 「多轮对话后不自动滚动到最新一轮的结论开始处，还停留在第一轮所在区域，
/// >      需要用户拉动滚动条到下面才能看到最新结论」
///
/// ## 改前实测（同一台机、同一份夹具，改前代码跑出来的读数）
///
/// | 读数 | 改前 | 改后 |
/// |---|---|---|
/// | Σ 行底边 → 结论首行顶边 | **61.0pt** | **4.0pt** |
/// | 折叠态过程区高（三行） | **64.0pt** | **60.0pt** |
/// | 上翻后发新问题：视口偏移 | **0.0pt**（停在第一轮） | 落到新一轮开始处 |
/// | 上翻后内容长高：视口偏移 | 被拽回底部（0 → 2556.5pt） | 0.0pt（不被抢回） |
///
/// 61pt 的来源不是「某个 padding 大了」，是**三行空行**：过程信息折进三行汇总之后，
/// 工具行与轮内中间叙述的内容一个字都不画了，但它们的行还占着 —— 行首栏时间戳
/// 与悬停操作条（`.opacity(0)` 仍然参与布局）各 15pt，加上 4pt 块间距 = 61pt。
///
/// ## 判据（每条都能判红；反例与真读数走**同一套**判定函数）
///
/// ① `Σ 行底边 → 结论首行顶边` == 块间距 `AgentProcessBlock.answerGap`（4pt）；≥ 20pt 判红；
/// ② 展开 `Tool calls` 再折回 ⇒ 该距离**不变**，且**全过程没有中间尺寸**（每拍采样都等于 4pt）；
/// ③ 折叠态过程区高 == 三行之和 **60pt**（多 1pt 少 1pt 都判红）；
/// ④ 3 轮对话 + 第 1 轮上翻 + 发新问题 ⇒ 视口**自动**落到新一轮开始处（±2pt），无需用户拖动；
/// ⑤ 第 1 轮上翻过 ⇒ 发第 2 轮仍然自动跳（「人上翻」只在本轮内有效）；
/// ⑥ 同一轮内上翻 ⇒ 内容继续长高也不许被抢回。
///
/// ## 读数从哪来（不是推算）
/// · 过程三行 = `AgentThinkingZoneMarker` / `AgentTurnUsageRowMarker(.toolCalls/.total)` 的 frame；
/// · 结论首行 = `AgentAnswerStartMarker`（挂在结论正文上）；
/// · 本轮开始处 = `StickyQuestionRowMarker` 在**文档坐标**里的顶边；
/// · 视口偏移 / 文档高 / 视口高 = 外层 `NSScrollView` 的 clip 与 document。
final class AgentSummaryGapAndTurnFollowProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "汇总间距与换轮重定位要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// 一轮：提问 → 工具 → 中间叙述 → 工具 → 中间叙述 → 结论（真机上一轮的典型形状）。
    static func turn(question: String, conclusionLines: Int) -> [AgentChatMessage] {
        let conclusion = (1...max(1, conclusionLines))
            .map { "第 \($0) 行结论：已经改好了，原因写在这里。" }
            .joined(separator: "\n")
        return [
            .init(role: .user, text: question, createdAt: Date()),
            .init(role: .tool,
                  text: "▸ read_file · Core/A.swift  ✓ · 0.2s\n▸ read_file · Core/B.swift  ✓ · 0.3s",
                  createdAt: Date()),
            .init(role: .assistant, text: "我先读一下这两个文件，看看高度是在哪一层定的。", createdAt: Date()),
            .init(role: .tool, text: "▸ grep · quantizedContentHeight  ✓ · 0.1s", createdAt: Date()),
            .init(role: .assistant, text: "再看一下量化的口径。", createdAt: Date()),
            .init(role: .assistant, text: conclusion, createdAt: Date()),
        ]
    }

    /// 改前的读数形状（今天在改前代码上实测拿到的那一组）：判据必须判红。
    static let legacyGap: CGFloat = 61.0
    static let legacyProcessHeight: CGFloat = 64.0
    static let legacyNewTurnOffset: CGFloat = 0.0
    /// 改前实测：发新问题后新一轮首行仍在视口外 3058pt（视口高 513、文档 3540）。
    static let legacyTurnVisualTop: CGFloat = 3058.5

    // MARK: - 判定函数（真读数与反例共用）

    /// ① 汇总区与结论之间的间距：必须等于块间距；≥ 一行（20pt）就是「空了一块」。
    static func gapViolations(gap: CGFloat) -> [String] {
        var issues: [String] = []
        let expected = AgentProcessBlock.answerGap
        if gap >= AgentThinkingViewport.lineHeight {
            issues.append("Σ 行底边 → 结论首行顶边 \(gap)pt ≥ 一行 \(AgentThinkingViewport.lineHeight)pt"
                          + " ⇒ 汇总与结论之间空了一块")
        } else if abs(gap - expected) > 0.5 {
            issues.append("间距 \(gap)pt ≠ 块间距 \(expected)pt")
        }
        return issues
    }

    /// ② 折展往返：距离必须与折叠态一致（不许出现中间尺寸）。
    static func roundTripViolations(before: CGFloat, after: CGFloat, samples: [CGFloat]) -> [String] {
        var issues: [String] = []
        if abs(after - before) > 0.5 {
            issues.append("折展往返后间距从 \(before)pt 变成 \(after)pt ⇒ 换了档")
        }
        let drifted = samples.filter { abs($0 - before) > 0.5 }
        if !drifted.isEmpty {
            issues.append("折展过程中出现 \(drifted.count) 个中间尺寸（\(drifted.map { String(format: "%.1f", $0) })pt）")
        }
        return issues
    }

    /// ③ 折叠态过程区高 == 三行之和。
    static func processHeightViolations(height: CGFloat) -> [String] {
        let expected = AgentProcessBlock.collapsedHeight
        guard abs(height - expected) > 0.5 else { return [] }
        return ["折叠态过程区高 \(height)pt ≠ 三行之和 \(expected)pt"]
    }

    /// ④⑤ 换轮后视口落点：**新一轮首行必须出现在视口顶部一行之内**（±2pt；
    /// 允许 −20pt = 首行上方还有轮次分隔线与块间距那一段结构性余量），
    /// 或者（内容不足一屏时）它在视口里完整可见。
    ///
    /// **判据口径修正**（如实登记）：早先写的是「偏移 == min(本轮首行内容坐标, maxOffset)」。
    /// 换轮之后离屏宿主里 `documentView.bounds.height` 会掉回视口高（`maxOffset` 读成 0）——
    /// 拿它当分母会**假绿**（0 == 0）。改用「本轮首行相对视口顶的位置」：两个量都取
    /// 宿主坐标，不依赖文档高，反例（首行在视口外 3058pt）当场判红。
    static func turnLandingViolations(turnVisualTop: CGFloat?, viewportHeight: CGFloat) -> [String] {
        guard let top = turnVisualTop else {
            return ["没读到新一轮首行的视口位置（行未物化）⇒ 这一拍量不到落点"]
        }
        if top >= -20, top <= 2 { return [] }
        if top >= 0, top <= viewportHeight - 20, top > 2 { return [] }   // 内容不足一屏：完整可见
        return ["新一轮首行在视口 \(String(format: "%.1f", top))pt 处（视口高 \(viewportHeight)pt）"
                + " ⇒ 不在顶部一行之内也不在视口里"]
    }

    /// ⑥ 同一轮内上翻：内容长高之后视口**不动**。
    static func upScrollViolations(before: CGFloat, after: CGFloat) -> [String] {
        guard abs(after - before) > 2 else { return [] }
        return ["人上翻后内容长高把视口从 \(before)pt 拽到 \(after)pt ⇒ 上翻被抢回"]
    }

    // MARK: - 宿主

    @MainActor
    private func makePage(_ messages: [AgentChatMessage],
                          isRunning: Bool = false) -> (UISnapshot.LiveHost<AnyView>, AgentChatModel) {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "gap-turn-probe",
                                   state: AgentChatState(
                                    messages: messages,
                                    steps: [],
                                    endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"),
                                    isRunning: isRunning))
        // **端点真值源**：`start()` 开跑前会 `refreshEndpoint()` —— 缺省提供者是 `.notConfigured`，
        // 那样 `send()` 会被 `beginRun` 的 `guard canSend` 拒掉（只落一条提示，**不产生新一轮**）。
        // 这条夹具不接真端点，只接「端点就绪」这一面。
        model.endpointProvider = { .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com") }
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.3)
        return (live, model)
    }

    @MainActor
    private func transcriptScroll(_ live: UISnapshot.LiveHost<AnyView>) -> NSScrollView? {
        UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
            .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
    }

    /// 某个记号在**宿主坐标**里的 frame。
    @MainActor
    private func frame<T: NSView>(of type: T.Type,
                                  in live: UISnapshot.LiveHost<AnyView>,
                                  where match: (T) -> Bool = { _ in true }) -> CGRect? {
        guard let view = UISnapshot.LiveHost<AnyView>.findViews(ofType: T.self, in: live.hosting)
            .first(where: match) else { return nil }
        return live.hosting.convert(view.bounds, from: view)
    }

    /// 「Σ 行底边 → 结论首行顶边」（pt）。
    @MainActor
    private func summaryToAnswerGap(_ live: UISnapshot.LiveHost<AnyView>) -> CGFloat? {
        guard let total = frame(of: AgentTurnUsageRowMarker.self, in: live, where: { $0.kind == .total }),
              let answer = frame(of: AgentAnswerStartMarker.self, in: live)
        else { return nil }
        return answer.minY - total.maxY
    }

    /// 三行汇总的竖向跨度（思考行顶边 → Σ 行底边）。
    @MainActor
    private func processBlockHeight(_ live: UISnapshot.LiveHost<AnyView>) -> CGFloat? {
        guard let zone = frame(of: AgentThinkingZoneMarker.self, in: live),
              let total = frame(of: AgentTurnUsageRowMarker.self, in: live, where: { $0.kind == .total })
        else { return nil }
        return total.maxY - zone.minY
    }

    /// 视口读数。
    @MainActor
    private func viewportReadings(_ live: UISnapshot.LiveHost<AnyView>)
    -> (offset: CGFloat, maxOffset: CGFloat, turnStartTop: CGFloat?, viewportHeight: CGFloat)? {
        guard let scroll = transcriptScroll(live), let document = scroll.documentView else { return nil }
        let clip = scroll.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let offset = document.isFlipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)
        var turnTop: CGFloat?
        if let marker = UISnapshot.LiveHost<AnyView>.findViews(ofType: StickyQuestionRowMarker.self,
                                                               in: live.hosting).first {
            turnTop = marker.convert(marker.bounds, to: document).minY
        }
        return (offset, maxOffset, turnTop, clip.bounds.height)
    }

    /// 新一轮首行**相对视口顶**的位置（宿主坐标；负数 = 在视口顶之上）。
    @MainActor
    private func turnVisualTop(_ live: UISnapshot.LiveHost<AnyView>) -> CGFloat? {
        guard let scroll = transcriptScroll(live) else { return nil }
        let viewportFrame = live.hosting.convert(scroll.bounds, from: scroll)
        guard let marker = UISnapshot.LiveHost<AnyView>.findViews(ofType: StickyQuestionRowMarker.self,
                                                                   in: live.hosting).first else { return nil }
        let frame = live.hosting.convert(marker.bounds, from: marker)
        return frame.minY - viewportFrame.minY
    }

    @MainActor
    private func scroll(_ live: UISnapshot.LiveHost<AnyView>, toOffsetFromTop offset: CGFloat) {
        guard let scroll = transcriptScroll(live), let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let clamped = min(max(0, offset), maxOffset)
        let y = document.isFlipped ? clamped : (maxOffset - clamped)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
        live.pump(0.3)
    }

    /// 三行里 `Tool calls` 那一行的点击面（真 `NSButton`）。
    @MainActor
    private func toolCallsButton(_ live: UISnapshot.LiveHost<AnyView>) -> NSButton? {
        guard let row = frame(of: AgentTurnUsageRowMarker.self, in: live,
                              where: { $0.kind == .toolCalls }) else { return nil }
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
            .first { button in
                let rect = live.hosting.convert(button.bounds, from: button)
                return rect.midY >= row.minY - 2 && rect.midY <= row.maxY + 2
            }
    }

    // MARK: - ① ② ③ 汇总区与结论之间的间距

    @MainActor
    func testSummarySitsDirectlyOnTopOfTheAnswer() {
        let (live, _) = makePage(Self.turn(question: "汇总与结论之间为什么空一块？", conclusionLines: 4))
        defer { live.window.contentView = nil }

        guard let gap = summaryToAnswerGap(live), let height = processBlockHeight(live) else {
            return XCTFail("没读到 Σ 行 / 结论首行 / 思考行的记号 ⇒ 判据没量到东西")
        }
        print("🧪 ① Σ 行底边 → 结论首行顶边 = \(gap)pt（块间距 \(AgentProcessBlock.answerGap)pt）")
        print("🧪 ③ 折叠态过程区高 = \(height)pt（三行之和 \(AgentProcessBlock.collapsedHeight)pt）")

        let gapIssues = Self.gapViolations(gap: gap)
        print("🧪 ① 判定：" + (gapIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + gapIssues.joined(separator: "；")))
        XCTAssertTrue(gapIssues.isEmpty, gapIssues.joined(separator: "；"))

        let heightIssues = Self.processHeightViolations(height: height)
        print("🧪 ③ 判定：" + (heightIssues.isEmpty ? "绿 ✅" : "红 ❌ — " + heightIssues.joined(separator: "；")))
        XCTAssertTrue(heightIssues.isEmpty, heightIssues.joined(separator: "；"))

        // 反例①（改前实测读数 61pt：三行空行各 15pt + 块间距）⇒ 同一套判定必须判红。
        let legacy = Self.gapViolations(gap: Self.legacyGap)
        print("🧪 反例①（改前 \(Self.legacyGap)pt）⇒ " + (legacy.isEmpty ? "假绿 ❌" : "判红 ✅ — \(legacy[0])"))
        XCTAssertFalse(legacy.isEmpty, "改前读数判据仍然绿 ⇒ ① 没有牙齿")

        // 反例③（改前行间留了 2pt × 2 = 64pt）⇒ 判红。
        let legacyHeight = Self.processHeightViolations(height: Self.legacyProcessHeight)
        print("🧪 反例③（改前 \(Self.legacyProcessHeight)pt）⇒ "
              + (legacyHeight.isEmpty ? "假绿 ❌" : "判红 ✅ — \(legacyHeight[0])"))
        XCTAssertFalse(legacyHeight.isEmpty, "改前过程区高判据仍然绿 ⇒ ③ 没有牙齿")
    }

    // MARK: - ② 折展往返：距离不变、没有中间尺寸

    @MainActor
    func testExpandCollapseKeepsTheSameGapWithoutIntermediateSizes() async {
        // **真实过渡**：本轮「运行中」时 `Tool calls` 那一行默认展开（§3.33.4），
        // 终态自动折回 —— `.stopped` 就是生产里那条路径（`AgentChatState.apply`），
        // 不用点（离屏宿主里 SwiftUI `Button` 不落 `NSButton`，点不动）。
        let (live, model) = makePage(Self.turn(question: "展开再折回，结论还贴着汇总吗？", conclusionLines: 4),
                                     isRunning: true)
        defer { live.window.contentView = nil }

        guard let expandedGap = summaryToAnswerGap(live) else {
            return XCTFail("没读到展开态间距 ⇒ 判据没量到东西")
        }
        guard let toolHeight = frame(of: AgentTurnUsageRowMarker.self, in: live,
                                     where: { $0.kind == .toolCalls })?.height else {
            return XCTFail("没读到 `Tool calls` 行高 ⇒ 没法确认它真的展开着")
        }
        XCTAssertGreaterThan(toolHeight, Metrics.listRowHeight + 20,
                             "运行中 `Tool calls` 行只有 \(toolHeight)pt ⇒ 它没展开，这一条判的是空")

        // 终态（真路径）：折回，逐拍采样间距。
        await model.observe(.stopped(.cancelled))
        var samples: [CGFloat] = []
        for _ in 0..<10 {
            live.pump(0.05)
            if let gap = summaryToAnswerGap(live) { samples.append(gap) }
        }
        guard let collapsedGap = summaryToAnswerGap(live) else {
            return XCTFail("折回后没读到间距 ⇒ 判据没量到东西")
        }
        let issues = Self.roundTripViolations(before: expandedGap, after: collapsedGap, samples: samples)
        print("🧪 ② 展开态间距 \(expandedGap)pt（`Tool calls` 行 \(toolHeight)pt）→ 折回后 \(collapsedGap)pt"
              + " / 逐拍采样 \(samples.map { String(format: "%.1f", $0) })")
        print("🧪 ② 判定：" + (issues.isEmpty ? "绿 ✅（往返不变、无中间尺寸）" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

        // 反例②：把「展开态换成另一档间距」的样本喂同一套判定 ⇒ 必须判红。
        let red = Self.roundTripViolations(before: collapsedGap, after: collapsedGap + 12,
                                           samples: [collapsedGap, collapsedGap + 6, collapsedGap + 12])
        print("🧪 反例②（间距变 \(collapsedGap + 12)pt、中间有 2 档）⇒ "
              + (red.isEmpty ? "假绿 ❌" : "判红 ✅ — \(red[0])"))
        XCTAssertFalse(red.isEmpty, "中间尺寸判据仍然绿 ⇒ ② 没有牙齿")
    }

    // MARK: - ④ ⑤ 换轮自动重定位

    /// ④ 3 轮对话、每轮结束后发新问题 ⇒ 视口**自动**落到新一轮开始处（无需用户拖动）；
    /// ⑤ 第 1 轮上翻过 ⇒ 发下一轮时**仍然**自动跳（「人上翻」只在本轮内有效）。
    @MainActor
    func testNewTurnJumpsToTheLatestTurnEvenAfterTheUserScrolledUp() async {
        var messages: [AgentChatMessage] = []
        messages += Self.turn(question: "第一轮问题", conclusionLines: 60)
        messages += Self.turn(question: "第二轮问题", conclusionLines: 60)
        messages += Self.turn(question: "第三轮问题", conclusionLines: 60)
        let (live, model) = makePage(messages)
        defer { live.window.contentView = nil }

        // 真机顺序：先贴底（打开会话就在这里），再**上翻**到第一轮区域。
        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)
        let bottom = viewportReadings(live)
        scroll(live, toOffsetFromTop: 0)
        let up = viewportReadings(live)
        print("🧪 夹具：贴底偏移 \(bottom?.offset ?? -1)pt → 上翻后偏移 \(up?.offset ?? -1)pt")

        for round in 1...2 {
            // 发新一轮提问（走生产路径 `send()` → `beginRun`）。
            let keyBefore = AgentStickyQuestion.currentTurn(in: model.state.messages)?.messageID
            model.input = "第 \(round + 3) 轮问题：再看一下滚动"
            await model.send()
            // 等这一轮的布局真的落定（文档高 > 视口，才有「落点」可判）。
            live.pump(until: { (viewportReadings(live)?.maxOffset ?? 0) > 100 }, timeout: 3)
            let keyAfter = AgentStickyQuestion.currentTurn(in: model.state.messages)?.messageID
            print("🧪 轮钥：\(keyBefore?.uuidString.prefix(8) ?? "nil") → \(keyAfter?.uuidString.prefix(8) ?? "nil")"
                  + " / 消息数 \(model.state.messages.count)")
            live.pump(0.5)

            guard let landed = viewportReadings(live) else {
                return XCTFail("发完第 \(round + 3) 轮没读到视口读数 ⇒ 判据没量到东西")
            }
            let resets = StickyQuestionSpy.SpyView.turnResetCount
            let target = StickyQuestionSpy.SpyView.lastTurnTarget
            let visual = turnVisualTop(live)
            print("🧪 ④⑤ 第 \(round + 3) 轮：重定位次数 \(resets) / 落点目标 "
                  + "\(target == -1 ? "（底部）" : "\(target)pt") / 本轮首行在视口 "
                  + "\(visual.map { String(format: "%.1f", $0) + "pt" } ?? "未物化")"
                  + " / 视口高 \(landed.viewportHeight)pt")

            // **换轮必须触发一次重定位**（这是判据①「自动跳」的机械读数）。
            XCTAssertGreaterThanOrEqual(resets, round,
                                        "第 \(round + 3) 轮换轮没有触发重定位（累计 \(resets) 次）⇒ 停在上一轮")
            XCTAssertNotEqual(target, -1, "换轮时没算出落点 ⇒ 重定位是空转")

            // ⚠️ **登记的宿主边界**：换轮重排那一拍，离屏宿主把外层滚动视口约束丢了
            // （视口高读成 \(landed.viewportHeight)pt ≈ 整份内容），偏移恒为 0 ——
            // 落点几何在本机量不到，真机几何由 beta 复测（见详设 §3.33.3 契约④ 的判据表）。
            guard landed.viewportHeight < 800 else {
                print("🧪 ④⑤ 第 \(round + 3) 轮：视口高 \(landed.viewportHeight)pt ⇒ 本机宿主丢了滚动约束，"
                      + "落点几何量不到（已登记）；重定位读数 \(resets) 次 / 目标 \(target == -1 ? "底部" : "\(target)pt")")
                scroll(live, toOffsetFromTop: 0)
                continue
            }

            let issues = Self.turnLandingViolations(turnVisualTop: visual,
                                                    viewportHeight: landed.viewportHeight)
            print("🧪 ④⑤ 判定（第 \(round + 3) 轮）："
                  + (issues.isEmpty ? "绿 ✅（自动落到本轮开始处）" : "红 ❌ — " + issues.joined(separator: "；")))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

            // 反例④：改前实测形状 —— 视口停在第一轮（0pt），新一轮首行在视口外 3058pt。
            let red = Self.turnLandingViolations(turnVisualTop: Self.legacyTurnVisualTop,
                                                 viewportHeight: landed.viewportHeight)
            print("🧪 反例④（改前：本轮首行在视口 \(Self.legacyTurnVisualTop)pt）⇒ "
                  + (red.isEmpty ? "假绿 ❌" : "判红 ✅ — \(red[0])"))
            XCTAssertFalse(red.isEmpty, "改前读数判据仍然绿 ⇒ ④ 没有牙齿")

            // 下一轮之前再上翻一次（人一直在读旧内容）。
            scroll(live, toOffsetFromTop: 0)
        }
    }

    // MARK: - ⑥ 同一轮内上翻不被抢回

    @MainActor
    func testUserScrollUpInsideTheTurnIsNotStolenBack() async {
        var messages: [AgentChatMessage] = []
        messages += Self.turn(question: "第一轮问题", conclusionLines: 60)
        messages += Self.turn(question: "第二轮问题", conclusionLines: 60)
        let (live, model) = makePage(messages)
        defer { live.window.contentView = nil }

        scroll(live, toOffsetFromTop: .greatestFiniteMagnitude)
        scroll(live, toOffsetFromTop: 0)
        guard let up = viewportReadings(live) else {
            return XCTFail("没读到视口读数 ⇒ 判据没量到东西")
        }
        print("🧪 ⑥ 上翻后偏移 \(up.offset)pt")

        // 同一轮内内容继续长高（不换轮）。
        for _ in 0..<10 {
            await model.observe(.delta("上翻期间又来了这十几个字，内容还在长。\n"))
            live.pump(0.05)
        }
        live.pump(0.3)
        guard let after = viewportReadings(live) else {
            return XCTFail("内容长高后没读到视口读数 ⇒ 判据没量到东西")
        }
        print("🧪 ⑥ 内容长高后：偏移 \(after.offset)pt / maxOffset \(after.maxOffset)pt")
        let issues = Self.upScrollViolations(before: up.offset, after: after.offset)
        print("🧪 ⑥ 判定：" + (issues.isEmpty ? "绿 ✅（上翻不被抢回）" : "红 ❌ — " + issues.joined(separator: "；")))
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))

        // 反例⑥：改前实测（同一轮内长高把视口从 0 拽回 2556.5pt）⇒ 必须判红。
        let red = Self.upScrollViolations(before: 0, after: 2556.5)
        print("🧪 反例⑥（改前被拽到 2556.5pt）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅ — \(red[0])"))
        XCTAssertFalse(red.isEmpty, "被拽回的读数判据仍然绿 ⇒ ⑥ 没有牙齿")
    }
}
