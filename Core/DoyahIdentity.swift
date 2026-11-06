import Foundation

/// 产品身份常量 —— **改名的单一事实来源**。
///
/// 为什么要集中到一处：2026-09-22 从 `PostgresClient` 改名为 **Doyah Studio** 时发现，
/// 这几样东西原本散在 9 个文件里：包标识出现在构建脚本、`project.yml` 与钥匙串兜底值里，
/// 而 Application Support 的目录名在 6 个 Store（连接档 / 保存查询 / 智能体配置 /
/// 数据任务 / 审计日志 / 目录书签）里各写了一份字面量。下次再改名，只改这一个文件。
///
/// 注意区分两类常量：
/// - **现行**身份：新代码一律用它们；
/// - **历史**身份（`legacy*`）：只有一次性数据迁移会用（`Scripts/migrate-doyah-identity.sh`），
///   迁移完成后也不要删 —— 老容器/老钥匙串条目可能还在别人机器上，删了就再也迁不动了。
public enum DoyahIdentity {

    // MARK: - 现行身份

    /// 反查 DNS 形式的包标识。必须与 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`
    /// 以及 `Scripts/build-app.sh` 写进 `Info.plist` 的 `CFBundleIdentifier` 一致。
    ///
    /// 它同时决定三件事：沙箱容器位置、钥匙串 service 名（`KeychainSecretStore` 的默认值）、
    /// 以及 UserDefaults 的域。**改它 = 换容器 + 换钥匙串 = 必须配迁移。**
    public static let bundleIdentifier = "studio.doyah.DoyahStudio"

    /// 日常版（装机版）的 Application Support 数据目录名 —— 也是**回落值**与**变体继承的来源**。
    ///
    /// 常量只此一处：全仓其余位置一律读 `applicationSupportDirectoryName`（它先看 `Info.plist`
    /// 的覆盖项，再回落到这里）。改名的单一事实来源仍然是本文件。
    public static let defaultApplicationSupportDirectoryName = "DoyahStudio"

    /// Application Support 下的数据目录名：**可被构建变体覆盖**。
    ///
    /// 为什么需要覆盖（2026-11-06 实测）：同一个 `CFBundleIdentifier` 的两份 `.app`
    /// **根本不能同时跑** —— 装机版（`~/Applications`，日常开发工具，一直开着）在跑时，
    /// `open dist/…app` 与 `open -n` 都只是把已有实例调到前台（`ps aux` 里进程数始终为 1）。
    /// 所以 rc 包必须有自己的包标识；而**包标识一分开，数据目录也必须分开** ——
    /// 否则两个版本抢同一份 `agent.json` / `connections.json` / 会话与审计日志，
    /// 比覆盖安装更危险（两份进程各写各的，谁都不是真的）。
    ///
    /// 取值顺序：`Info.plist` 的 `DoyahDataDirectoryName`（由 `Scripts/build-app.sh --variant rc`
    /// 写入 `DoyahStudio-rc`）→ 回落到 `defaultApplicationSupportDirectoryName`。
    /// **日常版不写这个键** ⇒ 走回落分支，行为与产物路径一字不变。
    public static var applicationSupportDirectoryName: String {
        if let override = Bundle.main.object(forInfoDictionaryKey: dataDirectoryNameInfoKey) as? String {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return defaultApplicationSupportDirectoryName
    }

    /// `Info.plist` 里「数据目录名覆盖」的键名（构建脚本写、Core 读 —— 两边就这一个约定）。
    public static let dataDirectoryNameInfoKey = "DoyahDataDirectoryName"

    /// `Info.plist` 里「构建变体」的键名（`rc` / 缺省 = 日常版）。
    public static let buildVariantInfoKey = "DoyahBuildVariant"

    /// 这一次进程是哪个构建变体。读不到 / 认不出 ⇒ 按日常版对待（安全默认）。
    public static var buildVariant: DoyahBuildVariant {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: buildVariantInfoKey) as? String else {
            return .daily
        }
        return DoyahBuildVariant(rawValue: raw) ?? .daily
    }

