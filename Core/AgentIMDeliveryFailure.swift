import Foundation

/// **主动消息失败的三档归因**（`T-3.25-14`，需求 ⑭：配额 / 瞬时 / 网络分开说，不许只说「失败」）。
///
/// 为什么非分不可：这三档对用户意味着三件完全不同的事 ——
/// · **配额**：今天一条都发不出去了，重试一百次也没用，得告诉他明天再来或换通道；
/// · **瞬时**：服务端自己抖了一下，等一下重试就好；
/// · **网络**：本机连不上（代理 / DNS / 掉线），要重连而不是重发。
///
/// 口径来自官方机器人开放平台的文件/消息错误码（Hermes 适配器 `chunked_upload.py` 同口径）：
/// `40093001` = 分片/上传瞬时失败（可重试）；`40093002` = 当日配额用尽（**不可重试**）。
public enum AgentIMDeliveryFailure: Equatable, Sendable {

    /// 当日配额用尽（不可重试）。
    case quota(code: String)
    /// 瞬时失败（可重试一次）。
    case transient(code: String)
    /// 本机到平台的网络问题（重连后再试）。
    case network
    /// 其余（带原状态的机器码，不替平台编原因）。
    case other(code: String)

    public static let quotaCode = "40093002"
    public static let transientCode = "40093001"

    /// 是不是「再试也没用」的那一档（界面要说清「今天发不出去了」，别混成网络错误）。
    public var isPermanent: Bool {
        if case .quota = self { return true }
        return false
    }

    /// 该不该自动重试（配额不重试；其余一次为限由调用方控制）。
    public var shouldRetry: Bool {
        switch self {
        case .quota: return false
        case .transient, .network: return true
        case .other: return false
        }
    }

    /// 从「状态 + 平台码」判档。平台码可能是数字也可能是字符串（两处都收）。
    public static func classify(status: Int?, code: String?) -> AgentIMDeliveryFailure {
        let normalized = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case quotaCode: return .quota(code: normalized)
        case transientCode: return .transient(code: normalized)
        default: break
        }
        if status == nil { return .network }
        if status == 429 { return .quota(code: normalized.isEmpty ? "rateLimited" : normalized) }
        if let status, (500..<600).contains(status) {
            return .transient(code: normalized.isEmpty ? "serverFailed" : normalized)
        }
        return .other(code: normalized.isEmpty ? "rejected" : normalized)
    }

    /// 从一次外发的结局判档（`nil` = 这一条已发出去，没有失败可归因）。
    public static func classify(_ outcome: AgentIMSendOutcome) -> AgentIMDeliveryFailure? {
        switch outcome {
        case .delivered, .responseNotJSON: return nil
        case .networkFailed: return .network
        case .rateLimited: return .quota(code: "rateLimited")
        case .serverFailed: return .transient(code: "serverFailed")
        case .rejected(let status, let code): return classify(status: status, code: code)
        case .unauthorized: return .other(code: "unauthorized")
        case .forbidden: return .other(code: "forbidden")
        case .notReady(let code): return .other(code: "notReady:\(code)")
        }
    }

    /// 机器码（观测面板与日志的稳定标识）。
    public var machineCode: String {
        switch self {
        case .quota(let code): return "quota:\(code)"
        case .transient(let code): return "transient:\(code)"
        case .network: return "network"
        case .other(let code): return "other:\(code)"
        }
    }
}
