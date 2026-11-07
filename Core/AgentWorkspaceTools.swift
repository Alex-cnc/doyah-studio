import Foundation

/// 工具被拒的原因码（`FR-AI-20` ②：「拒绝并**报明原因**」）。
///
/// 刻意用**机器码 + 细节串**，不写死人话 —— 人话由带 `language:` 的渲染入口给
/// （与 `AgentGuardFinding` / 本地化纪律同一条口径：Core 不写死人话）。
public enum AgentToolRefusal: String, Codable, Equatable, Sendable {
    case outsideWorkspace
    case notFound
    case notAFile
    case notADirectory
    case binaryFile
    case unreadable
    case emptyQuery
    case unregistered
    /// 被策略拒（只读模式下的写语句等 —— `FR-AI-20` ⑤ / `FR-AI-23` ⑥）。
    case deniedByPolicy
    /// 参数取不出来（不是对象 / 值类型不对）—— 如实拒，**不猜**。
    case badArguments
    /// 这一侧没接上实现（宿主没注入工具）—— 如实说，不假装能做。
    case unavailable
    /// 非白名单命令 / 控制字符（`FR-AI-20` ④）。
    case commandNotAllowed
    /// 没批准就想落盘 / 执行（`FR-AI-20` ③④⑤）。
    case approvalRequired
    /// **伤害性动作被刹停**（`FR-AI-34`）：不进审批队列、不执行，**立刻停并告诉你**。
    /// 与 `deniedByPolicy` 分开：那条是"此刻策略不许"，这条是"这事本身有害"。
    case harmStopped
    /// **子代理不许再派子代理**（深度只许 1 层）：否则一路派下去没人收口。
    case subagentNesting
    /// **同一文件正有另一次写入在进行**（`FR-AI-31` ①）：不排队、不静默覆盖 —— 如实说，让人 / 模型重试。
    /// 与 `staleTarget` 分开：这条是"此刻有人正握着这个文件"，那条是"我拿到的那份基线已经过期"。
    case writeConflict
    /// **批准之后目标被改过**（`FR-AI-31` ① 的负例「静默覆盖」）：不拿旧审批盖新内容，如实说重新来过。
    case staleTarget
    /// **这一侧没配 MCP server / 这个工具没有归属 server**（`FR-AI-21` ⑤：如实说「未配置」，
    /// 不许假回退、不许静默消失）。与 `unavailable` 分开：那条是"宿主没接实现"，这条是"用户还没配"。
    case mcpNotConfigured
    /// **配了但连不上**（`FR-AI-21` ⑤）：`detail` 带机器码与原因（`spawnFailed/...` / `timeout/...`）。
    case mcpUnreachable
    /// **超出这一跳的工具预算**（2026-11-06）：不执行、如实说，并告诉模型「先给结论」。
    /// 与 `unavailable` 分开：那条是"这侧没有"，这条是"这跳的名额用完了，下一跳还可以做"。
    case hopBudget
}

/// 一次读的**窗口**（2026-11-06 起 `read_file` 按行开窗）：给了就说明「这次只给了第几行到第几行」。
///
/// 为什么单拎一个结构而不是把提示句塞进 `text`：`text` 是**文件原文**（会被当成资料包进不可信边界、
/// 会被判据按字节比对）；「这次给了哪一段」是**我们的事实**，必须能在边界之外单独说、单独断言。
public struct AgentToolFileWindow: Equatable, Sendable {
    /// 起始行（0 起）。
    public var startLine: Int
    /// 结束行（**不含**，0 起）。
    public var endLine: Int
    /// 文件总行数。
    public var totalLines: Int

    public init(startLine: Int, endLine: Int, totalLines: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.totalLines = totalLines
    }

    /// 这一段之后从哪一行接着读（`nil` = 已经到文件尾）。
    public var nextOffset: Int? { endLine < totalLines ? endLine : nil }
}

/// 读文件的输出（结构化 ⇒ 截断**可被断言**，不必靠人话里那句提示）。
public struct AgentToolFileOutput: Equatable, Sendable {
    public var path: String
    public var text: String
    public var truncated: Bool
    public var totalBytes: Int
    /// 按行开窗时的窗口；`nil` = 整篇都在（小文件 / 旧路径）。
    public var window: AgentToolFileWindow?

    public init(path: String, text: String, truncated: Bool, totalBytes: Int,
                window: AgentToolFileWindow? = nil) {
        self.path = path
        self.text = text
        self.truncated = truncated
        self.totalBytes = totalBytes
        self.window = window
    }
}

/// 列目录的输出。
public struct AgentToolDirectoryOutput: Equatable, Sendable {
    public var path: String
    /// 目录项（目录带结尾 `/`），已排序。
    public var entries: [String]
    public var truncated: Bool
}

/// 搜索的输出：**逐词一组**命中（`FR-AI-20` ① 要求文件名与内容两类都能命中）。
///
/// 2026-11-07（真机：一轮 26 步 / 149.6 秒，`search` 被近义词反复调用了十几次）起按**词**分组：
/// 一次调用可以搜多个词，每组各自报「文件名命中 / 内容命中」，并标出这一组是**现搜的**还是
/// **缓存命中**的（`cached` / `partial`）。顶层的 `fileNames` / `contentHits` 是各组合并后的
/// 全集（旧渲染与旧判据照旧读它，不因改形状而失明）。
public struct AgentToolSearchOutput: Equatable, Sendable {

