import Foundation

/// **权限配置面**（`FR-AGT-GUARD-PERM-002` / 本端计划 P2-1）：等级 / 沙箱根 / 白名单如何声明。
///
/// 两条判据：
/// ① **改配置立即生效** —— 取用方每次都问当前配置，不缓存旧副本；
/// ② **非法配置拒绝并说明** —— 拒绝要带具体哪一条不合规，不是一句「配置无效」。
public enum AgentPermissionLevel: String, Codable, Sendable, CaseIterable {
    /// 只读：任何写 / 执行都要审批且默认拒。
    case readOnly
    /// 工作区内：沙箱根内可写可跑，界外一律拒。
    case scoped
    /// 全权：仍受 §3.6 审批与 §P2-3 刹停约束（等级不取消审批）。
    case fullAccess
}

public struct AgentSandboxRoot: Equatable, Sendable, Codable {
    /// 必须是**绝对路径**（相对路径没法判边界）。
    public var path: String
    /// 该根是否允许写；`false` ⇒ 只读根（读可以，写判越界）。
    public var allowsWrite: Bool

    public init(path: String, allowsWrite: Bool) {
        self.path = path
        self.allowsWrite = allowsWrite
    }
}

public enum AgentPermissionConfigError: Error, Equatable, Sendable {
    case mustBeAbsolute(String)
    case noRoots
    case duplicateRoot(String)
    case emptyCommand
    case unknownLevel(String)
}

public struct AgentPermissionConfig: Equatable, Sendable, Codable {
    public var level: AgentPermissionLevel
    public var roots: [AgentSandboxRoot]
    /// 可执行命令白名单（首个 token）。
    public var commands: [String]

    /// 出厂默认：只读、一个空的只读根（必须先声明根才能干活）。
    public static let readOnlyDefault = AgentPermissionConfig(
        level: .readOnly, roots: [], commands: []
    )

    public init(level: AgentPermissionLevel, roots: [AgentSandboxRoot], commands: [String]) {
        self.level = level
        self.roots = roots
        self.commands = commands
    }

    /// 校验并构造。`throws` 的那几种就是「非法配置」的全部情形。
    public static func validated(level: AgentPermissionLevel,
                                 roots: [AgentSandboxRoot],
                                 commands: [String]) throws -> AgentPermissionConfig {
        guard !roots.isEmpty else { throw AgentPermissionConfigError.noRoots }
        var seen = Set<String>()
        for root in roots {
            guard root.path.hasPrefix("/") else {
                throw AgentPermissionConfigError.mustBeAbsolute(root.path)
            }
            let normalized = (root.path as NSString).standardizingPath
            guard seen.insert(normalized).inserted else {
                throw AgentPermissionConfigError.duplicateRoot(root.path)
            }
        }
        for command in commands where command.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AgentPermissionConfigError.emptyCommand
        }
        return AgentPermissionConfig(level: level, roots: roots, commands: commands)
    }

    /// 该路径可写吗（等级 + 根两级都要过）。
    public func allowsWrite(to path: String) -> Bool {
        guard level != .readOnly else { return false }
        let normalized = (path as NSString).standardizingPath
        return roots.contains { root in
            root.allowsWrite && Self.isInside(normalized, root: (root.path as NSString).standardizingPath)
        }
    }

    /// 路径是否在某根内（**按路径分量**比较，不用字符串前缀 —— `/tmp/a` 不许匹配 `/tmp/ab`）。
    public static func isInside(_ path: String, root: String) -> Bool {
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }
}

/// 配置的**当前值**持有者：`apply` 成功即生效，失败则原样保留旧配置并报出原因。
public struct AgentPermissionConfigStore: Sendable {
    public private(set) var current: AgentPermissionConfig
    public private(set) var lastError: AgentPermissionConfigError?

    public init(current: AgentPermissionConfig = .readOnlyDefault) {
        self.current = current
    }

    /// 改配置：合法则立即生效；非法则**不动**当前值。
    @discardableResult
    public mutating func apply(level: AgentPermissionLevel,
                               roots: [AgentSandboxRoot],
                               commands: [String]) -> Result<AgentPermissionConfig, AgentPermissionConfigError> {
        do {
            let next = try AgentPermissionConfig.validated(level: level, roots: roots, commands: commands)
            current = next
            lastError = nil
            return .success(next)
        } catch let error as AgentPermissionConfigError {
            lastError = error
            return .failure(error)
        } catch {
            lastError = .unknownLevel("\(error)")
            return .failure(.unknownLevel("\(error)"))
        }
    }
}
