import XCTest

/// `check-language-registry.py` 的 Swift 版：**语言登记形状**（`FR-STD-WS-NAV-002` ①②③④ 的机械半边）。
///
/// 口径是「**新增语言不改核心代码**」：语言的扩展名映射与关键字 / 注释 / 字符串 / 运算符规则全部
/// **声明式登记**在 `Core/CodeLanguageDefinitions.swift`。判据管的是**形状**（知识点住哪儿、
/// 扩展名有没有两个主人、颜色是不是从令牌取、默认视图有几个消费者），覆盖面（「常见语言前 10」）
/// 仍由 `Tests/CodeLanguageRegistryTests.swift` 逐条量。
///
/// · **A 形状禁令**：语言的**消费方**文件里不许出现「按语言身份分支」的写法（`language == .html`
///   / `case .sql:`）；判定物先剥注释，命中处先解析**主体类型**（解析到 `TextLanguage` 才是身份分支，
///   解析到同名风格枚举只有**登记过**才放过，解析不出来按身份分支处理 —— fail-closed）；
///   A 档的面（`CONSUMER_FILES`）与**盘上发现面**（引用语言类型的生产级 `.swift`）必须同集合；
/// · **B 登记自洽**：每条登记项给全 `displayName` / `fileExtensions` / `syntax`，`isCode` 者必须有
///   注释规则与字符串界定符；语言标识与登记项**同集合**；一个扩展名 / 文件名只能有一个主人；
///   回落值（`isFallback: true`）恰好一条；
/// · **C 主题令牌**：高亮色走 `SyntaxTone`（两个编辑器文件里不许出现裸色值，且必须有取色锚点）；
/// · **E 默认视图的消费者唯一**：声明 `.browser` 的语言恰好是 HTML；`App/` 下读 `defaultView` 的
///   文件恰好是 `App/WorkspaceTabsModel.swift`（双向），且它必须真的把这一档交给浏览器那一侧；
/// · **D 空跑防护**：登记项 / 标识行 / 扩展名 / 消费方文件 / 取色锚点 / `App/` 文件数几条下限。
final class LanguageRegistryShapeTests: XCTestCase {

    enum Gate {
        static let definitionsFile = "Core/CodeLanguageDefinitions.swift"
        static let ledgerFile = "Scripts/language-registry-exemptions.json"
        static let faceDirs = ["App", "CLI", "Core", "Platform"]
        static let faceToken = #"\b(?:TextLanguage|CodeLanguageDefinition)\b"#
        static let editorFiles = ["App/Views/CodeEditorView.swift", "App/Views/SQLEditorView.swift"]
        static let tokenFile = "Core/DesignTokens.swift"
        static let tokenAnchor = "Theme.nsColor(SyntaxTone."
        static let bareColor = #"NSColor\(\s*(?:calibrated|displayP3|device|sRGB)?\s*[Rr]ed\s*:|0x[0-9A-Fa-f]{6,8}\b"#
        static let viewConsumerFiles = ["App/WorkspaceTabsModel.swift"]
        static let viewConsumerToken = "defaultView"
        static let viewHandoffAnchor = "openInBrowserTab"
        static let viewSourceDir = "App"
        static let browserViewLanguage = "html"

        static let floorDefinitions = 17
        static let floorIdentifiers = 17
        static let floorConsumers = 12
        static let floorExtensions = 30
        static let floorAnchors = 6
        static let floorAppFiles = 90

        /// 语言消费方那一族（A 档的声明面）——「谁按语言身份分支过，就是谁把知识从登记表里搬走了」。
        static let consumerFiles = [
            "Core/EditAssist.swift",
            "App/Views/CodeEditorView.swift",
            "App/Views/GhostTextOverlay.swift",
            "App/Views/MarkdownPreviewView.swift",
            "App/WorkspaceTabsModel.swift",
            "CLI/main.swift",
            "Core/CodeCompletion.swift",
            "Core/CodeFormatting.swift",
            "Core/CodeLexer.swift",
            "Core/CodeFenceLanguage.swift",
            "Core/CodeFolding.swift",
            "Core/CodeSyntax.swift",
            "Core/InlineGhostCompletion.swift",
            "Core/InlineGhostPathCompletion.swift",
            "Core/MarkdownEditing.swift",
            "Core/TextLanguage.swift",
            "Core/WorkspaceSession.swift",
            "Core/WorkspaceTab.swift",
            "Core/SymbolOutline.swift",
            "App/Views/SymbolHover.swift",
            "App/Views/SQLEditorView.swift",
            "Core/SnippetTemplate.swift",
        ]