    /// 一个词的命中。
    public struct Group: Equatable, Sendable {
        /// 模型这次给的词（原文，不改写）。
        public var query: String
        public var fileNames: [String]
        /// `相对路径:行号: 片段`
        public var contentHits: [String]
        /// 这一组来自缓存（没扫盘）。
        public var cached: Bool
        /// 缓存来自**别的词**（包含关系）⇒ 只覆盖一部分，要全量得单独搜这个词。
        public var partial: Bool
        /// 缓存里那一次搜索的原词（`partial` 时界面/回灌要说清来源）。
        public var source: String?
        public var truncated: Bool
        /// 这一组花了多少毫秒（缓存命中 ⇒ 0；同一次扫盘的几个词共享同一个读数）。
        public var elapsedMillis: Int

        public init(query: String, fileNames: [String] = [], contentHits: [String] = [],
                    cached: Bool = false, partial: Bool = false, source: String? = nil,
                    truncated: Bool = false, elapsedMillis: Int = 0) {
            self.query = query
            self.fileNames = fileNames
            self.contentHits = contentHits
            self.cached = cached
            self.partial = partial
            self.source = source
            self.truncated = truncated
            self.elapsedMillis = elapsedMillis
        }
    }

    public var fileNames: [String]
    /// `相对路径:行号: 片段`
    public var contentHits: [String]
    public var truncated: Bool
    /// 逐词命中（顺序 = 模型给的词的顺序）。
    public var groups: [Group]
    /// 本次实际搜过的词（含缓存命中的）。
    public var queries: [String]
    /// 整次调用花了多少毫秒（探针 / 回灌要能读出来）。
    public var elapsedMillis: Int

    /// 这一整次是不是全部来自缓存。
    public var fromCache: Bool { !groups.isEmpty && groups.allSatisfy(\.cached) }

    public init(fileNames: [String] = [], contentHits: [String] = [], truncated: Bool = false,
                groups: [Group] = [], queries: [String] = [], elapsedMillis: Int = 0) {
        self.fileNames = fileNames
        self.contentHits = contentHits
        self.truncated = truncated
        self.groups = groups
        self.queries = queries
        self.elapsedMillis = elapsedMillis
    }
}

/// 要审批的动作（写 / 执行）。指纹按**次**算：工具名 + 参数 ⇒ 换参数要重新批。
public struct AgentApprovalRequest: Equatable, Sendable {
    public var toolName: String
    public var fingerprint: String
    /// 要写的差异预览 / 要跑的命令原文（给人看的**事实**，不是人话判词）。
    public var payload: String
    /// **出单那一刻**目标的基线串（`FR-AI-31` ①）：临写前复核用 —— 对不上就说明这份审批已经过期。
    /// 执行类动作没有目标文件 ⇒ 空串（不许拿"没有基线"当"基线成立"）。
    public var baseDigest: String
    /// 授权作用域（§3.36 ②）：由**出单的这一处**给 —— 只有它知道目标路径 / 首词 / 参数原文。
    ///
    /// 空串 = 这一处没给作用域；授权一侧会退回「参数指纹」（同一串参数才算同一档），
    /// **绝不退回「只认工具名」**（那等于一档放行全盘）。
    public var scope: String
    /// 危险面（§3.36 ③）：不可逆的那几档只保留「仅这一次」。
    public var hazard: AgentApprovalHazard

    public init(toolName: String, fingerprint: String, payload: String, baseDigest: String = "",
                scope: String = "", hazard: AgentApprovalHazard = .ordinary) {
        self.toolName = toolName
        self.fingerprint = fingerprint
        self.payload = payload
        self.baseDigest = baseDigest
        self.scope = scope
        self.hazard = hazard
    }

    /// 授权的**作用域**：出单时给了就用它，没给就用参数指纹兜底（窄，不会吞掉别的目标）。
    public var approvalScope: AgentApprovalScope {
        let value = scope.isEmpty ? AgentApprovalScope.argumentDigest(fingerprint) : scope
        return AgentApprovalScope(tool: toolName, value: value)
    }
}

/// 一次工具调用的结果。
public enum AgentToolOutcome: Equatable, Sendable {
    case file(AgentToolFileOutput)
    case directory(AgentToolDirectoryOutput)
    case search(AgentToolSearchOutput)
    /// 只读语句直接跑出来的结果（`query_db`）。
    case rows(AgentToolRowsOutput)
    /// 真跑了一条白名单命令（`run_command`）。
    case command(AgentCommandResult)
    case wrote(AgentToolFileOutput)
    /// 用户自配 MCP server 上的工具跑完（`FR-AI-21`）：远端正文**原样** + 是不是远端报的错。
    case mcp(MCPClientToolCall)
    /// **联网**（`FR-AGT-TOOL-INGEST-001/004`）：一次搜索或一次抓取的结果（详设 §3.27）。
    case web(AgentWebOutput)
    case refused(AgentToolRefusal, detail: String)
    case needsApproval(AgentApprovalRequest)
}

/// 联网工具的结果：搜索给命中列表，抓取给正文（两者共用一只结构，`kind` 分开）。
public struct AgentWebOutput: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// `web_search`：只有命中（标题 / URL / 摘要），**没有正文**
        case search
        /// `fetch_url`：只有正文（HTML 已转纯文本）
        case page
    }

    public var kind: Kind
    public var query: String
    public var hits: [AgentWebHit]
    public var text: String
    public var finalURL: String
    public var totalBytes: Int
    public var truncated: Bool

    public init(kind: Kind,
                query: String = "",
                hits: [AgentWebHit] = [],
                text: String = "",
                finalURL: String = "",
                totalBytes: Int = 0,
                truncated: Bool = false) {
        self.kind = kind
        self.query = query
        self.hits = hits
        self.text = text
        self.finalURL = finalURL
        self.totalBytes = totalBytes
        self.truncated = truncated
    }
}

