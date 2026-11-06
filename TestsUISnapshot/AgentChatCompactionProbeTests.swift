import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「对话区被顶爆」这一族的 **App 侧探针（第二片：This task 卡 + Applied 行）**。
///
/// ## 这两条真机缺陷（2026-11-06，人类主人原话）
///
/// 1. 「This task 这个区域的高度越来越高，按设计是只能保持最多 2 行」；
/// 2. 「会话界面的执行脚本命令的 Applied 三行是什么东西，而且占用的区域越来越多，
///    让 thinking 区域越来越少」。
///
/// 上一片（`AgentChatStepListProbeTests`）只钉住了「展开 + 几百步不许超过 168pt」，
/// 没钉住**设计要求**：This task 卡收起态最多 2 行。于是跑起来照样长到 12 行。
/// 而每张 `.applied` 工具卡在对话区各占三行（`✓ ▸ 命令` / `⎿ applied` / `Applied ⟲`），
/// 20 个文件 = 60 行，页面又自动滚到底 ⇒ thinking 那块可视高度被挤没。
///
/// ## 判据（能判红）
///
/// ① **This task 卡 ≤ 2 行**：50 步时整块理想高 = `AgentStepListPanel.collapsedHeight`（≈ 80pt，
///    表头 20 + 2 行 × 20 + 间距 + 内边距），且 3 / 50 / 300 步三档**逐点相同**；
/// ② **Applied 默认 1 行**：20 张 `.applied` 卡合并成一行摘要，理想高 = `summaryHeight`（20pt）；
///    点开（`expanded: true`）时明细有上限，且**与卡片数无关**（20 与 60 张一样高）；
/// ③ **thinking 区稳定**：真 `AgentChatView`（900×620）挂 50 步 + 20 张 applied 卡时，
///    对话区（转写视口 = thinking / 正文所在的那一格）高度 ≥ `thinkingFloor`，且与
///    「3 步 + 0 张卡」的基线**逐点相同**；
/// ④ **反例必须判红**：同一套判据函数喂给「去掉上限」的缺陷形态夹具（全部行平铺 /
///    20 张卡各三行）必须报红 —— 否则上面三条只是「刚好量到绿」。
///
/// ## 边界（如实登记）
///
/// · SwiftUI `Text` 在这台宿主里不落成 `NSTextField`（`ExecutionReceiptPaneProbeTests` 同一条边界），
///   所以判据量的是**容器 frame**（视口 / 输入框 / 面板理想高），不是文字本身；
/// · 折叠动作是 SwiftUI `Button`（不落 `NSButton`，见 `DialogActionRowProbeTests`）⇒ 展开态用
///   `initialStepsExpanded:` / `expanded: .constant(true)` 挂起来，不靠合成鼠标事件；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑。
final class AgentChatCompactionProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    /// 判据用的量级：50 步 + 20 张已应用卡（真机截图那种形状）。
    static let probeSteps = 50
    static let probeApplied = 20
    /// 对话区（thinking / 正文所在视口）的可视高度下限。620 高的页面里留这么多才算「看得见」。
    static let thinkingFloor: CGFloat = 240

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "对话区压缩探针要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    private func steps(_ count: Int) -> [AgentChatStep] {
        (0..<count).map { index in
            AgentChatStep(index: index + 1,
                          status: index == count - 1 ? .running : .done,
                          tools: ["search", "list_dir", "read_file"])
        }
    }

    private func counter(for count: Int) -> AgentStepCounter {
        AgentStepCounter(executed: max(0, count - 1), budget: AgentLoopLimits.defaultMaxSteps)
    }

    /// `count` 张 `.applied` 卡（一次批量写入的形状：命令名 + 参数）。
    private func appliedCards(_ count: Int) -> [AgentToolCard] {
        (0..<count).map { index in
            AgentToolCard(name: "write_file",
                          arguments: "Sources/Feature\(index).swift",
                          outcome: .applied(fingerprint: "sha\(index)"))
        }
    }

    private func state(stepCount: Int, appliedCount: Int) -> AgentChatState {
        AgentChatState(messages: [
            .init(role: .user, text: "把 TODO 都清掉。"),
            .init(role: .assistant, text: "先扫一遍。")
        ],
                       cards: appliedCards(appliedCount),
                       steps: steps(stepCount),
                       endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"),
                       isRunning: true)
    }

    // MARK: - 判据函数（真实测量与反例测量**共用同一套**，这样反例能证明它真的能判红）

    /// ① This task 卡：≤ 2 行高（`AgentStepListPanel.collapsedHeight`）。
    static func taskCardViolations(height: CGFloat) -> [String] {
        var issues: [String] = []
        let limit = AgentStepListPanel.collapsedHeight
        if height > limit + 0.5 {
            issues.append("This task 卡高 \(height)pt > 上限 \(limit)pt（= 表头 1 行 + 2 行 × \(AgentStepListPanel.rowHeight)pt）")
        }
        return issues
    }

    /// ② Applied 摘要行：默认只占 1 行（`AgentAppliedSummaryRow.summaryHeight`）。
    static func appliedDefaultViolations(height: CGFloat) -> [String] {
        var issues: [String] = []
        let limit = AgentAppliedSummaryRow.summaryHeight
        if height > limit + 0.5 {
            issues.append("Applied 默认高 \(height)pt > 一行 \(limit)pt")
        }
        return issues
    }

    /// ②' Applied 明细：展开也有上限（`summaryHeight` + 间距 + `detailMaxHeight`）。
    static func appliedExpandedViolations(height: CGFloat) -> [String] {
        var issues: [String] = []
        let limit = AgentAppliedSummaryRow.summaryHeight + AgentAppliedSummaryRow.detailMaxHeight + Spacing.hair
        if height > limit + 0.5 {
            issues.append("Applied 展开高 \(height)pt > 上限 \(limit)pt ⇒ 明细没有高度上限")
        }
        return issues
    }

    /// ③ thinking 区（转写视口）：不得低于下限。
    static func thinkingViolations(viewport: CGFloat) -> [String] {
        var issues: [String] = []
        if viewport < thinkingFloor {
            issues.append("对话区可视高 \(viewport)pt < 下限 \(thinkingFloor)pt ⇒ thinking / 正文被挤没")
        }
        return issues
    }

    // MARK: - ① This task 卡 = 最多 2 行

    @MainActor
    private func panelHeight(stepCount: Int, expanded: Bool) -> CGFloat {
        let panel = AgentStepListPanel(steps: steps(stepCount),
                                       counter: counter(for: stepCount),
                                       isRunning: true,
                                       elapsedSeconds: 12.3,
                                       expanded: .constant(expanded))
            .frame(width: Self.pageSize.width)
        let hosting = NSHostingView(rootView: panel)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 2000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    func testThisTaskCardKeepsTwoRowsAt50Steps() {
        let few = panelHeight(stepCount: 3, expanded: false)
        let many = panelHeight(stepCount: Self.probeSteps, expanded: false)
        let more = panelHeight(stepCount: 300, expanded: false)
        let limit = AgentStepListPanel.collapsedHeight
        print("🧪 This task 卡理想高（收起）：3 步 \(few)pt / 50 步 \(many)pt / 300 步 \(more)pt"
              + "（设计上限 2 行 = \(limit)pt = 表头 \(AgentStepListPanel.headerHeight) + 2×\(AgentStepListPanel.rowHeight)"
              + " + 间距 + 内边距）")

        XCTAssertGreaterThan(many, 0, "面板在宿主里量出来是 0 高 —— 夹具没挂上，这一条判的是空")
        XCTAssertEqual(many, limit, accuracy: 0.5,
                       "50 步的 This task 卡高 \(many)pt ≠ \(limit)pt ⇒ 没有按设计钉在 2 行")
        XCTAssertEqual(more, many, accuracy: 0.5,
                       "3 位数量级的步数变化（\(Self.probeSteps) → 300）让卡高从 \(many)pt 变成 \(more)pt ⇒ 会随步数长高")
        XCTAssertTrue(Self.taskCardViolations(height: many).isEmpty,
                      Self.taskCardViolations(height: many).joined(separator: "；"))

        // 展开态仍然有界（明细在内部滚），且与步数无关。
        let expandedMany = panelHeight(stepCount: Self.probeSteps, expanded: true)
        let expandedMore = panelHeight(stepCount: 300, expanded: true)
        print("🧪 This task 卡理想高（展开）：50 步 \(expandedMany)pt / 300 步 \(expandedMore)pt"
              + "（上限 \(AgentStepListPanel.expandedMaxHeight)pt）")
        XCTAssertLessThanOrEqual(expandedMany, AgentStepListPanel.expandedMaxHeight + 0.5,
                                 "展开 50 步量到 \(expandedMany)pt，超过上限 \(AgentStepListPanel.expandedMaxHeight)pt ⇒ 展开没有高度上限")
        XCTAssertEqual(expandedMore, expandedMany, accuracy: 0.5,
                       "展开态 50 步（\(expandedMany)pt）与 300 步（\(expandedMore)pt）不同高 ⇒ 展开态随步数长高")
    }

    // MARK: - ② Applied：默认一行、明细有上限

    @MainActor
    private func appliedHeight(cardCount: Int, expanded: Bool) -> CGFloat {
        let row = AgentAppliedSummaryRow(cards: appliedCards(cardCount),
                                         expanded: .constant(expanded),
                                         onUndo: { _ in })
            .frame(width: Self.pageSize.width)
        let hosting = NSHostingView(rootView: row)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 2000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    func testAppliedIsOneLineByDefault() {
        let few = appliedHeight(cardCount: 1, expanded: false)
        let many = appliedHeight(cardCount: Self.probeApplied, expanded: false)
        let more = appliedHeight(cardCount: 60, expanded: false)
        print("🧪 Applied 摘要理想高（收起）：1 张 \(few)pt / \(Self.probeApplied) 张 \(many)pt / 60 张 \(more)pt"
              + "（一行 = \(AgentAppliedSummaryRow.summaryHeight)pt）")

        XCTAssertGreaterThan(many, 0, "Applied 摘要在宿主里量出来是 0 高 —— 夹具没挂上")
        XCTAssertEqual(many, AgentAppliedSummaryRow.summaryHeight, accuracy: 0.5,
                       "20 张已应用卡的摘要高 \(many)pt ≠ 一行 \(AgentAppliedSummaryRow.summaryHeight)pt"
                           + " ⇒ 默认不是一行（真机上就是那串三行）")
        XCTAssertEqual(more, many, accuracy: 0.5,
                       "卡数 20 → 60 让摘要高从 \(many)pt 变成 \(more)pt ⇒ 这一块会随写入次数长高")
        XCTAssertTrue(Self.appliedDefaultViolations(height: many).isEmpty,
                      Self.appliedDefaultViolations(height: many).joined(separator: "；"))

        let expandedMany = appliedHeight(cardCount: Self.probeApplied, expanded: true)
        let expandedMore = appliedHeight(cardCount: 60, expanded: true)
        let cap = AgentAppliedSummaryRow.summaryHeight + AgentAppliedSummaryRow.detailMaxHeight + Spacing.hair
        print("🧪 Applied 明细理想高（展开）：\(Self.probeApplied) 张 \(expandedMany)pt / 60 张 \(expandedMore)pt（上限 \(cap)pt）")
        XCTAssertLessThanOrEqual(expandedMany, cap + 0.5,
                                 "展开 \(Self.probeApplied) 张量到 \(expandedMany)pt，超过上限 \(cap)pt ⇒ 明细没有高度上限")
        XCTAssertEqual(expandedMore, expandedMany, accuracy: 0.5,
                       "展开态 20 张（\(expandedMany)pt）与 60 张（\(expandedMore)pt）不同高 ⇒ 明细随条数长高")
        XCTAssertTrue(Self.appliedExpandedViolations(height: expandedMany).isEmpty,
                      Self.appliedExpandedViolations(height: expandedMany).joined(separator: "；"))
    }

    // MARK: - ③ 整页：thinking 区不被压缩

    @MainActor
    private struct PageReading {
        let composer: CGRect
        /// 对话区（转写滚动视口）在宿主坐标里那一格 —— thinking / 正文就在它里面。
        let transcriptViewport: CGRect
        /// 对话区**内容**高（滚动容器里那张文档视图的高）。
        ///
        /// 这才是「Applied 越堆越多、把 thinking 挤出可视区」的那个量：视口不会被内容挤小，
        /// 但内容一长，视口里就只剩最底下那串 Applied 行（页面又自动滚到底）。
        let transcriptContentHeight: CGFloat
        let fittingHeight: CGFloat
        let signature: String
    }

    @MainActor
    private func readPage(stepCount: Int, appliedCount: Int, expanded: Bool = false) throws -> PageReading {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "compaction-probe",
                                   state: state(stepCount: stepCount, appliedCount: appliedCount))
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model, initialStepsExpanded: expanded)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.2)
        defer { live.window.contentView = nil }

        _ = try? live.capture(name: "agent-compaction-\(stepCount)-\(appliedCount)-\(expanded ? "expanded" : "collapsed")")

        let fields = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTextField.self, in: live.hosting)
            .filter { $0.isEditable }
        let rects = fields.map { live.hosting.convert($0.bounds, from: $0) }
        let composer = try XCTUnwrap(rects.max(by: { $0.maxY < $1.maxY }),
                                     "整页里一个可编辑输入框都没取到 —— 输入区没落成真控件")

        // 转写区 = 面积最大的那个滚动容器（对话区是页面上唯一的滚动视口；`ScrollView` 在
        // 这台宿主里落成 `NSScrollView`，这是本文件能量到「对话区可视高 / 内容高」的唯一途径）。
        let scrolls = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
        print("🧪 滚动容器：\(scrolls.map { NSStringFromRect(live.hosting.convert($0.bounds, from: $0)) })")
        let transcript = try XCTUnwrap(
            scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }),
            "整页里一个滚动容器都没取到 —— 对话区没落成滚动视口"
        )
        let viewport = live.hosting.convert(transcript.bounds, from: transcript)
        let contentHeight = transcript.documentView?.bounds.height ?? transcript.bounds.height

        return PageReading(composer: composer,
                           transcriptViewport: viewport,
                           transcriptContentHeight: contentHeight,
                           fittingHeight: live.hosting.fittingSize.height,
                           signature: try live.signature())
    }

    @MainActor
    func testThinkingAreaSurvives50StepsAnd20AppliedCards() throws {
        let baseline = try readPage(stepCount: 3, appliedCount: 0)
        let heavy = try readPage(stepCount: Self.probeSteps, appliedCount: Self.probeApplied)
        let doubled = try readPage(stepCount: Self.probeSteps, appliedCount: Self.probeApplied * 3)
        let sameStepsNoCards = try readPage(stepCount: Self.probeSteps, appliedCount: 0)

        print("🧪 基线（3 步 / 0 张卡）：对话区 \(NSStringFromRect(baseline.transcriptViewport))"
              + " / 内容高 \(baseline.transcriptContentHeight)pt / 输入框 \(NSStringFromRect(baseline.composer))"
              + " / 理想高 \(baseline.fittingHeight)pt")
        print("🧪 重载（\(Self.probeSteps) 步 / \(Self.probeApplied) 张卡）：对话区 \(NSStringFromRect(heavy.transcriptViewport))"
              + " / 内容高 \(heavy.transcriptContentHeight)pt / 输入框 \(NSStringFromRect(heavy.composer))"
              + " / 理想高 \(heavy.fittingHeight)pt（判据下限 \(Self.thinkingFloor)pt）")
        print("🧪 加码（\(Self.probeSteps) 步 / \(Self.probeApplied * 3) 张卡）：内容高 \(doubled.transcriptContentHeight)pt"
              + " / 理想高 \(doubled.fittingHeight)pt")
        print("🧪 对照（\(Self.probeSteps) 步 / 0 张卡）：内容高 \(sameStepsNoCards.transcriptContentHeight)pt")

        XCTAssertGreaterThan(heavy.transcriptViewport.height, 0, "对话区视口高 0 ⇒ 没量到滚动视口")
        XCTAssertTrue(Self.thinkingViolations(viewport: heavy.transcriptViewport.height).isEmpty,
                      Self.thinkingViolations(viewport: heavy.transcriptViewport.height).joined(separator: "；"))
        XCTAssertEqual(heavy.transcriptViewport.height, baseline.transcriptViewport.height, accuracy: 0.5,
                       "对话区可视高从 \(baseline.transcriptViewport.height)pt 变成 \(heavy.transcriptViewport.height)pt"
                           + " ⇒ This task 卡 / Applied 行在挤 thinking 区")
        XCTAssertEqual(heavy.composer.minY, baseline.composer.minY, accuracy: 0.5,
                       "输入框被推到 \(heavy.composer.minY)pt（基线 \(baseline.composer.minY)pt）⇒ 下面那块把布局顶开了")

        // **Applied 不许随写入次数增长**：20 张与 60 张的对话区内容高逐点相同。
        XCTAssertEqual(doubled.transcriptContentHeight, heavy.transcriptContentHeight, accuracy: 0.5,
                       "已应用卡从 \(Self.probeApplied) 张加到 \(Self.probeApplied * 3) 张，对话区内容高从 "
                           + "\(heavy.transcriptContentHeight)pt 变成 \(doubled.transcriptContentHeight)pt"
                           + " ⇒ 这一块还在随写入次数堆（真机上就是把 thinking 挤没的那串三行）")
        // 20 张卡相对 0 张卡，只许多出一行摘要（+ 一个块间距）。
        let extra = heavy.transcriptContentHeight - sameStepsNoCards.transcriptContentHeight
        print("🧪 Applied 在对话区里占的高度：20 张比 0 张多 \(extra)pt（一行摘要 = "
              + "\(AgentAppliedSummaryRow.summaryHeight)pt）")
        XCTAssertLessThanOrEqual(extra, AgentAppliedSummaryRow.summaryHeight + Spacing.xs,
                                 "20 张已应用卡让对话区内容高多出 \(extra)pt（> 一行摘要 "
                                     + "\(AgentAppliedSummaryRow.summaryHeight)pt）⇒ 默认不是一行摘要")

        // 整页**理想高**不是等式判据（它是内容理想尺寸之和）；只判它**没被撑出窗口**。
        for (label, reading) in [("基线", baseline), ("重载", heavy), ("加码", doubled)] {
            XCTAssertLessThanOrEqual(reading.fittingHeight, Self.pageSize.height + 1,
                                     "\(label)态整页理想高 \(reading.fittingHeight)pt 超过窗口 \(Self.pageSize.height)pt ⇒ 页面被内容撑开")
            XCTAssertGreaterThanOrEqual(reading.transcriptViewport.minY, -0.5, "\(label)态：对话区跑到可视区上沿之外")
            XCTAssertLessThanOrEqual(reading.transcriptViewport.maxY, Self.pageSize.height + 0.5,
                                     "\(label)态：对话区被顶出可视区下沿")
        }
    }

    // MARK: - ④ 反例：同一套判据喂给「去掉上限」的缺陷形态，必须报红

    /// 缺陷形态 ①：This task 卡的**旧写法** —— 所有步骤行平铺在 `VStack` 里，无上限、无滚动。
    private struct UnboundedStepList: View {
        let steps: [AgentChatStep]
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text("This task · \(steps.count) steps")
                    .font(Theme.font(.mono))
                    .frame(height: AgentStepListPanel.headerHeight)
                ForEach(steps) { step in
                    Text("├─ " + step.tools.joined(separator: " · "))
                        .font(Theme.font(.mono))
                        .frame(height: AgentStepListPanel.rowHeight)
                }
            }
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 缺陷形态 ②：Applied 的**旧写法** —— 每张卡三行、全部平铺。
    private struct UnboundedAppliedList: View {
        let cards: [AgentToolCard]
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(cards) { card in
                    Text("✓ ▸ \(card.name)(\(card.arguments))").font(Theme.font(.mono))
                    Text("⎿ applied").font(Theme.font(.mono))
                    Text("Applied ⟲").font(Theme.font(.mono))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor
    private func fittingHeight<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: Self.pageSize.width))
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 4000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    func testCounterExamplesAreRed() {
        // ① This task 卡去掉「2 行上限」⇒ 判据必须报红。
        let unboundedPanel = fittingHeight(UnboundedStepList(steps: steps(Self.probeSteps)))
        let panelIssues = Self.taskCardViolations(height: unboundedPanel)
        print("🧪 反例①（无上限 This task 卡，\(Self.probeSteps) 步）：\(unboundedPanel)pt / 上限 "
              + "\(AgentStepListPanel.collapsedHeight)pt ⇒ \(panelIssues.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(panelIssues.isEmpty,
                       "把 2 行上限去掉（\(Self.probeSteps) 步平铺成 \(unboundedPanel)pt）判据仍然绿 ⇒ 判据没有牙齿")

        // ② Applied 恢复成「每张卡三行、无限制」⇒ 判据必须报红。
        let unboundedApplied = fittingHeight(UnboundedAppliedList(cards: appliedCards(Self.probeApplied)))
        let appliedIssues = Self.appliedDefaultViolations(height: unboundedApplied)
        print("🧪 反例②（旧 Applied 三行 × \(Self.probeApplied) 张）：\(unboundedApplied)pt / 一行上限 "
              + "\(AgentAppliedSummaryRow.summaryHeight)pt ⇒ \(appliedIssues.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(appliedIssues.isEmpty,
                       "Applied 恢复成多行（\(unboundedApplied)pt）判据仍然绿 ⇒ 判据没有牙齿")

        // ③ thinking 区：把「被顶爆」的量直接喂进 thinking 判据 ⇒ 必须报红。
        let squeezed = Self.thinkingViolations(viewport: 40)
        print("🧪 反例③（对话区只剩 40pt）：\(squeezed.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(squeezed.isEmpty, "对话区只剩 40pt 判据仍然绿 ⇒ thinking 区的判据没有牙齿")
    }
}
