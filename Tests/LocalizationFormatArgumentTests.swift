import XCTest

/// `check-format-arguments.py` 的 Swift 版：**语言表占位符 ↔ 调用点实参的对账**（队列 L-46）。
///
/// 挡的是第 16 轮读图抓到的 `待审批（(null)）`：模板写 `%@`（对象）而调用点传 `Int`
/// —— `String(format:)` 对非对象参数给的就是字面量 `(null)`。编译过、单测绿、门禁全过，
/// 只有像素上看得见（没人比较**模板**与**实参**）。
///
/// 判据（逐条与脚本对齐）：
/// · **A** 数字实参落 `%@` 槽 ⇒ 红；**A′** 字符串实参落 `%d`/`%f`/`*` 槽 ⇒ 红；
/// · **B** 实参数 ≠ 该位置模板的占位符数（中英**任一**侧）⇒ 红（界面上会印出模板原文 `%@`）；
/// · **C** 判不出类型的实参**不是白名单放行**：形状必须逐条登记（`unclassified` 式的裸漏 ⇒ 红）；
/// · **D** 每个形状命中处数不许超登记上限；全局「无据」量不许超 `unknownBudget`；
/// · **E** 台账不许陈旧（例外必须仍对应一处真违规、形状必须仍被命中）；**空跑不许通过**；
/// · **F** 扫描面由 `Package.swift` 的生产 target 派生（面里的根不在盘 / 生产 target 没声明路径 ⇒ 红）；
/// · **G** 语言列表由 `enum AppLanguage` 派生；某个键少一种语言 / 用了枚举外的语言 ⇒ 红。
///
/// 已知局限（原脚本照实登记的，本测试同样不覆盖）：只查 `L(...)`；`Tests*` 不在面内；
/// 判不出类型的实参只被「形状登记 + 棘轮」钉住（`kind` 写错看不见）。
final class LocalizationFormatArgumentTests: XCTestCase {

    enum Gate {
        static let tableRel = "Core/Localization.swift"
        static let anchor = "static let table: [LKey: [AppLanguage: String]]"
        static let ledgerRel = "Scripts/format-argument-dispositions.json"
        static let packageRel = "Package.swift"

        struct Site {
            let file: String
            let line: Int
            let key: String
            let args: [String]
        }

        struct Evaluation {
            var errors: [String] = []
            var notes: [String] = []
            var tableKeys = 0
            var specKeys = 0
            var checked = 0
            var totalSites = 0
            var unknownTotal = 0
            var unknownUnregistered = 0
            var unknownUnverified = 0
            var typedByEvidence = 0
            var unknownBudget = 0
            var face: [String] = []
            var languages: [String] = []
            var shapeHistogram: [String: Int] = [:]
        }

        // MARK: - 转换符

        /// printf 转换符：可选位置索引 / 标志 / 宽度 / 精度 / 长度修饰 + 转换符本身。
        static let specPattern = #"%(?:(\d+)\$)?[-+ #0]*(\d+|\*)?(?:\.(\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?([@diouxXfFeEgGscpn%])"#

        /// 模板的**实参槽位序列**：位置索引按 1-based 归位、`*` 宽度/精度各占一个槽、`%%` 不是槽。
        static func specifiers(_ template: String) -> [String] {
            guard let regex = LScan.regex(specPattern) else { return [] }
            var slots: [String?] = []
            var cursor = 0
            let ns = template as NSString
            for match in regex.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
                let conversion = ns.substring(with: match.range(at: 4))
                if conversion == "%" { continue }
                var stars: [String] = []
                for group in [2, 3] {
                    let range = match.range(at: group)
                    if range.location != NSNotFound, ns.substring(with: range) == "*" { stars.append("*") }
                }
                let indexText = match.range(at: 1).location == NSNotFound ? nil : ns.substring(with: match.range(at: 1))
                let start = indexText.flatMap { Int($0).map { $0 - 1 } } ?? cursor
                for offset in 0..<stars.count {
                    while slots.count <= start + offset { slots.append(nil) }
                    slots[start + offset] = "*"
                }
                let last = start + stars.count
                while slots.count <= last { slots.append(nil) }
                slots[last] = conversion
                cursor = last + 1
            }
            return slots.map { $0 ?? "?" }
        }

        // MARK: - 语言表（模板侧）

