import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-012` 的九个显示开关 —— 契约面判据。
///
/// 契约表在概设 §8.9 ⑤（键 / 默认 / 取值域 / 契约四列），需求书给四条验收要点：
/// ① 改完立即生效且重启后保持；② 关掉思考段时零占位；③ 关掉时间戳时行首栏宽度不变；
/// ④ 键名 / 默认值 / 取值域三样与契约一致。几何那两条在 `AgentDisplayRowsTests`，
/// 这里管「三样一致」与落盘 / 拒绝。
final class AgentDisplayPreferencesTests: XCTestCase {

    // MARK: - 契约表（夹具：逐字抄自概设 §8.9 ⑤，九行 + 一行固定关）

    private struct ContractRow {
        var key: AgentDisplayKey
        var defaultValue: String
        var allowed: String
    }

    private var contractTable: [ContractRow] {
        [
            .init(key: .streaming, defaultValue: "on", allowed: "on|off"),
            .init(key: .compact, defaultValue: "off", allowed: "on|off"),
            .init(key: .thinking, defaultValue: "off", allowed: "on|off"),
            .init(key: .timestamps, defaultValue: "off", allowed: "on|off"),
            .init(key: .toolProgress, defaultValue: "all", allowed: "all|summary|off"),
            .init(key: .indicatorGlyph, defaultValue: "emoji", allowed: "emoji|unicode|ascii"),
            .init(key: .longPreview, defaultValue: "2+2", allowed: "off|H+T (1...20)"),
            .init(key: .bottomBarMeta, defaultValue: "off", allowed: "on|off"),
            .init(key: .submitWhileRunning, defaultValue: "interrupt", allowed: "interrupt|queue"),
        ]
    }

    // MARK: - 正常路径

    /// ④ 默认值逐项对契约表（含「花费显示」不是开关这一条）。
    func testDefaultsMatchContractTable() {
        let defaults = AgentDisplayPreferences()
        for row in contractTable {
            XCTAssertEqual(defaults.canonicalValue(for: row.key), row.defaultValue,
                           "默认值与契约表不符：\(row.key.rawValue)")
        }
        // 契约把「花费显示」定成**固定关、不设开关**：第九个之外不许有第十个键。
        XCTAssertEqual(AgentDisplayKey.allCases.count, 9, "九个显示开关 —— 契约是九，不是十")
        XCTAssertFalse(AgentDisplayKey.allCases.contains { $0.rawValue.contains("spending") },
                       "花费显示不设开关（契约：固定关）")
        XCTAssertFalse(AgentDisplayPreferences.spendingDisplayEnabled, "花费显示恒关")
    }

    /// ④ 键名与取值域逐项对契约表；且每个键的取值域**每个值都真能写进去**。
    func testKeysAndValueDomainsMatchContract() {
        for row in contractTable {
            XCTAssertEqual(AgentDisplayPreferences.allowedValues(for: row.key), row.allowed,
                           "取值域与契约表不符：\(row.key.rawValue)")
        }
        // 键名集合逐字钉住（跨端一致性：别端读同一组字面量）。
        let expectedKeys = [
            "display.streaming", "display.compact", "display.thinking", "display.timestamps",
            "display.toolProgress", "display.indicatorGlyph", "display.longPreview",
            "display.bottomBarMeta", "display.submitWhileRunning",
        ]
        XCTAssertEqual(AgentDisplayKey.allCases.map(\.rawValue), expectedKeys)

        // 取值域里的每个值都能落地，且落地后读回来就是它（无静默夹值）。
        for value in AgentToolProgressMode.allCases {
            var preferences = AgentDisplayPreferences()
            XCTAssertNoThrow(try preferences.apply(key: AgentDisplayKey.toolProgress.rawValue, value: value.rawValue))
            XCTAssertEqual(preferences.toolProgress, value)
        }
        for value in AgentIndicatorGlyph.allCases {
            var preferences = AgentDisplayPreferences()
            XCTAssertNoThrow(try preferences.apply(key: AgentDisplayKey.indicatorGlyph.rawValue, value: value.rawValue))
            XCTAssertEqual(preferences.indicatorGlyph, value)
        }
        for value in AgentSubmitWhileRunning.allCases {
            var preferences = AgentDisplayPreferences()
            XCTAssertNoThrow(try preferences.apply(key: AgentDisplayKey.submitWhileRunning.rawValue, value: value.rawValue))
            XCTAssertEqual(preferences.submitWhileRunning, value)
        }
        // 布尔五键：开 / 关都写进去。
        for key in [AgentDisplayKey.streaming, .compact, .thinking, .timestamps, .bottomBarMeta] {
            var on = AgentDisplayPreferences()
            try? on.apply(key: key.rawValue, value: "on")
            XCTAssertEqual(on.canonicalValue(for: key), "on")
            try? on.apply(key: key.rawValue, value: "off")
            XCTAssertEqual(on.canonicalValue(for: key), "off")
            // 盘上 / 手改出来的 `true` `false` 与 `on` `off` 是同一件事（不因此把整份降级）。
            try? on.apply(key: key.rawValue, value: "TRUE")
            XCTAssertEqual(on.canonicalValue(for: key), "on", "大小写不敏感")
        }
    }

    /// ①「重启后保持」：存了什么读回什么（九项逐项）。
    func testRoundTripKeepsEverySwitch() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)

        var preferences = AgentDisplayPreferences()
        try preferences.applyBatch([
            (AgentDisplayKey.streaming.rawValue, "off"),
            (AgentDisplayKey.compact.rawValue, "on"),
            (AgentDisplayKey.thinking.rawValue, "on"),
            (AgentDisplayKey.timestamps.rawValue, "on"),
            (AgentDisplayKey.toolProgress.rawValue, "summary"),
            (AgentDisplayKey.indicatorGlyph.rawValue, "ascii"),
            (AgentDisplayKey.longPreview.rawValue, "3+5"),
            (AgentDisplayKey.bottomBarMeta.rawValue, "on"),
            (AgentDisplayKey.submitWhileRunning.rawValue, "queue"),
        ])
        try file.save(preferences)

        let loaded = file.load()
        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertEqual(loaded.preferences, preferences, "九项往返必须逐项一致")
    }

    /// 一次改多项的原子性：第三项非法 ⇒ 前两项**也不许**留在内存里。
    func testBatchApplyIsAtomic() {
        var preferences = AgentDisplayPreferences()
        XCTAssertThrowsError(try preferences.applyBatch([
            (AgentDisplayKey.compact.rawValue, "on"),
            (AgentDisplayKey.thinking.rawValue, "on"),
            (AgentDisplayKey.toolProgress.rawValue, "verbose"),
        ]))
        XCTAssertEqual(preferences, AgentDisplayPreferences(),
                       "批量被拒之后不许留下半套新值")
    }

    // MARK: - 该拒的

    /// 未知键 / 取值域外的值都要**抛错**（静默夹成默认值等于谎报「保存成功」）。
    func testRejectsUnknownKeyAndOutOfDomainValues() {
        var preferences = AgentDisplayPreferences()
        XCTAssertThrowsError(try preferences.apply(key: "display.nope", value: "on")) { error in
            XCTAssertEqual(error as? AgentDisplayError, .unknownKey("display.nope"))
        }
        // 每个枚举键各来一个域外值（含空串与带杂字符的）。
        XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.toolProgress.rawValue, value: "verbose"))
        XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.toolProgress.rawValue, value: ""))
        XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.indicatorGlyph.rawValue, value: "emoji!"))
        XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.submitWhileRunning.rawValue, value: "both"))
        XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.streaming.rawValue, value: "maybe"))
        // 被拒之后一个字段都没变。
        XCTAssertEqual(preferences, AgentDisplayPreferences(), "被拒的写入不许改到任何一项")
    }

    /// 取值域边界：行数对 1+1 与 20+20 收，0+2 / 21+21 / 2x2 / 空 都不收。
    func testLongPreviewBoundaries() {
        var preferences = AgentDisplayPreferences()
        for value in ["1+1", "20+20", "2+2", "off"] {
            XCTAssertNoThrow(try preferences.apply(key: AgentDisplayKey.longPreview.rawValue, value: value),
                             "\(value) 该被接受")
        }
        for value in ["0+2", "2+0", "21+21", "2x2", "", "+", "2+", "+2", "-1+2"] {
            XCTAssertThrowsError(try preferences.apply(key: AgentDisplayKey.longPreview.rawValue, value: value),
                                 "\(value) 该被拒绝")
        }
    }

    // MARK: - 降级（如实、点名）

    /// 盘上没有这份文件 ⇒ 全新 + 契约默认（不是「降级」，别报错吓人）。
    func testMissingFileIsFreshWithContractDefaults() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = AgentDisplayPreferencesFile(directory: directory).load()
        XCTAssertEqual(loaded.state, .fresh)
        XCTAssertEqual(loaded.preferences, AgentDisplayPreferences.contractDefaults)
    }

    /// 坏文件 ⇒ 降级到默认 + 机器码（不静默采信半份）。
    func testBrokenFileDegradesToDefaults() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)
        try Data("not json at all".utf8).write(to: file.fileURL)
        let loaded = file.load()
        XCTAssertEqual(loaded.state, .degraded(reason: "parseFailed"))
        XCTAssertEqual(loaded.preferences, AgentDisplayPreferences.contractDefaults)
    }

    /// 越界值 ⇒ 降级并**点名是哪一项**（「文件坏了」这种笼统说法用户没法修）。
    func testOutOfRangeStoredValueDegradesAndNamesTheKey() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)
        let json = """
        {"version": 1, "values": {"display.compact": "on", "display.toolProgress": "verbose"}}
        """
        try Data(json.utf8).write(to: file.fileURL)
        let loaded = file.load()
        guard case let .degraded(reason) = loaded.state else {
            return XCTFail("越界值必须降级，实际：\(loaded.state)")
        }
        XCTAssertTrue(reason.contains(AgentDisplayKey.toolProgress.rawValue),
                      "降级原因要点名是哪一项：\(reason)")
        XCTAssertEqual(AgentDisplayPreferencesFile.degradedKey(for: reason), .toolProgress)
        XCTAssertEqual(loaded.preferences, AgentDisplayPreferences.contractDefaults)
    }

    /// 盘上多了不认识的键 ⇒ **忽略它**照常载入（旧版 / 别端实验键不该把九项一起清掉）。
    func testUnknownStoredKeyIsIgnored() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)
        let json = """
        {"version": 1, "values": {"display.compact": "on", "display.experimental": "42"}}
        """
        try Data(json.utf8).write(to: file.fileURL)
        let loaded = file.load()
        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertTrue(loaded.preferences.compact, "认得的那一项照常生效")
    }

    /// 拒绝 / 降级的人话两种语言都拿得到，且不是原样模板（`%@` 不许漏到界面上）。
    func testRejectionTextIsLocalizedInBothLanguages() {
        let error = AgentDisplayError.invalidValue(key: AgentDisplayKey.toolProgress.rawValue,
                                                   value: "verbose",
                                                   allowed: AgentDisplayPreferences.allowedValues(for: .toolProgress))
        for language in AppLanguage.allCases {
            let line = AgentDisplayRejectionText.line(for: error, language: language)
            XCTAssertFalse(line.contains("%@"), "模板占位符漏到了界面上：\(line)")
            XCTAssertTrue(line.contains("verbose"))
        }
        XCTAssertNotEqual(AgentDisplayRejectionText.line(for: error, language: .simplifiedChinese),
                          AgentDisplayRejectionText.line(for: error, language: .english))

        let degraded = AgentDisplayRejectionText.degradedLine(reason: "invalidValue:display.toolProgress",
                                                              language: .simplifiedChinese)
        XCTAssertTrue(degraded.contains("display.toolProgress"), degraded)
        let fileLevel = AgentDisplayRejectionText.degradedLine(reason: "parseFailed", language: .english)
        XCTAssertTrue(fileLevel.contains("parseFailed"), fileLevel)
    }

    // MARK: - 助手

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-display-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
