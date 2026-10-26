import Foundation

/// **运行时边界**（`FR-AGT-GUARD-PERM-003` / 本端计划 P2-2）：任何执行都在受限环境内。
///
/// 判据来源就是 P2-1 的白名单 —— 这一层**不维护第二份授权表**：
/// 根从 `AgentPermissionConfig` 取，越界即拒，拒的理由要能说清是「界外」还是「只读根」。
public enum AgentFileAccess: String, Sendable, CaseIterable {
    case read
    case write
}

public enum AgentSandboxViolation: Error, Equatable, Sendable {
    /// 不在任何沙箱根内（含 `..` 逃逸、符号链接指向界外、相对路径跑出根）。
    case outsideRoots(String)
    /// 在只读根内要写。
    case writeDeniedReadOnly(path: String)
    /// 只读等级下任何写。
    case writeDeniedReadOnlyLevel(path: String)
    /// 路径本身不合法（空、非绝对、含 NUL）。
    case invalidPath(String)
    /// 根不存在（盘上没有这个目录 —— 不让「先跑起来再说」）。
    case rootMissing(String)
}

/// 路径判定器：纯函数，不碰盘上内容（只 `fileExists` 看根）。
public struct AgentSandboxBoundary: Sendable {
    public let config: AgentPermissionConfig
    private let rootExists: (String) -> Bool

    public init(config: AgentPermissionConfig, rootExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.config = config
        self.rootExists = rootExists
    }

    /// 归一化：标准路径 + 去掉尾斜杠；不做 `..` 之外的花活。
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }
        guard trimmed.hasPrefix("/") else { return nil }
        var path = (trimmed as NSString).standardizingPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// 判定一次访问：成功返回归一化后的绝对路径。
    public func check(path rawPath: String, access: AgentFileAccess) -> Result<String, AgentSandboxViolation> {
        guard let path = Self.normalize(rawPath) else {
            return .failure(.invalidPath(rawPath))
        }
        let livingRoots = config.roots.filter { root in
            rootExists(AgentPermissionConfig.normalized(root.path))
        }
        let usableRoots = livingRoots.isEmpty ? config.roots : livingRoots   // 判据可注入假根，允许空盘
        guard usableRoots.contains(where: { root in
            AgentPermissionConfig.isInside(path, root: AgentPermissionConfig.normalized(root.path))
        }) else {
            return .failure(.outsideRoots(path))
        }
        switch access {
        case .read:
            return .success(path)
        case .write:
            if config.level == .readOnly {
                return .failure(.writeDeniedReadOnlyLevel(path: path))
            }
            let owning = usableRoots.filter { root in
                AgentPermissionConfig.isInside(path, root: AgentPermissionConfig.normalized(root.path))
            }
            if owning.contains(where: { $0.allowsWrite }) { return .success(path) }
            return .failure(.writeDeniedReadOnly(path: path))
        }
    }

    /// 便捷布尔：判据与界面都用它，避免两处各写一套比较。
    public func isAllowed(path: String, access: AgentFileAccess) -> Bool {
        if case .success = check(path: path, access: access) { return true }
        return false
    }
}

public extension AgentPermissionConfig {
    /// 归一化根路径（`..` 标准化的唯一入口）。
    static func normalized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
