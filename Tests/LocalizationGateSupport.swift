import Foundation
import XCTest

// ============================================================================
// 本地化 / 文案族判据的共用基础设施（2026-11-09 · 判据搬家第一批）
//
// 这 8 条判据原先各是一份 Python 门禁（`Scripts/check-*.py`）。搬进 `swift test`
// 的理由与口径见各测试文件头部；本文件只放**共用**的那几件：
//
//   · `LRepo`       仓根 / 读文件 / 扫面（由 `#filePath` 推，不依赖 cwd）
//   · `SwiftSource` Swift 词法级别的「注释 / 字符串字面量」掩码（等长抹白、换行保留）
//   · 括号配平 / 顶层逗号切分 / 行号等小工具（Python 侧 `match_bracket` 等的等价物）
//   · `LanguageTable` 语言表条目解析（方括号配平 + 两个语言槽位）
//
// 纪律：**判定物等长抹白**（换行保留 ⇒ 行号不动），否则「注释里写了一句反例」会被判红。
// ============================================================================

enum LRepo {

    /// 工程根（`Tests/<本文件>` 的上两级）。
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // Tests/
        .deletingLastPathComponent()      // <root>/

    static func path(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    static func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative).path)
    }

    static func text(_ relative: String) throws -> String {
        try String(contentsOf: path(relative), encoding: .utf8)
    }

    static func textIfExists(_ relative: String) -> String? {
        try? text(relative)
    }

    /// 仓库相对路径下的全部 `.swift`（升序；与 Python 的 `rglob("*.swift")` 同面）。
    static func swiftFiles(_ roots: [String]) -> [String] {
        var found: [String] = []
        for relative in roots where exists(relative) {
            let base = path(relative)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(relativePath(of: url))
            }
        }
        return Array(Set(found)).sorted()
    }

    static func relativePath(of url: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        let full = url.standardizedFileURL.path
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
    }

    /// 读一份 JSON 对象（台账）。
    static func json(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: path(relative))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LRepo", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(relative) 不是 JSON 对象"])
        }
        return object
    }

    /// 台账里的整数字段（缺省 = 0）。
    static func int(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String { return Int(value) ?? 0 }
        return 0
    }

    static func string(_ any: Any?) -> String {
        (any as? String) ?? ""
    }
}

// ============================================================================
// Swift 词法掩码
// ============================================================================

struct SwiftSource {

    let chars: [Character]
    /// 代码面：注释 + 字符串字面量正文抹成空格（换行保留）。单行串的 `\( … )` 插值体**仍是代码**
    /// （与 `check-effective-language.py` / `check-literal-language.py` 的 `masked_chars` 同口径）；
    /// raw 串（`#"…"#`）的插值**不建模**，整段按字符串抹掉（抹多不抹少，如实登记的边界）。
    let code: [Character]
    /// 只剥注释，字符串正文原样保留（`check-format-arguments.py` 的 `mask_comments`）。
    let uncommented: [Character]
    /// 字符串字面量跨度（含开/闭引号；raw 串含 `#` 前缀）。
    let literals: [(start: Int, end: Int)]

    init(_ text: String) {
        let source = Array(text)
        var code = source
        var plain = source
        var spans: [(start: Int, end: Int)] = []

        func blank(_ buffer: inout [Character], _ from: Int, _ to: Int) {
            guard from < to else { return }
            for index in from..<min(to, buffer.count) where buffer[index] != "\n" {
                buffer[index] = " "
            }
        }

        let count = source.count
        var index = 0
        while index < count {
            // 行注释
            if source[index] == "/", index + 1 < count, source[index + 1] == "/" {
                var stop = index
                while stop < count && source[stop] != "\n" { stop += 1 }
                blank(&code, index, stop)
                blank(&plain, index, stop)
                index = stop
                continue
            }
            // 块注释（可嵌套）
            if source[index] == "/", index + 1 < count, source[index + 1] == "*" {
                var depth = 1
                var cursor = index + 2
                while cursor < count && depth > 0 {
                    if source[cursor] == "/", cursor + 1 < count, source[cursor + 1] == "*" {
                        depth += 1
                        cursor += 2
                    } else if source[cursor] == "*", cursor + 1 < count, source[cursor + 1] == "/" {
                        depth -= 1
                        cursor += 2
                    } else {
                        cursor += 1
                    }
                }
                blank(&code, index, cursor)
                blank(&plain, index, cursor)
                index = cursor
                continue
            }
            // 字符串（含 raw 前缀 `#`）
            var hashes = 0
            var quote = index
            while quote < count && source[quote] == "#" { hashes += 1; quote += 1 }
            if quote < count, source[quote] == "\"" {
                let start = index
                let triple = quote + 2 < count && source[quote + 1] == "\"" && source[quote + 2] == "\""
                let opener = triple ? 3 : 1
                let terminator = Array(String(repeating: "\"", count: opener) + String(repeating: "#", count: hashes))
                blank(&code, start, quote + opener)
                var cursor = quote + opener
                while cursor < count {
                    if SwiftSource.matches(source, at: cursor, terminator) {
                        blank(&code, cursor, cursor + terminator.count)
                        cursor += terminator.count
                        break
                    }
                    if hashes == 0, source[cursor] == "\\" {
                        if cursor + 1 < count, source[cursor + 1] == "(" {
                            blank(&code, cursor, cursor + 2)
                            cursor = SwiftSource.skipInterpolation(source, from: cursor + 2)
                            continue
                        }
                        blank(&code, cursor, cursor + 2)
                        cursor += 2
                        continue
                    }
                    if source[cursor] != "\n" { code[cursor] = " " }
                    cursor += 1
                }
                spans.append((start, min(cursor, count)))
                index = max(cursor, index + 1)
                continue
            }
            index += 1
        }

        self.chars = source
        self.code = code
        self.uncommented = plain
        self.literals = spans
    }

