import XCTest
@testable import DoyahCore

/// SQL 编辑器的**行内灰字**（`FR-EDIT-57` 的 SQL 形态）。
///
/// 与代码编辑器那 18 例的分工：那边的口径（只画不写 / 只收单行 / 长度上限 / 词中间不出 …）
/// 已在 `InlineGhostCompletionTests` 钉住，这里只判**SQL 这条路多出来的那几条**：
/// 候选来自 `QueryCompletion`（方言 + 查询记忆）、关键字**大小写不敏感**、
/// 接受后写进正文的是候选的规范形态。这些事在 AppKit 回调里只能靠手点看出来。
final class InlineGhostSQLTests: XCTestCase {

    private let dialect: SQLDialect = SQLDialectFactory.make(for: .postgresql)

    private func memory(_ sql: String, connections: Set<String> = ["生产库"]) -> QueryMemory.Memory {
        QueryMemory.Memory(
            fingerprint: QueryMemory.coarseFingerprint(sql),
            latestSQL: sql,
            variantCount: 1,
            runCount: 1,
            days: ["2026-10-18"],
            connections: connections,
            lastExecutedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func ghost(
        _ text: String,
        caret: Int? = nil,
        selectionLength: Int = 0,
        memory index: QueryMemory.Index = QueryMemory.Index(),
        connection: String? = nil
    ) -> InlineGhostSuggestion? {
        let location = caret ?? (text as NSString).length
        return InlineGhostCompletion.suggestion(
            in: text,
            selection: NSRange(location: location, length: selectionLength),
            language: .sql,
            candidateProvider: { prefix in
                QueryCompletion.ghostCandidates(
                    prefix: prefix,
                    dialect: self.dialect,
                    memory: index,
                    connection: connection
                )
            }
        )
    }

    // MARK: 关键字：大小写不敏感，写进去的是规范形态

    /// 敲 `sel` 出灰字 `ECT`，Tab 之后正文是 `SELECT`（不是把灰字接在用户输入后面变成 `selECT`）。
    func testKeywordGhostsCaseInsensitively() {
        let suggestion = ghost("sel")
        XCTAssertEqual(suggestion?.insertText, "SELECT")
        XCTAssertEqual(suggestion?.ghost, "ECT")
        XCTAssertEqual(suggestion?.kind, .keyword)
        XCTAssertEqual(suggestion?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(suggestion?.caretOffset, 6)

        let text = "sel" as NSString
        XCTAssertEqual(
            text.replacingCharacters(in: suggestion!.range, with: suggestion!.insertText),
            "SELECT"
        )
    }

    /// 内置函数单独一类（界面按类别淡），且候选形态保持方言表里的小写原文。
    func testBuiltinKindIsClassified() {
        let suggestion = ghost("cou")
        XCTAssertEqual(suggestion?.insertText, "count")
        XCTAssertEqual(suggestion?.ghost, "nt")
        XCTAssertEqual(suggestion?.kind, .builtin)
    }

    /// 只替换**当前这个词**：前面隔着空格 / 标点都不带进来。
    func testGhostReplacesOnlyTheCurrentWord() {
        let text = "select a from t wher"
        let suggestion = ghost(text)
        XCTAssertEqual(suggestion?.insertText, "WHERE")
        XCTAssertEqual(suggestion?.ghost, "E")
        XCTAssertEqual(suggestion?.range, (text as NSString).range(of: "wher"))
    }

    // MARK: 查询记忆（与候选列表同一份：方言在前、记忆在后）

    /// 记忆里跑过的整句也能当灰字 —— **但只在用户敲的就是这句的开头时**（灰字替换的是"当前这个词"）。
    func testMemoryCandidateGhostsAtStatementStart() {
        let index = QueryMemory.Index(memories: [memory("tmp_orders_backup")])
        let suggestion = ghost("tmp_", memory: index, connection: "生产库")
        XCTAssertEqual(suggestion?.insertText, "tmp_orders_backup")
        XCTAssertEqual(suggestion?.ghost, "orders_backup")
        XCTAssertEqual(suggestion?.kind, .word)
    }

    /// 语句**中间**那段前缀不拿整句来补：整句不是这个词的尾巴，接了就把半句话换成一整句。
    func testMemoryCandidateIsNotGhostedMidStatement() {
        let index = QueryMemory.Index(memories: [memory("select id from t_user")])
        XCTAssertNil(ghost("select id from t_us", memory: index, connection: "生产库"))
    }

    /// 别的连接的记忆一条都不给（按连接隔离的口径在 `QueryCompletion`，这里确认灰字这条路也照办）。
    func testMemoryFromOtherConnectionIsNotGhosted() {
        let index = QueryMemory.Index(memories: [memory("tmp_orders_backup")])
        XCTAssertNil(ghost("tmp_", memory: index, connection: "测试库"))
    }

    // MARK: 与代码编辑器共用的口径在这里同样生效

    /// 注释里不出（本行词法切片能判出来的那一档）。
    func testInsideCommentGivesNothing() {
        XCTAssertNil(ghost("-- sel"))
    }

    /// 有选区时不出：一按 Tab 就把选中内容换掉是最坏的"智能"。
    func testSelectionGivesNothing() {
        XCTAssertNil(ghost("sel", selectionLength: 2))
    }

    /// 前缀没过口径检查时**根本不问候选**（每一击键都跑，别白算一遍）。
    func testProviderIsNotCalledWhenPrefixIsRejected() {
        var called = false
        let suggestion = InlineGhostCompletion.suggestion(
            in: "r",
            selection: NSRange(location: 1, length: 0),
            language: .sql,
            candidateProvider: { _ in
                called = true
                return [InlineGhostCandidate(insertText: "ROLLBACK", caseInsensitive: true)]
            }
        )
        XCTAssertNil(suggestion)
        XCTAssertFalse(called, "前缀太短就该在算候选之前停手")
    }

    /// 跨行候选（多行 SQL）不画：灰字的语义是"补完当前这个词"。
    func testMultiLineCandidateIsNotGhosted() {
        let suggestion = InlineGhostCompletion.suggestion(
            in: "sel",
            selection: NSRange(location: 3, length: 0),
            language: .sql,
            candidateProvider: { _ in
                [InlineGhostCandidate(insertText: "SELECT\n  *", kind: .snippet, caseInsensitive: true)]
            }
        )
        XCTAssertNil(suggestion)
    }

    /// 候选没声明 `caseInsensitive` 时仍然逐字相同（代码编辑器那条路不受影响）。
    func testCaseSensitiveCandidateStillRequiresExactCase() {
        func suggest(_ text: String) -> InlineGhostSuggestion? {
            InlineGhostCompletion.suggestion(
                in: text,
                selection: NSRange(location: (text as NSString).length, length: 0),
                language: .javascript,
                candidateProvider: { _ in
                    [InlineGhostCandidate(insertText: "return", kind: .keyword)]
                }
            )
        }
        XCTAssertEqual(suggest("ret")?.ghost, "urn")
        XCTAssertNil(suggest("RET"))
    }

    // MARK: 候选形状

    /// 全部候选都声明大小写不敏感；顺序仍与候选列表一致（方言在前）。
    func testGhostCandidatesKeepDialectFirstAndDeclareCaseInsensitivity() {
        let index = QueryMemory.Index(memories: [memory("select * from orders")])
        let candidates = QueryCompletion.ghostCandidates(
            prefix: "se", dialect: dialect, memory: index, connection: "生产库"
        )
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.insertText, "SELECT", "\(candidates.map(\.insertText))")
        XCTAssertTrue(candidates.allSatisfy(\.caseInsensitive))
    }
}
