import XCTest

/// `check-core-localization.py` 的两条**展示文本棘轮**（R-037 / L-109）的 Swift 版。
///
/// 原脚本管两件事，口径一致：**只挡变差，销账即降基线**。
///
/// **棘轮 A（含汉字的字面量）**：`Core/**` + `Plugins/Notes/Sources/**` 里「字符串字面量正文含
/// 汉字」的行数，按「文件数 / 行数」两个口径记账，比基线（`Scripts/core-localization-baseline.json`）
/// 更差即红。判定物 = **字面量的实际跨度**（先剥注释；多行串 / raw 串都认）⇒ 注释里的中文不算，
/// 三引号块里的中文算。
///
/// **棘轮 B（写死的英文展示文案）**：同面上「像展示文案的英文字面量」一律要在白名单
/// `Scripts/core-localization-english.json` 里；每条要有人给的 `kind`（`unclassified` 不在词表内
/// ⇒ 仍然红）；白名单**只许缩小**（盘上已经没有的条目 ⇒ 红，提示销账）。
///
/// 覆盖边界（与原脚本逐条对齐，未收窄）：
/// · 只扫 `Core` + `Plugins/Notes/Sources`（`App/` / `CLI/` 的写死英文仍不在面内 —— 原脚本同样如此）；
/// · 棘轮 B 的判定物是**逐行**字面量 + 只剥行首 `//` 注释（原脚本的既有缺口，本测试未改口径）；
/// · 全大写单词不在候选面（`TSV` / `INSERT` 这类与格式名同形）。
///
/// 反例（本族证据，`test…` 前缀见下）：多行串里的中文必须计入；注释里的中文必须不计入；
/// 新出现的 `"Home"` / `"Untitled Document"` 必须报新增；白名单里的死条目 / 未分类条目必须报红。
final class LocalizationCoreRatchetTests: XCTestCase {

    enum Gate {
        static let faces = ["Core", "Plugins/Notes/Sources"]
        static let hanExempt: Set<String> = ["Core/Localization.swift"]
        static let englishPathExempt: [String: String] = [
            "Localization.swift": "语言表本身（这里就是两语槽位；汉字棘轮同样豁免它）",
            "CodeLanguageDefinitions.swift": "代码语言的登记表：关键字表 / 语言名 / 补全项 —— 整表都是技术标识，与语言表同一性质",
        ]
        static let baseline = "Scripts/core-localization-baseline.json"
        static let ledger = "Scripts/core-localization-english.json"
        /// 空跑防护：面里 `.swift` 份数下限（2026-10-13 实测 222，留搬家余量取 180）。
        static let floorFiles = 180

        /// 英文白名单的 `kind` 词表（与台账 `kinds` 逐键对账）。
        static let allowedKinds: Set<String> = [
            "sql", "dbType", "wireValue", "explainField", "driverMessage", "serverMessageMatch",
            "internalErrorDescription", "protocolToken", "formatPattern", "pathName", "assetName",
            "xmlElementName", "cliFlag", "parseToken", "logOnly", "guardrailPattern", "productName",
            "sampleValue", "displayDebt", "bilingualTable", "diffHeader",
        ]
        static let pendingKind = "unclassified"

        static let badChars: Set<Character> = Set("\\%{}<>*_=#@$+|&~`[]()")
        static let allowedChars = "^[A-Za-z0-9 ,.';:!?/+-]+$"
        static let titleCase = "^[A-Z][a-z]{2,}$"
        static let minLength = 3
        static let maxLength = 60

        // MARK: - 面

        /// 扫描面（仓库相对路径 → 文件正文）。测试可注入夹具，判据本体与 IO 分离。
        static func loadFace() throws -> [String: String] {
            var files: [String: String] = [:]
            for relative in LRepo.swiftFiles(faces) {
                files[relative] = try LRepo.text(relative)
            }
            return files
        }

        // MARK: - 棘轮 A：含汉字的字面量

