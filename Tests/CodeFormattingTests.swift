import XCTest
@testable import DoyahCore

/// 代码格式化（FR-EDIT-39，形态 = ③ 混合）。
///
/// 这一族钉的是**选路与三种结局**，不是"某个工具能不能跑"（那要真装工具，属于证据脚本的事）。
/// 「装了没有」由注入的探测结果决定 —— 于是「外部优先 / 兜底 / 如实拒绝」三条路在同一台机器上
/// 全都测得到（否则永远只有一条被测到，而另外两条照样能编译）。
final class CodeFormattingTests: XCTestCase {

    private func plan(_ language: TextLanguage, installed: [String] = []) -> CodeFormatPlan {
        CodeFormatPlanner.plan(language: language) { installed.contains($0) }
    }

    private func decision(_ language: TextLanguage, installed: [String] = []) -> CodeFormatPlan {
        plan(language, installed: installed)
    }

    // MARK: 选路：外部优先

    func testExternalToolWinsWhenInstalled() {
        let plan = decision(.javascript, installed: ["prettier"])
        guard case .external(let tool) = plan else { return XCTFail("装了 Prettier 就该走外部：\(plan)") }
        XCTAssertEqual(tool.executable, "prettier")
        XCTAssertEqual(tool.displayName, "Prettier", "如实说明用到的名字不许空、也不许是文件名")
        XCTAssertTrue(tool.arguments.contains("--stdin-filepath"), "Prettier 按文件名判 parser")
    }

    func testFileNamePlaceholderIsResolvedToTheRealPath() {
        let tool = CodeFormatTool(
            executable: "prettier",
            arguments: ["--stdin-filepath", CodeFormatTool.fileNamePlaceholder],
            displayName: "Prettier"
        )
        XCTAssertEqual(
            tool.resolvedArguments(file: "/tmp/a/b.js"),
            ["--stdin-filepath", "/tmp/a/b.js"]
        )
        // 没有路径（新建未保存）时给一个**带正确扩展名**的名字：`untitled.txt` 会让它直接报错，
        // 而那不是用户的错。
        XCTAssertEqual(CodeFormatPlanner.fileName(path: nil, language: .javascript), "untitled.js")
        XCTAssertEqual(CodeFormatPlanner.fileName(path: "/tmp/x.py", language: .python), "/tmp/x.py")
    }

    func testFirstInstalledCandidateWins() {
        // 候选按登记顺序：两个都装了，取第一个。
        let definition = CodeLanguageDefinition(
            .javascript,
            displayName: "JavaScript",
            fileExtensions: ["js"],
            syntax: CodeSyntax(stringDelimiters: ["\""]),
            format: CodeFormatCapability(
                tools: [
                    CodeFormatTool(executable: "first", displayName: "First"),
                    CodeFormatTool(executable: "second", displayName: "Second")
                ]
            )
        )
        let plan = CodeFormatPlanner.plan(definition: definition) { _ in true }
        guard case .external(let tool) = plan else { return XCTFail("应取第一个候选：\(plan)") }
        XCTAssertEqual(tool.displayName, "First")
    }

    // MARK: 选路：内置兜底

    func testBuiltinTakesOverWhenNoExternalTool() {
        XCTAssertEqual(decision(.javascript), .builtin(.braceIndent))
        XCTAssertEqual(decision(.python), .builtin(.whitespace))
        XCTAssertEqual(decision(.sql), .builtin(.sql))
        XCTAssertEqual(decision(.html), .builtin(.whitespace))
    }

    func testLanguageWithoutBuiltinIsRefusedHonestly() {
        // Markdown 的空白本身就是语义 ⇒ 只给外部工具。没装 prettier 时**如实拒绝**，
        // 而不是拿内置兜底去改它、"看起来格式化过了"。
        XCTAssertEqual(decision(.markdown), .refused(.noFormatter(language: .markdown)))
        XCTAssertEqual(decision(.yaml), .refused(.noFormatter(language: .yaml)))
    }

