import Foundation

// MARK: - 扩展点槽位（需求 `FR-AGT-LINK-EXT-003` ④：封闭六类）
//
// 一句话：**插件只能挂在这六个口子上**，想加第七类得改内核，那不算装插件。
// 落成 `enum` + `CaseIterable` 而不是「字符串随便写」：清单里的 `slot` 用字符串存，
// 校验期判这张封闭表 —— 第六类之外的写法在**装的时候**就被拒，而不是运行时
// 「神奇地不生效」（后者用户看到的是「装了没用」，排查要花掉一整轮）。
public enum AgentExtensionSlot: String, Codable, Equatable, Sendable, CaseIterable {
    /// 记忆后端（`FR-AGT-KNOW-MEM`）
    case memoryBackend = "memory"
    /// 模型来源（多档模型的来源一侧）
    case modelSource = "model"
    /// 工具库（不止内置那八件）
    case toolLibrary = "tool"
    /// 定时任务源
    case scheduleSource = "schedule"
    /// 通道（IM / 外部消息面）
    case channel = "channel"
    /// 存储
    case storage = "storage"

    /// 与清单里的 `slot` 同一字面量（诊断行 / 台账渲染都用它，别另造一套拼写）。
    public var manifestValue: String { rawValue }
}

/// 内核五项：**不可插件化**（需求书 §3.2「不是到处都能挂钩子」那一段逐字点名的五件）。
///
/// 它存在的意义只有一个：让「插件想接管循环 / 刹停」这件事在**校验期**就是一条具名拒绝，
/// 而不是靠评审肉眼从清单里找出来。
public enum AgentKernelFacet: String, Codable, Equatable, Sendable, CaseIterable {
    /// 循环（`AgentLoop`）
    case loop
    /// 刹停（`AgentPreActionStop` / 急停）
    case stop
    /// 先验（工作区上下文注入）
    case prior
    /// 会话持久化
    case sessionPersistence = "session"
    /// 队列（本轮后排发 / 排队提问）
    case queue

    public var manifestValue: String { rawValue }
}

// MARK: - 拒绝原因（全机器码，人话由渲染层给）

/// 校验 / 调用被拒的原因。**一律 ASCII 机器码**：Core 里不写用户可见文案
/// （语言由渲染层按 `language:` 决定），判据也就不用跟文案对账。
public enum AgentExtensionRejection: String, Equatable, Sendable, Error {
    /// 清单读不出来（JSON 坏 / 缺字段）
    case manifestUnreadable
    /// 槽位不在六类封闭清单里
    case slotUnknown
    /// 槽位写成了内核五项之一
    case slotIsKernelFacet
    /// `provides` 里混进了内核五件的名字
    case providesKernelFacet
    /// 没有声明权限块（①：清单必须写明能读哪些目录 / 能调哪些命令）
    case permissionNotDeclared
    /// `provides` 空 = 装了也什么都接不上
    case providesEmpty
    /// 钩子声明「可能放宽」—— 契约要求只能收紧
    case hookNotTighteningOnly
    /// `id` 空
    case idEmpty
}

/// 调用 / 读文件 / 跑命令的判定结果。
public enum AgentExtensionAccess: Equatable, Sendable {
    case allowed
    case denied(AgentExtensionDenial)

    public var isAllowed: Bool { self == .allowed }

    /// 机器码（对账 / 渲染都用它）。
    public var denial: AgentExtensionDenial? {
        if case let .denied(reason) = self { return reason }
        return nil
    }
}

/// 未授权调用被拒的具名原因（②：未授权的能力不可调用）。
public enum AgentExtensionDenial: String, Equatable, Sendable {
    /// 这个 id 没装（或已卸）
    case notInstalled
    /// 装的是别的槽位
    case slotMismatch
    /// 能力名不在本次授权的集合里（用户只批了子集）
    case capabilityNotGranted
    /// 目录没在清单里声明
    case directoryNotDeclared
    /// 目录声明了但这次安装没授权
    case directoryNotGranted
    /// 命令没在清单里声明
    case commandNotDeclared
    /// 命令声明了但这次安装没授权
    case commandNotGranted
    /// 空路径 / 空命令（边界：不许拿空串蒙过去）
    case emptyRequest
}