/// `query_db` 的只读结果（行数据**不进**这个结构 —— 它只带列名与行数，`NFR-AI-01` 口径）。
public struct AgentToolRowsOutput: Equatable, Sendable {
    public var columns: [String]
    public var rowCount: Int
    public var statementKind: String
    /// 失败时的可读原因（脱敏由执行器一侧保证）。
    public var errorMessage: String?

    public init(columns: [String], rowCount: Int, statementKind: String, errorMessage: String? = nil) {
        self.columns = columns
        self.rowCount = rowCount
        self.statementKind = statementKind
        self.errorMessage = errorMessage
    }
}

/// 工作区路径沙箱（`FR-AI-20` ②）：**唯一**一处判「这个路径在不在工作区里」。
///
/// 两条写法都要挡（判据点名）：**绝对路径**落在工作区外、以及用 `..` 爬出去。
/// 归一化后仍落在工作区内的 `..`（如 `a/../b`）是**合法**的 —— 挡的是「出去」，不是 `..` 本身。
public enum AgentWorkspaceSandbox {

    public enum Resolution: Equatable, Sendable {
        case inside(URL)
        case outside(detail: String)
    }

    public static func resolve(_ raw: String, in root: URL) -> Resolution {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .outside(detail: "empty path") }

        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }
        let base = root.standardizedFileURL

        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        if candidate.path == base.path || candidate.path.hasPrefix(basePath) {
            return .inside(candidate)
        }
        return .outside(detail: candidate.path)
    }
}

/// 工作区内的工具实现（`FR-AI-20`；本片 = **只读三件**：`read_file` / `list_dir` / `search`）。
///
/// 检索**复用既有引擎**（`WorkspaceSearch`，契约 §3.33「一套引擎、两个入口」）——
/// 不为工具另写一套遍历，否则两套口径必然漂移。
public struct AgentWorkspaceTools: Sendable {

    public var root: URL
    /// 工具声明的出处（`FR-AI-19`：唯一出处）。默认取标准表；工具实现**不自己命名工具**，按等级来这里取。
    public var registry: AgentToolRegistry
    /// 一次读回的**字节**上限（超出即截断并**如实标记**，不静默）。
    ///
    /// 2026-11-06 由 262,144 收到 6,000：整篇进上下文是那一轮 19 分钟的 74% 来源
    /// （每跳都把历史正文重发一遍）。6KB ≈ 一屏代码，够模型判断下一步；
    /// 要后面几段就用 `offset` 续读 —— 续读只花一段的钱，重读整篇要花整篇的钱。
    /// 这个数还必须**小于**回灌段的单条上限（`AgentLoop.maxObservationCharacters` = 8,000），
    /// 否则截断提示（「下一段用 offset=…」）会被回灌那一层再截掉，模型就看不见续读的办法了。
    public var maxReadBytes: Int
    /// 一次读回的**行数**上限（与字节上限一起生效，谁先到算谁）。
    public var maxReadLines: Int
    /// 列目录的上限。
    public var maxDirectoryEntries: Int
    /// 停手记录（`FR-AI-34`）：给了就把每次刹停留痕；不给（单测）就不写文件。
    public var harmStopLog: AgentHarmStopLog?
    /// **同一轮里的搜索缓存**（2026-11-07）：同词再搜 / 近义词（包含关系）直接命中，毫秒级。
    /// 每轮一份（`makeLoop` 每次新造 `AgentWorkspaceTools`）；写 / 执行立即作废。
    /// 不给（`nil`）= 不缓存（探针的反例臂就靠它）。
    public var searchCache: AgentSearchCache?
    /// 「谁正在写哪个文件」的台账（`FR-AI-31` ①）。默认取**进程内共享**那一本 ——
    /// 每轮现造一个 `AgentWorkspaceTools` 也不会各拿一本账，否则并发写永远抓不到。
    public var writes: AgentWriteCoordinator
    /// **搜索执行器的定位入口**（2026-11-07）：默认「随包 `Contents/Resources/tools/rg`
    /// → PATH」，两处都没有就不加速、走 Swift 引擎。
    ///
    /// 为什么是个可注入的闭包而不是直接调 `AgentRipgrep.locate()`：反例判据要能把
    /// 「rg 被删 / 被改名 / 没有执行权」这一格真的翻出来（`Tests/AgentRipgrepSearchTests`），
    /// 而测试进程的 PATH 与 `Bundle.main` 都不是 App 的那一份。
    public var ripgrepLocator: @Sendable () -> String?

    public init(root: URL, registry: AgentToolRegistry = .standard,
                maxReadBytes: Int = 6_000, maxReadLines: Int = 160, maxDirectoryEntries: Int = 500,
                harmStopLog: AgentHarmStopLog? = nil,
                searchCache: AgentSearchCache? = AgentSearchCache(),
                writes: AgentWriteCoordinator = .shared,
                ripgrepLocator: @escaping @Sendable () -> String? = { AgentRipgrep.locate() }) {
        self.root = root
        self.registry = registry
        self.maxReadBytes = maxReadBytes
        self.maxReadLines = maxReadLines
        self.maxDirectoryEntries = maxDirectoryEntries
        self.harmStopLog = harmStopLog
        self.searchCache = searchCache
        self.writes = writes
        self.ripgrepLocator = ripgrepLocator
    }