    func testUnknownLanguageIsRefusedAsUnknown() {
        // 认不出（回落值）与「认得但没有工具」是**两种拒绝**，说给用户听的话不一样。
        XCTAssertEqual(decision(.plainText), .refused(.unknownLanguage))
    }

    func testBuiltinIsOnlyDeclaredForLanguagesWithLexicalRules() {
        // 登记纪律：兜底靠词法证明「那段空白不在字符串里」，没有词法就证不了。
        for definition in CodeLanguageRegistry.all where definition.format.builtin.isAvailable {
            XCTAssertTrue(
                definition.syntax.hasAnyRule,
                "\(definition.displayName) 登记了内置兜底，却没有词法规则（兜底没法证明空白不在字符串里）"
            )
        }
    }

    func testEveryRegisteredToolSaysItsName() {
        for definition in CodeLanguageRegistry.all {
            for tool in definition.format.tools {
                XCTAssertFalse(
                    tool.displayName.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(definition.displayName) 的工具 \(tool.executable) 没给 displayName：说了用外部工具就得说得清是哪一个"
                )
                XCTAssertFalse(tool.executable.contains("/"), "不许写死绝对路径（用户的安装位置不由我们决定）")
            }
        }
    }

    func testRegistryHandsOutOneAndTheSameDefinition() {
        // `formats` 表是单列的，两条取定义的路径必须合出同一份定义。
        for language in TextLanguage.allCases {
            let fromIndex = CodeLanguageRegistry.definition(id: language.rawValue)
            XCTAssertEqual(fromIndex?.format, language.definition.format, "\(language.rawValue) 两条路给的能力不一致")
        }
        XCTAssertEqual(CodeLanguageRegistry.all.count, TextLanguage.allCases.count)
    }

    // MARK: 内置兜底：空白规整（字符串里的空白一个字都不动）

    func testWhitespaceTrimsLineEndsAndKeepsExactlyOneFinalNewline() {
        let text = "let a = 1;   \nlet b = 2;\t\n\n\n"
        XCTAssertEqual(CodeBuiltinFormatter.tidy(text, language: .javascript), "let a = 1;\nlet b = 2;\n")
    }

    func testWhitespaceDoesNotTouchWhitespaceInsideStrings() {
        // 多行模板串里的行尾空格**是内容**：改了就是改语义，而界面看起来只是"格式化了一下"。
        let text = "const t = `a  \nb`;\n"
        XCTAssertEqual(CodeBuiltinFormatter.tidy(text, language: .javascript), text)
    }

    func testWhitespaceLeavesCarriageReturnsAlone() {
        // CRLF 是另一件事（改它 = 把整个文件重写一遍），本层不动。
        let text = "a = 1\r\nb = 2\r\n"
        XCTAssertEqual(CodeBuiltinFormatter.tidy(text, language: .javascript), text)
    }

    func testWhitespaceOnEmptyTextStaysEmpty() {
        XCTAssertEqual(CodeBuiltinFormatter.tidy("", language: .python), "")
        XCTAssertEqual(CodeBuiltinFormatter.tidy("   \n\n", language: .python), "")
    }

    // MARK: 内置兜底：行首缩进（花括号深度）

    func testBraceIndentFollowsDepth() {
        let text = "func f() {\nreturn 1\n}\n"
        XCTAssertEqual(
            CodeBuiltinFormatter.format(text, style: .braceIndent, language: .go),
            "func f() {\n    return 1\n}\n"
        )
    }

    func testBraceIndentDoesNotCountBracesInsideStringsOrComments() {
        let text = "func f() {\nlet s = \"}\"\n// }\nreturn 1\n}\n"
        XCTAssertEqual(
            CodeBuiltinFormatter.format(text, style: .braceIndent, language: .go),
            "func f() {\n    let s = \"}\"\n    // }\n    return 1\n}\n"
        )
    }

