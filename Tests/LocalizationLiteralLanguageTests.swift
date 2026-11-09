import XCTest

/// `check-literal-language.py` 的 Swift 版：**「语言是传进来的，不是写死的」**（队列 L-47）。
///
/// 挡的是第 46 轮读图抓到的 `diagnosis-empty-en`：英文界面上界面文案都是英文，**唯独「给模型的
/// 资料」整块是中文** —— `Core/DiagnosisContext.swift` 的文件私有取值助手把 `language:`
/// 钉死成 `.simplifiedChinese`，而语言表里那些键**都有英文译文**却只被这一处引用 ⇒ 英文译文
/// **永远不可达（死译文）**。汉字棘轮看不见它（代码里一个汉字都没有），「当前语言只有一个来源」
/// 也看不见它（只扫 `App/`）—— 「把语言写成字面量」这个形状两边都没覆盖。
///
/// 判据（逐条与脚本对齐）：
/// · **A** 写死语言的调用点必须逐条登记（按文件，带 `maxSites` 与理由）：未登记 / 超登记 ⇒ 红；
///   比登记少 ⇒ 只提示（减少是好事）；`maxSites: 0` = 回归钉；
/// · **B** 死译文双向对账：新增未登记的死键 ⇒ 红；修好不销账 / 键已不存在 ⇒ 红；包装函数
///   （形参含 `LKey`、函数体里写死语言）的每个调用点都算「写死语言」；
/// · **C** 本轮修的那几族不许回退：源树判据（文本出口必须带 `language:` 形参；调用方必须把
///   `language:` 传下去；笔记侧**不许**收语言；面板必须传 `effectiveLanguage`）；
/// · **C′** 一句话只有一个出处（`AppState` 必须调 `LicenseLoader.summary(`、不许自己抄 `L(.licenseActive)`）；
/// · **D** 空跑不许通过（语言表解析不到键 / 键引用为 0 / 扫描到的文件过少 ⇒ 红）。
///
/// 已知边界（原脚本照实登记，本测试不扩大也不缩小）：只认字面键与字面语言；动态键看不见（漏判）；
/// 「字面语言落局部变量再传」按**名字**追（不判作用域）；`Tests*` 不在扫描面。
final class LocalizationLiteralLanguageTests: XCTestCase {

    enum Gate {
        static let ledgerRel = "Scripts/literal-language-dispositions.json"
        static let tableRel = "Core/Localization.swift"
        static let scanRoots = ["Core", "App", "CLI", "Platform"]
        static let minSourceFiles = 80

        /// 把字面语言传下去的形状（判定物 = 代码面）。
        static let literalPattern = #"language:\s*(?:AppLanguage\s*)?\.\s*(simplifiedChinese|english)\b"#
        /// 字面语言先落局部变量、再当 `language:` 实参传下去。
        static let bindingPattern = #"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z_][A-Za-z0-9_.]*)?=\s*(?:AppLanguage\s*)?\.\s*(simplifiedChinese|english)\b"#
        /// 语言表定义行。
        static let keyDefPattern = #"^\s*\.([A-Za-z][A-Za-z0-9_]*):\s*\[\.simplifiedChinese:"#
        /// 本地化取值入口的形状。
        static let calleePattern = #"^(L|LocalizedStrings\.(text|format)|[A-Za-z_][A-Za-z0-9_.]*[Tt]ext|[A-Za-z_][A-Za-z0-9_.]*[Cc]opy)$"#

        struct Site {
            let file: String
            let line: Int
            let text: String
        }

        struct Reference {
            let key: String
            let file: String
            let line: Int
            let literal: Bool
        }

        struct Reading {
            var keys: [String: Bool] = [:]          // key → 是否有英文译文
            var files: [String] = []
            var sites: [Site] = []
            var references: [Reference] = []
            var problems: [String] = []
            var notes: [String] = []
            var deadKeys: [String: [Reference]] = [:]
            var registeredSites = 0
            var registeredDead = 0
        }

        // MARK: - 判定物

        static func masked(_ text: String) -> [Character] { Array(SwiftSource(text).codeText) }

        static func lineText(_ chars: [Character], at index: Int) -> String {
            var start = index
            while start > 0 && chars[start - 1] != "\n" { start -= 1 }
            var end = index
            while end < chars.count && chars[end] != "\n" { end += 1 }
            return String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
        }

