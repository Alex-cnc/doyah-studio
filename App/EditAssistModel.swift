import Foundation
import SwiftUI
import DoyahCore

/// 编辑区 AI 辅助的**状态机**（`FR-STD-WS-AI-001` 的界面半）。
///
/// 规矩（与 Core `EditAssist` 的分工）：
/// - 判断「发不发得出去」只认 `EditAssist.gate`（Core），本类型**不自己拼这一套**；
/// - 真发请求的那一步由 `AppState` 注入（`runner`）—— 密钥、外发留痕、配额都在那一侧，
///   这里拿不到也不该拿到；
/// - 「应用」只把 `Proposal` 交给注入的 `apply`（让编辑面走一次可撤销编辑），
///   本类型**不碰文件、不碰页签内容**（契约 ①：不许静默改文件）。
@MainActor
final class EditAssistModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case sending
        case answer(String)
        case proposal(EditAssist.Proposal)
        case refused(EditAssist.Refusal)
    }

    @Published var isPresented = false
    @Published private(set) var action: EditAssist.Action = .explain
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var context: EditAssist.Context?
    /// 「模型：…」「端点：…」两行（契约 ②：界面上说得出用的是哪个模型与端点）。
    @Published private(set) var modelName = ""
    @Published private(set) var endpointName = ""
    /// 应用之后那一行回执。
    @Published private(set) var appliedNotice: String?

    /// 改写型动作的自然语言要求（用户在这一格里写）。
    @Published var instruction = ""

    /// 数据边界（契约 ③）。**默认保守**，且改一次就同步进 `context`（外发读数跟着变）。
    @Published var boundary: EditAssist.Boundary = .default {
        didSet { context?.boundary = boundary }
    }

    /// 发请求（由 `AppState` 注入：带密钥 / 外发留痕 / 配额）。
    var runner: ((EditAssist.Request) async throws -> LLMResponse)?
    /// 应用一条改动（由 `AppState` 注入：走编辑面的可撤销编辑）。
    var apply: ((EditAssist.Proposal) -> Void)?

    /// 打开面板（菜单 / 快捷键都走这一个入口）。
    ///
    /// 闸门**在这里先判一次**：端点 / 模型没配时就别让用户点「发送」才发现 ——
    /// 界面第一屏就该是「未配置」，而不是一个转圈的等待。
    func open(action: EditAssist.Action,
              context: EditAssist.Context,
              endpoint: String,
              model: String) {
        self.action = action
        self.context = context
        self.boundary = context.boundary
        self.instruction = context.instruction
        self.endpointName = endpoint
        self.modelName = model
        self.appliedNotice = nil
        phase = refusal(EditAssist.gate(action: action, context: context, endpoint: endpoint, model: model))
        isPresented = true
    }

    /// 闸门的判定结果（`nil` = 可以发）。
    private func refusal(_ refusal: EditAssist.Refusal?) -> Phase {
        if let refusal { return .refused(refusal) }
        return .idle
    }

    /// 当前上下文（把面板里改过的边界 / 要求写回去之后的版本）。
    var effectiveContext: EditAssist.Context? {
        guard var context else { return nil }
        context.boundary = boundary
        if action.needsInstruction { context.instruction = instruction }
        return context
    }

    /// 「将发送：选中片段 · 12 行 · 480 字」那一行（契约 ③：发出去什么先讲清）。
    var outboundSummary: EditAssist.OutboundSummary? { effectiveContext?.outboundSummary }

    var canSend: Bool {
        guard let context = effectiveContext else { return false }
        if case .sending = phase { return false }
        return EditAssist.gate(action: action, context: context,
                               endpoint: endpointName, model: modelName) == nil
    }

    var canApply: Bool {
        if case .proposal = phase { return true }
        return false
    }

    /// 发请求。所有「还没发就已经知道不行」的情形都在这里拦下，并落成人话。
    func send() {
        guard let context = effectiveContext else { return }
        if let refusal = EditAssist.gate(action: action, context: context,
                                         endpoint: endpointName, model: modelName) {
            phase = .refused(refusal)
            return
        }
        guard let request = EditAssist.request(action: action, context: context) else {
            phase = .refused(.nothingToSend)
            return
        }
        guard let runner else {
            phase = .refused(.endpointNotConfigured)
            return
        }
        phase = .sending
        Task { [weak self] in
            do {
                let response = try await runner(request)
                guard let self else { return }
                if let result = EditAssist.result(from: response.text, action: action, context: context) {
                    switch result {
                    case .proposal(let proposal): self.phase = .proposal(proposal)
                    case .answer(let text): self.phase = .answer(text)
                    }
                } else {
                    self.phase = .refused(.emptyResponse)
                }
            } catch {
                self?.phase = .refused(.unreachable(ErrorPresenter.message(for: error)))
            }
        }
    }

    /// 应用当前提案（只有提案态可点）。
    func applyProposal() {
        guard case .proposal(let proposal) = phase, let apply else { return }
        apply(proposal)
        appliedNotice = L(.editAssistApplied)
        isPresented = false
    }

    func dismiss() {
        isPresented = false
        phase = .idle
    }
}
