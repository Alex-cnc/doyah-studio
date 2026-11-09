import XCTest

/// `check-copy-emphasis.py` 的 Swift 版：**「文案即所见」**（队列 L-19）。
///
/// 判的是两件事，外加两条防静默、两条对账：
///
/// · **A 文案层**：语言表（`Core/Localization.swift` 的 `LocalizedStrings.table`）每个条目的
///   **两种语言槽位**都不许含 markdown 强调标 `**`（`***` 密码掩码按键登记例外）；
/// · **B 渲染层**：产品源文件里不许再出现 `LocalizedStringKey`（口径只剩纯文本一种）；
///   判定物是**代码面** —— 注释与字符串字面量先抹掉（旧实现只跳整行注释 ⇒ 行尾注释 / 块注释 /
///   字符串三处假红）；
/// · **C 防静默**：解析出的条目数不得低于下限，且**语言槽位必须全部落在条目里**
///   （全文件槽位命中数 ≠ 条目数 ⇒ 有条目形状落在判定物之外 ⇒ 点名报红，而不是少算几条还判绿）；
/// · **D 例外两端对账**：marker 例外键必须在表里且**仍含**登记的标记、必须写理由；
///   renderer 例外文件必须存在且**仍在使用** `LocalizedStringKey`（否则陈旧）；
/// · **E 接线**：本族判据必须在闭环里真的跑到 —— 原脚本判的是「`verify-all.sh` 的非注释行里
///   有 `check-copy-emphasis.py` 与它的负例」。判据搬进 `swift test` 之后，等价物是
///   「`verify-all.sh` 仍跑 `verify-core.sh`（那一步跑的是 `swift test`）」+「旧脚本已摘除」；
/// · **F 面不许写死**：`FACE_DIRS` 与 `Package.swift` 的**生产** target `path:`/`sources:`
///   双向对账（派生出的生产 root 未纳入面 / 面里的根不是生产 root / 生产 target 没声明路径 /
///   根不在盘 / 面为空 ⇒ 判红）。
final class LocalizationCopyGateTests: XCTestCase {

    enum Gate {
        /// 判据 B 的面。**2026-11-09 搬进 swift test 时按 `Package.swift` 的实测补了 Retro 三根**
        /// （`Plugins/Retro/{Sources,Views,CLI}`）—— 原脚本的 F 判据当时是红的（面与生产 target 脱钩）。
        static let faceDirs = [
            "App", "CLI", "Core", "Platform",
            "Plugins/Notes/Sources", "Plugins/Notes/Views",
            "Plugins/Retro/Sources", "Plugins/Retro/Views", "Plugins/Retro/CLI",
            "Tools/LicenseTool",
        ]
        static let tableFile = "Core/Localization.swift"
        static let exemptions = "Scripts/copy-emphasis-exemptions.json"
        static let verifyAll = "Scripts/verify-all.sh"
        static let marker = "**"
        /// 判据 C 的下限：2026-10-14 实测 2069 条；取 1500 留余量（真正的防静默靠槽位对账）。
        static let minTableEntries = 1500
        /// 接线锚点：`swift test`（新判据的跑法）必须在闭环里被真的调到。
        static let wiringAnchor = "./Scripts/verify-core.sh"

        // MARK: - 判据 A / C

        typealias TableReading = LanguageTable.Parsed

        static func tableReading(_ text: String) -> TableReading {
            LanguageTable.parse(text)
        }

        /// 判据 A：文案层不许有 `**`（marker 例外键除外）。
        static func markerProblems(entries: [LocalizedEntry], exemptKeys: Set<String>) -> [String] {
            var problems: [String] = []
            for entry in entries {
                for (language, value) in [("zh", entry.zh), ("en", entry.en)] {
                    guard value.contains(marker) else { continue }
                    if exemptKeys.contains(entry.key) { continue }
                    problems.append("\(tableFile):\(entry.line)：键 `\(entry.key)` 的 \(language) 槽位里有 `\(marker)` —— "
                                    + "标记会照字面显示在纯文本渲染点上")
                }
            }
            return problems
        }