    func testBraceIndentLeavesLinesInsideMultilineStringsAlone() {
        // 落在字符串里的整行（多行串的续行）**整行不动** —— 行首空白也是内容。
        let text = "const t = `\n  keep   me\n`;\n"
        XCTAssertEqual(CodeBuiltinFormatter.format(text, style: .braceIndent, language: .javascript), text)
    }

    func testBraceIndentNormalisesTabsAtLineStart() {
        let text = "if (a) {\n\tb();\n}\n"
        XCTAssertEqual(
            CodeBuiltinFormatter.format(text, style: .braceIndent, language: .javascript),
            "if (a) {\n    b();\n}\n"
        )
    }

    // MARK: 结局：外部工具

    private final class FakeRunner: CodeFormatProcessRunning, @unchecked Sendable {
        struct Call: Equatable {
            var executable: String
            var arguments: [String]
            var input: String
        }

        /// 按调用顺序回答：第一条给格式化、第二条给版本探测；不够用时重复用最后一条。
        private var queue: [Result<CodeFormatProcessResult, Error>]
        private(set) var calls: [Call] = []

        init(_ results: Result<CodeFormatProcessResult, Error>...) {
            self.queue = results.isEmpty ? [.success(.init(exitCode: 0, standardOutput: "", standardError: ""))] : results
        }

        func runFilter(executable: String, arguments: [String], input: String) async throws -> CodeFormatProcessResult {
            calls.append(Call(executable: executable, arguments: arguments, input: input))
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            return try next.get()
        }
    }

    private func execute(
        language: TextLanguage,
        text: String,
        path: String? = "/tmp/sample.js",
        runner: FakeRunner,
        installed: [String] = ["prettier"]
    ) async -> CodeFormatExecution {
        await CodeFormatService.run(
            plan: decision(language, installed: installed),
            language: language,
            path: path,
            text: text,
            runner: runner
        )
    }

    func testExternalSuccessReportsTheToolNameVersionAndTheChange() async {
        let runner = FakeRunner(
            .success(.init(exitCode: 0, standardOutput: "let a=1;\n", standardError: "")),
            .success(.init(exitCode: 0, standardOutput: "3.3.3\n", standardError: ""))
        )
        let execution = await execute(language: .javascript, text: "let   a = 1 ;\n", runner: runner)
        guard case .ready(let outcome) = execution else { return XCTFail("应成功：\(execution)") }
        // 契约层口径（b）：说了用外部工具，就要说得清**哪一个、哪一版**。
        XCTAssertEqual(outcome.engine, .external(name: "Prettier", version: "3.3.3"))
        XCTAssertEqual(outcome.text, "let a=1;\n")
        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(runner.calls.count, 2, "一次格式化 + 一次版本探测")
        XCTAssertEqual(runner.calls[0].arguments, ["--stdin-filepath", "/tmp/sample.js"])
        XCTAssertEqual(runner.calls[0].input, "let   a = 1 ;\n", "源码经 stdin 喂给工具（不落盘）")
        XCTAssertEqual(runner.calls[1].arguments, ["--version"])
    }

    func testVersionProbeFailureStillReportsTheName() async {
        // 探测失败**不是**格式化失败：只说名字，不编版本号。
        let runner = FakeRunner(
            .success(.init(exitCode: 0, standardOutput: "let a=1;\n", standardError: "")),
            .success(.init(exitCode: 1, standardOutput: "", standardError: "unrecognised flag"))
        )
        let execution = await execute(language: .javascript, text: "let a = 1;\n", runner: runner)
        guard case .ready(let outcome) = execution else { return XCTFail("应成功：\(execution)") }
        XCTAssertEqual(outcome.engine, .external(name: "Prettier", version: nil))
    }

