import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **整批撤回（`FR-STD-WS-EDIT-015`）的 App 内行为探针**。
///
/// ## 判什么
///
///   ① 一次任务里的多处文件改动**按批次一次撤回**（不是一条一条点）；
///   ② **只撤 Agent 改的**：这一批没写过的文件（人手改的）一个字节都不动；
///   ③ **人不背锅**：Agent 写完**又被人改过**的那一份读「没动」、内容一字不改，
///      回执里点名它（`changedSinceWrite`）；
///   ④ 撤回之后还能**「撤销这次撤回」**，回到 Agent 写完那一版。
///
/// ## 怎么判
///
/// 走的是产品里那条路（`AppState.runAgentBatch` 的三步，逐行同形）：
/// `AgentWriteBatchStore`（采集端，真写盘之后再记）→ `AgentWriteBatchRevert.plan`（纯函数出计划）
/// → `apply`（真落盘）→ `inverse`（反向批次，**落盘之前**算）。
/// `reader` / `writer` 与 `AppState` 里那两段同形：越界一律不读写，写就真写进临时工作区。
///
/// 断言全是 `FileManager` 读回来的**真实正文**（这一条需求怕的正是"界面上说撤了、盘上没动"），
/// 再对计划 / 回执读数做结构性核对。**不 mock 文件系统**。
///
/// ## 反证记录（2026-11-01：改坏一处产品代码 → 红 → 逐字节还原 → 绿）
///
/// 把 `AgentWriteBatchRevert.plan` 里两处 `writtenDigest` 摘要检查删掉（"不看之后有没有人改过"）⇒
/// 本文件 11 处红：「撤回计划不对…」「人手改的那一份被这一批撤回了」「冲突那一条也动了盘」
/// 「人改的内容被覆盖了」「回执里没点名那一处」「回执没写清为什么没动」都出现了；逐字节还原后 3/3 绿。
///
/// ## 边界（如实登记）
///
/// · 不判界面那一层（「整批撤回」那枚按钮的悬停 / 文案）：归人工点验清单；
/// · `AppState.revertAgentBatch` 本身没有在这里调 —— 它要 `AppState` 的连接 / 任务上下文齐全
///   （`agentEditJournal` 那一册由真实 Agent 会话填），在探针里造一个假的等于把被测的那件事换成
///   mock；这里判的是它**唯一**的落盘实现（`plan` / `apply` / `inverse`）在真磁盘上的行为；
/// · 不碰用户数据：夹具是临时目录。
final class AgentBatchRevertProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 与 `AppState.runAgentBatch` / `agentBatchReader` 同形的读写

    private func reader(root: URL) -> (String) -> String? {
        { path in
            guard case let .inside(url) = AgentWorkspaceSandbox.resolve(path, in: root) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private func writer(root: URL) -> (String, String?) throws -> Void {
        { path, text in
            guard case let .inside(url) = AgentWorkspaceSandbox.resolve(path, in: root) else {
                throw NSError(domain: "probe", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "越界：\(path)"])
            }
            if let text {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// 一次「Agent 写文件」：真写盘，再按 `AppState` 那条路记进批次（前像 + 写完之后）。
    private func agentWrite(
        _ text: String,
        to path: String,
        scratch: WorkspaceFileProbeKit.Scratch,
        batch: AgentWriteBatchStore
    ) throws {
        let previous = try? String(contentsOf: scratch.url(path), encoding: .utf8)
        try scratch.write(text, at: path)
        batch.record(path: path, previousText: previous, writtenText: text)
    }

    // MARK: - ① ② 一次撤回整批；人手改的文件不动

    func testBatchRevertRestoresAgentEditsAndLeavesHumanFilesAlone() throws {
        let scratch = try WorkspaceFileProbeKit.Scratch("edit-015a")
        defer { scratch.remove() }

        try scratch.write("人手写的\n", at: "human.txt")
        try scratch.write("v0\n", at: "a.txt")

        let batch = AgentWriteBatchStore(runID: "run-a")
        try agentWrite("v1\n", to: "a.txt", scratch: scratch, batch: batch)     // 改既有文件
        try agentWrite("b1\n", to: "b.txt", scratch: scratch, batch: batch)     // 新建文件
        try agentWrite("v0 补一句\n", to: "human.txt", scratch: scratch, batch: batch)
        try scratch.write("人手写的（Agent 之后又改过）\n", at: "human.txt")     // 人又改回来

        let steps = batch.plan(reader: reader(root: scratch.root))
        XCTAssertEqual(
            steps,
            [
                .restore(path: "a.txt", text: "v0\n"),
                .delete(path: "b.txt"),
                .conflict(path: "human.txt", reason: .changedSinceWrite)
            ],
            "撤回计划不对（应当是「改回前像 / 删掉新建 / 人改过的那条只报冲突」）：\(steps)"
        )

        let result = try AgentWriteBatchRevert.apply(steps, writer: writer(root: scratch.root))

        XCTAssertEqual(result.applied, 2, "真撤了几条：\(result.applied)（应当是 a.txt 与 b.txt 两条）")
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(try scratch.text(at: "a.txt"), "v0\n", "Agent 改过的文件没有回到那一批开始之前")
        XCTAssertFalse(scratch.exists("b.txt"), "Agent 新建的文件没有被撤掉——盘上留着一个凭空出现的文件")
        XCTAssertEqual(
            try scratch.text(at: "human.txt"), "人手写的（Agent 之后又改过）\n",
            "人手改的那一份被这一批撤回了 —— 需求要求「只撤 Agent 改的、不动人手」"
        )
    }

    // MARK: - ③ 人改过的那一处：读「没动」+ 回执点名 + 内容一字不改

    func testHumanEditsAreReportedAsUnmovedAndNeverOverwritten() throws {
        let scratch = try WorkspaceFileProbeKit.Scratch("edit-015b")
        defer { scratch.remove() }

        try scratch.write("v0\n", at: "a.txt")
        let batch = AgentWriteBatchStore(runID: "run-b")
        try agentWrite("v1\n", to: "a.txt", scratch: scratch, batch: batch)
        // Agent 写完，人又在这份上改了（编辑器里敲的字）。
        try scratch.write("v2 人的改动\n", at: "a.txt")

        let steps = batch.plan(reader: reader(root: scratch.root))
        XCTAssertEqual(
            steps, [.conflict(path: "a.txt", reason: .changedSinceWrite)],
            "人改过的文件没有被识别成冲突：\(steps)"
        )

        let result = try AgentWriteBatchRevert.apply(steps, writer: writer(root: scratch.root))
        XCTAssertEqual(result.applied, 0, "冲突那一条也动了盘：\(result.applied) 条")
        XCTAssertEqual(
            try scratch.text(at: "a.txt"), "v2 人的改动\n",
            "人改的内容被覆盖了 —— 这是整批撤回最怕的一种丢数据"
        )

        let receipt = AgentBatchRevertReceipt.make(
            batchID: UUID(), at: Date(), result: result, cardIDs: [UUID()])
        XCTAssertEqual(receipt.reverted, 0)
        XCTAssertEqual(receipt.unmoved.map(\.path), ["a.txt"], "回执里没点名那一处")
        XCTAssertEqual(receipt.unmoved.map(\.reason), [.changedSinceWrite], "回执没写清为什么没动")
        XCTAssertFalse(receipt.isClean, "有一处没撤，回执不该说自己干净")
        XCTAssertEqual(receipt.total, 1)
    }

    // MARK: - ④ 撤销这次撤回 ⇒ 回到 Agent 写完那一版

    func testUndoingTheRevertBringsBackTheAgentVersion() throws {
        let scratch = try WorkspaceFileProbeKit.Scratch("edit-015c")
        defer { scratch.remove() }

        try scratch.write("v0\n", at: "a.txt")
        let batch = AgentWriteBatchStore(runID: "run-c")
        try agentWrite("v1\n", to: "a.txt", scratch: scratch, batch: batch)
        try agentWrite("b1\n", to: "b.txt", scratch: scratch, batch: batch)

        // 第一步：整批撤回（反向批次必须在落盘**之前**算 —— 落盘后盘上已经是撤后的样子）。
        let steps = batch.plan(reader: reader(root: scratch.root))
        let inverse = AgentWriteBatchRevert.inverse(of: steps, reader: reader(root: scratch.root))
        let discarded = try AgentWriteBatchRevert.apply(steps, writer: writer(root: scratch.root))
        XCTAssertEqual(discarded.applied, 2)
        XCTAssertEqual(try scratch.text(at: "a.txt"), "v0\n")
        XCTAssertFalse(scratch.exists("b.txt"))

        // 第二步：「撤销这次撤回」—— 反向批次再走一遍同一条 plan/apply。
        let redo = AgentWriteBatchStore(runID: "redo")
        for snapshot in inverse { redo.record(snapshot) }
        XCTAssertFalse(redo.isEmpty, "撤完一条都没留反向批次 —— 「撤销这次撤回」无从谈起")

        let redoSteps = redo.plan(reader: reader(root: scratch.root))
        let reverted = try AgentWriteBatchRevert.apply(redoSteps, writer: writer(root: scratch.root))

        print("BATCH[撤销撤回] 计划 \(redoSteps) · 落盘 \(reverted.applied) 条")
        XCTAssertEqual(reverted.applied, 2, "「撤销这次撤回」只动了 \(reverted.applied) 条")
        XCTAssertTrue(reverted.conflicts.isEmpty, "「撤销这次撤回」遇到冲突：\(reverted.conflicts)")
        XCTAssertEqual(
            try scratch.text(at: "a.txt"), "v1\n",
            "撤销这次撤回之后不是 Agent 写完的那一版"
        )
        XCTAssertTrue(scratch.exists("b.txt"), "Agent 新建的那个文件没有被送回来")
        XCTAssertEqual(try scratch.text(at: "b.txt"), "b1\n")
    }
}