        /// 判据 C：条目数下限 + 槽位对账 + 解析不出的候选逐条点名。
        static func silentProblems(_ reading: TableReading) -> [String] {
            var problems: [String] = []
            if reading.entries.count < minTableEntries {
                problems.append("\(tableFile)：只解析出 \(reading.entries.count) 条（下限 \(minTableEntries)）")
            }
            if reading.entries.isEmpty {
                problems.append("\(tableFile)：一条条目都没解析出来 —— 零命中不是通过")
            }
            for language in [LanguageTable.slots.0, LanguageTable.slots.1] {
                let count = reading.slotCounts[language] ?? 0
                if count != reading.entries.count {
                    problems.append("\(tableFile)：语言槽位 `.\(language)` 全文件命中 \(count) 处，"
                                    + "而条目解析出 \(reading.entries.count) 条 —— 有条目形状落在判定物之外")
                }
            }
            problems.append(contentsOf: reading.unparsed.map { $0 + " —— 条目形状落进判定物之外：修判定物，不许整条跳过" })
            return problems
        }

        // MARK: - 判据 B

        /// 面内出现 `LocalizedStringKey` 的（文件 → 行号）。判定物 = 代码面。
        static func renderSites(_ files: [String: String], face: [String], exemptions: Set<String>) -> [String: [Int]] {
            var hits: [String: [Int]] = [:]
            for relative in files.keys.sorted() where face.contains(where: {
                relative == $0 || relative.hasPrefix($0 + "/")
            }) {
                let code = SwiftSource(files[relative] ?? "").codeText
                for (index, line) in code.components(separatedBy: "\n").enumerated() where line.contains("LocalizedStringKey") {
                    hits[relative, default: []].append(index + 1)
                }
            }
            return hits
        }

        // MARK: - 判据 D

        struct ExemptPayload {
            var marker: [(key: String, marker: String, reason: String)] = []
            var renderer: [(file: String, reason: String)] = []
        }

        static func loadExemptions(_ payload: [String: Any]) -> ExemptPayload {
            var result = ExemptPayload()
            for item in (payload["markerExemptions"] as? [[String: Any]]) ?? [] {
                result.marker.append((LRepo.string(item["key"]), LRepo.string(item["marker"]), LRepo.string(item["reason"])))
            }
            for item in (payload["rendererExemptions"] as? [[String: Any]]) ?? [] {
                result.renderer.append((LRepo.string(item["file"]), LRepo.string(item["reason"])))
            }
            return result
        }