// MARK: - 清单

/// 智能体侧插件清单（`extension.json`）。
///
/// 与宿主那份 `plugin.json`（`Core/Plugin/PluginManifest.swift`）**分开**：
/// 那一份管「界面挂哪儿、装哪一份代码」，这一份管「能读哪些目录、能调哪些命令、
/// 钩子最多收紧到哪一档」。分开的理由是边界 —— 宿主清单的注释里写死了一条
/// 「清单里没有权限开关（能力位只有 `LicensePresentation` 一处判据）」，
/// 把权限塞进去等于同时动两套语义。
public struct AgentExtensionManifest: Codable, Equatable, Sendable {

    /// 权限声明（①）。`nil` = 清单里根本没写这一块 ⇒ 拒装（不是「默认为空」）。
    public struct Permission: Codable, Equatable, Sendable {
        /// 可读目录（绝对路径；按路径分量做包含判断，不做字符串前缀）。
        public var readableDirectories: [String]
        /// 可调命令（程序名，或其后的固定前缀；超出的参数不放宽）。
        public var allowedCommands: [String]

        public init(readableDirectories: [String] = [], allowedCommands: [String] = []) {
            self.readableDirectories = readableDirectories
            self.allowedCommands = allowedCommands
        }
    }

    /// 策略钩子（⑤）。**只能收紧**：`tighteningOnly` 必须是 `true`，
    /// 且它能表达的最高档就是 `maxTighten` —— 到不了「放宽」。
    public struct Hook: Codable, Equatable, Sendable {

        public enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
            case preToolUse = "preToolUse"
            case preModelCall = "preModelCall"
            case preCommand = "preCommand"
        }

        /// 收紧档（`note` < `requiresApproval` < `deny`）。只用于**清单声明**；
        /// 运行期的判定在 `AgentPolicyCombiner`。
        public enum Tighten: String, Codable, Equatable, Sendable, CaseIterable {
            case note
            case requiresApproval
            case deny
        }

        public var kind: Kind
        public var maxTighten: Tighten
        /// 契约要求：声明只能收紧。写 `false` ⇒ 拒装（不是运行时才判）。
        public var tighteningOnly: Bool

        public init(kind: Kind, maxTighten: Tighten = .note, tighteningOnly: Bool = true) {
            self.kind = kind
            self.maxTighten = maxTighten
            self.tighteningOnly = tighteningOnly
        }
    }

    public var id: String
    /// 槽位**存原样字符串**：这样「写了第七类」在磁盘上看得见，校验期能报具名拒绝。
    public var slot: String
    /// 在这个槽位里提供的能力名（工具名 / 模型来源名 / 通道名 …）。
    public var provides: [String]
    /// 权限块；缺 = 拒装。
    public var permission: Permission?
    public var hooks: [Hook]

    public init(
        id: String,
        slot: String,
        provides: [String],
        permission: Permission?,
        hooks: [Hook] = []
    ) {
        self.id = id
        self.slot = slot
        self.provides = provides
        self.permission = permission
        self.hooks = hooks
    }
}

// MARK: - 校验（装之前）

public enum AgentExtensionVerdict: Equatable, Sendable {
    case installable(AgentExtensionManifest)
    case rejected(AgentExtensionRejection)

    public var manifest: AgentExtensionManifest? {
        if case let .installable(manifest) = self { return manifest }
        return nil
    }

    public var rejection: AgentExtensionRejection? {
        if case let .rejected(reason) = self { return reason }
        return nil
    }
}

public enum AgentExtensionValidator {

    /// 清单文件在插件目录里的名字（与宿主 `plugin.json` 并列、互不取代）。
    public static let manifestFileName = "extension.json"

