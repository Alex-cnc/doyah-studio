import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「对话区**展示优先级**」这一族的 App 侧探针（详设 §3.33）。
///
/// ## 真机缺陷（2026-11-07，人类主人原话）
///
/// > 「结论竟然折叠起来，却把 29 个 claims 全展开放屏幕上，而且我也不懂这些 claims 有什么用。
/// >  hermes 最终的界面就是思考和其他对用户没用的信息都是默认折叠不占地方，
/// >  只把用户的问题和结论呈现出来。」
///
/// 两处**优先级倒置**：
/// · `App/Views/AgentChatView.swift` 的 `assistantBody` 按 `longPreview`（当时的默认 `2+2`）
///   把**结论本身**折成首 2 末 2 行；
/// · 断言台账（`AgentClaimTrace.block`：机器头 + 29 条断言 + 每条下面的出处行）在
///   `noticeRow` 里**整块铺开**，一条不折、没有高度上限。
/// 结果：要读的折了，不该读的铺满一屏。
///
/// ## 判据（能判红）
///
/// ① **结论在、且是默认形态**：真 `AgentChatView`（900×620）里「用户问题 + 结论」与
///    「再加 29 条断言台账」两种形态的对话区**内容高之差 ≤ 一行**（`summaryHeight`），
///    且结论那一格高度 > 0；默认显示开关下 `previewSplit` 必须是 `nil`（结论不许被折）；
/// ② **claims 折叠态 == 一行**：`AgentClaimAuditRow` 收起时高度逐点等于 `summaryHeight`，
///    29 条与 300 条**逐点相同**；有未核断言时这一行的文案就是那条告警，全部已核时不许出现；
/// ③ **展开 ≤ 240pt 且内部滚动**：展开态高度 ≤ `expandedMaxHeight`，宿主里真的落出一个
///    `NSScrollView`，且 29 条与 300 条同高；
/// ④ **反例必须判红**：把明细还原成「有多少铺多少」（无 `ScrollView`、无上限）、
///    把结论按 `2+2` 折起来、把整块台账原样铺进 `Text` —— 同一套判据函数必须报红。
///
/// ## 边界（如实登记）
///
/// · SwiftUI `Text` 在这台宿主里不落成 `NSTextField`（`ExecutionReceiptPaneProbeTests` 同一条边界）⇒
///   判据量的是**容器 frame**（行高 / 明细上限 / 对话区内容高），文字内容用同一个纯函数
///   `AgentClaimAuditRow.summaryText(for:expanded:language:)` 判（视图与探针读同一份）；
/// · 折叠动作是 `onTapGesture`（不落 `NSButton`）⇒ 展开态用 `expanded: .constant(true)` 挂起来；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑。
final class AgentChatAnswerPriorityProbeTests: XCTestCase {

    static let pageSize = CGSize(width: 900, height: 620)
    /// 真机那一轮的形状：29 条断言、其中 8 条没依据。
    static let probeClaims = 29
    static let probeUnverified = 8

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "对话区展示优先级探针要真视图与真布局：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 夹具

    /// `total` 条断言，前 `unverified` 条「没验证」（真机那一轮的形状）。
    private func provenance(total: Int, unverified: Int) -> AgentAnswerProvenance {
        let claims = (0..<total).map { index -> AgentClaim in
            let dirty = index < unverified
            return AgentClaim(statement: "第 \(index + 1) 条断言：这一处确实是这样",
                              status: dirty ? .unverified : .verified,
                              bases: dirty ? [] : [.file(path: "Core/AgentLoop.swift", line: index + 1)],
                              confidence: dirty ? 0.2 : 0.95,
                              alternatives: dirty ? ["换个查法再看一遍"] : [])
        }
        return AgentAnswerProvenance(claims: claims)
    }

    /// 台账落进消息流的**那段文本**（机器头 + 逐行）——界面拿到的就是它。
    private func block(total: Int, unverified: Int) -> String {
        AgentClaimTrace.block(for: provenance(total: total, unverified: unverified),
                              language: .simplifiedChinese) ?? ""
    }

    private func audit(total: Int, unverified: Int) -> AgentClaimAudit {
        AgentClaimAudit.parse(block(total: total, unverified: unverified))!
    }