        /// 一个文件里「**字符串字面量正文**含汉字」的行号（升序去重）。
        static func hanLines(_ text: String) -> [Int] {
            let source = SwiftSource(text)
            let chars = source.chars
            var lineStarts: [Int] = [0]
            for index in 0..<chars.count where chars[index] == "\n" { lineStarts.append(index + 1) }
            var hits: Set<Int> = []
            for span in source.literals where span.end > span.start {
                let first = lineStarts.lastIndex(where: { $0 <= span.start }) ?? 0
                let last = lineStarts.lastIndex(where: { $0 <= max(span.end - 1, span.start) }) ?? 0
                for number in first...last {
                    let lineStart = lineStarts[number]
                    let lineEnd = number + 1 < lineStarts.count ? lineStarts[number + 1] - 1 : chars.count
                    let from = max(span.start, lineStart)
                    let to = min(span.end, lineEnd)
                    if from < to, String(chars[from..<to]).contains(where: LScan.isHan) {
                        hits.insert(number + 1)
                    }
                }
            }
            return hits.sorted()
        }

        struct HanReading {
            var files = 0
            var lines = 0
            var scanned = 0
            var perFile: [String: [Int]] = [:]
        }

        static func hanReading(_ files: [String: String]) -> HanReading {
            var reading = HanReading()
            for relative in files.keys.sorted() {
                if hanExempt.contains(relative) { continue }
                reading.scanned += 1
                let hits = hanLines(files[relative] ?? "")
                if !hits.isEmpty {
                    reading.files += 1
                    reading.lines += hits.count
                    reading.perFile[relative] = hits
                }
            }
            return reading
        }

        // MARK: - 棘轮 B：写死的英文展示文案

        /// 一行里「真的是两个字界引号之间」的字面量（开引号前一字符不许是 `'` / `"` / `\` / 反引号）。
        static let englishLiteral = #""((?:[^"\\]|\\.)*)""#

        static func introducesLiteral(_ line: [UInt16], at index: Int) -> Bool {
            guard index > 0 else { return true }
            let previous = line[index - 1]
            if CharacterSet.alphanumerics.contains(Unicode.Scalar(previous) ?? " ") { return false }
            return ![UInt16(UnicodeScalar("'").value), UInt16(UnicodeScalar("\"").value),
                     UInt16(UnicodeScalar("\\").value), UInt16(UnicodeScalar("`").value)].contains(previous)
        }

        static func isEnglishDisplayCandidate(_ literal: String) -> Bool {
            if !literal.contains(where: { $0.isLetter && $0.isASCII }) { return false }
            if literal.contains(where: LScan.isHan) { return false }
            if literal.contains(where: { badChars.contains($0) }) { return false }
            guard let allowed = LScan.regex(allowedChars) else { return false }
            let range = NSRange(location: 0, length: (literal as NSString).length)
            guard allowed.firstMatch(in: literal, range: range) != nil else { return false }
            let text = literal.trimmingCharacters(in: .whitespaces)
            guard text.count >= minLength, text.count <= maxLength else { return false }
            if text.contains(" ") { return true }
            guard let title = LScan.regex(titleCase) else { return false }
            return title.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }

