import XCTest

/// `Scripts/check-design-tokens.py` 的 Swift 版（2026-11-09 判据搬家第二批 · 设计令牌 5 条之一）。
///
/// 为什么这条搬进测试、别的四条摘掉：见提交信息。本族的拦截史是**三次真红并导致改产品代码**
/// （`6bc2a642` bare-font 2 处 / `3e1721aa` 五类 17 处 / `bc21b074` 五处面板的 textstyle 与 foreground），
/// 口径「逐处加出来的错只能逐处拦」天生属于测试。
///
/// **只挡变差，销账即降基线**（棘轮）：按「文件 × 规则」与「规则合计」两个口径比
/// `Scripts/design-token-baseline.json`，任何一处高于基线即红。
///
/// 六条规则（与老脚本逐条同口径）：
/// · `bare-color` 裸颜色 —— 字面色值**永远判红**（命名色 / `NSColor.systemXxx` / `NSColor(calibratedRed:)` /
///   `Color(red:)` / `Color(white:)` / `#RRGGBB`）；`NSColor` 的**语义（角色）色**登记进
///   `Scripts/design-token-whitelist.json` 后放行（随主题自动适配，不是硬编码色值）。
///   `Color.clear` 是唯一按 token 放行的写法（只摘这一枚 token，不整行放行）。
/// · `bare-font` 裸字号（不在 11/12/13/15/17 刻度上）
/// · `bare-spacing` 裸间距（不在 0/1/2/4/8/12/16/24/32 刻度上）
/// · `bare-radius` 裸圆角（不在 1/4/6/8/10 刻度上）
/// · `bare-textstyle` 系统文本样式（`.font(.headline)` 这类 —— 不在字号刻度上）
/// · `bare-foreground` 系统语义前景色（`.foregroundStyle(.secondary)` 这类 —— 不在色板里）
///
/// 判定物只认**代码**那半：逐行切出 `(代码, 注释)`（块注释 / 行尾注释 / 字符串与多行串都认），
/// 注释里的形状不算命中；豁免标记也必须**落在注释位**且**理由非空**，并登记进
/// `Scripts/design-token-exemptions.json`（未登记 / 陈旧 ⇒ 红）。
///
/// **HEAD 上本来就红的那两处照实保留**：`App/Views/ProductOverviewSheet.swift` 的
/// `bare-textstyle 0 → 5` / `bare-foreground 0 → 3` 是老脚本在 HEAD 上的读数。本测试**不洗白**它：
/// `knownDrift` 精确钉住这 8 处（少一处 / 多一处都红），读数写在测试与提交里；
/// 棘轮仍按基线卡其余文件。既没改判据、也没改产品代码。
final class DesignTokenRatchetTests: XCTestCase {

    // MARK: - 口径（与老脚本同一份常量）

    enum Gate {
        static let face = "App"
        static let baselinePath = "Scripts/design-token-baseline.json"
        static let whitelistPath = "Scripts/design-token-whitelist.json"
        static let ledgerPath = "Scripts/design-token-exemptions.json"
        static let packageManifest = "Package.swift"
        static let appTarget = "DoyahStudioApp"

        /// 空跑防护（面下限）：2026-11-09 实测 187 份 / 45888 代码行。取老脚本的下限，不收紧。
        static let floorFiles = 105
        static let floorLines = 25000

        static let spacingScale: Set<Double> = [0, 1, 2, 4, 8, 12, 16, 24, 32]
        static let fontScale: Set<Double> = [11, 12, 13, 15, 17]
        static let radiusScale: Set<Double> = [1, 4, 6, 8, 10]

        /// `NSColor` 的语义（角色）色全集 —— 白名单只许从这里挑。
        static let semanticUniverse: Set<String> = [
            "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
            "placeholderTextColor", "separatorColor", "gridColor",
            "controlAccentColor", "controlTextColor", "disabledControlTextColor",
            "selectedControlTextColor", "selectedTextColor", "selectedTextBackgroundColor",
            "selectedContentBackgroundColor", "unemphasizedSelectedTextColor",
            "unemphasizedSelectedContentBackgroundColor", "keyboardFocusIndicatorColor",
            "controlBackgroundColor", "windowBackgroundColor", "windowFrameTextColor",
            "textBackgroundColor", "headerTextColor", "findHighlightColor", "linkColor",
            "shadowColor",
        ]

