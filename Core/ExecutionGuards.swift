import Foundation

// MARK: - 行编辑（概设 §4.6 · 详设 §6 `DATA_NO_PK` / `DATA_WRITE_CONFLICT`）

/// 行写回的两条硬规则：**没有主键不给行编辑**、**影响 0 行报冲突**。
/// 现状是这两条都没有专门类型（详设 §10.1），用户看到的是「点了没反应」或「看起来成功了」。
public enum RowWriteDecision: Equatable, Sendable {
    /// 可以写：有主键 + 只影响一行
    case write
    /// 拒绝：表没有主键，行不可定位（`DATA_NO_PK`）
    case noPrimaryKey
    /// 失败：数据库说影响 0 行 ⇒ 行已被别人改/删（`DATA_WRITE_CONFLICT`）
    case writeConflict
    /// 失败：影响多行 ⇒ 条件不唯一，拒绝按行编辑语义提交
    case affectedMultipleRows(Int)
}

public enum RowWriteGuard {

    /// 提交前的判定（纯函数，界面与能力层共用一份）。
    /// - Parameters:
    ///   - hasPrimaryKey: 该表是否有主键（无主键 ⇒ 行不可定位）
    ///   - affectedRows: 服务端回报的影响行数（`nil` = 还没执行）
    public static func decide(hasPrimaryKey: Bool, affectedRows: Int?) -> RowWriteDecision {
        guard hasPrimaryKey else { return .noPrimaryKey }
        guard let affected = affectedRows else { return .write }
        if affected == 0 { return .writeConflict }
        if affected > 1 { return .affectedMultipleRows(affected) }
        return .write
    }

    /// 错误码（`nil` = 无需报错）。
    public static func errorCode(for decision: RowWriteDecision) -> String? {
        switch decision {
        case .write: return nil
        case .noPrimaryKey: return "DATA_NO_PK"
        case .writeConflict: return "DATA_WRITE_CONFLICT"
        case .affectedMultipleRows: return "DATA_WRITE_CONFLICT"
        }
    }
}

// MARK: - 结构脚本预览闸（概设 §4.7 · 详设 §6 `DDL_PREVIEW_REQUIRED`）

public enum DDLGateDecision: Equatable, Sendable {
    /// 允许执行：脚本已预览过，且预览内容与当前脚本一致
    case allowed
    /// 拒绝：未预览（`DDL_PREVIEW_REQUIRED`）
    case previewRequired
    /// 拒绝：预览后脚本又被改过（预览作废，需重新预览）
    case previewStale
}

public enum DDLPreviewGate {

    /// - Parameters:
    ///   - script: 待执行脚本
    ///   - previewedScript: 上次预览并被用户确认的脚本（`nil` = 从未预览）
    public static func decide(script: String, previewedScript: String?) -> DDLGateDecision {
        guard let previewed = previewedScript else { return .previewRequired }
        return previewed == script ? .allowed : .previewStale
    }

    public static func errorCode(for decision: DDLGateDecision) -> String? {
        switch decision {
        case .allowed: return nil
        case .previewRequired, .previewStale: return "DDL_PREVIEW_REQUIRED"
        }
    }
}

// MARK: - 导入导出（概设 §4.8 · 详设 §6 `IO_TARGET_EXISTS` / `IO_PARTIAL`）

public enum ImportExportDecision: Equatable, Sendable {
    /// 可以继续
    case proceed
    /// 目标文件已存在：必须询问（`IO_TARGET_EXISTS`）
    case targetExists
    /// 已结束但有失败项：必须逐项汇报（`IO_PARTIAL`）
    case partial(failed: Int, succeeded: Int)
}

public enum ImportExportGuard {

    /// 写之前：目标存在一律先问（不许静默覆盖）。
    public static func decideBeforeWrite(targetExists: Bool, overwriteApproved: Bool) -> ImportExportDecision {
        (targetExists && !overwriteApproved) ? .targetExists : .proceed
    }

    /// 写之后：有失败项就必须报「部分失败」，并分别列出成功/失败条数（不许整体判成功）。
    public static func decideAfterWrite(failed: Int, succeeded: Int) -> ImportExportDecision {
        failed > 0 ? .partial(failed: failed, succeeded: succeeded) : .proceed
    }

    public static func errorCode(for decision: ImportExportDecision) -> String? {
        switch decision {
        case .proceed: return nil
        case .targetExists: return "IO_TARGET_EXISTS"
        case .partial: return "IO_PARTIAL"
        }
    }
}

// MARK: - 会话终止（概设 §4.9 · 详设 §6 `SESS_KILL_DENIED`）

public enum SessionKillDecision: Equatable, Sendable {
    /// 允许终止（且必须已经过二次确认）
    case allowed
    /// 拒绝：权限不足（`SESS_KILL_DENIED`），要给出服务端原话
    case denied(reason: String)
    /// 拒绝：还没二次确认
    case confirmationRequired
    /// 拒绝：不许终止自己的会话（否则界面那条连接立刻自断）
    case selfSessionRefused
}

public enum SessionKillGuard {

    public static func decide(
        isOwnSession: Bool,
        confirmed: Bool,
        canTerminate: Bool,
        serverReason: String = ""
    ) -> SessionKillDecision {
        if isOwnSession { return .selfSessionRefused }
        if !confirmed { return .confirmationRequired }
        if !canTerminate { return .denied(reason: serverReason) }
        return .allowed
    }

    public static func errorCode(for decision: SessionKillDecision) -> String? {
        switch decision {
        case .allowed: return nil
        case .denied: return "SESS_KILL_DENIED"
        case .confirmationRequired, .selfSessionRefused: return "SESS_KILL_DENIED"
        }
    }
}

// MARK: - 授权能力位（概设 §3 授权判定 · 详设 §6 `LIC_NO_CAPABILITY`）

/// 能力位缺口的判定与呈现口径：**说明缺哪个位、怎么给**，禁「灰色诱导」（先展示再报错）。
public enum CapabilityGateDecision: Equatable, Sendable {
    case allowed
    /// 缺能力位（`LIC_NO_CAPABILITY`）
    case missing(capability: String)
}

public enum CapabilityGate {

    public static func decide(required: String, granted: Set<String>) -> CapabilityGateDecision {
        granted.contains(required) ? .allowed : .missing(capability: required)
    }

    /// 呈现出**唯一**口径：先说缺哪个位，再说去哪儿给（不写「升级以解锁」这类诱导话术）。
    public static func message(for decision: CapabilityGateDecision, language: AppLanguage) -> String? {
        switch decision {
        case .allowed:
            return nil
        case .missing(let capability):
            switch language {
            case .simplifiedChinese:
                return "当前许可证不含「\(capability)」能力位；请在许可证页添加该能力位后重试"
            case .english:
                return "This license lacks the \"\(capability)\" capability. Add it on the License page and retry."
            }
        }
    }

    public static func errorCode(for decision: CapabilityGateDecision) -> String? {
        switch decision {
        case .allowed: return nil
        case .missing: return "LIC_NO_CAPABILITY"
        }
    }
}
