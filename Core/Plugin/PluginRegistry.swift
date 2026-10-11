import Foundation

/// 插件注册表：宿主「认识哪些插件、哪些被降级、每个挂点归谁」的**唯一来源**（概设 §4）。
///
/// **反例（本类型存在的理由）**：宿主里出现 `if pluginNotes { … }` 这种按插件名分支的代码 ——
/// 一旦有它，「删掉插件功能就消失」就不再是可机械判定的性质。所以挂点归属**只从这里查**，
/// 门禁（`Scripts/check-plugin-assembly.py`）据此断言「挂点唯一来源」。
public struct PluginRegistry: Equatable, Sendable {
    /// 被降级的插件：**列出来、不静默**（同许可证降级的纪律，§3.24 第 9 条）。
    public struct Degraded: Equatable, Sendable {
        public let id: String
        public let reason: String

        public init(id: String, reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    /// 已激活插件（按清单声明顺序：目录名字典序 → 同挂点内按 `order`）。
    public let active: [PluginManifest]
    public let degraded: [Degraded]

    public init(loaded: [PluginManifestLoader.Loaded]) {
        self.active = loaded.compactMap { $0.degradedReason == nil ? $0.manifest : nil }
        self.degraded = loaded.compactMap { item in
            guard let reason = item.degradedReason else { return nil }
            // 清单读得出来就用清单 id（诊断行指人准）；读不出来退回目录名。
            return Degraded(id: item.manifest?.id ?? item.directoryName, reason: reason)
        }
    }

    public static let empty = PluginRegistry(loaded: [])

    /// 按插件根目录装配注册表（目录缺失 ⇒ 空注册表，**不是错误**：插件不在就是不在）。
    public static func load(pluginsDirectory: URL?) -> PluginRegistry {
        guard let pluginsDirectory else { return .empty }
        guard FileManager.default.fileExists(atPath: pluginsDirectory.path) else { return .empty }
        return PluginRegistry(loaded: PluginManifestLoader.load(pluginsDirectory: pluginsDirectory))
    }

    /// 默认位置装配（env 覆盖 → app 包内 `Plugins/`）。
    public static func loadDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> PluginRegistry {
        load(pluginsDirectory: PluginManifestLoader.defaultPluginsDirectory(environment: environment, bundle: bundle))
    }

    /// 启动诊断行（排障用，同「许可证：…」那一行）：**列明激活与降级**，不打印"一切正常"就完事。
    public var diagnosticLine: String {
        let activeText = active.isEmpty ? "（无）" : active.map(\.id).joined(separator: ",")
        guard !degraded.isEmpty else {
            return "插件：\(activeText) / 降级：无"
        }
        let degradedText = degraded.map { "\($0.id)（\($0.reason)）" }.joined(separator: "；")
        return "插件：\(activeText) / 降级：\(degradedText)"
    }

    /// 某个挂点的所有者（按 `order` 升序，缺省排后）。挂点归属**只此一处**可查。
    public func owners(of point: PluginManifest.Contribution.Point) -> [String] {
        active
            .compactMap { manifest -> (String, Int)? in
                guard let contribution = manifest.contributions.first(where: { $0.point == point }) else {
                    return nil
                }
                return (manifest.id, contribution.order ?? Int.max)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
            .map(\.0)
    }

    /// 是否声明了某个挂点（宿主据此决定「这一块要不要画」，而不是逐插件写 if）。
    public func hasContributions(at point: PluginManifest.Contribution.Point) -> Bool {
        !owners(of: point).isEmpty
    }
}
