import AppKit
import DoyahCore
import SwiftUI

/// 审批单底部那两枚动作（**真 `NSButton`**）：拒绝 / 批准并执行。
///
/// ## 为什么从 SwiftUI `Button`（`DialogActionButton`）换成 AppKit
///
/// 与 `PanelIconButton` / `SQLTaskAppKitMenu` / `ObjectTreeRetryButton` 同一条实测：
/// 离屏宿主里 SwiftUI `Button` **不落** `NSButton`、无障碍树也**不构建**
/// ⇒ 「点这一枚之后到底发生什么」在自动化里一次都量不到，只能靠人点。
/// 而 `FR-STD-DB-TASK-002` 的核心验收恰恰是**点一下**：点拒绝 ⇒ 一条语句都不发、历史读作「已拒绝」。
///
/// 换成真 `NSButton` 之后，探针 `performClick(nil)` 走的就是用户点它那条 action 路径
/// （不是另开一个入口，也不是拿实现里的闭包自己调一遍）。
///
/// ## 外观口径
///
/// 与原先 `DialogActionButton` 同形：图标 + 文字（对话框是竖向表单，图标省不出空间、只省掉了「这是什么」）、
/// 小尺寸、带边框；拒绝是破坏性角色（红字）、批准是默认动作（回车等价）。
/// 提示同时挂 `toolTip` 与无障碍标签 —— 那两件事原来由 `.help` / `.accessibilityLabel` 给。
///
/// ## 边界（如实登记）
///
/// `isWorking` 期间两枚都灰（`isEnabled = false`）：在途时再点一次就是**第二次决策**，
/// 而状态机那时已流转过 —— 用户看到的会是「点了没反应」。这条由本文件的 `updateNSView` 落实，
/// 由探针判（灰着的那一枚 `performClick` 不派发）。
struct AgentApprovalActionButton: NSViewRepresentable {

    /// 两枚动作各是什么（决定图标、键序与默认动作）。
    enum Kind: String {
        case reject
        case approve
    }

    let kind: Kind
    /// 按钮文字（已本地化的字符串，调用点写 `L(.key)`）。
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    private var systemName: String {
        switch kind {
        case .reject: return "xmark.circle"
        case .approve: return "checkmark.circle"
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        button.setAccessibilityRole(.button)
        // 批准是默认动作：回车等价（原先那枚 `.keyboardShortcut(.defaultAction)` 的可见后果）。
        // 拒绝**不**挂 Esc：审批单关窗是「不做决定」，与「拒绝」是两件事
        // （`dismissAgentApprovalSheet` 的注释：关窗不等于批准，也不等于拒绝）。
        if kind == .approve {
            button.keyEquivalent = "\r"
        }
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.contentTintColor = kind == .reject ? .systemRed : nil
        button.image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func fire() {
            action()
        }
    }
}

/// 审批单底部的动作行：右对齐的「拒绝」「批准并执行」两枚真按钮。
struct AgentApprovalDecisionRow: View {

    /// 在途（已提交决策、还没落地）：两枚都灰。
    let isWorking: Bool
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Spacer()

            AgentApprovalActionButton(
                kind: .reject,
                title: L(.agentApprovalReject),
                isEnabled: !isWorking,
                action: onReject
            )

            AgentApprovalActionButton(
                kind: .approve,
                title: L(.agentApprovalApprove),
                isEnabled: !isWorking,
                action: onApprove
            )
        }
    }
}

/// 「点了这两枚动作之后做什么」——**审批单与探针读同一处**。
///
/// 各写一份的后果正是本仓反复踩的那一类：按钮在、点了没反应（接线漏了），
/// 或者探针测的是自己拼的一条假路（绿了但用户点的那一枚还是死的）。
/// 所以这里既产出两个动作，也产出**那一行本身**（`row(isWorking:)`）：
/// 探针拿到的就是审批单里那一行，点的就是用户点的那一枚。
@MainActor
struct AgentApprovalDecisionWiring {

    let reject: () -> Void
    let approve: () -> Void

    /// 审批单上那一行（`isWorking` = 在途，两枚都灰）。
    func row(isWorking: Bool) -> AgentApprovalDecisionRow {
        AgentApprovalDecisionRow(isWorking: isWorking, onReject: reject, onApprove: approve)
    }

    /// 造两枚动作的闭包。
    ///
    /// 落地全在 `AppState`（状态机流转 / 执行 / 留痕一处收口），这里只做三件事：
    /// ① 置「在途」（两枚按钮据此变灰）；② 把备注与**允许方式**（`tier`）带上；
    /// ③ 收回结果（是否已离开待审批队列 ⇒ 该关窗）。
    ///
    /// - Parameters:
    ///   - note: 取当前的备注（用户可能刚打完字 —— 传值会把点击那一刻之前的文字丢掉）；
    ///   - tier: 取当前的允许方式（§3.36；缺省「仅这一次」= 不记任何东西）—— 同样是**取当前值**，
    ///     改了档位再点批准，落账的就是改后那一档；
    ///   - isWorking: 在途状态回写；
    ///   - onSettled: 决策落地后回调「是否已离开待审批队列」（`true` ⇒ 关窗）。
    static func make(
        appState: AppState,
        approvalID: UUID,
        note: @escaping () -> String,
        tier: @escaping () -> AgentApprovalTier = { .once },
        isWorking: @escaping (Bool) -> Void,
        onSettled: @escaping (Bool) -> Void = { _ in }
    ) -> AgentApprovalDecisionWiring {
        func submit(approve: Bool) {
            isWorking(true)
            let decisionNote = note()
            let chosenTier = approve ? tier() : AgentApprovalTier.once
            Task {
                if approve {
                    await appState.approveAgentAction(id: approvalID, note: decisionNote, tier: chosenTier)
                } else {
                    await appState.rejectAgentAction(id: approvalID, note: decisionNote)
                }
                isWorking(false)
                // 只有这条审批单真的离开待审批队列才关窗：流转失败时留在原处，
                // 让用户看到错误（而不是「点了没反应、窗口却关了」）。
                onSettled(!appState.pendingAgentApprovals.contains { $0.id == approvalID })
            }
        }
        return AgentApprovalDecisionWiring(
            reject: { submit(approve: false) },
            approve: { submit(approve: true) }
        )
    }
}