        static let identifierLine = #"static\s+let\s+(\w+)\s*=\s*TextLanguage\(registered:\s*"([^"]+)"\)"#
        static let definitionHead = #"CodeLanguageDefinition\(\s*\.(\w+)\s*,"#

        static func stripComments(_ text: String) -> String {
            SwiftSource(text).uncommentedText
        }

        // MARK: - 台账

        struct Ledger {
            var exempt: [[String: String]] = []
            var homonymEnums: [[String: String]] = []
            var problems: [String] = []
        }

        static func loadLedger(_ payload: [String: Any]?) -> Ledger {
            var ledger = Ledger()
            guard let payload else {
                ledger.problems.append("\(ledgerFile) 不在盘上 —— 判据 A 的例外与同名枚举登记全走它")
                return ledger
            }
            for item in (payload["exempt"] as? [[String: Any]]) ?? [] {
                ledger.exempt.append([
                    "file": LRepo.string(item["file"]),
                    "snippet": LRepo.string(item["snippet"]),
                    "reason": LRepo.string(item["reason"]),
                ])
            }
            for item in (payload["homonymEnums"] as? [[String: Any]]) ?? [] {
                ledger.homonymEnums.append([
                    "type": LRepo.string(item["type"]),
                    "reason": LRepo.string(item["reason"]),
                ])
            }
            for (index, entry) in ledger.exempt.enumerated() {
                for field in ["file", "snippet", "reason"] where (entry[field] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    ledger.problems.append("例外台账第 \(index + 1) 条缺 `\(field)`（理由不许空）")
                }
            }
            for (index, entry) in ledger.homonymEnums.enumerated() {
                if (entry["type"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    ledger.problems.append("同名枚举台账第 \(index + 1) 条缺 `type`")
                } else if (entry["reason"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    ledger.problems.append("同名枚举台账第 \(index + 1) 条（`\(entry["type"]!)`）缺 `reason`")
                }
            }
            return ledger
        }

        // MARK: - A：身份分支

        static let declaredType = #"\b([a-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_]*)\b"#

        /// 同文件里「标识符 → 类型」的文本级表（同名多类型 ⇒ nil：解析不出就按身份分支判红）。
        static func typeTable(_ text: String) -> [String: String?] {
            var seen: [String: Set<String>] = [:]
            guard let regex = LScan.regex(declaredType) else { return [:] }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(at: 1))
                seen[name, default: []].insert(ns.substring(with: match.range(at: 2)))
            }
            return seen.mapValues { $0.count == 1 ? $0.first : nil }
        }

        static func switchSubject(_ lines: [String], at index: Int) -> String? {
            var depth = 0
            var cursor = index - 1
            while cursor >= 0 {
                let line = lines[cursor]
                if let regex = LScan.regex(#"^\s*switch\s+(.+?)\s*\{\s*$"#),
                   depth <= 0,
                   let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                    let subject = (line as NSString).substring(with: match.range(at: 1))
                    let names = subject.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init)
                    return names.last
                }
                depth += line.filter { $0 == "}" }.count - line.filter { $0 == "{" }.count
                if depth < 0 { return nil }
                cursor -= 1
            }
            return nil
        }

        enum BranchShape {
            case eq(String)
            case caseSubject
        }

        static func identityShape(_ line: String, identifier: String) -> BranchShape? {
            let escaped = NSRegularExpression.escapedPattern(for: identifier)
            if let regex = LScan.regex(#"([A-Za-z_][A-Za-z0-9_]*)\s*(?:==|!=)\s*\."# + escaped + #"\b"#),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                return .eq((line as NSString).substring(with: match.range(at: 1)))
            }
            if let regex = LScan.regex(#"\."# + escaped + #"\b\s*(?:==|!=)\s*([A-Za-z_][A-Za-z0-9_]*)"#),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                return .eq((line as NSString).substring(with: match.range(at: 1)))
            }
            if let regex = LScan.regex(#"case\s+\."# + escaped + #"\s*:"#),
               regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                return .caseSubject
            }
            return nil
        }