    /// **笔记（插件）自己的数据家目录名** —— 与 `applicationSupportDirectoryName` **平级，刻意不嵌套在其下**。
    ///
    /// 为什么单独一层（FR-PLUG-04）：笔记是**另一个产品**（Doyah Notes）的数据，它不该跟宿主的
    /// 连接凭据 / 查询历史 / 审计日志混放在同一个目录里 —— 备份体积、清理策略、迁移节奏都各自独立，
    /// 宿主的清理不该顺手删掉用户的笔记，笔记的迁移也不该动宿主的数据家。
    ///
    /// 唯一读它的地方是 `NoteStore`（旧位置的一次性迁移见 `NoteStoreMigration`）。
    public static let notesDataDirectoryName = "DoyahNotes"

    /// 钥匙串 service 名的默认值：优先取运行时的真实包标识，取不到才退回常量
    /// （例如 CLI 这类没有 bundle 的可执行文件）。
    public static var keychainServiceName: String {
        Bundle.main.bundleIdentifier ?? bundleIdentifier
    }

    /// 终端里对外报出的版本名（XTVERSION 应答，`ESC P > | 名字 ESC \`）。
    ///
    /// **不冒充 xterm**：报自己的名字与版本，程序据此知道对面不是 xterm，
    /// 从而走保守分支（冒充的话它会按 xterm 的能力表来用我们没实现的东西）。
    public static var terminalVersionName: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        if let version, !version.isEmpty { return "DoyahStudio \(version)" }
        return "DoyahStudio"
    }

    // MARK: - 历史身份（仅供一次性迁移）

    /// 改名前的包标识（= 旧钥匙串 service 名、旧沙箱容器名）。
    public static let legacyBundleIdentifier = "com.vnull.PostgresClient"

    /// 改名前的数据目录名。
    public static let legacyApplicationSupportDirectoryName = "PostgresClient"
}

/// 构建变体：**日常版**与**rc 版**同时存在一台机器上（版本累进的开发节奏）。
///
/// 由 `Scripts/build-app.sh --variant rc` 写进 `Info.plist` 的 `DoyahBuildVariant`。
/// 变体要动的东西只有两样（都由构建脚本落地）：`CFBundleIdentifier` 加后缀（才能同时跑）
/// 与数据目录改名（各写各的）。
public enum DoyahBuildVariant: String, Sendable {
    /// 装机版（`~/Applications`，日常开发工具，一直开着）。缺省。
    case daily
    /// 开发中编出来的包（`dist/`，只用来验具体 bug / 功能）。
    case rc
}

/// rc 变体的**首次启动**配置继承：把日常版数据目录里的 `agent.json` / `connections.json`
/// 拷一份到 rc 自己的目录里（**只一次**）。
///
/// ## 为什么只拷这两个
///
/// rc 该继承的是「怎么连、模型怎么配」—— 这些是**配置**，两个版本本来就该一样，
/// 否则每开一次 rc 都要重配一遍模型端点和库连接。
///
/// **不拷**的是：`workspace-session.json`（上次开到哪个文件）、`agent-im/`（IM 收件箱的
/// 投递状态）、审计日志、会话 / 检查点 / 记忆 —— 那些是**日常版此刻的运行状态**。
/// 拷过来会让 rc 把日常版的收件箱当成自己的（同一封消息被两个进程各回一次），
/// 也会让「这一轮 rc 验了什么」混进日常版的账里。
///
/// ## 只一次
///
/// 判据是**rc 目录为空**（`startup.log` 不算 —— 它是本进程同一次启动里的留痕，
/// 不该把继承挡掉）。所以调用点必须在**任何 `StartupLog.write` 之前**
/// （`DoyahStudioApp.init()` 里紧跟单实例判定，见那里的注释）。
///
/// 若日常版目录里这两个文件都不存在，本次一律不写任何东西（目录仍然空）⇒ 下次启动还会再试一次 ——
/// 这正是想要的：主人先在日常版里配好，rc 下次启动才继承得到。
public enum VariantConfigInheritance {

