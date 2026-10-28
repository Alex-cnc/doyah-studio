import XCTest
@testable import DoyahCore

/// `FR-STD-WS-NAV-005` 片段模板（snippets）的行为判据。
///
/// 需求四条 → 这里的四组用例：
/// ① 按语言给片段（`SnippetCatalog.templates(for:)` 从语言表取）；
/// ② 触发后插入骨架、**可跳占位符**（解析 + 会话两处）；
/// ③ 片段表可扩展（`SnippetCatalog.merged` + 引擎只吃传进来的表）；
/// ④ 片段表与语言表同源（`CodeLanguageRegistry.definition(of:).snippets`，源树那一半在
///    `Tests/SnippetTemplateSourceTests.swift`）。
final class SnippetTemplateTests: XCTestCase {

    // MARK: 骨架解析

    /// `$1` / `${1:默认}` 都要认：默认文本进正文、位置与长度对得上。
    func testParserKeepsDefaultsAndStops() {
        let body = SnippetParser.parse("SELECT ${1:*}\nFROM ${2:table};")
        XCTAssertEqual(body.text, "SELECT *\nFROM table;")
        XCTAssertEqual(body.stops.map(\.index), [1, 2])
        let ns = body.text as NSString
        XCTAssertEqual(ns.substring(with: body.stops[0].range), "*")
        XCTAssertEqual(ns.substring(with: body.stops[1].range), "table")
        XCTAssertNil(body.finish)
    }

    /// `${1}`（无默认）与 `$1`（裸写）同一个落点、长度 0（插入点，不选中任何东西）。
    func testParserBareStopsHaveZeroLength() {
        let body = SnippetParser.parse("a ${1} b $2 c")
        XCTAssertEqual(body.text, "a  b  c")
        XCTAssertEqual(body.stops.count, 2)
        XCTAssertEqual(body.stops[0].length, 0)
        XCTAssertEqual(body.stops[1].length, 0)
        XCTAssertEqual(body.stops[0].offset, 2)
        XCTAssertEqual(body.stops[1].offset, 5)
    }

    /// `$0` 只定收尾位置、不占落点；`${0:…}` 的默认文本不插（收尾位置没有要填的东西）。
    func testParserRecordsFinishWithoutStop() {
        let body = SnippetParser.parse("${1:x}$0tail")
        XCTAssertEqual(body.text, "xtail")
        XCTAssertEqual(body.stops.map(\.index), [1])
        XCTAssertEqual(body.finish, 1)
    }

    /// `$$` / `\$` 是字面 `$`：金额、shell 变量这类正文里的 `$` 不许被当占位符吃掉。
    func testParserEscapesDollar() {
        XCTAssertEqual(SnippetParser.parse("cost $$5").text, "cost $5")
        XCTAssertTrue(SnippetParser.parse("cost $$5").stops.isEmpty)
        XCTAssertEqual(SnippetParser.parse("\\$1").text, "$1")
        XCTAssertTrue(SnippetParser.parse("\\$1").stops.isEmpty)
    }

    /// 认不出的 `${…` **原样落字符**，不吞后面那个字符（悄悄吃字符是最难查的一类）。
    func testParserKeepsUnknownBracesLiterally() {
        let body = SnippetParser.parse("${x} and $ y")
        XCTAssertEqual(body.text, "${x} and $ y")
        XCTAssertTrue(body.stops.isEmpty)
    }

    /// 落点按**序号**排、同序号按位置排 —— 不管它们在骨架里出现的先后。
    func testParserOrdersStopsByIndex() {
        let body = SnippetParser.parse("${2:b}${1:a}")
        XCTAssertEqual(body.stops.map(\.index), [1, 2])
        let ns = body.text as NSString
        XCTAssertEqual(ns.substring(with: body.stops[0].range), "a")
        XCTAssertEqual(ns.substring(with: body.stops[1].range), "b")
    }

    /// 确定性：同一份骨架解析两遍逐字段相同（不依赖字典序 / 时间 / 随机）。
    func testParserIsDeterministic() {
        let source = "SELECT ${1:*}\nFROM ${2:table}\nWHERE ${3:x = 1};"
        XCTAssertEqual(SnippetParser.parse(source), SnippetParser.parse(source))
    }

    // MARK: 语言表里的片段（①②④）

    /// SQL 有 `select` / `join` 骨架，且骨架**自洽**（第一行是 SELECT、带 FROM）。
    func testSQLTableProvidesSelectAndJoin() {
        let templates = SnippetCatalog.templates(for: .sql)
        XCTAssertGreaterThanOrEqual(templates.count, 4)
        XCTAssertTrue(templates.contains { $0.trigger == "select" })
        XCTAssertTrue(templates.contains { $0.trigger == "join" })
        for template in templates {
            let body = SnippetParser.parse(template.body)
            XCTAssertFalse(body.text.isEmpty, "\(template.trigger) 的骨架是空的")
            XCTAssertTrue(body.text.hasPrefix("SELECT") || body.text.hasPrefix("INSERT")
                            || body.text.hasPrefix("CREATE"),
                          "\(template.trigger) 的骨架不是一条能自己站住的语句：\(body.text)")
        }
    }

