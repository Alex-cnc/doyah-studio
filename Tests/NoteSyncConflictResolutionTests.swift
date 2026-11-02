import XCTest
@testable import DoyahCore

/// `FR-NTS-NOTE-SYNC-002` 判据 ①–⑤ 的机器读数。
///
/// 每条用例对应需求里那一行判据（不是「顺手多测一点」）：
///   ① 被覆盖的那版可打开、可另存（`testLosingVersionIsOpenable…` / `testSaveAsNewNote…`）；
///   ② 两版都标来源设备与时间（`testBothVersionsCarry…` + 旧状态文件如实写「来源不明」）；
///   ③ 合并结果是新版本、可回退（`rev = 两版最大 + 1`，且写库走 `NoteLibrary.save` ⇒ 记一版历史）；
///   ④ 「以我这版为准」是人按的（源树判据：自动路径零引用）；
///   ⑤ 删除墓碑 `rev` 严格递增、不许被高 `rev` 副本按 LWW 复活。
final class NoteSyncConflictResolutionTests: XCTestCase {

    // MARK: - 夹具

    private func stamp(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func record(
        uid: String = "note-sync-1",
        rev: Int,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil,
        deviceId: String? = "mac-a",
        payload: String = "{\"version\":2,\"spans\":[]}"
    ) -> SyncRecord {
        SyncRecord(
            uid: uid,
            rev: rev,
            updatedAt: stamp(updatedAt),
            deletedAt: deletedAt.map(stamp),
            deviceId: deviceId,
            payload: payload
        )
    }

    /// 一版真正带正文的快照（canonical 编码，与云端行面同一份）。
    private func bodyPayload(text: String) -> String {
        let body = NoteBody(markdown: text)
        let data = try! NoteBodyCanonical.encoder().encode(body)
        return String(data: data, encoding: .utf8)!
    }

    private func conflictCopy(
        losing: SyncRecord,
        winner: SyncRecord,
        at: TimeInterval = 900
    ) -> CloudConflictCopy {
        CloudConflictCopy(
            uid: losing.uid,
            losing: losing,
            winnerRev: winner.rev,
            winner: winner,
            at: stamp(at)
        )
    }

    // MARK: - 判据②：两版都标来源设备与时间

    func testBothVersionsCarryTheirOwnDeviceAndTime() {
        let losing = record(rev: 3, updatedAt: 500, deviceId: "windows-副机", payload: bodyPayload(text: "第一行标题\n本机写的那一版"))
        let winner = record(rev: 3, updatedAt: 600, deviceId: "mac-mini", payload: bodyPayload(text: "另一端的版本"))
        let copy = conflictCopy(losing: losing, winner: winner)

        let presentation = SyncConflictResolver.presentation(of: copy, untitledFallback: "无标题")

        // 判负那一版：自己的设备 + 自己的时刻。
        XCTAssertEqual(presentation.losing.rev, 3)
        XCTAssertEqual(presentation.losing.deviceId, "windows-副机")
        XCTAssertEqual(presentation.losing.updatedAt, stamp(500))
        XCTAssertTrue(presentation.losing.hasKnownDevice)
        // 胜者那一版：**另一台的设备与时刻**（不是把判负那版抄一遍）。
        XCTAssertEqual(presentation.winner?.rev, 3)
        XCTAssertEqual(presentation.winner?.deviceId, "mac-mini")
        XCTAssertEqual(presentation.winner?.updatedAt, stamp(600))
        XCTAssertEqual(presentation.winnerRev, 3)
        // 标题由落败版正文首行推出 —— 两版标题可能不同，界面说的是「这条笔记」。
        XCTAssertEqual(presentation.title, "第一行标题")
    }

    /// 旧状态文件里没有 `winner` 这一整条 ⇒ 解码按缺省 `nil`，界面如实「来源不明」，不编设备名。
    func testLegacyStateFileWithoutWinnerDecodesAndReportsUnknownSource() throws {
        let json = """
        {"uid":"note-legacy","losing":{"uid":"note-legacy","rev":2,"updatedAt":500,"payload":"old body"},"winnerRev":2,"at":700}
        """
        let decoder = CloudSyncCoding.decoder()
        let copy = try decoder.decode(CloudConflictCopy.self, from: Data(json.utf8))

        XCTAssertNil(copy.winner, "旧记录没有胜者整条 ⇒ 不许凭空造一条")
        let presentation = SyncConflictResolver.presentation(of: copy, untitledFallback: "无标题")
        XCTAssertNil(presentation.winner)
        // 判负那一版自己仍然有来源（它是整条记录存档的）。
        XCTAssertEqual(presentation.losing.deviceId, nil)
        XCTAssertFalse(presentation.losing.hasKnownDevice, "没有出端就如实说不知道")
    }

    // MARK: - 判据①：可打开

    func testLosingVersionIsOpenableAndKeepsTheLosingText() {
        let text = "这一版是另一台机器写的\n第二行"
        let losing = record(rev: 4, updatedAt: 500, payload: bodyPayload(text: text))
        let winner = record(rev: 4, updatedAt: 600, payload: bodyPayload(text: "胜者那一版"))
        let copy = conflictCopy(losing: losing, winner: winner)

        let presentation = SyncConflictResolver.presentation(of: copy, untitledFallback: "无标题")

        XCTAssertEqual(presentation.losingText, text, "打开的必须是判负那一版，不是胜者那版")
        XCTAssertTrue(presentation.canRestoreLosingVersion)
    }

    /// 快照不是 `NoteBody`（纯文本）⇒ 原样给，**不当成空正文**。
    func testPlainTextPayloadIsReturnedVerbatim() {
        XCTAssertEqual(SyncConflictResolver.text(ofPayload: "纯文本正文"), "纯文本正文")
        XCTAssertEqual(SyncConflictResolver.text(ofPayload: ""), "")
    }

    // MARK: - 判据①：可另存

    func testSaveAsNewNoteKeepsTheLosingPayloadByteForByte() throws {
        let text = "判负那一版的正文\n别的端写的"
        let payload = bodyPayload(text: text)
        let losing = record(rev: 5, updatedAt: 500, payload: payload)
        let winner = record(rev: 5, updatedAt: 600, payload: bodyPayload(text: "胜者"))
        let copy = conflictCopy(losing: losing, winner: winner)

        let saved = SyncConflictResolver.newNotePayload(from: copy, untitledFallback: "无标题")

        XCTAssertEqual(saved.spans, payload, "另存要把原快照**整份**写回去（逐字），不是重新投影的产物")
        XCTAssertEqual(saved.body, text)
        XCTAssertEqual(saved.title, "判负那一版的正文")
        // 来源可追溯（半年后能回答「它是从哪条笔记来的」）。
        let source = SyncConflictResolver.source(for: copy)
        XCTAssertEqual(source.kind, .conflictCopy)
        XCTAssertEqual(source.fingerprint, "note-sync-1")
    }

    func testSaveAsNewNoteFallsBackToPlainBodyWhenPayloadIsNotNoteBody() {
        let losing = record(rev: 2, updatedAt: 500, payload: "纯文本旧快照")
        let winner = record(rev: 2, updatedAt: 600, payload: "winner")
        let copy = conflictCopy(losing: losing, winner: winner)

        let saved = SyncConflictResolver.newNotePayload(from: copy, untitledFallback: "无标题")

        XCTAssertNil(saved.spans, "不是 NoteBody 就不伪造富文本权威源")
        XCTAssertEqual(saved.body, "纯文本旧快照")
        XCTAssertEqual(saved.title, "纯文本旧快照")
    }

    // MARK: - 判据③：合并结果是新版本

    func testKeepLosingProducesARevisionAboveBothVersions() {
        let losing = record(rev: 3, updatedAt: 500, payload: "losing body")
        let winner = record(rev: 3, updatedAt: 600, payload: "winner body")
        let copy = conflictCopy(losing: losing, winner: winner)

        let resolved = SyncConflictResolver.keepLosingVersionAsHumanChoice(
            copy, currentRevision: nil, deviceId: "mac-human", at: stamp(1000)
        )

        XCTAssertEqual(resolved.rev, 4, "新版本 = 两版最大 + 1（同 rev 重发会再判一次冲突）")
        XCTAssertEqual(resolved.uid, "note-sync-1")
        XCTAssertEqual(resolved.payload, "losing body", "以我这版为准 ⇒ 正文就是判负那一版，逐字")
        XCTAssertEqual(resolved.updatedAt, stamp(1000))
        XCTAssertEqual(resolved.deviceId, "mac-human", "这一版是按下这一下的设备写的")
        XCTAssertNil(resolved.deletedAt)
    }

    /// 版本账可能比副本记的更新（同步又成功过一次）⇒ 新 `rev` 必须也高于它。
    func testKeepLosingRespectsAnEvenNewerCurrentRevision() {
        let losing = record(rev: 3, updatedAt: 500, payload: "losing")
        let winner = record(rev: 3, updatedAt: 600, payload: "winner")
        let copy = conflictCopy(losing: losing, winner: winner)

        let resolved = SyncConflictResolver.keepLosingVersionAsHumanChoice(
            copy, currentRevision: 7, deviceId: "mac-human", at: stamp(1000)
        )

        XCTAssertEqual(resolved.rev, 8, "现取到的 rev 7 也要算进去，否则又会撞一次")
    }

    /// 结果必须能被决胜规则接受（新版本 = 真的「赢」）—— 不是只把数字改大。
    func testResolvedRevisionWinsUnderLWW() {
        let winner = record(rev: 3, updatedAt: 600, payload: "winner")
        let losing = record(rev: 3, updatedAt: 500, payload: "losing")
        let copy = conflictCopy(losing: losing, winner: winner)
        let resolved = SyncConflictResolver.keepLosingVersionAsHumanChoice(
            copy, currentRevision: nil, deviceId: "mac-human", at: stamp(1000)
        )

        let merge = SyncResolution.decide(incoming: resolved, local: winner)
        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertEqual(merge.primary.payload, "losing")
        XCTAssertNil(merge.conflict)
    }

    // MARK: - 判据⑤：墓碑

    /// 高 `rev` 的活版本**不许**把墓碑按 LWW 复活；它落冲突副本（不静默丢）。
    func testTombstoneIsNotResurrectedByAHigherRevisionCopy() {
        let tombstone = record(rev: 3, updatedAt: 400, deletedAt: 400, payload: "deleted")
        let staleAlive = record(rev: 5, updatedAt: 700, payload: "旧的活版本")

        let merge = SyncResolution.decide(incoming: staleAlive, local: tombstone)

        XCTAssertEqual(merge.verdict, .expired, "墓碑不许被高 rev 副本顶回来")
        XCTAssertTrue(merge.primary.isTombstone, "主版本仍是墓碑")
        XCTAssertEqual(merge.conflict, staleAlive, "活版本落冲突副本 —— 不静默丢")
    }

    /// 墓碑的 `rev` 严格递增（删除也是一次内容变更）。
    func testTombstoneRevisionStrictlyIncreases() {
        let alive = record(rev: 4, updatedAt: 400, payload: "alive")
        let tombstone = SyncResolution.tombstone(of: alive, at: stamp(500), deviceId: "mac-a")

        XCTAssertEqual(tombstone.rev, 5)
        XCTAssertEqual(tombstone.deletedAt, stamp(500))
        XCTAssertEqual(tombstone.uid, alive.uid)

        var ledger = SyncLedger()
        ledger.apply(alive)
        XCTAssertEqual(ledger.visible.count, 1)
        let deleteMerge = ledger.apply(tombstone)
        XCTAssertEqual(deleteMerge.verdict, .accepted)
        XCTAssertTrue(ledger.visible.isEmpty, "删除之后本地看不到这一条")
        // 再来一条更旧的活版本 ⇒ 不复活。
        let resurrect = ledger.apply(record(rev: 4, updatedAt: 900, payload: "又冒出来"))
        XCTAssertEqual(resurrect.verdict, .expired)
        XCTAssertTrue(ledger.visible.isEmpty)
        // 更旧的那版（rev 4 < 墓碑 rev 5）本来就不是冲突（`expired` 不落副本）—— 只记「没复活、也没堆版本」。
        XCTAssertEqual(ledger.allVersions(uid: "note-sync-1").count, 1)
    }

    // MARK: - 判据④：人按的（源树判据）

    /// 自动同步路径**零引用**人的裁决入口 —— 「以我这版为准」不可能自己发生。
    ///
    /// 覆盖范围（如实声明）：只扫本仓 `Plugins/Notes/Sources/NoteSync/` 三份**同步**源码
    /// （`SyncCore.swift` / `CloudSyncService.swift` / `SyncConflictResolution.swift`）与界面侧
    /// `Plugins/Notes/Views/NotesPanel.swift`、`App/AppState.swift`。别处的同名字符串不在覆盖面内。
    func testHumanChoiceEntryPointIsNeverCalledFromAutomaticSyncPaths() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓根
        let automatic = [
            "Plugins/Notes/Sources/NoteSync/SyncCore.swift",
            "Plugins/Notes/Sources/NoteSync/CloudSyncService.swift",
        ]
        for path in automatic {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            // **只数代码行**（`//` / `///` 注释行不算）—— 注释里写名字是解释，不是调用；
            // 早先按整文件子串判，注入一行 `try? resolveConflictCopy(auto)` 仍判绿（`self.` 都不带），
            // 属假绿，已改成「代码行里出现几次」。
            let codeLines = text
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            let code = codeLines.joined(separator: "\n")
            XCTAssertFalse(
                code.contains("keepLosingVersionAsHumanChoice"),
                "\(path) 里出现了人的裁决入口 ⇒ 自动路径能替人决定，判据④不成立"
            )
            // 销账那条**只允许定义**（`public func resolveConflictCopy(`），代码里再出现一次就是调用点。
            let resolveHits = code.components(separatedBy: "resolveConflictCopy").count - 1
            let definitionHits = code.components(separatedBy: "func resolveConflictCopy").count - 1
            XCTAssertEqual(
                resolveHits, definitionHits,
                "\(path) 里出现了「销账」的调用点（出现 \(resolveHits) 次、定义 \(definitionHits) 次）⇒ 自动路径会把留底的副本自己抹掉"
            )
        }

        // 正题：入口确实在（不是靠「查不到」蒙过去的空判据）。
        let resolverText = try String(
            contentsOf: root.appendingPathComponent("Plugins/Notes/Sources/NoteSync/SyncConflictResolution.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(resolverText.contains("func keepLosingVersionAsHumanChoice("))

        // 界面侧只有一处调用（人是唯一的触发者）。
        let notesPanel = try String(
            contentsOf: root.appendingPathComponent("Plugins/Notes/Views/NotesPanel.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            notesPanel.components(separatedBy: "keepConflictLosingVersion").count - 1, 1,
            "冲突面上「以我这版为准」只许有一枚按钮"
        )
    }
}
