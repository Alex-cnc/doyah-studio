import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 高危任务审批单上那两枚动作（`FR-STD-DB-TASK-002`）—— B1 批次第四片。
///
/// ## 这一格为什么停在「差人工在审批单上点一次」
///
/// 语义那一面早就在：`Core/HighRiskTaskApproval.swift` 拆句 / 逐条目标库 / 影响面三档 / 决策一处
/// （`Tests/HighRiskTaskApprovalTests` 18 例）。缺的是**点一下**：审批单底部两枚动作是
/// SwiftUI `DialogActionButton`，离屏宿主里不落 `NSButton`（同 `PanelIconButton` 文件头的实测）
/// ⇒「点拒绝之后是不是真的一条语句都没发、历史里读作什么」只能靠人点。
///
/// ## 这一片怎么量
///
/// ① 两枚动作换成**真 `NSButton`**（`App/Views/AgentApprovalDecisionRow.swift`），
///    接线收进 `AgentApprovalDecisionWiring.make` —— 审批单与探针读同一处；
/// ② 探针 `performClick(nil)` 走的就是用户点它那条 action 路径，判据读 `AppState` 的**状态**：
///    待审批队列、审计记录（`outcome` / 备注 / 有没有 `executed`）、盘上那份 `agent-audit.jsonl`；
/// ③ 审计落点指到**临时目录**（`agentAuditLogOverride`）：验一次「点拒绝」不该往用户的真账里写一行。
///
/// ## 边界（如实登记，别把这条读成「真库上点过了」）
///
/// · **不是真数据库**：拒绝这一档本来就不发语句（这正是要判的），但「批准之后真的把两条语句
///   按原序打上库」要真集群 —— 那一面归 `Scripts/run-manual-verification-probes.sh` 那条路。
/// · **审批单本体不整张装宿主**：它的 `.task` 要去问优化器估影响面（要有连接）。
///   本片量的是动作行 —— 也就是用户在那一张单上唯一点得到的两枚东西。
/// · **行内逐条文字读不出来**（SwiftUI `Text` 不落 `NSTextField`）⇒「每条语句一行」这件事判在
///   `Tests/HighRiskTaskApprovalTests` 与 `AppState.highRiskPlan` 那一层（本文件第 ③ 条）。
final class AgentApprovalDecisionProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主：DOYAH_UI_SNAPSHOT=1 才跑（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 夹具

    /// 记账盒（闭包捕获用 —— 直接捕获 `var` 会被「逃逸闭包」挡下）。
    private final class Box {
        var rejectClicks = 0
        var approveClicks = 0
        var working: Bool?
        var settled: Bool?
    }

    /// 一条待审的**覆盖写入**：`TRUNCATE` + `INSERT` 两条（数据任务编译出来就是这两条）。
    private func overwriteRecord(database: String = "shop") -> AgentActionRecord {
        AgentActionRecord(
            connectionName: "本机测试库",
            database: database,
            model: "probe",
            sql: "TRUNCATE TABLE orders;\nINSERT INTO orders (id, note) VALUES (1, 'x');",
            statementKind: .schemaChange,
            risk: .destructive,
            outcome: .pendingApproval
        )
    }

    private func pendingApproval(database: String = "shop") -> AgentApproval {
        let record = overwriteRecord(database: database)
        return AgentApproval(id: record.id, record: record, state: .pending)
    }

    /// 临时审计目录：探针不往用户的 `agent-audit.jsonl` 里写一行。
    private func temporaryAuditLog() throws -> (AgentAuditLog, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-approval-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (AgentAuditLog(directoryURL: directory), directory)
    }

    @MainActor
    private func buttons(in view: some View, size: CGSize = CGSize(width: 620, height: 80)) -> [NSButton] {
        let live = UISnapshot.LiveHost(AnyView(view), size: size)
        live.pump(0.4)
        return UISnapshot.LiveHost<AnyView>.findViews(ofType: NSButton.self, in: live.hosting)
    }

    // MARK: - ① 两枚动作都在、各带各的提示、在途时两枚都灰

    @MainActor
    func testTheDecisionRowIsTwoRealButtonsAndGoesGreyWhileWorking() throws {
        let box = Box()
        let idle = buttons(in: AgentApprovalDecisionRow(
            isWorking: false,
            onReject: { box.rejectClicks += 1 },
            onApprove: { box.approveClicks += 1 }
        ))

        XCTAssertEqual(idle.count, 2, "审批单底部落出 \(idle.count) 枚真按钮 —— 两枚动作不是 AppKit 控件（离屏点不到）")
        let rejectButton = try XCTUnwrap(idle.first { $0.title == L(.agentApprovalReject) },
                                         "没有「\(L(.agentApprovalReject))」那一枚，实际：\(idle.map(\.title))")
        let approveButton = try XCTUnwrap(idle.first { $0.title == L(.agentApprovalApprove) },
                                          "没有「\(L(.agentApprovalApprove))」那一枚，实际：\(idle.map(\.title))")
        XCTAssertEqual(rejectButton.toolTip, L(.agentApprovalReject), "拒绝那枚没有悬停提示")
        XCTAssertEqual(approveButton.toolTip, L(.agentApprovalApprove), "批准那枚没有悬停提示")
        XCTAssertEqual(approveButton.keyEquivalent, "\r", "批准不是默认动作（回车落不到它）")

        rejectButton.performClick(nil)
        approveButton.performClick(nil)
        XCTAssertEqual(box.rejectClicks, 1, "点「拒绝」没有派发（实测 \(box.rejectClicks) 次）")
        XCTAssertEqual(box.approveClicks, 1, "点「批准并执行」没有派发（实测 \(box.approveClicks) 次）")

        // 在途：两枚都必须灰（那时状态机已经流转过，再点一次是第二次决策）。
        let working = buttons(in: AgentApprovalDecisionRow(
            isWorking: true,
            onReject: { box.rejectClicks += 1 },
            onApprove: { box.approveClicks += 1 }
        ))
        XCTAssertEqual(working.count, 2, "在途那一档按钮数变了：\(working.count)")
        XCTAssertTrue(working.allSatisfy { !$0.isEnabled },
                      "在途时还有一枚能点：\(working.filter(\.isEnabled).map(\.title))")
        print("🧪 动作行读数：按钮 \(idle.map(\.title)) / 在途时全部变灰 / 回车键等价「\(approveButton.keyEquivalent)」")
    }

    // MARK: - ② 点「拒绝」：一条都没发，历史读作「已拒绝」

    @MainActor
    func testClickingRejectSendsNothingAndLeavesRejectedInHistory() async throws {
        let (log, directory) = try temporaryAuditLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState()
        await state.startupChain?.value
        state.connections = []
        state.selectedConnectionID = nil
        state.agentAuditLogOverride = log

        let approval = pendingApproval()
        state.pendingAgentApprovals = [approval]
        state.agentApprovalRequest = approval

        let box = Box()
        // **生产那一份接线**（审批单的 `decisionRow` 调的就是它）。
        let actions = AgentApprovalDecisionWiring.make(
            appState: state,
            approvalID: approval.id,
            note: { "不接受这条" },
            isWorking: { box.working = $0 },
            onSettled: { box.settled = $0 }
        )

        // **审批单里那一行**（`wiring.row(isWorking:)`）—— 点的就是用户点的那一枚。
        let row = buttons(in: actions.row(isWorking: false))
        let rejectButton = try XCTUnwrap(row.first { $0.title == L(.agentApprovalReject) },
                                         "找不到「\(L(.agentApprovalReject))」那一枚")
        rejectButton.performClick(nil)

        XCTAssertEqual(box.working, true, "点了之后没有进「在途」（按钮不会变灰，用户能连点）")

        // 决策是异步落地的（`Task { await … }`）：等它写完盘再判，不靠一次 sleep 猜。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !state.pendingAgentApprovals.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(state.pendingAgentApprovals.isEmpty, "点了拒绝，这条还挂在待审批队列里")
        XCTAssertEqual(box.settled, true, "落地之后没有回报「已离开队列」—— 窗口不会关，用户以为没生效")
        XCTAssertNil(state.agentApprovalRequest, "审批单还开着（决策落地了却没清掉呈现状态）")
        XCTAssertNil(state.agentAuditError, "拒绝这条路上冒了错：\(state.agentAuditError ?? "")")
        XCTAssertEqual(state.agentAuditMessage, L(.agentApprovalRejected), "没有给「已拒绝」那句话")

        let history = state.agentAuditRecords
        XCTAssertEqual(history.last?.outcome, .rejected, "历史里最后一条不是「已拒绝」：\(history.map(\.outcome))")
        XCTAssertEqual(history.last?.detail, "不接受这条", "备注没进审计（拒绝理由丢了）")
        XCTAssertFalse(history.contains { $0.outcome == .executed },
                       "拒绝之后历史里出现了「已执行」：\(history.map(\.outcome))")

        let onDisk = try await log.entries()
        XCTAssertEqual(onDisk.compactMap { $0.outcome == .rejected ? true : nil }.count, 1,
                       "盘上那本审计不是恰好一条「已拒绝」：\(onDisk.map(\.outcome))")
        XCTAssertFalse(onDisk.contains { $0.outcome == .executed || $0.outcome == .failed },
                       "盘上出现了执行痕迹：\(onDisk.map(\.outcome))")
        print("🧪 拒绝读数：队列 \(state.pendingAgentApprovals.count) 条 / 历史 \(history.map(\.outcome.rawValue)) / 盘上 \(onDisk.map(\.outcome.rawValue))")
    }

    // MARK: - ③ 覆盖写入：两条语句各带自己的目标库，拒绝交出一张空表

    @MainActor
    func testOverwritePlanListsTwoStatementsWithTheirOwnTargetAndRejectionSendsNone() throws {
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil

        let approval = pendingApproval(database: "shop")
        let plan = try XCTUnwrap(state.highRiskPlan(for: approval.record),
                                 "覆盖写入那条脚本拆不出计划 —— 审批单上会退回「整段原文」")
        XCTAssertEqual(plan.statements.count, 2, "覆盖写入应拆成两条，实际：\(plan.statements.map(\.sql))")
        XCTAssertEqual(plan.statements.map(\.kind), ["TRUNCATE", "INSERT"], "逐条类别不对：\(plan.statements.map(\.kind))")
        XCTAssertEqual(plan.statements.map(\.index), [1, 2], "序号不是 1 起连续")
        XCTAssertEqual(plan.statements.map(\.targetDatabase), ["shop", "shop"],
                       "每条语句的目标库没各自带上（审批单上会看不出哪条打哪个库）")
        XCTAssertTrue(plan.statements.allSatisfy { !$0.impactIsSettled },
                      "影响面在问之前就已经「有数」了 —— 估不出来不许冒充 0 行")

        let rejected = HighRiskTaskApproval.outcome(for: plan, decision: .reject)
        XCTAssertFalse(rejected.sendsAnything, "拒绝之后还说「要发东西」")
        XCTAssertTrue(rejected.statements.isEmpty, "拒绝之后交出了 \(rejected.statements.count) 条语句")
        print("🧪 覆盖写入读数：\(plan.statements.map { "#\($0.index) \($0.kind) @ \($0.targetDatabase ?? "nil")" }) / 拒绝交出 \(rejected.statements.count) 条")
    }

    // MARK: - ④ 源锚点：审批单用的就是这一份，且不再自己拼 SwiftUI 按钮

    func testTheSheetUsesThatRowAndWiring() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let sheet = try String(
            contentsOf: root.appendingPathComponent("App/Views/AgentApprovalSheet.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(sheet.contains("AgentApprovalDecisionRow("),
                      "审批单不再走那枚真按钮的动作行 ⇒ 离屏又点不到了")
        XCTAssertTrue(sheet.contains("AgentApprovalDecisionWiring.make("),
                      "审批单自己拼了一份「点了之后做什么」⇒ 探针量到的就不是用户点的那条路")
        XCTAssertTrue(sheet.contains("actions.row(isWorking: isWorking)"),
                      "审批单没用接线给的那一行 ⇒ 探针点的是它自己拼的一行，不是用户点的那一枚")
        XCTAssertFalse(sheet.contains("rejectAgentAction"),
                       "审批单里还直接调着 `rejectAgentAction` —— 接线分了两处")
        XCTAssertFalse(sheet.contains("DialogActionButton(systemName: \"xmark.circle\""),
                       "旧的两枚 SwiftUI 动作按钮还在（一份控件两条实现）")
        XCTAssertFalse(sheet.contains("func decide(approve: Bool)"),
                       "旧的 `decide(approve:)` 还在 —— 两套接线，探针测的那一套未必是用户点的那一套")

        let row = try String(
            contentsOf: root.appendingPathComponent("App/Views/AgentApprovalDecisionRow.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(row.contains("button.target = context.coordinator"),
                      "按钮没有 target/action ⇒ 点了什么都不发生")
        XCTAssertTrue(row.contains("button.isEnabled = isEnabled"),
                      "在途时按钮不变灰（用户能连点两次决策）")
    }
}