    func testToolThatDoesNotKnowTheVersionFlagIsNotProbed() async {
        // `gofmt` 登记了空 `versionArguments`（它不认 `--version`）⇒ 根本不起第二次进程。
        let runner = FakeRunner(.success(.init(exitCode: 0, standardOutput: "package main\n", standardError: "")))
        let execution = await execute(
            language: .go,
            text: "package main\n",
            path: "/tmp/main.go",
            runner: runner,
            installed: ["gofmt"]
        )
        guard case .ready(let outcome) = execution else { return XCTFail("应成功：\(execution)") }
        XCTAssertEqual(outcome.engine, .external(name: "gofmt", version: nil))
        XCTAssertEqual(runner.calls.count, 1, "不认 --version 的工具不该被探测第二次")
        XCTAssertEqual(runner.calls[0].arguments, [])
    }

    func testExternalNoChangeIsReportedAsUnchanged() async {
        // 「看起来变了但没变」的反面：结果与原文逐字相同就要说没变。
        let runner = FakeRunner(
            .success(.init(exitCode: 0, standardOutput: "let a = 1;\n", standardError: "")),
            .success(.init(exitCode: 0, standardOutput: "3.3.3\n", standardError: ""))
        )
        let execution = await execute(language: .javascript, text: "let a = 1;\n", runner: runner)
        guard case .ready(let outcome) = execution else { return XCTFail("应成功：\(execution)") }
        XCTAssertFalse(outcome.changed)
    }

    func testExternalNonZeroExitCarriesTheToolDiagnostic() async {
        let runner = FakeRunner(
            .success(.init(exitCode: 2, standardOutput: "", standardError: "\n[error] Unexpected token\n"))
        )
        let execution = await execute(language: .javascript, text: "let a = ;\n", runner: runner)
        guard case .failed(let failure) = execution else { return XCTFail("应失败：\(execution)") }
        XCTAssertEqual(failure.engine, .external(name: "Prettier", version: nil))
        XCTAssertEqual(failure.exitCode, 2)
        XCTAssertEqual(failure.message, "[error] Unexpected token", "取 stderr 的第一条非空行")
        XCTAssertEqual(runner.calls.count, 1, "失败了就不去问版本（那一态要的是失败原因）")
    }

    func testExternalLaunchFailureHasNoExitCode() async {
        let runner = FakeRunner(.failure(ExternalProcessError.launchFailed(executable: "prettier", reason: "not found")))
        let execution = await execute(language: .javascript, text: "let a = 1;\n", runner: runner)
        guard case .failed(let failure) = execution else { return XCTFail("应失败：\(execution)") }
        XCTAssertNil(failure.exitCode, "起不来就没有退出码，不许编一个 0 出来")
        XCTAssertFalse(failure.message.isEmpty)
    }

    // MARK: 结局：内置与拒绝

    func testBuiltinSQLGoesThroughTheExistingFormatter() async {
        let execution = await CodeFormatService.run(
            plan: .builtin(.sql),
            language: .sql,
            path: "/tmp/q.sql",
            text: "select a from t\n",
            runner: FakeRunner(.success(.init(exitCode: 0, standardOutput: "", standardError: "")))
        )
        guard case .ready(let outcome) = execution else { return XCTFail("应成功：\(execution)") }
        XCTAssertEqual(outcome.engine, .builtin(.sql))
        XCTAssertTrue(outcome.text.contains("SELECT"), "走既有保守格式化器：\(outcome.text)")
    }

    func testRefusedPlanNeverTouchesTheRunner() async {
        let runner = FakeRunner(.success(.init(exitCode: 0, standardOutput: "x", standardError: "")))
        for language in [TextLanguage.markdown, .yaml, .plainText] {
            let execution = await CodeFormatService.run(
                plan: decision(language),
                language: language,
                path: nil,
                text: "a  \n",
                runner: runner
            )
            guard case .refused = execution else { return XCTFail("\(language.rawValue) 应被拒绝：\(execution)") }
        }
        XCTAssertTrue(runner.calls.isEmpty, "拒绝那条路不许起进程")
    }

