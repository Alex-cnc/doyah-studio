import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「执行步骤详单」的 **App 侧探针**：量的是**真视图的 frame**，不是「看着还行」。
///
/// ## 这一行为什么要探针（2026-11-04 真机两条）
///
/// 人类主人点开输入框上方那块详单之后，整块工作区只剩一串 `search · search · list_dir · read_file…`
/// —— 对话区与输入框**都不见了**（原话：「点击了一下这个地方，界面全被执行步骤详单给撑爆了」）。
/// 根因是那一块既**没有高度上限**、也**没有内部滚动**：步数有多少，它就长多高，把下面的一切顶出去。
///
/// ## 判据（能判红）
///
/// ① **有上限**：展开态的详单在 300 步时的高度不超过 `AgentStepListPanel.maxHeight`（+ 表头那一行），
///    而且**3 步与 300 步一样高**（多出来的在内部滚，不外扩）；
/// ② **不撞开布局**：整页（真 `AgentChatView`，900×620）挂着 300 步、展开与收起两态，
///    **输入框那一格的位置与高度逐点相同**（±0.5pt），且完全落在可视区内 ——
///    这正是「输入框不见了」那条缺陷的机器判据；
/// ③ 收起态与展开态**不是同一个画面**（指纹不同）：证明这条口真的把状态换了，不是两次都挂在收起态上。
///
/// ## 边界（如实登记）
///
/// · 表头上那串 `95/150` 的**文字**读不回来（SwiftUI `Text` 在这台宿主里不落成 `NSTextField`，
///   与 `ExecutionReceiptPaneProbeTests` 文件头同一条边界）⇒ 计数器的判据在
///   `Tests/AgentStepCounterTests.swift`（纯值、可判红）；本文件只管**位置与高度**。
/// · 点表头那一下是 SwiftUI `Button`（不落 `NSButton`，见 `DialogActionRowProbeTests`）⇒
///   展开态靠 `AgentChatView(initialStepsExpanded:)` 这个口挂起来，不靠合成鼠标事件。
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑。
final class AgentChatStepListProbeTests: XCTestCase {

    /// 页面尺寸（夹具与判据共用一处定义）。
    static let pageSize = CGSize(width: 900, height: 620)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "详单探针要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// `count` 步：最后一跳还在跑，其余都已走完（与真跑起来时 `hopStarted` 逐步追加的形状一致）。
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

    @MainActor
    private func state(stepCount: Int) -> AgentChatState {
        AgentChatState(messages: [
            .init(role: .user, text: "把这几个文件里的 TODO 都清掉。"),
            .init(role: .assistant, text: "先扫一遍。")
        ],
                       steps: steps(stepCount),
                       endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"),
                       isRunning: true)
    }

    // MARK: - ① 详单有高度上限（3 步与 300 步一样高）

    /// 单挂`AgentStepListPanel`（真视图），量它的**理想高度**：`NSHostingView.fittingSize` 问的就是
    /// SwiftUI 自己排出来的高度 —— 没有上限时它等于「步数 × 行高」，有上限时被钉在 `maxHeight`。
    @MainActor
    private func panelFittingHeight(stepCount: Int) -> CGFloat {
        let panel = AgentStepListPanel(steps: steps(stepCount),
                                       counter: counter(for: stepCount),
                                       isRunning: true,
                                       elapsedSeconds: 12.3,
                                       expanded: .constant(true))
            .frame(width: Self.pageSize.width)
        let hosting = NSHostingView(rootView: panel)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 2000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    func testExpandedPanelIsHeightCappedAndScrollsInternally() {
        let few = panelFittingHeight(stepCount: 3)
        let many = panelFittingHeight(stepCount: 300)
        let more = panelFittingHeight(stepCount: 600)
        print("🧪 详单理想高度：3 步 \(few)pt / 300 步 \(many)pt / 600 步 \(more)pt（行体上限 \(AgentStepListPanel.maxHeight)pt）")

        XCTAssertGreaterThan(few, 0, "详单在宿主里量出来是 0 高 —— 夹具没挂上，这一条判的是空")
        // 高度上限 + 表头那一行：超过它就是「步数有多少、这一块长多高」。
        XCTAssertLessThanOrEqual(
            many, AgentStepListPanel.maxHeight + 48,
            "300 步的详单理想高度 \(many)pt 超过上限 \(AgentStepListPanel.maxHeight)pt（+表头一行 48pt）"
                + " ⇒ 没有高度上限"
        )
        // 命门：**再多一倍步数，高度一点不长**（多出来的在内部滚）。
        XCTAssertEqual(more, many, accuracy: 0.5,
                       "300 步（\(many)pt）与 600 步（\(more)pt）高度不同 ⇒ 多出来的步数没有被内部滚动吃掉")
        XCTAssertLessThan(few, many,
                          "3 步（\(few)pt）不比 300 步（\(many)pt）矮 —— 判据没量到内容的差别（夹具坏了？）")
    }

    // MARK: - ② 整页：展开 300 步之后输入框还在原位

    /// 整页挂载，返回：输入框在宿主坐标里的那一格 + 宿主理想高度 + 画面指纹。
    @MainActor
    private struct PageReading {
        let composer: CGRect
        let fittingHeight: CGFloat
        let signature: String
    }

    @MainActor
    private func readPage(expanded: Bool, stepCount: Int) throws -> PageReading {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "step-list-probe", state: state(stepCount: stepCount))
        let live = UISnapshot.LiveHost(
            AnyView(AgentChatView(model: model, initialStepsExpanded: expanded)
                .environmentObject(appState)
                .environmentObject(WorkspaceTabsModel())),
            size: Self.pageSize
        )
        live.settle()
        live.pump(0.2)
        defer { live.window.contentView = nil }

        // 取证：把这一面落一张图（人眼复核用；判据不靠图，靠下面那些 frame）。
        _ = try? live.capture(name: "agent-step-list-\(stepCount)-\(expanded ? "expanded" : "collapsed")")

        let fields = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTextField.self, in: live.hosting)
            .filter { $0.isEditable }
        // 输入框是**最靠下**的那一格（它上面才是正文与详单）。
        let rects = fields.map { field in
            live.hosting.convert(field.bounds, from: field)
        }
        print("🧪 expanded=\(expanded) 输入框候选：\(rects.map { NSStringFromRect($0) })")
        let composer = try XCTUnwrap(rects.max(by: { $0.maxY < $1.maxY }),
                                     "整页里一个可编辑输入框都没取到 —— 输入区没落成真控件")