    /// 解析一份清单数据。坏 JSON **不抛给宿主**，落成具名拒绝。
    public static func decode(_ data: Data) -> AgentExtensionVerdict {
        do {
            let manifest = try JSONDecoder().decode(AgentExtensionManifest.self, from: data)
            return validate(manifest)
        } catch {
            return .rejected(.manifestUnreadable)
        }
    }

    /// 六条验收要点里能被机械判的那几条，全在这一处判。
    public static func validate(_ manifest: AgentExtensionManifest) -> AgentExtensionVerdict {
        let trimmedID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return .rejected(.idEmpty) }

        // ④ 封闭清单：先判「是不是内核五项」，再判「在不在六类里」——
        // 两者混成一句会把「插件想接管循环」报成「槽位拼错了」，诊断行会指错方向。
        let slotRaw = manifest.slot.trimmingCharacters(in: .whitespacesAndNewlines)
        if AgentKernelFacet(rawValue: slotRaw) != nil { return .rejected(.slotIsKernelFacet) }
        guard AgentExtensionSlot(rawValue: slotRaw) != nil else { return .rejected(.slotUnknown) }

        // ① 权限必须**明写**（`nil` 不等于「空权限」，前者是没声明）
        guard manifest.permission != nil else { return .rejected(.permissionNotDeclared) }

        let provided = manifest.provides.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !provided.isEmpty else { return .rejected(.providesEmpty) }
        if provided.contains(where: { AgentKernelFacet(rawValue: $0) != nil }) {
            return .rejected(.providesKernelFacet)
        }

        // ⑤ 钩子在清单层就得声明「只收紧」
        if manifest.hooks.contains(where: { !$0.tighteningOnly }) {
            return .rejected(.hookNotTighteningOnly)
        }

        return .installable(manifest)
    }
}

// MARK: - 授权台账（装了才生效 / 未授权不可调用）

/// 一次安装的授权面：**用户批了多少，就只放行多少**。
///
/// `capabilities` / `directories` / `commands` 是**这一台机器上这次安装**的授权，
/// 不是清单里的声明 —— 声明是「我要什么」，这里是「给了什么」。
public struct AgentExtensionGrant: Equatable, Sendable {
    public let manifest: AgentExtensionManifest
    public let capabilities: Set<String>
    public let directories: [String]
    public let commands: [String]
    /// 这个插件**自己声明拥有**的文件 / 目录（卸载只删这些，见 ③）
    public let ownedPaths: [String]
    /// 安装时登记的子进程（卸载要停掉）
    public let childProcesses: [Int32]

    public init(
        manifest: AgentExtensionManifest,
        capabilities: Set<String>,
        directories: [String],
        commands: [String],
        ownedPaths: [String] = [],
        childProcesses: [Int32] = []
    ) {
        self.manifest = manifest
        self.capabilities = capabilities
        self.directories = directories
        self.commands = commands
        self.ownedPaths = ownedPaths
        self.childProcesses = childProcesses
    }
}

/// 卸载后的残留读数（③：**卸载后无残留进程与配置文件** —— 这句话必须可量，不然等于没说）。
public struct AgentExtensionResidue: Equatable, Sendable {
    /// 盘上仍然存在的自有路径（空 = 配置文件已清干净）
    public let paths: [String]
    /// 还登记着、没被报告终止的子进程（空 = 无残留进程）
    public let processes: [Int32]
    /// 授权台账里还挂着这个 id（空 = 授权也一起收掉了）
    public let grantRemains: Bool

    public var isClean: Bool { paths.isEmpty && processes.isEmpty && !grantRemains }
}

public struct AgentExtensionUninstallReceipt: Equatable, Sendable {
    public let pluginID: String
    public let wasInstalled: Bool
    public let removedPaths: [String]
    public let processesToStop: [Int32]
    public let residue: AgentExtensionResidue
}

/// 扩展点的唯一入口：装 / 卸 / 判能不能调。
///
/// 有意做成 `struct` + `mutating` 的台账（不是全局单例）：判据能造两份互不干扰的实例，
/// 也就不会出现「测试之间互相污染授权」这种假绿。
public struct AgentExtensionDesk: Sendable {

