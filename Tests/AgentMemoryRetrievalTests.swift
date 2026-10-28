import XCTest
@testable import DoyahCore

/// 记忆相关性检索（`FR-AGT-KNOW-MEM-007`）的机械判据。
///
/// 盯住三处最容易做松的：**零命中必须为空**（不许拿「最近用过」凑数）、
/// **时间只做同分平手**（新而无关的不许挤掉相关的）、**命中要能说理由**。
final class AgentMemoryRetrievalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ id: String,
                       _ note: String,
                       daysAgo: Int = 0,
                       kind: MemoryKind = .routine) -> AgentMemoryEntry {
        AgentMemoryEntry(id: id,
                         workspace: "ws-1",
                         connection: "prod",
                         kind: kind.rawValue,
                         note: note,
                         fingerprint: id,
                         firstSeenAt: now,
                         lastUsedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                         useCount: 1)
    }

    // MARK: - 宁可少给

    func testEmptyQueryReturnsNothing() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "迁移要先跑对账")], query: "  ")
        XCTAssertTrue(hits.isEmpty, "空查询不许靠「最近用过」凑数")
    }

    func testUnrelatedQueryReturnsNothing() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "迁移要先跑对账")], query: "今天天气怎么样")
        XCTAssertTrue(hits.isEmpty, "一条都不相关就该是空")
    }

    // MARK: - 命中理由

    func testHitCarriesMatchedTermsAsReason() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "迁移之前先跑对账，再关连接池")],
                                                 query: "迁移 对账")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].score, 2)
        XCTAssertEqual(Set(hits[0].matchedTerms), ["迁移", "对账"])
        XCTAssertTrue(hits[0].reason.contains("迁移"))
        XCTAssertTrue(hits[0].reason.contains("2"))
    }

    // MARK: - 排序：先相关，时间只做平手

    func testMoreMatchesRankFirst() {
        let weak = entry("m-weak", "迁移", daysAgo: 0)
        let strong = entry("m-strong", "迁移要先跑对账", daysAgo: 30)
        let hits = AgentMemoryRetrieval.retrieve([weak, strong], query: "迁移 对账")
        XCTAssertEqual(hits.first?.entry.id, "m-strong", "命中多的在前，哪怕它更旧")
    }

    func testNewerButUnrelatedNeverDisplacesRelevant() {
        let relevant = entry("m-old", "发布前先跑 verify-core", daysAgo: 90)
        let irrelevantButNew = entry("m-new", "这台机器的 Postgres 在 217", daysAgo: 0)
        let hits = AgentMemoryRetrieval.retrieve([irrelevantButNew, relevant], query: "verify-core")
        XCTAssertEqual(hits.map(\.entry.id), ["m-old"], "新的无关项不许挤进来")
    }

    func testTiesBreakByRecencyThenID() {
        let older = entry("b", "对账在迁移之后", daysAgo: 5)
        let newer = entry("a", "迁移后要对账", daysAgo: 1)
        let hits = AgentMemoryRetrieval.retrieve([older, newer], query: "对账")
        XCTAssertEqual(hits.map(\.entry.id), ["a", "b"], "同分先看最近用到")
    }

    // MARK: - 上界是上界，不是配额

    func testLimitIsAnUpperBoundNotAQuota() {
        let entries = (1...10).map { entry("m\($0)", "迁移第 \($0) 步") }
        let hits = AgentMemoryRetrieval.retrieve(entries, query: "迁移", limit: 3)
        XCTAssertEqual(hits.count, 3)

        let fewer = AgentMemoryRetrieval.retrieve([entry("m1", "迁移")], query: "迁移", limit: 8)
        XCTAssertEqual(fewer.count, 1, "只有一条命中就只给一条")
    }

    // MARK: - 切词

    func testEnglishTermsAreCaseInsensitive() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "run VERIFY-CORE before release")],
                                                 query: "verify-core")
        XCTAssertEqual(hits.count, 1)
    }

    func testChineseBigramsMatch() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "迁移之前先跑对账")], query: "对账")
        XCTAssertEqual(hits.count, 1, "两字窗口要能命中中文词")
    }

    func testSingleCJKCharacterStillMatches() {
        let hits = AgentMemoryRetrieval.retrieve([entry("m1", "这条讲门禁")], query: "门")
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - 进上下文的形态

    func testReferencesUseMemoryURIAndSkipExpired() {
        let usable = entry("m1", "迁移要先跑对账")
        let refs = AgentMemoryRetrieval.references(from: [usable], query: "迁移", now: now)
        XCTAssertEqual(refs.count, 1)
        guard case .file(let path, let text) = refs[0] else { return XCTFail("记忆走 .file 通道") }
        XCTAssertTrue(path.hasPrefix("memory://"))
        XCTAssertEqual(text, "迁移要先跑对账")

        XCTAssertTrue(AgentMemoryRetrieval.references(from: [usable], query: "无关词", now: now).isEmpty,
                      "不相干就一条都不挂")
    }
}
