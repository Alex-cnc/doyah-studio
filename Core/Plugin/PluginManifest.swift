import Foundation

/// 插件清单（manifest）：插件「能装什么、要什么、挂哪儿」的**唯一声明**（概设 §3.1）。
///
/// **为什么要有它**：插件化之前，笔记是随宿主一起编译的模块 —— 「装得上 / 卸得掉」
/// 这件事**无处表达**。清单把装卸语义变成**数据**（可解析、可 dump、可门禁），
/// 而不是散在代码里的 `if pluginX` 分支。
///
/// **边界**（概设 §1 非目标，必须守住）：
/// - 清单里**没有"权限开关"**这类字段 —— 能力位仍只有 `LicensePresentation` 一处判据（§3.24）；
/// - 清单只**声明**，不引入 IPC、不引入动态下载（Q20 = A 不变）。
public struct PluginManifest: Codable, Equatable, Sendable {
    /// 挂点声明（概设 §5）：只声明**位置与形态**；「谁能看见」由宿主按能力位裁决。
    public struct Contribution: Codable, Equatable, Sendable {
        /// 宿主挂点 = **契约 §3.52③ 点名的那些口子**（插件只能经这些接进来）。
        /// 多一个自定义挂点就等于开了一条"插件自己决定的接线" ⇒ 这里只收契约里有的。
        public enum Point: String, Codable, Sendable, CaseIterable {
            case activityBar
            case mainPaneTab
            /// Home 区页签（契约与 `mainPaneTab` 并列点名）——首页也是挂点，不是核心特权。
            case homePaneTab
            case menu
            case settings
            case searchIndex
            /// 存储工厂：插件走"宿主代管存储"时的插入口（契约 §3.52⑤）。
            case storageFactory
            /// 通知与审计投递（契约 §3.52③ 尾项）：插件说话要经宿主这一层。
            case notificationSink
            case statusBar
            case commandPalette
        }

        public let point: Point
        /// 同挂点内的排序；缺省 = 清单声明顺序。
        public let order: Int?

        public init(point: Point, order: Int? = nil) {
            self.point = point
            self.order = order
        }
    }

    /// 存储归属（概设 §6）：默认 `pluginOwned`（沿用 `FR-PLUG-04` 数据家独立）。
    public enum Storage: String, Codable, Sendable {
        case pluginOwned
        case hostManaged
    }

    public let id: String
    public let displayName: String
    public let version: String
    /// 入口 target（契约 §3.52② 点名字段）：构建只消费它 —— 没有它，"装哪一份代码"就得靠人记。
    public let entryTarget: String
    /// 宿主 API 版本；不匹配 ⇒ **只降级该插件**（不崩、不静默）。
    public let apiVersion: Int
    public let capabilities: [String]
    public let contributions: [Contribution]
    public let storage: Storage

    /// 宿主当前 API 版本。**升这个数 = 有意的不兼容变更**（旧清单会被降级并列明原因）。
    public static let currentAPIVersion = 1

    public init(
        id: String,
        displayName: String,
        version: String,
        entryTarget: String,
        apiVersion: Int,
        capabilities: [String],
        contributions: [Contribution],
        storage: Storage
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.entryTarget = entryTarget
        self.apiVersion = apiVersion
        self.capabilities = capabilities
        self.contributions = contributions
        self.storage = storage
    }
}

/// 清单的**读取与校验**（纯逻辑、不碰界面，故在 Core 里可单测）。
///
/// 校验失败的语义是**降级**而不是崩溃：坏插件不该拖垮宿主（概设 §3.3、§4 失败隔离）。
public enum PluginManifestLoader {
    /// 插件目录名（宿主仓内，概设未定项 1 的建议值）。
    public static let pluginsDirectoryName = "Plugins"
    /// 清单文件名。
    public static let manifestFileName = "plugin.json"
    /// 测试 / 排障用的目录覆盖键（同 `DOYAH_LICENSE_PATH` 一类）。
    public static let directoryOverrideKey = "DOYAH_PLUGINS_DIR"

    /// 一个插件目录的加载结果：成功给 `manifest`，失败给 `degradedReason`（**不抛给宿主**）。
    public struct Loaded: Equatable, Sendable {
        /// 目录名 —— 清单读不出来时也是可读的标识（用于诊断行）。
        public let directoryName: String
        public let manifest: PluginManifest?
        public let degradedReason: String?

        public var isActive: Bool { manifest != nil && degradedReason == nil }

        public init(directoryName: String, manifest: PluginManifest?, degradedReason: String?) {
            self.directoryName = directoryName
            self.manifest = manifest
            self.degradedReason = degradedReason
        }
    }

    /// 解析一份清单数据。
    public static func decode(_ data: Data) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: data)
    }

    /// 加载一个插件目录下的清单（不递归；`plugin.json` 必须在插件目录根上）。
    public static func load(pluginDirectory: URL) -> Loaded {
        let name = pluginDirectory.lastPathComponent
        let manifestURL = pluginDirectory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return Loaded(directoryName: name, manifest: nil, degradedReason: "missing \(manifestFileName)")
        }
        do {
            let manifest = try decode(try Data(contentsOf: manifestURL))
            if let reason = degradationReason(for: manifest) {
                return Loaded(directoryName: name, manifest: manifest, degradedReason: reason)
            }
            // 目录名与清单 id 不一致属**声明漂移**：读得出来但要如实说，否则诊断行会指错人。
            if manifest.id != name {
                return Loaded(
                    directoryName: name,
                    manifest: manifest,
                    degradedReason: "directory name does not match manifest id (dir \(name) / manifest \(manifest.id))"
                )
            }
            return Loaded(directoryName: name, manifest: manifest, degradedReason: nil)
        } catch {
            return Loaded(directoryName: name, manifest: nil, degradedReason: "manifest parse failed: \(error)")
        }
    }

    /// 扫描插件根目录（按目录名字典序，保证诊断行与门禁读数可复现）。
    public static func load(pluginsDirectory: URL) -> [Loaded] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let directories = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return directories.map(load(pluginDirectory:))
    }

    /// 插件根目录：环境覆盖优先，其次 app 包内 `Plugins/`（仓库根目录留给 CLI 显式 `--dir`）。
    public static func defaultPluginsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> URL? {
        if let override = environment[directoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundle.url(forResource: pluginsDirectoryName, withExtension: nil)
    }

    /// 降级判据（**只有两条**：API 版本、存储归属；能力位不在这里判 —— 见类型注释的边界）。
    public static func degradationReason(for manifest: PluginManifest) -> String? {
        if manifest.apiVersion != PluginManifest.currentAPIVersion {
            return "apiVersion mismatch (manifest \(manifest.apiVersion) / host \(PluginManifest.currentAPIVersion))"
        }
        return nil
    }
}
