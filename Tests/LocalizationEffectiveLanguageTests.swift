import XCTest

/// `check-effective-language.py` 的 Swift 版：**「当前语言」只有一个来源**（队列 L-13）。
///
/// 守的是第 13 轮读图抓到的那类真缺陷：行详情侧栏在中文界面上写着 `Text · 12 characters`
/// —— 渲染点传的是 `LocalizationManager.shared.language`（**用户选择**），而当时的渲染语境是
/// **宿主语言**。修法是把「当前该用哪种语言」收成一个口子 `LocalizationManager.effectiveLanguage`
/// （宿主语境优先，其次用户选择），并把「不许再按用户选择取语言」变成机械判据：
///
/// · `App/` 下（除 `App/LocalizationManager.swift` —— 它就是形成这个值的那个文件）不得出现
///   「按用户选择取语言」的写法：**接收者**是 `LocalizationManager.shared`、或任何**绑定到它的名字**
///   （`let x = LocalizationManager.shared` / `@StateObject` / `@ObservedObject` /
///   `@EnvironmentObject … LocalizationManager` / `@Environment(LocalizationManager.self) …`），
///   后接 `.language`；
/// · 三个**合法例外**逐条写明理由（系统菜单是进程级的、根视图 `.id` 是重建视图树用的、
///   菜单勾选态问的就是用户选了什么），且例外表**反向对账**（文件里没这种写法了 ⇒ 陈旧 ⇒ 红）；
/// · 判定物是**代码面**（剥注释与字符串字面量、插值体算代码），并把「与点号相邻的空白（含换行）」
///   抹掉 ⇒ 跨行链与 `LocalizationManager .shared .language` 回到同一形状；
/// · 口子本身必须在（`var effectiveLanguage: AppLanguage` 被改名 / 删掉要当场说清）；
/// · 空跑防护：面为空判红。
final class LocalizationEffectiveLanguageTests: XCTestCase {

    enum Gate {
        static let scanRoot = "App"
        static let definitionFile = "App/LocalizationManager.swift"
        static let languageType = "LocalizationManager"
        static let receiverSelf = "LocalizationManager.shared"
        /// 旧口径写死的接收者名保留为兜底（接收者在别的文件里声明时类型发现看不到绑定）。
        static let knownReceiverNames = ["localization"]

        /// 合法例外：文件 → 理由。每条都反向对账。
        static let allowed: [String: String] = [
            "App/MainMenuLocalizer.swift": "改的是 AppKit 系统菜单（进程级系统界面）：按用户选择 / 启动语言改写 NSMenuItem.title，不跟渲染语境",
            "App/DoyahStudioApp.swift": "根部 `.id(localization.language)`：用户改语言时用它整体重建视图树，不是拿它当「当前渲染语言」",
            "App/DoyahStudioCommands.swift": "菜单勾选态：问的就是「用户选的是哪种语言」",
        ]

        static let requiredDeclaration = "App/LocalizationManager.swift"

        struct Flattened {
            var text: String
            var lines: [Int]
        }

        /// 判定物 ①：剥注释与字符串字面量（插值体算代码）
        static func codeFace(_ source: String) -> String {
            SwiftSource(source).codeText
        }

        /// 判定物 ②：抹掉「与点号相邻的空白（含换行）」⇒ 跨行链归一。
        static func flatten(_ text: String) -> Flattened {
            let masked = Array(codeFace(text))
            var lineOf: [Int] = []
            lineOf.reserveCapacity(masked.count)
            var line = 1
            for character in Array(text) {
                lineOf.append(line)
                if character == "\n" { line += 1 }
            }
            var out: [Character] = []
            var lines: [Int] = []
            var index = 0
            while index < masked.count {
                let character = masked[index]
                if " \t\n".contains(character) {
                    var next = index
                    while next < masked.count && " \t\n".contains(masked[next]) { next += 1 }
                    let previous = out.last ?? " "
                    let following = next < masked.count ? masked[next] : " "
                    if previous == "." || following == "." {
                        index = next
                        continue
                    }
                }
                out.append(character)
                lines.append(index < lineOf.count ? lineOf[index] : 1)
                index += 1
            }
            return Flattened(text: String(out), lines: lines)
        }

