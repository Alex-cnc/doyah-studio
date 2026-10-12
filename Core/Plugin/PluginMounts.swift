import Foundation

/// 挂点装配的**消费侧**：把「注册表里有哪些插件」翻译成宿主需要的判断（概设 §5 · 契约 §3.52③④）。
///
/// **为什么单独一个类型**：宿主只该问两件事 —— 「这一项挂上了吗」「这个挂点有人吗」。
/// 让视图各自去读清单，就会出现"每个视图各自解释清单"的多判据；这里把清单读一次、判据只留一处
/// （可见性判据仍在 `LicensePresentation` 那一处调用，本类型只提供"挂没挂"这一个事实）。
public struct PluginMounts: Equatable, Sendable {
    /// 缺位的插件 id（清单缺失 / 被降级）。**缺位 = 它的挂点整体消失**（契约 §3.52④）。
    public let unmountedPlugins: Set<String>

    public init(unmountedPlugins: Set<String>) {
        self.unmountedPlugins = unmountedPlugins
    }

    /// **不过滤**（默认值）：给单测 / 预览 / 还没接插件面的调用方 —— 老行为一字不变。
    public static let disabled = PluginMounts(unmountedPlugins: [])

    /// 活动栏项 → **背书它的插件 id**；`nil` = **基础核心**，不受插件有无影响。
    ///
    /// 这张映射表就是「什么进插件」的落地形态（契约 §3.52①）：首批 = 回放、笔记；
    /// 基础核心 = 编辑器 / 工作区 / 终端 / 数据库 / 文件与搜索 / 设置与凭据。
    public static func ownerPluginID(of item: ActivityBarItem) -> String? {
        switch item {
        case .retro:
            return "Replay"
        case .notes:
            // 笔记**暂不接**：契约 §3.52⑥「既有实现不要求立刻搬家」——
            // 等笔记真搬进 `Plugins/Notes/` 那一轮再接，否则今天就会把笔记区判没。
            return nil
        case .workspace, .database:
            return nil
        }
    }

    /// 该项该不该出现（许可之外的那一半）。
    public func isMounted(_ item: ActivityBarItem) -> Bool {
        guard let owner = Self.ownerPluginID(of: item) else { return true }
        return !unmountedPlugins.contains(owner)
    }

    /// 扫盘装配（app 侧用）。测试 / 探针可传自己的注册表与目录。
    ///
    /// **fail-open 的边界（重要）**：**插件根目录不存在 ⇒ 不过滤** ——
    /// 那是「插件面还没接进来」（单测、CLI、老形态），不是「插件被卸掉」。
    /// 两者混同会把功能判没；「插件不在 ⇒ 消失」这条判据只对**根目录存在**的装配面成立。
    public static func live(
        registry: PluginRegistry,
        pluginsDirectory: URL? = PluginManifestLoader.defaultPluginsDirectory()
    ) -> PluginMounts {
        guard let pluginsDirectory, FileManager.default.fileExists(atPath: pluginsDirectory.path) else {
            return .disabled
        }
        let referenced = Set(ActivityBarItem.allCases.compactMap(ownerPluginID(of:)))
        let active = Set(registry.active.map(\.id))
        return PluginMounts(unmountedPlugins: referenced.subtracting(active))
    }

    /// 机器可读的一行读数（探针用；ASCII，避免撞 Core 本地化棘轮）。
    public var unmountedSummary: String {
        guard !unmountedPlugins.isEmpty else { return "unmounted=[]" }
        return "unmounted=[\(unmountedPlugins.sorted().joined(separator: ","))]"
    }
}