    /// 已卸掉的插件留下的自有面 —— 只用于算残留读数，不再参与判定。
    private struct Retired: Sendable {
        let paths: [String]
        let processes: [Int32]
    }

    private var grants: [String: AgentExtensionGrant] = [:]
    private var uninstalled: [String: Retired] = [:]
    /// 还活着的子进程（`markProcessTerminated` 才减）
    private var liveProcesses: [String: Set<Int32>] = [:]

    public init() {}

    public var installedIDs: [String] { grants.keys.sorted() }

    public func grant(for pluginID: String) -> AgentExtensionGrant? { grants[pluginID] }

    // MARK: 装

    /// 安装一个插件。`capabilities` 缺省 = 清单里 `provides` 的全部（用户装的时候一次批）。
    ///
    /// 校验不过 ⇒ **不落台账**，返回具名拒绝（装了才生效：没装成就不该有任何一条能力可调）。
    @discardableResult
    public mutating func install(
        _ manifest: AgentExtensionManifest,
        capabilities: Set<String>? = nil,
        directories: [String]? = nil,
        commands: [String]? = nil,
        ownedPaths: [String] = [],
        childProcesses: [Int32] = []
    ) -> AgentExtensionVerdict {
        let verdict = AgentExtensionValidator.validate(manifest)
        guard let accepted = verdict.manifest else { return verdict }

        let declared = Set(accepted.provides.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let grantedCapabilities = capabilities.map { $0.intersection(declared) } ?? declared
        let declaredDirectories = accepted.permission?.readableDirectories ?? []
        let declaredCommands = accepted.permission?.allowedCommands ?? []

        let grantedDirectories = directories.map { requested in
            requested.filter { declaredDirectories.contains($0) }
        } ?? declaredDirectories
        let grantedCommands = commands.map { requested in
            requested.filter { declaredCommands.contains($0) }
        } ?? declaredCommands

        grants[accepted.id] = AgentExtensionGrant(
            manifest: accepted,
            capabilities: grantedCapabilities,
            directories: grantedDirectories,
            commands: grantedCommands,
            ownedPaths: ownedPaths,
            childProcesses: childProcesses
        )
        liveProcesses[accepted.id] = Set(childProcesses)
        uninstalled.removeValue(forKey: accepted.id)
        return .installable(accepted)
    }

    // MARK: 调（② 未授权的能力不可调用）

    /// 能否调用这个插件在这个槽位提供的某个能力。
    public func call(slot: AgentExtensionSlot, capability: String, pluginID: String) -> AgentExtensionAccess {
        guard let grant = grants[pluginID] else { return .denied(.notInstalled) }
        guard grant.manifest.slot.trimmingCharacters(in: .whitespacesAndNewlines) == slot.rawValue else {
            return .denied(.slotMismatch)
        }
        let name = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .denied(.emptyRequest) }
        guard grant.capabilities.contains(name) else { return .denied(.capabilityNotGranted) }
        return .allowed
    }