        /// 字面色值（硬边界：永远判红，不许进白名单）。
        static let bareColor = TokenRegex(
            #"\b(?:Color|NSColor)\.(?:orange|red|blue|yellow|green|purple|pink|gray|grey|brown|cyan|indigo|mint|teal)\b"# +
            #"|\bNSColor\.system(?:Red|Orange|Yellow|Green|Blue|Purple|Pink|Gray|Brown|Teal|Indigo|Mint|Cyan)\b"# +
            #"|\bNSColor\(calibratedRed:|\bNSColor\(deviceRed:"# +
            #"|\bColor\(red:|\bColor\(white:"# +
            #"|(?<![0-9A-Za-z_])#[0-9A-Fa-f]{6}(?![0-9A-Za-z])"#
        )
        static let semanticName = TokenRegex(#"\.([A-Za-z]+Color)\b"#)
        static let clearToken = TokenRegex(#"\b(?:Color|NSColor)\.clear\b"#)
        static let fontSize = TokenRegex(
            #"\.system\(size:\s*([0-9.]+)|systemFont\(ofSize:\s*([0-9.]+)|monospacedSystemFont\(ofSize:\s*([0-9.]+)"# +
            #"|monospacedDigitSystemFont\(ofSize:\s*([0-9.]+)"#
        )
        static let padding = TokenRegex(#"\.padding\(\s*(?:\.\w+\s*,\s*)?([0-9.]+)\s*\)"#)
        static let stackSpacing = TokenRegex(#"\b(?:VStack|HStack|LazyVStack|LazyHStack|Grid)\([^)]*spacing:\s*([0-9.]+)"#)
        static let corner = TokenRegex(#"cornerRadius:\s*([0-9.]+)|RoundedRectangle\(cornerRadius:\s*([0-9.]+)"#)
        /// `(?<!Theme)` 放过 `Theme.font(.body)`。
        static let bareTextStyle = TokenRegex(
            #"(?<!Theme)\.font\(\.(?:body|headline|caption2?|callout|subheadline|footnote|largeTitle|title[23]?)\)"#
        )
        static let bareForeground = TokenRegex(
            #"\.foregroundStyle\(\.(?:secondary|tertiary|quaternary)\)"# +
            #"|\.foregroundColor\(\.(?:secondaryLabelColor|tertiaryLabelColor)\)"#
        )

        static let fileMarker = "token-ok-file:"
        static let lineMarker = "token-ok"

        /// 老脚本在 **HEAD** 上的红（2026-11-09 实测 rc=1）。精确钉住：增减都要改这里并说明。
        static let knownDrift: [String: [String: Int]] = [
            "App/Views/ProductOverviewSheet.swift": ["bare-textstyle": 5, "bare-foreground": 3],
        ]

        static let rules = ["bare-color", "bare-font", "bare-spacing", "bare-radius", "bare-textstyle", "bare-foreground"]
    }

    // MARK: - 判定物：逐行切 (代码, 注释)

    struct CodeRow {
        let code: String
        let comment: String
    }

    /// 字符串扫描：从开引号走到收引号（含 `\(` 插值与 `\"` 转义；未收尾则到行尾）。
    static func skipString(_ chars: [Character], _ start: Int) -> Int {
        var index = start + 1
        while index < chars.count {
            let char = chars[index]
            if char == "\\" {
                if index + 1 < chars.count && chars[index + 1] == "(" {
                    var depth = 1
                    index += 2
                    while index < chars.count && depth > 0 {
                        if chars[index] == "\"" {
                            index = skipString(chars, index)
                            continue
                        }
                        if chars[index] == "(" { depth += 1 }
                        if chars[index] == ")" { depth -= 1 }
                        index += 1
                    }
                    continue
                }
                index += 2
                continue
            }
            if char == "\"" || char == "\n" { return index + 1 }
            index += 1
        }
        return chars.count
    }

    static func hasToken(_ chars: [Character], _ index: Int, _ token: [Character]) -> Bool {
        guard index + token.count <= chars.count else { return false }
        for offset in 0..<token.count where chars[index + offset] != token[offset] { return false }
        return true
    }

    /// 逐行 `(代码, 注释)` —— 注释里的 `//`、`/*` 在字符串里不算注释（多行串同理）。
    static func splitCodeComment(_ text: String) -> [CodeRow] {
        let chars = Array(text)
        let triple: [Character] = ["\"", "\"", "\""]
        var rows: [CodeRow] = []
        var code = ""
        var comment = ""
        var index = 0
        var inBlock = false
        var inMultiline = false

        func flush() {
            rows.append(CodeRow(code: code, comment: comment))
            code = ""
            comment = ""
        }

        while index < chars.count {
            if inBlock {
                if hasToken(chars, index, ["*", "/"]) {
                    inBlock = false
                    index += 2
                    comment += "*/"
                    continue
                }
                if chars[index] == "\n" { flush() } else { comment.append(chars[index]) }
                index += 1
                continue
            }
            if inMultiline {
                var end = index
                while end + 2 < chars.count && !hasToken(chars, end, triple) { end += 1 }
                if end + 2 < chars.count {
                    code += String(chars[index..<end]) + "\"\"\""
                    index = end + 3
                    inMultiline = false
                } else {
                    code += String(chars[index...])
                    index = chars.count
                }
                continue
            }
            if hasToken(chars, index, triple) {
                inMultiline = true
                index += 3
                continue
            }
            if chars[index] == "\"" {
                let end = skipString(chars, index)
                code += String(chars[index..<end])
                index = end
                continue
            }
            if hasToken(chars, index, ["/", "/"]) {
                var end = index
                while end < chars.count && chars[end] != "\n" { end += 1 }
                comment += String(chars[index..<end])
                index = end
                continue
            }
            if hasToken(chars, index, ["/", "*"]) {
                inBlock = true
                index += 2
                comment += "/*"
                continue
            }
            if chars[index] == "\n" {
                flush()
                index += 1
                continue
            }
            code.append(chars[index])
            index += 1
        }
        if !code.isEmpty || !comment.isEmpty { flush() }
        return rows
    }

    // MARK: - 规则

    /// 一处裸色 = 字面色值，或**未登记**的系统语义色。`Color.clear` 只摘这一枚 token。
    static func isBareColor(_ code: String, allowed: Set<String>) -> Bool {
        let probe = Gate.clearToken.replacing(code, with: "")
        if Gate.bareColor.matches(probe) { return true }
        for name in Gate.semanticName.captures(probe) where Gate.semanticUniverse.contains(name) && !allowed.contains(name) {
            return true
        }
        return false
    }

    struct Counts {
        var values: [String: Int] = [:]
        func value(_ rule: String) -> Int { values[rule] ?? 0 }
        var total: Int { values.values.reduce(0, +) }
    }

    struct FileScan {
        var counts = Counts()
        var exemptLines: [Int] = []
        var reasonlessLines: [Int] = []
        var codeLines = 0
    }

    /// 单文件扫描（判定物 = 代码那半；一行里同一规则只记一次，与老脚本同口径）。
    static func scanFile(_ text: String, allowed: Set<String>) -> FileScan {
        var scan = FileScan()
        var counts: [String: Int] = [:]
        for (offset, row) in splitCodeComment(text).enumerated() {
            let number = offset + 1
            let mark = row.comment.contains(Gate.fileMarker) ? Gate.fileMarker
                : (row.comment.contains(Gate.lineMarker) ? Gate.lineMarker : nil)
            if let mark {
                let tail = row.comment.components(separatedBy: mark).dropFirst().joined(separator: mark)
                let reason = tail.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,.-—"))
                if reason.isEmpty { scan.reasonlessLines.append(number) } else { scan.exemptLines.append(number) }
                continue
            }
            let code = row.code.trimmingCharacters(in: .whitespaces)
            if code.isEmpty { continue }
            scan.codeLines += 1

            func bump(_ rule: String) {
                counts[rule, default: 0] += 1
            }

            if isBareColor(code, allowed: allowed) { bump("bare-color") }
            if Gate.fontSize.numbers(code).contains(where: { $0 != 0 && !Gate.fontScale.contains($0) }) { bump("bare-font") }
            let spacing = Gate.padding.numbers(code) + Gate.stackSpacing.numbers(code)
            if spacing.contains(where: { !Gate.spacingScale.contains($0) }) { bump("bare-spacing") }
            if Gate.corner.numbers(code).contains(where: { !Gate.radiusScale.contains($0) }) { bump("bare-radius") }
            if Gate.bareTextStyle.matches(code) { bump("bare-textstyle") }
            if Gate.bareForeground.matches(code) { bump("bare-foreground") }
        }
        scan.counts.values = counts
        return scan
    }

    /// 整面扫描 → (每文件规则计数, 行级豁免, 无理由豁免, 文件级豁免, 文件数, 代码行数)
    struct FaceScan {
        var counts: [String: [String: Int]] = [:]
        var exemptLines: [String: [Int]] = [:]
        var reasonless: [String] = []
        var exemptFiles: [String: String] = [:]
        var files = 0
        var codeLines = 0
        var totals: [String: Int] {
            var total: [String: Int] = [:]
            for perFile in counts.values {
                for (rule, value) in perFile { total[rule, default: 0] += value }
            }
            return total
        }
    }

    static func scanFace(_ paths: [String], allowed: Set<String>, text: (String) throws -> String) rethrows -> FaceScan {
        var face = FaceScan()
        for path in paths {
            let body = try text(path)
            if let reason = fileExemptionReason(body) {
                face.exemptFiles[path] = reason
                continue
            }
            face.files += 1
            let scan = scanFile(body, allowed: allowed)
            face.codeLines += scan.codeLines
            if !scan.counts.values.isEmpty { face.counts[path] = scan.counts.values }
            if !scan.exemptLines.isEmpty { face.exemptLines[path] = scan.exemptLines }
            face.reasonless += scan.reasonlessLines.map { "\(path):\($0)" }
        }
        return face
    }

    /// 文件级豁免：文件头 5 行内的 `token-ok-file: 理由`（理由非空才算数）。
    static func fileExemptionReason(_ text: String) -> String? {
        for line in splitCodeComment(text).prefix(5) {
            guard line.comment.contains(Gate.fileMarker) else { continue }
            let tail = line.comment.components(separatedBy: Gate.fileMarker).dropFirst().joined(separator: Gate.fileMarker)
            let reason = tail.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,.-—"))
            return reason.isEmpty ? nil : reason
        }
        return nil
    }

    // MARK: - 台账

    static func whitelist() throws -> (allowed: Set<String>, problems: [String]) {
        guard LRepo.exists(Gate.whitelistPath) else { return ([], ["语义色白名单文件不存在：\(Gate.whitelistPath)"]) }
        let data = try JSONSerialization.jsonObject(with: Data(try LRepo.text(Gate.whitelistPath).utf8)) as? [String: Any]
        guard let entries = data?["semanticColors"] as? [Any], !entries.isEmpty else {
            return ([], ["语义色白名单的 semanticColors 缺失或为空（空跑防护）"])
        }
        var allowed: Set<String> = []
        var problems: [String] = []
        for entry in entries {
            guard let name = entry as? String else {
                problems.append("白名单条目不是字符串：\(entry)")
                continue
            }
            if !Gate.semanticUniverse.contains(name) {
                problems.append("白名单里出现**非语义色**：\(name)（只许 NSColor 角色色）")
            } else if allowed.contains(name) {
                problems.append("白名单条目重复：\(name)")
            } else {
                allowed.insert(name)
            }
        }
        return (allowed, problems)
    }

    struct Ledger {
        var lines: [(file: String, line: Int)] = []
        var files: Set<String> = []
    }

    static func ledger() throws -> (ledger: Ledger, problems: [String]) {
        guard LRepo.exists(Gate.ledgerPath) else {
            return (Ledger(), ["豁免台账不存在：\(Gate.ledgerPath)（逃逸口必须有台账）"])
        }
        guard let data = try JSONSerialization.jsonObject(with: Data(try LRepo.text(Gate.ledgerPath).utf8)) as? [String: Any] else {
            return (Ledger(), ["豁免台账不是合法 JSON：\(Gate.ledgerPath)"])
        }
        var ledger = Ledger()
        var problems: [String] = []
        var seenLines: Set<String> = []
        var seenFiles: Set<String> = []
        guard let lineEntries = data["lines"] as? [Any], let fileEntries = data["files"] as? [Any] else {
            return (Ledger(), ["豁免台账的 lines / files 缺失或不是列表"])
        }
        for entry in lineEntries {
            guard let entry = entry as? [String: Any], let file = entry["file"] as? String else {
                problems.append("豁免台账 lines 条目形状不对：\(entry)")
                continue
            }
            guard let reason = entry["reason"] as? String, !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
                problems.append("豁免台账 lines 条目没写理由：\(file)")
                continue
            }
            guard let number = entry["line"] as? Int, number > 0 else {
                problems.append("豁免台账 lines 条目缺行号：\(file)")
                continue
            }
            let identity = "\(file):\(number)"
            if seenLines.contains(identity) {
                problems.append("豁免台账重复登记：\(identity)")
                continue
            }
            seenLines.insert(identity)
            ledger.lines.append((file, number))
        }
        for entry in fileEntries {
            guard let entry = entry as? [String: Any], let file = entry["file"] as? String else {
                problems.append("豁免台账 files 条目形状不对：\(entry)")
                continue
            }
            guard let reason = entry["reason"] as? String, !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
                problems.append("豁免台账 files 条目没写理由：\(file)")
                continue
            }
            if seenFiles.contains(file) {
                problems.append("豁免台账重复登记：\(file)")
                continue
            }
            seenFiles.insert(file)
            ledger.files.insert(file)
        }
        return (ledger, problems)
    }

    /// 逃逸口对账：未登记 ⇒ 红；台账陈旧 ⇒ 红；无理由 ⇒ 红。
    static func escapeProblems(_ face: FaceScan, _ ledger: Ledger) -> [String] {
        var problems: [String] = []
        let registeredLines = Set(ledger.lines.map { "\($0.file):\($0.line)" })
        for (path, numbers) in face.exemptLines.sorted(by: { $0.key < $1.key }) {
            for number in numbers where !registeredLines.contains("\(path):\(number)") {
                problems.append("未登记的行级豁免：\(path):\(number)（逃逸口必须进 \(Gate.ledgerPath)）")
            }
        }
        for entry in face.reasonless {
            problems.append("豁免没写理由：\(entry)（写法 `// \(Gate.lineMarker)：理由`）")
        }
        for path in face.exemptFiles.keys.sorted() where !ledger.files.contains(path) {
            problems.append("未登记的文件级豁免：\(path)（逃逸口必须进 \(Gate.ledgerPath)）")
        }
        for entry in ledger.lines where !(face.exemptLines[entry.file] ?? []).contains(entry.line) {
            problems.append("豁免台账陈旧：\(entry.file):\(entry.line) 盘上已无该标记")
        }
        for path in ledger.files.sorted() where face.exemptFiles[path] == nil {
            problems.append("豁免台账陈旧：\(path) 盘上已无文件级标记")
        }
        return problems
    }

    // MARK: - 面

    static func packageSources() -> [String]? {
        guard let manifest = LRepo.textIfExists(Gate.packageManifest) else { return nil }
        let pattern = #"name:\s*""# + Gate.appTarget + #"".*?sources:\s*\[([^\]]*)\]"#
        guard let match = TokenRegex(pattern, options: [.dotMatchesLineSeparators]).firstMatch(manifest) else { return nil }
        let body = match.capture(1, in: manifest)
        return TokenRegex(#""([^"]+)""#).captures(body)
    }

    // MARK: - 面与台账读数（真仓库）

    func repoScan() throws -> FaceScan {
        let (allowed, _) = try Self.whitelist()
        return try Self.scanFace(LRepo.swiftFiles([Gate.face]), allowed: allowed) { try LRepo.text($0) }
    }

    // MARK: - 用例

    /// 面不许被悄悄削窄：文件数 / 代码行数 / 目录都得在。
    func testFaceIsNotNarrowed() throws {
        XCTAssertTrue(LRepo.exists(Gate.face), "扫描面不存在：\(Gate.face)/（面被砍到底不许静默通过）")
        let face = try repoScan()
        XCTAssertGreaterThanOrEqual(face.files, Gate.floorFiles, "扫描面只有 \(face.files) 份 .swift（下限 \(Gate.floorFiles)）")
        XCTAssertGreaterThanOrEqual(face.codeLines, Gate.floorLines, "代码行只有 \(face.codeLines)（下限 \(Gate.floorLines)）")
    }

    /// 面与工程声明对账（`Package.swift` 的 `DoyahStudioApp` sources）。
    func testFaceMatchesPackageSources() {
        guard let declared = Self.packageSources() else {
            return XCTFail("`\(Gate.packageManifest)` 里找不到 `\(Gate.appTarget)` 的 `sources:` 列表（面无法与工程声明对账）")
        }
        XCTAssertTrue(declared.contains(Gate.face), "`\(Gate.appTarget)` 的 sources 里没有 `\(Gate.face)`：\(declared)")
        for item in declared {
            XCTAssertTrue(LRepo.exists(item), "`\(Gate.appTarget)` 声明的源目录不在盘上：\(item)")
        }
    }

    /// 白名单只许语义色，且不许空。
    func testWhitelistOnlyAllowsSemanticColors() throws {
        let (allowed, problems) = try Self.whitelist()
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        XCTAssertFalse(allowed.isEmpty)
    }

    /// 字面色值永远判红（5 例反例）；白名单里的语义色放行、未登记的语义色仍判红（25 条一条不少）。
    func testLiteralColorsAndSemanticBoundary() throws {
        let (allowed, _) = try Self.whitelist()
        let samples = [
            "let c = Color.orange",
            "let c = NSColor.systemRed",
            "let c = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)",
            "let c = Color(red: 0.1, green: 0.2, blue: 0.3)",
            "let c = Color(hex: \"#FF00FF\")",
        ]
        for sample in samples {
            XCTAssertTrue(Self.isBareColor(sample, allowed: allowed), "反例没被拦下（闸被放宽）：\(sample)")
        }
        for name in Gate.semanticUniverse.sorted() {
            let negative = "let c = NSColor.\(name)"
            let hit = Self.isBareColor(negative, allowed: allowed)
            if allowed.contains(name) {
                XCTAssertFalse(hit, "白名单里的语义色仍被判裸色：\(negative)")
            } else {
                XCTAssertTrue(hit, "未登记的系统语义色没被判裸色：\(negative)")
            }
        }
    }

    /// `Color.clear` 只放行这一枚 token（`let a = Color.orange; let b = Color.clear` 仍判红）。
    func testColorClearIsTheOnlyTokenLevelEscape() {
        XCTAssertTrue(Self.isBareColor("let a = Color.orange; let b = Color.clear", allowed: []))
        XCTAssertFalse(Self.isBareColor("let b = Color.clear", allowed: []))
    }

    /// 注释不是命中：块注释与行尾注释里的形状不算。
    func testCommentsAreNotHits() {
        let text = """
        /* 历史：.font(.headline) / .foregroundStyle(.secondary) / Color.orange */
        let a = 1 // .font(.headline)
        let b = 2 /// .foregroundStyle(.secondary)
        """
        let scan = Self.scanFile(text, allowed: [])
        XCTAssertEqual(scan.counts.total, 0, "注释里的形状被判成命中：\(scan.counts.values)")
        XCTAssertEqual(scan.codeLines, 2)
    }

    /// 字符串里的 `token-ok` 不构成豁免（旧版对整行做子串判定即假绿）。
    func testTokenOkInsideStringIsNotAnExemption() {
        let text = "let a = Color.orange; let b = \"token-ok\"\n"
        let scan = Self.scanFile(text, allowed: [])
        XCTAssertEqual(scan.counts.value("bare-color"), 1)
        XCTAssertTrue(scan.exemptLines.isEmpty)
    }

    /// 一行多处命中不许漏：`.padding(8).padding(6)` 里 6 不在刻度上。
    func testEveryHitOnOneLineIsJudged() {
        let scan = Self.scanFile("view.padding(8).padding(6)\n", allowed: [])
        XCTAssertEqual(scan.counts.value("bare-spacing"), 1)
        let clean = Self.scanFile("view.padding(8).padding(12)\n", allowed: [])
        XCTAssertEqual(clean.counts.value("bare-spacing"), 0)
    }

    /// 无理由的豁免判红（旧版只认标记、不判理由）。
    func testReasonlessExemptionIsRejected() {
        let scan = Self.scanFile("let a = Color.orange // token-ok：\n", allowed: [])
        XCTAssertEqual(scan.reasonlessLines, [1])
        XCTAssertTrue(scan.exemptLines.isEmpty)
        XCTAssertEqual(scan.counts.total, 0, "带标记的行不再计违规（口径与老脚本一致）")
    }

    /// 六条规则各自都会开火（一处夹具，六类各一）。
    func testEachRuleFires() {
        let text = """
        let a = Color.orange
        let b = Text("x").font(.system(size: 14))
        let c = HStack(spacing: 3) { EmptyView() }
        let d = RoundedRectangle(cornerRadius: 5)
        let e = Text("x").font(.headline)
        let f = Text("x").foregroundStyle(.secondary)
        """
        let scan = Self.scanFile(text, allowed: [])
        for rule in Gate.rules {
            XCTAssertEqual(scan.counts.value(rule), 1, "规则 \(rule) 没开火：\(scan.counts.values)")
        }
    }

    /// 逃逸口台账三态：未登记 / 无理由 / 陈旧都判红（夹具面 + 夹具台账）。
    func testEscapeLedgerHasThreeStates() {
        var face = FaceScan()
        face.exemptLines = ["App/Probe.swift": [7]]
        face.reasonless = ["App/Probe.swift:9"]
        face.exemptFiles = ["App/Probe.swift2": "系统外壳色"]
        var ledger = Ledger()
        ledger.lines = [("App/Probe.swift", 7), ("App/Gone.swift", 3)]
        ledger.files = ["App/Gone2.swift"]
        let problems = Self.escapeProblems(face, ledger)
        XCTAssertTrue(problems.contains { $0.contains("App/Gone.swift:3 盘上已无该标记") }, problems.joined(separator: "\n"))
        XCTAssertTrue(problems.contains { $0.contains("App/Gone2.swift 盘上已无文件级标记") }, problems.joined(separator: "\n"))
        XCTAssertTrue(problems.contains { $0.contains("豁免没写理由") }, problems.joined(separator: "\n"))
        XCTAssertTrue(problems.contains { $0.contains("未登记的文件级豁免：App/Probe.swift2") }, problems.joined(separator: "\n"))
        XCTAssertFalse(problems.contains { $0.contains("App/Probe.swift:7") })
    }

    /// 真仓库台账 / 逃逸口必须是干净的（否则「加一行注释就整文件放行」会变成常规操作）。
    func testRepoExemptionsAreRegistered() throws {
        let (allowed, _) = try Self.whitelist()
        let face = try Self.scanFace(LRepo.swiftFiles([Gate.face]), allowed: allowed) { try LRepo.text($0) }
        let (ledger, problems) = try Self.ledger()
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        let escapes = Self.escapeProblems(face, ledger)
        XCTAssertTrue(escapes.isEmpty, escapes.joined(separator: "\n"))
    }

    /// 棘轮：任何「文件 × 规则」与「规则合计」都不得高于基线（`knownDrift` 那一条除外）。
    func testRatchetIsNotWorseThanBaseline() throws {
        let face = try repoScan()
        let text = try LRepo.text(Gate.baselinePath)
        guard let baseline = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let files = baseline["files"] as? [String: [String: Int]],
              let totals = baseline["totals"] as? [String: Int] else {
            return XCTFail("基线不是合法形状：\(Gate.baselinePath)")
        }
        var problems: [String] = []
        for (path, counts) in face.counts.sorted(by: { $0.key < $1.key }) {
            let budget = files[path] ?? [:]
            for (rule, value) in counts.sorted(by: { $0.key < $1.key }) where value > (budget[rule] ?? 0) {
                if Gate.knownDrift[path]?[rule] != nil { continue }
                problems.append("\(path): \(rule) \(budget[rule] ?? 0) → \(value)")
            }
        }
        for (rule, value) in face.totals.sorted(by: { $0.key < $1.key }) {
            let drift = Gate.knownDrift.values.reduce(0) { $0 + ($1[rule] ?? 0) }
            if value > (totals[rule] ?? 0) + drift {
                problems.append("合计 \(rule) \(totals[rule] ?? 0) → \(value)（已计入 knownDrift \(drift)）")
            }
        }
        XCTAssertTrue(problems.isEmpty, "比基线更差（只能降不能升）：\n" + problems.joined(separator: "\n"))
    }

    /// **读数与老脚本逐位相等**（2026-11-09 HEAD）：扫描面 187 份 / 45888 代码行；合计 331 处
    /// = `bare-color 2 / bare-foreground 97 / bare-spacing 52 / bare-textstyle 180`
    /// （其中 8 处就是 `knownDrift`；基线 2/102/56/189 是**预算**，现值更低 = 已销账但没下调基线）。
    /// 这一条是「搬过来没换口径」的证据 —— 计数差一处它就红。
    func testMeasuredReadingMatchesTheOldGatesNumbers() throws {
        let face = try repoScan()
        XCTAssertEqual(face.files, 187, "扫描面的文件数与老脚本不一致")
        XCTAssertEqual(face.codeLines, 45888, "扫描面的代码行数与老脚本不一致")
        XCTAssertEqual(face.counts["App/Views/ProductOverviewSheet.swift"],
                       ["bare-textstyle": 5, "bare-foreground": 3],
                       "HEAD 上那两处红的读数是老脚本的 rc=1 读数")
        XCTAssertEqual(face.totals, [
            "bare-color": 2,
            "bare-foreground": 97,
            "bare-spacing": 52,
            "bare-textstyle": 180,
        ], "六条规则的合计与老脚本不一致（扫的不是同一件事）")
    }

    /// **HEAD 上的红照实保留**：`ProductOverviewSheet.swift` 的读数就是老脚本的 rc=1 读数，
    /// 且它是**唯一**超出基线的文件（别的文件一红就走 `testRatchetIsNotWorseThanBaseline`）。
    func testKnownDriftIsExactlyWhatTheGateReportedOnHEAD() throws {
        let face = try repoScan()
        let text = try LRepo.text(Gate.baselinePath)
        guard let baseline = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let files = baseline["files"] as? [String: [String: Int]] else {
            return XCTFail("基线不是合法形状：\(Gate.baselinePath)")
        }
        XCTAssertEqual(face.counts["App/Views/ProductOverviewSheet.swift"] ?? [:], Gate.knownDrift["App/Views/ProductOverviewSheet.swift"])
        var beyond: Set<String> = []
        for (path, counts) in face.counts {
            let budget = files[path] ?? [:]
            if counts.contains(where: { $0.value > (budget[$0.key] ?? 0) }) { beyond.insert(path) }
        }
        XCTAssertEqual(beyond, Set(Gate.knownDrift.keys), "超出基线的文件集合变了（修好了就销账 / 新增了就修）")
    }
}

// MARK: - 小工具

/// `NSRegularExpression` 的薄壳：命中判定 / 捕获取值 / 数值集合。
struct TokenRegex {
    private let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // 判据自己的模式写错是硬错，立刻炸掉（不静默当「无命中」）。
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func firstMatch(_ text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func replacing(_ text: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    /// 一行里的**每一处**命中的每个捕获组数值（旧版只判首个匹配）。
    func numbers(_ text: String) -> [Double] {
        var found: [Double] = []
        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match else { return }
            for group in 1..<match.numberOfRanges {
                let range = match.range(at: group)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { continue }
                if let value = Double(text[swiftRange]) { found.append(value) }
            }
        }
        return found
    }

    func captures(_ text: String) -> [String] {
        var found: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            for group in 1..<match.numberOfRanges {
                let range = match.range(at: group)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { continue }
                found.append(String(text[swiftRange]))
            }
        }
        return found
    }
}

extension NSTextCheckingResult {
    func capture(_ index: Int, in text: String) -> String {
        guard index < numberOfRanges, let range = Range(range(at: index), in: text) else { return "" }
        return String(text[range])
    }
}
