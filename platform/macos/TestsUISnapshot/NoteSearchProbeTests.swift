import Combine
import Foundation
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **「待人工验收清单」B 类 · 第九批（队列 `L-89` ㈡ 第 7、8 条）**：
/// 笔记检索里那两条「只能人工点」的条目 —— 两条都是**速度差**造成的，人的眼睛恰好派不上用场。
///
///   · **存完立刻搜**（清单原文：「搜一个词 → 清空搜索框 → 新建一条**带这个词**的笔记 → 保存 → 再搜那个词」
///     → 过 =「刚存的那条**在结果里**」）—— 要判的是 L-44 收口时接上的那条线：
///     `reloadNotes()` 末尾要把正在跑的检索**跟着重算**，否则「刚存下的那条在搜索结果里永远不出现、
///     刚删掉的那条还在结果里」。**这条线没有任何东西看得见**：搜出来的列表少了刚存的那条，
///     看起来就跟「没搜到」一模一样。
///   · **键盘快打**（清单原文：「快速连续输入」→ 过 =「结果不『倒回去』（迟到的查询结果不许覆盖新的）」）
///     —— 人手打字与 SQLite 查库**谁快谁慢不可控**，靠人去点就是在撞窗口。
///
/// ## 判据怎么落（三条，各自独立）
///
/// ① **真 AppState + 真库**（`DOYAH_NOTES_DIR` 指向每轮清空的临时目录；产品自己的 `NoteLibrary`，
///    不是测试替身）：查询在搜索框里没动过的情况下，存下一条带这个词的笔记 ⇒ 它必须**当场在结果里**；
///    反向同理（删掉一条 ⇒ 当场从结果里消失）；清单原文那两个先后顺序也各判一遍。
/// ② **唯一落地出口**（本批应用侧的改动）：`AppState.settleNoteSearch(_:for:)` 是检索结果的**唯一**落地出口，
///    它自带「这一次的结果对应的还是不是搜索框里的词」这一句判断，并且**把判断结果当返回值**交出来 ——
///    于是「迟到的结果被丢掉」这件事可以被**直接断言**，不必去撞时序窗口。
/// ③ **端到端那一次**（真库、真 `AppState`）：一次带着旧词的检索在途，词换成新的之后它的结果才回来 ⇒
///    ① 订阅 `$noteSearchState` 记下**每一次落地**（连同落地那一刻搜索框里的词），不变量 =
///    「没有任何一次落地是在搜索框里的词与它自己的词不一致时发生的」；② 再把「旧词的结果晚到」在
///    `runSearch(_:for:)` 上跑一遍，状态必须一个字节不动。
///
/// ## 边界（如实写在前面）
///
/// · 查询是**单字**时走子串兜底（trigram 不产出 token），与界面同一条路；本批**不**判「哪条路更准」
///   （那是 L-44 的判据与 `note-search-route.json` 的事）。
/// · 竞态那条判的是**界面这一层**（落地出口 + 调用序）：SQLite 自己的并发语义不在本批范围。
/// · `$noteSearchState` 是 **willSet** 语义（发出的那一拍，`state.noteSearchState` 还是旧值）——
///   记落地必须取**闭包参数那个新值**，读 `state.visibleNotes` 会拿到上一次的结果
///   （第一版就这么写错了，当场判红逼出来的：`AGENT-SPEC.md` §9 第 79 条）。
/// · **夹具自己清库**：同一次探针跑里所有用例共用一个 `DOYAH_NOTES_DIR`（同进程），
///   别的用例播下的笔记会留下来 ⇒ 每个用例开头清库、结尾也清库（不把自己的痕迹留给别人）。
/// · 本文件与快照同纪律：`DOYAH_UI_SNAPSHOT=1` 才跑（取证工具，不进每轮门禁）；
///   证据 JSON 落在 `DOYAH_SNAPSHOT_DIR`，由 `Scripts/run-manual-verification-probes.sh` 核对
///   —— **跳过 ≠ 通过**（探针没跑时文件不存在，脚本判红）。
final class NoteSearchProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "笔记检索探针要往真库里写夹具：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    // MARK: - 纪律与装配

    /// **往笔记库写夹具的用例必须先过这一关**（与 `UISnapshotPanelsTests` 同一条纪律）。
    ///
    /// 笔记库的落点是**产品真实数据目录**（`<Application Support>/DoyahNotes/notes.sqlite3`），
    /// 只有 `DOYAH_NOTES_DIR` 在场时才指向临时目录。本文件的夹具**每一步都在写库**
    /// （存笔记 / 删笔记 / 换库文件），缺变量时**跳过并说清为什么** ——
    /// 绝不允许往真实用户数据家留下测试痕迹。
    private func requireIsolatedNotesDirectory() throws {
        let override = ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? ""
        try XCTSkipIf(
            override.isEmpty,
            "本用例要往笔记库里写夹具 ⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
                + "（用 `Scripts/run-manual-verification-probes.sh` 或自己给一个临时目录）"
        )
    }

    /// 清掉整个库（主文件 + WAL 两个侧车）。
    ///
    /// 同一次跑里所有用例共用一份 `DOYAH_NOTES_DIR`：不清就是「上一个用例播下的笔记还算数」，
    /// 判据会随用例执行顺序漂（第一版实测：搜「山」查出两条同名笔记、搜「湖」查出三条 —— 全是别人的夹具）。
    private func removeLibrary() {
        let url = NoteLibrary.defaultDatabaseURL()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// 真 `AppState`（Standard 档 —— 笔记能力就在这一档）+ **等启动链落地** + 干净库。
    ///
    /// 启动链末尾会去库里读一次笔记；不等它就播种，那次读会晚于播种落地，
    /// 把内存列表填成另一份值 —— 判据不许看运气。
    @MainActor
    private func makeState() async throws -> AppState {
        removeLibrary()
        let state = AppState()
        await state.startupChain?.value
        _ = try UISnapshot.applyLicense(.standard, to: state)
        XCTAssertTrue(state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")
        return state
    }

    /// 证据文件落在快照目录（`DOYAH_SNAPSHOT_DIR`）；**脚本会核对它** —— 探针没真跑时文件不存在 ⇒ 判红。
    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["notesDirectory"] = NoteLibrary.defaultDirectory().path
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("note-search-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    /// 用产品自己的库写一条笔记（返回落库后的那条）—— 夹具走的是与界面同一个入口。
    private func seed(_ title: String, body: String, into library: NoteLibrary) async throws -> Note {
        try await library.upsert(
            NoteDraft(title: title, body: body, tags: [], source: NoteSource(kind: .manual))
        )
    }

    private func titles(_ notes: [Note]) -> [String] { notes.map(\.title) }

    /// 一次**落地**里带出来的笔记标题（willSet 语义 ⇒ 只能取闭包参数那个新值）。
    private func landedTitles(_ state: AppState.NoteSearchState) -> [String] {
        if case .library(_, let notes) = state { return notes.map(\.title) }
        return []
    }

    // MARK: - ① 存完立刻搜（清单原文：保存之后那一条必须当场在结果里）

    /// **查询还在搜索框里的时候存下一条带这个词的笔记 ⇒ 它必须当场出现在结果里**（不必再打一遍字）。
    ///
    /// 这就是 `reloadNotes()` 末尾那次重算的判据：去掉它，刚存的那条在结果里永远不出现，
    /// 而屏幕上看起来只是「少一条」—— 与「没搜到」长得一模一样。
    @MainActor
    func testSavingWhileTheQueryIsSetPutsTheNoteInTheResultsImmediately() async throws {
        try requireIsolatedNotesDirectory()
        let state = try await makeState()
        defer { UISnapshot.clearLicense(from: state); removeLibrary() }
        let library = NoteLibrary.defaultLibrary()

        // 夹具：让库存在（第一次用的时候库还不存在，检索会主动让路 —— 那是 L-44 的另一条口径）。
        _ = try await seed("基线一条", body: "与检索无关的内容", into: library)
        await state.reloadNotes()

        let keyword = "kubernetes"   // ≥3 字 ⇒ 走全文检索那条路（与本条判据无关，只是取个常见形状）
        state.notesQuery = keyword
        await state.searchNotes()
        let beforeSave = state.visibleNotes.count
        XCTAssertEqual(beforeSave, 0, "前置：此时还没有一条笔记带这个词")

        // ① 查询**一个字都没动**，直接新建并保存（界面上的动作：点「新建」→ 写字 → 点「保存」）。
        state.beginNewNote()
        state.noteEditorTitle = "新写的一条"
        state.noteEditorBody = "正文里带 \(keyword) 这个词"
        await state.saveNoteFromEditor()

        XCTAssertEqual(state.notesQuery, keyword, "前置：保存这条路不许动搜索框")
        let found = state.visibleNotes
        XCTAssertEqual(
            titles(found), ["新写的一条"],
            "刚存下的那条没有出现在结果里（`reloadNotes()` 末尾那次重算断了？）—— 实测结果：\(titles(found))"
        )
        XCTAssertTrue(
            state.notes.contains { $0.title == "新写的一条" },
            "内存列表里也没有刚存的那条 —— 保存这条路本身没落地"
        )

        try writeEvidence("saveThenSearch", [
            "queryAfterSave": state.notesQuery,
            "beforeSaveCount": beforeSave,
            "afterSaveTitles": titles(found),
        ])
    }

    /// **反向同一条线**：查询不动的情况下删掉一条 ⇒ 它必须当场从结果里消失。
    @MainActor
    func testDeletingWhileTheQueryIsSetDropsTheNoteFromTheResults() async throws {
        try requireIsolatedNotesDirectory()
        let state = try await makeState()
        defer { UISnapshot.clearLicense(from: state); removeLibrary() }
        let library = NoteLibrary.defaultLibrary()

        let target = try await seed("要删的一条", body: "正文带 kubernetes", into: library)
        _ = try await seed("留下的一条", body: "正文带 kubernetes", into: library)
        await state.reloadNotes()

        state.notesQuery = "kubernetes"
        await state.searchNotes()
        let beforeDelete = state.visibleNotes.count
        XCTAssertEqual(beforeDelete, 2, "前置：两条都该命中")

        await state.deleteNote(id: target.id)
        let left = state.visibleNotes
        XCTAssertEqual(
            titles(left), ["留下的一条"],
            "删掉的那条还留在检索结果里（列表变了没重算）—— 实测结果：\(titles(left))"
        )

        try writeEvidence("deleteWhileSearching", [
            "queryAfterDelete": state.notesQuery,
            "beforeDeleteCount": beforeDelete,
            "remainingTitles": titles(left),
        ])
    }

    /// **清单原文那两个先后顺序**：搜一个词 → 清空搜索框 → 新建带这个词的笔记 → 保存 → 再搜那个词。
    ///
    /// 与上面那条是**两条不同的路**：这条走「清空 → 保存 → 重新输入」，中间经过 `.idle`（空查询不是检索）。
    /// 两条都要成立 —— 只判一条，等于把另一半留给运气。
    @MainActor
    func testClearingThenSavingThenSearchingAgainFindsIt() async throws {
        try requireIsolatedNotesDirectory()
        let state = try await makeState()
        defer { UISnapshot.clearLicense(from: state); removeLibrary() }
        let library = NoteLibrary.defaultLibrary()

        _ = try await seed("基线一条", body: "与检索无关的内容", into: library)
        await state.reloadNotes()

        let keyword = "洞庭湖"
        state.notesQuery = keyword
        await state.searchNotes()
        XCTAssertEqual(state.visibleNotes.count, 0, "前置：库里还没有这条")

        // 清空搜索框（空查询**不是**检索）⇒ 列表回到全部笔记。
        state.notesQuery = ""
        await state.searchNotes()
        XCTAssertEqual(state.visibleNotes.count, 1, "清空之后应当看到全部笔记")

        state.beginNewNote()
        state.noteEditorTitle = "后来补的"
        state.noteEditorBody = "沿 \(keyword) 骑了一圈"
        await state.saveNoteFromEditor()

        state.notesQuery = keyword
        await state.searchNotes()
        let found = titles(state.visibleNotes)
        XCTAssertEqual(found, ["后来补的"], "按清单原文再搜一次，刚存的那条必须在结果里 —— 实测：\(found)")

        try writeEvidence("clearSaveSearch", [
            "queryAfterRetype": state.notesQuery,
            "foundTitles": found,
        ])
    }

    // MARK: - ② 唯一落地出口（键盘快打 · 决定点）

    /// **迟到的那一次结果不许落地**（两条：库给了结果 / 库没读出来），当前那个词的那一次必须落得下去。
    ///
    /// 判的是本批改动的那一个出口 —— 它把「这一次的结果对应的还是不是搜索框里的词」当返回值交出来，
    /// 所以「丢掉」这件事是被断言的，不是被撞上的。**留下的那只结果**同样要判：
    /// 只判「迟到的不许落地」而不管「该落的没落」，判据可以被一句 `return` 骗过去。
    @MainActor
    func testLateResultsAreDroppedAndCurrentOnesStillLand() async throws {
        try requireIsolatedNotesDirectory()
        let state = try await makeState()
        defer { UISnapshot.clearLicense(from: state); removeLibrary() }
        let library = NoteLibrary.defaultLibrary()

        _ = try await seed("湖的那条", body: "洞庭湖骑行", into: library)
        _ = try await seed("山的那条", body: "南太行拉练", into: library)
        await state.reloadNotes()

        // 先把搜索框摆到「山」上并真查一次 ⇒ 状态里是「山」的结果。
        state.notesQuery = "山"
        await state.searchNotes()
        let settled = titles(state.visibleNotes)
        XCTAssertEqual(settled, ["山的那条"], "前置：当前词的结果")

        // 一次**真实算出来的**「湖」的结果，在本该属于「山」的时刻送到出口。
        let stale = try await library.search("湖")
        XCTAssertEqual(stale.notes.count, 1, "前置：库里确实有一条命中「湖」")
        let staleApplied = state.settleNoteSearch(.results(stale), for: "湖")
        XCTAssertFalse(staleApplied, "迟到的结果被挡住了，但出口说自己落了地（返回值与行为不一致）")
        XCTAssertEqual(
            titles(state.visibleNotes), settled,
            "迟到的「湖」结果覆盖了「山」的结果 —— 键盘快打时屏幕上的结果会「倒回去」"
        )

        // 失败那一档同样只有一个出口。
        let staleFailureApplied = state.settleNoteSearch(.failure("库读不出来"), for: "湖")
        XCTAssertFalse(staleFailureApplied, "迟到的失败也不许落地（否则屏幕会突然说「库读不出来」）")
        XCTAssertEqual(titles(state.visibleNotes), settled, "迟到的失败改了状态")

        // **反向**：当前那个词的结果必须落得下去（否则判据可以被一句「永远丢掉」骗过去）。
        let current = try await library.search("山")
        XCTAssertTrue(state.settleNoteSearch(.results(current), for: "山"), "当前词的结果被丢掉 —— 判据会空转")
        XCTAssertEqual(titles(state.visibleNotes), ["山的那条"], "当前词的结果落地后内容不对")

        try writeEvidence("lateResultDropped", [
            "staleResultApplied": staleApplied,
            "staleFailureApplied": staleFailureApplied,
            "appliedForCurrentWord": true,
            "settledTitles": settled,
        ])
    }

    // MARK: - ③ 端到端那一次（真库 + 真 AppState + 落地出口）

    /// **端到端**：一次带着**旧词**的检索在途，词已经换成新的之后它的结果才回来。
    ///
    /// 两条独立判据：
    /// ① **落地不变量**（订阅每一次状态落地，连同落地那一刻搜索框里的词）：
    ///    没有任何一次落地是在「搜索框里的词 ≠ 它自己带来的词」时发生的 —— 这条不看时序，
    ///    只要迟到的那次真落了地就一定被记到（`boxWords` 里会出现与结果不符的组合）；
    /// ② 旧词的结果晚到 ⇒ 状态**一个字节不动**（拿 `runSearch(_:for:)` 走一遍完整路：
    ///    真库 → 真结果 → 真出口）。
    ///
    /// **窗口为什么不需要靠运气**：`Task { … }` 的函数体在**当前任务下一次挂起**时才开始跑，
    /// 而「把词换成新的」是同步的一句 —— 所以那一次带旧词的检索**必定**在新词已经上屏之后才落地。
    /// 另：切换之后「山」那一次还会落在它后面 ⇒ **只看最终状态是判不出来的**（终态一样），
    /// 这一条的量尺是 ① 那个不变量，不是终态。
    @MainActor
    func testAStaleResultNeverOverwritesTheNewerQueryEndToEnd() async throws {
        try requireIsolatedNotesDirectory()
        let state = try await makeState()
        defer { UISnapshot.clearLicense(from: state); removeLibrary() }
        let library = NoteLibrary.defaultLibrary()

        _ = try await seed("湖的那条", body: "洞庭湖骑行", into: library)
        _ = try await seed("山的那条", body: "南太行拉练", into: library)
        await state.reloadNotes()

        // 每一次**落地**都记下来（取闭包参数那个**新值** —— `@Published` 是 willSet 语义），
        // 连同落地那一刻搜索框里的词。
        var landings: [(box: String, titles: [String])] = []
        let watcher = state.$noteSearchState.dropFirst().sink { landed in
            MainActor.assumeIsolated {
                landings.append((box: state.notesQuery, titles: self.landedTitles(landed)))
            }
        }
        defer { watcher.cancel() }

        state.notesQuery = "湖"
        await state.searchNotes()
        XCTAssertEqual(titles(state.visibleNotes), ["湖的那条"], "前置：先按「湖」查一次")

        // 在途的一次「湖」检索：它带着自己的词（与界面那条路同一个函数）。
        let stale = Task { await state.runSearch("湖", for: "湖") }
        // 不等它 —— 词换成「山」（「打字比查库快」那一刻）。
        state.notesQuery = "山"
        // 先收在途那一次：它的落地只可能发生在这之后。
        await stale.value
        // 然后再正常查一次「山」（界面上的 `.task(id:)` 就是这个动作）。
        await state.searchNotes()

        XCTAssertEqual(
            titles(state.visibleNotes), ["山的那条"],
            "最终结果不是最后那个词的 —— 实测：\(titles(state.visibleNotes))"
        )
        let staleLandings = landings.filter { $0.box == "山" && $0.titles == ["湖的那条"] }
        XCTAssertTrue(
            staleLandings.isEmpty,
            "有 \(staleLandings.count) 次落地发生在搜索框已经是「山」的时候、结果却来自「湖」"
                + "（迟到的结果覆盖了新的）—— 全部落地：\(landings.map { "\($0.box):\($0.titles)" })"
        )

        // ② 旧词的结果晚到 ⇒ 状态一个字节不动（走完整条路：真库 → 真结果 → 真出口）。
        state.notesQuery = "山"
        await state.searchNotes()
        let before = titles(state.visibleNotes)
        await state.runSearch("湖", for: "湖")
        XCTAssertEqual(
            titles(state.visibleNotes), before,
            "旧词的结果晚到之后状态变了 —— 实测：\(titles(state.visibleNotes))"
        )

        try writeEvidence("quickTyping", [
            "landingCount": landings.count,
            "landingsAfterSwitch": landings.filter { $0.box == "山" }.count,
            "staleLandingsAfterSwitch": staleLandings.count,
            "finalTitles": titles(state.visibleNotes),
            "stateAfterLateArrival": before,
        ])
    }
}
