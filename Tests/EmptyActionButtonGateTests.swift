import XCTest

/// `Scripts/check-empty-action-buttons.py` 的 Swift 版（2026-11-10 判据搬家第三批 · UI 交互 9 条之一）。
///
/// **为什么这条搬进测试、别的 UI 判据摘掉**：它的拦截史是**四次真红并导致一次显式归类**
/// （`fb539b30` master 上 rc=1：N2-9 新加的 `requestNoteRemoval` 空守卫没登记 /
/// `d55a2617` 点名 AI 会话区「未配置」守卫 / `da2d4bfb` 7 条未登记守卫逐条读体登记 /
/// `6abecaf5` `exportNotes` + `purgeTrashBeyondLimits` 两条进台账）——
/// 而它的判定物是**纯数据**：`App/AppState.swift` 里的空守卫 ↔ 台账
/// `Scripts/empty-action-button-dispositions.json` 的双向对账，天生属于测试。
///
/// 它守的是什么（队列 L-50）：产品里「内容为空」时按钮有三种并存的处置 ——
/// **灰着**（`view-disabled`）· **可点 + 给一句理由**（`explain`）· **够不着按钮**（`internal`，
/// 人判登记）；第四种是缺陷 —— **可点却静默无反应**（2026-09-26 读图在笔记编辑器「保存」上抓到）。
///
/// 判据（与老脚本逐条同口径，判定物相同）：
/// A 双向对账：源码里每条「内容为空」守卫（条件含 `isEmpty` 或引用登记的判据属性）必须恰好
///   登记一条；台账里有而源码里没有的 ⇒ 陈旧判红。
/// B `explain` 档的守卫体里必须**真的有一句人话**（本地化取值 / 可读化入口 / 抛出 / 消息属性赋值）。
/// C `view-disabled` 档：判据属性全局只定义一次 / 守卫必须用它 / 视图必须把它接进 `.disabled(...)`
///   / 视图不许拿属性名再自己 `isEmpty` 一遍（L-50 的病根就是两处各写一遍）。
/// D `view-disabled-local` 档：字面锚点必须还在视图里。
/// E 空跑防护：台账非空、扫到的守卫非空、视图文件非空、条数下限。
final class EmptyActionButtonGateTests: XCTestCase {

    // MARK: - 口径（与老脚本同一份常量）

    enum Gate {
        static let stateFile = "App/AppState.swift"
        static let viewDirs = ["App/Views", "Plugins/Notes/Views"]
        static let ledgerPath = "Scripts/empty-action-button-dispositions.json"
        static let forms: Set<String> = ["view-disabled", "view-disabled-local", "explain", "internal"]
        /// 空跑防护：2026-11-10 实测 50 条守卫 / 50 条台账 / 视图 121 份。
        static let floorEntries = 40
        static let floorSightings = 40
        static let floorViews = 100
    }

    struct Sighting: Equatable {
        let function: String
        let line: Int
        let condition: String
        let body: String
    }

    struct Entry {
        let function: String
        let guardText: String
        let form: String
        let reason: String
        let view: String
        let anchor: String
        let predicate: String
    }

    // MARK: - 词法（与老脚本逐字同口径）