        /// 一处「字面语言写在哪儿」（`BINDING` 的赋值行也算，`via` 记消费点数）。
        static func literalSites(_ relative: String, _ text: String) -> [Site] {
            let chars = Array(text)
            let code = masked(text)
            var sites: [Site] = []
            if let regex = LScan.regex(literalPattern) {
                let ns = String(code) as NSString
                for match in regex.matches(in: String(code), range: NSRange(location: 0, length: ns.length)) {
                    let offset = charOffset(String(code), utf16Offset: match.range.location)
                    sites.append(Site(file: relative, line: LScan.line(of: chars, at: offset),
                                      text: lineText(chars, at: offset)))
                }
            }
            if let binding = LScan.regex(bindingPattern) {
                let codeText = String(code)
                let ns = codeText as NSString
                for match in binding.matches(in: codeText, range: NSRange(location: 0, length: ns.length)) {
                    let name = ns.substring(with: match.range(at: 1))
                    guard let used = LScan.regex(#"language:\s*"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#) else { continue }
                    let count = used.numberOfMatches(in: codeText, range: NSRange(location: 0, length: ns.length))
                    if count == 0 { continue }
                    let offset = charOffset(codeText, utf16Offset: match.range.location)
                    let via = "字面语言先落局部变量 `\(name)`（.\(ns.substring(with: match.range(at: 2)))），"
                        + "再当 `language:` 实参传出去 \(count) 处"
                    sites.append(Site(file: relative, line: LScan.line(of: chars, at: offset),
                                      text: lineText(chars, at: offset) + "  [" + via + "]"))
                }
            }
            return sites.sorted { ($0.line, $0.text) < ($1.line, $1.text) }
        }

        static func charOffset(_ text: String, utf16Offset: Int) -> Int {
            let index = String.Index(utf16Offset: min(max(utf16Offset, 0), text.utf16.count), in: text)
            return text.distance(from: text.startIndex, to: index)
        }

        /// 语言表：键 → 是否带英文译文。
        static func keyTable(_ text: String) -> [String: Bool] {
            var table: [String: Bool] = [:]
            guard let regex = LScan.regex(keyDefPattern, options: [.anchorsMatchLines]) else { return table }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let lineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
                let line = ns.substring(with: lineRange)
                table[ns.substring(with: match.range(at: 1))] = line.contains(".english:")
            }
            return table
        }

        /// 本文件里形参含 `LKey` 的函数名（短名取值助手：`t(` / `text(`）。
        static func localHelpers(_ text: String) -> Set<String> {
            functionNames(text) { params, _ in params.contains("LKey") }
        }

        /// 文件私有的「写死语言取值助手」：形参含 `LKey`、函数体里出现字面语言（代码面）。
        static func wrapperNames(_ text: String) -> Set<String> {
            let code = masked(text)
            return functionNames(text) { params, body in
                guard params.contains("LKey") else { return false }
                return LScan.regex(literalPattern)?.firstMatch(
                    in: body, range: NSRange(location: 0, length: (body as NSString).length)) != nil
            }
        }

        /// 扫描 `func 名(…)` 的形参与函数体，按 `accept` 过滤。
        static func functionNames(_ text: String, accept: (String, String) -> Bool) -> Set<String> {
            var names: Set<String> = []
            let chars = Array(text)
            guard let regex = LScan.regex(#"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#) else { return names }
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let open = match.range.location + match.range.length - 1
                guard let close = LScan.bracket(chars, from: open, open: "(", close: ")") else { continue }
                let params = String(chars[(open + 1)..<close])
                var brace = close + 1
                while brace < chars.count && chars[brace] != "{" && chars[brace] != "\n" { brace += 1 }
                guard brace < chars.count, chars[brace] == "{",
                      let end = LScan.bracket(chars, from: brace, open: "{", close: "}") else { continue }
                let body = String(chars[brace..<min(end + 1, chars.count)])
                if accept(params, body) { names.insert(ns.substring(with: match.range(at: 1))) }
            }
            return names
        }