    /// 能否读这个路径：先看清单声明（没声明 = 越界），再看这次安装有没有授权。
    public func read(path: String, pluginID: String) -> AgentExtensionAccess {
        guard let grant = grants[pluginID] else { return .denied(.notInstalled) }
        let candidate = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return .denied(.emptyRequest) }
        let declared = grant.manifest.permission?.readableDirectories ?? []
        guard declared.contains(where: { AgentExtensionPath.contains(root: $0, candidate: candidate) }) else {
            return .denied(.directoryNotDeclared)
        }
        guard grant.directories.contains(where: {
            AgentExtensionPath.contains(root: $0, candidate: candidate)
        }) else {
            return .denied(.directoryNotGranted)
        }
        return .allowed
    }

    /// 能否跑这条命令：声明里必须有一条是它的程序名（或其前缀），且这次安装授权了那条。
    public func run(command: String, pluginID: String) -> AgentExtensionAccess {
        guard let grant = grants[pluginID] else { return .denied(.notInstalled) }
        let candidate = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return .denied(.emptyRequest) }
        let declared = grant.manifest.permission?.allowedCommands ?? []
        guard declared.contains(where: { AgentExtensionCommand.matches(command: candidate, declared: $0) }) else {
            return .denied(.commandNotDeclared)
        }
        guard grant.commands.contains(where: { AgentExtensionCommand.matches(command: candidate, declared: $0) }) else {
            return .denied(.commandNotGranted)
        }
        return .allowed
    }

    // MARK: 卸（③ 卸载后无残留进程与配置文件）

    /// 卸载：**只删它自己声明拥有的那些路径**（`ownedPaths`），并把子进程交回去停。
    ///
    /// 「无残留」由 `residue(pluginID:)` 量：盘上还剩下的自有路径 + 还登记着的进程 + 还挂着的授权。
    public mutating func uninstall(pluginID: String) -> AgentExtensionUninstallReceipt {
        guard let grant = grants.removeValue(forKey: pluginID) else {
            return AgentExtensionUninstallReceipt(
                pluginID: pluginID,
                wasInstalled: false,
                removedPaths: [],
                processesToStop: [],
                residue: residue(pluginID: pluginID)
            )
        }
        var removed: [String] = []
        for path in grant.ownedPaths {
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
            if !FileManager.default.fileExists(atPath: path) { removed.append(path) }
        }
        let processes = Array(liveProcesses[pluginID] ?? []).sorted()
        uninstalled[pluginID] = Retired(paths: grant.ownedPaths, processes: processes)
        return AgentExtensionUninstallReceipt(
            pluginID: pluginID,
            wasInstalled: true,
            removedPaths: removed,
            processesToStop: processes,
            residue: residue(pluginID: pluginID)
        )
    }

    /// 残留读数。装着的按授权台账算，卸过的按卸那一刻记下的自有面算。
    public func residue(pluginID: String) -> AgentExtensionResidue {
        let owned = grants[pluginID]?.ownedPaths ?? uninstalled[pluginID]?.paths ?? []
        let stillOnDisk = owned.filter { FileManager.default.fileExists(atPath: $0) }
        let processes = Array(liveProcesses[pluginID] ?? []).sorted()
        return AgentExtensionResidue(
            paths: stillOnDisk,
            processes: processes,
            grantRemains: grants[pluginID] != nil
        )
    }

    /// 宿主确实把子进程停掉了之后调它 —— 残留读数才会真的归零（不是自动假设）。
    public mutating func markProcessTerminated(pluginID: String, processID: Int32) {
        liveProcesses[pluginID]?.remove(processID)
    }
}

// MARK: - 路径与命令的匹配规则（判据钉的就是这两处）

public enum AgentExtensionPath {
    /// 目录包含判断：**按路径分量**比，不做字符串前缀。
    ///
    /// `/a/b` 不许放行 `/a/bc/x`（字符串前缀会放行，这是最容易写错的一处）；
    /// `..` 先标准化再比（`/a/b/../etc` 标准化成 `/a/etc` ⇒ 落在根外，拒）。
    public static func contains(root: String, candidate: String) -> Bool {
        let rootComponents = components(of: root)
        let candidateComponents = components(of: candidate)
        guard !rootComponents.isEmpty, !candidateComponents.isEmpty else { return false }
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func components(of path: String) -> [Substring] {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return standardized.split(separator: "/", omittingEmptySubsequences: true)
    }
}

public enum AgentExtensionCommand {
    /// 命令匹配：**整串相等**，或「声明串 + 空白」开头（同一条声明后面多几个参数）。
    ///
    /// 因此声明的粒度由写的人决定：写 `ls` 就是放行整个 `ls`（含 `ls -la`），
    /// 写 `git status` 只放行 `git status --short` 这一族，`git push` 另需一条。
    /// 边界（判据钉住）：声明了 `ls` **不许**放行 `lsblk`
    /// —— 后者是另一个程序，纯字符串前缀会把它放过去。
    public static func matches(command: String, declared: String) -> Bool {
        let candidate = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = declared.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !allowed.isEmpty else { return false }
        if candidate == allowed { return true }
        return candidate.hasPrefix(allowed + " ")
    }
}

// MARK: - 策略钩子（⑤ 只能收紧、不能放宽；fail-closed；不得绕过审批与审计）

/// 判定的三档严重度。**顺序即语义**：合并只许往严重的一侧走。
public enum AgentPolicyLevel: Int, Comparable, Codable, Equatable, Sendable, CaseIterable {
    case allow = 0
    case requiresApproval = 1
    case deny = 2