    /// Markdown 有表格骨架（需求 ① 点名的另一个例子）。
    func testMarkdownTableSnippetExists() {
        let templates = SnippetCatalog.templates(for: .markdown)
        guard let table = templates.first(where: { $0.trigger == "table" }) else {
            return XCTFail("Markdown 没有 table 片段")
        }
        let body = SnippetParser.parse(table.body)
        XCTAssertTrue(body.text.contains("| --- |"), "表格骨架缺少分隔行：\(body.text)")
        XCTAssertGreaterThanOrEqual(body.stops.count, 3)
    }

    /// 纯文本没有片段 —— 如实不给（不是「给了个空的」）。
    func testPlainTextHasNoSnippets() {
        XCTAssertTrue(SnippetCatalog.templates(for: .plainText).isEmpty)
        XCTAssertNil(SnippetEngine.expansion(
            in: "select", caret: 6, templates: [], language: .plainText
        ))
    }

    /// 同源：`definition(of:)` 与 `all` 里那一条给的是**同一份**片段表（合成只一处）。
    func testRegistryExposesSameSnippetTable() {
        let sql = CodeLanguageRegistry.definition(of: .sql)
        let fromAll = CodeLanguageRegistry.all.first { $0.language == .sql }
        XCTAssertEqual(sql.snippets, fromAll?.snippets)
        XCTAssertFalse(sql.snippets.isEmpty)
    }

    // MARK: 触发判定

    /// 触发词要**整词**命中：`selects` / `myselect` 都不算。
    func testTriggerRequiresWholeWord() {
        let templates = SnippetCatalog.templates(for: .sql)
        XCTAssertNil(SnippetEngine.expansion(in: "selects", caret: 7, templates: templates, language: .sql))
        XCTAssertNil(SnippetEngine.expansion(in: "myselect", caret: 8, templates: templates, language: .sql))
        XCTAssertNotNil(SnippetEngine.expansion(in: "select", caret: 6, templates: templates, language: .sql))
    }

    /// 大小写不敏感（表里登记小写，写 SQL 的人习惯打大写）。
    func testTriggerIsCaseInsensitive() {
        let templates = SnippetCatalog.templates(for: .sql)
        let plan = SnippetEngine.expansion(in: "SELECT", caret: 6, templates: templates, language: .sql)
        XCTAssertEqual(plan?.trigger, "select")
    }

    /// 光标在词中间（后面还接词字符）⇒ 不展开（否则会把半个词换成整段骨架）。
    func testTriggerRejectsCaretInsideWord() {
        let templates = SnippetCatalog.templates(for: .sql)
        XCTAssertNil(SnippetEngine.expansion(in: "selectx", caret: 6, templates: templates, language: .sql))
    }

    /// 字符串里的那个词不触发（掩码取自词法器，与着色同一份切分）。
    func testTriggerSkipsInsideString() {
        let templates = SnippetCatalog.templates(for: .sql)
        // `'select'`：光标停在右引号前 —— 词的范围落在字符串里。
        XCTAssertNil(SnippetEngine.expansion(in: "'select'", caret: 7, templates: templates, language: .sql))
        // 关掉闸门时它本来是能展开的：对照组证明这条判据不是恒绿。
        XCTAssertNotNil(SnippetEngine.expansion(in: "select", caret: 6, templates: templates, language: .sql))
    }

    /// 注释行尾那个词同样不触发。
    func testTriggerSkipsInsideComment() {
        let templates = SnippetCatalog.templates(for: .sql)
        XCTAssertNil(SnippetEngine.expansion(in: "-- select", caret: 9, templates: templates, language: .sql))
    }

    /// 只替换触发词那一段，别的字一个不动。
    func testExpansionReplacesOnlyTheTrigger() {
        let templates = SnippetCatalog.templates(for: .sql)
        guard let plan = SnippetEngine.expansion(in: "x select", caret: 8, templates: templates, language: .sql)
        else { return XCTFail("没认出触发词") }
        XCTAssertEqual(plan.replaceRange, NSRange(location: 2, length: 6))
        XCTAssertTrue(plan.insertion.hasPrefix("SELECT "))
    }

    // MARK: 会话（跳占位符）