    // MARK: 选路：**无联网**那一档（人类主人 2026-10-02 定案：优先外部；无联网 ⇒ 回退内置 + 如实说明）

    func testNoNetworkFallsBackToBuiltinAndKeepsTheReason() {
        for language in [TextLanguage.javascript, .python, .go] {
            let decision = CodeFormatPlanner.decide(language: language) { _ in .unusable(.networkUnreachable) }
            XCTAssertEqual(
                decision.plan,
                .builtin(language.definition.format.builtin),
                "\(language.rawValue)：无联网 ⇒ 回退内置"
            )
            XCTAssertEqual(
                decision.fallbackReason,
                .networkUnreachable,
                "\(language.rawValue)：回退原因必须带出来 —— 界面说不清为什么回退就等于没如实说明"
            )
        }
    }

    func testUnusableCandidateIsNeverChosen() {
        // 不变式：探针说「不能用」的候选**永远不许**进 plan —— 无联网时挑一个跑不起来的工具，
        // 正是「静默失败」和「报了成功却没变」的来源。
        let decision = CodeFormatPlanner.decide(language: .javascript) { _ in .unusable(.networkUnreachable) }
        if case .external(let tool) = decision.plan {
            XCTFail("不能用的候选被选中了：\(tool.executable)")
        }
    }

    func testUnusableProbeStillPrefersAUsableCandidate() {
        // 「无联网」只否掉**那一个**工具，不是否掉整条外部路：还有能用的候选就仍然走外部。
        let decision = CodeFormatPlanner.decide(language: .javascript) { name in
            name == "prettier" ? .unusable(.networkUnreachable) : .usable
        }
        switch decision.plan {
        case .external(let tool):
            XCTAssertNotEqual(tool.executable, "prettier", "不能用的候选不许被选中")
            XCTAssertNil(decision.fallbackReason, "走了外部就没有回退原因")
        default:
            // javascript 只登记了 prettier 时走这条：那就必须回退内置且带原因。
            XCTAssertEqual(decision.fallbackReason, .networkUnreachable)
        }
    }

    func testTwoStateProbeStaysBackwardCompatible() {
        // 只有「装了没有」两态的调用点行为照旧；回退原因**恒为 nil**（说不出的原因不许编）。
        let installed = CodeFormatPlanner.decide(language: .javascript) { $0 == "prettier" }
        XCTAssertNil(installed.fallbackReason)
        guard case .external = installed.plan else { return XCTFail("装了就该走外部：\(installed.plan)") }

        let missing = CodeFormatPlanner.decide(language: .javascript) { _ in false }
        XCTAssertEqual(missing.plan, .builtin(TextLanguage.javascript.definition.format.builtin))
        XCTAssertNil(missing.fallbackReason)
    }
}

/// **只用内置**（需求提出者 2026-10-02 定案）这一族。
///
/// 上面那族钉的是「外部优先 / 兜底 / 拒绝」三态；这一族钉的是**这一版的产品路径根本不进外部那条分支**
/// —— 环境里装了 `prettier` 也不走它，而且宿主侧**拿不到**任何起子进程的手段（`runBuiltin` 不收 `runner`）。
final class CodeFormatBuiltinOnlyTests: XCTestCase {

    /// 红绿成对的对照：旧口径「装了工具」走外部；定案口径走同一个语言仍走内置。
    func testBuiltinOnlyNeverGoesExternalEvenWhenAToolIsInstalled() {
        let old = CodeFormatPlanner.plan(language: .javascript) { _ in true }
        guard case .external = old else { return XCTFail("旧口径装了工具就该走外部：\(old)") }

        XCTAssertEqual(
            CodeFormatPlanner.planBuiltinOnly(language: .javascript),
            .builtin(.braceIndent),
            "定案「只用内置」之后不许再回外部那条分支"
        )
    }