    public static func < (lhs: AgentPolicyLevel, rhs: AgentPolicyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 一个钩子的判定结果。`failed` = 钩子自己报错 / 超时（**不是**「它放行了」）。
public struct AgentPolicyHookResult: Equatable, Sendable {
    /// 谁判的（插件 id + 钩子种类），留痕要用
    public let hookID: String
    /// 它要收紧到哪一档
    public let level: AgentPolicyLevel
    /// 钩子自己挂了（崩 / 超时 / 返回解析不了）
    public let failed: Bool

    public init(hookID: String, level: AgentPolicyLevel = .allow, failed: Bool = false) {
        self.hookID = hookID
        self.level = level
        self.failed = failed
    }
}

/// 一条留痕（审计面）：**每个被求值的钩子都有一条**，失败的也在里面。
public struct AgentPolicyTrace: Equatable, Sendable {
    public let hookID: String
    public let level: AgentPolicyLevel
    public let failed: Bool
    /// 这次求值有没有改变基线判定（给「钩子做了什么」留证据）
    public let tightened: Bool
}

/// 合并结果。
///
/// 两个「不许」靠类型保证，而不是靠自觉：
/// - **不许放宽**：`decision` 只由 `AgentPolicyCombiner` 产出，且合并只会升档；
/// - **不许绕过审计**：求值过的钩子一定在 `traces` 里，没有「给个结论、不给留痕」的构造路径
///   （`init` 是 `fileprivate`）。
public struct AgentPolicyVerdict: Equatable, Sendable {
    public let decision: AgentPolicyLevel
    public let traces: [AgentPolicyTrace]

    fileprivate init(decision: AgentPolicyLevel, traces: [AgentPolicyTrace]) {
        self.decision = decision
        self.traces = traces
    }
}

public enum AgentPolicyCombiner {
    /// 基线判定 + 各路钩子 ⇒ 最终判定。
    ///
    /// 三条规矩（判据逐条钉）：
    /// ① 只能升档：`decision = max(base, 各钩子)`；钩子说 `allow` 也**抬不动** `base = deny`；
    ///    所以「钩子替人放行」在类型上不成立（审批那档也降不下去）。
    /// ② fail-closed：任何一个钩子 `failed` ⇒ 直接 `deny`（不是忽略它、用别路的结果）。
    /// ③ 留痕齐全：`traces` 与传入的钩子一一对应，失败的也有一条。
    public static func evaluate(base: AgentPolicyLevel, hooks: [AgentPolicyHookResult]) -> AgentPolicyVerdict {
        var decision = base
        var traces: [AgentPolicyTrace] = []
        var anyFailed = false

        for hook in hooks {
            if hook.failed {
                anyFailed = true
                traces.append(AgentPolicyTrace(hookID: hook.hookID, level: .deny, failed: true, tightened: base < .deny))
                continue
            }
            let raised = hook.level > decision ? hook.level : decision
            traces.append(
                AgentPolicyTrace(
                    hookID: hook.hookID,
                    level: hook.level,
                    failed: false,
                    tightened: raised > decision
                )
            )
            decision = raised
        }

        if anyFailed { decision = .deny }
        return AgentPolicyVerdict(decision: decision, traces: traces)
    }
}