        /// 盘上发现面：`FACE_DIRS` 下引用语言类型的生产级 `.swift`。
        static func discoverConsumers(_ files: [String: String]) -> [String] {
            files.keys.filter { relative in
                guard faceDirs.contains(where: { relative.hasPrefix($0 + "/") }) else { return false }
                if relative.hasSuffix("Tests.swift") || relative.contains("/Tests/") || relative == definitionsFile {
                    return false
                }
                let text = stripComments(files[relative] ?? "")
                return LScan.regex(faceToken)?.firstMatch(
                    in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
            }.sorted()
        }

        static func reconcileFace(_ files: [String: String], declared: [String]) -> [String] {
            var problems: [String] = []
            let discovered = Set(discoverConsumers(files))
            let declaredSet = Set(declared)
            for relative in discovered.subtracting(declaredSet).sorted() {
                problems.append("\(relative) 引用语言类型却不在 A 档声明面里 —— 语言消费者多了一份")
            }
            for relative in declaredSet.subtracting(discovered).sorted() {
                problems.append("\(relative) 在 A 档声明面里，但盘上不再引用语言类型 —— **死条目**")
            }
            return problems
        }

        struct BranchReading {
            var problems: [String] = []
            var judged = 0
            var exempt = 0
            var homonym = 0
            var scanned = 0
            var exemptHits: Set<Int> = []
            var homonymSeen: Set<String> = []
        }

        static func checkIdentityBranches(_ files: [String: String], identifiers: [String],
                                          ledger: Ledger, declared: [String]) -> BranchReading {
            var reading = BranchReading()
            reading.problems = reconcileFace(files, declared: declared)
            let homonymTypes = Set(ledger.homonymEnums.map { $0["type"] ?? "" }.filter { !$0.isEmpty })
            for relative in declared {
                guard let text = files[relative] else {
                    reading.problems.append("缺文件：\(relative)（A 档声明面里的文件不在盘上）")
                    continue
                }
                reading.scanned += 1
                let stripped = stripComments(text)
                let lines = stripped.components(separatedBy: "\n")
                let table = typeTable(stripped)
                for (index, line) in lines.enumerated() {
                    for identifier in identifiers {
                        guard let shape = identityShape(line, identifier: identifier) else { continue }
                        let resolved: String?
                        let where_: String
                        switch shape {
                        case .caseSubject:
                            let subject = switchSubject(lines, at: index)
                            resolved = subject.flatMap { table[$0] ?? nil }
                            where_ = subject.map { "`switch \($0)`" } ?? "所属 `switch` 的主体"
                        case .eq(let operand):
                            resolved = table[operand] ?? nil
                            where_ = "`\(operand)`"
                        }
                        if resolved != "TextLanguage", let resolved, homonymTypes.contains(resolved) {
                            reading.homonym += 1
                            reading.homonymSeen.insert(resolved)
                            continue
                        }
                        if resolved == "TextLanguage" {
                            if let index = ledger.exempt.firstIndex(where: {
                                $0["file"] == relative && !($0["snippet"] ?? "").isEmpty && line.contains($0["snippet"] ?? "")
                            }) {
                                reading.exempt += 1
                                reading.exemptHits.insert(index)
                                continue
                            }
                        }
                        reading.judged += 1
                        reading.problems.append("\(relative):\(index + 1) 按语言身份分支（`\(identifier)`）—— \(where_) 解析到 "
                                                + "\(resolved ?? "未知类型")；语言知识只允许住在 \(definitionsFile)，"
                                                + "消费方要拿规则请走 `CodeLanguageDefinition`")
                    }
                }
            }
            // 死登记棘轮
            for (index, entry) in ledger.exempt.enumerated() where !reading.exemptHits.contains(index) {
                reading.problems.append("例外台账第 \(index + 1) 条（`\(entry["file"] ?? "")` / `\(entry["snippet"] ?? "")`）"
                                        + " 在盘上没有命中 —— **死豁免**")
            }
            for entry in ledger.homonymEnums where !reading.homonymSeen.contains(entry["type"] ?? "") {
                reading.problems.append("同名枚举台账登记的 `\(entry["type"] ?? "")` 一次都没被解析到 —— **死登记**")
            }
            return reading
        }

        // MARK: - B：登记自洽

        struct DefinitionReading {
            var problems: [String] = []
            var definitions: [String] = []
            var identifiers: [String] = []
            var extensions = 0
            var browserViews: [String] = []
        }

        static func checkDefinitions(_ text: String) -> DefinitionReading {
            var reading = DefinitionReading()
            let marker = "private static let definitions: [CodeLanguageDefinition] = ["
            var region = text
            if let start = text.range(of: marker) {
                let after = text[start.upperBound...]
                if let end = after.range(of: "\n    ]") {
                    region = String(after[..<end.lowerBound])
                } else {
                    reading.problems.append("\(definitionsFile) 里找不到登记表数组的收口 —— 结构变了：本判据靠这段文本定位登记项")
                }
            } else {
                reading.problems.append("\(definitionsFile) 里找不到登记表数组（`\(marker)` … `    ]`）—— 结构变了")
            }
            // 整行注释的登记项不算登记。
            region = region.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let fallbacks = region.components(separatedBy: "isFallback: true").count - 1
            if fallbacks != 1 {
                reading.problems.append("回落值（`isFallback: true`）必须**恰好一条**，实际 \(fallbacks) 条")
            }
            if let regex = LScan.regex(identifierLine) {
                let ns = text as NSString
                var names: Set<String> = []
                for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    names.insert(ns.substring(with: match.range(at: 2)))
                }
                reading.identifiers = names.sorted()
            }
            guard let heads = LScan.regex(definitionHead) else { return reading }
            let ns = region as NSString
            let matches = heads.matches(in: region, range: NSRange(location: 0, length: ns.length))
            var registered: [String] = []
            var extensions: [String: String] = [:]
            var entries: [String: String] = [:]
            for (index, head) in matches.enumerated() {
                let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let chunk = ns.substring(with: NSRange(location: head.range.location, length: max(end - head.range.location, 0)))
                let language = ns.substring(with: head.range(at: 1))
                registered.append(language)
                if chunk.contains("defaultView: .browser") { reading.browserViews.append(language) }
                for field in ["displayName:", "fileExtensions:", "syntax:"] where !chunk.contains(field) {
                    reading.problems.append("\(definitionsFile) 的 `.\(language)` 登记项缺 `\(field)`")
                }
                if !chunk.contains("isCode: false") {
                    for field in ["comments:", "stringDelimiters:"] where !chunk.contains(field) {
                        reading.problems.append("\(definitionsFile) 的 `.\(language)` 是代码语言却没有 `\(field)`（症状：识别了却一个颜色都没有）")
                    }
                }
                for (label, store) in [("fileExtensions:", 0), ("fileNames:", 1)] {
                    guard let listRegex = LScan.regex(NSRegularExpression.escapedPattern(for: label) + #"\s*\[([^\]]*)\]"#) else { continue }
                    for match in listRegex.matches(in: chunk, range: NSRange(location: 0, length: (chunk as NSString).length)) {
                        let list = (chunk as NSString).substring(with: match.range(at: 1))
                        for value in stringLiterals(list) {
                            if store == 0 {
                                reading.extensions += 1
                                if let owner = extensions[value] {
                                    reading.problems.append("扩展名 `.\(value)` 同时属于 `\(owner)` 与 `\(language)`（判语言会随表顺序变）")
                                }
                                extensions[value] = language
                            } else {
                                if let owner = entries[value] {
                                    reading.problems.append("文件名 `\(value)` 同时属于 `\(owner)` 与 `\(language)`")
                                }
                                entries[value] = language
                            }
                        }
                    }
                }
            }
            if Set(registered).count != registered.count {
                reading.problems.append("\(definitionsFile) 里有重复登记的语言（\(registered)）")
            }
            if Set(registered) != Set(reading.identifiers) {
                reading.problems.append("语言标识与登记项不是同一个集合 ——"
                                        + " 只在标识里：\(Set(reading.identifiers).subtracting(registered).sorted())；"
                                        + " 只在登记里：\(Set(registered).subtracting(reading.identifiers).sorted())")
            }
            reading.definitions = registered
            return reading
        }

        static func stringLiterals(_ text: String) -> [String] {
            guard let regex = LScan.regex(#""([^"]*)""#) else { return [] }
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
                ns.substring(with: $0.range(at: 1))
            }
        }

        // MARK: - C / E

        static func checkColors(_ files: [String: String]) -> (problems: [String], anchors: Int) {
            var problems: [String] = []
            var anchors = 0
            guard let tokens = files[tokenFile] else {
                problems.append("缺文件：\(tokenFile)")
                return (problems + ["\(tokenFile) 里找不到 `public enum SyntaxTone` —— 高亮色令牌的唯一定义处没了"], 0)
            }
            if !tokens.contains("public enum SyntaxTone") {
                problems.append("\(tokenFile) 里找不到 `public enum SyntaxTone` —— 高亮色令牌的唯一定义处没了")
            }
            for relative in editorFiles {
                guard let text = files[relative] else {
                    problems.append("缺文件：\(relative)")
                    continue
                }
                let stripped = stripComments(text)
                for (index, line) in stripped.components(separatedBy: "\n").enumerated() {
                    anchors += line.components(separatedBy: tokenAnchor).count - 1
                    if LScan.regex(bareColor)?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                        problems.append("\(relative):\(index + 1) 出现裸色值 —— 语法色必须走 `\(tokenAnchor)…`")
                    }
                }
                if !stripped.contains(tokenAnchor) {
                    problems.append("\(relative) 里没有取色锚点 `\(tokenAnchor)`（语法色的入口应当唯一）")
                }
            }
            return (problems, anchors)
        }

