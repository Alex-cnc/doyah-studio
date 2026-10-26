import XCTest
@testable import DoyahCore

/// `FR-AGT-QUAL-VERIFY-003` / `FR-AGT-QUAL-VERIFY-004` 的**上屏判据**（逐条标签的视图面）。
///
/// 这两条此前只到「一整段文字」（`AgentClaim.rendered`）：Core 算得出、界面也只挂得了一条汇总提示条，
/// **答复正文里逐条结论仍看不到自己凭什么成立**。本文件守的是「逐行投影」这一层：
///
/// ① 每条结论一行、带自己的档位字形与标签，**三档不许互相冒充**（003 ①③）；
/// ② 出处跟在它那条结论下面（004 ①）、带可复制文本（004 ②）；
/// ③ 顺序与答复里出现顺序一致、同一出处不重复贴（噪音判据）；
/// ④ 边界：一条结论都没有 ⇒ 不出块（不印「0 条结论」）；空替代方案不占行。
final class AgentClaimTraceTests: XCTestCase {

    private let fileBasis = AgentClaimBasis.file(path: "Core/AgentSession.swift", line: 312)
    private let otherBasis = AgentClaimBasis.commandOutput(command: "swift test --filter AgentLoopTests",
                                                           exitCode: 0)

    private func trace(_ claims: [AgentClaim]) -> AgentAnswerProvenance {
        AgentAnswerProvenance(claims: claims)
    }

    // MARK: - ① 三档各行其道（正常面）