    /// 内置档位与旧口径的兜底那一档**逐条一致**（换口径不该换结果）。
    func testBuiltinOnlyKeepsTheSameBuiltinChoices() {
        XCTAssertEqual(CodeFormatPlanner.planBuiltinOnly(language: .javascript), .builtin(.braceIndent))
        XCTAssertEqual(CodeFormatPlanner.planBuiltinOnly(language: .python), .builtin(.whitespace))
        XCTAssertEqual(CodeFormatPlanner.planBuiltinOnly(language: .sql), .builtin(.sql))
        XCTAssertEqual(CodeFormatPlanner.planBuiltinOnly(language: .html), .builtin(.whitespace))
    }

    /// 两种拒绝仍然分得开（认不出 / 认得但没有内置）。
    func testBuiltinOnlyStillRefusesHonestly() {
        XCTAssertEqual(CodeFormatPlanner.planBuiltinOnly(language: .plainText), .refused(.unknownLanguage))
        XCTAssertEqual(
            CodeFormatPlanner.planBuiltinOnly(language: .markdown),
            .refused(.noFormatter(language: .markdown))
        )
    }

    /// 执行入口：内置那一档真跑出结果、如实报「变没变」，且**幂等**（再跑一次不该再变）。
    func testRunBuiltinFormatsAndIsIdempotent() {
        let messy = "func f() {\nreturn 1\n}\n"
        guard case .ready(let changed) = CodeFormatService.runBuiltin(language: .javascript, text: messy) else {
            return XCTFail("内置这条路必须给得出结果")
        }
        XCTAssertEqual(changed.engine, .builtin(.braceIndent))
        XCTAssertEqual(changed.text, "func f() {\n    return 1\n}\n")
        XCTAssertTrue(changed.changed)

        guard case .ready(let again) = CodeFormatService.runBuiltin(language: .javascript, text: changed.text) else {
            return XCTFail("已规整的文本也要给出结果")
        }
        XCTAssertFalse(again.changed, "没变就说没变（不然每点一次格式化都在改文件）")
        XCTAssertEqual(again.text, changed.text)
    }

    /// 拒绝那两档**原样穿过**执行入口。
    func testRunBuiltinPassesRefusalsThrough() {
        XCTAssertEqual(
            CodeFormatService.runBuiltin(language: .markdown, text: "# t\n"),
            .refused(.noFormatter(language: .markdown))
        )
    }

    /// 源锚点：宿主那一侧**回不到外部那条路**（判据在，旧写法就活不下来）。
    func testAppSideReachesNoExternalRoute() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("App/WorkspaceTabsModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            app.contains("CodeFormatService.runBuiltin("),
            "格式化入口没有走「只用内置」那条路（定案作废了「外部优先/回退内置」）"
        )
        for forbidden in [
            "CodeFormatToolLocator", "FoundationCodeFormatProcessRunner", "CodeFormatPlanner.decide",
        ] {
            XCTAssertFalse(app.contains(forbidden), "定案「只用内置」之后宿主不该再出现 \(forbidden)")
        }
    }

    /// 源锚点（内测清单 `#2` 复测打回：「**编辑下无格式化菜单**」）：
    /// 功能一直在，但只长在工作区页签条那枚「格式化」下拉里 —— 用户按名字去**菜单栏的「编辑」**找，
    /// 找不到就等于没有。判据钉三件事：① 主菜单「编辑」里真的有这一项；② ⇧⌘F **只注册一处**
    /// （同一快捷键挂两个菜单项时 AppKit 只认一个，另一项变成摆设）；③ 这一项能跟着界面语言变。
    func testFormatMenuItemLivesInMainEditMenu() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let commands = try String(
            contentsOf: root.appendingPathComponent("App/DoyahStudioCommands.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(commands.contains("CommandGroup(after: .pasteboard)"),
                      "主菜单「编辑」那一组里没有条目 —— 他找的就是那儿")
        XCTAssertTrue(commands.contains("L(.menuFormat)"), "「编辑」里那一项没有用无占位符的菜单键")
        XCTAssertTrue(commands.contains("workspaceTabs.formatSelected()"),
                      "「编辑」里的格式化没有打到工作区页签上")

        var registrations: [(String, Int)] = []
        let appRoot = root.appendingPathComponent("App")
        let appFiles = try FileManager.default.subpathsOfDirectory(atPath: appRoot.path)
            .filter { $0.hasSuffix(".swift") }
        for file in appFiles {
            let text = try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8)
            let count = text.components(separatedBy: "keyboardShortcut(AppShortcut.formatCode").count - 1
            if count > 0 { registrations.append((file, count)) }
        }
        let total = registrations.reduce(0) { $0 + $1.1 }
        XCTAssertEqual(total, 1, "⇧⌘F 注册了 \(total) 处：\(registrations) —— 只许一处，多了就是摆设")