        /// `key → language → template`。只认登记表数组**里面**的条目。
        static func table(_ source: String) -> [String: [String: String]] {
            let chars = Array(source)
            guard let anchorRange = source.range(of: anchor) else { return [:] }
            let anchorEnd = source.distance(from: source.startIndex, to: anchorRange.upperBound)
            guard let equals = firstIndex(of: "= [", in: chars, from: anchorEnd),
                  let open = firstIndex(of: "[", in: chars, from: equals + 2) else { return [:] }
            guard let close = LScan.bracket(chars, from: open) else { return [:] }
            let bodyChars = Array(chars[(open + 1)..<close])
            let masked = Array(SwiftSource(String(bodyChars)).uncommentedText)
            var result: [String: [String: String]] = [:]
            var index = 0
            while index < masked.count {
                guard masked[index] == "." else { index += 1; continue }
                var cursor = index + 1
                var key = ""
                while cursor < masked.count, masked[cursor].isLetter || masked[cursor].isNumber || masked[cursor] == "_" {
                    key.append(masked[cursor])
                    cursor += 1
                }
                while cursor < masked.count, masked[cursor] == " " || masked[cursor] == "\t" { cursor += 1 }
                guard !key.isEmpty, cursor < masked.count, masked[cursor] == ":" else { index += 1; continue }
                cursor += 1
                while cursor < masked.count, masked[cursor] == " " || masked[cursor] == "\t" { cursor += 1 }
                guard cursor < masked.count, masked[cursor] == "[" else { index += 1; continue }
                guard let innerClose = LScan.bracket(masked, from: cursor) else { index += 1; continue }
                let inner = String(bodyChars[(cursor + 1)..<innerClose])
                var entry: [String: String] = [:]
                for language in [LanguageTable.slots.0, LanguageTable.slots.1] {
                    if let literal = languageLiteral(in: inner, language: language) {
                        entry[language] = literal
                    }
                }
                if !entry.isEmpty { result[key] = entry }
                index = innerClose + 1
            }
            return result
        }

        /// `.language: "…"` 的值；支持 `"a" + "b"` 拼接。
        static func languageLiteral(in text: String, language: String) -> String? {
            let chars = Array(text)
            var index = 0
            while index < chars.count {
                guard chars[index] == "." else { index += 1; continue }
                var cursor = index + 1
                var name = ""
                while cursor < chars.count, chars[cursor].isLetter || chars[cursor].isNumber {
                    name.append(chars[cursor])
                    cursor += 1
                }
                guard name == language else { index += 1; continue }
                while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" { cursor += 1 }
                guard cursor < chars.count, chars[cursor] == ":" else { index += 1; continue }
                cursor += 1
                while cursor < chars.count, chars[cursor] == " " || chars[cursor] == "\t" || chars[cursor] == "\n" {
                    cursor += 1
                }
                guard cursor < chars.count, chars[cursor] == "\"" else { return nil }
                return readConcatenatedLiteral(chars, from: cursor)
            }
            return nil
        }

        static func readConcatenatedLiteral(_ chars: [Character], from start: Int) -> String {
            var pieces = ""
            var cursor = start
            while cursor < chars.count, chars[cursor] == "\"" {
                cursor += 1
                while cursor < chars.count, chars[cursor] != "\"" {
                    if chars[cursor] == "\\", cursor + 1 < chars.count {
                        pieces.append(chars[cursor])
                        pieces.append(chars[cursor + 1])
                        cursor += 2
                        continue
                    }
                    pieces.append(chars[cursor])
                    cursor += 1
                }
                cursor += 1 // 闭引号
                while cursor < chars.count, " \n\t".contains(chars[cursor]) { cursor += 1 }
                if cursor < chars.count, chars[cursor] == "+" {
                    cursor += 1
                    while cursor < chars.count, " \n\t".contains(chars[cursor]) { cursor += 1 }
                    if cursor < chars.count, chars[cursor] == "\"" { continue }
                }
                break
            }
            return pieces
        }

        /// UTF-16 偏移（NSRegularExpression 给的）→ Character 偏移（[Character] 下标）。
        static func charOffset(_ text: String, utf16Offset: Int) -> Int {
            let index = String.Index(utf16Offset: min(max(utf16Offset, 0), text.utf16.count), in: text)
            return text.distance(from: text.startIndex, to: index)
        }

        static func firstIndex(of character: Character, in chars: [Character], from: Int) -> Int? {
            var index = max(from, 0)
            while index < chars.count {
                if chars[index] == character { return index }
                index += 1
            }
            return nil
        }

        static func firstIndex(of needle: String, in chars: [Character], from: Int) -> Int? {
            let target = Array(needle)
            guard target.count > 0, from >= 0 else { return nil }
            var index = from
            while index + target.count <= chars.count {
                if Array(chars[index..<(index + target.count)]) == target { return index }
                index += 1
            }
            return nil
        }

