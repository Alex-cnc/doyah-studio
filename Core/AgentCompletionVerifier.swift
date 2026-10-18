import Foundation

/// **完成判据自检**（`FR-AI-31` ②）—— 回边四件里 Verifier 那一片。
///
/// 要害一句话：**模型说「做完了」不算完成**。要算完成，得拿出**本次运行真跑过**的证据，
/// 而且这份证据能**机械复核**（此刻盘上还成立）。拿不出 / 对不上 / 说得含糊 ⇒ 如实说
/// 「未验证」—— SRS 那条验收要点的负例正是「把模型说做完了当完成」。
///
/// 三件事分开记，不混成一坨：
/// · `AgentCompletionEvidence` —— **本次运行**里工具层真的产出的东西（写盘 / 改文件 / 命令退出码 / 读过）；
/// · `AgentCompletionClaim` —— 模型答复里**引用**的那一条（`EVIDENCE:` 行，见 `AgentSystemPrompt` 第 5 条规矩）；
/// · `AgentCompletionReport` —— 复核结论（`verified` / `unverified:<码>` / `notClaimed`）。
///
/// **复核为什么要再读一次盘**：工具层回一句「写了 100 字节」也只是一句话；只有「此刻盘上
/// 仍是那份内容」才叫复核。指纹口径与 `AgentWriteTargetState.digest` 逐字一致
/// （`content:<FNV-1a>`，同一份正文 ⇒ 同一串），所以审批基线与完成判据读的是**同一个串**，
/// 不会出现「审批说没变、完成判据说变了」这种两套标准。
public struct AgentCompletionEvidence: Equatable, Sendable {

    /// 证据的来历（**工具层真的做了什么**，不是模型说了什么）。
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// 整篇写盘（`write_file`）。
        case write
        /// 定点改（`edit_file`）。
        case edit
        /// 真跑过一条命令（`run_command`）—— 证据是**退出码**。
        case command
        /// 读过（`read_file`）—— 只能证明「我此刻看到的是这份内容」，不能单独当「改动完成」。
        case read
    }

    public var kind: Kind
    /// 产出它的工具名（过程面要能指着说是谁干的）。
    public var toolName: String
    /// 工作区相对路径（命令类为空串 —— 命令没有「目标文件」）。
    public var path: String
    /// 写 / 改 / 读之后**应有**的内容指纹（`content:<hash>`）；命令类为空串。
    public var digest: String
    /// 退出码（只有命令类给）。
    public var exitCode: Int?
    /// 第几跳（0 起；与审计 / 调用链的跳号同一口径）。
    public var step: Int

    public init(kind: Kind, toolName: String, path: String = "", digest: String = "",
                exitCode: Int? = nil, step: Int) {
        self.kind = kind
        self.toolName = toolName
        self.path = path
        self.digest = digest
        self.exitCode = exitCode
        self.step = step
    }

    /// 内容 ⇒ 指纹（**唯一一处算法**：直接借写入基线那一处，别在两处算同一个串）。
    public static func digest(of text: String) -> String { "content:" + AgentFingerprint.hash(text) }
}

/// 模型答复里引用的一条证据（`EVIDENCE: <kind> <目标>` 那一行）。
public struct AgentCompletionClaim: Equatable, Sendable {
    public var kind: AgentCompletionEvidence.Kind
    /// 文件类 = 归一化后的相对路径；命令类 = `exit=<码>`。
    public var target: String
    public var exitCode: Int?
    /// 原文（复核失败时如实回引，不重写模型的话）。
    public var raw: String
}

/// 复核结论。
///
/// `reason` 是**机器码**（人话在界面语言表翻）：
/// · `noEvidence` —— 嘴上说完成，一行 `EVIDENCE:` 都没有（**负例**：自报即完成）；
/// · `claimNotInRun` —— 引用的那条**本次没发生过**（幻觉 / 记错了上一轮）；
/// · `diskDiffers` —— 引用的写**此刻盘上对不上**（被改过 / 被撤销 / 根本没落）；
/// · `unreadable` —— 目标此刻读不出来（被删 / 二进制 / 无权限）；
/// · `commandFailed` —— 引用的是「跑成功了」，可实际退出码不是这个；
/// · `badClaim` —— 那一行没法解析（复核不了，就不许算过）。
public struct AgentCompletionReport: Equatable, Sendable {

