import XCTest
@testable import DoyahCore

/// `FR-AI-22`（上下文供给与边界）的机械判据 —— 验收要点 ①②③④。
final class AgentContextTests: XCTestCase {

    private let secret = "sk-abcdefghijklmnopqrstuvwxyz012345"

    // MARK: - ① 六类各自成段，且**外发正文与预览是同一份**

    func testSixReferenceKindsEachProduceASectionAndPreviewEqualsWhatIsSent() {
        let payload = AgentContextAssembler.assemble([
            .file(path: "a.txt", text: "文件内容"),
            .directory(path: "dir", entries: ["x.swift", "y.swift"]),
            .selection(path: "b.swift", text: "let value = 1", firstLine: 42),
            .activeTab(title: "Home", kind: "note"),
            .terminalTail(text: "警告：三处"),
            .schemaSummary(database: "zxvmax", tables: [
                .init(schema: "public", name: "users", columns: ["id", "name"]),
            ]),
        ])

        XCTAssertEqual(payload.sections.count, 6, "六类各一段")
        XCTAssertEqual(payload.sections.map(\.title), ["file:a.txt", "dir:dir", "selection:b.swift:42",
                                                       "tab", "terminal", "schema:zxvmax"])
        XCTAssertTrue(payload.sections[2].body.contains("let value = 1"))
        XCTAssertTrue(payload.sections[5].body.contains("public.users (id, name)"))

        // **同一份**：预览就是外发正文本身
        XCTAssertEqual(payload.preview, payload.text)
        XCTAssertEqual(payload.promptFragment, payload.text, "循环的回灌段吃的也是同一份")
        // 正文里六段都在
        for fragment in ["文件内容", "x.swift", "let value = 1", "note:Home", "警告：三处", "public.users"] {
            XCTAssertTrue(payload.text.contains(fragment), "外发正文里要能看到「\(fragment)」")
        }
    }

    // MARK: - ② 边界过滤是纯函数：行数据与密钥都出去不了

    func testRowDataNeverLeavesEvenWhenPutIntoAnAllowedReference() {
        let terminalWithRows = """
        psql 输出开始
        | 1 | alice  | 1990-01-01 |
        | 2 | bob    | 1991-02-02 |
        1	alice	1990-01-01
        101, alice, 1990-01-01
        结束
        """
        let payload = AgentContextAssembler.assemble([.terminalTail(text: terminalWithRows)])

        XCTAssertFalse(payload.text.contains("alice"), "**结果集行数据一条都不许外发**")
        XCTAssertEqual(payload.totalRedactedRows, 4, "挡了几行要如实计数")
        XCTAssertTrue(payload.text.contains("[row]"), "占位符是机器形态")
        XCTAssertTrue(payload.text.contains("psql 输出开始"), "非行数据的正文照常过去")
    }

    func testSecretsAreRedactedAndCounted() {
        let payload = AgentContextAssembler.assemble([
            .selection(path: "config.swift", text: "let key = \"\(secret)\"\npassword=hunter2\n正常一行", firstLine: 1),
        ])
        XCTAssertFalse(payload.text.contains(secret), "密钥片段不许外发")
        XCTAssertFalse(payload.text.contains("hunter2"))
        XCTAssertGreaterThanOrEqual(payload.totalRedactedSecrets, 2, "挡了几处要如实计数")
        XCTAssertTrue(payload.text.contains("正常一行"))
    }