        /// 本文件里「按用户选择取语言」的接收者：类型自身 + 绑定到它的名字。
        static func receivers(_ code: String) -> [String] {
            var names: Set<String> = [receiverSelf]
            names.formUnion(knownReceiverNames)
            let patterns = [
                #"\b(?:let|var)\s+([A-Za-z_]\w*)\s*(?:[ \t]*:[^\n=]+)?=[ \t]*LocalizationManager\.shared\b(?!\.)"#,
                #"@EnvironmentObject\s+(?:(?:private|internal|fileprivate|public)\s+)?var\s+([A-Za-z_]\w*)[ \t]*:[ \t]*LocalizationManager\b"#,
                #"@Environment\s*\(\s*LocalizationManager\.self\s*\)\s*(?:(?:private|internal|fileprivate|public)\s+)?var\s+([A-Za-z_]\w*)"#,
            ]
            for pattern in patterns {
                guard let regex = LScan.regex(pattern) else { continue }
                let ns = code as NSString
                for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                    names.insert(ns.substring(with: match.range(at: 1)))
                }
            }
            return names.sorted()
        }

        /// [(行号, `接收者.language`)]，同处去重。
        static func forbiddenHits(_ flattened: Flattened, names: [String]) -> [(Int, String)] {
            let alternation = names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            guard let regex = LScan.regex("(?:" + alternation + ")\\.language\\b") else { return [] }
            var hits: [(Int, String)] = []
            let ns = flattened.text as NSString
            for match in regex.matches(in: flattened.text, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: match.range)
                let line = match.range.location < flattened.lines.count ? flattened.lines[match.range.location] : 1
                if !hits.contains(where: { $0.0 == line && $0.1 == label }) {
                    hits.append((line, label))
                }
            }
            return hits
        }

        struct Reading {
            var scanned = 0
            var hits: [String: [String]] = [:]
            var problems: [String] = []
        }

        static func scan(_ files: [String: String], allowed: [String: String], fileExists: (String) -> Bool) -> Reading {
            var reading = Reading()
            for relative in files.keys.sorted() where relative.hasPrefix(scanRoot + "/") && relative.hasSuffix(".swift") {
                if relative == definitionFile { continue }
                reading.scanned += 1
                let flattened = flatten(files[relative] ?? "")
                for (line, label) in forbiddenHits(flattened, names: receivers(flattened.text)) {
                    reading.hits[relative, default: []].append("\(line):\(label)")
                    if allowed[relative] == nil {
                        reading.problems.append("\(relative):\(line) 用了 `\(label)` 当作「当前语言」 —— "
                                                + "请改用 `LocalizationManager.shared.effectiveLanguage`（宿主语境优先）")
                    }
                }
            }
            if reading.scanned == 0 {
                reading.problems.append("\(scanRoot)/ 下没扫到任何 .swift（除定义文件）—— 面为空，判据无意义")
            }
            for (relative, reason) in allowed.sorted(by: { $0.key < $1.key }) {
                if !fileExists(relative) {
                    reading.problems.append("例外表里的文件不存在：\(relative)（理由：\(reason)）")
                } else if reading.hits[relative] == nil {
                    reading.problems.append("\(relative)：例外条目陈旧 —— 这个文件里已经没有按用户选择取语言的写法了，请从 ALLOWED 里删掉它")
                }
            }
            return reading
        }
    }

    // MARK: - 真仓库判据

    func testCurrentLanguageHasASingleSource() throws {
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles([Gate.scanRoot]) {
            files[relative] = try LRepo.text(relative)
        }
        let reading = Gate.scan(files, allowed: Gate.allowed, fileExists: { LRepo.exists($0) })
        XCTAssertTrue(reading.problems.isEmpty,
                      "语言来源报红 \(reading.problems.count) 项：\n" + reading.problems.joined(separator: "\n"))
        let declared = LRepo.textIfExists(Gate.requiredDeclaration) ?? ""
        let flattened = Gate.flatten(declared)
        XCTAssertTrue(
            LScan.regex(#"\bvar\s+effectiveLanguage\s*:\s*AppLanguage\b"#)?.firstMatch(
                in: flattened.text, range: NSRange(location: 0, length: (flattened.text as NSString).length)) != nil,
            "\(Gate.requiredDeclaration)：找不到 `var effectiveLanguage: AppLanguage` —— 本判据守的那个口子被改名或删掉了")
        print("📏 语言来源：扫描面 \(reading.scanned) 个 .swift；命中文件 \(reading.hits.keys.sorted())")
    }

    // MARK: - 反例（夹具走坏路必须报红）

    func testUserSelectionReadIsRed() {
        let files = [
            "App/Views/Fixture.swift": """
            struct Fixture: View {
                @ObservedObject private var localization = LocalizationManager.shared
                var body: some View { Text(FixtureCopy.title(localization.language)) }
            }
            """,
            "App/Other.swift": """
            func render() -> String { FixtureCopy.title(LocalizationManager.shared.language) }
            """,
        ]
        let reading = Gate.scan(files, allowed: [:], fileExists: { _ in true })
        XCTAssertEqual(reading.problems.count, 2, "两处都要点名：\(reading.problems)")
        XCTAssertTrue(reading.problems.contains { $0.contains("App/Views/Fixture.swift:3") })
        XCTAssertTrue(reading.problems.contains { $0.contains("App/Other.swift:1") })
    }

    /// 判定物必须是代码面：注释里 / 字符串里写一遍不算（旧实现的两种假红）。
    func testCommentAndStringMentionsAreNotHits() {
        let files = [
            "App/Views/Fixture.swift": """
            // 以前这里写过 LocalizationManager.shared.language
            /* 块注释：localization.language */
            let sample = "LocalizationManager.shared.language"
            let good = LocalizationManager.shared.effectiveLanguage
            """,
        ]
        let reading = Gate.scan(files, allowed: [:], fileExists: { _ in true })
        XCTAssertTrue(reading.problems.isEmpty, "注释与字符串里的不算：\(reading.problems)")
    }

    /// 绑定发现的三形（`@StateObject` / `@EnvironmentObject` / `@Environment(...self)`）+ 跨行链归一。
    func testBindingsAndLineWrappedChainsAreCaught() {
        let files = [
            "App/A.swift": """
            struct A: View {
                @EnvironmentObject private var loc: LocalizationManager
                var body: some View { Text(loc.language.rawValue) }
            }
            """,
            "App/B.swift": """
            struct B: View {
                @Environment(LocalizationManager.self) private var manager
                var body: some View { Text(manager.language.rawValue) }
            }
            """,
            "App/C.swift": """
            struct C {
                func text() -> String {
                    LocalizationManager
                        .shared
                        .language
                        .rawValue
                }
            }
            """,
        ]
        let reading = Gate.scan(files, allowed: [:], fileExists: { _ in true })
        XCTAssertEqual(reading.problems.count, 3, "三形都要抓到：\(reading.problems)")
    }

    /// 例外表反向对账：文件里已经没有这种写法 ⇒ 陈旧 ⇒ 红；面为空 ⇒ 红。
    func testStaleExceptionAndEmptyFaceAreRed() {
        let stale = Gate.scan(["App/Clean.swift": "let x = 1\n"],
                             allowed: ["App/Clean.swift": "夹具：陈旧例外"],
                             fileExists: { _ in true })
        XCTAssertTrue(stale.problems.contains { $0.contains("例外条目陈旧") }, "陈旧例外必须判红：\(stale.problems)")

        let empty = Gate.scan([:], allowed: [:], fileExists: { _ in true })
        XCTAssertTrue(empty.problems.contains { $0.contains("面为空") }, "面为空必须判红：\(empty.problems)")
    }
}
