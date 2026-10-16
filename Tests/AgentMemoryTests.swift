import XCTest
@testable import DoyahCore

/// 对话记忆（`FR-AI-29`）的机械判据 —— 照 SRS 六条验收要点逐条落，**负例逐条点名**。
///
/// 这一层最容易被做松的两处，正是用例里盯得最紧的：
/// 1. **「理由带实际数字」**：一旦退化成「因为常用 / 太久没用」这种形容词，验收①就废了 ——
///    所以断言里直接钉住数字（`累计执行 3 次` / `跨 5 天`），并且拿 `FR-AI-15` 的入口**逐字对拍**，
///    证明是**同一套口径**、不是长得像的第二套。
/// 2. **「删掉即不再进上下文」**：删除必须作用在**事实源**上（不是只改派生索引），
///    否则换个入口读回来它又在。
final class AgentMemoryTests: XCTestCase {

    private var directory: URL!
    private var store: AgentMemoryStore!

    /// 注入时刻（不读钟 —— 否则「跨 N 天」这类读数无法逐项对拍）。
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentMemoryStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 夹具

    private func draft(_ workspace: String,
                       connection: String = "prod",
                       kind: MemoryKind = .routine,
                       note: String) -> AgentMemoryDraft {
        AgentMemoryDraft(workspace: workspace, connection: connection, kind: kind, note: note)
    }

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// 判据侧自己算的闲置天数（自然日之差）—— 拿来与理由里的数字对拍，
    /// 而不是把被测实现算出来的那个数再喂回去。
    private func idleDays(of entry: AgentMemoryEntry, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: entry.lastUsedAt)
        let to = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    private func headerLine(_ workspace: String) throws -> String {
        let data = try AgentMemoryStore.encoder.encode(AgentMemoryHeader(workspace: workspace))
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func entryLine(_ entry: AgentMemoryEntry) throws -> String {
        let data = try AgentMemoryStore.encoder.encode(entry)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 手写事实源（用来造「坏文件 / 认不出的条目 / 塞了行数据字段」这类**写入闸拦不住**的现场）。
    private func writeRaw(_ lines: [String], workspace: String) throws {
        let url = store.factFileURL(workspace: workspace)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func handmadeEntry(id: String,
                               workspace: String,
                               connection: String = "prod",
                               kind: String = "routine",
                               note: String,
                               at date: Date) -> AgentMemoryEntry {
        AgentMemoryEntry(id: id, workspace: workspace, connection: connection, kind: kind, note: note,
                         fingerprint: QueryMemory.coarseFingerprint(note),
                         firstSeenAt: date, lastUsedAt: date, useCount: 1)
    }

    // MARK: - ① 逐条列出 + 回答「为什么记了它」（可读理由**带实际数字**）

    func testInspectionListsEveryEntryAndExplainsWhyWithRealNumbers() throws {
        _ = try store.record(draft("ws-1", kind: .routine, note: "工作区里的 Python 项目用 pytest"), at: daysAgo(4))
        _ = try store.record(draft("ws-1", kind: .pinned, note: "巡检脚本每周一跑"), at: daysAgo(2))
        _ = try store.record(draft("ws-1", connection: "stage", kind: .troubleshooting, note: "排查过连接超时"), at: now)

        let inspection = store.inspect(workspace: "ws-1", now: now)
        XCTAssertEqual(inspection.entries.count, 3, "逐条列出：三条都在")
        XCTAssertEqual(inspection.explanations.count, inspection.entries.count, "解释与条目逐条对齐，不许错位")
        XCTAssertEqual(inspection.explanations.map(\.id), inspection.entries.map(\.id))
        XCTAssertEqual(inspection.skippedLines, 0)
        XCTAssertEqual(inspection.unknownEntries, 0)
        XCTAssertFalse(inspection.workspaceMismatch)

        for (entry, explanation) in zip(inspection.entries, inspection.explanations) {
            XCTAssertEqual(explanation.lines.count, 4, "与 FR-AI-15 同一套形状的四行")
            XCTAssertTrue(explanation.lines[0].contains(entry.fingerprint), "聚类依据要给出实际指纹")
            XCTAssertTrue(explanation.lines[1].contains("连接 \(entry.connection)"), "来源行要点名连接：\(explanation.lines[1])")
            XCTAssertTrue(explanation.lines[1].contains("累计执行 \(entry.useCount) 次"),
                          "来源行要给实际次数：\(explanation.lines[1])")
            XCTAssertTrue(explanation.lines[2].contains(entry.note), "最近原文那一行要在")
            // 「为什么记了它」那一行必须带**实际数字**（不是形容词）。
            XCTAssertTrue(explanation.reasonLine?.hasPrefix("为什么记了它") == true,
                          explanation.lines.joined(separator: " / "))
            XCTAssertTrue(explanation.reasonLine?.contains("闲置 \(idleDays(of: entry)) 天") == true,
                          "闲置天数要是真算出来的：\(explanation.reasonLine ?? "")")
        }

        // 「最近用到」在前（可检视的顺序是稳定的）。
        XCTAssertEqual(inspection.entries.first?.connection, "stage")
    }

    /// **同一套口径的机械证明**：本层产出的四行 == 直接调 `FR-AI-15` 那四个入口算出来的四行（逐字相等）。
    func testExplanationIsByteIdenticalToTheFRAI15EntryPoint() throws {
        let note = "工作区里的 Python 项目用 pytest"
        let at = daysAgo(3)
        _ = try store.record(draft("ws-1", kind: .routine, note: note), at: at)
        guard let entry = store.entries(workspace: "ws-1").entries.first else { return XCTFail("要读得回") }

        // 判据侧**自己**照 FR-AI-15 的口径组装一次（不调被测的那条捷径）。
        let memory = QueryMemory.Memory(
            fingerprint: entry.fingerprint,
            latestSQL: entry.note,
            variantCount: 1,
            runCount: entry.useCount,
            days: AgentMemory.dayKeys(from: entry.firstSeenAt, to: entry.lastUsedAt),
            connections: [entry.connection],
            lastExecutedAt: entry.lastUsedAt
        )
        let stats = MemoryStats(runCount: entry.useCount,
                                dayCount: memory.days.count,
                                variantCount: 1,
                                lastExecutedAt: entry.lastUsedAt,
                                connections: [entry.connection])
        let verdict = RetentionPolicy.standard.evaluate(kind: .routine, stats: stats, now: now)
        let expected = MemoryExplanation.describe(memory: memory, kind: .routine, verdict: verdict)

        let actual = AgentMemoryReasons.describe(entry: entry, now: now)
        XCTAssertEqual(actual?.lines, expected, "理由必须来自 FR-AI-15 的同一个实现，不是第二套")
        XCTAssertEqual(actual?.isRetained, !verdict.shouldForget)
        XCTAssertEqual(actual?.isPinned, false)
    }

    /// 重复记同一条 ⇒ 累计次数，且**理由里的数字跟着涨**（真实数字，不是写死的）。
    func testMergingSameNoteAccumulatesAndTheReasonShowsIt() throws {
        let note = "工作区里改完先跑 verify-core"
        let first = try store.record(draft("ws-1", note: note), at: daysAgo(4))
        let second = try store.record(draft("ws-1", note: note), at: now)

        XCTAssertTrue(first.merged == false)
        XCTAssertTrue(second.merged, "同工作区同连接同指纹 ⇒ 合并，不再长一条")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 1)

        let explanation = try XCTUnwrap(store.inspect(workspace: "ws-1", now: now).explanations.first)
        XCTAssertEqual(explanation.useCount, 2)
        XCTAssertTrue(explanation.reasonLine?.contains("2 次") == true, explanation.reasonLine ?? "")
        XCTAssertTrue(explanation.lines[1].contains("跨 5 天"),
                      "两端之间有 5 个自然日 ⇒ 理由里给实际天数：\(explanation.lines[1])")
    }

    /// 按 `FR-AI-15` 的生命周期判定「该忘了」的条目：理由说的是**为什么它被忘了**，
    /// 并且**不再进上下文**。
    func testExpiredEntryExplainsItselfAndStaysOutOfContext() throws {
        let note = "只跑过一次的临时排查"
        let result = try store.record(draft("ws-1", kind: .troubleshooting, note: note), at: daysAgo(400))
        XCTAssertTrue(result.accepted)

        let explanation = try XCTUnwrap(store.inspect(workspace: "ws-1", now: now).explanations.first)
        XCTAssertFalse(explanation.isRetained, "闲置 400 天且只跑过 1 次 ⇒ 按 FR-AI-15 口径该被遗忘")
        XCTAssertTrue(explanation.reasonLine?.hasPrefix("为什么它被忘了") == true, explanation.reasonLine ?? "")
        XCTAssertTrue(explanation.reasonLine?.contains("400") == true, explanation.reasonLine ?? "")

        let loaded = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(loaded.count, 1, "**列出来**与**进上下文**是两回事：它还看得见")
        XCTAssertTrue(AgentMemoryContext.references(from: loaded, now: now).isEmpty,
                      "该忘的不进上下文（FR-AI-15 的生命周期在上下文这一侧同样成立）")
    }

    // MARK: - ② 删除立即生效且可验证（负例）

    func testDeleteTakesEffectImmediatelyEverywhereIncludingTheContext() throws {
        let keep = try store.record(draft("ws-1", note: "要留下的那条"), at: daysAgo(1))
        let drop = try store.record(draft("ws-1", note: "要删掉的那条"), at: now)
        let keepID = try XCTUnwrap(keep.entry?.id)
        let dropID = try XCTUnwrap(drop.entry?.id)

        // 删之前：它在上下文里（否则「删掉后不再出现」这条判据是空的）。
        let before = AgentContextAssembler.assemble(
            AgentMemoryContext.references(from: store.entries(workspace: "ws-1").entries, now: now))
        XCTAssertTrue(before.text.contains("要删掉的那条"))

        XCTAssertTrue(try store.remove(id: dropID, workspace: "ws-1"), "真删掉了要如实说 true")

        // ① 事实源里没有了；② 重建索引里没有了；③ 下一次组装上下文里没有了。
        let after = store.entries(workspace: "ws-1")
        XCTAssertEqual(after.entries.map(\.id), [keepID])
        XCTAssertEqual(after.skippedLines, 0)

        let rebuilt = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertFalse(rebuilt.ids.contains(dropID), "重建索引后不再出现")
        XCTAssertEqual(rebuilt.ids, [keepID])

        let context = AgentContextAssembler.assemble(
            AgentMemoryContext.references(from: after.entries, now: now))
        XCTAssertFalse(context.text.contains("要删掉的那条"), "删掉即不再进上下文")
        XCTAssertTrue(context.text.contains("要留下的那条"), "不许误伤别的条目")

        // 重启（新实例、只靠盘上文件）后仍然是删掉的状态。
        let reopened = AgentMemoryStore(directory: directory).entries(workspace: "ws-1")
        XCTAssertEqual(reopened.entries.map(\.id), [keepID])
    }

    func testDeletingSomethingThatIsNotThereReportsFalse() throws {
        _ = try store.record(draft("ws-1", note: "就这一条"), at: now)
        XCTAssertFalse(try store.remove(id: "no-such-id", workspace: "ws-1"), "没这条 ⇒ 如实说 false")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 1)
    }

    func testRemoveAllClearsTheLayerAndTheRebuiltIndexIsEmpty() throws {
        _ = try store.record(draft("ws-1", note: "甲"), at: daysAgo(2))
        _ = try store.record(draft("ws-1", note: "乙"), at: daysAgo(1))
        _ = try store.record(draft("ws-1", connection: "stage", note: "丙"), at: now)
        _ = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertEqual(store.loadIndex(workspace: "ws-1")?.entryCount, 3)

        XCTAssertEqual(try store.removeAll(workspace: "ws-1"), 3, "清了几条要报准")
        XCTAssertTrue(store.entries(workspace: "ws-1").entries.isEmpty)
        XCTAssertTrue(try store.rebuildIndex(workspace: "ws-1", builtAt: now).isEmpty,
                      "事实源清空 ⇒ 派生的索引重建出来也是空的")
        XCTAssertEqual(try store.removeAll(workspace: "ws-1"), 0, "已经空了 ⇒ 报 0，不假装清过")
    }

    // MARK: - ③ 换工作区看不到别的记忆（负例）

    func testTwoWorkspacesCannotSeeEachOther() throws {
        _ = try store.record(draft("ws-1", note: "只在 ws-1"), at: daysAgo(1))
        _ = try store.record(draft("ws-2", note: "只在 ws-2"), at: now)

        let one = store.inspect(workspace: "ws-1", now: now)
        let two = store.inspect(workspace: "ws-2", now: now)
        XCTAssertEqual(one.entries.count, 1)
        XCTAssertEqual(two.entries.count, 1)
        XCTAssertEqual(one.entries.first?.note, "只在 ws-1")
        XCTAssertEqual(two.entries.first?.note, "只在 ws-2")
        XCTAssertFalse(one.explanations.flatMap(\.lines).joined().contains("只在 ws-2"), "换工作区看不到别的记忆")
        XCTAssertFalse(two.explanations.flatMap(\.lines).joined().contains("只在 ws-1"))

        // 两份事实源是**两个文件**（隔离是结构性的，不是读的时候过滤出来的）。
        XCTAssertNotEqual(store.factFileURL(workspace: "ws-1"), store.factFileURL(workspace: "ws-2"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.factFileURL(workspace: "ws-2").path))

        // 归属不符的写入进不去（不静默落到别人家的工作区）。
        try writeRaw([try headerLine("ws-2")], workspace: "ws-1")
        let refused = try store.record(draft("ws-1", note: "越界"), at: now)
        XCTAssertFalse(refused.accepted)
        XCTAssertTrue(refused.rejections.contains(.workspaceMismatch), "\(refused.rejections)")
    }

    /// 头一行声明的是别的工作区 ⇒ **看不到**，而且要与「空」分得开。
    func testForeignWorkspaceHeaderIsInvisibleRatherThanEmpty() throws {
        try writeRaw([try headerLine("ws-9"),
                      try entryLine(handmadeEntry(id: "m-1", workspace: "ws-9", note: "别人家的", at: now))],
                     workspace: "ws-1")
        let loaded = store.entries(workspace: "ws-1")
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertTrue(loaded.workspaceMismatch, "「看不到」必须与「空」分得开")
        XCTAssertTrue(store.inspect(workspace: "ws-1", now: now).workspaceMismatch)
    }

    /// 换工作区读**空**（从没写过）也要是「空」而不是「坏」。
    func testNeverWrittenWorkspaceReadsAsEmptyNotBroken() throws {
        let loaded = store.entries(workspace: "ws-never")
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertFalse(loaded.workspaceMismatch)
        XCTAssertFalse(loaded.missingHeader)
        XCTAssertFalse(loaded.hasSkippedReadings)
        XCTAssertTrue(store.inspect(workspace: "ws-never", now: now).explanations.isEmpty)
    }

    /// 连接是同一工作区里的**第二层**隔离。
    func testConnectionIsASecondIsolationLayer() throws {
        _ = try store.record(draft("ws-1", connection: "prod", note: "生产库里的写法"), at: daysAgo(1))
        _ = try store.record(draft("ws-1", connection: "stage", note: "测试库里的写法"), at: now)

        XCTAssertEqual(store.connections(workspace: "ws-1"), ["prod", "stage"])
        XCTAssertEqual(store.entries(workspace: "ws-1", connection: "prod").entries.map(\.note), ["生产库里的写法"])
        XCTAssertEqual(store.entries(workspace: "ws-1", connection: "stage").entries.map(\.note), ["测试库里的写法"])
        XCTAssertEqual(store.inspect(workspace: "ws-1", connection: "prod", now: now).entries.count, 1)
    }

    /// 同一句话在**不同连接**下是两条（连接不同不合并）。
    func testSameNoteInDifferentConnectionsDoesNotMerge() throws {
        let note = "这句在两个库里都记过"
        let a = try store.record(draft("ws-1", connection: "prod", note: note), at: daysAgo(1))
        let b = try store.record(draft("ws-1", connection: "stage", note: note), at: now)
        XCTAssertFalse(a.merged)
        XCTAssertFalse(b.merged)
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 2)
    }