    /// 一段**长结论**（30 行，带一个代码块：折了就必然把它切成两半）。
    private func conclusion(lines: Int = 30) -> String {
        var out = (1...max(2, lines - 4)).map { "第 \($0) 行：结论正文。" }
        out.append("```swift")
        out.append("let answer = 42")
        out.append("```")
        return out.joined(separator: "\n")
    }

    private func state(withConclusion: Bool, claims: Int? = nil, unverified: Int = 0,
                       noticeText: String? = nil) -> AgentChatState {
        var messages: [AgentChatMessage] = [
            .init(role: .user, text: "这个仓库的 Agent 结论为什么被折叠了？"),
        ]
        if withConclusion {
            messages.append(.init(role: .assistant, text: conclusion()))
        }
        if let claims {
            messages.append(.init(role: .notice,
                                  text: noticeText ?? block(total: claims, unverified: unverified)))
        }
        return AgentChatState(messages: messages,
                              endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"))
    }

    // MARK: - 判据函数（真实测量与反例测量**共用同一套**，反例才证明判据有牙齿）

    /// ② claims 折叠态：**一行**（`AgentClaimAuditRow.summaryHeight`）。
    static func collapsedViolations(height: CGFloat) -> [String] {
        let limit = AgentClaimAuditRow.summaryHeight
        guard height > limit + 0.5 else { return [] }
        return ["claims 折叠态高 \(height)pt > 一行 \(limit)pt ⇒ 台账还在往上长"]
    }

    /// ③ claims 展开态：**有上限**（`expandedMaxHeight` = 折叠行 + 间距 + 240pt）。
    static func expandedViolations(height: CGFloat) -> [String] {
        let limit = AgentClaimAuditRow.expandedMaxHeight
        guard height > limit + 0.5 else { return [] }
        return ["claims 展开态高 \(height)pt > 上限 \(limit)pt（= 一行 \(AgentClaimAuditRow.summaryHeight)"
                + " + 明细上限 \(AgentClaimAuditRow.detailMaxHeight) + 间距）⇒ 明细没有高度上限"]
    }

    /// ① 结论那一格：**高度 > 0**（0 = 被折没了 / 根本没画）。
    static func conclusionVisibilityViolations(height: CGFloat) -> [String] {
        guard height > 0.5 else {
            return ["结论那一段高度 \(height)pt ⇒ 结论没画出来（被折叠 / 被挤没）"]
        }
        return []
    }

    /// ① 结论默认形态：**默认显示开关下不许折**（`previewSplit` 必须 `nil`）。
    static func conclusionFoldViolations(text: String, preferences: AgentDisplayPreferences) -> [String] {
        guard let split = AgentDisplayProjection.previewSplit(text: text, preferences: preferences) else {
            return []
        }
        return ["结论默认被折成首 \(split.head.components(separatedBy: "\n").count)"
                + " 末 \(split.tail.components(separatedBy: "\n").count) 行（藏了 \(split.hidden) 行）"
                + " ⇒ 要看的折了、不该看的铺开"]
    }

    /// ① 整页：台账只许多占**一行**（内容高与理想高两个读法都要守）。
    static func pageExtraViolations(extra: CGFloat) -> [String] {
        let limit = AgentClaimAuditRow.summaryHeight + Spacing.xs
        guard extra > limit + 0.5 else { return [] }
        return ["台账让这一页多出 \(extra)pt > 一行 \(limit)pt ⇒ 台账默认没折成一行、整页被它撑开"]
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

    @MainActor
    private func auditRowHeight(claims: Int, unverified: Int, expanded: Bool) -> CGFloat {
        height(AgentClaimAuditRow(audit: audit(total: claims, unverified: unverified),
                                  expanded: .constant(expanded)))
    }

    // MARK: - ② claims 折叠态 = 一行

    @MainActor
    func testClaimsCollapseToOneLineAndWarnOnlyWhenUnverified() throws {
        let few = auditRowHeight(claims: 3, unverified: 0, expanded: false)
        let many = auditRowHeight(claims: Self.probeClaims, unverified: Self.probeUnverified, expanded: false)
        let more = auditRowHeight(claims: 300, unverified: 8, expanded: false)
        let limit = AgentClaimAuditRow.summaryHeight
        print("🧪 claims 折叠态理想高：3 条 \(few)pt / \(Self.probeClaims) 条 \(many)pt / 300 条 \(more)pt"
              + "（一行 = \(limit)pt）")

        XCTAssertGreaterThan(many, 0, "折叠行量出来是 0 高 ⇒ 夹具没挂上，这一条判的是空")
        XCTAssertEqual(many, limit, accuracy: 0.5,
                       "\(Self.probeClaims) 条断言折叠态高 \(many)pt ≠ 一行 \(limit)pt ⇒ 没有折成一行")
        XCTAssertEqual(more, many, accuracy: 0.5,
                       "条数 29 → 300 让折叠行从 \(many)pt 变成 \(more)pt ⇒ 这一行会随条数长高")
        XCTAssertTrue(Self.collapsedViolations(height: many).isEmpty,
                      Self.collapsedViolations(height: many).joined(separator: "；"))

        // 未核断言那一条**必须**在折叠行上（不许藏在展开区里）。
        let dirty = audit(total: Self.probeClaims, unverified: Self.probeUnverified)
        let dirtyText = AgentClaimAuditRow.summaryText(for: dirty, expanded: false, language: .simplifiedChinese)
        let clean = audit(total: Self.probeClaims, unverified: 0)
        let cleanText = AgentClaimAuditRow.summaryText(for: clean, expanded: false, language: .simplifiedChinese)
        print("🧪 claims 折叠行文案：未核 8 ⇒「\(dirtyText)」/ 全部已核 ⇒「\(cleanText)」")

        XCTAssertEqual(AgentClaimAuditRow.summaryGlyph(for: dirty), "⚠",
                       "有未核断言时行首必须是告警字形")
        XCTAssertTrue(dirtyText.contains("8 条断言没有依据"), "折叠行没有那条告警：\(dirtyText)")
        XCTAssertEqual(AgentClaimAuditRow.summaryGlyph(for: clean), "✓")
        XCTAssertFalse(cleanText.contains("没有依据"),
                       "全部已核还出现「没有依据」= 狼来了：\(cleanText)")
        XCTAssertTrue(cleanText.contains("\(Self.probeClaims) 条断言 · 已核 \(Self.probeClaims) / 未核 0"),
                      "汇总行不对：\(cleanText)")
    }

    // MARK: - ③ 展开 ≤ 240pt 且内部滚动

    @MainActor
    func testClaimsDetailIsBoundedAndScrolls() {
        let many = auditRowHeight(claims: Self.probeClaims, unverified: Self.probeUnverified, expanded: true)
        let more = auditRowHeight(claims: 300, unverified: 8, expanded: true)
        let scrolls = scrollViewCount(AgentClaimAuditRow(audit: audit(total: 300, unverified: 8),
                                                         expanded: .constant(true)))
        print("🧪 claims 展开态理想高：\(Self.probeClaims) 条 \(many)pt / 300 条 \(more)pt"
              + "（上限 \(AgentClaimAuditRow.expandedMaxHeight)pt = 一行 \(AgentClaimAuditRow.summaryHeight)"
              + " + 明细 \(AgentClaimAuditRow.detailMaxHeight) + 间距）/ 内部滚动容器 \(scrolls) 个")

        XCTAssertTrue(Self.expandedViolations(height: many).isEmpty,
                      Self.expandedViolations(height: many).joined(separator: "；"))
        XCTAssertEqual(more, many, accuracy: 0.5,
                       "展开态 29 条（\(many)pt）与 300 条（\(more)pt）不同高 ⇒ 明细随条数长高")
        XCTAssertLessThanOrEqual(AgentClaimAuditRow.detailMaxHeight, 240,
                                 "明细上限必须 ≤ 240pt（设计要求），现在是 \(AgentClaimAuditRow.detailMaxHeight)pt")
        XCTAssertEqual(scrolls, 1, "展开态的明细要在**内部滚动**（正好一个滚动容器），实测 \(scrolls) 个")
    }

    // MARK: - ① 整页：结论可见、台账只占一行、对话区不被撑开

    @MainActor
    private struct PageReading {
        let transcriptViewport: CGRect
        let transcriptContentHeight: CGFloat
        let fittingHeight: CGFloat
    }

    @MainActor
    private func readPage(withConclusion: Bool, claims: Int? = nil, unverified: Int = 0,
                          noticeText: String? = nil) -> PageReading {
        let appState = AppState()
        appState.connections = []
        let model = AgentChatModel(sessionID: "answer-priority-probe",
                                   state: state(withConclusion: withConclusion,
                                                claims: claims, unverified: unverified,
                                                noticeText: noticeText))
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

    @MainActor
    func testConclusionIsShownAndClaimsTakeOnlyOneLine() {
        let questionOnly = readPage(withConclusion: false)
        let withAnswer = readPage(withConclusion: true)
        let heavy = readPage(withConclusion: true, claims: Self.probeClaims, unverified: Self.probeUnverified)
        let doubled = readPage(withConclusion: true, claims: 300, unverified: 8)

        let conclusionHeight = withAnswer.transcriptContentHeight - questionOnly.transcriptContentHeight
        let claimsExtra = heavy.transcriptContentHeight - withAnswer.transcriptContentHeight
        print("🧪 整页读数（900×620）：只有提问 内容高 \(questionOnly.transcriptContentHeight)pt"
              + " / +结论 \(withAnswer.transcriptContentHeight)pt（结论 \(conclusionHeight)pt）"
              + " / +\(Self.probeClaims) 条台账 \(heavy.transcriptContentHeight)pt"
              + "（台账多占 \(claimsExtra)pt，一行 = \(AgentClaimAuditRow.summaryHeight)pt）"
              + " / +300 条台账 \(doubled.transcriptContentHeight)pt")
        print("🧪 对话区视口：\(NSStringFromRect(questionOnly.transcriptViewport))"
              + " / 整页理想高 \(questionOnly.fittingHeight)pt（窗口 \(Self.pageSize.height)pt）")

        XCTAssertGreaterThan(questionOnly.transcriptContentHeight, 0, "对话区内容高 0 ⇒ 没量到滚动容器")
        XCTAssertTrue(Self.conclusionVisibilityViolations(height: conclusionHeight).isEmpty,
                      Self.conclusionVisibilityViolations(height: conclusionHeight).joined(separator: "；"))
        XCTAssertGreaterThan(conclusionHeight, AgentClaimAuditRow.summaryHeight,
                             "结论只占 \(conclusionHeight)pt ⇒ 那段 30 行的回答被折了")

        // 台账那一段只许多占**一行**（判的是对话区**内容高**：页面被撑开的那个量）。
        XCTAssertTrue(Self.pageExtraViolations(extra: claimsExtra).isEmpty,
                      Self.pageExtraViolations(extra: claimsExtra).joined(separator: "；"))
        // 整页**理想高**只作参考读数：它把块间距也算进去（不是等式判据，同
        // `AgentChatCompactionProbeTests` 的登记），真正的撑开量是上面那个内容高。
        print("🧪 整页理想高：只有结论 \(withAnswer.fittingHeight)pt → 带台账 \(heavy.fittingHeight)pt"
              + "（多 \(heavy.fittingHeight - withAnswer.fittingHeight)pt，含块间距）")
        XCTAssertEqual(doubled.transcriptContentHeight, heavy.transcriptContentHeight, accuracy: 0.5,
                       "台账从 \(Self.probeClaims) 条加到 300 条，对话区内容高从 "
                           + "\(heavy.transcriptContentHeight)pt 变成 \(doubled.transcriptContentHeight)pt"
                           + " ⇒ 折成一行这件事是假的（条数还在往上铺）")

        // 对话区视口不因台账变小（内容再多也只换内容高，不挤视口）。
        for (label, reading) in [("只有提问", questionOnly), ("带结论", withAnswer),
                                 ("29 条台账", heavy), ("300 条台账", doubled)] {
            XCTAssertEqual(reading.transcriptViewport.height, questionOnly.transcriptViewport.height,
                           accuracy: 0.5,
                           "\(label)态对话区视口高 \(reading.transcriptViewport.height)pt ≠ 基线"
                               + " \(questionOnly.transcriptViewport.height)pt")
        }

        // 默认显示开关下：结论**不许被折**（这条是「默认展开」的硬口径）。
        let defaultPreferences = AgentDisplayPreferences()
        let issues = Self.conclusionFoldViolations(text: conclusion(), preferences: defaultPreferences)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
    }

    // MARK: - ④ 反例：同一套判据喂给缺陷形态，必须报红

    /// 缺陷形态 ①：台账明细**不封顶**（有多少铺多少，没有 `ScrollView`）—— 改造前的样子。
    private struct UnboundedClaimRows: View {
        let audit: AgentClaimAudit
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(AgentClaimAuditRow.summaryText(for: audit, expanded: true,
                                                    language: .simplifiedChinese))
                    .font(Theme.font(.mono))
                    .frame(height: AgentClaimAuditRow.summaryHeight)
                ForEach(Array(audit.sections.enumerated()), id: \.offset) { _, section in
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(Theme.font(.mono))
                            .frame(height: AgentClaimAuditRow.lineHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 缺陷形态 ②：台账整块**原样铺进一个 `Text`**（真机上那 29 条 + 出处行的老写法）。
    private struct RawClaimBlock: View {
        let text: String
        var body: some View {
            Text(text)
                .font(Theme.font(.mono))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @MainActor
    func testCounterExamplesAreRed() {
        // ① 明细不封顶 ⇒ 展开判据必须报红。
        let unbounded = height(UnboundedClaimRows(audit: audit(total: Self.probeClaims,
                                                               unverified: Self.probeUnverified)))
        let unboundedIssues = Self.expandedViolations(height: unbounded)
        print("🧪 反例①（明细无上限，\(Self.probeClaims) 条台账）：\(unbounded)pt / 上限 "
              + "\(AgentClaimAuditRow.expandedMaxHeight)pt ⇒ \(unboundedIssues.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(unboundedIssues.isEmpty,
                       "去掉明细上限（\(Self.probeClaims) 条铺成 \(unbounded)pt）判据仍然绿 ⇒ 判据没有牙齿")

        // ② 整块台账原样铺（老写法）⇒ 折叠判据必须报红。
        let raw = height(RawClaimBlock(text: block(total: Self.probeClaims, unverified: Self.probeUnverified)))
        let rawIssues = Self.collapsedViolations(height: raw)
        print("🧪 反例②（整块台账原样铺，\(Self.probeClaims) 条）：\(raw)pt / 一行上限 "
              + "\(AgentClaimAuditRow.summaryHeight)pt ⇒ \(rawIssues.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(rawIssues.isEmpty, "整块台账铺开（\(raw)pt）判据仍然绿 ⇒ 判据没有牙齿")

        // ③ 结论按 `2+2` 折起来 ⇒ 折叠判据必须报红。
        var folded = AgentDisplayPreferences()
        folded.longPreview = .headTail(head: 2, tail: 2)
        let foldIssues = Self.conclusionFoldViolations(text: conclusion(), preferences: folded)
        print("🧪 反例③（结论按首 2 末 2 折）：\(foldIssues.isEmpty ? "假绿 ❌" : "判红 ✅ — \(foldIssues[0])")")
        XCTAssertFalse(foldIssues.isEmpty, "把结论折起来判据仍然绿 ⇒ 判据没有牙齿")

        // ④ 结论被折没（高度 0）⇒ 可见性判据必须报红。
        let missing = Self.conclusionVisibilityViolations(height: 0)
        print("🧪 反例④（结论高度 0）：\(missing.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(missing.isEmpty, "结论高度 0 判据仍然绿 ⇒ 判据没有牙齿")

        // ⑤ 整页级反例：台账恢复成**改造前那样整块铺进消息流**（首行是人话、没有机器头
        //    ⇒ 界面认不出它是台账，只能原样铺开）⇒ 整页被判据判红。
        let legacyBody = block(total: Self.probeClaims, unverified: Self.probeUnverified)
            .components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        let clean = readPage(withConclusion: true)
        let legacy = readPage(withConclusion: true, claims: Self.probeClaims,
                              unverified: Self.probeUnverified, noticeText: legacyBody)
        let legacyExtra = legacy.transcriptContentHeight - clean.transcriptContentHeight
        let legacyIssues = Self.pageExtraViolations(extra: legacyExtra)
        print("🧪 反例⑤（台账整块铺进消息流，\(Self.probeClaims) 条）：对话区内容高 \(legacy.transcriptContentHeight)pt"
              + " 比只有结论的 \(clean.transcriptContentHeight)pt 多 \(legacyExtra)pt ⇒ "
              + "\(legacyIssues.isEmpty ? "假绿 ❌" : "判红 ✅")")
        XCTAssertFalse(legacyIssues.isEmpty,
                       "整块台账铺进消息流（多 \(legacyExtra)pt）判据仍然绿 ⇒ 判据没有牙齿")
    }
}
