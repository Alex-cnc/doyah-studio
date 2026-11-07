import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// beta1.0.3 真机复验三条缺陷 + 「思考区三态」的端上判据（详设 §3.33 第二轮）。
///
/// ## 主人原话（装好的 beta1.0.3 上）
///
/// > ① 「Doyah Agent 里输出的『我先读一下……再……』这是思考过程吗？」
/// > ② 「最新的版本仍然是把结论折叠了」
/// > ③ 「claim 已经折叠了」，但「tools 调用了最终还没折叠起来」
///
/// 随后拍的产品决策（覆盖「一律默认折叠」）：思考区三态 —— **运行中展开 / 终态自动折
/// 一行 / 手动展开后本轮内 sticky**；结论任何状态下都可见；工具调用仍默认折一行。
///
/// ## 根因（各自一处）
///
/// ① **旧库的 `display.longPreview = 2+2`**：上一批只改 `contractDefault`，那只管新装机器；
///    已装用户盘上仍是当年按旧默认写下的 `2+2`（`Core/AgentDisplayPreferences.swift` 的 `load()`）。
/// ② **过程独白被当正文**：`assistantBody` 把 `message.text` 整段交给 Markdown。
/// ③ **工具块默认展开**：`defaultExpanded = !(compact || summary)`，契约默认 `toolProgress = .all`。
///
/// ## 判据（都能判红）
///
/// ⓪ 旧库（v1、`2+2`）走**真启动路径**（`AppState.loadAgentDisplayPreferencesIfNeeded()`）⇒
///    结论可见高度 = 全文高度（±0.5pt），且盘上被写回 v2；
/// ① 运行中：思考区高度 > 0，独白**不在结论段**里（在思考区）；
/// ② 终态：思考区高 == 一行摘要（= `AgentThinkingZone.collapsedHeight`），摘要带步数 / 耗时；
/// ③ 终态后手动展开：高 > 一行、≤ 200pt，且追加事件不回落（同一 `manual` 值再挂一次）；
/// ④ 新轮开始：手动态清空 ⇒ 回到「运行中默认展开」（`AgentThinkingManualState`）；
/// ⑤ 56 次工具调用 ⇒ 折叠 **一行**（20pt），300 次同高；展开 ≤ 240pt 且真有 `NSScrollView`；
/// ⑥ 整页对话区内容高：新形态 vs 旧形态（重建）对照。
///
/// ## 边界（如实登记）
///
/// · SwiftUI `Text` 不落成 `NSTextField`（同 `ExecutionReceiptPaneProbeTests`）⇒ 量的是
///   **容器 frame / 内容高**；文案由纯函数判（`AgentToolBlockSummary` / `AgentThinkingSummary`）；
/// · 折叠动作是 `onTapGesture` / `Button`（不落 `NSButton`）⇒ 展开态靠独立件的 `phase` /
///   `manual` 参数挂起来（`AgentThinkingZone` / `AgentToolBlockView` 就是为此拆出来的）；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 取证才跑，门禁不跑。
final class AgentChatNarrationProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    static let probeToolCalls = 56
    static let probeElapsedPerCall = 0.15   // 56 × 0.15 = 8.4s

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "过程信息折叠探针要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// 真机那一轮的过程独白。
    static let narration = "我先读一下 Core/AgentChat.swift 和 Core/AgentDisplayPreferences.swift，"
        + "看看折叠是在哪一层做的，再决定改哪里。"

    /// 结论：30 行 + 代码块（被折了就必然切两半）。
    static func conclusion(lines: Int = 30) -> String {
        var out = (1...max(2, lines - 4)).map { "第 \($0) 行：结论正文。" }
        out.append("```swift")
        out.append("let answer = 42")
        out.append("```")
        return out.joined(separator: "\n")
    }

    /// `count` 条工具调用，形状与 `Core/AgentChat.swift` 写出来的过程行一致。
    static func toolText(count: Int, elapsed: Double = probeElapsedPerCall) -> String {
        (0..<count).map { index in
            "▸ read_file · Core/File\(index).swift  ✓ · " + String(format: "%.1fs", elapsed)
        }.joined(separator: "\n")
    }

    /// beta1.0.3 之前那份盘：`version: 1` + `longPreview = 2+2`（当年按旧默认写下的）。
    static func legacyPayloadJSON(preview: String = "2+2") -> String {
        """
        {"version": 1, "values": {
          "display.streaming": "on",
          "display.compact": "off",
          "display.thinking": "off",
          "display.timestamps": "off",
          "display.toolProgress": "all",
          "display.indicatorGlyph": "emoji",
          "display.longPreview": "\(preview)",
          "display.bottomBarMeta": "off",
          "display.submitWhileRunning": "interrupt"
        }}
        """
    }

    /// 一轮的步骤（12 步：最后一步还在跑 / 已收尾两态都用它）。
    static func steps(_ count: Int = 12) -> [AgentChatStep] {
        (0..<count).map { index in
            AgentChatStep(index: index + 1, status: .done, tools: ["read_file"])
        }
    }

    // MARK: - 判据函数（真读数与反例读数共用同一套，反例才证明判据有牙齿）

    /// ① / ② 思考区折叠态：**一行**。
    static func thinkingFoldViolations(height: CGFloat) -> [String] {
        let limit = AgentThinkingZone.collapsedHeight
        guard height > limit + 0.5 else { return [] }
        return ["思考区折叠态高 \(height)pt > 一行 \(limit)pt ⇒ 终态没自动折起来"]
    }

    /// ② 运行中 / ③ 手动展开：**不许 0 高**，且 ≤ 200pt。
    static func thinkingExpandedViolations(height: CGFloat) -> [String] {
        var issues: [String] = []
        if height <= AgentThinkingZone.collapsedHeight + 0.5 {
            issues.append("思考区展开态高 \(height)pt ≯ 一行 ⇒ 内容没出来")
        }
        if height > AgentThinkingZone.expandedMaxHeight + 0.5 {
            issues.append("思考区展开态高 \(height)pt > 上限 \(AgentThinkingZone.expandedMaxHeight)pt ⇒ 没有限高")
        }
        return issues
    }

    /// ⑤ 工具块折叠态：一行摘要。
    static func toolFoldViolations(height: CGFloat) -> [String] {
        let limit = AgentToolBlockView.collapsedHeight
        guard height > limit + 0.5 else { return [] }
        return ["工具块折叠态高 \(height)pt > 一行 \(limit)pt ⇒ 工具列表没折"]
    }

    /// ⑤ 工具块展开态：≤ 240pt。
    static func toolExpandedViolations(height: CGFloat) -> [String] {
        let limit: CGFloat = 240
        guard height > limit + 0.5 else { return [] }
        return ["工具块展开态高 \(height)pt > 上限 \(limit)pt ⇒ 明细没有高度上限"]
    }

    /// ⓪ 结论可见高度 vs 全文高度。
    static func conclusionFoldViolations(visible: CGFloat, full: CGFloat) -> [String] {
        guard visible + 0.5 < full else { return [] }
        return ["结论可见高 \(visible)pt < 全文高 \(full)pt（差 \(full - visible)pt）⇒ 结论被折了"]
    }

    // MARK: - 几何读数

    @MainActor
    private func height<V: View>(_ view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: Self.pageSize.width))
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 4000))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    @MainActor
    private func scrollViewCount<V: View>(_ view: V) -> Int {
        let hosting = NSHostingView(rootView: view.frame(width: Self.pageSize.width))
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: Self.pageSize.width, height: 4000))
        hosting.layoutSubtreeIfNeeded()
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: hosting).count
    }

    /// 一页（真 `AgentChatView` 900×620）的读数。
    @MainActor
    private struct PageReading {
        let transcriptViewport: CGRect
        let transcriptContentHeight: CGFloat
        let fittingHeight: CGFloat
    }

    /// 造一个**只属于这次读数**的显示开关目录（不碰真用户的配置）。
    private func makeStoreDirectory(legacyPreview: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("narration-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let legacyPreview {
            let file = AgentDisplayPreferencesFile(directory: directory)
            try Data(Self.legacyPayloadJSON(preview: legacyPreview).utf8).write(to: file.fileURL)
        }
        return directory
    }

    /// 真 `AgentChatView`，**走真启动路径**读显示开关（`loadAgentDisplayPreferencesIfNeeded`）。
    @MainActor
    private func readPage(_ messages: [AgentChatMessage],
                          store: URL,
                          isRunning: Bool = false,
                          steps: [AgentChatStep] = []) -> PageReading {
        let appState = AppState()
        appState.connections = []
        appState.agentDisplayPreferencesDirectoryOverride = store
        appState.loadAgentDisplayPreferencesIfNeeded()
        let model = AgentChatModel(sessionID: "narration-probe",
                                   state: AgentChatState(
                                    messages: messages,
                                    steps: steps,
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

        let scrolls = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSScrollView.self, in: live.hosting)
        let transcript = scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        let viewport = transcript.map { live.hosting.convert($0.bounds, from: $0) } ?? .zero
        let contentHeight = transcript?.documentView?.bounds.height ?? 0
        return PageReading(transcriptViewport: viewport,
                           transcriptContentHeight: contentHeight,
                           fittingHeight: live.hosting.fittingSize.height)
    }

    private func question(_ text: String = "结论为什么被折了？") -> AgentChatMessage {
        .init(role: .user, text: text)
    }

    /// 思考区那一格（探针直接挂视图，`manual` 可指定）。
    @MainActor
    private func thinkingZoneHeight(text: String, phase: AgentThinkingPhase, manual: Bool?,
                                    steps: Int = 12, elapsed: Double? = 18.4) -> CGFloat {
        height(AgentThinkingZone(text: text,
                                 phase: phase,
                                 manual: manual,
                                 steps: steps,
                                 elapsedSeconds: elapsed,
                                 highlight: nil,
                                 language: .simplifiedChinese) { _ in })
    }

    // MARK: - ⓪ 旧库（longPreview = 2+2）启动 ⇒ 结论不折（走真启动路径）

    @MainActor
    func testLegacyTwoPlusTwoStoreStillShowsTheWholeConclusion() throws {
        let legacyStore = try makeStoreDirectory(legacyPreview: "2+2")
        let freshStore = try makeStoreDirectory()
        defer {
            try? FileManager.default.removeItem(at: legacyStore)
            try? FileManager.default.removeItem(at: freshStore)
        }

        // 真启动路径：AppState 读那份旧盘（迁移在 `load()` 里）。
        let probeState = AppState()
        probeState.agentDisplayPreferencesDirectoryOverride = legacyStore
        probeState.loadAgentDisplayPreferencesIfNeeded()
        let migratedPreview = probeState.agentDisplayPreferences.longPreview
        let onDisk = (try? String(contentsOf: AgentDisplayPreferencesFile(directory: legacyStore).fileURL,
                                  encoding: .utf8)) ?? ""
        print("🧪 旧库启动：内存 longPreview = \(migratedPreview.canonicalValue)"
              + " / 盘上写回 v2 = \(onDisk.contains("\"version\" : 2"))")
        XCTAssertEqual(migratedPreview, .off,
                       "旧库里的 `2+2` 没迁走 ⇒ 已装用户看到的结论仍是首 2 末 2 行")
        XCTAssertTrue(onDisk.contains("\"version\" : 2"), "迁移之后没有写回 v2：\(onDisk)")

        let conclusion = Self.conclusion()
        let baseline = readPage([question()], store: freshStore)
        let migratedPage = readPage([question(), .init(role: .assistant, text: conclusion)],
                                    store: legacyStore)
        let freshPage = readPage([question(), .init(role: .assistant, text: conclusion)],
                                 store: freshStore)

        let visibleOld = migratedPage.transcriptContentHeight - baseline.transcriptContentHeight
        let visibleFresh = freshPage.transcriptContentHeight - baseline.transcriptContentHeight
        print("🧪 结论可见高（真视图）：旧库迁移后 \(visibleOld)pt / 新装默认 \(visibleFresh)pt"
              + "（首 2 末 2 只剩 4 行 ≈ \(4 * Metrics.listRowHeight)pt 量级）")

        XCTAssertGreaterThan(baseline.transcriptContentHeight, 0, "对话区内容高 0 ⇒ 没量到滚动容器")
        XCTAssertTrue(Self.conclusionFoldViolations(visible: visibleOld, full: visibleFresh).isEmpty,
                      "旧库启动后结论仍被折：\(visibleOld)pt vs 全文 \(visibleFresh)pt")
        XCTAssertGreaterThan(visibleOld, 4 * Metrics.listRowHeight,
                             "结论只占 \(visibleOld)pt ⇒ 这正是「首 2 末 2」那一折")

        // 反例：**不迁移**的旧盘（把 `2+2` 写进 v2，迁移条件不成立）⇒ 同一套判据必须报红。
        let stubbornStore = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: stubbornStore) }
        var legacy = AgentDisplayPreferences()
        try legacy.apply(key: AgentDisplayKey.longPreview.rawValue, value: "2+2")
        try AgentDisplayPreferencesFile(directory: stubbornStore).save(legacy)
        let redPage = readPage([question(), .init(role: .assistant, text: conclusion)],
                               store: stubbornStore)
        let redVisible = redPage.transcriptContentHeight - baseline.transcriptContentHeight
        let red = Self.conclusionFoldViolations(visible: redVisible, full: visibleFresh)
        print("🧪 反例⓪（不迁移，盘上 `2+2` 原样生效）：结论可见高 \(redVisible)pt ⇒ "
              + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "不迁移的旧库（\(redVisible)pt）判据仍然绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ① / ② / ③ 思考区三态

    @MainActor
    func testThinkingZoneTriState() {
        let narration = Self.narration
        // ① 运行中：默认展开、> 0 高、≤ 200pt。
        let running = thinkingZoneHeight(text: narration, phase: .running, manual: nil)
        // ② 终态：自动折成一行。
        let finished = thinkingZoneHeight(text: narration, phase: .finished, manual: nil)
        // ③ 终态 + 手动展开：> 一行，且追加更多事件（文本变长）后仍然展开。
        let manualOpen = thinkingZoneHeight(text: narration, phase: .finished, manual: true)
        let manualOpenLonger = thinkingZoneHeight(text: narration + "\n\n我再看一下测试文件。\n\n还要再确认一处。",
                                                  phase: .finished, manual: true)
        // ③ 手动收起：运行中被用户收起也只剩一行。
        let manualClosed = thinkingZoneHeight(text: narration, phase: .running, manual: false)

        let summary = AgentThinkingSummary.text(steps: 12, elapsedSeconds: 18.4,
                                                expanded: false, language: .simplifiedChinese)
        print("🧪 思考区三态：运行中 \(running)pt / 终态 \(finished)pt（一行 = "
              + "\(AgentThinkingZone.collapsedHeight)pt）/ 手动展开 \(manualOpen)pt → 再加事件 "
              + "\(manualOpenLonger)pt / 运行中手动收起 \(manualClosed)pt（上限 "
              + "\(AgentThinkingZone.expandedMaxHeight)pt）")
        print("🧪 终态摘要行：「▸ \(summary)」")

        XCTAssertTrue(Self.thinkingExpandedViolations(height: running).isEmpty,
                      Self.thinkingExpandedViolations(height: running).joined(separator: "；"))
        XCTAssertEqual(finished, AgentThinkingZone.collapsedHeight, accuracy: 0.5,
                       "终态思考区高 \(finished)pt ≠ 一行 \(AgentThinkingZone.collapsedHeight)pt ⇒ 没自动折")
        XCTAssertTrue(summary.contains("12 步"), "摘要没报步数：\(summary)")
        XCTAssertTrue(summary.contains("18.4s"), "摘要没报耗时：\(summary)")
        XCTAssertTrue(Self.thinkingExpandedViolations(height: manualOpen).isEmpty,
                      "终态手动展开没展开：\(manualOpen)pt")
        // ③ sticky：文本变长（新一轮事件追加）后**仍然展开**（高度可以随内容长，但必须 > 一行）。
        XCTAssertGreaterThan(manualOpenLonger, AgentThinkingZone.collapsedHeight + 0.5,
                             "追加事件后思考区掉回 \(manualOpenLonger)pt ⇒ 手动展开不 sticky")
        XCTAssertTrue(Self.thinkingExpandedViolations(height: manualOpenLonger).isEmpty,
                      Self.thinkingExpandedViolations(height: manualOpenLonger).joined(separator: "；"))
        XCTAssertEqual(manualClosed, AgentThinkingZone.collapsedHeight, accuracy: 0.5,
                       "运行中手动收起后高 \(manualClosed)pt ⇒ 收起没生效")

        // 反例：终态**不折**（旧形态 = 12 行思考整段铺开）⇒ 同一套判据必须报红。
        let unfolded = height(VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12, id: \.self) { index in
                Text("过程第 \(index + 1) 行：我看到这一处是这样。")
                    .font(Theme.font(.mono))
                    .frame(height: Metrics.listRowHeight)
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
        let red = Self.thinkingFoldViolations(height: unfolded)
        print("🧪 反例②（终态不折，整段思考铺开）：\(unfolded)pt ⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "整段思考铺开（\(unfolded)pt）判据仍然绿 ⇒ 判据没有牙齿")
    }

    /// ① 独白住在思考区、**不在结论段**（「我先读一下…」不许当正文）。
    @MainActor
    func testNarrationLivesInThinkingZoneNotInBody() throws {
        let conclusion = Self.conclusion()
        let withNarration = Self.narration + "\n\n" + conclusion
        let split = AgentAnswerClassifier.split(withNarration)

        print("🧪 分类：narration=「\(split.narration?.prefix(20) ?? "nil")…」"
              + " / conclusion 首行「\(split.conclusion.components(separatedBy: "\n").first ?? "")」")
        XCTAssertEqual(split.narration, Self.narration, "独白没被认出来 ⇒ 它会当正文铺")
        XCTAssertEqual(split.conclusion, conclusion, "结论被切走了")
        XCTAssertFalse(split.conclusion.contains("我先读一下"), "独白仍在结论段里 ⇒ 它会当正文铺")

        let store = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: store) }

        // 运行中：整页里思考区展开（内容高比终态那一版更高）。
        let running = readPage([question(), .init(role: .assistant, text: withNarration, isStreaming: true)],
                               store: store, isRunning: true, steps: Self.steps())
        let finished = readPage([question(), .init(role: .assistant, text: withNarration)],
                                store: store, steps: Self.steps())
        let zoneExtra = running.transcriptContentHeight - finished.transcriptContentHeight
        print("🧪 整页：运行中 \(running.transcriptContentHeight)pt / 终态 \(finished.transcriptContentHeight)pt"
              + "（思考区展开多占 \(zoneExtra)pt）")

        XCTAssertGreaterThan(zoneExtra, AgentThinkingZone.collapsedHeight,
                             "运行中与终态的整页差只有 \(zoneExtra)pt ⇒ 运行中思考区没展开")

        // 结论在两种状态下都完整可见（≥ 全文高度的一屏内读数）。
        let baseline = readPage([question()], store: store, steps: Self.steps())
        let conclusionOnly = readPage([question(), .init(role: .assistant, text: conclusion)],
                                      store: store, steps: Self.steps())
        let conclusionHeight = conclusionOnly.transcriptContentHeight - baseline.transcriptContentHeight
        XCTAssertGreaterThan(conclusionHeight, 4 * Metrics.listRowHeight,
                             "结论只占 \(conclusionHeight)pt ⇒ 结论被折了")
    }

    /// ④ 新轮开始 ⇒ 手动态清空（回到「运行中默认展开」）。
    func testManualThinkingStateResetsOnNewTurn() {
        let turnOne = UUID()
        let turnTwo = UUID()
        var state = AgentThinkingManualState()

        state.register(turnKey: turnOne)
        XCTAssertTrue(AgentThinkingFold.isExpanded(phase: .running, manual: state.manual(for: turnOne)),
                      "新一轮开始时运行中默认就该展开")
        state.set(false)   // 用户手动收起
        XCTAssertFalse(AgentThinkingFold.isExpanded(phase: .running, manual: state.manual(for: turnOne)),
                       "手动收起没生效")
        state.register(turnKey: turnOne)   // 同一轮内的重绘，不许把手动态清掉
        XCTAssertFalse(AgentThinkingFold.isExpanded(phase: .running, manual: state.manual(for: turnOne)),
                       "同一轮内重绘把手动态清了 ⇒ 点不动")

        state.register(turnKey: turnTwo)   // 新轮
        XCTAssertTrue(AgentThinkingFold.isExpanded(phase: .running, manual: state.manual(for: turnTwo)),
                      "新轮没有回到默认（仍沿用上一轮的收起）")
        print("🧪 手动态：轮一收起后重绘仍收起 ✅ / 轮二回到默认展开 ✅")
    }

    // MARK: - ⑤ 56 次工具调用 ⇒ 一行摘要；展开 ≤ 240pt 且内部滚动

    @MainActor
    func testToolBlockIsOneLineSummaryByDefault() throws {
        let few = Self.toolText(count: Self.probeToolCalls)
        let many = Self.toolText(count: 300)

        let collapsedFew = height(AgentToolBlockView(text: few, expanded: false, highlight: nil,
                                                     language: .simplifiedChinese) {})
        let collapsedMany = height(AgentToolBlockView(text: many, expanded: false, highlight: nil,
                                                      language: .simplifiedChinese) {})
        let expandedFew = height(AgentToolBlockView(text: few, expanded: true, highlight: nil,
                                                    language: .simplifiedChinese) {})
        let expandedMany = height(AgentToolBlockView(text: many, expanded: true, highlight: nil,
                                                     language: .simplifiedChinese) {})
        let expandedScrolls = scrollViewCount(AgentToolBlockView(text: many, expanded: true,
                                                                 highlight: nil,
                                                                 language: .simplifiedChinese) {})

        let rows = AgentToolLines.rows(few)
        let summary = AgentToolBlockSummary.text(count: rows.count,
                                                 elapsedSeconds: AgentToolBlockSummary.elapsedSeconds(rows),
                                                 expanded: false,
                                                 language: .simplifiedChinese)
        print("🧪 工具块：折叠态 \(Self.probeToolCalls) 次 \(collapsedFew)pt / 300 次 \(collapsedMany)pt"
              + "（一行 = \(AgentToolBlockView.collapsedHeight)pt）/ 展开态 \(expandedFew)pt / \(expandedMany)pt"
              + "（整块上限 \(AgentToolBlockView.expandedMaxHeight)pt）/ 滚动容器 \(expandedScrolls) 个")
        print("🧪 工具块摘要行：「▸ \(summary)」")

        XCTAssertEqual(rows.count, Self.probeToolCalls, "夹具没解析出 56 条：\(rows.count)")
        XCTAssertTrue(summary.contains("\(Self.probeToolCalls) 次工具调用"), "摘要没报条数：\(summary)")
        // 总耗时按解析出来的读数比（`0.15s` 在过程行里写成 `0.1s`，读回来的和 = 5.6s）。
        let totalElapsed = AgentToolBlockSummary.elapsedSeconds(rows)
        let expectedElapsed = String(format: "%.1fs", totalElapsed ?? -1)
        XCTAssertTrue(summary.contains(expectedElapsed),
                      "摘要没报总耗时（应含 \(expectedElapsed)）：\(summary)")

        XCTAssertTrue(Self.toolFoldViolations(height: collapsedFew).isEmpty,
                      Self.toolFoldViolations(height: collapsedFew).joined(separator: "；"))
        XCTAssertEqual(collapsedMany, collapsedFew, accuracy: 0.5,
                       "56 → 300 次让折叠态从 \(collapsedFew)pt 变成 \(collapsedMany)pt ⇒ 没有折成一行")
        XCTAssertTrue(Self.toolExpandedViolations(height: expandedFew).isEmpty,
                      Self.toolExpandedViolations(height: expandedFew).joined(separator: "；"))
        XCTAssertEqual(expandedMany, expandedFew, accuracy: 0.5,
                       "展开态 56 次（\(expandedFew)pt）与 300 次（\(expandedMany)pt）不同高 ⇒ 明细在长")
        XCTAssertEqual(expandedScrolls, 1, "展开态要有**内部滚动**（正好一个滚动容器），实测 \(expandedScrolls) 个")

        // 整页：56 次工具调用只许多占一行。
        let store = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: store) }
        let withTool = readPage([question(),
                                 .init(role: .assistant, text: Self.conclusion()),
                                 .init(role: .tool, text: few)], store: store)
        let withoutTool = readPage([question(), .init(role: .assistant, text: Self.conclusion())],
                                   store: store)
        let toolExtra = withTool.transcriptContentHeight - withoutTool.transcriptContentHeight
        // **§3.33.4 之后这条预算改成两行**：有工具就必然带出「Tool calls (N)」与「Σ total」两行
        // （三行汇总的固定顺序），所以 56 次调用在整页上多占的是 **2 行 + 2 个发丝间距**，
        // 而不是 1 行。有牙齿的那一半在别处：**56 次与 300 次同高**（上面 `collapsedMany == collapsedFew`），
        // 且工具明细只在展开时按行出现。
        let toolRowBudget = AgentToolBlockView.collapsedHeight * 2 + Spacing.hair * 2 + 0.5
        print("🧪 整页：56 次工具块多占 \(toolExtra)pt（两行预算 \(toolRowBudget)pt；"
              + "一行 \(AgentToolBlockView.collapsedHeight)pt ⇒ Tool calls + Σ 两行）")
        XCTAssertLessThanOrEqual(toolExtra, toolRowBudget,
                                 "56 次工具调用在整页上多占 \(toolExtra)pt ⇒ 超过「Tool calls + Σ」两行")

        // 反例：无上限的 56 行（改前形态）⇒ 同一套判据必须报红。
        let unbounded = height(VStack(alignment: .leading, spacing: Spacing.hair) {
            ForEach(0..<Self.probeToolCalls, id: \.self) { index in
                Text("├─ ⏺ read_file(\"Core/File\(index).swift\") (0.2s)")
                    .font(Theme.font(.mono))
                    .frame(height: Metrics.listRowHeight)
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
        let red = Self.toolFoldViolations(height: unbounded)
        print("🧪 反例⑤（工具行不折，56 行）：\(unbounded)pt ⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "56 行铺开（\(unbounded)pt）判据仍然绿 ⇒ 判据没有牙齿")

        // 反例：展开态无上限（不封顶、不滚动）。
        let unboundedExpanded = height(VStack(alignment: .leading, spacing: Spacing.hair) {
            Text("└─ ▾ 56 次工具调用 · 8.4s · 收起").font(Theme.font(.mono))
                .frame(height: Metrics.listRowHeight)
            ForEach(0..<Self.probeToolCalls, id: \.self) { index in
                Text("├─ ⏺ read_file(\"Core/File\(index).swift\") (0.2s)")
                    .font(Theme.font(.mono))
                    .frame(height: Metrics.listRowHeight)
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
        let redExpanded = Self.toolExpandedViolations(height: unboundedExpanded)
        print("🧪 反例⑤b（展开态无上限）：\(unboundedExpanded)pt ⇒ "
              + (redExpanded.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(redExpanded.isEmpty, "展开态无上限判据仍然绿 ⇒ 判据没有牙齿")
    }

    // MARK: - ⑥ 整页对话区高度：新形态 vs 旧形态（重建）

    /// 旧形态 = beta1.0.3 那三处的组合：结论按 `2+2` 折 + 工具调用不折（56 行）+
    /// 独白当正文。用同一批 Markdown / 行高重建，量「这一屏本来要占多高」。
    private struct LegacyShapePage: View {
        let conclusion: String
        let narration: String
        let toolLines: [String]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("结论为什么被折了？").font(Theme.font(.mono))
                    AgentMarkdownBody(text: narration, isStreaming: false,
                                      font: Theme.font(.mono), highlight: nil,
                                      tint: Theme.text(.primary))
                    let lines = conclusion.components(separatedBy: "\n")
                    AgentMarkdownBody(text: lines.prefix(2).joined(separator: "\n"),
                                      isStreaming: false, font: Theme.font(.mono),
                                      highlight: nil, tint: Theme.text(.primary))
                    Text("… 展开 (\(lines.count - 4))").font(Theme.font(.mono))
                    AgentMarkdownBody(text: lines.suffix(2).joined(separator: "\n"),
                                      isStreaming: false, font: Theme.font(.mono),
                                      highlight: nil, tint: Theme.text(.primary))
                    ForEach(Array(toolLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(Theme.font(.mono)).frame(height: Metrics.listRowHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
            }
        }
    }

    @MainActor
    func testWholePageHeightsBeforeAndAfter() throws {
        let store = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: store) }
        let conclusion = Self.conclusion()
        let tools = Self.toolText(count: Self.probeToolCalls)
        let withEverything = [
            question(),
            .init(role: .assistant, text: Self.narration + "\n\n" + conclusion),
            .init(role: .tool, text: tools),
        ]
        let after = readPage(withEverything, store: store, steps: Self.steps())
        let legacy = height(LegacyShapePage(conclusion: conclusion,
                                            narration: Self.narration + "\n\n" + conclusion,
                                            toolLines: tools.components(separatedBy: "\n")))

        print("🧪 整页对话区内容高：新形态（结论整段 + 思考一行 + 工具一行）\(after.transcriptContentHeight)pt"
              + " / 旧形态（结论 2+2 + 独白当正文 + 56 行工具）\(legacy)pt"
              + " / 省下 \(legacy - after.transcriptContentHeight)pt")
        print("🧪 对话区视口：\(NSStringFromRect(after.transcriptViewport))"
              + " / 整页理想高 \(after.fittingHeight)pt（窗口 \(Self.pageSize.height)pt）")

        XCTAssertGreaterThan(after.transcriptContentHeight, 0, "对话区内容高 0 ⇒ 没量到滚动容器")
        XCTAssertLessThan(after.transcriptContentHeight, legacy,
                          "新形态（\(after.transcriptContentHeight)pt）不比旧形态（\(legacy)pt）矮 ⇒ 折叠没生效")
        XCTAssertGreaterThan(legacy, Self.pageSize.height,
                             "旧形态重建只有 \(legacy)pt ⇒ 反例没重建出「56 行铺满」的样子")
    }
}