    // MARK: - 越界授权（`§3.26`）

    /// 目标落在工作区外时的**唯一出路**：出一张单，写明越界目标，**批准之前一个字节都不动**。
    ///
    /// 指纹用**绝对路径**：同一个相对路径在不同工作区指向不同文件 —— 用相对路径会让
    /// 「在别处批过的那一次」在这边也算数（详设 §3.26「指纹」一格）。
    private func outsideApproval(tool: AgentToolDefinition, url: URL, payload: String) -> AgentToolOutcome {
        let absolute = url.standardizedFileURL.path
        let preview = "越界：\(absolute)（工作区：\(root.path)）\n" + payload
        return .needsApproval(AgentApprovalRequest(
            toolName: tool.name,
            fingerprint: AgentFingerprint.hash("\(tool.name)|\(absolute)|\(payload)"),
            payload: preview,
            baseDigest: AgentWriteTargetState.digest(at: url),
            // 作用域 = 目标绝对路径（同一个相对路径在不同工作区指向不同文件）；越界永不记授权。
            scope: AgentApprovalScope.normalizedPath(absolute),
            hazard: .outsideWorkspace))
    }

    /// 把一个可能越界的相对 / 绝对路径**绝对化**（不改写用户给的原值，只用于比较与出单）。
    private func absoluteURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed).standardizedFileURL }
        return root.appendingPathComponent(trimmed).standardizedFileURL
    }

    // MARK: - read_file

    /// 读文件（`FR-AI-20`；**按行开窗**，2026-11-06）。
    ///
    /// 由头：整篇进上下文会把一轮里 74% 的时间花在重发历史正文上；而**整篇截断**又让模型看不见后半段，
    /// 只能一遍遍重读同一个文件（真机：同一文件读了 22 次）。所以改成「**窗口 + 可续读**」：
    /// · 默认给前 `maxReadLines` 行（约一屏），超过 `maxReadBytes` 再按字节收口；
    /// · 被截断时**明说**：文件共几行、这次给了第几行到第几行、下一段用 `offset` 怎么读。
    ///   「怎么读下一段」这句必须在正文里 —— 模型看不见它就只能整篇重读。
    public func readFile(path: String,
                         offset: Int? = nil,
                         limit: Int? = nil,
                         fingerprint: String? = nil,
                         granted: Set<String> = []) -> AgentToolOutcome {
        let resolved = AgentWorkspaceSandbox.resolve(path, in: root)
        let url: URL
        switch resolved {
        case .inside(let inside):
            url = inside
        case .outside:
            // 越界**不直接拒**：没批过就出单（§3.26）；批过（指纹命中）才读。
            guard let tool = registry.definition(for: .readFile) else {
                return .refused(.unregistered, detail: AgentToolLevel.readOnly.rawValue)
            }
            let target = absoluteURL(for: path)
            guard let fingerprint, granted.contains(fingerprint) else {
                return outsideApproval(tool: tool, url: target, payload: path)
            }
            url = target
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .refused(.notFound, detail: url.lastPathComponent)
        }
        guard !isDirectory.boolValue else { return .refused(.notAFile, detail: url.lastPathComponent) }
        guard let data = try? Data(contentsOf: url) else {
            return .refused(.unreadable, detail: url.lastPathComponent)
        }

        // **二进制判据只能整段判**：按字节回退会把「恰好以多字节字符开头被切断」的垃圾也解出来，
        // 那等于把真二进制当文本塞给模型（判据当场抓过这个缺陷）。
        guard let whole = String(data: data, encoding: .utf8) else {
            return .refused(.binaryFile, detail: url.lastPathComponent)
        }

        let lines = whole.split(separator: "\n", omittingEmptySubsequences: false)
        let totalLines = max(1, lines.count)
        let startLine = min(max(0, offset ?? 0), totalLines - 1)
        let wanted = max(1, limit ?? maxReadLines)
        var endLine = min(totalLines, startLine + wanted)
        var text = lines[startLine..<endLine].joined(separator: "\n")

        // 字节上限：按**整行**收口（不切半行）；单行本身超上限才按字节安全边界切。
        var bytesClamped = false
        if text.utf8.count > maxReadBytes {
            var kept = startLine
            var used = 0
            while kept < endLine {
                let lineBytes = lines[kept].utf8.count + (kept > startLine ? 1 : 0)
                if used + lineBytes > maxReadBytes { break }
                used += lineBytes
                kept += 1
            }
            endLine = max(startLine + 1, kept)
            text = lines[startLine..<endLine].joined(separator: "\n")
            if text.utf8.count > maxReadBytes {
                let head = Data(text.utf8.prefix(maxReadBytes))
                text = Self.decodeUTF8(head) ?? String(decoding: head, as: UTF8.self)
            }
            bytesClamped = true
        }

        let truncated = endLine < totalLines || bytesClamped
        return .file(AgentToolFileOutput(path: relativePath(url),
                                        text: text,
                                        truncated: truncated,
                                        totalBytes: data.count,
                                        window: truncated
                                            ? AgentToolFileWindow(startLine: startLine, endLine: endLine,
                                                                  totalLines: totalLines)
                                            : nil))
    }

    /// UTF-8 解码（**字符安全**）：末尾最多回退 3 字节找能解码的边界。
    ///
    /// **只用于「已经按字节切过」的那一段**（切点可能落在多字节字符中间）；
    /// 整段解码请直接用 `String(data:encoding:)` —— 回退会放走真二进制。
    static func decodeUTF8(_ data: Data) -> String? {
        if let whole = String(data: data, encoding: .utf8) { return whole }
        var slice = data
        for _ in 0..<4 {
            guard !slice.isEmpty else { return nil }
            slice = slice.dropLast()
            if let candidate = String(data: slice, encoding: .utf8) { return candidate }
        }
        return nil
    }

    // MARK: - list_dir

    public func listDirectory(path: String,
                              fingerprint: String? = nil,
                              granted: Set<String> = []) -> AgentToolOutcome {
        let resolved = AgentWorkspaceSandbox.resolve(path, in: root)
        let url: URL
        switch resolved {
        case .inside(let inside):
            url = inside
        case .outside:
            // 列目录越界也是越界（§3.26）：先出单，批了才列。
            guard let tool = registry.definition(for: .listDirectory) else {
                return .refused(.unregistered, detail: AgentToolLevel.readOnly.rawValue)
            }
            let target = absoluteURL(for: path)
            guard let fingerprint, granted.contains(fingerprint) else {
                return outsideApproval(tool: tool, url: target, payload: path)
            }
            url = target
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .refused(.notFound, detail: url.lastPathComponent)
        }
        guard isDirectory.boolValue else { return .refused(.notADirectory, detail: url.lastPathComponent) }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        var entries: [String] = []
        for name in names.sorted() {
            var childIsDirectory: ObjCBool = false
            let child = url.appendingPathComponent(name)
            _ = FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory)
            entries.append(childIsDirectory.boolValue ? name + "/" : name)
        }
        let truncated = entries.count > maxDirectoryEntries
        if truncated { entries = Array(entries.prefix(maxDirectoryEntries)) }
        return .directory(AgentToolDirectoryOutput(path: relativePath(url), entries: entries, truncated: truncated))
    }

    // MARK: - search

    /// 一次调用最多搜几个词（防止模型把一整段话拆成 50 个词：那样每个文件要多比 50 轮）。
    public static let maxQueriesPerCall = 8

    /// 搜索（文件名 + 内容两类）。**复用既有引擎**，不另写遍历。
    ///
    /// 2026-11-07：改成**一次收多个词**。由头是真机读数 —— 26 步 / 149.6 秒、56 次工具调用，
    /// `search` 被「会话时间太长 / 会话超时 / 会话时间 / 会话」这类近义改写刷了十几次，
    /// 每次都是全仓扇扫（1.4–1.8 秒）+ 一次模型往返（约 9 秒）。
    /// 现在：多个词一次调用、**一次扫盘**；重复 / 包含关系的词直接吃缓存（毫秒级）；
    /// 返回里带一句「本次已搜过这 N 个词」，省得它下一步再一个一个词地重搜。
    public func searchStructured(queries rawQueries: [String], limit: Int = 50,
                                 at now: Date = Date()) -> AgentToolOutcome {
        let queries = Self.distinctQueries(rawQueries)
        guard !queries.isEmpty else {
            return .refused(.emptyQuery, detail: rawQueries.joined(separator: " "))
        }
        let started = Date()

        // ① 先问缓存：同一个词 / 包含关系的词不必再扫盘。
        let cachedHits = searchCache?.lookup(queries, at: now) ?? [:]
        var groups: [AgentToolSearchOutput.Group] = []
        var pending: [String] = []
        for query in queries {
            if let hit = cachedHits[WorkspaceSearch.normalize(query: query)] {
                groups.append(AgentToolSearchOutput.Group(
                    query: query, fileNames: hit.fileNames, contentHits: hit.contentHits,
                    cached: true, partial: !hit.exact, source: hit.source,
                    truncated: hit.truncated, elapsedMillis: 0))
            } else {
                pending.append(query)
            }
        }

        // ② 剩下的词**一次扫盘**（多词引擎：读一遍文件，每个词各比一遍）。
        if !pending.isEmpty {
            let scanStart = Date()
            // **首选随包 ripgrep**（`Contents/Resources/tools/rg`，2026-11-07 主人拍板）：
            // 同一查询（`WorkspaceSearch`）、同一个工作区根（`~/dev/doyah/lead`）实测：
            // limit=50 时 rg 65ms / 这两行 240ms；limit=1000（扫到底、不提前停）时 rg 49ms /
            // 这两行 1402ms —— 慢的那一头随「要扫多少」放大，rg 那一头不随。
            // 取不到 rg（随包被删 / 没有执行权 / 架构不符 / 超时 / rg 自己出错）⇒
            // `accelerate` 返回 nil，**原样回落既有 Swift 引擎** —— 不抛错、不返回空。
            let accelerated = ripgrepLocator().flatMap {
                AgentRipgrep.accelerate(in: root, queries: pending, limit: limit, executable: $0)
            }
            let nameResults = accelerated?.fileNames
                ?? WorkspaceSearch.findFileNames(in: root, queries: pending, limit: limit)
            let contentResults = accelerated?.contents
                ?? WorkspaceSearch.findContents(in: root, queries: pending, limit: limit)
            let millis = Int(Date().timeIntervalSince(scanStart) * 1000)
            for (index, query) in pending.enumerated() {
                let names = index < nameResults.count ? nameResults[index] : .init(entries: [], isTruncated: false)
                let contents = index < contentResults.count ? contentResults[index] : .empty
                let fileNames = names.entries.map(\.relativePath)
                var hits: [String] = []
                for group in contents.groups {
                    for hit in group.hits {
                        hits.append("\(group.entry.relativePath):\(hit.line): \(hit.snippet)")
                    }
                }
                let truncated = names.isTruncated || contents.isTruncated
                searchCache?.store(query: query, fileNames: fileNames, contentHits: hits,
                                   truncated: truncated, at: now)
                groups.append(AgentToolSearchOutput.Group(
                    query: query, fileNames: fileNames, contentHits: hits,
                    cached: false, partial: false, source: nil,
                    truncated: truncated, elapsedMillis: millis))
            }
        }

        // ③ 顺序还原成模型给的词的顺序（缓存命中的那几组是后来插进来的）。
        let order = Dictionary(queries.enumerated().map { (WorkspaceSearch.normalize(query: $1), $0) },
                               uniquingKeysWith: { first, _ in first })
        groups.sort { (order[WorkspaceSearch.normalize(query: $0.query)] ?? 0)
            < (order[WorkspaceSearch.normalize(query: $1.query)] ?? 0) }

        var mergedFileNames: [String] = []
        var mergedHits: [String] = []
        for group in groups {
            for name in group.fileNames where !mergedFileNames.contains(name) { mergedFileNames.append(name) }
            for hit in group.contentHits where !mergedHits.contains(hit) { mergedHits.append(hit) }
        }
        return .search(AgentToolSearchOutput(
            fileNames: mergedFileNames, contentHits: mergedHits,
            truncated: groups.contains(where: \.truncated),
            groups: groups, queries: queries,
            elapsedMillis: Int(Date().timeIntervalSince(started) * 1000)))
    }

    /// 单数入口：`query` 里**用空白（或逗号）隔开多个词**时按多个词搜（2026-11-07）；
    /// 只有一个词时与旧行为逐字相同。
    public func search(query: String, limit: Int = 50) -> AgentToolOutcome {
        let words = query.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" })
            .map(String.init)
        return searchStructured(queries: words.count > 1 ? words : [query], limit: limit)
    }

    /// 多词入口（`queries` 数组）。
    public func search(queries: [String], limit: Int = 50) -> AgentToolOutcome {
        searchStructured(queries: queries, limit: limit)
    }

    /// 词表归一：去空白、去空词、按归一词去重（`QQ` 与 `qq` 算同一个词），最多 `maxQueriesPerCall` 个。
    public static func distinctQueries(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = WorkspaceSearch.normalize(query: trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(trimmed)
            if result.count >= maxQueriesPerCall { break }
        }
        return result
    }

    // MARK: - write_file（③：差异预览 + 逐次审批 + 未批准不落盘）

    /// 备一次写入：**只看不写**，返回要审批的动作（`payload` = 差异预览）。
    ///
    /// `tool` 必须来自**注册表**（`FR-AI-19` ①：工具名只许出现在注册表定义处 ⇒ 本文件不写工具名字面量，
    /// 这一步由判据 `AgentToolRegistrySourceTests` 守着）。
    public func prepareWrite(path: String, content: String, tool: AgentToolDefinition? = nil,
                             guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false)) -> AgentToolOutcome {
        // ⑥ 只读模式下写类工具**连审批单都建不出来**（沿用 `AgentGuardrail` 的既有口径）
        guard !guardPolicy.readOnly else {
            return .refused(.deniedByPolicy, detail: AgentToolLevel.writable.rawValue)
        }
        guard let tool = tool ?? registry.writableDefinition else {
            return .refused(.unregistered, detail: AgentToolLevel.writable.rawValue)
        }
        let resolved = AgentWorkspaceSandbox.resolve(path, in: root)
        let url: URL
        switch resolved {
        case .inside(let inside):
            url = inside
        case .outside:
            // 越界写 = 出单（§3.26）：批了才落盘，单上写明目标绝对路径。
            return outsideApproval(tool: tool, url: absoluteURL(for: path), payload: content)
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue { return .refused(.notAFile, detail: url.lastPathComponent) }

        let before = exists ? ((try? String(contentsOf: url, encoding: .utf8)) ?? "") : ""
        let relative = relativePath(url)
        return .needsApproval(AgentApprovalRequest(
            toolName: tool.name,
            fingerprint: AgentFingerprint.hash("\(tool.name)|\(relative)|\(content)"),
            payload: AgentTextDiff.preview(before: before, after: content, path: relative),
            // 基线**出单时就记下**（`FR-AI-31` ①）：临写前复核这一格，对不上说明这份审批已经过期。
            baseDigest: AgentWriteTargetState.digest(at: url),
            // 作用域 = 这一个文件（§3.36 ②）：批了 `a.txt` 不等于批了同一目录里别的文件。
            scope: AgentApprovalScope.normalizedPath(relative),
            hazard: .ordinary))
    }

    /// 真写。**五件事缺一不可**：参数指纹与请求一致、该指纹在已批准集合里、目标仍在工作区内、
    /// **没有另一次写在同时写这个文件**（`FR-AI-31` ① 租约）、**目标还是出单时那一份**（基线）。
    ///
    /// `baseDigest` 给了才复核基线（`nil` = 调用方没有那一格，旧行为逐字不变）；
    /// 界面把卡片上记的基线传进来 ⇒ 审批之后被改过的文件**不会被旧审批静默覆盖**。
    public func writeFile(path: String, content: String, tool: AgentToolDefinition? = nil,
                          guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false),
                          fingerprint: String, granted: Set<String>,
                          baseDigest: String? = nil,
                          batch: AgentWriteBatchStore? = nil) -> AgentToolOutcome {
        let prepared = prepareWrite(path: path, content: content, tool: tool, guardPolicy: guardPolicy)
        guard case .needsApproval(let request) = prepared else { return prepared }
        guard request.fingerprint == fingerprint, granted.contains(fingerprint) else {
            return .refused(.approvalRequired, detail: request.fingerprint)
        }
        // 走到这里**指纹已经核过**（下一行的 guard 在前面）：越界写也放行 —— 那正是这张单批的东西。
        let url: URL
        if case .inside(let inside) = AgentWorkspaceSandbox.resolve(path, in: root) {
            url = inside
        } else {
            url = absoluteURL(for: path)
        }
        // **租约**（`FR-AI-31` ①）：同一个文件同时只许一个人写。拿不到就立刻如实说，**不排队、不覆盖**。
        guard let lease = writes.acquire(path: url.path) else {
            return .refused(.writeConflict, detail: relativePath(url))
        }
        defer { writes.release(lease) }
        // **基线复核**：出单之后这个文件被改过 ⇒ 这份审批已经不是"我批的那一份"，宁可不写。
        if let baseDigest, AgentWriteTargetState.digest(at: url) != baseDigest {
            return .refused(.staleTarget, detail: relativePath(url))
        }
        // **前像**在写之前取（`FR-STD-WS-EDIT-015`）：这一轮真写成功了才记，写坏的不记。
        let existedBefore = FileManager.default.fileExists(atPath: url.path)
        let previousText = existedBefore ? (try? String(contentsOf: url, encoding: .utf8)) : nil
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .refused(.unreadable, detail: url.lastPathComponent)
        }
        batch?.record(path: relativePath(url), previousText: previousText, writtenText: content)
        // 磁盘变了：这一轮之前的搜索命中不再可信（「写完再看一眼」要看到真东西）。
        searchCache?.invalidate()
        return .wrote(AgentToolFileOutput(path: relativePath(url), text: content,
                                         truncated: false, totalBytes: content.utf8.count))
    }

    // MARK: - edit_file（定点改代码：唯一锚点 + 逐次审批 + 未批准不落盘）

    /// 定点替换的**纯函数**（单测直接打这一条）：锚点必须**命中且唯一**。
    ///
    /// 两种情况都返回 `nil`（= 拒）：
    /// · **0 次命中** ⇒ 锚点对不上（文件被改过 / 记错了）—— 不是"改不动"，是"你不知道现在长什么样"；
    /// · **多次命中** ⇒ 锚点不唯一 —— 绝不替人猜"第一处"：那正是 AI 改代码最容易悄悄改错地方的地方。
    public static func applyingEdit(to text: String, oldString: String, newString: String) -> String? {
        guard !oldString.isEmpty else { return nil }
        let hits = text.components(separatedBy: oldString).count - 1
        guard hits == 1 else { return nil }
        return text.replacingOccurrences(of: oldString, with: newString)
    }

    /// 备一次定点修改：**只看不写**，返回要审批的动作（`payload` = 差异预览）。
    public func prepareEdit(path: String, oldString: String, newString: String,
                            tool: AgentToolDefinition? = nil,
                            guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false)) -> AgentToolOutcome {
        guard !guardPolicy.readOnly else {
            return .refused(.deniedByPolicy, detail: AgentToolLevel.writable.rawValue)
        }
        guard let tool = tool ?? registry.definition(for: .editFile) else {
            return .refused(.unregistered, detail: AgentToolLevel.writable.rawValue)
        }
        let url: URL
        switch AgentWorkspaceSandbox.resolve(path, in: root) {
        case .inside(let inside):
            url = inside
        case .outside:
            // 越界改 = 出单（§3.26）：单上写目标绝对路径与要改的两行，批了才动。
            return outsideApproval(tool: tool, url: absoluteURL(for: path),
                                   payload: "− " + oldString + "\n+ " + newString)
        }
        guard let before = try? String(contentsOf: url, encoding: .utf8) else {
            return .refused(.unreadable, detail: url.lastPathComponent)
        }
        guard let after = Self.applyingEdit(to: before, oldString: oldString, newString: newString) else {
            // **如实报数**：把"命中几次"写进 detail —— 0 与多次的处置理由不一样，别混成一句"改不了"。
            let hits = oldString.isEmpty ? 0 : before.components(separatedBy: oldString).count - 1
            return .refused(.badArguments, detail: "anchorHits:\(hits)")
        }
        let relative = relativePath(url)
        return .needsApproval(AgentApprovalRequest(
            toolName: tool.name,
            fingerprint: AgentFingerprint.hash("\(tool.name)|\(relative)|\(oldString)|\(newString)"),
            payload: AgentTextDiff.preview(before: before, after: after, path: relative),
            scope: AgentApprovalScope.normalizedPath(relative),
            hazard: .ordinary))
    }

    /// 真改。**三件事缺一不可**（与 `writeFile` 同一口径）：参数指纹与请求一致、该指纹在已批准集合里、目标仍在工作区内。
    public func editFile(path: String, oldString: String, newString: String,
                         tool: AgentToolDefinition? = nil,
                         guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false),
                         fingerprint: String, granted: Set<String>) -> AgentToolOutcome {
        let prepared = prepareEdit(path: path, oldString: oldString, newString: newString,
                                   tool: tool, guardPolicy: guardPolicy)
        guard case .needsApproval(let request) = prepared else { return prepared }
        guard request.fingerprint == fingerprint, granted.contains(fingerprint) else {
            return .refused(.approvalRequired, detail: request.fingerprint)
        }
        // 走到这里**指纹已经核过**（下一行的 guard 在前面）：越界写也放行 —— 那正是这张单批的东西。
        let url: URL
        if case .inside(let inside) = AgentWorkspaceSandbox.resolve(path, in: root) {
            url = inside
        } else {
            url = absoluteURL(for: path)
        }
        // **租约**（`FR-AI-31` ①）：与整篇重写共用同一本账 —— 两种写落在同一个文件上也要串行化。
        guard let lease = writes.acquire(path: url.path) else {
            return .refused(.writeConflict, detail: relativePath(url))
        }
        defer { writes.release(lease) }
        // **临写前再读一次盘**：审批这段时间里文件可能被改过 ⇒ 锚点必须**此刻**仍然唯一。
        guard let before = try? String(contentsOf: url, encoding: .utf8),
              let after = Self.applyingEdit(to: before, oldString: oldString, newString: newString) else {
            return .refused(.badArguments, detail: "anchorStale")
        }
        do {
            try after.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .refused(.unreadable, detail: url.lastPathComponent)
        }
        // 磁盘变了：本轮之前的搜索命中作废。
        searchCache?.invalidate()
        return .wrote(AgentToolFileOutput(path: relativePath(url), text: after,
                                         truncated: false, totalBytes: after.utf8.count))
    }

    // MARK: - run_command（④：白名单 + 工作目录沙箱 + 未审批不执行）

    /// 备一条命令：白名单与工作区参数先过一遍，过了才生成审批请求。`tool` 同样来自注册表。
    public func prepareCommand(_ command: String, tool: AgentToolDefinition? = nil,
                               guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false),
                               policy: AgentCommandPolicy = .standard) -> AgentToolOutcome {
        // **「忠」的第一道：伤害性动作及时刹停**（`FR-AI-34`）。
        // 放在**最前**，先于只读闸门、先于白名单、先于审批：
        // · 有害就是有害，与"此刻是不是只读模式"无关；
        // · **不建审批单** —— 不是"排队等批"，而是连单都不给（L0：不等指令、不打折扣、不给自己找"这次例外"）；
        // · 顺手留一条停手记录（"我没做过什么"要能被查）。
        if let signal = AgentHarmStop.inspect(command: command) {
            harmStopLog?.record(signal)
            return .refused(.harmStopped, detail: "\(signal.category.rawValue):\(signal.marker)")
        }
        // ⑥ 只读模式下执行类工具**连审批单都建不出来**
        guard !guardPolicy.readOnly else {
            return .refused(.deniedByPolicy, detail: AgentToolLevel.executable.rawValue)
        }
        guard let tool = tool ?? registry.executableDefinition else {
            return .refused(.unregistered, detail: AgentToolLevel.executable.rawValue)
        }
        switch policy.assess(command) {
        case .refused(let code, let detail):
            return .refused(code, detail: detail)
        case .allowed(let executable, let arguments):
            // 越界参数**不再直接拒**（§3.26）：整条命令本来就要审批，人在单上看得见 `cd /etc` 这种
            // 目标。这里只把越界目标标在单子上，让「批的是什么」不用猜。
            var payload = command
            if let refusal = policy.argumentsStayInsideWorkspace(arguments, root: root) {
                payload += "\n（越界：\(refusal.rawValue)）"
            }
            let material = "\(tool.name)|\(executable)|\(arguments.joined(separator: " "))"
            return .needsApproval(AgentApprovalRequest(toolName: tool.name,
                                                      fingerprint: AgentFingerprint.hash(material),
                                                      payload: payload,
                                                      // 作用域 = 命令首词（§3.36 ②）：`python3 a.py` 批过之后
                                                      // `python3 b.py` 不再问；换成 `git` 仍要问。
                                                      scope: AgentApprovalScope.commandWord(command),
                                                      // 危险面 = 首词 / git 子命令（`rm`、`git reset` …）⇒ 只保留「仅这一次」。
                                                      hazard: AgentApprovalHazardRules.command(command)))
        }
    }

    /// 真跑。工作目录**钉在工作区根**（沙箱）；命令交给注入的执行器（单测不真起进程）。
    public func runCommand(_ command: String,
                           tool: AgentToolDefinition? = nil,
                           guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false),
                           fingerprint: String,
                           granted: Set<String>,
                           policy: AgentCommandPolicy = .standard,
                           runner: AgentCommandRunner) async -> AgentToolOutcome {
        let prepared = prepareCommand(command, tool: tool, guardPolicy: guardPolicy, policy: policy)
        guard case .needsApproval(let request) = prepared else { return prepared }
        guard request.fingerprint == fingerprint, granted.contains(fingerprint) else {
            return .refused(.approvalRequired, detail: request.fingerprint)
        }
        guard case .allowed(let executable, let arguments) = policy.assess(command) else {
            return .refused(.commandNotAllowed, detail: command)
        }
        let result = await runner.run(executable: executable, arguments: arguments, workingDirectory: root)
        // 命令可能改了盘：本轮之前的搜索命中作废。
        searchCache?.invalidate()
        return .command(result)
    }

    // MARK: - 内部

    private func relativePath(_ url: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        let suffix = path.dropFirst(base.count)
        return suffix.hasPrefix("/") ? String(suffix.dropFirst()) : String(suffix)
    }
}
