import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-014/015`：斜杠命令本地解析、大小写不敏感、带参、单行审计、改配置走审批。
final class AgentSlashCommandTests: XCTestCase {
    private let parser = AgentSlashCommandParser()

    func testParsesKnownCommandsCaseInsensitively() {
        XCTAssertEqual(parser.parse("/HELP"), .parsed(kind: .help, argument: ""))
        XCTAssertEqual(parser.parse("  /Stop "), .parsed(kind: .stop, argument: ""))
        XCTAssertEqual(parser.parse("/Clear"), .parsed(kind: .clear, argument: ""))
        XCTAssertEqual(parser.parse("/compact"), .parsed(kind: .compact, argument: ""))
    }

    func testCarriesArgumentVerbatim() {
        XCTAssertEqual(parser.parse("/model gpt-4o"), .parsed(kind: .model, argument: "gpt-4o"))
        XCTAssertEqual(parser.parse("/theme 深色"), .parsed(kind: .theme, argument: "深色"))
        XCTAssertEqual(parser.parse("/sessions 备份"), .parsed(kind: .search, argument: "备份"))
    }

    func testMissingArgumentIsReportedNotDefaulted() {
        XCTAssertEqual(parser.parse("/model"), .missingArgument(kind: .model))
        XCTAssertEqual(parser.parse("/search   "), .missingArgument(kind: .search))
    }

    func testUnknownCommandIsNotGuessed() {
        XCTAssertEqual(parser.parse("/deploy prod"), .unknown(name: "deploy"))
    }

    func testPlainTextIsNotACommand() {
        XCTAssertEqual(parser.parse("帮我查一下慢查询"), .notACommand)
        XCTAssertEqual(parser.parse("/ leading-space"), .notACommand)
        XCTAssertEqual(parser.parse(""), .notACommand)
    }

    func testAuditLineIsAlwaysSingleLine() {
        let multiline = parser.parse("/model foo\nDB=secret\nrm -rf /")
        let line = multiline.auditLine
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.hasPrefix("slash /model"))
        XCTAssertEqual(parser.parse("/deploy\nline2").auditLine.split(separator: "\n").count, 1)
        XCTAssertEqual(parser.parse("/model a\nb").auditLine.filter { $0 == "\n" }.count, 0)
    }

    func testConfigurationCommandsRequireApproval() {
        XCTAssertTrue(AgentSlashCommandKind.model.mutatesConfiguration)
        XCTAssertTrue(AgentSlashCommandKind.theme.mutatesConfiguration)
        XCTAssertFalse(AgentSlashCommandKind.help.mutatesConfiguration)
        XCTAssertFalse(AgentSlashCommandKind.stop.mutatesConfiguration)
        XCTAssertEqual(AgentSlashCommandKind.allCases.count, 9)
    }

    func testAllSevenDocumentedCommandsExist() {
        let documented = AgentSlashCommandParser().helpText
        // /sessions 的语义分类是 .search（别名），帮助里按 /sessions 写
        let documentedName: [AgentSlashCommandKind: String] = [.search: "sessions"]
        for kind in AgentSlashCommandKind.allCases {
            let name = documentedName[kind] ?? kind.rawValue
            XCTAssertTrue(documented.contains { $0.hasPrefix("/\(name)") }, "帮助里缺 /\(name)")
        }
        XCTAssertTrue(documented.contains { $0.hasPrefix("/sessions") })
    }
}