    var codeText: String { String(code) }
    var uncommentedText: String { String(uncommented) }

    /// 跳过 `\( … )` 的插值体（`from` = 体的第一个字符），返回闭括号之后的下标。体内按代码走。
    static func skipInterpolation(_ source: [Character], from start: Int) -> Int {
        var depth = 1
        var index = start
        while index < source.count {
            if source[index] == "\"" {
                var cursor = index + 1
                while cursor < source.count {
                    if source[cursor] == "\\" { cursor += 2; continue }
                    if source[cursor] == "\"" { cursor += 1; break }
                    cursor += 1
                }
                index = cursor
                continue
            }
            if source[index] == "(" { depth += 1 }
            if source[index] == ")" {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return index
    }

    private static func matches(_ source: [Character], at index: Int, _ needle: [Character]) -> Bool {
        guard index + needle.count <= source.count else { return false }
        for offset in 0..<needle.count where source[index + offset] != needle[offset] { return false }
        return true
    }
}

// ============================================================================
// 小工具
// ============================================================================

enum LScan {

    static func isHan(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return character.unicodeScalars.contains { isHanScalar($0) }
        }
        return isHanScalar(scalar)
    }

    static func isHanScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
    }

    static func hasHan(_ text: String) -> Bool {
        text.contains(where: isHan)
    }

    /// 行号（1-based）：`chars[0..<offset]` 里的换行数 + 1。
    static func line(of chars: [Character], at offset: Int) -> Int {
        var line = 1
        for index in 0..<min(offset, chars.count) where chars[index] == "\n" { line += 1 }
        return line
    }

