import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-012` 的**生效面**判据：九项开关各自把「这一屏画什么」改成什么。
///
/// 需求书四条验收要点里，两条是几何的（② 零占位 / ③ 行首栏不抖动），一条是「立即生效」
/// （①，这里 = 同一份输入换个开关值，投影立刻不同 —— 不需要重启，也不需要重建任何缓存），
/// 第四条（键名 / 默认 / 域）在 `AgentDisplayPreferencesTests`。其余五条按契约表逐项判。
final class AgentDisplayRowsTests: XCTestCase {

    private func message(_ text: String, role: AgentChatRole = .assistant, streaming: Bool = false) -> AgentChatMessage {
        AgentChatMessage(role: role, text: text, isStreaming: streaming)
    }

    private func tools(_ count: Int) -> [AgentDisplayProjection.ToolLine] {
        (1...count).map {
            AgentDisplayProjection.ToolLine(name: "read_file", summary: "Core/f\($0).swift",
                                            elapsed: "0.\($0)s")
        }
    }

    // MARK: - ① 立即生效

    /// 同一份输入、只换开关值 ⇒ 投影立刻不同（不许「重启后生效」）。
    func testPreferenceChangeTakesEffectImmediately() {
        let input = AgentDisplayProjection.Input(message: message("答：已读完三个文件。"), tools: tools(3))

        var preferences = AgentDisplayPreferences()
        let all = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(all.filter { if case .tool = $0.kind { return true } else { return false } }.count, 3)

        preferences.toolProgress = .summary
        let summary = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(summary.filter { if case .toolSummary = $0.kind { return true } else { return false } }.count, 1,
                       "换档之后同一份输入立刻就是新形状（没有缓存）")

        preferences.toolProgress = .off
        let off = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(off.filter { if case .toolCount = $0.kind { return true } else { return false } }.count, 1)
    }

    // MARK: - ② 关掉思考段 = 零占位

    /// 关掉时**一行都不出**，且整屏里没有任何「空正文」的行（空行也算占位）。
    func testThinkingOffLeavesNoPlaceholderAtAll() {
        let input = AgentDisplayProjection.Input(message: message("答案正文"),
                                                 thinking: "先读文件，再对照判据。")

        var preferences = AgentDisplayPreferences()          // 默认：显示思考段 = 关
        let hidden = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertFalse(hidden.contains { if case .thinking = $0.kind { return true } else { return false } },
                       "关掉思考段之后不许有思考行")
        XCTAssertFalse(hidden.contains { $0.text.isEmpty && $0.detail.isEmpty },
                       "关掉思考段之后连空行都不许留：零占位")
        // 且**行数**与「根本没给思考段」时一模一样 —— 这是「零占位」最硬的口径。
        let noThinking = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message("答案正文")),
            preferences: preferences)
        XCTAssertEqual(hidden.count, noThinking.count)

        preferences.thinking = true
        let shown = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(shown.filter { if case .thinking = $0.kind { return true } else { return false } }.count, 1)
        XCTAssertEqual(shown.count, noThinking.count + 1, "打开时只多那**一行**，不多空白")

        // 打开但内容为空 ⇒ 同样零行（画个空框等于告诉人「这里有东西、只是空」）。
        let emptyThinking = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message("答案正文"), thinking: "   \n  "),
            preferences: preferences)
        XCTAssertEqual(emptyThinking.count, noThinking.count)
    }

    // MARK: - ③ 关掉时间戳不抖动

    /// 每一行的行首栏宽度恒等于契约常量，与开关无关、与这一行有没有时刻无关。
    func testTimestampColumnWidthNeverChanges() {
        let input = AgentDisplayProjection.Input(message: message("第一行\n第二行"), timestamp: "09:41", tools: tools(2))

        var preferences = AgentDisplayPreferences()          // 默认：时间戳 = 关
        let off = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertTrue(off.allSatisfy { $0.leadingColumnWidth == AgentDisplayProjection.timestampColumnWidth })
        XCTAssertTrue(off.allSatisfy { $0.leading.isEmpty }, "关掉时行首栏是空的（不画假时刻）")

        preferences.timestamps = true
        let on = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(on.count, off.count, "开关不许改变行数")
        for (lhs, rhs) in zip(on, off) {
            XCTAssertEqual(lhs.leadingColumnWidth, rhs.leadingColumnWidth,
                           "同一行的行首栏宽度必须一样（不抖动）")
            XCTAssertEqual(lhs.leadingColumnWidth, AgentDisplayProjection.timestampColumnWidth)
        }
        XCTAssertTrue(on.allSatisfy { $0.leading.count == AgentDisplayProjection.timestampColumnWidth },
                      "开着时时刻串补齐到固定宽度（超宽截断，不许把列撑开）")

        // 超长的时刻串（有人手改盘上文件 / 别的端格式）也只许截到固定宽度。
        let wide = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message("x"), timestamp: "2026-10-26T09:41:00"),
            preferences: preferences)
        XCTAssertTrue(wide.allSatisfy { $0.leading.count == AgentDisplayProjection.timestampColumnWidth })
    }

    // MARK: - ⑤ 工具进度三档

    /// 全部 = 每条一行；摘要 = 一条折叠头（带条数与名字）；关 = 只留条数、**展开不了**。
    func testToolProgressThreeModes() {
        let input = AgentDisplayProjection.Input(message: message("完"), tools: tools(3))

        var preferences = AgentDisplayPreferences()
        let all = AgentDisplayProjection.rows(for: input, preferences: preferences)
        let toolRows = all.compactMap { row -> (String, Bool)? in
            if case let .tool(name, collapsed) = row.kind { return (name, collapsed) }
            return nil
        }
        XCTAssertEqual(toolRows.count, 3)
        XCTAssertTrue(toolRows.allSatisfy { $0.0 == "read_file" })
        XCTAssertTrue(toolRows.allSatisfy { $0.1 == false }, "非紧凑模式下工具条目不默认折叠")

        preferences.toolProgress = .summary
        let summary = AgentDisplayProjection.rows(for: input, preferences: preferences)
        let summaryRow = summary.first { if case .toolSummary = $0.kind { return true } else { return false } }
        guard case let .toolSummary(count, names)? = summaryRow?.kind else {
            return XCTFail("摘要档必须出一行折叠头")
        }
        XCTAssertEqual(count, 3)
        XCTAssertEqual(names.count, 3, "折叠头要带着可以展开的那几条")
        XCTAssertFalse(summary.contains { if case .tool = $0.kind { return true } else { return false } },
                       "摘要档不许逐条铺开")

        preferences.toolProgress = .off
        let off = AgentDisplayProjection.rows(for: input, preferences: preferences)
        let countRow = off.first { if case .toolCount = $0.kind { return true } else { return false } }
        guard case let .toolCount(count)? = countRow?.kind else {
            return XCTFail("关档要留一行「调用 N 次」")
        }
        XCTAssertEqual(count, 3)
        XCTAssertFalse(off.contains { if case .toolSummary = $0.kind { return true } else { return false } },
                       "关档不给折叠头（给了就等于留了一个能展开的口子）")
        XCTAssertEqual(off.filter { $0.text.isEmpty && $0.detail.isEmpty }.count, 1,
                       "关档只有那一条条数行（其余行都有内容）")
    }

    // MARK: - ⑥ 状态指示字形三档

    /// 三档 × 三态：都非空、同档三态互不相同、同态三档互不相同。
    func testIndicatorGlyphsCoverThreeStatesInEveryStyle() {
        for style in AgentIndicatorGlyph.allCases {
            let glyphs = AgentDisplayProjection.Indicator.allCases.map {
                AgentDisplayProjection.glyph(for: $0, style: style)
            }
            XCTAssertFalse(glyphs.contains(""), "\(style.rawValue) 档不许有空字形")
            XCTAssertEqual(Set(glyphs).count, 3, "\(style.rawValue) 档三态必须能分辨")
        }
        for indicator in AgentDisplayProjection.Indicator.allCases {
            let glyphs = AgentIndicatorGlyph.allCases.map {
                AgentDisplayProjection.glyph(for: indicator, style: $0)
            }
            XCTAssertEqual(Set(glyphs).count, 3, "\(indicator.rawValue) 三档必须分别是三种字形")
        }
        // ASCII 档不许出现非 ASCII 字符（它的用途就是「字体不认符号时照样能读懂」）。
        for indicator in AgentDisplayProjection.Indicator.allCases {
            let glyph = AgentDisplayProjection.glyph(for: indicator, style: .ascii)
            XCTAssertTrue(glyph.unicodeScalars.allSatisfy { $0.isASCII }, "ASCII 档混进了非 ASCII：\(glyph)")
        }
    }

    // MARK: - ⑦ 长消息预览（首 2 末 2）

    /// 够长才折：首 2 行 + 折叠行（`…`）+ 末 2 行，折叠行报出被藏了几行。
    func testLongMessagePreviewKeepsFirstTwoAndLastTwo() {
        let body = (1...7).map { "line\($0)" }.joined(separator: "\n")
        let input = AgentDisplayProjection.Input(message: message(body))

        var preferences = AgentDisplayPreferences()
        let folded = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(folded.count, 3, "首 2 / 末 2 / 折叠处 各一行")
        XCTAssertEqual(folded[0].text, "line1\nline2")
        XCTAssertEqual(folded[0].hiddenLines, 3, "7 行 − 首 2 − 末 2 = 藏 3 行")
        guard case let .previewGap(hidden) = folded[1].kind else { return XCTFail("第二行该是折叠处") }
        XCTAssertEqual(hidden, 3)
        XCTAssertEqual(folded[1].text, "…", "折叠处必须有省略号")
        XCTAssertEqual(folded[2].text, "line6\nline7")

        // 关掉预览 ⇒ 原样一整段（不许在短消息 / 关档上加折叠口）。
        preferences.longPreview = .off
        let plain = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(plain[0].text, body)
        XCTAssertFalse(plain.contains { if case .previewGap = $0.kind { return true } else { return false } })

        // 边界：刚好 4 行（= 首 2 + 末 2）不折 —— 折了会少一行内容还多一个「展开」。
        let exact = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message((1...4).map { "line\($0)" }.joined(separator: "\n"))),
            preferences: AgentDisplayPreferences())
        XCTAssertEqual(exact.count, 1)

        // 边界：5 行 ⇒ 折 1 行。
        let five = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message((1...5).map { "line\($0)" }.joined(separator: "\n"))),
            preferences: AgentDisplayPreferences())
        XCTAssertEqual(five.count, 3)
        XCTAssertEqual(five[0].hiddenLines, 1)
    }

    // MARK: - ⑧ 运行底栏元数据

    /// 关 ⇒ 一段都不出；开 ⇒ 只出**有读数**的那几段（缺的那项不许写 0 / 占位符）。
    func testBottomBarMetaOnlyShowsReadingsItHas() {
        let meta = AgentDisplayProjection.RunMeta(model: "gpt-x", contextPercent: 42,
                                                  workingDirectory: "/Users/alex/dev")
        let input = AgentDisplayProjection.Input(message: message("答"), runMeta: meta)

        var preferences = AgentDisplayPreferences()          // 默认：底栏元数据 = 关
        XCTAssertFalse(AgentDisplayProjection.rows(for: input, preferences: preferences)
            .contains { if case .metadata = $0.kind { return true } else { return false } })

        preferences.bottomBarMeta = true
        let on = AgentDisplayProjection.rows(for: input, preferences: preferences)
        let metadata = on.compactMap { row -> (AgentDisplayProjection.MetadataField, String)? in
            if case let .metadata(field, value) = row.kind { return (field, value) }
            return nil
        }
        XCTAssertEqual(metadata.map(\.0), [.model, .contextPercent, .workingDirectory], "字段序固定")
        XCTAssertEqual(metadata.map(\.1), ["gpt-x", "42%", "/Users/alex/dev"])

        // 缺的那一项整段不出现（不写 `0%`、不写占位符）。
        let partial = AgentDisplayProjection.rows(
            for: AgentDisplayProjection.Input(message: message("答"),
                                              runMeta: .init(model: "gpt-x", contextPercent: nil,
                                                             workingDirectory: nil)),
            preferences: preferences)
        XCTAssertEqual(partial.filter { if case .metadata = $0.kind { return true } else { return false } }.count, 1)
        XCTAssertFalse(partial.contains { $0.text.contains("0%") }, "没有读数就不写 0")
    }

    // MARK: - 流式输出关 ⇒ 收齐再显示

    /// 关掉流式：还在收的那一条**一行都不出**（不出半截）；收完之后照常出。
    /// 开着流式：同一条立刻出（带 `live` 标记，界面画光标）。
    func testStreamingOffWaitsUntilTheMessageIsComplete() {
        let streaming = AgentDisplayProjection.Input(message: message("半截正", streaming: true))

        var preferences = AgentDisplayPreferences()
        let on = AgentDisplayProjection.rows(for: streaming, preferences: preferences)
        XCTAssertEqual(on.count, 1)
        XCTAssertTrue(on[0].live, "流式开着时这一行还在长（界面画光标）")

        preferences.streaming = false
        XCTAssertTrue(AgentDisplayProjection.rows(for: streaming, preferences: preferences).isEmpty,
                      "关掉流式：收齐再显示，收齐之前一行都不许出")

        // 收齐之后照常出，且不再带 live。
        let done = AgentDisplayProjection.Input(message: message("半截正文"))
        let afterDone = AgentDisplayProjection.rows(for: done, preferences: preferences)
        XCTAssertEqual(afterDone.count, 1)
        XCTAssertFalse(afterDone[0].live)
    }

    // MARK: - 紧凑模式

    /// 开：工具条目默认折叠 + 块间距取紧档（0）。
    func testCompactModeCollapsesToolsAndTightensSpacing() {
        let input = AgentDisplayProjection.Input(message: message("答"), timestamp: "09:41", tools: tools(2))

        var preferences = AgentDisplayPreferences()
        let normal = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertTrue(normal.allSatisfy { $0.spacingAfter >= 0 })
        XCTAssertTrue(normal.contains { $0.spacingAfter > 0 }, "非紧凑模式下块之间留一行")

        preferences.compact = true
        let compact = AgentDisplayProjection.rows(for: input, preferences: preferences)
        XCTAssertTrue(compact.allSatisfy { $0.spacingAfter == 0 }, "紧凑模式下块间距取紧档")
        let toolCollapsed = compact.compactMap { row -> Bool? in
            if case let .tool(_, collapsed) = row.kind { return collapsed }
            return nil
        }
        XCTAssertFalse(toolCollapsed.isEmpty)
        XCTAssertTrue(toolCollapsed.allSatisfy { $0 }, "紧凑模式下工具块默认折叠")
    }

    // MARK: - ⑨ 运行中提交

    /// 打断 = 先停后发（默认）；排队 = 这一轮结束后接着跑。两条路必须真的是两种处置。
    func testSubmitWhileRunningSplitsIntoTwoPaths() {
        var preferences = AgentDisplayPreferences()
        XCTAssertEqual(preferences.submitWhileRunning, .interrupt, "契约默认 = 打断")
        XCTAssertTrue(AgentDisplayProjection.abortsInFlightBeforeSending(preferences))

        preferences.submitWhileRunning = .queue
        XCTAssertFalse(AgentDisplayProjection.abortsInFlightBeforeSending(preferences),
                       "排队档不许先停（那会把在跑的这一轮打断）")
    }

    // MARK: - 组合：九项一起改仍自洽

    /// 九项同时取「非默认」值之后，投影仍能逐行给出合法形状（没有互相踩）。
    func testAllNineSwitchesNonDefaultStillProjectConsistently() {
        var preferences = AgentDisplayPreferences()
        try? preferences.applyBatch([
            (AgentDisplayKey.streaming.rawValue, "on"),
            (AgentDisplayKey.compact.rawValue, "on"),
            (AgentDisplayKey.thinking.rawValue, "on"),
            (AgentDisplayKey.timestamps.rawValue, "on"),
            (AgentDisplayKey.toolProgress.rawValue, "summary"),
            (AgentDisplayKey.indicatorGlyph.rawValue, "ascii"),
            (AgentDisplayKey.longPreview.rawValue, "1+1"),
            (AgentDisplayKey.bottomBarMeta.rawValue, "on"),
            (AgentDisplayKey.submitWhileRunning.rawValue, "queue"),
        ])
        let input = AgentDisplayProjection.Input(
            message: message("a\nb\nc\nd"),
            timestamp: "09:41",
            thinking: "想了想",
            tools: tools(2),
            runMeta: .init(model: "m", contextPercent: 7, workingDirectory: "/tmp"))
        let rows = AgentDisplayProjection.rows(for: input, preferences: preferences)

        // 行首栏宽度仍然一致（时间戳开着 + 紧凑）。
        XCTAssertTrue(rows.allSatisfy { $0.leadingColumnWidth == AgentDisplayProjection.timestampColumnWidth })
        // 每条预览行都带着一致的行首栏（折叠行不许把列错开）。
        let kinds = rows.map(\.kind)
        XCTAssertTrue(kinds.contains { if case .thinking = $0 { return true } else { return false } })
        XCTAssertTrue(kinds.contains { if case .toolSummary = $0 { return true } else { return false } })
        XCTAssertTrue(kinds.contains { if case .previewGap = $0 { return true } else { return false } })
        XCTAssertTrue(kinds.contains { if case .metadata = $0 { return true } else { return false } })
        // 4 行正文 + 首1末1 ⇒ 折 2 行。
        XCTAssertTrue(rows.contains { $0.hiddenLines == 2 })
    }

    // MARK: - ③ 行首栏（时间戳列）在视图层的形状

    /// 关掉时间戳时行首栏**照样占满等宽**（不可见填充），因此正文不左移 —— 这是契约③
    /// 在视图侧的落点：列宽由**字符数**保证，视图不写 `frame(width:)`。
    func testLeadingColumnKeepsItsWidthWhetherTheSwitchIsOnOrOff() {
        let width = AgentDisplayProjection.timestampColumnWidth
        var preferences = AgentDisplayPreferences()          // 默认：时间戳 = 关

        let off = AgentDisplayProjection.leadingColumn(timestamp: "09:41", preferences: preferences)
        XCTAssertEqual(off.count, width, "关掉时仍占满固定列宽（否则正文会左移）")
        XCTAssertTrue(off.unicodeScalars.allSatisfy { $0.value == 0x00A0 },
                      "关掉时只能用不可见填充（普通空格会被排版吃掉）")
        XCTAssertFalse(off.contains("0"), "关掉时不许露出时刻")

        preferences.timestamps = true
        XCTAssertEqual(AgentDisplayProjection.leadingColumn(timestamp: "09:41", preferences: preferences), "09:41",
                       "开着时就是这一条的时刻")
        XCTAssertEqual(AgentDisplayProjection.leadingColumn(timestamp: "9:4", preferences: preferences).count, width,
                       "短串补齐到固定宽度")
        let wide = AgentDisplayProjection.leadingColumn(timestamp: "2026-10-26T09:41:00", preferences: preferences)
        XCTAssertEqual(wide.count, width, "超宽串只许截断，不许把列撑开")
        // 没有时刻（老会话没有这一栏）⇒ 空栏，不编一个「现在」。
        XCTAssertEqual(AgentDisplayProjection.leadingColumn(timestamp: nil, preferences: preferences).count, width)
        XCTAssertTrue(AgentDisplayProjection.leadingColumn(timestamp: nil, preferences: preferences)
            .unicodeScalars.allSatisfy { $0.value == 0x00A0 })
    }

    // MARK: - ⑧ 底栏元数据的唯一出处（状态行与投影同一份）

    /// 关 ⇒ 空；开 ⇒ 只出有读数的段、字段序固定 —— 状态行据此追加，不再各算一遍。
    func testMetadataSegmentsAreTheSingleSourceForTheStatusBar() {
        let meta = AgentDisplayProjection.RunMeta(model: "gpt-x", contextPercent: 42,
                                                  workingDirectory: "/Users/alex/dev")
        var preferences = AgentDisplayPreferences()          // 默认：底栏元数据 = 关
        XCTAssertTrue(AgentDisplayProjection.metadataSegments(meta: meta, preferences: preferences).isEmpty,
                      "关掉时状态行一段都不追加")

        preferences.bottomBarMeta = true
        let segments = AgentDisplayProjection.metadataSegments(meta: meta, preferences: preferences)
        XCTAssertEqual(segments.map(\.field), [.model, .contextPercent, .workingDirectory], "字段序固定")
        XCTAssertEqual(segments.map(\.value), ["gpt-x", "42%", "/Users/alex/dev"])

        // 缺读数的那段整段不出（不写 0%、不写占位）。
        let partial = AgentDisplayProjection.metadataSegments(
            meta: .init(model: nil, contextPercent: nil, workingDirectory: "/tmp"),
            preferences: preferences)
        XCTAssertEqual(partial.map(\.field), [.workingDirectory])
        // 整份读数都没给 ⇒ 空（不是三条空串）。
        XCTAssertTrue(AgentDisplayProjection.metadataSegments(meta: nil, preferences: preferences).isEmpty)
    }

    // MARK: - ⑥ 预览切法的唯一出处

    /// 短消息不折（`nil`）、够长才折、关档一律不折 —— 界面与投影读的是同一份切法。
    func testPreviewSplitIsTheSharedSlicingRule() {
        var preferences = AgentDisplayPreferences()          // 默认：首 2 末 2
        XCTAssertNil(AgentDisplayProjection.previewSplit(text: "a\nb\nc\nd", preferences: preferences),
                     "刚好 4 行不折（折了会少一行内容还多一个展开）")

        let split = AgentDisplayProjection.previewSplit(text: (1...7).map { "line\($0)" }.joined(separator: "\n"),
                                                       preferences: preferences)
        XCTAssertEqual(split?.head, "line1\nline2")
        XCTAssertEqual(split?.tail, "line6\nline7")
        XCTAssertEqual(split?.hidden, 3)

        preferences.longPreview = .off
        XCTAssertNil(AgentDisplayProjection.previewSplit(text: (1...7).map { "line\($0)" }.joined(separator: "\n"),
                                                        preferences: preferences),
                     "关掉预览 ⇒ 不折")
    }

    // MARK: - 时间戳 / 思考段的**来源**

    /// 消息自带时刻与思考段：缺省都是 `nil`（老会话不许被编出一个「现在」），
    /// 而真正跑起来的那条（`beginRun`）必须带时刻 —— 否则时间戳开关打开也没东西可画。
    func testMessagesCarryTheirOwnTimestampAndThinkingSource() {
        let plain = AgentChatMessage(role: .assistant, text: "答")
        XCTAssertNil(plain.createdAt, "没有来源就不编时刻")
        XCTAssertNil(plain.thinking, "没有思考源就是 nil（开关打开也不画空框）")

        var state = AgentChatState(messages: [], cards: [], steps: [],
                                   endpoint: .ready(model: "m", endpoint: "e"),
                                   isRunning: false, grants: [])
        state.beginRun(prompt: "看一下表结构")
        XCTAssertNotNil(state.messages.first?.createdAt, "发出去的这一条必须带时刻")
        XCTAssertNotNil(state.messages.last?.createdAt)

        // 回放：盘上那一跳的 `at` 直接搬到消息上（不是回放时读钟）。
        let turn = AgentSessionTurn(sessionID: "s", workspace: "/w", kind: .model,
                                    role: "user", text: "问", at: Date(timeIntervalSince1970: 1_700_000_000))
        let session = AgentSession(header: AgentSessionHeader(id: "s", workspace: "/w", title: "问"),
                                   turns: [turn])
        XCTAssertEqual(AgentSessionReplay.messages(from: session).first?.createdAt, turn.at)
    }
}