        let menuKeys = try String(contentsOf: root.appendingPathComponent("Core/MenuLocalization.swift"), encoding: .utf8)
        XCTAssertTrue(menuKeys.contains(".menuFormat,"), ".menuFormat 没进菜单键表 ⇒ 切语言后这一项停在旧语言")
        XCTAssertEqual(LocalizedStrings.text(.menuFormat, language: .simplifiedChinese), "格式化代码")
        XCTAssertEqual(LocalizedStrings.text(.menuFormat, language: .english), "Format Code")
    }

    /// 内测 `#2` 第二轮复测打回（原话：「**格式化菜单有了，但并不具备格式化能力**，我把一个 json 文件
    /// 打乱了，点击格式没反应」）—— 先钉**能力那一层**：JSON 必须有内置格式化能力，且乱掉的输入必须真的变。
    /// 这一条在 Core 里判得到；「菜单点下去能不能把它叫起来」是 App 侧那条判据（见探针）。
    func testJSONHasBuiltinCapabilityAndScrambledInputChanges() throws {
        guard case .builtin(let style) = CodeFormatPlanner.planBuiltinOnly(language: .json) else {
            return XCTFail("JSON 没有内置格式化能力 ⇒ 菜单点下去只可能「没反应」")
        }
        XCTAssertEqual(style, .json, "JSON 的内置档必须是**断行重排**那一种（`braceIndent` 只逐行调缩进）")

        // 判据要钉**结果长什么样**，不能只判「变了」：旧口径下 `braceIndent` 会返回
        // 「除行尾那一个换行外一模一样」的文本 —— 只判 `!=` 的话它会**绿**，而用户看到的是「没反应」。
        let scrambled = "{\"a\":1,\"b\":{\"c\":[1,2,3]},\"d\":\"x\"}"
        let expected = """
        {
            "a": 1,
            "b": {
                "c": [
                    1,
                    2,
                    3
                ]
            },
            "d": "x"
        }
        """ + "\n"
        XCTAssertEqual(CodeBuiltinFormatter.format(scrambled, style: style, language: .json), expected)
    }

    /// 字符串里的结构符不许当结构符；空容器保持紧凑；重复格式化不再变（幂等）；空输入原样返回。
    func testPrettyJSONProtectsStringsAndIsIdempotent() {
        XCTAssertEqual(
            CodeBuiltinFormatter.prettyJSON("{\"k\":\"a{b}:,c\\\"d\"}"),
            "{\n    \"k\": \"a{b}:,c\\\"d\"\n}\n"
        )
        XCTAssertEqual(CodeBuiltinFormatter.prettyJSON("{\"a\":{},\"b\":[]}"),
                       "{\n    \"a\": {},\n    \"b\": []\n}\n")
        XCTAssertEqual(CodeBuiltinFormatter.prettyJSON(""), "")
        let once = CodeBuiltinFormatter.prettyJSON("{\"a\":[1,{\"b\":2}]}")
        XCTAssertEqual(CodeBuiltinFormatter.prettyJSON(once), once, "第二次格式化不该再动它")
    }
}