        return PageReading(composer: composer,
                           fittingHeight: live.hosting.fittingSize.height,
                           signature: try live.signature())
    }

    @MainActor
    func testExpandingWith300StepsLeavesTheComposerWhereItWas() throws {
        let collapsed = try readPage(expanded: false, stepCount: 300)
        let expanded = try readPage(expanded: true, stepCount: 300)

        print("🧪 收起：输入框 \(NSStringFromRect(collapsed.composer)) / 理想高 \(collapsed.fittingHeight)pt")
        print("🧪 展开：输入框 \(NSStringFromRect(expanded.composer)) / 理想高 \(expanded.fittingHeight)pt")

        // 输入框必须在可视区内（「输入框不见了」的机器判据）。
        for (label, reading) in [("收起", collapsed), ("展开", expanded)] {
            XCTAssertGreaterThan(reading.composer.height, 0, "\(label)态：输入框高度为 0（画了但看不见）")
            XCTAssertGreaterThanOrEqual(reading.composer.minY, -0.5, "\(label)态：输入框跑到可视区上沿之外")
            XCTAssertLessThanOrEqual(reading.composer.maxY, Self.pageSize.height + 0.5,
                                     "\(label)态：输入框被顶出了可视区下沿（\(reading.composer.maxY) > \(Self.pageSize.height)）")
        }

        // 展开不许改变外层：输入框的位置与高度逐点相同。
        XCTAssertEqual(expanded.composer.minY, collapsed.composer.minY, accuracy: 0.5,
                       "展开 300 步之后输入框挪了位置（\(collapsed.composer.minY) → \(expanded.composer.minY)）")
        XCTAssertEqual(expanded.composer.height, collapsed.composer.height, accuracy: 0.5,
                       "展开 300 步之后输入框高度变了（\(collapsed.composer.height) → \(expanded.composer.height)）")

        // 两态不是同一张画面：证明 `initialStepsExpanded` 这条口真的生效了。
        XCTAssertNotEqual(expanded.signature, collapsed.signature,
                          "收起与展开的画面指纹相同 ⇒ 两次挂的都是收起态，这条判据是假绿")
    }

    /// 300 步展开时，外层**不随步数变**：300 步与 600 步的整页理想高、输入框那一格都一样。
    @MainActor
    func testPageDoesNotGrowWithStepCountWhenExpanded() throws {
        let many = try readPage(expanded: true, stepCount: 300)
        let more = try readPage(expanded: true, stepCount: 600)
        print("🧪 展开态整页理想高：300 步 \(many.fittingHeight)pt / 600 步 \(more.fittingHeight)pt（页面 \(Self.pageSize.height)pt）")

        XCTAssertLessThanOrEqual(
            many.fittingHeight, Self.pageSize.height + 1,
            "展开 300 步之后整页理想高 \(many.fittingHeight)pt 超过窗口高度 —— 详单在把外层布局撑开"
        )
        XCTAssertEqual(more.fittingHeight, many.fittingHeight, accuracy: 0.5,
                       "步数从 300 加到 600，整页高度从 \(many.fittingHeight)pt 变成 \(more.fittingHeight)pt"
                           + " ⇒ 外层尺寸跟着步数长（那正是「撑爆」的形状）")
        XCTAssertEqual(more.composer.minY, many.composer.minY, accuracy: 0.5,
                       "步数翻倍之后输入框挪了位置（\(many.composer.minY) → \(more.composer.minY)）")
    }
}
