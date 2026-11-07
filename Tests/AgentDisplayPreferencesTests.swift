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
            // 长消息预览：**默认不折**（2026-11-07 详设 §3.33）。这一格原来钉的是 `2+2`
            // —— 那正好把结论本身折成首 2 末 2 行，人类主人实机看到的「结论竟然折叠起来」
            // 就是它。开关还在（`off|H+T`），但默认形态是「结论整体呈现」。
            .init(key: .longPreview, defaultValue: "off", allowed: "off|H+T (1...20)"),
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

    // MARK: - 旧默认迁移（2026-11-07 真机复验：已装机器结论仍被折）

    /// 真机那一份盘的形状：beta1.0.3 之前按旧默认写下的一整份（`longPreview = 2+2`）。
    private func legacyPayloadJSON(preview: String = "2+2") -> String {
        """
        {"version": 1, "values": {
          "display.streaming": "on",
          "display.compact": "off",
          "display.thinking": "off",
          "display.timestamps": "off",
          "display.toolProgress": "all",
          "display.indicatorGlyph": "emoji",
          "display.longPreview": "\(preview)",
          "display.bottomBarMeta": "off",
          "display.submitWhileRunning": "interrupt"
        }}
        """
    }

    /// ① 旧库（v1、`2+2`）启动 ⇒ **迁到 `off`**，并且要求写回一次（只迁一次）。
    ///
    /// 反例（改前的行为）就在同一个函数里量：同一份文本按 v1 原值解出来是 `2+2`
    /// ⇒ `previewSplit` 非 `nil` ⇒ 结论被折。这条反例证明判据有牙齿。
    func testLegacyDefaultTwoPlusTwoMigratesToOff() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)
        try Data(legacyPayloadJSON().utf8).write(to: file.fileURL)

        let loaded = file.load()
        XCTAssertEqual(loaded.state, .loaded)
        XCTAssertEqual(loaded.preferences.longPreview, .off,
                       "旧库里的 `2+2` 没迁走 ⇒ 已装用户看到的结论仍是首 2 末 2 行")
        XCTAssertTrue(loaded.needsRewrite, "迁移之后要写回一次（否则每次启动都重判，且用户此后显式选 2+2 会被再覆盖）")

        // 写回之后：version 2 + 仍然 `off`，且不再要求重写。
        try file.save(loaded.preferences)
        let onDisk = try String(contentsOf: file.fileURL, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("\"version\" : 2"), "写回的那份必须是 v2：\(onDisk)")
        let again = file.load()
        XCTAssertEqual(again.preferences.longPreview, .off)
        XCTAssertFalse(again.needsRewrite, "v2 之后不许再迁 —— 否则用户显式选的值每次启动都被改掉")

        // **反例**：同一份 v1 文本按原值解（不迁移）= 改前的行为 ⇒ 结论被折。
        var legacy = AgentDisplayPreferences()
        try legacy.apply(key: AgentDisplayKey.longPreview.rawValue, value: "2+2")
        XCTAssertEqual(legacy.longPreview, .headTail(head: 2, tail: 2))
        let longText = (1...30).map { "第 \($0) 行：结论正文。" }.joined(separator: "\n")
        XCTAssertNotNil(AgentDisplayProjection.previewSplit(text: longText, preferences: legacy),
                        "反例没被判红 ⇒ 这条判据量不出「结论被折」")
        XCTAssertNil(AgentDisplayProjection.previewSplit(text: longText, preferences: loaded.preferences),
                     "迁移后默认形态仍然折了结论")
    }

    /// ② 迁移**只做一次**：用户在 v2 之后显式选 `2+2` 要保留（不迁移）。
    func testExplicitChoiceAfterMigrationSurvives() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)

        // 先演一遍迁移 + 写回。
        try Data(legacyPayloadJSON().utf8).write(to: file.fileURL)
        let migrated = file.load()
        try file.save(migrated.preferences)

        // 用户自己把开关打开（显式 opt-in）。
        var chosen = migrated.preferences
        try chosen.apply(key: AgentDisplayKey.longPreview.rawValue, value: "2+2")
        try file.save(chosen)

        let loaded = file.load()
        XCTAssertEqual(loaded.preferences.longPreview, .headTail(head: 2, tail: 2),
                       "v2 之后用户显式选的 `2+2` 被迁移吃掉了 ⇒ 「保存成功」是谎话")
        XCTAssertFalse(loaded.needsRewrite)
    }

    /// ③ 旧库里的**非默认**值不迁（`3+5` 是用户自己选的，哪怕它是 v1）。
    func testLegacyNonDefaultPreviewIsKept() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AgentDisplayPreferencesFile(directory: directory)
        try Data(legacyPayloadJSON(preview: "3+5").utf8).write(to: file.fileURL)

        let loaded = file.load()
        XCTAssertEqual(loaded.preferences.longPreview, .headTail(head: 3, tail: 5))
        XCTAssertFalse(loaded.needsRewrite, "只有等于旧默认 `2+2` 的才视为「当年那份默认」")
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