    // MARK: - ④ 键集合是白名单 · 结构上没有行数据字段 · 密钥片段被挡（负例）

    func testKeyWhitelistsAreExactlyTheDeclaredOnesAndCarryNoRowData() throws {
        let entryKeys = Set(Mirror(reflecting: handmadeEntry(id: "m", workspace: "w", note: "n", at: now))
            .children.compactMap { $0.label })
        XCTAssertEqual(entryKeys, AgentMemoryEntry.keyWhitelist)
        XCTAssertEqual(Set(Mirror(reflecting: AgentMemoryHeader(workspace: "w")).children.compactMap { $0.label }),
                       AgentMemoryHeader.keyWhitelist)
        XCTAssertEqual(Set(Mirror(reflecting: AgentMemoryIndex.Item(id: "m", kind: "routine", connection: "c",
                                                                    fingerprint: "f", firstSeenAt: now,
                                                                    lastUsedAt: now, useCount: 1))
            .children.compactMap { $0.label }), AgentMemoryIndex.Item.keyWhitelist)

        let encoded = try AgentMemoryStore.encoder.encode(handmadeEntry(id: "m", workspace: "w", note: "n", at: now))
        let keys = Set((try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]).keys)
        XCTAssertTrue(keys.isSubset(of: AgentMemoryEntry.keyWhitelist))
        for forbidden in ["rows", "rowData", "data", "values", "result", "resultset", "columns",
                          "apiKey", "token", "secret", "password", "content"] {
            XCTAssertFalse(keys.contains(forbidden), "记忆的键里不许有 `\(forbidden)` 这种落点")
        }
    }

    func testSecretFragmentIsRejectedAndCounted() throws {
        let review = AgentMemoryIntake.review(draft("ws-1", note: "调用时用的是 sk-abcdefghij0123456789 这个键"))
        XCTAssertFalse(review.isAccepted)
        XCTAssertTrue(review.rejections.contains(.secretFragment(count: 1)), "\(review.rejections)")

        let result = try store.record(draft("ws-1", note: "password=hunter2hunter2 记一下"))
        XCTAssertFalse(result.accepted, "密钥片段被挡 ⇒ 不落盘")
        XCTAssertTrue(result.rejections.contains(.secretFragment(count: 1)), "\(result.rejections)")
        XCTAssertTrue(store.entries(workspace: "ws-1").entries.isEmpty)

        // 别的工作区里也不该出现（拒收就是没写）。
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.factFileURL(workspace: "ws-1").path))
    }

    func testRowLikeContentIsRejectedAndCounted() throws {
        let table = try store.record(draft("ws-1", note: "| 1 | alice | 2026-01-01 |"))
        XCTAssertFalse(table.accepted, "看着是结果集行 ⇒ 拒收")
        XCTAssertTrue(table.rejections.contains(.rowLikeContent(count: 1)), "\(table.rejections)")

        let tsv = try store.record(draft("ws-1", note: "1\talice\t2026-01-01"))
        XCTAssertFalse(tsv.accepted)
        XCTAssertTrue(tsv.rejections.contains(.rowLikeContent(count: 1)), "\(tsv.rejections)")
        XCTAssertTrue(store.entries(workspace: "ws-1").entries.isEmpty)
    }

    func testEmptyNoteIsRejected() throws {
        let result = try store.record(draft("ws-1", note: "   \n  "))
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.rejections, [.emptyNote])
        XCTAssertTrue(store.entries(workspace: "ws-1").entries.isEmpty)
    }

    /// 手改文件塞进来一行带 `rows` 字段的：**键不在白名单外一律不认**，而且如实计数。
    func testHandEditedLineWithAnExtraKeyIsSkippedAndCounted() throws {
        let smuggled = "{\"id\":\"m-x\",\"workspace\":\"ws-1\",\"connection\":\"prod\",\"kind\":\"routine\","
            + "\"note\":\"n\",\"fingerprint\":\"f\",\"firstSeenAt\":\"0\",\"lastUsedAt\":\"0\",\"useCount\":1,"
            + "\"rows\":[[1,\"alice\"]]}"
        try writeRaw([try headerLine("ws-1"),
                      try entryLine(handmadeEntry(id: "m-ok", workspace: "ws-1", note: "正常的一条", at: now)),
                      smuggled],
                     workspace: "ws-1")

        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.map(\.id), ["m-ok"], "白名单之外的行不许读进来")
        XCTAssertEqual(loaded.skippedLines, 1, "跳过几个行要如实报数")
        XCTAssertFalse(loaded.entries.map(\.note).joined().contains("alice"))
    }

    /// **纵深防御**：万一有条目绕过了写入闸（手改文件），它进上下文时仍会被外发边界挡下并计数。
    func testRowDataThatBypassedIntakeIsStillRedactedOnTheWayOut() throws {
        try writeRaw([try headerLine("ws-1"),
                      try entryLine(handmadeEntry(id: "m-row", workspace: "ws-1",
                                                  note: "| 1 | alice | 2026-01-01 |", at: now))],
                     workspace: "ws-1")
        let loaded = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(loaded.count, 1, "键都合法，所以读得回来")

        let payload = AgentContextAssembler.assemble(AgentMemoryContext.references(from: loaded, now: now))
        XCTAssertEqual(payload.totalRedactedRows, 1, "外发前照样被挡下并计数")
        XCTAssertFalse(payload.text.contains("alice"), "结果集内容一个字都不许外发")
        XCTAssertTrue(payload.text.contains("[row]"), "挡掉的地方要留机器形态的痕迹")
    }

    // MARK: - ⑤ 删掉索引能从事实源重建

    func testIndexIsADerivedCacheRebuildableByteForByte() throws {
        _ = try store.record(draft("ws-1", note: "甲"), at: daysAgo(3))
        _ = try store.record(draft("ws-1", note: "乙"), at: daysAgo(2))
        _ = try store.record(draft("ws-1", connection: "stage", note: "丙"), at: daysAgo(1))

        let factsBefore = try Data(contentsOf: store.factFileURL(workspace: "ws-1"))
        let built = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        let bytesBefore = try XCTUnwrap(store.readIndexData(workspace: "ws-1"))
        XCTAssertTrue(store.hasIndex(workspace: "ws-1"))
        XCTAssertEqual(built.entryCount, 3)
        XCTAssertEqual(built.count(of: .routine), 3)
        XCTAssertEqual(built.items.map(\.connection).sorted(), ["prod", "prod", "stage"])

        // 删掉索引 ⇒ 事实源一字不动，数据一条不丢。
        XCTAssertTrue(store.removeIndex(workspace: "ws-1"))
        XCTAssertFalse(store.hasIndex(workspace: "ws-1"))
        XCTAssertNil(store.loadIndex(workspace: "ws-1"), "删掉就是没有，不许返回陈旧值")
        XCTAssertEqual(try Data(contentsOf: store.factFileURL(workspace: "ws-1")), factsBefore)
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 3)

        // 重建 ⇒ 与删之前**逐字节一致**（同一份事实源 + 同一个注入时刻）。
        let rebuilt = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertEqual(rebuilt, built)
        let bytesAfter = try XCTUnwrap(store.readIndexData(workspace: "ws-1"))
        XCTAssertEqual(bytesAfter, bytesBefore, "重建出来的索引逐字节一致（可 diff、可进版本库）")
        XCTAssertEqual(try Data(contentsOf: store.factFileURL(workspace: "ws-1")), factsBefore,
                       "索引是派生的：事实源不因它而变")
    }

    func testIndexFollowsWritesAndDeletions() throws {
        let first = try XCTUnwrap(try store.record(draft("ws-1", note: "甲"), at: daysAgo(2)).entry)
        _ = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertEqual(store.loadIndex(workspace: "ws-1")?.ids, [first.id])

        let second = try XCTUnwrap(try store.record(draft("ws-1", kind: .pinned, note: "乙"), at: daysAgo(1)).entry)
        let grown = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertEqual(grown.ids, [second.id, first.id], "新建的在前（最近用到倒序）")
        XCTAssertEqual(grown.count(of: .pinned), 1)

        XCTAssertTrue(try store.remove(id: first.id, workspace: "ws-1"))
        XCTAssertEqual(try store.rebuildIndex(workspace: "ws-1", builtAt: now).ids, [second.id])
    }

    func testCorruptIndexFileIsRecoveredByRebuilding() throws {
        _ = try store.record(draft("ws-1", note: "甲"), at: now)
        _ = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        try "这不是索引".write(to: store.indexFileURL(workspace: "ws-1"), atomically: true, encoding: .utf8)

        XCTAssertNil(store.loadIndex(workspace: "ws-1"), "派生缓存坏掉 ⇒ 当作没有（重建就是了）")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 1, "事实源不受影响")
        XCTAssertEqual(try store.rebuildIndex(workspace: "ws-1", builtAt: now).ids.count, 1)
    }

    // MARK: - ⑥ 坏文件 / 认不出的条目跳过并计数

    func testCorruptLinesAreSkippedAndCountedButTheLayerStaysUsable() throws {
        try writeRaw([try headerLine("ws-1"),
                      try entryLine(handmadeEntry(id: "m-1", workspace: "ws-1", note: "好的一条", at: now)),
                      "这不是 JSON",
                      "{\"half\":\"written\""],
                     workspace: "ws-1")
        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.map(\.id), ["m-1"], "坏行不许让整层不可用")
        XCTAssertEqual(loaded.skippedLines, 2, "跳过了几行要如实报")
        XCTAssertFalse(loaded.workspaceMismatch)
        XCTAssertFalse(loaded.missingHeader)
    }

    func testUnreadableFileIsSkippedAndCounted() throws {
        let url = store.factFileURL(workspace: "ws-bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00, 0x01, 0x80]).write(to: url)

        let loaded = store.entries(workspace: "ws-bin")
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertEqual(loaded.skippedFiles, 1, "读不了的文件的份数要如实报")
        XCTAssertTrue(loaded.hasSkippedReadings)
    }

    /// 「认不出的条目」：形状合法、但 `kind` 不在词表里 ⇒ 跳过并计数。
    func testUnknownKindEntryIsSkippedAndCountedAndStaysOutOfTheIndex() throws {
        try writeRaw([try headerLine("ws-1"),
                      try entryLine(handmadeEntry(id: "m-good", workspace: "ws-1", note: "认得出的一条", at: now)),
                      try entryLine(handmadeEntry(id: "m-weird", workspace: "ws-1", kind: "nonsense",
                                                  note: "认不出的一条", at: now))],
                     workspace: "ws-1")
        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.map(\.id), ["m-good"])
        XCTAssertEqual(loaded.unknownEntries, 1, "认不出的条目要计数")
        XCTAssertEqual(loaded.skippedLines, 0, "它不是坏行，是**认不出**——两个读数分得开")

        let index = try store.rebuildIndex(workspace: "ws-1", builtAt: now)
        XCTAssertEqual(index.ids, ["m-good"], "认不出的条目不许进派生索引")
        XCTAssertEqual(store.inspect(workspace: "ws-1", now: now).unknownEntries, 1)
    }

    /// 归属不是本工作区的条目：**看不到**，但读数里看得出来（不是静默丢）。
    func testForeignEntryInsideTheFileIsCountedAndInvisible() throws {
        try writeRaw([try headerLine("ws-1"),
                      try entryLine(handmadeEntry(id: "m-mine", workspace: "ws-1", note: "我的", at: now)),
                      // 整份文件被复制过来的现场：某一行的 workspace 不是本工作区。
                      try entryLine(handmadeEntry(id: "m-theirs", workspace: "ws-other", note: "别人的", at: now))],
                     workspace: "ws-1")

        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.map(\.id), ["m-mine"])
        XCTAssertEqual(loaded.foreignEntries, 1)
        XCTAssertEqual(loaded.skippedLines, 0)
        XCTAssertEqual(loaded.unknownEntries, 0)
        XCTAssertTrue(loaded.hasSkippedReadings, "有读数 ⇒ 界面上要能说出「有 1 条不是这个工作区的」")
    }

    /// 有内容却找不到头一行 ⇒ 如实报「头找不着」，且**不覆盖**（别把读不出来的东西悄悄清掉）。
    func testMissingHeaderIsReportedAndRefusesToBeOverwritten() throws {
        try writeRaw([try entryLine(handmadeEntry(id: "m-1", workspace: "ws-1", note: "没有头一行", at: now))],
                     workspace: "ws-1")
        let loaded = store.entries(workspace: "ws-1")
        XCTAssertTrue(loaded.missingHeader)
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertTrue(loaded.hasSkippedReadings)

        let refused = try store.record(draft("ws-1", note: "新的一条"), at: now)
        XCTAssertFalse(refused.accepted)
        XCTAssertTrue(refused.rejections.contains(.sourceUnreadable), "\(refused.rejections)")
        XCTAssertTrue(store.entries(workspace: "ws-1").missingHeader, "事实源没被悄悄覆盖")
    }

    // MARK: - 写入有上限

    func testWriteIsBoundedByTheLimitAndEvictionIsReported() throws {
        let limits = AgentMemoryLimits(maxEntriesPerWorkspace: 3, maxNoteCharacters: 200)
        // 注意：条目正文**故意不用「第 0 条 / 第 1 条」这种写法** —— 粗指纹会把数字字面量归一成 `?`，
        // 五条会当场并成一条（`QueryMemory.coarseFingerprint` 的既定口径，不是这里能绕的）。
        let notes = ["条目甲", "条目乙", "条目丙", "条目丁", "条目戊", "条目己"]
        var ids: [String] = []
        for index in 0..<5 {
            let result = try store.record(draft("ws-1", note: notes[index]),
                                          limits: limits,
                                          at: now.addingTimeInterval(Double(index) * 60))
            ids.append(try XCTUnwrap(result.entry?.id))
        }
        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.count, 3, "写入有上限：只剩 3 条")
        XCTAssertEqual(loaded.entries.map(\.id), [ids[4], ids[3], ids[2]], "留下的是最近用到的")
        XCTAssertFalse(loaded.entries.map(\.note).contains(notes[0]), "最近最少用的先出")

        // 挤出要**如实报数**（写第 4、5 条时各挤掉了当时最旧的那一条）。
        let last = try store.record(draft("ws-1", note: notes[5]), limits: limits,
                                    at: now.addingTimeInterval(300))
        XCTAssertEqual(last.evictedIDs, [ids[2]], "第 6 条进来 ⇒ 当时最旧的那条被挤出，并点名")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 3)
    }

    func testLongNoteIsTruncatedAndTheTruncationIsReported() throws {
        let limits = AgentMemoryLimits(maxEntriesPerWorkspace: 10, maxNoteCharacters: 12)
        let long = String(repeating: "abcdefghij", count: 4)
        let result = try store.record(draft("ws-1", note: long), limits: limits, at: now)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.truncatedCharacters, long.count - 12, "截掉多少要报准")
        XCTAssertEqual(result.entry?.note.count, 12)
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.first?.note.count, 12)
    }

    func testMergingKeepsTheLayerFromGrowing() throws {
        let limits = AgentMemoryLimits(maxEntriesPerWorkspace: 1, maxNoteCharacters: 200)
        let note = "一遍又一遍地记同一件事"
        _ = try store.record(draft("ws-1", note: note), limits: limits, at: daysAgo(1))
        let again = try store.record(draft("ws-1", note: note), limits: limits, at: now)
        XCTAssertTrue(again.merged)
        XCTAssertTrue(again.evictedIDs.isEmpty, "合并不会挤掉任何东西")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.map(\.useCount), [2])
    }

    /// 上限是**上一次写**的刻度：写进来那一条自己永远不被挤出（否则「记了它」当场不成立）。
    func testTheJustWrittenEntrySurvivesTheLimit() throws {
        let limits = AgentMemoryLimits(maxEntriesPerWorkspace: 1, maxNoteCharacters: 200)
        _ = try store.record(draft("ws-1", note: "旧的"), limits: limits, at: daysAgo(1))
        let fresh = try store.record(draft("ws-1", note: "新的"), limits: limits, at: now)
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.map(\.note), ["新的"])
        XCTAssertEqual(fresh.evictedIDs.count, 1)
    }

    // MARK: - 进上下文的那条通道

    func testContextReferencesAreOrderedLimitedAndSelfDescribing() throws {
        let oldest = try XCTUnwrap(try store.record(draft("ws-1", kind: .routine, note: "最早的一条"), at: daysAgo(3)).entry)
        let middle = try XCTUnwrap(try store.record(draft("ws-1", kind: .pinned, note: "中间的一条"), at: daysAgo(2)).entry)
        let newest = try XCTUnwrap(try store.record(draft("ws-1", kind: .routine, note: "最新的一条"), at: daysAgo(1)).entry)
        let loaded = store.entries(workspace: "ws-1").entries

        let refs = AgentMemoryContext.references(from: loaded, now: now)
        XCTAssertEqual(refs.count, 3)
        XCTAssertEqual(refs.first, AgentMemoryContext.reference(for: newest), "最近用到的在前")

        let everything = store.inspect(workspace: "ws-1", now: now)
        XCTAssertEqual(everything.entries.count, 3, "检视看得见全部")

        let limited = AgentMemoryContext.references(from: loaded, now: now, limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited.last, AgentMemoryContext.reference(for: middle))

        // 段的路径是自解释的（模型看得出这是什么、哪一档）。
        guard case let .file(path, text) = refs[0] else { return XCTFail("要走 .file 这条通道") }
        XCTAssertTrue(path.hasPrefix("memory://ws-1/"), path)
        XCTAssertTrue(path.contains(oldest.kind) || path.contains(newest.kind), path)
        XCTAssertEqual(text, newest.note, "带进上下文的是那条记忆的正文")

        // 统一走装配器 ⇒ 截断 / 边界过滤 / 外发预览都在那一处（本层不自己拼提示词）。
        let assembled = AgentContextAssembler.assemble(refs)
        XCTAssertEqual(assembled.preview, assembled.text)
        XCTAssertEqual(assembled.totalRedactedSecrets, 0)
    }

    func testDefaultDirectorySitsNextToTheOtherAgentStores() throws {
        let memory = AgentMemoryStore.defaultDirectory
        let sessions = AgentSessionStore.defaultDirectory
        XCTAssertEqual(memory.lastPathComponent, AgentMemory.directoryName)
        XCTAssertEqual(memory.deletingLastPathComponent(), sessions.deletingLastPathComponent(),
                       "与其余本机数据同一处（不另开文件体系）")
    }
}