    /// 只继承这两个文件（`ConnectionStore` / `AgentConfigurationStore` 的落盘位置，二者同处一目录）。
    public static let inheritedFileNames = ["agent.json", "connections.json"]

    /// 判断「rc 目录为空」时要忽略的、**本进程自己**很快就会写进去的留痕文件。
    public static let ignoredWhenCheckingEmptiness = ["startup.log"]

    /// 一次继承尝试的结局（`Equatable` 便于单测与日志断言）。
    public enum Outcome: Equatable {
        /// 不是变体构建（或目录名与日常版相同）：什么都不做。
        case notApplicable
        /// rc 目录里已经有东西 ⇒ 不是首次启动。
        case alreadySeeded
        /// 拷了这些文件。
        case inherited([String])
        /// 日常版目录在，但这两个文件都没有。
        case nothingToInherit
        /// 日常版目录不存在 ⇒ 跳过。
        case primaryMissing(String)
        /// 拷贝失败（权限 / 磁盘）。
        case failed(String)
    }

    /// 启动时调用（目录名与变体都从 `Info.plist` 读）。
    public static func runOnLaunch(fileManager: FileManager = .default) -> Outcome {
        let root = applicationSupportRoot(fileManager: fileManager)
        return run(
            fileManager: fileManager,
            variant: DoyahIdentity.buildVariant,
            applicationSupport: root,
            currentDirectoryName: DoyahIdentity.applicationSupportDirectoryName,
            primaryDirectoryName: DoyahIdentity.defaultApplicationSupportDirectoryName
        )
    }

    /// 判据本体（纯函数：四个入参决定一切，便于「不碰真实目录」地验各档）。
    public static func run(
        fileManager: FileManager,
        variant: DoyahBuildVariant,
        applicationSupport: URL,
        currentDirectoryName: String,
        primaryDirectoryName: String
    ) -> Outcome {
        // 日常版什么都不做；目录名与日常版相同也不行（那等于两个版本抢同一份数据）。
        guard variant != .daily, currentDirectoryName != primaryDirectoryName else {
            return .notApplicable
        }
        let current = applicationSupport.appendingPathComponent(currentDirectoryName, isDirectory: true)
        let primary = applicationSupport.appendingPathComponent(primaryDirectoryName, isDirectory: true)
        let existing = (try? fileManager.contentsOfDirectory(atPath: current.path)) ?? []
        let meaningful = existing.filter { !ignoredWhenCheckingEmptiness.contains($0) }
        guard meaningful.isEmpty else { return .alreadySeeded }
        guard fileManager.fileExists(atPath: primary.path) else { return .primaryMissing(primary.path) }
        do {
            try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
            var copied: [String] = []
            for name in inheritedFileNames {
                let source = primary.appendingPathComponent(name, isDirectory: false)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = current.appendingPathComponent(name, isDirectory: false)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.copyItem(at: source, to: destination)
                copied.append(name)
            }
            return copied.isEmpty ? .nothingToInherit : .inherited(copied)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// 把结局翻成一行人话（`nil` = 不必记日志）。日常版一个字都不写进 `startup.log`。
    public static func launchLogLine(for outcome: Outcome) -> String? {
        switch outcome {
        case .notApplicable, .alreadySeeded:
            return nil
        case let .inherited(names):
            return "rc 首次启动：已从主目录继承配置（\(names.joined(separator: "、"))）"
        case .nothingToInherit:
            return "rc 首次启动：主目录里没有 agent.json / connections.json，跳过配置继承"
        case let .primaryMissing(path):
            return "rc 首次启动：主目录不存在（\(path)），跳过配置继承"
        case let .failed(reason):
            return "rc 首次启动：配置继承失败（\(reason)）"
        }
    }

    /// 本机 Application Support 根目录（与各 Store 的取法一致）。
    public static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
