import Foundation

public enum AppError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case notConnected
    case notImplemented(String)
    case credentialStore(code: Int32)
    case persistence(String)
    case queryFailed(String)
    /// 概设 §9 `EXEC_EMPTY_SQL`：装配层判定「没有可执行内容」——空串或纯空白。
    /// 与 `ExecutionScope.Issue.emptyText` 同源，但它是**错误码落点**（可被装配层统一呈现与留痕）。
    case emptySQL

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "连接配置无效：\(reason)"
        case .notConnected:
            return "当前没有已建立的数据库连接"
        case .notImplemented(let feature):
            return "功能尚未实现：\(feature)"
        case .credentialStore(let code):
            return "凭据存储操作失败（错误码 \(code)）"
        case .persistence(let reason):
            return "本地配置读写失败：\(reason)"
        case .queryFailed(let message):
            return "SQL 执行失败：\(message)"
        case .emptySQL:
            return "没有可执行的 SQL：编辑器内容为空或只有空白"
        }
    }
}
