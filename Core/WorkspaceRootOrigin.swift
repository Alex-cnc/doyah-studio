import Foundation

/// 工作区根的**来源**（`FR-STD-WS-FS-011`）。
///
/// 只有两态，没有第三态：**默认**（`~/.doyah`）与**用户打开**（用户自己通过「打开文件夹…」
/// 选定的那个目录）。凡是从别处推出来的目录（上次编译目录、进程工作目录、书签表里第一条）
/// 都不构成来源 —— 那些正是「装到 `/Applications` 之后 Agent 的作用域锁在开发目录」的成因。
public enum WorkspaceRootOrigin: String, Codable, Sendable, Equatable {
    /// 产品自带的默认根：`~/.doyah`。
    case defaultRoot = "default"
    /// 用户显式打开的那个文件夹。
    case userOpened = "user-opened"

    /// 持久化键（判据与迁移都要认同一份字面量）。
    public var storageValue: String { rawValue }
}

/// 落盘的来源标记。**有它 = 用户/程序已经就来源做过一次决定**；没有它 = 旧数据或首次运行。
public struct WorkspaceRootRecord: Codable, Sendable, Equatable {
    public var origin: WorkspaceRootOrigin
    /// 只在 `userOpened` 时有意义；`defaultRoot` 下为 `nil`（默认根由常量决定，不另存一份路径）。
    public var path: String?

    public init(origin: WorkspaceRootOrigin, path: String? = nil) {
        self.origin = origin
        self.path = path
    }
}

/// 默认工作区根（`~/.doyah`）。
public enum AgentWorkspaceRoot {
    /// 目录名 —— 改名只改这一处。
    public static let directoryName = ".doyah"

    /// 默认根的绝对路径。
    ///
    /// 不读 `FileManager.currentDirectoryPath`、不读 `Bundle.main.bundleURL`：
    /// 装到哪儿、从哪个目录启动，都不影响它。
    public static func defaultURL(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home.appendingPathComponent(directoryName, isDirectory: true)
    }
}

/// 「这次该用哪个根」的结论。
public enum WorkspaceRootPlan: Equatable, Sendable {
    /// 默认根；`migratedFrom` 非空 = 这是从旧数据迁过来的，界面要说一句。
    case defaultRoot(migratedFrom: String?)
    /// 用户打开的那个目录（绝对路径）。
    case userOpened(String)
}

/// 判据本体：**纯函数**，四个输入决定一切（记录、旧数据里的路径）。
public enum WorkspaceRootPlanning {

    /// 三档：
    ///   ① 有记录且是 `userOpened`、路径非空 ⇒ 用它；
    ///   ② 有记录且是 `defaultRoot` ⇒ 默认根（旧数据已经迁过，不再重复提示）；
    ///   ③ 没有记录（首次运行 / 旧版本数据）⇒ 默认根；**旧数据里有路径就带 `migratedFrom`**
    ///      —— 这一档必须能被界面看见，静默迁移等于把用户原来的工作区悄悄换掉。
    ///
    /// 记录坏了（`userOpened` 但路径空 / 空串）按 ③ 处理：宁可落回默认根并说一句，
    /// 也不猜一个路径出来。
    public static func plan(record: WorkspaceRootRecord?, legacyPath: String?) -> WorkspaceRootPlan {
        let legacy = normalize(legacyPath)
        if let record {
            switch record.origin {
            case .userOpened:
                if let path = normalize(record.path) { return .userOpened(path) }
                return .defaultRoot(migratedFrom: legacy)
            case .defaultRoot:
                return .defaultRoot(migratedFrom: nil)
            }
        }
        return .defaultRoot(migratedFrom: legacy)
    }

    /// 去空白；空串一律当「没有」。
    public static func normalize(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// 来源标记的落盘（与 `workspace-bookmark.json` / `workspace-session.json` 同处一个数据目录、
/// 各自一个文件：三份文件的职责不同，混存会让「读不动书签」连带把来源也判成没有）。
public struct WorkspaceRootOriginStore: Sendable {

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认位置：应用数据目录下的 `workspace-origin.json`。
    public static func standard(applicationSupport: URL? = nil) -> WorkspaceRootOriginStore {
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return WorkspaceRootOriginStore(
            fileURL: base
                .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent("workspace-origin.json", isDirectory: false)
        )
    }

    /// 读取；文件不存在 / 空文件视为**没有记录**（不是错误），坏文件**抛错**
    /// （与 `WorkspaceSessionStore` 同口径：坏文件不许静默当成「没有」）。
    public func load() throws -> WorkspaceRootRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(WorkspaceRootRecord.self, from: data)
        } catch {
            // 认不出的来源标记（老版本写过的别的形状 / 手改坏了）：按「没有记录」处理，
            // 落回默认根 —— 猜一个来源比没有来源更坏。
            return nil
        }
    }

    /// 写入（原子替换；目录不存在时先建）。
    public func save(_ record: WorkspaceRootRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    /// 丢掉标记（`clear()` 清空工作区时用；下次启动即按首次运行处理）。
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// 工作区来源那几行的文案（Core 不认语言表，只认 `AppLanguage`；界面与 store 共用这一份，
/// 免得「提示里说的」与「设置里写的」是两句话）。
public enum WorkspaceRootCopy {

    public static func title(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "智能体工作区"
        case .english: return "Agent workspace"
        }
    }

    public static func rootLabel(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "工作区根"
        case .english: return "Workspace root"
        }
    }

    public static func originLabel(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "来源"
        case .english: return "Origin"
        }
    }

    public static func originText(_ origin: WorkspaceRootOrigin, defaultPath: String,
                                  _ language: AppLanguage) -> String {
        switch (origin, language) {
        case (.defaultRoot, .simplifiedChinese): return "默认（\(defaultPath)）"
        case (.defaultRoot, .english): return "Default (\(defaultPath))"
        case (.userOpened, .simplifiedChinese): return "用户打开"
        case (.userOpened, .english): return "Opened by you"
        }
    }

    public static func restoreDefaultButton(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "恢复默认（~/.doyah）"
        case .english: return "Restore default (~/.doyah)"
        }
    }

    public static func openFolderButton(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "打开文件夹…"
        case .english: return "Open Folder…"
        }
    }

    /// 旧数据迁移那一行（**必须出现**，不许静默）。
    public static func migratedNotice(previousPath: String, _ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "Agent 工作区已改为 ~/.doyah（原目录 \(previousPath) 可在设置里改回）"
        case .english:
            return "The agent workspace is now ~/.doyah (the previous folder \(previousPath) can be restored in Settings)"
        }
    }

    /// 默认根建不出来 / 不可写时那一句。
    public static func defaultRootUnavailable(path: String, reason: String,
                                              _ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "默认工作区 \(path) 不可用：\(reason)"
        case .english:
            return "Default workspace \(path) is unavailable: \(reason)"
        }
    }
}