    /// 过滤是**纯函数**：同样的输入两次结果一致（可单测、可对拍）。
    func testFilterIsPureAndReportsCounts() {
        let input = "保留这行\n| 1 | x |\ntoken = abc123def456"
        let first = AgentContextBoundary.filter(input)
        let second = AgentContextBoundary.filter(input)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.redactedRows, 1)
        XCTAssertEqual(first.redactedSecrets, 1)
        XCTAssertFalse(first.text.contains("abc123def456"))
    }

    // MARK: - ③ schema 上限（≤60 表 / ≤400 列）：超出只发表名 / 如实标注

    func testSchemaSummaryRespectsTableAndColumnLimits() {
        let manyTables = (0..<70).map { AgentContextReference.Table(name: "t\($0)", columns: ["id"]) }
        let payload = AgentContextAssembler.assemble([.schemaSummary(database: "d", tables: manyTables)],
                                                    limits: AgentContextLimits(maxTables: 60, maxColumns: 400))
        let section = payload.sections[0]
        XCTAssertTrue(section.truncated, "超上限要标注截断")
        XCTAssertTrue(section.body.contains("t59"), "上限内的表要列出来")
        XCTAssertFalse(section.body.contains("t60\n"), "上限之外的表不再逐个列")
        XCTAssertTrue(section.body.contains("more:10"), "上限之外**只报数**（10 张）")

        // 列数超限 ⇒ 只列前 N 列
        let wide = AgentContextReference.Table(name: "wide", columns: (0..<500).map { "c\($0)" })
        let narrow = AgentContextAssembler.assemble([.schemaSummary(database: "d", tables: [wide])],
                                                    limits: AgentContextLimits(maxTables: 60, maxColumns: 10))
        XCTAssertTrue(narrow.sections[0].truncated)
        XCTAssertTrue(narrow.sections[0].body.contains("c9"))
        XCTAssertFalse(narrow.sections[0].body.contains("c10,"))
        // **回归**：schema 段是由声明拼出来的 ⇒ 行数据启发式不许把合法列名行吃掉（判据抓过一次）
        XCTAssertEqual(narrow.sections[0].redactedRows, 0, "schema 段不该被记成「挡掉了行数据」")
    }

    // MARK: - ④ 终端尾部与选中代码超限 ⇒ 截断并**如实标注**（不静默）

    func testTerminalTailKeepsTheEndAndMarksTruncation() {
        let long = (0..<500).map { "行\($0)" }.joined(separator: "\n")
        let payload = AgentContextAssembler.assemble([.terminalTail(text: long)],
                                                    limits: AgentContextLimits(maxTerminalCharacters: 100))
        let section = payload.sections[0]
        XCTAssertTrue(section.truncated, "超限要标注")
        XCTAssertEqual(payload.truncatedSections, ["terminal"])
        XCTAssertTrue(section.outgoing.contains("[truncated]"), "外发正文里要能看见截断标记")
        XCTAssertTrue(section.body.contains("行499"), "尾部保留的是**末尾**（终端最有用的就是末尾）")
        XCTAssertFalse(section.body.contains("行0\n"), "太早的内容被裁掉")
    }

    func testSelectionTruncationIsMarkedAndHeadIsKept() {
        let long = String(repeating: "let x = 1\n", count: 500)
        let payload = AgentContextAssembler.assemble([.selection(path: "a.swift", text: long, firstLine: 1)],
                                                    limits: AgentContextLimits(maxSelectionCharacters: 50))
        XCTAssertTrue(payload.sections[0].truncated)
        XCTAssertTrue(payload.sections[0].body.hasPrefix("let x = 1"), "选中代码保留开头")
    }

    // MARK: - 结构面：上下文里没有承载行数据的形态

    func testPayloadSchemaHasNoPlaceForRowData() {
        let payload = AgentContextAssembler.assemble([.terminalTail(text: "x")])
        XCTAssertEqual(Set(Mirror(reflecting: payload).children.compactMap { $0.label }), ["sections"])
        XCTAssertEqual(Set(Mirror(reflecting: payload.sections[0]).children.compactMap { $0.label }),
                       ["title", "body", "truncated", "redactedRows", "redactedSecrets"])
        for forbidden in ["rows", "data", "results", "values"] {
            XCTAssertFalse(Set(Mirror(reflecting: payload.sections[0]).children.compactMap { $0.label }).contains(forbidden))
        }
    }

    // MARK: - 接线段：系统提示不许是空串（`FR-AI-16` / `FR-AI-22`）

    /// 由头：`App/AppState.swift` 曾把 `systemPrompt` 写死成 `""` —— 模型看不到身份、工具面与数据边界。
    /// 判据钉四件：① 基础提示非空且含身份 / 模型 / 端点 / 工具名 / 数据边界 / 审批规矩；
    /// ② 完整提示含工作区路径与挂上来的上下文；③ 截断与挡掉的段**如实标注**（不静默）；
    /// ④ 源码面：`AppState` 里**不许再出现**空 `systemPrompt: ""`，且必须引用装配器。
    func testSystemPromptIsWiredAndNotEmpty() throws {
        let base = AgentSystemPrompt.base(model: "qwen-test", endpoint: "http://127.0.0.1:11434/v1")
        XCTAssertFalse(base.isEmpty, "系统提示是空串 ⇒ 模型看不到身份 / 工具 / 边界")
        for key in ["qwen-test", "http://127.0.0.1:11434/v1", "read_file", "run_command",
                    "数据边界", "先出差异", "不许假装"] {
            XCTAssertTrue(base.contains(key), "系统提示里缺「\(key)」")
        }
        let full = AgentSystemPrompt.build(model: "m", endpoint: "e", workspacePath: "/tmp/ws",
                                           references: [.terminalTail(text: "hello-tail")])
        XCTAssertTrue(full.contains("/tmp/ws"), "完整提示没带工作区路径")
        XCTAssertTrue(full.contains("hello-tail"), "挂上来的上下文没进提示")
        XCTAssertTrue(full.contains("本次上下文"), "上下文段没有标明来源（`FR-AI-22`）")

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        XCTAssertFalse(app.contains("systemPrompt: \"\""), "AppState 里仍有空 systemPrompt ⇒ 接线没做")
        XCTAssertTrue(app.contains("AgentSystemPrompt."), "AppState 没有引用系统提示装配（`AgentSystemPrompt`）")
    }
}