    private static let funcRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:@\w+\s+)*(?:private\s+|static\s+|public\s+|internal\s+)*func\s+(\w+)"#)
    private static let guardRegex = try! NSRegularExpression(
        pattern: #"^\s*guard\b(.*?)\belse\b(.*)$"#)
    private static let messageAssignRegex = try! NSRegularExpression(
        pattern: #"(=\s*L\(|=\s*ErrorPresenter|=\s*CLIFailureText|=\s*LocalizationManager"#
            + #"|\bthrow\b"#
            + #"|\b(?:statusMessage|errorMessage|failureReason)\s*="#
            + #"|(?:title|text)\s*:\s*L\("#
            + #"|\b\w*(?:Message|Error|Notice)\s*=\s*\S)"#)

    static func normalize(_ text: String) -> String {
        var collapsed = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        collapsed = collapsed.trimmingCharacters(in: .whitespaces)
        while collapsed.hasSuffix("{") {
            collapsed.removeLast()
            collapsed = collapsed.trimmingCharacters(in: .whitespaces)
        }
        return collapsed
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        guard !word.isEmpty else { return false }
        return text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b",
                          options: .regularExpression) != nil
    }

    /// 扫 `App/AppState.swift`：只认**单行到 `else`** 的守卫（与老脚本同为有意的窄口径）。
    static func scanGuards(_ text: String, predicates: Set<String>) -> [Sighting] {
        let lines = text.components(separatedBy: "\n")
        var sightings: [Sighting] = []
        for (index, line) in lines.enumerated() {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("guard") else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = guardRegex.firstMatch(in: line, range: range) else { continue }
            let rawCondition = substring(line, match.range(at: 1))
            let condition = normalize(rawCondition)
            if condition.isEmpty { continue }
            let interesting = condition.contains("isEmpty")
                || predicates.contains { containsWord($0, in: condition) }
            guard interesting else { continue }
            sightings.append(Sighting(function: functionOwner(lines, at: index), line: index + 1,
                                      condition: condition, body: guardBlock(lines, at: index)))
        }
        return sightings
    }

    static func functionOwner(_ lines: [String], at index: Int) -> String {
        var owner = ""
        for i in 0...min(index, lines.count - 1) {
            let line = lines[i]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = funcRegex.firstMatch(in: line, range: range) {
                owner = substring(line, match.range(at: 1))
            }
        }
        return owner
    }

    static func guardBlock(_ lines: [String], at index: Int, maxLines: Int = 10) -> String {
        var chunk: [String] = []
        var depth = 0
        var started = false
        for i in index..<min(index + maxLines, lines.count) {
            let line = lines[i]
            chunk.append(line.trimmingCharacters(in: .whitespaces))
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if line.contains("{") { started = true }
            if started && depth <= 0 { break }
        }
        return chunk.joined(separator: "\n")
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    // MARK: - 装配（真仓库）

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓根
    }

    func text(_ relative: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func viewFiles() throws -> [String] {
        var found: [String] = []
        for dir in Gate.viewDirs {
            let base = Self.repoRoot.appendingPathComponent(dir)
            guard let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                found.append(url.path.replacingOccurrences(of: Self.repoRoot.path + "/", with: ""))
            }
        }
        return found.sorted()
    }

    struct Ledger {
        let entries: [Entry]
        let problems: [String]
    }

    func ledger() throws -> Ledger {
        let url = Self.repoRoot.appendingPathComponent(Gate.ledgerPath)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return Ledger(entries: [], problems: ["台账 `\(Gate.ledgerPath)` 不存在或不是合法 JSON"])
        }
        let raw = dictionary["entries"] as? [[String: Any]] ?? []
        let entries = raw.map { item in
            Entry(function: item["func"] as? String ?? "",
                  guardText: Self.normalize(item["guard"] as? String ?? ""),
                  form: item["form"] as? String ?? "",
                  reason: item["reason"] as? String ?? "",
                  view: item["view"] as? String ?? "",
                  anchor: item["anchor"] as? String ?? "",
                  predicate: item["predicate"] as? String ?? "")
        }
        var problems: [String] = []
        if entries.isEmpty {
            problems.append("台账里一条处置都没有 —— 空台账不是「都合规」")
        }
        return Ledger(entries: entries, problems: problems)
    }

    // MARK: - A 双向对账

    func testEveryGuardIsRegisteredExactlyOnce() throws {
        let ledger = try ledger()
        XCTAssertTrue(ledger.problems.isEmpty, ledger.problems.joined(separator: " · "))
        let predicates = Set(ledger.entries.map(\.predicate).filter { !$0.isEmpty })
        let sightings = Self.scanGuards(try text(Gate.stateFile), predicates: predicates)

        // 空跑防护：解析口径先坏掉时不许静默通过
        XCTAssertGreaterThanOrEqual(sightings.count, Gate.floorSightings,
                                    "扫到的空守卫只有 \(sightings.count) 条（下限 \(Gate.floorSightings)）—— 判据在空跑")

        let scanned = Set(sightings.map { "\($0.function)\u{1}\($0.condition)" })
        let registered = Set(ledger.entries.map { "\($0.function)\u{1}\($0.guardText)" })
        var problems: [String] = []
        for sighting in sightings where !registered.contains("\(sighting.function)\u{1}\(sighting.condition)") {
            problems.append("未登记的空守卫：`\(Gate.stateFile):\(sighting.line)` `\(sighting.function)` 的 "
                + "`guard \(sighting.condition)` —— 是灰着、给理由，还是够不着按钮？逐条登记进台账")
        }
        for entry in ledger.entries where !scanned.contains("\(entry.function)\u{1}\(entry.guardText)") {
            problems.append("台账里有陈旧条目：`\(entry.function)` 的 `guard \(entry.guardText)` 在 "
                + "`\(Gate.stateFile)` 里已经找不到（改形状或销账都要动台账，别让它烂在原地）")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))

        // 读数（不是断言口径，是给报告用的实测值）
        XCTAssertEqual(sightings.count, 50, "守卫条数与搬家时的实测值不等 —— 要么产品变了（更新本行），要么口径坏了")
        XCTAssertEqual(ledger.entries.count, 50, "台账条数与搬家时不等")
    }

    // MARK: - B / C / D 逐条处置

    func testEveryEntryDispositionHolds() throws {
        let ledger = try ledger()
        let predicates = Set(ledger.entries.map(\.predicate).filter { !$0.isEmpty })
        let sightings = Self.scanGuards(try text(Gate.stateFile), predicates: predicates)
        let views = try viewFiles()
        XCTAssertGreaterThanOrEqual(views.count, Gate.floorViews,
                                    "视图文件只有 \(views.count) 份（下限 \(Gate.floorViews)）⇒ 扫描面可能写坏了")

        var problems: [String] = []
        for entry in ledger.entries {
            if !Gate.forms.contains(entry.form) {
                problems.append("`\(entry.function)` 的 form `\(entry.form)` 不在词表 \(Gate.forms.sorted())")
                continue
            }
            if entry.reason.isEmpty {
                problems.append("`\(entry.function)`（\(entry.form)）必须写理由 —— 处置没理由就只是一句声明")
            }
            let sighting = sightings.first { $0.function == entry.function && $0.condition == entry.guardText }
            switch entry.form {
            case "explain":
                if let sighting, Self.messageAssignRegex.firstMatch(
                    in: sighting.body, range: NSRange(sighting.body.startIndex..<sighting.body.endIndex,
                                                      in: sighting.body)) == nil {
                    problems.append("`\(entry.function)` 登记为「可点 + 给一句理由」，但那句守卫体里没有给用户的话"
                        + "（`\(Gate.stateFile):\(sighting.line)`）—— 要么补话，要么改登记")
                }
            case "internal":
                break
            case "view-disabled-local":
                if entry.view.isEmpty {
                    problems.append("`\(entry.function)`（view-disabled-local）没写 `view`")
                    break
                }
                guard let viewText = try? text(entry.view) else {
                    problems.append("`\(entry.function)` 点名的视图不存在：`\(entry.view)`")
                    break
                }
                if entry.anchor.isEmpty {
                    problems.append("`\(entry.function)`（view-disabled-local）没写 `anchor`")
                } else if !viewText.contains(entry.anchor) {
                    problems.append("`\(entry.function)` 的字面锚点 `\(entry.anchor)` 已不在 `\(entry.view)` 里"
                        + "—— 视图侧的处置被删了（这就是这一档要判住的东西）")
                }
            default:  // view-disabled
                problems.append(contentsOf: try viewDisabledProblems(entry, sighting: sighting, views: views))
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    /// C 档：判据属性唯一出处 + 守卫与 `.disabled` 同一条判断 + 视图不许再推导一遍。
    func viewDisabledProblems(_ entry: Entry, sighting: Sighting?, views: [String]) throws -> [String] {
        var problems: [String] = []
        guard !entry.predicate.isEmpty else {
            return ["`\(entry.function)`（view-disabled）没写 `predicate`"]
        }
        guard !entry.view.isEmpty else {
            return ["`\(entry.function)`（view-disabled）没写 `view`"]
        }
        let definitions = try Self.predicateDefinitions(entry.predicate, views: views)
        if definitions.count != 1 {
            let whereText = definitions.isEmpty ? "一处都没有" : definitions.joined(separator: "、")
            problems.append("判据属性 `\(entry.predicate)` 必须**只定义一次**，实测 \(definitions.count) 处"
                + "（\(whereText)）—— 唯一出处是这一档的全部意义")
        }
        if let sighting, !Self.containsWord(entry.predicate, in: sighting.condition) {
            problems.append("`\(entry.function)` 的守卫没有走判据属性 `\(entry.predicate)`（"
                + "`\(Gate.stateFile):\(sighting.line)` `guard \(sighting.condition)`）"
                + "—— 守卫与 `.disabled` 必须同一条判断")
        }
        guard let viewText = try? text(entry.view) else {
            problems.append("`\(entry.function)` 点名的视图不存在：`\(entry.view)`")
            return problems
        }
        if !viewText.contains(entry.predicate) {
            problems.append("`\(entry.view)` 里没有引用判据属性 `\(entry.predicate)`（视图侧处置丢了）")
        } else if !Self.containsWord(entry.predicate, in: viewText, withinDisabled: true) {
            problems.append("`\(entry.view)` 引用了 `\(entry.predicate)`，但没有把它接进 `.disabled(...)`")
        }
        for property in try Self.predicateProperties(entry.predicate) {
            let pattern = NSRegularExpression.escapedPattern(for: property) + #"[^\n]{0,80}?\.isEmpty"#
            if viewText.range(of: pattern, options: .regularExpression) != nil {
                problems.append("`\(entry.view)` 在**重新推导**判据（`\(property)` 后面又跟了 `.isEmpty`）"
                    + "—— 判据 `\(entry.predicate)` 是唯一出处，L-50 的病根就是两处各写一遍")
            }
        }
        return problems
    }

    static func containsWord(_ word: String, in text: String, withinDisabled: Bool) -> Bool {
        let pattern = #"disabled\([^)]*\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func predicateDefinitions(_ predicate: String, views: [String]) throws -> [String] {
        let pattern = try NSRegularExpression(
            pattern: #"^\s*(?:private\s+|internal\s+|public\s+)?(?:var|let|func)\s+"#
                + NSRegularExpression.escapedPattern(for: predicate) + #"\b"#)
        var hits: [String] = []
        for relative in [Gate.stateFile] + views {
            let url = repoRoot.appendingPathComponent(relative)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in content.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if pattern.firstMatch(in: line, range: range) != nil {
                    hits.append("`\(relative):\(index + 1)`")
                }
            }
        }
        return hits
    }

    /// 判据体里引用到的存储属性名（用来挡「视图再写一遍」）。
    static func predicateProperties(_ predicate: String) throws -> [String] {
        let url = repoRoot.appendingPathComponent(Gate.stateFile)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n")
        let declaration = try NSRegularExpression(
            pattern: #"^\s*(?:private\s+)?var\s+"# + NSRegularExpression.escapedPattern(for: predicate) + #"\b"#)
        guard let start = lines.firstIndex(where: {
            declaration.firstMatch(in: $0, range: NSRange($0.startIndex..<$0.endIndex, in: $0)) != nil
        }) else { return [] }
        var body: [String] = []
        var depth = 0
        var started = false
        for line in lines[start..<min(start + 12, lines.count)] {
            body.append(line)
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if line.contains("{") { started = true }
            if started && depth <= 0 { break }
        }
        let text = body.joined(separator: "\n")
        let names = try NSRegularExpression(pattern: #"\b(note\w+|notes\w+)\b"#).matches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
        return Set(names).filter { $0 != predicate }.sorted()
    }

    // MARK: - 口径自检（解析器不许在坏输入上静默通过）

    func testGuardScannerUsesSingleLineElseOnly() {
        let source = """
        func alpha() {
            guard !rows.isEmpty else { return }
            guard !rows
                .isEmpty else { return }
        }
        """
        let sightings = Self.scanGuards(source, predicates: [])
        XCTAssertEqual(sightings.count, 1, "多行条件的守卫不在窄口径内（老脚本同一口径）")
        XCTAssertEqual(sightings.first?.function, "alpha")
        XCTAssertEqual(sightings.first?.condition, "!rows.isEmpty")
        XCTAssertEqual(sightings.first?.line, 2)
    }

    func testRegisteredPredicateJoinsTheScanner() {
        let source = "func beta() {\n    guard hasDeletableSelection else { return }\n}"
        XCTAssertTrue(Self.scanGuards(source, predicates: []).isEmpty)
        XCTAssertEqual(Self.scanGuards(source, predicates: ["hasDeletableSelection"]).count, 1)
    }

    func testExplainBodyMustSaySomething() {
        let silent = "guard !rows.isEmpty else { return }"
        let talking = "guard !rows.isEmpty else { egressError = L(.egressExportEmpty); return }"
        func saysSomething(_ body: String) -> Bool {
            Self.messageAssignRegex.firstMatch(
                in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)) != nil
        }
        XCTAssertFalse(saysSomething(silent), "静默早退必须被判红 —— 这正是 L-50 那一族缺陷")
        XCTAssertTrue(saysSomething(talking))
    }

    func testNormalizeCollapsesWhitespaceAndTrailingBrace() {
        XCTAssertEqual(Self.normalize("  !rows\n   .isEmpty { "), "!rows .isEmpty")
        XCTAssertEqual(Self.normalize("!a"), "!a")
    }

    func testViewRedefinesThePredicateIsCaught() {
        let viewText = "Button(…) { }.disabled(appState.hasDeletableSelection)\n// 下面是重新推导\nlet x = noteRows.isEmpty"
        XCTAssertTrue(viewText.range(of: #"noteRows[^\n]{0,80}?\.isEmpty"#, options: .regularExpression) != nil)
        XCTAssertTrue(Self.containsWord("hasDeletableSelection", in: viewText, withinDisabled: true))
        XCTAssertFalse(Self.containsWord("hasDeletableSelection", in: "Button { }", withinDisabled: true))
    }
}