    /// 建立会话后就停在第一个落点上；Tab 依次往后；跳完最后一格 ⇒ 收尾并结束。
    func testSessionWalksStopsThenFinishes() {
        let templates = [SnippetTemplate(trigger: "t", body: "a${1:one}b${2:two}c$0d")]
        guard let plan = SnippetEngine.expansion(in: "t", caret: 1, templates: templates, language: .swift)
        else { return XCTFail("没展开") }
        var session = SnippetSession.starting(after: plan, at: 0)
        XCTAssertEqual(session.activeRange?.location, 1)
        XCTAssertEqual(session.activeRange?.length, 3)   // one

        guard let second = session.advance() else { return XCTFail("没跳到第二个落点") }
        XCTAssertEqual(second.location, 5)               // "aonebtwocd" 里 two 的起点
        XCTAssertEqual(second.length, 3)

        guard let finish = session.advance() else { return XCTFail("没跳收尾位置") }
        XCTAssertEqual(finish.length, 0)
        XCTAssertTrue(session.isFinished)
        XCTAssertNil(session.advance(), "跳完之后再 Tab 必须交还缩进")
    }

    /// 在第一格多打两个字：后面的落点跟着平移（否则 Tab 会跳到一段无关的文字里）。
    func testSessionShiftsWhenEditingCurrentStop() {
        let templates = [SnippetTemplate(trigger: "t", body: "${1:one}-${2:two}")]
        guard let plan = SnippetEngine.expansion(in: "t", caret: 1, templates: templates, language: .swift)
        else { return XCTFail("没展开") }
        var session = SnippetSession.starting(after: plan, at: 0)
        // 把第一格的 `one`（0..<3）替换成 `longer`（6 字符）
        XCTAssertTrue(session.noteEdit(range: NSRange(location: 0, length: 3), replacementLength: 6))
        XCTAssertEqual(session.activeRange?.length, 6)
        guard let second = session.advance() else { return XCTFail("没跳到第二个落点") }
        XCTAssertEqual(second, NSRange(location: 7, length: 3))
    }

    /// 在**当前落点之后、最后一个落点之前**的正文里改字 ⇒ 会话作废（不猜位置）。
    ///
    /// 现场：骨架 `one-two`，光标还在第一格（`one`），人却去删那个连接符 ——
    /// 这一下既不在当前落点里，也不在最后落点之后，落点该往哪儿挪是猜出来的，
    /// 而猜错的表现是「按 Tab 跳进一段无关文字」。所以作废（Tab 回到缩进）。
    func testSessionInvalidatesOnEditBetweenStops() {
        let templates = [SnippetTemplate(trigger: "t", body: "${1:one}-${2:two}")]
        guard let plan = SnippetEngine.expansion(in: "t", caret: 1, templates: templates, language: .swift)
        else { return XCTFail("没展开") }
        var session = SnippetSession.starting(after: plan, at: 0)
        XCTAssertFalse(
            session.noteEdit(range: NSRange(location: 3, length: 1), replacementLength: 0),
            "在两个落点之间改字必须作废会话"
        )
    }

    /// 在最后一个落点**之后**改字 ⇒ 落点不动、会话照旧。
    func testSessionKeepsStopsWhenEditingAfterLastStop() {
        let templates = [SnippetTemplate(trigger: "t", body: "${1:one};")]
        guard let plan = SnippetEngine.expansion(in: "t", caret: 1, templates: templates, language: .swift)
        else { return XCTFail("没展开") }
        var session = SnippetSession.starting(after: plan, at: 0)
        XCTAssertTrue(session.noteEdit(range: NSRange(location: 4, length: 0), replacementLength: 2))
        XCTAssertEqual(session.activeRange, NSRange(location: 0, length: 3))
    }

    // MARK: 可扩展（③）

    /// 自定义表与内置表合并：同触发词**自定义胜出**，其余按各自顺序。
    func testCatalogMergeLetsCustomWinByTrigger() {
        let base = [
            SnippetTemplate(trigger: "select", body: "SELECT ${1:*} FROM ${2:t};"),
            SnippetTemplate(trigger: "join", body: "JOIN ${1:t};")
        ]
        let custom = [SnippetTemplate(trigger: "SELECT", body: "SELECT ${1:id} FROM ${2:t};")]
        let merged = SnippetCatalog.merged(base: base, custom: custom)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.body, "SELECT ${1:id} FROM ${2:t};")
        XCTAssertEqual(merged.last?.trigger, "join")
    }

    /// 引擎只吃传进来的表：一份完全自造的表不需要改核心代码就能用（需求 ③）。
    func testEngineWorksWithCustomTableOnly() {
        let custom = [SnippetTemplate(trigger: "hello", body: "你好，${1:world}！")]
        guard let plan = SnippetEngine.expansion(in: "hello", caret: 5, templates: custom, language: .plainText)
        else { return XCTFail("自造表没生效") }
        XCTAssertEqual(plan.insertion, "你好，world！")
        XCTAssertEqual(plan.body.stops.first?.length, 5)
    }
}