        static func checkDefaultViewConsumers(_ files: [String: String], browserViews: [String],
                                              viewFiles: [String: String]) -> (problems: [String], appFiles: Int, consumers: Int) {
            var problems: [String] = []
            _ = files
            let sources = viewFiles.keys.filter { $0.hasPrefix(viewSourceDir + "/") && $0.hasSuffix(".swift") }.sorted()
            if sources.isEmpty { return (["\(viewSourceDir)/ 不存在 —— 扫描面被削过（空跑不许通过）"], 0, 0) }
            var found: [String: [Int]] = [:]
            for relative in sources {
                let stripped = stripComments(viewFiles[relative] ?? "")
                for (index, line) in stripped.components(separatedBy: "\n").enumerated() where line.contains(viewConsumerToken) {
                    found[relative, default: []].append(index + 1)
                }
            }
            let allowed = Set(viewConsumerFiles)
            for relative in Set(found.keys).subtracting(allowed).sorted() {
                problems.append("\(relative) 也在读 `\(viewConsumerToken)` —— 「这个文件用哪种视图打开」只允许有一处消费者")
            }
            for relative in allowed.subtracting(found.keys).sorted() {
                problems.append("\(relative) 里没有 `\(viewConsumerToken)` —— 台账登记的消费者没接上")
            }
            for relative in allowed.intersection(found.keys).sorted() {
                if !stripComments(viewFiles[relative] ?? "").contains(viewHandoffAnchor) {
                    problems.append("\(relative) 读了 `\(viewConsumerToken)` 却没有交接锚点 `\(viewHandoffAnchor)` —— 判了却是白判")
                }
            }
            if sources.count < floorAppFiles {
                problems.append("\(viewSourceDir)/ 下只扫到 \(sources.count) 个 `.swift`（下限 \(floorAppFiles)）")
            }
            if browserViews != [browserViewLanguage] {
                problems.append("声明「默认用浏览器打开」（`defaultView: .browser`）的语言必须是 [\"\(browserViewLanguage)\"]，"
                                + "实际 \(browserViews)")
            }
            return (problems, sources.count, found.count)
        }
    }

    private func allSwiftFiles() throws -> [String: String] {
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles(Gate.faceDirs) { files[relative] = try LRepo.text(relative) }
        files[Gate.definitionsFile] = try LRepo.text(Gate.definitionsFile)
        files[Gate.tokenFile] = try LRepo.text(Gate.tokenFile)
        files[Gate.ledgerFile] = try LRepo.text(Gate.ledgerFile)
        return files
    }

    // MARK: - 真仓库判据

    func testLanguageRegistryShape() throws {
        let files = try allSwiftFiles()
        let definitions = Gate.checkDefinitions(files[Gate.definitionsFile] ?? "")
        let ledger = Gate.loadLedger(try LRepo.json(Gate.ledgerFile))
        let branches = Gate.checkIdentityBranches(files, identifiers: definitions.definitions,
                                                  ledger: ledger, declared: Gate.consumerFiles)
        let colors = Gate.checkColors(files)
        let views = Gate.checkDefaultViewConsumers(files, browserViews: definitions.browserViews, viewFiles: files)
        var problems = definitions.problems + ledger.problems + branches.problems + colors.problems + views.problems
        if definitions.definitions.count < Gate.floorDefinitions {
            problems.append("只解析到 \(definitions.definitions.count) 条登记项（下限 \(Gate.floorDefinitions)）")
        }
        if definitions.identifiers.count < Gate.floorIdentifiers {
            problems.append("只解析到 \(definitions.identifiers.count) 行语言标识（下限 \(Gate.floorIdentifiers)）")
        }
        if definitions.extensions < Gate.floorExtensions {
            problems.append("只解析到 \(definitions.extensions) 条扩展名（下限 \(Gate.floorExtensions)）")
        }
        if branches.scanned < Gate.floorConsumers {
            problems.append("只扫到 \(branches.scanned) 个语言消费方文件（下限 \(Gate.floorConsumers)）—— 扫描面失效")
        }
        if colors.anchors < Gate.floorAnchors {
            problems.append("只找到 \(colors.anchors) 处取色锚点（下限 \(Gate.floorAnchors)）—— 语法色可能没走主题令牌")
        }
        XCTAssertTrue(problems.isEmpty, "语言登记形状报红 \(problems.count) 处：\n" + problems.joined(separator: "\n"))
        print("📏 登记表：\(definitions.definitions.count) 种语言 / \(definitions.extensions) 条扩展名 / "
              + "A 档面 \(Gate.consumerFiles.count) 份（盘上发现 \(Gate.discoverConsumers(files).count) 份）/ "
              + "身份分支 \(branches.judged) 处（同名枚举 \(branches.homonym) · 豁免 \(branches.exempt)）/ "
              + "取色锚点 \(colors.anchors) 处 / 默认视图消费者 \(views.consumers) 个文件")
    }

    // MARK: - 反例

    func testIdentityBranchIsRed() {
        let files = [
            "Core/CodeLexer.swift": """
            func token(_ language: TextLanguage) -> Bool {
                if language == .sql { return true }
                return false
            }
            """,
        ]
        let reading = Gate.checkIdentityBranches(files, identifiers: ["sql"], ledger: Gate.Ledger(), declared: ["Core/CodeLexer.swift"])
        XCTAssertTrue(reading.problems.contains { $0.contains("按语言身份分支") }, "身份分支必须判红：\(reading.problems)")
    }

    /// 同名风格枚举：登记过 ⇒ 放过；没登记 ⇒ 红（fail-closed）。
    func testHomonymEnumNeedsRegistration() {
        let files = [
            "Core/Fixture.swift": """
            func pick(_ style: CodeFormatBuiltin) -> Bool {
                if style == .sql { return true }
                return false
            }
            """,
        ]
        let clean = Gate.checkIdentityBranches(files, identifiers: ["sql"],
                                               ledger: Gate.Ledger(exempt: [], homonymEnums: [["type": "CodeFormatBuiltin", "reason": "夹具"]]),
                                               declared: ["Core/Fixture.swift"])
        XCTAssertFalse(clean.problems.contains { $0.contains("身份分支") }, "登记过的同名枚举应放过：\(clean.problems)")

        let unregistered = Gate.checkIdentityBranches(files, identifiers: ["sql"], ledger: Gate.Ledger(),
                                                      declared: ["Core/Fixture.swift"])
        XCTAssertTrue(unregistered.problems.contains { $0.contains("身份分支") }, "未登记的同名枚举必须判红：\(unregistered.problems)")
    }

    /// A 档面必须与盘上发现面同集合：多一份消费者 / 死条目都判红。
    func testConsumerFaceDriftIsRed() {
        let files = ["Core/Planted.swift": "func f(_ language: TextLanguage) {}"]
        let extra = Gate.reconcileFace(files, declared: [])
        XCTAssertTrue(extra.contains { $0.contains("不在 A 档声明面里") }, "新消费者必须判红：\(extra)")
        let dead = Gate.reconcileFace(["Core/Clean.swift": "let x = 1"], declared: ["Core/Clean.swift"])
        XCTAssertTrue(dead.contains { $0.contains("死条目") }, "死条目必须判红：\(dead)")
    }

    func testDefinitionSelfConsistency() {
        let text = """
        enum Definitions {
            private static let definitions: [CodeLanguageDefinition] = [
                CodeLanguageDefinition(
                    .sql,
                    displayName: "SQL",
                    fileExtensions: ["sql", "psql"],
                    syntax: CodeSyntax(comments: [CodeCommentStyle(line: "--")], stringDelimiters: ["'"])
                ),
                CodeLanguageDefinition(
                    .python,
                    displayName: "Python",
                    fileExtensions: ["sql"],
                    isCode: false,
                    syntax: CodeSyntax()
                ),
                CodeLanguageDefinition(
                    .plain,
                    displayName: "Plain",
                    fileExtensions: ["txt"],
                    isFallback: true,
                    syntax: CodeSyntax()
                )
            ]
            public static let sql = TextLanguage(registered: "sql")
            public static let python = TextLanguage(registered: "python")
        }
        """
        let reading = Gate.checkDefinitions(text)
        XCTAssertTrue(reading.problems.contains { $0.contains("同时属于") }, "扩展名抢主人必须判红：\(reading.problems)")
        XCTAssertTrue(reading.problems.contains { $0.contains("不是同一个集合") }, "标识与登记项必须同集合：\(reading.problems)")

        let missingRule = text.replacingOccurrences(of: "comments: [CodeCommentStyle(line: \"--\")], ", with: "")
        XCTAssertTrue(Gate.checkDefinitions(missingRule).problems.contains { $0.contains("没有 `comments:`") },
                      "代码语言缺注释规则必须判红")
    }

    func testBareColorAndViewsAreRed() {
        let files = [
            Gate.tokenFile: "public enum SyntaxTone { case keyword }",
            "App/Views/CodeEditorView.swift": "let c = NSColor(red: 1, green: 0, blue: 0, alpha: 1)\nlet d = Theme.nsColor(SyntaxTone.keyword)",
            "App/Views/SQLEditorView.swift": "let e = Theme.nsColor(SyntaxTone.keyword)",
        ]
        let colors = Gate.checkColors(files)
        XCTAssertTrue(colors.problems.contains { $0.contains("裸色值") }, "裸色值必须判红：\(colors.problems)")

        let app = [
            "App/WorkspaceTabsModel.swift": "let v = registry.defaultView(forPath: p); openInBrowserTab()",
            "App/Other.swift": "let v = registry.defaultView(forPath: p)",
        ]
        let views = Gate.checkDefaultViewConsumers([:], browserViews: ["html"], viewFiles: app)
        XCTAssertTrue(views.problems.contains { $0.contains("也在读 `defaultView`") }, "第二个消费者必须判红：\(views.problems)")

        let noHandoff = ["App/WorkspaceTabsModel.swift": "let v = registry.defaultView(forPath: p)"]
        XCTAssertTrue(Gate.checkDefaultViewConsumers([:], browserViews: ["html"], viewFiles: noHandoff)
                        .problems.contains { $0.contains("交接锚点") }, "缺交接锚点必须判红")

        XCTAssertTrue(Gate.checkDefaultViewConsumers([:], browserViews: ["html", "markdown"],
                                                     viewFiles: ["App/WorkspaceTabsModel.swift": "defaultView openInBrowserTab"])
                        .problems.contains { $0.contains("默认用浏览器打开") }, "多一个 browser 类型必须判红")
    }
}