    public enum Status: String, Equatable, Sendable {
        case verified
        case unverified
        /// 模型没有声称完成（只是回答了一个问题）—— 这一档**不报错**，也不显示「已复核」。
        case notClaimed
    }

    public var status: Status
    public var reason: String
    public var detail: String
    public var citations: [AgentCompletionClaim]

    public init(status: Status, reason: String = "", detail: String = "",
                citations: [AgentCompletionClaim] = []) {
        self.status = status
        self.reason = reason
        self.detail = detail
        self.citations = citations
    }

    /// 过程面 / 界面读的那一格（机器码；`R-63` ③：不许静默）。
    public var code: String {
        switch status {
        case .verified: return "verified:\(citations.count)"
        case .notClaimed: return "notClaimed"
        case .unverified: return "unverified:\(reason)"
        }
    }

    public var isVerified: Bool { status == .verified }
}

/// `EVIDENCE:` 行的解析（**纯函数**，判据直接打这里）。
public enum AgentCompletionClaimParser {

    /// 引用前缀。用 ASCII 大写词而不是中文，是为了不被「正文里恰好说了句完成」误触发。
    public static let marker = "EVIDENCE:"

    /// 「宣称完成」的判据：**只在没有任何引用行时**才用它区分
    /// 「答了个问题（`notClaimed`）」与「说做完了却拿不出证据（`unverified:noEvidence`）」。
    public static let assertionMarkers: [String] = [
        "已完成", "任务完成", "全部完成", "都已完成", "做完了", "改好了", "改完了",
        "Done", "done", "DONE", "finished", "Completed", "completed",
    ]

    /// 一行里的引用（认不出 ⇒ 返回一条 `badClaim` 的占位，交给复核判红 —— 不静默丢）。
    static func parse(line: String) -> AgentCompletionClaim? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // 容忍列表符号与加粗（模型很爱这么写）
        for prefix in ["- ", "* ", "• ", "**", "-", "*"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard text.uppercased().hasPrefix(marker) else { return nil }
        let body = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else {
            return AgentCompletionClaim(kind: .read, target: "", exitCode: nil, raw: raw)
        }
        let kindWord = head.lowercased()
        var kind: AgentCompletionEvidence.Kind?
        switch kindWord {
        case "write", "wrote": kind = .write
        case "edit", "edited": kind = .edit
        case "read": kind = .read
        case "command", "run", "ran": kind = .command
        default:
            // **工具名也认**，但工具名不在本文件写死（源树判据：工具名只许出现在注册表一处）
            // ⇒ 到注册表按能力反查。
            if let definition = AgentToolRegistry.standard.definition(named: head) {
                kind = Self.kind(for: definition.capability)
            } else {
                kind = nil
            }
        }
        guard let kind else {
            return AgentCompletionClaim(kind: .read, target: "", exitCode: nil, raw: raw)
        }
        let rest = parts.dropFirst().joined(separator: " ")
        if kind == .command {
            // **必须带退出码** —— 只说「跑过了」等于什么都没说，复核不了（SRS：可机械复核）。
            guard let match = rest.range(of: #"exit\s*=\s*(-?\d+)"#, options: .regularExpression),
                  let code = Int((rest[match].split(separator: "=").last.map(String.init) ?? "")
                                    .trimmingCharacters(in: .whitespaces)) else {
                return AgentCompletionClaim(kind: kind, target: "", exitCode: nil, raw: raw)
            }
            return AgentCompletionClaim(kind: kind, target: "exit=\(code)", exitCode: code, raw: raw)
        }
        var path = rest
        for wrapper in ["`", "\"", "'"] where path.hasPrefix(wrapper) && path.hasSuffix(wrapper) {
            path = String(path.dropFirst().dropLast())
        }
        path = normalise(path)
        return AgentCompletionClaim(kind: kind, target: path, exitCode: nil, raw: raw)
    }

    /// 文本里**所有**引用行（按出现顺序；非引用行忽略）。
    public static func claims(in text: String) -> [AgentCompletionClaim] {
        text.components(separatedBy: .newlines).compactMap { parse(line: $0) }
    }

    /// 文本里有没有「宣称完成」的措辞。
    public static func assertsCompletion(_ text: String) -> Bool {
        assertionMarkers.contains { text.contains($0) }
    }

    /// 能力 ⇒ 证据种类（**唯一一处**映射；工具名不在这里出现）。
    static func kind(for capability: AgentToolCapability) -> AgentCompletionEvidence.Kind? {
        switch capability {
        case .writeFile: return .write
        case .editFile: return .edit
        case .readFile: return .read
        case .runCommand: return .command
        default: return nil
        }
    }

    /// 路径归一化：去掉 `./`、`/` 前缀与反引号，`..` 在沙箱里已被拒（这里只求同一份文件同一个串）。
    static func normalise(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") { value = String(value.dropFirst(2)) }
        while value.hasPrefix("/") { value = String(value.dropFirst()) }
        return value
    }
}

/// 完成判据的**复核器**（`FR-AI-31` ②）。
///
/// 只做一件事：把「模型引用的证据」与「本次真跑过的证据」对齐，并**再读一次盘**确认它此刻还成立。
/// 读盘是注入的（判据给假读盘，不碰真文件系统）；不给就按工作区真的读。
public struct AgentCompletionVerifier: Sendable {