        /// 判据 D：两个方向都判（登记项必须仍成立；没理由 ⇒ 红）。
        static func exemptionProblems(
            _ payload: ExemptPayload,
            entries: [LocalizedEntry],
            renderHits: [String: [Int]],
            fileExists: (String) -> Bool
        ) -> [String] {
            var problems: [String] = []
            let keyed = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
            for item in payload.marker where item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("\(exemptions)：例外条目 `\(item.key)` 没有写理由")
            }
            for item in payload.renderer where item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("\(exemptions)：例外条目 `\(item.file)` 没有写理由")
            }
            for item in payload.marker {
                guard let entry = keyed[item.key] else {
                    problems.append("\(exemptions)：marker 例外 `\(item.key)` 在语言表里不存在（陈旧条目）")
                    continue
                }
                if !item.marker.isEmpty, !(entry.zh + entry.en).contains(item.marker) {
                    problems.append("\(exemptions)：marker 例外 `\(item.key)` 登记的形态 `\(item.marker)` 已不在这条文案里")
                }
            }
            for item in payload.renderer {
                if !fileExists(item.file) {
                    problems.append("\(exemptions)：renderer 例外 `\(item.file)` 这个文件不存在")
                } else if renderHits[item.file] == nil {
                    problems.append("\(exemptions)：renderer 例外 `\(item.file)` 条目陈旧 —— 这个文件里已经没有 `LocalizedStringKey` 了")
                }
            }
            return problems
        }

        // MARK: - 判据 F

        static func faceProblems(packageText: String?,
                                 declared: [String],
                                 exists: (String) -> Bool,
                                 scanned: Int) -> [String] {
            var problems: [String] = []
            guard let packageText else {
                problems.append("找不到 Package.swift —— 判据 B 的面无从派生")
                return problems
            }
            let derived = ProductionFace.derive(packageText)
            for name in derived.undeclared {
                problems.append("[F] \(ProductionFace.package)：生产 target `\(name)` 既没声明 `path:` 也没声明 `sources:`")
            }
            for root in derived.face where !declared.contains(where: { ProductionFace.covers($0, root) }) {
                problems.append("[F] \(ProductionFace.package)：生产 root `\(root)` 不在判据 B 的面内"
                                + "（\(declared.joined(separator: ", "))）")
            }
            for entry in declared where !derived.face.contains(where: { ProductionFace.covers(entry, $0) }) {
                problems.append("[F] 面里的根 `\(entry)` 已不是 \(ProductionFace.package) 的生产 root（死条目）")
            }
            for entry in declared where !exists(entry) {
                problems.append("[F] 面里的根 `\(entry)` 在盘上不存在")
            }
            if scanned == 0 {
                problems.append("[F] 判据 B 的面里一份 `.swift` 都没有 —— 空跑不是通过")
            }
            return problems
        }

        // MARK: - 判据 E

        /// shell 的「代码面」：`#` 起的注释抹成空格（单 / 双引号里的 `#` 不算）。
        /// 不许拿 C 风格的剥注释代用：shell 的 glob（`Scripts/*`）会被当成 `/*` 块注释开头。
        static func maskShellComments(_ text: String) -> String {
            var out = Array(text)
            var quote: Character?
            var index = 0
            let chars = Array(text)
            while index < chars.count {
                let char = chars[index]
                if let current = quote {
                    if char == "\\", current == "\"" { index += 2; continue }
                    if char == current { quote = nil }
                    index += 1
                    continue
                }
                if char == "'" || char == "\"" { quote = char; index += 1; continue }
                if char == "#" {
                    var stop = index
                    while stop < chars.count && chars[stop] != "\n" { stop += 1 }
                    for k in index..<stop { out[k] = " " }
                    index = stop
                    continue
                }
                index += 1
            }
            return String(out)
        }

        static func wiringProblems(verifyAllText: String?) -> [String] {
            guard let verifyAllText else { return ["找不到 \(verifyAll) —— 判据 E 无从下手"] }
            var problems: [String] = []
            let script = maskShellComments(verifyAllText)
            if !script.contains(wiringAnchor) {
                problems.append("\(verifyAll) 的非注释行里没有 `\(wiringAnchor)` —— 本族判据没接进闭环（有判据、没闭环）")
            }
            if script.contains("check-copy-emphasis.py") {
                problems.append("\(verifyAll) 仍在调已摘除的 `check-copy-emphasis.py` —— 摘除没做完")
            }
            return problems
        }
    }

    // MARK: - 真仓库判据

    func testLanguageTableHasNoMarkdownMarker() throws {
        let reading = LanguageTable.real
        let payload = try LRepo.json(Gate.exemptions)
        let parsed = Gate.loadExemptions(payload)
        let problems = Gate.markerProblems(entries: reading.entries, exemptKeys: Set(parsed.marker.map(\.key)))
        XCTAssertTrue(problems.isEmpty, "判据 A 报红 \(problems.count) 项：\n" + problems.joined(separator: "\n"))
        print("📏 文案层：解析出 \(reading.entries.count) 条，标记命中 0（marker 例外 \(parsed.marker.count) 条）")
    }

    func testLanguageTableParsingIsComplete() throws {
        let reading = LanguageTable.real
        let problems = Gate.silentProblems(reading)
        XCTAssertTrue(problems.isEmpty, "判据 C 报红 \(problems.count) 项：\n" + problems.joined(separator: "\n"))
        print("📏 槽位对账：.\(LanguageTable.slots.0) \(reading.slotCounts[LanguageTable.slots.0] ?? 0) 处 / "
              + ".\(LanguageTable.slots.1) \(reading.slotCounts[LanguageTable.slots.1] ?? 0) 处"
              + " == 条目 \(reading.entries.count) 条")
    }

    func testProductSourcesHaveNoLocalizedStringKey() throws {
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles(Gate.faceDirs) {
            files[relative] = try LRepo.text(relative)
        }
        let payload = try LRepo.json(Gate.exemptions)
        let parsed = Gate.loadExemptions(payload)
        let exemptFiles = Set(parsed.renderer.map(\.file))
        let hits = Gate.renderSites(files, face: Gate.faceDirs, exemptions: exemptFiles)
        let offending = hits.filter { !exemptFiles.contains($0.key) }
        XCTAssertTrue(offending.isEmpty,
                      "判据 B 报红：\(offending.map { "\($0.key):\($0.value)" })")
        XCTAssertFalse(files.isEmpty, "面里一份 `.swift` 都没有 —— 空跑不是通过")
        print("📏 渲染层：面 \(Gate.faceDirs.count) 个源根 / \(files.count) 份 .swift，"
              + "代码面命中 \(hits.count) 处（登记例外 \(exemptFiles.count) 个文件）")
    }

    func testFaceIsDerivedFromPackageTargets() throws {
        let package = LRepo.textIfExists(ProductionFace.package)
        let scanned = LRepo.swiftFiles(Gate.faceDirs).count
        let problems = Gate.faceProblems(packageText: package, declared: Gate.faceDirs,
                                         exists: { LRepo.exists($0) }, scanned: scanned)
        XCTAssertTrue(problems.isEmpty, "判据 F 报红 \(problems.count) 项：\n" + problems.joined(separator: "\n"))
        print("📏 面：\(Gate.faceDirs.count) 个声明根 / \(scanned) 份 .swift/"
              + "Package.swift 派生 \(ProductionFace.derive(package ?? "").face.count) 个生产 root")
    }

    func testExemptionsAreReconciledBothWays() throws {
        let reading = LanguageTable.real
        let payload = try LRepo.json(Gate.exemptions)
        let parsed = Gate.loadExemptions(payload)
        var files: [String: String] = [:]
        for relative in LRepo.swiftFiles(Gate.faceDirs) { files[relative] = try LRepo.text(relative) }
        let hits = Gate.renderSites(files, face: Gate.faceDirs, exemptions: Set(parsed.renderer.map(\.file)))
        let problems = Gate.exemptionProblems(parsed, entries: reading.entries, renderHits: hits,
                                              fileExists: { LRepo.exists($0) })
        XCTAssertTrue(problems.isEmpty, "判据 D 报红 \(problems.count) 项：\n" + problems.joined(separator: "\n"))
    }

    func testGateIsWiredIntoTheClosure() throws {
        let problems = Gate.wiringProblems(verifyAllText: LRepo.textIfExists(Gate.verifyAll))
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    // MARK: - 反例（夹具走坏路必须报红）

    /// 中文槽位塞 `**` ⇒ 判据 A 红；登记的 marker 例外键放行。
    func testMarkerInChineseSlotIsRed() {
        let table = """
        enum Fixture {
            static let table: [LKey: [AppLanguage: String]] = [
                .plain: [.simplifiedChinese: "纯文本", .english: "Plain"],
                .emphasized: [.simplifiedChinese: "**四条判据全满足**才列进候选", .english: "Only when **all four** hold"],
                .masked: [.simplifiedChinese: "密码写成 ***", .english: "password as ***"],
            ]
        }
        """
        let reading = Gate.tableReading(table)
        XCTAssertEqual(reading.entries.count, 3, "三条条目都要解析出来：\(reading.unparsed)")
        let problems = Gate.markerProblems(entries: reading.entries, exemptKeys: ["masked"])
        XCTAssertEqual(problems.count, 2, "两条带 `**` 的槽位都要点名（zh / en 各一条），实际：\(problems)")
        XCTAssertTrue(problems.allSatisfy { $0.contains("emphasized") }, "例外的 `masked` 不许报：\(problems)")
    }

    /// 语言槽位缺一条 / 多一段形状外的东西 ⇒ 判据 C 点名，而不是「少算几条还判绿」。
    func testEntryShapeOutsideTheJudgeIsNamed() {
        let table = """
        enum Fixture {
            static let table: [LKey: [AppLanguage: String]] = [
                .complete: [.simplifiedChinese: "完整", .english: "Complete"],
                .half: [.simplifiedChinese: "只有中文"],
            ]
        }
        """
        let reading = Gate.tableReading(table)
        XCTAssertEqual(reading.entries.count, 1)
        XCTAssertEqual(reading.unparsed.count, 1, "缺 english 的条目要被点名：\(reading.unparsed)")
        let problems = Gate.silentProblems(reading)
        XCTAssertTrue(problems.contains { $0.contains("槽位") }, "槽位对账必须报落差：\(problems)")
    }

    /// `LocalizedStringKey` 出现在**代码面** ⇒ 红；只出现在注释 / 字符串里 ⇒ 不算（旧实现的三处假红）。
    func testLocalizedStringKeyOnlyCountsInCode() {
        let files = [
            "App/Views/Fixture.swift": """
            // 以前这里用 LocalizedStringKey(...)
            /* 块注释也提一句 LocalizedStringKey */
            let sample = "LocalizedStringKey 是字符串里的"
            Text(L(.fixtureKey))
            """,
            "App/Views/Real.swift": """
            Text(LocalizedStringKey(L(.fixtureKey)))
            """,
        ]
        let hits = Gate.renderSites(files, face: ["App"], exemptions: [])
        XCTAssertNil(hits["App/Views/Fixture.swift"], "注释与字符串里的不算：\(hits)")
        XCTAssertEqual(hits["App/Views/Real.swift"], [1], "代码面命中要点名行号：\(hits)")
    }

    /// 面与 `Package.swift` 脱钩的两种坏法：派生出的新生产 root 不在面内 / 面里的根不再是生产 root。
    func testFaceDriftIsRed() {
        let package = """
        // swift-tools-version: 5.10
        let package = Package(
            name: "Fixture",
            targets: [
                .target(name: "FixtureCore", path: ".", sources: ["Core"]),
                .executableTarget(name: "FixtureApp", path: "App"),
                .testTarget(name: "FixtureTests", path: "Tests"),
            ]
        )
        """
        let missing = Gate.faceProblems(packageText: package, declared: ["App"], exists: { _ in true }, scanned: 3)
        XCTAssertTrue(missing.contains { $0.contains("`Core` 不在判据 B 的面内") }, "新生产 root 必须判红：\(missing)")

        let dead = Gate.faceProblems(packageText: package, declared: ["App", "Core", "Retired"],
                                     exists: { _ in true }, scanned: 3)
        XCTAssertTrue(dead.contains { $0.contains("`Retired` 已不是") }, "死条目必须判红：\(dead)")

        let undeclared = Gate.faceProblems(
            packageText: "let package = Package(targets: [.target(name: \"Mystery\")])",
            declared: ["App"], exists: { _ in true }, scanned: 3)
        XCTAssertTrue(undeclared.contains { $0.contains("既没声明") }, "没声明路径的生产 target 必须判红：\(undeclared)")
    }

    /// 接线：闭环里没跑 `swift test` / 仍在调已摘除的旧脚本 ⇒ 红。
    func testWiringDriftIsRed() {
        XCTAssertTrue(Gate.wiringProblems(verifyAllText: "swift build\n").contains { $0.contains("没接进闭环") })
        XCTAssertTrue(Gate.wiringProblems(verifyAllText: "./Scripts/verify-core.sh\npython3 Scripts/check-copy-emphasis.py\n")
                        .contains { $0.contains("已摘除") })
        XCTAssertTrue(Gate.wiringProblems(verifyAllText: "# ./Scripts/verify-core.sh\n").contains { $0.contains("没接进闭环") },
                      "注释掉的那一行不算接线")
        XCTAssertTrue(Gate.wiringProblems(verifyAllText: "./Scripts/verify-core.sh\n").isEmpty)
    }
}
