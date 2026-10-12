import XCTest
@testable import DoyahCore

final class ResultExporterTests: XCTestCase {

    private func makeResult(
        columns: [String] = ["id", "name"],
        rows: [[String?]] = [["1", "Alice"], ["2", nil]]
    ) -> QueryResult {
        QueryResult(
            columns: columns.enumerated().map {
                ColumnMeta(id: $0.offset, name: $0.element, typeName: "TEXT")
            },
            rows: rows
        )
    }

    func testCSVHasBOMHeaderAndCRLFLines() {
        let text = ResultExporter.csv(for: makeResult())

        XCTAssertTrue(text.hasPrefix("\u{FEFF}"))
        XCTAssertEqual(
            text.dropFirst(),
            "id,name\r\n1,Alice\r\n2,\r\n"
        )
    }

    func testCSVCanOmitBOM() {
        let text = ResultExporter.csv(for: makeResult(rows: [["1", "a"]]), includeByteOrderMark: false)
        XCTAssertEqual(text, "id,name\r\n1,a\r\n")
    }

    func testCSVEscapesCommasQuotesAndNewlines() {
        XCTAssertEqual(ResultExporter.escapeCSVField("plain"), "plain")
        XCTAssertEqual(ResultExporter.escapeCSVField("a,b"), "\"a,b\"")
        XCTAssertEqual(ResultExporter.escapeCSVField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(ResultExporter.escapeCSVField("line1\nline2"), "\"line1\nline2\"")

        let text = ResultExporter.csv(
            for: makeResult(columns: ["c"], rows: [["a,b"]])
        )
        XCTAssertTrue(text.hasSuffix("\"a,b\"\r\n"))
    }

    func testCSVOfResultWithoutColumnsIsEmpty() {
        let empty = QueryResult()
        XCTAssertEqual(ResultExporter.csv(for: empty), "\u{FEFF}")
        XCTAssertFalse(ResultExporter.hasExportableContent(empty))
    }

    func testJSONContainsColumnsAndRows() {
        let json = ResultExporter.json(for: makeResult())

        XCTAssertTrue(json.contains("\"column\": 2") == false)
        XCTAssertTrue(json.contains("\"rowCount\": 2"))
        XCTAssertTrue(json.contains("{ \"name\": \"id\", \"type\": \"TEXT\" }"))
        XCTAssertTrue(json.contains("{ \"id\": \"1\", \"name\": \"Alice\" }"))
        XCTAssertTrue(json.contains("{ \"id\": \"2\", \"name\": null }"))
    }

    func testJSONDisambiguatesDuplicateColumnNames() {
        let result = makeResult(columns: ["value", "value"], rows: [["a", "b"]])
        let json = ResultExporter.json(for: result)

        XCTAssertTrue(json.contains("\"value\": \"a\""))
        XCTAssertTrue(json.contains("\"value_2\": \"b\""))
    }

    func testJSONEscapesSpecialCharacters() {
        XCTAssertEqual(ResultExporter.quote("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(ResultExporter.quote("tab\there"), "\"tab\\there\"")
        XCTAssertEqual(ResultExporter.quote("换行\n结束"), "\"换行\\n结束\"")
        XCTAssertEqual(ResultExporter.quote("中文"), "\"中文\"")
    }

    func testJSONReportsAffectedRows() {
        let result = QueryResult(affectedRows: 7)
        let json = ResultExporter.json(for: result)

        XCTAssertTrue(json.contains("\"affectedRows\": 7"))
        XCTAssertTrue(ResultExporter.hasExportableContent(result))
    }

    func testTextDispatchesByFormat() {
        let result = makeResult(rows: [["1", "a"]])
        XCTAssertTrue(ResultExporter.text(for: result, format: .csv).contains("\u{FEFF}"))
        XCTAssertTrue(ResultExporter.text(for: result, format: .json).hasPrefix("{"))
    }

    // MARK: - FR-RES-11：TSV / Markdown / INSERT

    func testTSVSeparatesFieldsWithTabs() {
        let text = ResultExporter.tsv(for: makeResult())

        XCTAssertEqual(text, "id\tname\n1\tAlice\n2\t\n")
        XCTAssertFalse(text.hasPrefix("\u{FEFF}"), "TSV 不带 BOM")
    }

    func testTSVReplacesEmbeddedTabsAndNewlines() {
        let text = ResultExporter.tsv(for: makeResult(columns: ["c"], rows: [["a\tb\nc"]]))
        XCTAssertEqual(text, "c\na b c\n")
    }

    func testMarkdownTableShape() {
        let text = ResultExporter.markdown(for: makeResult())

        XCTAssertEqual(
            text,
            "| id | name |\n| --- | --- |\n| 1 | Alice |\n| 2 | NULL |\n"
        )
    }

    func testMarkdownEscapesPipesAndNewlines() {
        let text = ResultExporter.markdown(for: makeResult(columns: ["c"], rows: [["a|b\nc"]]))
        XCTAssertTrue(text.contains("| a\\|b<br>c |"))
    }

    func testMarkdownOfResultWithoutColumnsIsEmpty() {
        XCTAssertEqual(ResultExporter.markdown(for: QueryResult()), "")
    }

    private func typedResult() -> QueryResult {
        let columns = [
            ColumnMeta(id: 0, name: "id", typeName: "integer"),
            ColumnMeta(id: 1, name: "name", typeName: "text"),
            ColumnMeta(id: 2, name: "ratio", typeName: "numeric"),
            ColumnMeta(id: 3, name: "active", typeName: "boolean")
        ]
        let rows: [[String?]] = [
            ["1", "O'Brien", "3.50", "t"],
            ["2", nil, nil, "f"]
        ]
        return QueryResult(columns: columns, rows: rows)
    }

    func testInsertStatementsQuoteTextAndKeepNumbersRaw() {
        let text = ResultExporter.insertStatements(for: typedResult(), tableName: "users")

        XCTAssertEqual(
            text,
            """
            INSERT INTO "users" ("id", "name", "ratio", "active") VALUES (1, 'O''Brien', 3.50, TRUE);
            INSERT INTO "users" ("id", "name", "ratio", "active") VALUES (2, NULL, NULL, FALSE);

            """
        )
    }

    func testInsertStatementsUseDialectIdentifierQuoting() {
        let text = ResultExporter.insertStatements(
            for: typedResult(),
            tableName: "users",
            dialect: GBaseDialect()
        )
        XCTAssertTrue(text.hasPrefix("INSERT INTO `users` (`id`, `name`, `ratio`, `active`) VALUES"))
    }

    func testInsertStatementsFallBackToQuotedTextForUnparseableNumbers() {
        let columns = [ColumnMeta(id: 0, name: "n", typeName: "integer")]
        let result = QueryResult(columns: columns, rows: [["abc"]])
        let text = ResultExporter.insertStatements(for: result, tableName: "t")

        XCTAssertTrue(text.contains("('abc')"), "解析不出数字时应退回字符串写法，而不是产生非法 SQL")
    }

    func testInsertStatementsEmptyWithoutRows() {
        let result = QueryResult(columns: [ColumnMeta(id: 0, name: "n", typeName: "text")], rows: [])
        XCTAssertEqual(ResultExporter.insertStatements(for: result, tableName: "t"), "")
    }

    func testTextDispatchesExtendedFormats() {
        let result = makeResult(rows: [["1", "a"]])

        XCTAssertTrue(ResultExporter.text(for: result, format: .tsv).hasPrefix("id\tname"))
        XCTAssertTrue(ResultExporter.text(for: result, format: .markdown).hasPrefix("| id |"))
        XCTAssertTrue(
            ResultExporter.text(for: result, format: .sqlInsert, tableName: "t")
                .hasPrefix("INSERT INTO \"t\"")
        )
    }

    func testExportFormatMetadata() {
        XCTAssertEqual(ResultExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ResultExportFormat.tsv.fileExtension, "tsv")
        XCTAssertEqual(ResultExportFormat.sqlInsert.fileExtension, "sql")
        XCTAssertEqual(ResultExportFormat.xlsx.fileExtension, "xlsx")
        XCTAssertTrue(ResultExportFormat.sqlInsert.requiresTableName)
        XCTAssertFalse(ResultExportFormat.csv.requiresTableName)
        XCTAssertFalse(ResultExportFormat.xlsx.requiresTableName)

        // 不写死"一共几个"（加了格式就要改一次的断言没什么信息量），
        // 改成钉住**真正要守的性质**：扩展名互不重复、二进制格式只有 xlsx。
        XCTAssertEqual(Set(ResultExportFormat.allCases.map(\.fileExtension)).count, ResultExportFormat.allCases.count)
        XCTAssertEqual(ResultExportFormat.allCases.filter(\.isBinary), [.xlsx])
    }

    // MARK: - `--format` 名字解析（队列 L-124 片 2）

    /// 正例：CLI 里写过的名字与别名一个都不许因为改造而丢。
    func testFormatNameParsingKeepsEveryDocumentedNameAndAlias() {
        let accepted: [(String, ResultExportFormat)] = [
            ("csv", .csv),
            ("CSV", .csv),
            (" json ", .json),
            ("tsv", .tsv),
            ("markdown", .markdown),
            ("md", .markdown),
            ("insert", .sqlInsert),
            ("sql", .sqlInsert),
            ("xlsx", .xlsx),
            ("excel", .xlsx)
        ]
        for (raw, expected) in accepted {
            XCTAssertEqual(
                try? ResultExportFormat.parse(commandLineName: raw).get(),
                expected,
                "「\(raw)」应当解析成 \(expected)"
            )
        }
    }

    /// 负例 ①：旧的二进制容器（WPS `.et` / Excel 2003 `.xls`）必须落到**自己那一档**，
    /// 不许混进「认不出」—— 两者给用户的下一句话完全不同（有替代路径 vs 没有）。
    func testFormatNameParsingSeparatesLegacyBinaryContainersFromUnknownNames() {
        for raw in ["et", "ET", ".et", ".ET", "ett", ".ett", "xls", ".xls"] {
            let parsed = ResultExportFormat.parse(commandLineName: raw)
            guard case .failure(.legacyBinarySheetContainer(let carried)) = parsed else {
                XCTFail("「\(raw)」应当落到 legacyBinarySheetContainer，实际 \(parsed)")
                continue
            }
            XCTAssertEqual(carried, raw, "原样带回用户写的那个名字，提示才能点名")
        }
    }

    /// 负例 ②：拼错的名字 = 认不出，**不许**被上面那一档吞掉（否则会给出「另存为」这种
    /// 对他毫无意义的替代路径）。顺带钉住空串与只差一个字母的近邻。
    func testFormatNameParsingRejectsUnknownNames() {
        for raw in ["jsonn", "cvs", "etx", ".xlsx2", "", "  ", "ett2"] {
            let parsed = ResultExportFormat.parse(commandLineName: raw)
            guard case .failure(.unknown(let carried)) = parsed else {
                XCTFail("「\(raw)」应当落到 unknown，实际 \(parsed)")
                continue
            }
            XCTAssertEqual(carried, raw)
        }
    }

    /// 反向：这一档**不许**把 `.xlsx` 也当成「写不出来」—— 它正是我们唯一能直出的表格格式，
    /// 也是上面那句提示让用户去用的替代路径（判反了，提示就把人指向死路）。
    func testLegacyContainerBranchDoesNotSwallowXLSX() {
        XCTAssertEqual(try? ResultExportFormat.parse(commandLineName: "xlsx").get(), .xlsx)
        XCTAssertEqual(try? ResultExportFormat.parse(commandLineName: ".xlsx").get(), nil,
                       "带点的 .xlsx 目前不认（`--format` 收的是格式名不是路径）；这条钉住现状，改动要有人拍板")
    }
}