    /// 工作区根（文件类证据的相对路径都相对它）。
    public var workspaceRoot: URL
    /// 读盘：路径 ⇒ 正文（读不出来给 `nil` —— 复核不了就说读不出来，不猜）。
    public var reader: @Sendable (URL) -> String?

    public init(workspaceRoot: URL,
                reader: (@Sendable (URL) -> String?)? = nil) {
        self.workspaceRoot = workspaceRoot
        self.reader = reader ?? { url in try? String(contentsOf: url, encoding: .utf8) }
    }

    /// - Parameters:
    ///   - text: 模型的最终答复（含 `EVIDENCE:` 行）。
    ///   - evidence: **本次运行**的工具证据（`AgentLoop` 边跑边攒；别处来的不算）。
    public func verify(text: String, evidence: [AgentCompletionEvidence]) -> AgentCompletionReport {
        let claims = AgentCompletionClaimParser.claims(in: text)
        guard !claims.isEmpty else {
            // 一条引用都没有：说完成了 ⇒ **未验证**（负例）；只是回答问题 ⇒ `notClaimed`（不冤枉）。
            return AgentCompletionClaimParser.assertsCompletion(text)
                ? AgentCompletionReport(status: .unverified, reason: "noEvidence",
                                        detail: "none of the claims cite a tool result of this run")
                : AgentCompletionReport(status: .notClaimed)
        }
        for claim in claims {
            guard let matched = latest(claim, in: evidence) else {
                return AgentCompletionReport(status: .unverified, reason: "claimNotInRun",
                                             detail: claim.raw, citations: claims)
            }
            switch claim.kind {
            case .command:
                guard matched.exitCode == claim.exitCode else {
                    return AgentCompletionReport(status: .unverified, reason: "commandFailed",
                                                 detail: "\(claim.raw) · actual:\(matched.exitCode.map(String.init) ?? "nil")",
                                                 citations: claims)
                }
            case .write, .edit, .read:
                let url = workspaceRoot.appendingPathComponent(claim.target)
                guard let onDisk = reader(url) else {
                    return AgentCompletionReport(status: .unverified, reason: "unreadable",
                                                 detail: claim.raw, citations: claims)
                }
                guard AgentCompletionEvidence.digest(of: onDisk) == matched.digest else {
                    return AgentCompletionReport(status: .unverified, reason: "diskDiffers",
                                                 detail: claim.raw, citations: claims)
                }
            }
        }
        return AgentCompletionReport(status: .verified, citations: claims)
    }

    /// 引用与证据对齐：同类里**最近的那一条**（同一次运行里同一个文件写两回，引用指最后一次）。
    /// 解析不出目标（`badClaim`）⇒ `nil` ⇒ 判红（复核不了的不许当通过）。
    private func latest(_ claim: AgentCompletionClaim, in evidence: [AgentCompletionEvidence])
    -> AgentCompletionEvidence? {
        guard !claim.target.isEmpty else { return nil }
        let sameKind = evidence.filter { $0.kind == claim.kind }
        switch claim.kind {
        case .command:
            return sameKind.last
        case .write, .edit, .read:
            return sameKind.last(where: { AgentCompletionClaimParser.normalise($0.path) == claim.target })
        }
    }
}
