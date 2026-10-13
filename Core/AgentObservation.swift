import Foundation

/// `FR-AI-30` ②（观察结果回灌）—— 提案 `0009` A 片：把「上一次执行发生了什么」变成模型的下一跳输入。
///
/// **结构上不含结果集行数据**（照 `NFR-AI-01` / `LLMRequest` 的做法）：只有语句类型、成败、
/// `SQLSTATE`、脱敏后的错误文本、影响行数与截断标记 —— **行数据没有可以落进去的字段**。
/// 脱敏（`AgentAudit.redacted`）与长度上限收在构造器**一处**，调用方不需要记得。
public struct AgentObservation: Equatable, Sendable {

    /// 语句类型（回灌时给模型一个粗分类，不承载语句原文之外的任何东西）。
    public enum StatementKind: String, Equatable, Sendable, CaseIterable {
        case query
        case write
        case ddl
    }

    /// 执行结局。
    public enum Outcome: String, Equatable, Sendable, CaseIterable {
        case succeeded
        case failed
    }

    /// 错误文本外发前的长度上限：超出即截断，并**如实标注**截了多少（不静默截）。
    public static let maxErrorMessageLength = 500

    public var statementKind: StatementKind
    public var outcome: Outcome
    /// `SQLSTATE`（可空）。
    public var errorCode: String?
    /// 失败的可读文本 —— 构造时已过脱敏与截断。
    public var errorMessage: String?
    /// 影响行数（可空；**是数字，不是行数据**）。
    public var affectedRows: Int?
    /// 被截掉的字符数（`nil` = 没截过）。
    public var truncatedCharacters: Int?
    /// 时刻（**注入**，实现不读钟 —— 与 `LLMRequest` 同一条纪律）。
    public var at: Date?

    public init(
        statementKind: StatementKind,
        outcome: Outcome,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        affectedRows: Int? = nil,
        at: Date? = nil
    ) {
        self.statementKind = statementKind
        self.outcome = outcome
        self.errorCode = errorCode
        self.affectedRows = affectedRows
        self.at = at

        let sanitized = errorMessage.map { AgentAudit.redacted($0) }
        if let sanitized, sanitized.count > Self.maxErrorMessageLength {
            self.errorMessage = String(sanitized.prefix(Self.maxErrorMessageLength))
            self.truncatedCharacters = sanitized.count - Self.maxErrorMessageLength
        } else {
            self.errorMessage = sanitized
            self.truncatedCharacters = nil
        }
    }

    /// 回灌给模型的那一段（**已包进不可信边界** —— 执行结果与错误文本都是外部数据）。
    public func promptSection() -> String {
        var body: [String] = []
        body.append("语句类型：\(statementKind.promptName)")
        body.append("执行结果：\(outcome.promptName)")
        if let code = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            body.append("错误码：\(code)")
        }
        if let message = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            body.append("错误信息：\(message)")
        }
        if let rows = affectedRows {
            body.append("影响行数：\(rows)")
        }
        if let truncated = truncatedCharacters {
            body.append("错误信息已截断：省略 \(truncated) 个字符")
        }
        return AgentGuardrail.wrapUntrusted(body.joined(separator: "\n"), source: .tableData).text
    }

    /// 外发正文的取证面：组装进请求体的那一段就是它（判据「查不到行数据」在这里取读）。
    public var outgoingText: String { promptSection() }
}

extension AgentObservation.StatementKind {
    var promptName: String {
        switch self {
        case .query: return "查询"
        case .write: return "写入"
        case .ddl: return "结构变更"
        }
    }
}

extension AgentObservation.Outcome {
    var promptName: String {
        switch self {
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }
}