    /// 三档必须是**三种**行首字形，而且标签与字形一一对应 —— 这是 003 ①「能区分」的最小证据。
    func testThreeStatusesGetThreeDistinctGlyphsAndLabels() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "会话按工作区隔离", status: .verified,
                       bases: [fileBasis], confidence: 0.98),
            AgentClaim(statement: "归档面不会被列表扫到", status: .inferred,
                       bases: [fileBasis], confidence: 0.7),
            AgentClaim(statement: "压测还没跑", status: .unverified,
                       confidence: 0.2, alternatives: ["先跑 1000 条再说"]),
        ]))

        let claimRows = rows.filter { $0.kind == .claim }
        XCTAssertEqual(claimRows.count, 3)
        XCTAssertEqual(claimRows.map(\.status), [.verified, .inferred, .unverified])
        let glyphs = claimRows.compactMap { $0.status.map(AgentClaimTrace.glyph(for:)) }
        XCTAssertEqual(glyphs, ["✓", "≈", "?"])
        XCTAssertEqual(Set(glyphs).count, 3, "三档不许有两档共用同一个字形")
    }

    /// 「没验证」是独立一档：块里不许出现「已验证」的标签去描述它（003 ③ 的负例）。
    func testUnverifiedClaimNeverRendersAsVerified() {
        let block = AgentClaimTrace.block(for: trace([
            AgentClaim(statement: "锁阻塞的原因还没查到", status: .unverified,
                       confidence: 0.2, alternatives: ["看 pg_locks"]),
        ]), language: .simplifiedChinese)

        let text = try! XCTUnwrap(block)
        XCTAssertTrue(text.contains("[没验证]"), text)
        XCTAssertFalse(text.contains("[已验证]"), "没验证的结论不许被标成已验证：\(text)")
        // 首行是汇总，结论行在其后 —— 字形跟档位走（`?` 不是 `✓`）。
        let claimLine = text.components(separatedBy: "\n").first { $0.contains("锁阻塞") } ?? ""
        XCTAssertTrue(claimLine.hasPrefix("?"), "行首字形要跟档位走：\(claimLine)")
    }

    // MARK: - ② 出处与替代方案（004 ① ②）

    /// 出处单独占一行、缩进在结论下面，且带可复制文本。
    func testBasisGetsItsOwnIndentedRowWithCopyableText() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "压缩只在会话边界发生", status: .verified,
                       bases: [fileBasis], confidence: 0.98),
        ]))
        XCTAssertEqual(rows.map(\.kind), [.claim, .basis])
        let basis = try! XCTUnwrap(rows.last)
        XCTAssertTrue(basis.text.contains("Core/AgentSession.swift:312"), basis.text)
        XCTAssertEqual(basis.copyableBasis, "Core/AgentSession.swift:312")
        XCTAssertNil(basis.status, "出处行本身不表达把握")
        // 出处行的可交付性跟着它的结论走
        XCTAssertTrue(basis.isDeliverable)
    }

    /// 同一条结论里同一个出处出现两次 ⇒ 只出一行（贴两遍是噪音，不是「更可溯源」）。
    func testDuplicateBasisWithinOneClaimRendersOnce() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "工具注册表是唯一真源", status: .verified,
                       bases: [fileBasis, fileBasis, otherBasis], confidence: 0.98),
        ]))
        XCTAssertEqual(rows.filter { $0.kind == .basis }.count, 2, "两条不同出处 ⇒ 两行")
        XCTAssertEqual(rows.filter { $0.kind == .claim }.count, 1)
    }

    /// 把握低且给了替代方案 ⇒ 出一行「备选」；把握高 ⇒ 不出（不给人多余的选择）。
    func testAlternativeRowOnlyWhenLowConfidenceCarriesOne() {
        let withAlt = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "大概是锁等待", status: .inferred, bases: [fileBasis],
                       confidence: 0.5, alternatives: ["也可能是 IO 打满"]),
        ]))
        XCTAssertTrue(withAlt.contains { $0.kind == .alternative })
        XCTAssertEqual(withAlt.first { $0.kind == .alternative }?.text, "也可能是 IO 打满")

        let confident = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "函数在 L312", status: .verified, bases: [fileBasis],
                       confidence: 0.98),
        ]))
        XCTAssertFalse(confident.contains { $0.kind == .alternative })
    }

    // MARK: - 该拒：不合格的结论不许冒充合格

    /// 没出处的结论 ⇒ 它那一行标 `isDeliverable == false`（004 ③ 的上屏面）。
    func testClaimWithoutBasisIsMarkedUndeliverable() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "性能提升了三倍", status: .unverified,
                       confidence: 0.2, alternatives: ["先量一遍再说"]),
        ]))
        XCTAssertFalse(try! XCTUnwrap(rows.first).isDeliverable)
        XCTAssertTrue(rows.allSatisfy { !$0.isDeliverable },
                      "一条没出处的结论，它的出处行 / 替代方案行也不许被算成可交付")
    }

    /// 低把握没给替代方案 ⇒ 那条结论不合格（003 ② 的负例），但它**照样上屏** ——
    /// 藏起来等于把「我不确定」也一起藏了。
    func testLowConfidenceWithoutAlternativeStaysVisibleButUndeliverable() {
        let claim = AgentClaim(statement: "应该是网络抖动", status: .inferred,
                               bases: [fileBasis], confidence: 0.4)
        let rows = AgentClaimTrace.rows(for: trace([claim]))
        let claimRow = try! XCTUnwrap(rows.first)
        XCTAssertEqual(claimRow.kind, .claim)
        XCTAssertEqual(claimRow.text, "应该是网络抖动")
        XCTAssertFalse(claimRow.isDeliverable)
        XCTAssertFalse(rows.contains { $0.kind == .alternative })
    }

    /// 接线（`App` 面）：界面收尾那条路径必须真的把块挂上去。
    ///
    /// 为什么扫源码而不是跑模型：`finish` 只能由一轮真跑的结果触发（要真模型 / 真工具），
    /// 那种判据只能人工点验。这里钉的是**接线本身在不在**（缺了就是「Core 算得出、界面不显示」，
    /// 正是本条上一批留下的缺口），跑得对不对由上一条块形状判据与本文件其余用例保证。
    func testChatModelFinishAppendsClaimTraceNotice() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("App/AgentChatModel.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("AgentClaimTrace.block(for: provenance"),
                      "界面收尾没把逐条出处块挂上去 ⇒ 正文里仍看不到每条结论凭什么成立")
        XCTAssertTrue(source.contains("state.appendNotice(trace)"),
                      "算出来的块没人接收：要落进消息流（时间线事件），不是只算一遍丢掉")
        // 反向：块**不许**拿去改写答复正文（改了就变成替模型发言，代码块还会被切碎）。
        XCTAssertFalse(source.contains("message.text = trace"),
                       "出处块不许覆盖答复正文")
    }

    // MARK: - 边界

    /// 一条结论都没有 ⇒ 不出块（不印「0 条结论」：那行字没有任何可核的东西）。
    func testEmptyProvenanceProducesNoBlock() {
        XCTAssertNil(AgentClaimTrace.block(for: trace([]), language: .simplifiedChinese))
        XCTAssertTrue(AgentClaimTrace.rows(for: trace([])).isEmpty)
    }

    /// 空白替代方案不占行（模型给了个空串，不该在界面上留下一行「备选：」）。
    func testBlankAlternativeLeavesNoRow() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "大概是锁等待", status: .unverified,
                       confidence: 0.2, alternatives: ["   ", ""]),
        ]))
        XCTAssertFalse(rows.contains { $0.kind == .alternative })
    }

    /// 顺序：结论按答复里出现的顺序排，每条结论的出处紧跟在它后面（不许先列完结论再列出处）。
    func testRowsKeepAnswerOrderAndBasisFollowsItsClaim() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "第一条", status: .verified, bases: [fileBasis], confidence: 0.98),
            AgentClaim(statement: "第二条", status: .verified, bases: [otherBasis], confidence: 0.98),
        ]))
        XCTAssertEqual(rows.map(\.kind), [.claim, .basis, .claim, .basis])
        XCTAssertEqual(rows[0].text, "第一条")
        XCTAssertTrue(try! XCTUnwrap(rows[1].text).contains("AgentSession.swift"))
        XCTAssertEqual(rows[2].text, "第二条")
        XCTAssertTrue(try! XCTUnwrap(rows[3].text).contains("AgentLoopTests"))
    }

    /// 块的形状：首行是汇总，其后逐行；行数与 rows 一一对应（不多不少）。
    func testBlockHasSummaryThenOneLinePerRow() {
        let provenance = trace([
            AgentClaim(statement: "结论甲", status: .verified, bases: [fileBasis], confidence: 0.98),
            AgentClaim(statement: "结论乙", status: .unverified, confidence: 0.2,
                       alternatives: ["换个查法"]),
        ])
        let block = try! XCTUnwrap(AgentClaimTrace.block(for: provenance, language: .simplifiedChinese))
        let lines = block.components(separatedBy: "\n")
        XCTAssertEqual(lines.count - 1, AgentClaimTrace.rows(for: provenance).count,
                       "首行汇总之外，每行对应一条 row：\(block)")
        XCTAssertTrue(lines[0].hasPrefix("2 条结论"), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("✓ [已验证] 结论甲"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("  出处："), "出处行要缩进：\(lines[2])")
    }

    /// 语言作形参：同一份账换英文 ⇒ 标签与两个前缀都换，中文一处不漏（L-47）。
    func testBlockFollowsLanguageParameter() {
        let provenance = trace([
            AgentClaim(statement: "ok", status: .verified, bases: [fileBasis], confidence: 0.98),
        ])
        let en = try! XCTUnwrap(AgentClaimTrace.block(for: provenance, language: .english))
        XCTAssertTrue(en.contains("[Verified]"), en)
        XCTAssertTrue(en.contains("Source:"), en)
        XCTAssertFalse(en.contains("出处"), "英文面不许漏中文：\(en)")
        XCTAssertFalse(en.contains("已验证"), "英文面不许漏中文：\(en)")
    }

    /// 把握百分比是四舍五入到整数的 0…100（界面拿它当读数印，不自己再算一遍）。
    func testConfidencePercentRounds() {
        let rows = AgentClaimTrace.rows(for: trace([
            AgentClaim(statement: "接近确定", status: .verified, bases: [fileBasis], confidence: 0.976),
            AgentClaim(statement: "很低", status: .unverified, confidence: 0.024),
        ]))
        let percents = rows.filter { $0.kind == .claim }.compactMap(\.confidencePercent)
        XCTAssertEqual(percents, [98, 2])
        XCTAssertTrue(rows.filter { $0.kind == .basis }.allSatisfy { $0.confidencePercent == nil },
                      "出处行没有「把握」可言")
    }
}