        /// {字面量: ["文件:行", …]} —— 盘上「像写死的英文展示文案」的全部字面量。
        static func englishCandidates(_ files: [String: String]) -> [String: [String]] {
            var found: [String: [String]] = [:]
            guard let literalRegex = LScan.regex(englishLiteral) else { return found }
            for relative in files.keys.sorted() {
                let name = (relative as NSString).lastPathComponent
                if englishPathExempt[name] != nil { continue }
                let lines = (files[relative] ?? "").components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                    let chars = Array(line.utf16)
                    let ns = line as NSString
                    for match in literalRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                        if !introducesLiteral(chars, at: match.range.location) { continue }
                        let literal = ns.substring(with: match.range(at: 1))
                        guard isEnglishDisplayCandidate(literal) else { continue }
                        let text = literal.trimmingCharacters(in: .whitespaces)
                        found[text, default: []].append("\(relative):\(index + 1)")
                    }
                }
            }
            return found
        }

        /// 棘轮 B 的判定（纯函数：喂盘上候选 + 台账内容，返回问题清单）。
        static func englishProblems(
            onDisk: [String: [String]],
            entries: [String: [String: Any]],
            kinds: Set<String>,
            pathExempt: Set<String>
        ) -> [String] {
            var problems: [String] = []
            if kinds != allowedKinds {
                problems.append("[台账] `kinds` 与词表不一致：台账独有 \(kinds.subtracting(allowedKinds).sorted()) / "
                                + "词表独有 \(allowedKinds.subtracting(kinds).sorted())")
            }
            if pathExempt != Set(englishPathExempt.keys) {
                problems.append("[台账] `pathExempt` 与豁免清单不一致：台账独有 "
                                + "\(pathExempt.subtracting(englishPathExempt.keys).sorted()) / "
                                + "清单独有 \(Set(englishPathExempt.keys).subtracting(pathExempt).sorted())")
            }
            for (literal, entry) in entries.sorted(by: { $0.key < $1.key }) {
                let kind = LRepo.string(entry["kind"])
                if kind == pendingKind || !allowedKinds.contains(kind) {
                    problems.append("[未分类] `\(literal)` 的 kind = `\(kind)` 不在词表内")
                }
            }
            for literal in Set(onDisk.keys).subtracting(entries.keys).sorted() {
                problems.append("[新增] `\(literal)` 是写死的英文展示文案，不在白名单里"
                                + "（首处 \(onDisk[literal]?.first ?? "?")）")
            }
            for literal in Set(entries.keys).subtracting(onDisk.keys).sorted() {
                problems.append("[陈旧] 白名单里的 `\(literal)` 盘上已经没有了 —— 请销账")
            }
            return problems
        }
    }

    // MARK: - 真仓库判据

    /// 棘轮 A：文件数 / 行数只许不升；面不许被削（空跑防护）；基线必须在盘。
    func testHanLiteralRatchetDoesNotWorsen() throws {
        let reading = Gate.hanReading(try Gate.loadFace())
        XCTAssertGreaterThanOrEqual(reading.scanned, Gate.floorFiles,
                                    "扫描面只有 \(reading.scanned) 个 .swift（下限 \(Gate.floorFiles)）"
                                    + " —— `Core/` 被改名或搬家了吗？面被砍到底不许静默通过")
        XCTAssertTrue(LRepo.exists(Gate.baseline),
                      "基线文件 \(Gate.baseline) 不在盘，而扫描面有 \(reading.scanned) 个 .swift —— 按 0/0 兜底会假绿")
        let payload = try LRepo.json(Gate.baseline)
        let baseline = (payload["baseline"] as? [String: Any]) ?? [:]
        let baselineFiles = LRepo.int(baseline["files"])
        let baselineLines = LRepo.int(baseline["lines"])
        XCTAssertLessThanOrEqual(
            reading.files, baselineFiles,
            "含汉字字面量的文件数 \(baselineFiles) → \(reading.files)（明细：\(reading.perFile.keys.sorted())）"
        )
        XCTAssertLessThanOrEqual(
            reading.lines, baselineLines,
            "含汉字字面量的行数 \(baselineLines) → \(reading.lines)（逐文件行号见 `--report` 等价读数）"
        )
        print("📏 棘轮 A：\(reading.files) 个文件 / \(reading.lines) 行（基线 \(baselineFiles) / \(baselineLines)；"
              + "扫描面 \(reading.scanned) 个 .swift）")
    }

    /// 棘轮 B：白名单之外 0 条、陈旧 0 条、每条都有词表内的 `kind`。
    func testEnglishDisplayCopyWhitelistIsExact() throws {
        let onDisk = Gate.englishCandidates(try Gate.loadFace())
        let ledger = try LRepo.json(Gate.ledger)
        let rawEntries = (ledger["entries"] as? [String: Any]) ?? [:]
        var entries: [String: [String: Any]] = [:]
        for (key, value) in rawEntries {
            if let one = value as? [String: Any] { entries[key] = one }
        }
        let kinds = Set(((ledger["kinds"] as? [String: Any]) ?? [:]).keys)
        let pathExempt = Set(((ledger["pathExempt"] as? [String: Any]) ?? [:]).keys)
        let problems = Gate.englishProblems(onDisk: onDisk, entries: entries,
                                            kinds: kinds, pathExempt: pathExempt)
        XCTAssertTrue(problems.isEmpty, "棘轮 B 报红 \(problems.count) 项：\n" + problems.joined(separator: "\n"))
        XCTAssertGreaterThan(onDisk.count, 0, "盘上一个候选都没有 —— 面或判定物坏了（空跑不是通过）")
        print("📏 棘轮 B：白名单 \(entries.count) 条 = 盘上候选 \(onDisk.count) 条")
    }

    // MARK: - 反例（判定物本身：夹具走坏路必须报红）

    /// 多行串里的中文**计入**（原脚本旧版的逐行正则会假绿）；注释里的中文**不计入**（旧版假阳）。
    func testHanLinesCountMultilineAndIgnoreComments() {
        // 行号：1 enum / 2 行注释 / 3 块注释 / 4 多行串开头 / 5-6 两行中文正文 / 7 收口
        //       8 单行串 / 9 行尾注释
        let text = """
        enum Fixture {
            // 注释里的 "保存失败" 不算
            /* 块注释里的 "读取失败" 也不算 */
            static let multi = \"\"\"
            备份工具版本低于服务器：请换用同主版本的客户端工具。
            第二行也是文案。
            \"\"\"
            static let single = "保存失败"
            static let tail = 1 // 行尾注释 "中文"
        }
        """
        let hits = Gate.hanLines(text)
        XCTAssertEqual(hits, [5, 6, 8], "多行串两行 + 单行串一行；实际 \(hits)")
        XCTAssertFalse(hits.contains(2) || hits.contains(3), "注释里的中文不许计入")
        XCTAssertFalse(hits.contains(9), "行尾注释里的中文不许计入")
    }

    /// 英文候选面：`"Home"`（L-109 的原始症状）与多词短语都在面内；SQL 片段因大写下划线不在面内。
    func testEnglishCandidateShape() {
        let files = [
            "Core/Fixture.swift": """
            enum Fixture {
                static let title = "Home"
                static let other = "Untitled Document"
                static let sql = "ALTER TABLE note ADD COLUMN spans TEXT;"
                // static let commented = "Home"
                static let chinese = "保存"
            }
            """,
        ]
        let found = Gate.englishCandidates(files)
        XCTAssertTrue(found.keys.contains("Home"), "Title-case 单词必须进面：\(found.keys.sorted())")
        XCTAssertTrue(found.keys.contains("Untitled Document"), "多词短语必须进面：\(found.keys.sorted())")
        XCTAssertFalse(found.keys.contains("保存"), "含汉字的字面量不进英文面")
        XCTAssertEqual(found["Home"]?.count, 1, "注释行里的字面量不算")
    }

    /// 白名单的三条坏法：死条目（盘上没了）、未分类（`unclassified`）、词表被改。
    func testEnglishLedgerBadStatesAreRed() {
        let onDisk = ["Home": ["Core/Fixture.swift:2"]]
        let clean = Gate.englishProblems(
            onDisk: onDisk,
            entries: ["Home": ["kind": "displayDebt"]],
            kinds: Gate.allowedKinds,
            pathExempt: Set(Gate.englishPathExempt.keys)
        )
        XCTAssertTrue(clean.isEmpty, "对照组应绿：\(clean)")

        let stale = Gate.englishProblems(
            onDisk: onDisk,
            entries: ["Home": ["kind": "displayDebt"], "Ghost Label": ["kind": "sql"]],
            kinds: Gate.allowedKinds,
            pathExempt: Set(Gate.englishPathExempt.keys)
        )
        XCTAssertTrue(stale.contains { $0.hasPrefix("[陈旧]") }, "盘上没有的条目必须报陈旧：\(stale)")

        let pending = Gate.englishProblems(
            onDisk: onDisk,
            entries: ["Home": ["kind": "unclassified"]],
            kinds: Gate.allowedKinds,
            pathExempt: Set(Gate.englishPathExempt.keys)
        )
        XCTAssertTrue(pending.contains { $0.hasPrefix("[未分类]") }, "未分类条目必须报红：\(pending)")

        let fresh = Gate.englishProblems(
            onDisk: onDisk,
            entries: [:],
            kinds: Gate.allowedKinds,
            pathExempt: Set(Gate.englishPathExempt.keys)
        )
        XCTAssertTrue(fresh.contains { $0.hasPrefix("[新增]") }, "白名单外的候选必须报新增：\(fresh)")
    }
}