        /// `enum AppLanguage` 的各例（语言列表**不写死**）。
        static func languageCases(_ source: String) -> [String] {
            let masked = Array(SwiftSource(source).uncommentedText)
            guard let enumRange = source.range(of: "enum AppLanguage") else { return [] }
            let start = source.distance(from: source.startIndex, to: enumRange.upperBound)
            guard let brace = firstIndex(of: "{", in: masked, from: start) else { return [] }
            guard let close = LScan.bracket(masked, from: brace, open: "{", close: "}") else { return [] }
            let body = String(masked[(brace + 1)..<close])
            var cases: [String] = []
            for line in body.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case ") else { continue }
                let rest = trimmed.dropFirst("case ".count)
                let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty { cases.append(String(name)) }
            }
            return cases
        }

        /// 每个键**实际写了哪些语言**（按顶层逗号切 ⇒ 模板字符串里的 `.x:` 不会被当语言键）。
        static func entryLanguages(_ source: String) -> [String: [String]] {
            let chars = Array(source)
            guard let anchorRange = source.range(of: anchor) else { return [:] }
            let anchorEnd = source.distance(from: source.startIndex, to: anchorRange.upperBound)
            guard let equals = firstIndex(of: "= [", in: chars, from: anchorEnd),
                  let open = firstIndex(of: "[", in: chars, from: equals + 2),
                  let close = LScan.bracket(chars, from: open) else { return [:] }
            let bodyChars = Array(chars[(open + 1)..<close])
            let masked = Array(SwiftSource(String(bodyChars)).uncommentedText)
            var out: [String: [String]] = [:]
            var index = 0
            while index < masked.count {
                guard masked[index] == "." else { index += 1; continue }
                var cursor = index + 1
                var key = ""
                while cursor < masked.count, masked[cursor].isLetter || masked[cursor].isNumber || masked[cursor] == "_" {
                    key.append(masked[cursor])
                    cursor += 1
                }
                while cursor < masked.count, masked[cursor] == " " || masked[cursor] == "\t" { cursor += 1 }
                guard !key.isEmpty, cursor < masked.count, masked[cursor] == ":" else { index += 1; continue }
                cursor += 1
                while cursor < masked.count, masked[cursor] == " " || masked[cursor] == "\t" { cursor += 1 }
                guard cursor < masked.count, masked[cursor] == "[" else { index += 1; continue }
                guard let innerClose = LScan.bracket(masked, from: cursor) else { index += 1; continue }
                let innerMasked = String(masked[(cursor + 1)..<innerClose])
                var languages: [String] = []
                for piece in LScan.splitTopLevel(innerMasked) {
                    let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix(".") || trimmed.hasPrefix("AppLanguage.") else { continue }
                    let tail = trimmed.hasPrefix("AppLanguage.") ? trimmed.dropFirst("AppLanguage.".count) : trimmed.dropFirst()
                    let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    let after = tail.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, after.hasPrefix(":"), !languages.contains(String(name)) {
                        languages.append(String(name))
                    }
                }
                out[key] = languages
                index = innerClose + 1
            }
            return out
        }

        // MARK: - 调用点

        static let callPattern = #"\bL\(\s*\.(\w+)\s*([,)])"#

        static func callSites(_ files: [String: String], face: [String]) -> [Site] {
            guard let regex = LScan.regex(callPattern) else { return [] }
            var sites: [Site] = []
            for relative in files.keys.sorted() where face.contains(where: {
                relative == $0 || relative.hasPrefix($0 + "/")
            }) {
                let raw = files[relative] ?? ""
                let masked = SwiftSource(raw).uncommentedText
                let maskedChars = Array(masked)
                let ns = masked as NSString
                for match in regex.matches(in: masked, range: NSRange(location: 0, length: ns.length)) {
                    let offset = charOffset(masked, utf16Offset: match.range.location)
                    guard let open = firstIndex(of: "(", in: maskedChars, from: offset),
                          let close = LScan.bracket(maskedChars, from: open, open: "(", close: ")"),
                          close >= open else { continue }
                    let inside = String(maskedChars[(open + 1)..<close])
                    let parts = LScan.splitTopLevel(inside)
                    var args: [String] = []
                    for part in parts.dropFirst() {
                        var text = part.trimmingCharacters(in: .whitespaces)
                        if text.hasPrefix("await ") { text = String(text.dropFirst("await ".count)).trimmingCharacters(in: .whitespaces) }
                        if !text.isEmpty { args.append(text) }
                    }
                    sites.append(Site(file: relative,
                                      line: LScan.line(of: raw, atUTF16: match.range.location),
                                      key: ns.substring(with: match.range(at: 1)),
                                      args: args))
                }
            }
            return sites
        }

        // MARK: - 实参类型

        static let numberPatterns = [
            #"^-?\d+(?:\.\d+)?$"#,
            #"^\(-?\d+\)$"#,
            #"^(?:Int|Int32|Int64|UInt|UInt8|UInt16|UInt32|UInt64|Double|Float|CGFloat)\("#,
            #"\.(?:count|rowCount|pageCount|columnCount|statementCount|exitCode|batchCount)\s*$"#,
            #"\.next\(\)\s*$"#,
            #"\?\?\s*-?\d+(?:\.\d+)?$"#,
            #"[+\-]\s*\d+\s*\)?$"#,
            #"\.timeIntervalSince\("#,
            #"\.utf8\.count\s*$"#,
        ]
        static let foundationMemberKinds: [String: String] = [
            "localizedDescription": "text", "lastPathComponent": "text", "path": "text",
            "identifier": "text", "uuidString": "text", "absoluteString": "text", "debugDescription": "text",
        ]
        static let foundationFunctionKinds: [String: String] = [
            "String": "text", "Substring": "text", "Character": "text", "L": "text",
            "min": "number", "max": "number", "abs": "number",
        ]

        struct Resolver {
            var functions: [String: Set<String>] = [:]
            var members: [String: Set<String>] = [:]

            init(files: [String: String], face: [String]) {
                guard let funcRegex = LScan.regex(#"\bfunc\s+(\w+)"#),
                      let memberRegex = LScan.regex(#"\b(?:let|var)\s+(\w+)\s*:\s*([^=\n,)\]\{]+)"#) else { return }
                for relative in files.keys.sorted() where face.contains(where: {
                    relative == $0 || relative.hasPrefix($0 + "/")
                }) {
                    let source = SwiftSource(files[relative] ?? "").uncommentedText
                    let chars = Array(source)
                    let ns = source as NSString
                    for match in funcRegex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                        // 只收类型级 / 全局函数（缩进 0 或 4）：嵌套函数同名会把整仓索引污染成错的。
                        let offset = LocalizationFormatArgumentTests.Gate.charOffset(source, utf16Offset: match.range.location)
                        var lineStart = offset
                        while lineStart > 0 && chars[lineStart - 1] != "\n" { lineStart -= 1 }
                        var indent = 0
                        var probe = lineStart
                        while probe < offset && chars[probe] == " " { indent += 1; probe += 1 }
                        if indent >= 8 { continue }
                        guard let open = LocalizationFormatArgumentTests.Gate.firstIndex(of: "(", in: chars, from: offset),
                              let close = LScan.bracket(chars, from: open, open: "(", close: ")") else { continue }
                        let tail = String(chars[min(close + 1, chars.count)..<min(close + 201, chars.count)])
                        guard let arrow = LScan.regex(#"^\s*(?:async\s+)?(?:throws\s+)?->\s*([^\{;\n]+)"#),
                              let arrowMatch = arrow.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)) else { continue }
                        let type = (tail as NSString).substring(with: arrowMatch.range(at: 1))
                        let name = ns.substring(with: match.range(at: 1))
                        functions[name, default: []].insert(kindOfType(type))
                    }
                    for match in memberRegex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                        let name = ns.substring(with: match.range(at: 1))
                        let type = ns.substring(with: match.range(at: 2))
                        members[name, default: []].insert(kindOfType(type))
                    }
                }
            }

            func resolve(_ text: String) -> String {
                if let call = LScan.regex(#"^([A-Za-z_][\w.]*)\s*\("#),
                   let match = call.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                    let head = (text as NSString).substring(with: match.range(at: 1))
                        .split(separator: ".").last.map(String.init) ?? ""
                    if let kind = foundationFunctionKinds[head] { return kind }
                    return pickKind(functions[head] ?? [])
                }
                if LScan.regex(#"^[\w.?]+$"#)?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil,
                   text.contains(".") {
                    let member = text.replacingOccurrences(of: "?", with: "").split(separator: ".").last.map(String.init) ?? ""
                    if let kind = foundationMemberKinds[member] { return kind }
                    return pickKind(members[member] ?? [])
                }
                return "unknown"
            }
        }

        static func kindOfType(_ type: String) -> String {
            let text = type.trimmingCharacters(in: .whitespaces)
            if LScan.regex(#"^(?:String|Substring|NSString|Character|UUID|URL|Date)\b"#)?
                .firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                return "text"
            }
            if LScan.regex(#"^(?:Int|Int8|Int16|Int32|Int64|UInt|UInt8|UInt16|UInt32|UInt64|Double|Float|CGFloat|TimeInterval)\b"#)?
                .firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                return "number"
            }
            return "unknown"
        }

        /// 声明冲突时保守返回 unknown（宁可登记，不可错报）。
        static func pickKind(_ kinds: Set<String>) -> String {
            let decisive = kinds.intersection(["text", "number"])
            return decisive.count == 1 ? decisive.first! : "unknown"
        }

        static func classify(_ argument: String, resolver: Resolver) -> String {
            let text = argument.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("\"") { return "text" }
            for pattern in numberPatterns {
                if let regex = LScan.regex(pattern),
                   regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                    return "number"
                }
            }
            let resolved = resolver.resolve(text)
            return resolved == "unknown" ? "unknown" : resolved
        }

        static func shape(of argument: String) -> String {
            var text = argument.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("await ") { text = String(text.dropFirst("await ".count)).trimmingCharacters(in: .whitespaces) }
            let ns = text as NSString
            if let call = LScan.regex(#"^([A-Za-z_][\w.]*)\s*\("#),
               let match = call.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1)) + "(…)"
            }
            if LScan.regex(#"^[\w.]+$"#)?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil {
                return text.contains(".") ? "." + (text.split(separator: ".").last.map(String.init) ?? "") : "<\(text)>"
            }
            if text.hasPrefix("(") || text.hasPrefix("[") || text.hasPrefix("{") {
                let head = text.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
                return String(head.prefix(24)).isEmpty ? "?" : String(head.prefix(24))
            }
            let squashed = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
            return String(squashed.prefix(32))
        }

        // MARK: - 判定

        static func evaluate(files: [String: String],
                             packageText: String,
                             ledger: [String: Any]) -> Evaluation {
            var result = Evaluation()
            let tableSource = files[tableRel] ?? ""
            let templates = table(tableSource)
            result.tableKeys = templates.count
            let languages = languageCases(tableSource)
            result.languages = languages
            let written = entryLanguages(tableSource)

            // F：扫描面
            let derived = ProductionFace.derive(packageText)
            let exempt = Set(((ledger["faceExempt"] as? [[String: Any]]) ?? []).map { LRepo.string($0["root"]) })
            let scanFace = derived.face.filter { !exempt.contains($0) }
            result.face = scanFace
            for root in exempt where !derived.face.contains(root) {
                result.errors.append("❌ [F] 面豁免陈旧：\(ledgerRel) 的 faceExempt 登记了 `\(root)`，"
                                     + "但 \(packageRel) 里没有这个生产 root")
            }
            for name in derived.undeclared {
                result.errors.append("❌ [F] 生产 target `\(name)` 既没声明 `path:` 也没声明 `sources:`")
            }
            if scanFace.isEmpty { result.errors.append("❌ [F] 扫描面为空 —— 空跑不是通过") }
            for root in scanFace where !LRepo.exists(root) {
                result.errors.append("❌ [F] 扫描面里的根 `\(root)` 在盘上不存在")
            }
            for root in scanFace where files.keys.contains(where: { $0.hasPrefix(root + "/") }) == false && LRepo.exists(root) {
                // 夹具里可能只给了一部分文件；真仓库的这条由「一个 L(...) 都没扫到」兜底。
                continue
            }

            // G：语言列表 + 每个键覆盖全部语言
            if languages.count < 2 {
                result.errors.append("❌ [G] 从 \(tableRel) 的 `enum AppLanguage` 只解析出 \(languages.count) 个语言")
            }
            for (key, langs) in written.sorted(by: { $0.key < $1.key }) {
                let missing = languages.filter { !langs.contains($0) }
                if !missing.isEmpty {
                    result.errors.append("❌ [G] 语言表键 `\(key)` 缺语言 \(missing) —— 那种语言下会回落到别的模板")
                }
                let extra = langs.filter { !languages.contains($0) }
                if !extra.isEmpty {
                    result.errors.append("❌ [G] 语言表键 `\(key)` 有 `enum AppLanguage` 之外的语言 \(extra)")
                }
            }

            let sites = callSites(files, face: scanFace)
            result.totalSites = sites.count
            if sites.isEmpty { result.errors.append("❌ 一个 `L(...)` 调用点都没扫到 —— 空跑不是通过") }

            var specKeys: [String: [String: [String]]] = [:]
            for (key, templatesByLanguage) in templates {
                var byLanguage: [String: [String]] = [:]
                for (language, template) in templatesByLanguage { byLanguage[language] = specifiers(template) }
                if byLanguage.values.contains(where: { !$0.isEmpty }) { specKeys[key] = byLanguage }
            }
            result.specKeys = specKeys.count
            if specKeys.isEmpty { result.errors.append("❌ 语言表里一个带占位符的键都没解析到 —— 判据取不到输入") }

            var shapes: [String: [String: Any]] = [:]
            for item in (ledger["shapes"] as? [[String: Any]]) ?? [] {
                shapes[LRepo.string(item["shape"])] = item
            }
            var exceptions: Set<String> = []
            for item in (ledger["exceptions"] as? [[String: Any]]) ?? [] {
                exceptions.insert("\(LRepo.string(item["judgement"]))|\(LRepo.string(item["key"]))|\(LRepo.string(item["site"]))")
            }
            result.unknownBudget = LRepo.int(ledger["unknownBudget"])

            let resolver = Resolver(files: files, face: scanFace)
            var hits: [String: Int] = [:]
            var seenExceptions: Set<String> = []

            func flagged(_ judgement: String, _ key: String, _ file: String, _ line: Int, _ message: String) {
                let site = "\(file):\(line)"
                let token = "\(judgement)|\(key)|\(site)"
                seenExceptions.insert(token)
                if !exceptions.contains(token) {
                    result.errors.append("❌ [\(judgement)] \(site)  L(.\(key))  \(message)")
                }
            }

            for site in sites {
                guard let specs = specKeys[site.key] else { continue }
                result.checked += 1
                var kinds: [String] = []
                for argument in site.args {
                    var kind = classify(argument, resolver: resolver)
                    if kind == "unknown" {
                        let shape = shape(of: argument)
                        result.shapeHistogram[shape, default: 0] += 1
                        guard let entry = shapes[shape] else {
                            result.unknownTotal += 1
                            result.unknownUnregistered += 1
                            result.errors.append("❌ [C] \(site.file):\(site.line)  L(.\(site.key))  未登记的类型不明实参 "
                                                 + "「\(argument)」⇒ 形状 `\(shape)` 不在 \(ledgerRel) 的 shapes 里")
                            kinds.append("unknown")
                            continue
                        }
                        hits[shape, default: 0] += 1
                        let declared = LRepo.string(entry["kind"])
                        if !["text", "number", "unverified"].contains(declared) {
                            result.errors.append("❌ [E] 台账形状 `\(shape)` 的 kind 非法：\(declared)")
                            kind = "unknown"
                            result.unknownTotal += 1
                            result.unknownUnverified += 1
                        } else if declared == "unverified" {
                            kind = "unknown"
                            result.unknownTotal += 1
                            result.unknownUnverified += 1
                        } else {
                            kind = declared
                            result.typedByEvidence += 1
                        }
                    }
                    kinds.append(kind)
                }
                for (language, slots) in specs.sorted(by: { $0.key < $1.key }) {
                    if site.args.count != slots.count {
                        flagged("B", site.key, site.file, site.line,
                                "实参 \(site.args.count) 个，而 \(language) 模板有 \(slots.count) 个占位符"
                                + "（\(slots)）—— 界面会印出字面量 `%@` 之类的模板原文")
                    }
                }
                for (index, kind) in kinds.enumerated() where kind != "unknown" {
                    for (language, slots) in specs.sorted(by: { $0.key < $1.key }) {
                        guard index < slots.count else { continue }
                        let conversion = slots[index]
                        if conversion == "?" { continue }
                        if kind == "number", conversion == "@" {
                            flagged("A", site.key, site.file, site.line,
                                    "\(language) 模板第 \(index + 1) 位是 `%@`，实参是数字 ⇒ 界面印 `(null)`")
                        }
                        if kind == "text", conversion == "*" {
                            flagged("A′", site.key, site.file, site.line,
                                    "\(language) 模板第 \(index + 1) 位是 `*`（宽度/精度取自实参），实参是字符串")
                        }
                        if kind == "text", "diouxXfFeEgG".contains(conversion) {
                            flagged("A′", site.key, site.file, site.line,
                                    "\(language) 模板第 \(index + 1) 位是 `%\(conversion)`，实参是字符串 ⇒ 数字槽收字符串")
                        }
                    }
                }
            }

            // D：棘轮
            let liveShapes = Set(hits.filter { $0.value > 0 }.keys)
            for (name, entry) in shapes.sorted(by: { $0.key < $1.key }) {
                let count = hits[name] ?? 0
                let maxSites = LRepo.int(entry["maxSites"])
                if count > maxSites {
                    result.errors.append("❌ [D] 形状 `\(name)` 命中 \(count) 处，超登记上限 \(maxSites)")
                }
                if count < maxSites {
                    result.notes.append("ℹ️ 形状 `\(name)` 命中从 \(maxSites) 降到 \(count)（好事）")
                }
            }
            if result.unknownTotal > result.unknownBudget {
                result.errors.append("❌ [D] 无据的类型不明实参共 \(result.unknownTotal) 处，超预算 \(result.unknownBudget)"
                                     + "（未登记 \(result.unknownUnregistered) + 登记为 unverified \(result.unknownUnverified)）")
            }
            // E：台账双向对账
            for item in (ledger["exceptions"] as? [[String: Any]]) ?? [] {
                let token = "\(LRepo.string(item["judgement"]))|\(LRepo.string(item["key"]))|\(LRepo.string(item["site"]))"
                if !seenExceptions.contains(token) {
                    result.errors.append("❌ [E] 例外陈旧：台账登记了 [\(LRepo.string(item["judgement"]))] "
                                         + "\(LRepo.string(item["site"])) L(.\(LRepo.string(item["key"])))，但它现在不违规")
                }
            }
            for name in shapes.keys where !liveShapes.contains(name) {
                result.errors.append("❌ [E] 形状陈旧：台账登记的形状 `\(name)` 现在一处都不命中 —— 请删除")
            }
            return result
        }
    }

    // MARK: - 真仓库判据

    func testPlaceholderArgumentReconciliationPasses() throws {
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles(["App", "CLI", "Core", "Platform", "Plugins", "Tools"]) {
            files[relative] = try LRepo.text(relative)
        }
        // 语言表与 Package.swift 也要在面里（evaluate 从 files 里取表）。
        files[Gate.tableRel] = try LRepo.text(Gate.tableRel)
        let result = Gate.evaluate(files: files,
                                   packageText: try LRepo.text(ProductionFace.package),
                                   ledger: try LRepo.json(Gate.ledgerRel))
        XCTAssertTrue(result.errors.isEmpty,
                      "占位符 ↔ 实参对账报红 \(result.errors.count) 项：\n" + result.errors.joined(separator: "\n"))
        XCTAssertGreaterThan(result.specKeys, 0, "带占位符的键为 0 —— 判据取不到输入")
        XCTAssertGreaterThan(result.totalSites, 0, "调用点为 0 —— 判据取不到输入")
        print("📏 占位符对账：带占位符键 \(result.specKeys) / 调用点 \(result.totalSites)（受检 \(result.checked)）；"
              + "无据 \(result.unknownTotal)（预算 \(result.unknownBudget)）；有据登记 \(result.typedByEvidence) 处；"
              + "语言 \(result.languages)")
    }

    // MARK: - 反例（原脚本 16 例自检的等价物）

    private static let fixtureTable = """
    import Foundation

    public enum AppLanguage: String, CaseIterable {
        case simplifiedChinese = "zh-Hans"
        case english = "en"
    }

    public enum LocalizedStrings {
        static let table: [LKey: [AppLanguage: String]] = [
            .greet: [.simplifiedChinese: "你好 %@，共 %d 条", .english: "Hi %@, %d rows"],
            .rows: [.simplifiedChinese: "共 %d 行", .english: "%d rows"],
            .plain: [.simplifiedChinese: "纯文本", .english: "plain"],
            .label: [.simplifiedChinese: "当前版本：%@", .english: "Current edition: %@"],
            .pos: [.simplifiedChinese: "%2$@ 与 %1$d", .english: "%2$@ and %1$d"],
            .star: [.simplifiedChinese: "%-*d 行", .english: "%-*d rows"],
        ]
    }
    """

    private static let fixturePackage = """
    // swift-tools-version: 5.10
    import PackageDescription

    let package = Package(
        name: "Fixture",
        targets: [
            .target(name: "FixtureCore", path: ".", sources: ["Core"]),
            .executableTarget(name: "FixtureApp", path: ".", sources: ["App"]),
            .testTarget(name: "FixtureTests", path: "Tests"),
        ]
    )
    """

    private static let fixtureOK = """
    import Foundation

    func render(name: String, count: Int) -> String {
        let a = L(.greet, name, count)
        let b = L(.rows, count)
        let c = L(.plain)
        let d = L(.label)
        let e = items.map { L(.rows, $0) }
        return a + b + c + d
    }
    """

    private static let fixtureLedger: [String: Any] = [
        "unknownBudget": 4,
        "shapes": [
            ["shape": "<name>", "kind": "text", "maxSites": 1, "reason": "夹具：裸标识符 `name`"],
            ["shape": "<count>", "kind": "number", "maxSites": 2, "reason": "夹具：裸标识符 `count`"],
            ["shape": "$0", "kind": "number", "maxSites": 1, "reason": "夹具：闭包形参"],
        ],
        "exceptions": [
            ["judgement": "B", "key": "label", "site": "App/Fixture.swift:7",
             "reason": "夹具：标签与值分开渲染，模板本不该带 %@（真仓库同款见 AboutLicenseSheet）"],
        ],
    ]

    private func evaluateFixture(_ source: String,
                                 table: String = fixtureTable,
                                 ledger: [String: Any]? = nil,
                                 package: String = fixturePackage,
                                 extra: [String: String] = [:]) -> Gate.Evaluation {
        var files = extra
        files["Core/Localization.swift"] = table
        files["App/Fixture.swift"] = source
        return Gate.evaluate(files: files, packageText: package, ledger: ledger ?? Self.fixtureLedger)
    }

    func testFixtureGreenControl() {
        let result = evaluateFixture(Self.fixtureOK)
        XCTAssertTrue(result.errors.isEmpty, "对照组必须绿：\(result.errors)")
    }

    func testNumberArgumentIntoObjectSlotIsRed() {
        let result = evaluateFixture(Self.fixtureOK.replacingOccurrences(
            of: "L(.greet, name, count)", with: "L(.greet, items.count, count)"))
        XCTAssertTrue(result.errors.contains { $0.hasPrefix("❌ [A]") }, "数字进 %@ 槽必须判红：\(result.errors)")
    }

    func testStringArgumentIntoNumberSlotIsRed() {
        let result = evaluateFixture(Self.fixtureOK.replacingOccurrences(
            of: "L(.rows, count)", with: "L(.rows, \"x\")"))
        XCTAssertTrue(result.errors.contains { $0.hasPrefix("❌ [A′]") }, "字符串进 %d 槽必须判红：\(result.errors)")
    }

    func testArgumentCountMismatchIsRed() {
        let result = evaluateFixture(Self.fixtureOK.replacingOccurrences(
            of: "L(.plain)", with: "L(.rows)"))
        XCTAssertTrue(result.errors.contains { $0.hasPrefix("❌ [B]") }, "实参数 ≠ 占位符数必须判红：\(result.errors)")
    }

    func testUnregisteredUnknownShapeIsRed() {
        let result = evaluateFixture(Self.fixtureOK.replacingOccurrences(
            of: "L(.greet, name, count)", with: "L(.greet, mystery, count)"))
        XCTAssertTrue(result.errors.contains { $0.hasPrefix("❌ [C]") }, "未登记的类型不明实参必须判红：\(result.errors)")
    }

    func testShapeRatchetAndBudgetAreRed() {
        let overSites = evaluateFixture(Self.fixtureOK + "let f = items.map { L(.rows, $0) }\n")
        XCTAssertTrue(overSites.errors.contains { $0.contains("[D] 形状 `<count>`") || $0.contains("[D] 形状 `$0`") },
                      "形状超上限必须判红：\(overSites.errors)")

        var tight = Self.fixtureLedger
        tight["unknownBudget"] = 0
        tight["shapes"] = [
            ["shape": "<name>", "kind": "text", "maxSites": 1, "reason": "夹具"],
            ["shape": "<count>", "kind": "number", "maxSites": 2, "reason": "夹具"],
            ["shape": "<mystery>", "kind": "unverified", "maxSites": 1, "reason": "夹具：无出处 ⇒ 仍占预算"],
        ]
        let overBudget = evaluateFixture(
            Self.fixtureOK.replacingOccurrences(of: "L(.greet, name, count)", with: "L(.greet, mystery, count)"),
            ledger: tight)
        XCTAssertTrue(overBudget.errors.contains { $0.contains("[D] 无据") }, "超预算必须判红：\(overBudget.errors)")
    }

    func testStaleExceptionIsRed() {
        var stale = Self.fixtureLedger
        stale["exceptions"] = [["judgement": "A", "key": "greet", "site": "App/Fixture.swift:99", "reason": "夹具：故意陈旧"]]
        let result = evaluateFixture(Self.fixtureOK, ledger: stale)
        XCTAssertTrue(result.errors.contains { $0.contains("例外陈旧") }, "陈旧例外必须判红：\(result.errors)")
    }

    func testEmptyRunIsNotAPass() {
        let empty = Self.fixtureTable
            .replacingOccurrences(of: "%2$@ 与 %1$d", with: "无占位符")
            .replacingOccurrences(of: "%2$@ and %1$d", with: "no slots")
            .replacingOccurrences(of: "%-*d 行", with: "只有文本")
            .replacingOccurrences(of: "%-*d rows", with: "text only")
            .replacingOccurrences(of: "%@", with: "")
            .replacingOccurrences(of: "%d", with: "")
        let result = evaluateFixture(Self.fixtureOK, table: empty)
        XCTAssertTrue(result.errors.contains { $0.contains("一个带占位符的键都没解析到") },
                      "没有占位符 = 判据取不到输入：\(result.errors)")
    }

    func testPositionalAndStarSlots() {
        let positionalOK = evaluateFixture(Self.fixtureOK + "let f = L(.pos, 42, \"文字\")\n")
        XCTAssertTrue(positionalOK.errors.isEmpty, "`%2$@ 与 %1$d` 的正确调用应绿：\(positionalOK.errors)")

        let positionalBad = evaluateFixture(Self.fixtureOK + "let f = L(.pos, \"文字\", 42)\n")
        XCTAssertTrue(positionalBad.errors.contains { $0.hasPrefix("❌ [A") },
                      "位置参数错序必须判红：\(positionalBad.errors)")

        let star = evaluateFixture(Self.fixtureOK + "let f = L(.star, 3, 42)\n")
        XCTAssertTrue(star.errors.isEmpty, "`*` 宽度各占一个实参槽：\(star.errors)")
    }

    func testCommentInsideArgumentsDoesNotSplitThem() {
        let result = evaluateFixture(Self.fixtureOK.replacingOccurrences(
            of: "L(.rows, count)", with: "L(.rows, /* 一,二 */ count)"))
        XCTAssertTrue(result.errors.isEmpty, "实参里的注释不许带进实参：\(result.errors)")
    }

    func testFaceDriftInPackageIsRed() {
        let extraPackage = Self.fixturePackage.replacingOccurrences(
            of: #"        .testTarget(name: "FixtureTests", path: "Tests"),"#,
            with: #"        .testTarget(name: "FixtureTests", path: "Tests"),"# + "\n"
                + #"        .target(name: "FixturePlatform", path: "Platform"),"#)
        let result = evaluateFixture(Self.fixtureOK, package: extraPackage,
                                     extra: ["Platform/Probe.swift": "import Foundation\n\nlet p = L(.greet, 1, 2)\n"])
        XCTAssertTrue(result.errors.contains { $0.contains("Platform/Probe.swift") },
                      "新生产 root 未进面 ⇒ 那里写的违规要判红：\(result.errors)")
    }

    func testMissingLanguageCoverageIsRed() {
        let table = Self.fixtureTable.replacingOccurrences(
            of: #".rows: [.simplifiedChinese: "共 %d 行", .english: "%d rows"],"#,
            with: #".rows: [.simplifiedChinese: "共 %d 行"],"#)
        let result = evaluateFixture(Self.fixtureOK, table: table)
        XCTAssertTrue(result.errors.contains { $0.contains("[G]") && $0.contains("rows") },
                      "键缺一种语言必须判红：\(result.errors)")
    }
}
