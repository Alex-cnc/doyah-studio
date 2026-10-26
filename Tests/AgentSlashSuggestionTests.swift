import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-014` 界面输入侧：斜杠命令的**候选提示**。
///
/// 判据重心在「该给才给、不该给就空」—— 猜参数是比不给候选更坏的错。
final class AgentSlashSuggestionTests: XCTestCase {

    private let completer = AgentSlashCompleter()

    // 只敲了 `/` ⇒ 全清单，按固定顺序（help 打头、stop 收尾）
    func testBareSlashListsWholeCatalogueInFixedOrder() {
        let got = completer.suggestions(for: "/")
        XCTAssertEqual(got.map(\.name), ["help", "model", "clear", "compact", "search", "sessions", "theme", "stop"])
    }

    // 前缀匹配
    func testPrefixMatches() {
        XCTAssertEqual(completer.suggestions(for: "/cl").map(\.name), ["clear"])
        XCTAssertEqual(completer.suggestions(for: "/c").map(\.name), ["clear", "compact"])
    }

    // 大小写不敏感
    func testCaseInsensitive() {
        XCTAssertEqual(completer.suggestions(for: "/HE").map(\.name), ["help"])
        XCTAssertEqual(completer.suggestions(for: "/Sess").map(\.name), ["sessions"])
    }

    // 精确命中的排第一（`/stop` 只有一条时也要在第一）
    func testExactMatchComesFirst() {
        let got = completer.suggestions(for: "/stop")
        XCTAssertEqual(got.first?.name, "stop")
    }

    // 别名 /sessions 与 /search 同指，候选里两个都能出
    func testAliasSessionsPointsAtSearch() {
        let got = completer.suggestions(for: "/sess")
        XCTAssertEqual(got.map(\.name), ["sessions"])
        XCTAssertEqual(got.first?.kind, .search)
    }

    // 进入参数区（有空格）⇒ 一条候选都不给：参数不猜
    func testNoSuggestionsOnceArgumentsStart() {
        XCTAssertTrue(completer.suggestions(for: "/model ").isEmpty)
        XCTAssertTrue(completer.suggestions(for: "/theme 科技蓝").isEmpty)
    }

    // 不是斜杠开头 / 名前有空白 ⇒ 空
    func testNonCommandsGetNothing() {
        XCTAssertTrue(completer.suggestions(for: "hello").isEmpty)
        XCTAssertTrue(completer.suggestions(for: " /help").isEmpty, "名前有空白不当命令")
        XCTAssertTrue(completer.suggestions(for: "//help").isEmpty)
    }

    // 不认识的前缀 ⇒ 空数组，不拿相近的顶
    func testUnknownPrefixYieldsNothing() {
        XCTAssertTrue(completer.suggestions(for: "/zzz").isEmpty)
    }

    // 插入文本：要参数的命令带尾随空格，不要参数的不带
    func testInsertionText() {
        XCTAssertEqual(completer.suggestions(for: "/mo").first?.insertion, "/model ")
        XCTAssertEqual(completer.suggestions(for: "/he").first?.insertion, "/help")
        XCTAssertEqual(completer.suggestions(for: "/st").first?.insertion, "/stop")
    }

    // 上限生效，且顺序仍是固定顺序
    func testLimitIsRespected() {
        let got = completer.suggestions(for: "/", limit: 3)
        XCTAssertEqual(got.map(\.name), ["help", "model", "clear"])
    }

    // 说明文案中英双语都有，且不是把命令名抄一遍
    func testDetailsAreBilingualAndMeaningful() {
        let chinese = AgentSlashCompleter.detail(for: .model, language: .simplifiedChinese)
        let english = AgentSlashCompleter.detail(for: .model, language: .english)
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertFalse(english.isEmpty)
        XCTAssertNotEqual(chinese, english)
        XCTAssertNotEqual(chinese, "model")
    }

    // 候选一旦给出，插回去必须能被解析器认成同一条命令（提示与解析不脱节）
    func testInsertionParsesBackToItsOwnKind() {
        let parser = AgentSlashCommandParser()
        for suggestion in completer.suggestions(for: "/") where !suggestion.kind.requiresArgument {
            guard case let .parsed(kind, _) = parser.parse(suggestion.insertion) else {
                return XCTFail("候选 \(suggestion.insertion) 解析不出来")
            }
            XCTAssertEqual(kind, suggestion.kind)
        }
    }
}
