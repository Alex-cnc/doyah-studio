import Foundation

/// 插件装卸面板的**投影**（`FR-AGT-LINK-EXT-003` 的界面那一半）。
///
/// 为什么这些值住 Core：面板要显示的东西（装了哪些、每个能读哪些目录、能跑哪些命令、
/// 有几条只能在收紧一侧生效的钩子、卸完还剩下什么）全都是**判定结果**，不是排版。
/// 摆在界面里就得另写一遍「什么算已装」—— 那正是两套口径开始漂移的地方。
///
/// 这里只产出**中性数据**（标识符 / 路径 / 命令名 / 计数 / ASCII 机器码），
/// 一句人话都不在这里拼：文案归界面语言表，Core 侧不留中文字面量（棘轮口径）。
public struct AgentExtensionPanelRow: Equatable, Sendable, Identifiable {

    /// 插件 id（清单里那一个，也是台账的键）。
    public let id: String
    /// 槽位原样字符串（`tool` / `memory` …；写了第七类在装的时候就被拒了，
    /// 能走到这一行的都是封闭词表内的值）。
    public let slot: String
    /// 这次装**真授权**的能力名（已与清单声明取过交集，并去掉空白与空项）。
    public let provides: [String]
    /// 这次装真放行的可读目录。
    public let readableDirectories: [String]
    /// 这次装真放行的可跑命令。
    public let allowedCommands: [String]
    /// 清单里声明的策略钩子条数（钩子只能把判定往严重一侧推，条数为 0 也别画成「没有权限」）。
    public let hookCount: Int
    /// 卸载时要清掉的自有路径条数（面板据此说清「卸了会动哪些东西」）。
    public let ownedPathCount: Int

    public init(
        id: String,
        slot: String,
        provides: [String],
        readableDirectories: [String],
        allowedCommands: [String],
        hookCount: Int,
        ownedPathCount: Int
    ) {
        self.id = id
        self.slot = slot
        self.provides = provides
        self.readableDirectories = readableDirectories
        self.allowedCommands = allowedCommands
        self.hookCount = hookCount
        self.ownedPathCount = ownedPathCount
    }
}

/// 目录里没装上的一份清单：**哪个文件 + 为什么**（ASCII 机器码，人话由界面按码翻）。
public struct AgentExtensionPanelProblem: Equatable, Sendable {

    /// 相对插件目录的清单路径（`ext.a/extension.json` 这种形状，便于人直接去看）。
    public let file: String
    /// 拒收原因的机器码（`AgentExtensionRejection.rawValue`，可 grep、可断言）。
    public let code: String

    public init(file: String, code: String) {
        self.file = file
        self.code = code
    }
}

/// 卸完之后「还剩什么」的读数。**不是结论** —— 面板据此说「无残留」或逐条点名。
public struct AgentExtensionPanelResidue: Equatable, Sendable {

    public let paths: [String]
    public let processes: [Int32]
    public let grantRemains: Bool

    public var isClean: Bool { paths.isEmpty && processes.isEmpty && !grantRemains }

    public init(paths: [String], processes: [Int32], grantRemains: Bool) {
        self.paths = paths
        self.processes = processes
        self.grantRemains = grantRemains
    }
}

/// 面板要的全部读数：已装清单（按 id 排好）+ 没装上的逐条原因。
public struct AgentExtensionPanel: Equatable, Sendable {

    public let rows: [AgentExtensionPanelRow]
    public let problems: [AgentExtensionPanelProblem]

    public init(rows: [AgentExtensionPanelRow], problems: [AgentExtensionPanelProblem]) {
        self.rows = rows
        self.problems = problems
    }

    /// 从一次目录装配的结果投影（宿主开跑前那一步产出的就是它）。
    public init(load: AgentExtensionCatalogLoad) {
        self.init(desk: load.desk, problems: load.problems)
    }

    public init(desk: AgentExtensionDesk, problems: [AgentExtensionCatalogProblem] = []) {
        self.rows = desk.installedIDs.compactMap { desk.grant(for: $0) }.map(Self.row(for:))
        self.problems = problems.map { AgentExtensionPanelProblem(file: $0.file, code: $0.rejection.rawValue) }
    }

    /// 一份授权 → 一行读数。
    ///
    /// 三处**归一**都在这儿做，界面不再各自处理：
    /// ① 名字 / 路径 / 命令一律去首尾空白；② 空串与重复项丢弃（面板上不该出现空行与同一行两遍）；
    /// ③ 保持清单里的原始顺序（不排序 —— 谁写的清单按谁的顺序看，排序会让人对不上自己那份文件）。
    public static func row(for grant: AgentExtensionGrant) -> AgentExtensionPanelRow {
        let manifest = grant.manifest
        // 能力集在台账里是 `Set`（无序），所以**顺序取自清单一侧**再与授权集求交 ——
        // 直接拿集合排会让人对不上自己写的那份 extension.json。
        let grantedCapabilities = normalized(manifest.provides).filter { grant.capabilities.contains($0) }
        return AgentExtensionPanelRow(
            id: manifest.id,
            slot: manifest.slot.trimmingCharacters(in: .whitespacesAndNewlines),
            provides: grantedCapabilities,
            readableDirectories: normalized(grant.directories),
            allowedCommands: normalized(grant.commands),
            hookCount: manifest.hooks.count,
            ownedPathCount: grant.ownedPaths.count
        )
    }

    /// 卸载收据 → 残留读数（面板只说「还剩什么」，不替人下「干净了」这个结论以外的话）。
    public static func residue(of receipt: AgentExtensionUninstallReceipt) -> AgentExtensionPanelResidue {
        AgentExtensionPanelResidue(paths: receipt.residue.paths,
                                   processes: receipt.residue.processes,
                                   grantRemains: receipt.residue.grantRemains)
    }

    /// 去空白 + 丢空项；**保持首次出现的顺序**，重复项只留一次。
    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}