    static func line(of text: String, atUTF16 offset: Int) -> Int {
        let ns = text as NSString
        guard offset > 0 else { return 1 }
        let prefix = ns.substring(to: min(offset, ns.length))
        return prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// `chars[index]` 必须是 `open`，返回配平的 `close` 下标（字符串字面量里的括号不算）。
    static func firstIndex(of character: Character, in chars: [Character], from: Int) -> Int? {
        var index = max(from, 0)
        while index < chars.count {
            if chars[index] == character { return index }
            index += 1
        }
        return nil
    }

    static func bracket(_ chars: [Character], from index: Int, open: Character = "[", close: Character = "]") -> Int? {
        var depth = 0
        var cursor = index
        var inString = false
        while cursor < chars.count {
            let char = chars[cursor]
            if inString {
                if char == "\\" { cursor += 2; continue }
                if char == "\"" { inString = false }
                cursor += 1
                continue
            }
            if char == "\"" { inString = true }
            else if char == open { depth += 1 }
            else if char == close {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    /// 按**顶层**逗号切分（括号 / 方括号 / 字符串里的逗号不算分隔符）。
    static func splitTopLevel(_ text: String) -> [String] {
        var pieces: [String] = []
        var buffer = ""
        var depth = 0
        var inString = false
        var escaped = false
        for character in text {
            if escaped { buffer.append(character); escaped = false; continue }
            if character == "\\" { buffer.append(character); escaped = true; continue }
            if character == "\"" {
                inString.toggle()
                buffer.append(character)
                continue
            }
            if !inString {
                if "([{".contains(character) { depth += 1 }
                else if ")]}".contains(character) { depth -= 1 }
                else if character == ",", depth == 0 {
                    pieces.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    buffer = ""
                    continue
                }
            }
            buffer.append(character)
        }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces.filter { !$0.isEmpty }
    }

    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }
}

// ============================================================================
// 语言表（`Core/Localization.swift` 的 `LocalizedStrings.table`）
// ============================================================================

struct LocalizedEntry {
    let key: String
    let line: Int
    let zh: String
    let en: String

    func value(_ language: String) -> String { language == "english" ? en : zh }
}

enum LanguageTable {

    static let file = "Core/Localization.swift"
    static let slots = ("simplifiedChinese", "english")

    /// 解析结果：条目 / 解析不出的候选（逐条点名）/ 全文件槽位命中数。
    struct Parsed {
        var entries: [LocalizedEntry] = []
        var unparsed: [String] = []
        var slotCounts: [String: Int] = [:]
    }

    /// 解析语言表（**手写扫描**：条目起点 `/^\s*\.键\s*:\s*\[/`，或紧跟在 `,` 之后 —— 同类条目的
    /// 第二条也认；槽位名 `.simplifiedChinese:` / `.english:` 排除在外）。
    ///
    /// 为什么不用一条大正则：真表 2000+ 条、7000+ 行，带零宽 lookbehind 的正则在这里是**平方级**
    /// 开销（实测单次解析 100 秒）。手写扫描是线性的，且判定物不变。
    static func parse(_ text: String) -> Parsed {
        var result = Parsed()
        let chars = Array(text)
        let count = chars.count
        var index = 0
        var consumed = -1
        var line = 1

        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        func skippingSpaceTabs(_ from: Int) -> Int {
            var cursor = from
            while cursor < count && (chars[cursor] == " " || chars[cursor] == "\t") { cursor += 1 }
            return cursor
        }

        while index < count {
            let character = chars[index]
            if character == "\n" {
                line += 1
                index += 1
                continue
            }
            guard character == "." else {
                index += 1
                continue
            }
            // 条目起点：行首，或 `,` 之后（中间只许空格 / 制表符）
            var back = index - 1
            while back >= 0 && (chars[back] == " " || chars[back] == "\t") { back -= 1 }
            let atStart = back < 0 || chars[back] == "\n" || chars[back] == ","
            guard atStart else {
                index += 1
                continue
            }
            var cursor = index + 1
            var key = ""
            while cursor < count && isIdentifier(chars[cursor]) {
                key.append(chars[cursor])
                cursor += 1
            }
            guard !key.isEmpty, key != slots.0, key != slots.1 else {
                index += 1
                continue
            }
            cursor = skippingSpaceTabs(cursor)
            guard cursor < count, chars[cursor] == ":" else {
                index += 1
                continue
            }
            cursor = skippingSpaceTabs(cursor + 1)
            guard cursor < count, chars[cursor] == "[" else {
                index += 1
                continue
            }
            if cursor < consumed {
                index += 1
                continue
            }
            let entryLine = line
            guard let close = LScan.bracket(chars, from: cursor) else {
                result.unparsed.append("\(file):\(entryLine) [. \(key)]：方括号未配平")
                index += 1
                continue
            }
            consumed = close
            let bodyChars = Array(chars[(cursor + 1)..<close])
            let body = SwiftSource(String(bodyChars)).uncommentedText
            var found: [String: String] = [:]
            var spans: [(Int, Int)] = []
            for slot in slotMatches(body) {
                found[slot.name] = slot.value
                spans.append(slot.span)
            }
            var rest = Array(body)
            for span in spans.sorted(by: { $0.0 > $1.0 }) {
                for position in span.0..<min(span.1, rest.count) { rest[position] = " " }
            }
            let remainder = String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,"))
            if Set(found.keys) != Set([slots.0, slots.1]) || !remainder.isEmpty {
                let names = found.keys.sorted().joined(separator: "/")
                result.unparsed.append(
                    "\(file):\(entryLine) [. \(key)]：块里读到的语言槽位是 \(names.isEmpty ? "无" : names)、"
                    + "槽位之外还剩 \(String(remainder.prefix(60)).debugDescription)"
                )
                index = close + 1
                continue
            }
            result.entries.append(
                LocalizedEntry(key: key, line: entryLine, zh: found[slots.0] ?? "", en: found[slots.1] ?? "")
            )
            index = close + 1
        }

        for slot in slotMatches(text) {
            result.slotCounts[slot.name, default: 0] += 1
        }
        return result
    }

    /// 真仓库那份表（**解析一次**，各判据共用 —— 7000 行 × 多次测试不值得反复算）。
    static let real: Parsed = {
        guard let text = LRepo.textIfExists(file) else { return Parsed() }
        return parse(text)
    }()

    /// 槽位：`.槽位名: "值"`（值里支持 `\"` 转义；顺序 / 空白 / 跨行无关）。
    static func slotMatches(_ text: String) -> [(name: String, value: String, span: (Int, Int))] {
        let chars = Array(text)
        let count = chars.count
        var found: [(String, String, (Int, Int))] = []
        var index = 0
        while index < count {
            guard chars[index] == "." else { index += 1; continue }
            var cursor = index + 1
            var name = ""
            while cursor < count && (chars[cursor].isLetter || chars[cursor].isNumber) {
                name.append(chars[cursor])
                cursor += 1
            }
            guard name == slots.0 || name == slots.1 else { index += 1; continue }
            var probe = cursor
            while probe < count && (chars[probe] == " " || chars[probe] == "\t") { probe += 1 }
            guard probe < count, chars[probe] == ":" else { index += 1; continue }
            probe += 1
            while probe < count && (chars[probe] == " " || chars[probe] == "\t") { probe += 1 }
            guard probe < count, chars[probe] == "\"" else { index += 1; continue }
            var value = ""
            var position = probe + 1
            while position < count && chars[position] != "\"" {
                if chars[position] == "\\" {
                    value.append(chars[position])
                    if position + 1 < count { value.append(chars[position + 1]) }
                    position += 2
                    continue
                }
                value.append(chars[position])
                position += 1
            }
            guard position < count else { index += 1; continue }
            found.append((name, value, (index, position + 1)))
            index = position + 1
        }
        return found
    }
}

// ============================================================================
// `Package.swift` → 生产扫描面（判据「面不许写死」）
// ============================================================================

enum ProductionFace {

    static let package = "Package.swift"

    /// 从 `Package.swift` 的**生产 target** 声明派生扫描面。
    /// 返回（面 · 既没声明 `path:` 也没声明 `sources:` 的生产 target 名 · 测试 target 名）。
    static func derive(_ text: String) -> (face: [String], undeclared: [String], tests: [String]) {
        let source = SwiftSource(text).uncommentedText
        let chars = Array(source)
        var face: [String] = []
        var undeclared: [String] = []
        var tests: [String] = []
        guard let targetRegex = LScan.regex(#"\.(\w*[Tt]arget)[ \t]*\("#) else {
            return ([], [], [])
        }
        let ns = source as NSString
        for match in targetRegex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: match.range(at: 1))
            let openIndex = match.range.location + match.range.length - 1
            guard let closeIndex = LScan.bracket(chars, from: openIndex, open: "(", close: ")") else {
                undeclared.append("\(kind)(未配平)")
                continue
            }
            let block = String(chars[(openIndex + 1)..<closeIndex])
            var fields: [String: String] = [:]
            for piece in LScan.splitTopLevel(block) {
                guard let colon = piece.firstIndex(of: ":") else { continue }
                let label = String(piece[piece.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(piece[piece.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if fields[label] == nil { fields[label] = value }
            }
            let name = (fields["name"] ?? "?").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if kind == "testTarget" {
                tests.append(name)
                continue
            }
            let path = fields["path"] ?? ""
            let sources = fields["sources"] ?? ""
            if path.isEmpty && sources.isEmpty {
                undeclared.append(name.isEmpty ? kind : name)
                continue
            }
            var base = path.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if base.isEmpty { base = "." }
            var items: [String] = []
            if let listRegex = LScan.regex(#""([^"]*)""#) {
                let listNS = sources as NSString
                items = listRegex.matches(in: sources, range: NSRange(location: 0, length: listNS.length))
                    .map { listNS.substring(with: $0.range(at: 1)) }
            }
            if items.isEmpty { items = [""] }
            for item in items {
                var relative = item.isEmpty ? base : (base as NSString).appendingPathComponent(item)
                if relative.hasPrefix("./") { relative = String(relative.dropFirst(2)) }
                if relative == "." { relative = "." }
                if !relative.isEmpty && !face.contains(relative) { face.append(relative) }
            }
        }
        return (face, undeclared, tests)
    }

    static func covers(_ declared: String, _ derived: String) -> Bool {
        derived == declared || derived.hasPrefix(declared.hasSuffix("/") ? declared : declared + "/")
    }
}
