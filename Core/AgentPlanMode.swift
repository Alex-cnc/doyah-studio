import Foundation

/// **计划先获准**（`FR-AGT-PLAN-PLAN-007` / 概设 §18.4-8，参考 dsh `plan-mode`）。
///
/// 契约五条：
/// ① 未批准时写类 / 执行类工具被拒（只读照旧，那才是"探索与设计"）；
/// ② 批准后按原计划执行，**计划内容不许变**（变了即失效，要重新批准）；
/// ③ 退回后回到规划态，**原计划保留**（不许清空 —— 清空等于让人重写一遍）；
/// ④ 模式状态在会话恢复后保留；
/// ⑤ 负例：未批准就执行写操作、或退回后计划被清空 ⇒ 判红。
///
/// 落法：**状态不另存文件，落在会话的「计划跳」里**。会话恢复重放跳时 `replay()` 把三态与历史重建出来 ——
/// 这样 ④ 与 ③ 同时成立，且不需要改盘上会话头的存储契约（加字段 = 改契约，代价大得多）。
public struct AgentPlanEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case submitted
        case approved
        case rejected
        case revisionRequested
    }

    public var kind: Kind
    public var at: Date
    public var note: String

    public init(kind: Kind, at: Date = Date(), note: String = "") {
        self.kind = kind
        self.at = at
        self.note = note
    }
}

public struct AgentPlanState: Equatable, Sendable {
    public enum Phase: String, Codable, Equatable, Sendable {
        /// 没进计划模式。
        case inactive
        /// 计划已提交，等人批。
        case awaitingApproval
        /// 已批准：写类放行。
        case approved
        /// 被退回：回到规划态，计划正文保留。
        case rejected
    }

    public var phase: Phase
    /// 计划正文（给人看的那份，不压缩、不摘要）。
    public var body: String
    /// 批准时钉住的内容指纹：执行期正文一改就对不上（判据 ②）。
    public var approvedFingerprint: String
    /// 三态历史（提交 / 批准 / 退回 / 要求继续规划），按时间顺序（判据 ③「可回看」）。
    public var history: [AgentPlanEvent]

    public init(phase: Phase = .inactive, body: String = "", approvedFingerprint: String = "",
                history: [AgentPlanEvent] = []) {
        self.phase = phase
        self.body = body
        self.approvedFingerprint = approvedFingerprint
        self.history = history
    }

    // MARK: 指纹

    /// 内容指纹：FNV-1a 64 位（不引任何加密库 —— 这里要的是"变了就不一样"，不是抗碰撞安全性）。
    public static func fingerprint(of body: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in body.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    // MARK: 三态流转

    /// 提交（或重新提交）计划 ⇒ 回到等批准；**正文变了 ⇒ 旧的批准作废**。
    @discardableResult
    public mutating func submit(_ newBody: String, at: Date = Date(), note: String = "") -> Bool {
        let changed = AgentPlanState.fingerprint(of: newBody) != approvedFingerprint || phase != .approved
        body = newBody
        phase = .awaitingApproval
        approvedFingerprint = ""
        history.append(AgentPlanEvent(kind: .submitted, at: at, note: note))
        return changed
    }

    public mutating func approve(at: Date = Date(), note: String = "") {
        guard phase == .awaitingApproval else { return }
        phase = .approved
        approvedFingerprint = AgentPlanState.fingerprint(of: body)
        history.append(AgentPlanEvent(kind: .approved, at: at, note: note))
    }

    /// 退回：回到规划态，**正文保留**（判据 ③ 的负例就盯这一条）。
    public mutating func reject(at: Date = Date(), note: String = "") {
        phase = .rejected
        approvedFingerprint = ""
        history.append(AgentPlanEvent(kind: .rejected, at: at, note: note))
    }

    public mutating func requestRevision(at: Date = Date(), note: String = "") {
        phase = .rejected
        approvedFingerprint = ""
        history.append(AgentPlanEvent(kind: .revisionRequested, at: at, note: note))
    }

    // MARK: 闸门

    public enum Verdict: Equatable, Sendable {
        case allow
        /// 计划还没批（`fingerprint` = 当前计划的内容指纹）。
        case awaitingApproval(fingerprint: String)
        /// 已批准，但正文被改过 ⇒ 旧批准失效。
        case planChanged(approved: String, current: String)
    }

    /// 这条工具调用放不放行。**只读一律放行**（探索与设计本来就要读）。
    public func verdict(for definition: AgentToolDefinition) -> Verdict {
        guard definition.level != .readOnly else { return .allow }
        switch phase {
        case .inactive:
            return .allow
        case .awaitingApproval:
            return .awaitingApproval(fingerprint: AgentPlanState.fingerprint(of: body))
        case .rejected:
            return .awaitingApproval(fingerprint: AgentPlanState.fingerprint(of: body))
        case .approved:
            let current = AgentPlanState.fingerprint(of: body)
            return current == approvedFingerprint ? .allow : .planChanged(approved: approvedFingerprint, current: current)
        }
    }

    // MARK: 会话恢复

    /// 计划事件在会话里存成一条跳：`kind == "plan"`，正文是 JSON（事件 + 当时的计划正文）。
    public static let turnKind = AgentSessionTurn.Kind.plan.rawValue

    public static func turnText(for event: AgentPlanEvent, body: String) -> String {
        let payload: [String: String] = [
            "event": event.kind.rawValue,
            "note": event.note,
            "body": body,
            "at": ISO8601DateFormatter().string(from: event.at),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// 从会话跳里重建状态：**同一会话开着的计划模式，恢复后状态不丢**（判据 ④）。
    public static func replay(_ turns: [AgentSessionTurn]) -> AgentPlanState {
        var state = AgentPlanState()
        let decoder = JSONDecoder()
        for turn in turns where turn.kind == .plan {
            guard let data = turn.text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let raw = obj["event"], let kind = AgentPlanEvent.Kind(rawValue: raw) else { continue }
            let body = obj["body"] ?? ""
            switch kind {
            case .submitted:
                state.body = body
                state.phase = .awaitingApproval
                state.approvedFingerprint = ""
            case .approved:
                state.body = body.isEmpty ? state.body : body
                state.phase = .approved
                state.approvedFingerprint = fingerprint(of: state.body)
            case .rejected, .revisionRequested:
                state.body = body.isEmpty ? state.body : body
                state.phase = .rejected
                state.approvedFingerprint = ""
            }
            _ = decoder
            state.history.append(AgentPlanEvent(kind: kind, at: Date(), note: obj["note"] ?? ""))
        }
        return state
    }
}