        /// 从 `index` 处向左找最近的未配对 `(`，连同被调名一起返回 (start, end)。
        static func enclosingCall(_ chars: [Character], at index: Int) -> (Int, Int)? {
            var depth = 0
            var cursor = index
            var open = -1
            while cursor >= 0 {
                if chars[cursor] == ")" { depth += 1 }
                else if chars[cursor] == "(" {
                    if depth == 0 { open = cursor; break }
                    depth -= 1
                }
                cursor -= 1
            }
            guard open >= 0, let end = LScan.bracket(chars, from: open, open: "(", close: ")") else { return nil }
            var start = open - 1
            while start >= 0, chars[start].isLetter || chars[start].isNumber || chars[start] == "." || chars[start] == "_" {
                start -= 1
            }
            return (start + 1, end)
        }

        static func keyReferences(_ relative: String, _ text: String,
                                  keys: Set<String>, wrappers: Set<String>) -> [Reference] {
            guard relative != tableRel else { return [] }
            // 短名取值助手（`t(` / `text(`）必须**按文件**发现：形参含 `LKey` 的本地函数。
            let helpers = localHelpers(text)
            let chars = Array(text)
            guard let regex = LScan.regex(#"\.([A-Za-z][A-Za-z0-9_]*)\b"#) else { return [] }
            let ns = text as NSString
            var references: [Reference] = []
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: match.range(at: 1))
                guard keys.contains(name) else { continue }
                let offset = charOffset(text, utf16Offset: match.range.location)
                guard let call = enclosingCall(chars, at: offset) else { continue }
                let segment = String(chars[call.0...call.1])
                guard let callee = segment.split(separator: "(", maxSplits: 1,
                                                 omittingEmptySubsequences: false).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces) else { continue }
                let accepted = LScan.regex(calleePattern)?.firstMatch(
                    in: callee, range: NSRange(location: 0, length: (callee as NSString).length)) != nil
                guard accepted || helpers.contains(callee) else { continue }
                let maskedSegment = String(masked(segment))
                let literal = (LScan.regex(literalPattern)?.firstMatch(
                    in: maskedSegment, range: NSRange(location: 0, length: (maskedSegment as NSString).length)) != nil)
                    || wrappers.contains(callee)
                references.append(Reference(key: name, file: relative, line: LScan.line(of: chars, at: offset), literal: literal))
            }
            return references
        }

        // MARK: - 判据 C（源树判据 / 调用方 / 负向那一条）

        /// 文本出口必须带 `language:` 形参（删掉形参、再在函数体里写死一次，只靠 A 挡不住）。
        static let pinnedParameters: [(file: String, patterns: [String])] = [
            ("Core/DiagnosisContext.swift", [
                #"func\s+text\(language:"#,
                #"func\s+promptText\(language:"#,
                #"func\s+boundedPromptText\(language:"#,
                #"func\s+makeEvidence\([\s\S]{0,400}?language:\s*AppLanguage"#,
            ]),
            ("Core/DiagnosisAdvice.swift", [#"func\s+parse\([\s\S]{0,300}?language:\s*AppLanguage"#]),
            ("Core/LicenseLoader.swift", [
                #"func\s+load\([\s\S]{0,400}?language:\s*AppLanguage"#,
                #"func\s+licenseDecodeFailureHint\(language:\s*AppLanguage"#,
                #"func\s+summary\([\s\S]{0,200}?language:\s*AppLanguage"#,
            ]),
            ("Plugins/Notes/Sources/NoteBody.swift", [
                #"func\s+toSpans\([^)]*language:\s*AppLanguage"#,
                #"func\s+exportMarkdown\([^)]*language:\s*AppLanguage"#,
            ]),
            ("Core/TableImport.swift", [
                #"func\s+copySupport\([^)]*language:\s*AppLanguage"#,
                #"func\s+preferredWriteMode\([^)]*language:\s*AppLanguage"#,
            ]),
            ("Core/SSHTunnelProcess.swift", [
                #"func\s+start\([^)]*language:\s*AppLanguage"#,
                #"func\s+describe\(language:\s*AppLanguage"#,
            ]),
            ("Core/AICaptureUltra.swift", [
                #"func\s+diagnosisNote\([\s\S]{0,500}?language:\s*AppLanguage"#,
                #"func\s+maintenanceNote\([\s\S]{0,500}?language:\s*AppLanguage"#,
                #"func\s+stateText\([^)]*language:\s*AppLanguage"#,
            ]),
            ("Core/License.swift", [
                #"func\s+features\(language:\s*AppLanguage"#,
                #"func\s+items\([^)]*language:\s*AppLanguage"#,
            ]),
            ("Core/LicensePresentation.swift", [#"func\s+upgradeLines\([\s\S]{0,300}?language:\s*AppLanguage"#]),
            ("Core/MaintenancePlan.swift", [
                #"func\s+review\([\s\S]{0,400}?language:\s*AppLanguage"#,
                #"func\s+makePlan\([\s\S]{0,300}?language:\s*AppLanguage"#,
            ]),
            ("Core/MCPToolCatalog.swift", [#"func\s+decision\([\s\S]{0,600}?language:\s*AppLanguage"#]),
            ("Core/MCPSession.swift", [
                #"public\s+let\s+language:\s*AppLanguage"#,
                #"init\([\s\S]{0,200}?language:\s*AppLanguage"#,
            ]),
            ("Core/MySQLWording.swift", [
                #"func\s+connectTimedOut\([^)]*language:\s*AppLanguage"#,
                #"func\s+hostResolveFailed\([^)]*language:\s*AppLanguage"#,
                #"func\s+lastInsertID\([^)]*language:\s*AppLanguage"#,
                #"func\s+statementTimeout\([^)]*language:\s*AppLanguage"#,
                #"func\s+cancelNoConnectionID\([^)]*language:\s*AppLanguage"#,
                #"func\s+cancelStatementMissing\([^)]*language:\s*AppLanguage"#,
                #"func\s+cancelDispatchFailed\([^)]*language:\s*AppLanguage"#,
                #"func\s+copyUnsupported\([^)]*language:\s*AppLanguage"#,
            ]),
            ("Core/MySQLService.swift", [
                #"public\s+nonisolated\s+let\s+language:\s*AppLanguage"#,
                #"init\([\s\S]{0,200}?language:\s*AppLanguage"#,
                #"func\s+withTimeout<[\s\S]{0,200}?language:\s*AppLanguage"#,
            ]),
        ]

        /// 调用方也必须把语言传下去（形参留着还不够）。
        static let callSiteNeedles: [(file: String, needles: [String])] = [
            ("App/AppState.swift", [
                "MaintenancePlanner.makePlan(", "AICapture.maintenanceNote(",
                "AICapture.diagnosisNote(", "DatabaseServiceFactory.make(",
            ]),
            ("App/Views/AboutLicenseSheet.swift", ["LicensePresentation.upgradeLines("]),
            ("App/Views/ConnectionFormView.swift", ["DatabaseServiceFactory.make("]),
            ("CLI/main.swift", [
                "MaintenancePlanner.makePlan(", "MCPServerSession(capabilities:",
                "DatabaseServiceFactory.make(",
            ]),
            ("Core/DatabaseService.swift", ["MySQLService(config:", "GBaseService(config:"]),
            ("Core/GBaseService.swift", ["MySQLService("]),
        ]

        static func sourceTreeProblems(files: [String: String]) -> [String] {
            var problems: [String] = []
            for (relative, patterns) in pinnedParameters.sorted(by: { $0.file < $1.file }) {
                guard let text = files[relative] else {
                    problems.append("C 文件消失：\(relative)")
                    continue
                }
                let ns = text as NSString
                for pattern in patterns {
                    guard let regex = LScan.regex(pattern),
                          regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil else {
                        problems.append("C \(relative) 的文本出口丢了 `language:` 形参（匹配不到：\(pattern)）")
                        continue
                    }
                }
            }
            for (relative, needles) in callSiteNeedles.sorted(by: { $0.file < $1.file }) {
                guard let text = files[relative] else {
                    problems.append("C 文件消失：\(relative)")
                    continue
                }
                let chars = Array(text)
                for needle in needles {
                    guard let range = text.range(of: needle) else {
                        problems.append("C \(relative) 里找不到调用点 \(needle)（改名了？）")
                        continue
                    }
                    let start = text.distance(from: text.startIndex, to: range.lowerBound)
                    guard let paren = LScan.firstIndex(of: "(", in: chars, from: start),
                          let close = LScan.bracket(chars, from: paren, open: "(", close: ")") else {
                        problems.append("C \(relative) 的 \(needle) 实参括号不配对 —— 判据取不到输入")
                        continue
                    }
                    if !String(chars[paren..<close]).contains("language:") {
                        problems.append("C \(relative) 的 \(needle) 没把语言传下去 —— Core 里那族又会退回「自己选语言」")
                    }
                }
            }
            // 负向：笔记侧不许收语言（`Core/AICapture.swift` 只收文本与标识）。
            if let note = files["Core/AICapture.swift"] {
                let code = note.components(separatedBy: "\n").map { $0.split(separator: "/", maxSplits: 1,
                                                                           omittingEmptySubsequences: false).first.map(String.init) ?? "" }
                    .joined(separator: "\n")
                let ns = code as NSString
                let hasParameter = LScan.regex(#"language:\s*AppLanguage"#)?.firstMatch(
                    in: code, range: NSRange(location: 0, length: ns.length)) != nil
                let hasLiteral = LScan.regex(literalPattern)?.firstMatch(
                    in: code, range: NSRange(location: 0, length: ns.length)) != nil
                if hasParameter || hasLiteral {
                    problems.append("C Core/AICapture.swift 又收起了语言 —— 笔记侧只收文本与标识，语言由宿主渲染好再进来")
                }
                for (pattern, what) in [
                    (#"func\s+skillNote\([\s\S]{0,500}?defaultTag:\s*String"#, "skillNote(defaultTag:)"),
                    (#"func\s+sqlNote\([\s\S]{0,400}?tag:\s*String"#, "sqlNote(tag:)"),
                ] {
                    if LScan.regex(pattern)?.firstMatch(in: note, range: NSRange(location: 0, length: (note as NSString).length)) == nil {
                        problems.append("C Core/AICapture.swift 的出口不再收「渲染好的标签文本」（\(what)）")
                    }
                }
            } else {
                problems.append("C 文件消失：Core/AICapture.swift")
            }
            // 面板必须把 effectiveLanguage 传给**那一个调用点**（文件里别处出现不算）。
            if let panel = files["App/Views/DiagnosisPanel.swift"] {
                let chars = Array(panel)
                let needle = "boundedPromptText("
                guard let range = panel.range(of: needle) else {
                    problems.append("C App/Views/DiagnosisPanel.swift 里找不到 \(needle)（改名了？判据取不到输入）")
                    return problems
                }
                let start = panel.distance(from: panel.startIndex, to: range.lowerBound)
                guard let paren = LScan.firstIndex(of: "(", in: chars, from: start),
                      let close = LScan.bracket(chars, from: paren, open: "(", close: ")") else {
                    problems.append("C App/Views/DiagnosisPanel.swift 的 \(needle) 实参括号不配对 —— 判据取不到输入")
                    return problems
                }
                if !String(chars[paren..<close]).contains("language: LocalizationManager.shared.effectiveLanguage") {
                    problems.append("C App/Views/DiagnosisPanel.swift 没把 effectiveLanguage 传给 boundedPromptText（界面语言又会与提示词脱钩）")
                }
            } else {
                problems.append("C 文件消失：App/Views/DiagnosisPanel.swift")
            }
            // C′：一句话只有一个出处。
            if let state = files["App/AppState.swift"] {
                if !state.contains("LicenseLoader.summary(") {
                    problems.append("C App/AppState.swift 没有调 `LicenseLoader.summary(` —— 界面又自己抄了一份许可文案")
                }
                if state.contains("L(.licenseActive)") {
                    problems.append("C App/AppState.swift 又出现 `L(.licenseActive)` —— 许可状态那一句应当只有 "
                                    + "`LicenseLoader.summary(for:language:)` 一个出处（抄一份必然漂移）")
                }
            } else {
                problems.append("C 文件消失：App/AppState.swift")
            }
            return problems
        }

        // MARK: - 判定

        static func evaluate(files: [String: String], ledger: [String: Any]) -> Reading {
            var reading = Reading()
            let tableText = files[tableRel] ?? ""
            reading.keys = keyTable(tableText)
            let keys = Set(reading.keys.keys)
            reading.files = files.keys.sorted()

            if reading.keys.isEmpty {
                reading.problems.append("语言表一个键都没解析到（\(tableRel)）—— 判据取不到输入，不许当通过")
            }
            if reading.files.count < minSourceFiles {
                reading.problems.append("只扫到 \(reading.files.count) 个 Swift 文件（少于 \(minSourceFiles)）—— 扫描根写错了吧")
            }

            for relative in reading.files {
                let text = files[relative] ?? ""
                reading.sites.append(contentsOf: literalSites(relative, text))
                reading.references.append(contentsOf: keyReferences(
                    relative, text, keys: keys, wrappers: wrapperNames(text)))
            }
            if reading.references.isEmpty {
                reading.problems.append("一个键引用都没有 —— 判据取不到输入，不许当通过")
            }

            // A：写死语言的调用点逐条登记（按文件归组 + 棘轮）
            var measured: [String: [Site]] = [:]
            for site in reading.sites { measured[site.file, default: []].append(site) }
            let registeredFiles = Set(((ledger["files"] as? [[String: Any]]) ?? []).map { LRepo.string($0["file"]) })
            reading.registeredSites = registeredFiles.count
            var registeredByFile: [String: [String: Any]] = [:]
            for entry in (ledger["files"] as? [[String: Any]]) ?? [] {
                registeredByFile[LRepo.string(entry["file"])] = entry
            }
            for (name, occurrences) in measured.sorted(by: { $0.key < $1.key }) {
                guard let entry = registeredByFile[name] else {
                    reading.problems.append("A 未登记的写死语言调用点：\(name)（\(occurrences.count) 处，首个在 "
                                            + "\(occurrences[0].line) 行：\(occurrences[0].text)）⇒ 要么把语言透传，"
                                            + "要么在台账 \(ledgerRel) 里登记 maxSites 与理由")
                    continue
                }
                if occurrences.count > LRepo.int(entry["maxSites"]) {
                    reading.problems.append("A 写死语言调用点增多：\(name) 实测 \(occurrences.count) 处 > "
                                            + "台账 maxSites \(LRepo.int(entry["maxSites"]))（第 \(occurrences[0].line) 行起：\(occurrences[0].text)）")
                }
            }
            for (name, entry) in registeredByFile.sorted(by: { $0.key < $1.key }) {
                guard let occurrences = measured[name] else {
                    if LRepo.int(entry["maxSites"]) > 0 {
                        reading.problems.append("A 台账条目陈旧：\(name) 登记了 maxSites \(LRepo.int(entry["maxSites"]))，"
                                                + "但实测 0 处 ⇒ 把它销掉或改成 0（回归钉）")
                    }
                    continue
                }
                if occurrences.count < LRepo.int(entry["maxSites"]) {
                    reading.notes.append("\(name) 的写死语言调用点由 \(LRepo.int(entry["maxSites"])) 处减到 \(occurrences.count) 处")
                }
            }

            // B：死译文（双向对账）
            var byKey: [String: [Reference]] = [:]
            for reference in reading.references { byKey[reference.key, default: []].append(reference) }
            for (name, occurrences) in byKey where reading.keys[name] == true && occurrences.allSatisfy(\.literal) {
                reading.deadKeys[name] = occurrences
            }
            let registeredDeadEntries = (ledger["deadKeys"] as? [[String: Any]]) ?? []
            let registeredDead = Set(registeredDeadEntries.map { LRepo.string($0["key"]) })
            reading.registeredDead = registeredDead.count
            for (name, occurrences) in reading.deadKeys.sorted(by: { $0.key < $1.key }) where !registeredDead.contains(name) {
                let where_ = occurrences.prefix(3).map { "\($0.file):\($0.line)" }.joined(separator: "、")
                reading.problems.append("B 新增死译文：.\(name) 有英文译文却只被写死语言的入口引用（\(where_)）")
            }
            for name in registeredDead.sorted() {
                if !keys.contains(name) {
                    reading.problems.append("B 台账陈旧：deadKey .\(name) 在语言表里已不存在")
                } else if reading.deadKeys[name] == nil {
                    reading.problems.append("B 台账陈旧：deadKey .\(name) 现在已经可达（或不再被引用）⇒ 修好了就销账")
                }
            }

            reading.problems.append(contentsOf: sourceTreeProblems(files: files))
            return reading
        }
    }

    // MARK: - 真仓库判据

    func testLanguageIsPassedInNotHardcoded() throws {
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles(Gate.scanRoots) {
            files[relative] = try LRepo.text(relative)
        }
        files[Gate.tableRel] = try LRepo.text(Gate.tableRel)
        // 判据 C 还要读三个不在扫描根里的文件（笔记插件 / 面板）。
        for relative in ["Plugins/Notes/Sources/NoteBody.swift", "Plugins/Notes/Sources/NoteStorage/NoteBodyMigration.swift",
                         "App/Views/DiagnosisPanel.swift"] where files[relative] == nil {
            if let text = LRepo.textIfExists(relative) { files[relative] = text }
        }
        let result = Gate.evaluate(files: files, ledger: try LRepo.json(Gate.ledgerRel))
        XCTAssertTrue(result.problems.isEmpty,
                      "语言透传报红 \(result.problems.count) 项：\n" + result.problems.joined(separator: "\n"))
        XCTAssertGreaterThan(result.references.count, 0, "键引用为 0 —— 判据取不到输入")
        print("📏 语言透传：扫描 \(result.files.count) 个 Swift 文件；写死语言调用点 \(result.sites.count) 处"
              + "（登记 \(result.registeredSites) 个文件）；死译文 \(result.registeredDead) 个键")
    }

    // MARK: - 反例

    /// 三种「写死语言」的形状都要抓到：裸枚举 / 限定枚举 / 落局部变量再传；注释与字符串不算。
    func testLiteralLanguageShapes() {
        let text = """
        enum Fixture {
            func a() { render(language: .simplifiedChinese) }
            func b() { render(language: AppLanguage.english) }
            func c() {
                let lang = AppLanguage.simplifiedChinese
                render(language: lang)
            }
            func d() { render(language: languageProvider()) }
            // render(language: .english)
            let s = "render(language: .english)"
            let unused = AppLanguage.english
        }
        """
        let sites = Gate.literalSites("Core/Fixture.swift", text)
        XCTAssertEqual(sites.count, 3, "三处写死语言（含赋值形），注释 / 字符串 / 未传出的赋值不算：\(sites.map { "\($0.line):\($0.text)" })")
        XCTAssertEqual(sites.last?.line, 5, "赋值形记在赋值那一行：\(sites.map(\.line))")
    }

    /// 死译文双向：只被写死语言的入口引用的键 ⇒ 死；有可达路径 ⇒ 活；台账不销账 ⇒ 红。
    func testDeadKeyDetectionBothWays() {
        let table = """
        enum Fixture {
            static let table: [LKey: [AppLanguage: String]] = [
                .dead: [.simplifiedChinese: "甲", .english: "A"],
                .alive: [.simplifiedChinese: "乙", .english: "B"],
            ]
        }
        """
        let files = [
            Gate.tableRel: table,
            "Core/Fixture.swift": """
            enum Fixture {
                private func t(_ key: LKey) -> String { LocalizedStrings.text(key, language: .simplifiedChinese) }
                let a = t(.dead)
                let b = L(.alive, language: contextLanguage())
            }
            """,
        ]
        var ledger: [String: Any] = ["files": [["file": "Core/Fixture.swift", "maxSites": 1, "reason": "夹具"]], "deadKeys": []]
        let unregistered = Gate.evaluate(files: files, ledger: ledger).problems.filter { $0.hasPrefix("B") }
        XCTAssertTrue(unregistered.contains { $0.contains("新增死译文：.dead") },
                      "未登记的死键必须判红：\(unregistered)")

        ledger["deadKeys"] = [["key": "dead", "reason": "夹具：已登记的欠账"]]
        let registered = Gate.evaluate(files: files, ledger: ledger).problems.filter { $0.hasPrefix("B") }
        XCTAssertFalse(registered.contains { $0.contains("新增死译文") },
                       "登记过的不再报新增：\(registered)")

        ledger["deadKeys"] = [["key": "alive", "reason": "夹具：故意陈旧"]]
        let stale = Gate.evaluate(files: files, ledger: ledger).problems.filter { $0.hasPrefix("B") }
        XCTAssertTrue(stale.contains { $0.contains("台账陈旧：deadKey .alive") },
                      "已可达的死键必须销账：\(stale)")
    }

    /// 写死语言的调用点超登记上限 ⇒ 红；台账条目陈旧 ⇒ 红。
    func testLiteralSiteRatchetAndStaleLedger() {
        let files = [
            Gate.tableRel: "enum X {\n    static let table: [LKey: [AppLanguage: String]] = [\n"
                + "        .k: [.simplifiedChinese: \"甲\", .english: \"A\"],\n    ]\n}\n",
            "Core/Fixture.swift": """
            enum Fixture {
                let a = L(.k, language: .simplifiedChinese)
                let b = L(.k, language: .simplifiedChinese)
            }
            """,
        ]
        let over = Gate.evaluate(files: files,
                                 ledger: ["files": [["file": "Core/Fixture.swift", "maxSites": 1, "reason": "夹具"]],
                                          "deadKeys": []])
        XCTAssertTrue(over.problems.contains { $0.contains("A 写死语言调用点增多") }, "超上限必须判红：\(over.problems)")

        let stale = Gate.evaluate(files: [Gate.tableRel: files[Gate.tableRel]!,
                                          "Core/Clean.swift": "enum Clean { let a = 1 }\n"],
                                  ledger: ["files": [["file": "Core/Clean.swift", "maxSites": 3, "reason": "夹具：陈旧"]],
                                           "deadKeys": []])
        XCTAssertTrue(stale.problems.contains { $0.contains("A 台账条目陈旧") }, "陈旧条目必须判红：\(stale.problems)")
    }

    /// 源树判据：删掉 `language:` 形参 / 调用方不传 / 笔记侧收回语言 ⇒ 红（只靠 A 挡不住的那一族）。
    func testSourceTreeJudgementIsRed() {
        let files = [
            "Core/DiagnosisContext.swift": "enum D { func text(key: LKey) -> String { key.rawValue } }",
            "Core/DiagnosisAdvice.swift": "enum A { func parse(reply: String) -> Int { 0 } }",
            "Core/LicenseLoader.swift": "enum L { func load() {} }",
            "Plugins/Notes/Sources/NoteBody.swift": "enum N { func toSpans() {} }",
            "Core/TableImport.swift": "enum T { func copySupport() {} }",
            "Core/SSHTunnelProcess.swift": "enum S { func start() {} }",
            "Core/AICaptureUltra.swift": "enum U { func diagnosisNote() {} }",
            "Core/License.swift": "enum L2 { func features() {} }",
            "Core/LicensePresentation.swift": "enum P { func upgradeLines() {} }",
            "Core/MaintenancePlan.swift": "enum M { func review() {} }",
            "Core/MCPToolCatalog.swift": "enum C { func decision() {} }",
            "Core/MCPSession.swift": "final class S2 { init() {} }",
            "Core/MySQLWording.swift": "enum W { func connectTimedOut() {} }",
            "Core/MySQLService.swift": "final class S3 { init() {} }",
            "Core/AICapture.swift": "enum Capture { func skillNote(tag: String) {} }",
            "App/Views/DiagnosisPanel.swift": "let x = boundedPromptText(text)",
            "App/AppState.swift": "let y = L(.licenseActive)",
        ]
        let problems = Gate.sourceTreeProblems(files: files)
        XCTAssertTrue(problems.contains { $0.contains("DiagnosisContext.swift 的文本出口丢了") },
                      "形参被删必须判红：\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("DiagnosisPanel.swift 没把 effectiveLanguage") },
                      "面板不传 effectiveLanguage 必须判红：\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("AppState.swift 又出现 `L(.licenseActive)`") },
                      "重复实现必须判红：\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("AppState.swift 没有调 `LicenseLoader.summary(") },
                      "不自证出处必须判红：\(problems)")
    }

    /// 空跑不许通过：语言表解析不到键 / 键引用为 0。
    func testEmptyRunIsRed() {
        let result = Gate.evaluate(files: ["Core/Fixture.swift": "enum X {}\n"], ledger: ["files": [], "deadKeys": []])
        XCTAssertTrue(result.problems.contains { $0.contains("语言表一个键都没解析到") }, "空表必须判红：\(result.problems)")
        XCTAssertTrue(result.problems.contains { $0.contains("一个键引用都没有") }, "零引用必须判红：\(result.problems)")
    }
}
