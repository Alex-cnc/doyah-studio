import Foundation

// MARK: - 代码格式化（FR-EDIT-39，形态 = ③ 混合）
//
// 口径（2026-09-30 需求提出者拍板）：**有外部 formatter 就用外部、没有就用内置兜底，
// 并如实说明用了哪一种**；认不出的语言 / 不支持的语言**如实说原因**（不静默失败、
// 也不给出「看起来变了但没变」的结果）。
//
// 这一层的形状与 FR-EDIT-38 ① 同源：**工具的登记项是数据**（住在语言登记表里），
// 本文件不认识任何一个具体语言 —— 这里出现 `language == .python` 这类身份判断
// 就是判据要报红的形状。
//
// 三条不变量（判据与单测各守一半）：
//   1. **外部工具只许从 stdin 读、往 stdout 写**：用户没点保存之前，谁都不许动磁盘；
//   2. **内置兜底只改空白**（行尾空白 / 文件末尾换行 / 花括号语言的行首缩进），
//      且**字符串与注释里的空白一个字都不动**（多行模板串里的空格是内容）；
//   3. **认不出就是认不出**：回落值（认不出语言）与「认得但没有可用工具」是两种不同的拒绝。

/// 一个外部格式化工具的登记项。
public struct CodeFormatTool: Sendable, Equatable {
    /// 可执行文件名（在 `PATH` 里找；**不写死绝对路径** —— 用户的安装位置不由我们决定）。
    public let executable: String
    /// 固定实参。`%FILE%` 会换成当前文件的路径（没有路径时退回一个带正确扩展名的占位名）——
    /// 少数工具（如 Prettier）靠文件名判 parser。
    public let arguments: [String]
    /// 界面上如实说明用的名字（`Prettier` / `gofmt` …）。**不许空**：说了用外部工具就得说得清是哪一个。
    public let displayName: String
    /// 问版本的实参（契约层口径（b）：说了用外部工具，就要说得清**哪一个、哪一版**）。
    ///
    /// 默认 `--version`（绝大多数工具的约定）。**工具不认这个旗标就登记空数组**（`gofmt` 就是
    /// 这种）—— 探测不到就只说名字，**不编一个版本号出来**；探测失败也不算格式化失败。
    public let versionArguments: [String]

    public init(
        executable: String,
        arguments: [String] = [],
        displayName: String,
        versionArguments: [String] = ["--version"]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.displayName = displayName
        self.versionArguments = versionArguments
    }

    /// 实参里的文件名占位符。
    public static let fileNamePlaceholder = "%FILE%"

    /// 解出真实实参。
    public func resolvedArguments(file: String) -> [String] {
        arguments.map { $0 == Self.fileNamePlaceholder ? file : $0 }
    }

    /// 要不要探测版本（登记了空数组 = 这个工具不认 `--version`）。
    public var canReportVersion: Bool { !versionArguments.isEmpty }
}

/// 内置兜底能做的那几件事（**能力表里的数据**，不是身份分支）。
public enum CodeFormatBuiltin: String, Sendable, CaseIterable {
    /// 不提供内置兜底（没有外部工具时如实拒绝）。
    case none
    /// 行尾空白 + 文件末尾恰好一个换行（字符串里的空白不动）。
    case whitespace
    /// `whitespace` 之上，再把花括号语言的行首缩进按括号深度重排。
    case braceIndent
    /// 走既有的保守 SQL 格式化器（`Core/SQLFormatter.swift`，FR-EDIT-22）。
    case sql
    /// **JSON 专用：断行 + 缩进重排**（`prettyJSON`）。
    ///
    /// 为什么只有它敢断行：**JSON 字符串外的空白是语义无关的** —— 重排不会改意思，
    /// 而 JS / C / Go 那些括号语言里，注释、模板字符串、正则字面量都可能藏着花括号，
    /// 没有真词法就会改坏。旧口径把 JSON 也交给 `braceIndent`（**逐行**重排缩进）⇒
    /// 一行式的 JSON（需求提出者「打乱」的正是这种）**除行尾那一个换行外没有任何变化**，
    /// 界面上就是「点了没反应」（内测 `#2` 第二轮打回，见队列 `L-169`）。
    case json

    /// 这条兜底**真的会改东西吗**：`none` 不算能力（登记了它等于「没有兜底」）。
    public var isAvailable: Bool { self != .none }
}

/// 一个语言的格式化能力（登记在语言表里）。
public struct CodeFormatCapability: Sendable, Equatable {
    /// 外部工具候选，**按优先级**（第一个装了的赢）。
    public let tools: [CodeFormatTool]
    /// 内置兜底。
    public let builtin: CodeFormatBuiltin

    public init(tools: [CodeFormatTool] = [], builtin: CodeFormatBuiltin = .none) {
        self.tools = tools
        self.builtin = builtin
    }

    /// 没有登记任何能力。**认得出的语言也可以是这个**（例如 C# / PHP：常见发行版里没有
    /// 「读 stdin、写 stdout」的官方格式化器，硬塞一个等于骗用户）。
    public static let none = CodeFormatCapability()
}

/// 这次格式化**用的是哪一种**（界面要如实说明它）。
public enum CodeFormatEngine: Sendable, Equatable {
    /// 外部工具（名字 = 登记项里的 `displayName`；版本探测不到时为 `nil`，
    /// **不编一个版本号** —— 契约层要的是「说得清用了哪一个」，不是「看起来说得清」）。
    case external(name: String, version: String?)
    /// 内置兜底。
    case builtin(CodeFormatBuiltin)
}

/// 做不了的两种原因 —— **分开说**，因为它们对用户的含义不同。
public enum CodeFormatRefusal: Sendable, Equatable {
    /// 认不出这个文件是什么语言（语言表的回落值）。
    case unknownLanguage
    /// 认得出来，但既没有装了的外部工具、也没有内置兜底。
    case noFormatter(language: TextLanguage)
}

/// 本次要走的路线（纯计算结果，不含任何副作用）。
public enum CodeFormatPlan: Sendable, Equatable {
    case external(CodeFormatTool)
    case builtin(CodeFormatBuiltin)
    case refused(CodeFormatRefusal)
}

/// 选路（纯函数）：**这一条判据是「③ 混合」的全部内容**。
public enum CodeFormatPlanner {

    /// 语言 + 路径 + 「这个可执行文件在不在」的探测结果 → 走哪条路。
    ///
    /// 探测结果**由调用方注入**（App 侧 = 真查 `PATH`，单测 = 一张名字表）：
    /// 「装了没有」是环境事实，不是这段逻辑的事 —— 注入之后这条判据在没装任何工具的
    /// 机器上也跑得出，否则「外部优先 / 内置兜底」这两条分支永远只有一条被测到。
    public static func plan(
        language: TextLanguage,
        isExecutable: (String) -> Bool
    ) -> CodeFormatPlan {
        plan(definition: language.definition, isExecutable: isExecutable)
    }

    /// 同一条判断，直接吃一份定义 —— 单测用它构造**表里还没有的组合**
    /// （例如「认得、有词法、却一个工具都没有」，那是"如实拒绝"这条路的来源）。
    public static func plan(
        definition: CodeLanguageDefinition,
        isExecutable: (String) -> Bool
    ) -> CodeFormatPlan {
        // ① 认不出（回落值）：不装作用纯文本格式化器「格式化」了一遍。
        if definition.isFallback { return .refused(.unknownLanguage) }

        let capability = definition.format
        // ② 外部优先：候选按登记顺序，第一个装了的就用它。
        if let tool = capability.tools.first(where: { isExecutable($0.executable) }) {
            return .external(tool)
        }
        // ③ 内置兜底。**只对有词法规则的语言开放**：兜底靠词法证明「那段空白不在字符串里」，
        //    没有词法就证明不了（纯文本 / Markdown / YAML 的空白本来就可能是内容）——
        //    证明不了就不做，如实拒绝，而不是猜着改。
        if capability.builtin.isAvailable, definition.syntax.hasAnyRule {
            return .builtin(capability.builtin)
        }
        // ④ 都不行：如实拒绝，并说清是哪个语言。
        return .refused(.noFormatter(language: definition.language))
    }

    /// **只用内置**（需求提出者 2026-10-02 定案）—— 不探测外部工具，也没有「外部优先 / 回退内置」那一层。
    ///
    /// 与 `plan(language:isExecutable:)` 的差别只有一处：**不进「外部优先」那条分支，连探测都不做**
    /// （环境里装没装 `prettier` 不影响这条路）。三条出口与旧口径一致：认不出 ⇒ `.refused(.unknownLanguage)`；
    /// 有词法且有内置 ⇒ `.builtin`；其余 ⇒ `.refused(.noFormatter)`。
    public static func planBuiltinOnly(language: TextLanguage) -> CodeFormatPlan {
        planBuiltinOnly(definition: language.definition)
    }

    public static func planBuiltinOnly(definition: CodeLanguageDefinition) -> CodeFormatPlan {
        if definition.isFallback { return .refused(.unknownLanguage) }
        let capability = definition.format
        if capability.builtin.isAvailable, definition.syntax.hasAnyRule {
            return .builtin(capability.builtin)
        }
        return .refused(.noFormatter(language: definition.language))
    }

    /// `%FILE%` 的落值：有路径用路径，没有就用「untitled.<本语言的第一个扩展名>」——
    /// 靠文件名判 parser 的工具（Prettier）拿到 `untitled.txt` 会直接报错，而那不是用户的错。
    public static func fileName(path: String?, language: TextLanguage) -> String {
        if let path, !path.isEmpty { return path }
        let ext = language.fileExtensions.first ?? "txt"
        return "untitled.\(ext)"
    }
}

/// 外部工具「装上了但用不了」的原因。**「无联网」是其中一类** —— 人类主人 2026-10-02 的形态定案
/// （「**优先外部，如无联网则用内置**」）要求这一档**回退内置**，且**如实说明**为什么回退。
///
/// 这里只给**结构**，不给给用户看的句子 —— 用户可见文案一律走语言表（见 `App/LocalizationManager`）。
public enum CodeFormatUnusableReason: Sendable, Equatable, CaseIterable {
    /// 无网络连接（或网络型格式化工具连不上它的端点）。
    case networkUnreachable
    /// 装上了但跑不起来（缺依赖 / 没执行权限 / 平台不匹配）。
    case notRunnable
}

/// 探针的**三态**：「装了没有」只是其中一维 —— 「装了但不能用」必须与「没装」分开，
/// 否则界面说不出回退的**真正**原因（定案要的就是这一句）。
public enum CodeFormatToolStatus: Sendable, Equatable {
    case usable
    case unusable(CodeFormatUnusableReason)
    case missing
}

/// 选路结果 + **回退原因**（非空 = 本该走外部、因它退回了内置；界面必须说出来）。
public struct CodeFormatDecision: Sendable, Equatable {
    public let plan: CodeFormatPlan
    public let fallbackReason: CodeFormatUnusableReason?

    public init(plan: CodeFormatPlan, fallbackReason: CodeFormatUnusableReason?) {
        self.plan = plan
        self.fallbackReason = fallbackReason
    }
}

public extension CodeFormatPlanner {

    /// 三态探针版选路 —— **定案口径的落点**：候选按优先级找**能用的**；装上了但不能用的
    /// **记下原因继续往下找**；一个能用的外部都没有 ⇒ 回退内置，并**把原因带出去**。
    static func decide(
        language: TextLanguage,
        status: (String) -> CodeFormatToolStatus
    ) -> CodeFormatDecision {
        decide(definition: language.definition, status: status)
    }

    /// 同一条判断，直接吃一份定义（单测用它构造表里还没有的组合）。
    static func decide(
        definition: CodeLanguageDefinition,
        status: (String) -> CodeFormatToolStatus
    ) -> CodeFormatDecision {
        if definition.isFallback {
            return CodeFormatDecision(plan: .refused(.unknownLanguage), fallbackReason: nil)
        }
        let capability = definition.format
        var unusable: CodeFormatUnusableReason?
        for tool in capability.tools {
            switch status(tool.executable) {
            case .usable:
                return CodeFormatDecision(plan: .external(tool), fallbackReason: nil)
            case .unusable(let reason):
                // 登记顺序 = 优先级 ⇒ **第一个**候选的原因最能解释用户看到的结果。
                if unusable == nil { unusable = reason }
            case .missing:
                continue
            }
        }
        if capability.builtin.isAvailable, definition.syntax.hasAnyRule {
            return CodeFormatDecision(plan: .builtin(capability.builtin), fallbackReason: unusable)
        }
        return CodeFormatDecision(
            plan: .refused(.noFormatter(language: definition.language)),
            fallbackReason: nil
        )
    }

    /// 旧的布尔探针（只有「装了没有」两态）走这条 —— 回退原因恒为 `nil`。
    /// 保留它是因为两态调用点仍然有效，**不是**因为三态可以不要。
    static func decide(
        language: TextLanguage,
        isExecutable: (String) -> Bool
    ) -> CodeFormatDecision {
        decide(language: language) { isExecutable($0) ? .usable : .missing }
    }
}

/// 「这个工具装了没有」的**唯一实现**：按 `PATH` 顺序找可执行文件。
///
/// 与 `FoundationProcessRunner.resolveExecutable` 同一口径（那里是备份工具用的），
/// 差别只有一处：这里找不到就是 `false`，不抛错 —— 选路要的是「有没有」，不是「为什么没有」。
public enum CodeFormatToolLocator {
    public static func isExecutable(_ name: String) -> Bool {
        (try? FoundationProcessRunner.resolveExecutable(name)) != nil
    }
}

// MARK: - 进程面（外部工具）

/// 「把源码喂给工具、把结果读回来」的进程执行面。
///
/// **为什么不复用 `ExternalProcessRunner`**：那条路是给备份工具用的（stdin 接 `/dev/null`、
/// 输出逐行回调）—— 格式化器要的正好相反：**stdin 是整篇源码、stdout 是整篇结果**。
/// 塞进一条协议会让两边都变含糊，而单测想要的只是「喂进去什么、拿回来什么」这一件事。
public protocol CodeFormatProcessRunning: Sendable {
    func runFilter(executable: String, arguments: [String], input: String) async throws -> CodeFormatProcessResult
}

/// 一次过滤调用的原始结果。
public struct CodeFormatProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// 真实现（`Foundation.Process`）。**argv 直接交给进程、永不经过 shell**（与备份同一口径）：
/// 路径里的空格、引号都只是普通参数，命令注入在结构上不可能发生。
public struct FoundationCodeFormatProcessRunner: CodeFormatProcessRunning {
    public init() {}

    public func runFilter(
        executable: String,
        arguments: [String],
        input: String
    ) async throws -> CodeFormatProcessResult {
        let process = Process()
        process.executableURL = try FoundationProcessRunner.resolveExecutable(executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        do {
            try process.run()
        } catch {
            throw ExternalProcessError.launchFailed(executable: executable, reason: error.localizedDescription)
        }

        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        // 读与等退出**并行**：先等退出再读，缓冲区满时子进程会阻塞在写、我们也读不到（死锁）。
        let readerOut = Task.detached(priority: .utility) { Self.readAll(stdout.fileHandleForReading) }
        let readerErr = Task.detached(priority: .utility) { Self.readAll(stderr.fileHandleForReading) }
        let waiter = Task.detached(priority: .utility) { process.waitUntilExit() }

        await waiter.value
        let out = await readerOut.value
        let err = await readerErr.value
        return CodeFormatProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: out, as: UTF8.self),
            standardError: String(decoding: err, as: UTF8.self)
        )
    }

    private static func readAll(_ handle: FileHandle) -> Data {
        var data = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            data.append(chunk)
        }
        return data
    }
}

// MARK: - 结局

/// 一次格式化的结局（界面只需要这三态）。
public enum CodeFormatExecution: Sendable, Equatable {
    case ready(CodeFormatOutcome)
    case refused(CodeFormatRefusal)
    case failed(CodeFormatFailure)
}

/// 成了的那一态。
public struct CodeFormatOutcome: Sendable, Equatable {
    /// 要落到编辑器里的文本。
    public let text: String
    /// 用的是哪一种（如实说明）。
    public let engine: CodeFormatEngine
    /// 结果与原文是否**逐字不同**。为假时界面说「内容没有变化」，
    /// 而不是装作格式化了一遍（需求原文：不给出「看起来变了但没变」的结果）。
    public let changed: Bool

    public init(text: String, engine: CodeFormatEngine, changed: Bool) {
        self.text = text
        self.engine = engine
        self.changed = changed
    }
}

/// 工具起来了但没成。
public struct CodeFormatFailure: Sendable, Equatable {
    public let engine: CodeFormatEngine
    /// 退出码；**起不来时是 `nil`**（没有进程就没有退出码，别编一个 0 出来）。
    public let exitCode: Int32?
    /// 工具自己吐出来的诊断（**原文，不翻译** —— 那是它的输出，不是我们的文案）。
    public let message: String

    public init(engine: CodeFormatEngine, exitCode: Int32?, message: String) {
        self.engine = engine
        self.exitCode = exitCode
        self.message = message
    }
}

// MARK: - 执行

public enum CodeFormatService {

    /// 照计划执行。`runner` 只在「外部」那条路上用到 —— 单测喂假实现，
    /// 于是「外部优先 / 工具失败怎么说」这些判断不需要真的装 Prettier。
    public static func run(
        plan: CodeFormatPlan,
        language: TextLanguage,
        path: String?,
        text: String,
        databaseType: DatabaseType = .postgresql,
        runner: CodeFormatProcessRunning
    ) async -> CodeFormatExecution {
        switch plan {
        case .refused(let reason):
            return .refused(reason)

        case .builtin(let style):
            let formatted = CodeBuiltinFormatter.format(
                text, style: style, language: language, databaseType: databaseType
            )
            return .ready(
                CodeFormatOutcome(text: formatted, engine: .builtin(style), changed: formatted != text)
            )

        case .external(let tool):
            let engine = CodeFormatEngine.external(name: tool.displayName, version: nil)
            do {
                let result = try await runner.runFilter(
                    executable: tool.executable,
                    arguments: tool.resolvedArguments(
                        file: CodeFormatPlanner.fileName(path: path, language: language)
                    ),
                    input: text
                )
                guard result.exitCode == 0 else {
                    return .failed(
                        CodeFormatFailure(
                            engine: engine,
                            exitCode: result.exitCode,
                            message: diagnostic(result.standardError, fallback: result.standardOutput)
                        )
                    )
                }
                // 成了才去问版本：失败的那一态要的是失败原因，不是版本号。
                let reported = CodeFormatEngine.external(
                    name: tool.displayName,
                    version: await version(of: tool, runner: runner)
                )
                return .ready(
                    CodeFormatOutcome(
                        text: result.standardOutput,
                        engine: reported,
                        changed: result.standardOutput != text
                    )
                )
            } catch {
                return .failed(
                    CodeFormatFailure(engine: engine, exitCode: nil, message: error.localizedDescription)
                )
            }
        }
    }

    /// **只用内置**那条路的执行入口：**不收 `runner`** —— 这条路上没有任何子进程可起
    /// （定案「只用内置」在结构上落地：调用方拿不到跑外部工具的手段）。
    public static func runBuiltin(
        language: TextLanguage,
        text: String,
        databaseType: DatabaseType = .postgresql
    ) -> CodeFormatExecution {
        switch CodeFormatPlanner.planBuiltinOnly(language: language) {
        case .refused(let reason):
            return .refused(reason)
        case .builtin(let style):
            let formatted = CodeBuiltinFormatter.format(
                text, style: style, language: language, databaseType: databaseType
            )
            return .ready(
                CodeFormatOutcome(text: formatted, engine: .builtin(style), changed: formatted != text)
            )
        case .external:
            // 结构上到不了这里（`planBuiltinOnly` 从不返回 `.external`）；真到了也不静默。
            return .refused(.noFormatter(language: language))
        }
    }

    /// 问工具版本（契约层口径（b）：说了用外部工具，就要说得清**哪一个、哪一版**）。
    ///
    /// 三条边界，都按「如实」处理：
    ///   · 登记里 `versionArguments` 为空（工具不认 `--version`，如 `gofmt`）⇒ **不探测**，
    ///     返回 `nil`，界面只说名字；
    ///   · 探测起不来 / 非零退出 ⇒ 同样返回 `nil`（探测失败**不是**格式化失败）；
    ///   · 版本串只取**第一条非空行**并截断 —— 有些工具的 `--version` 会顺带吐一堆构建信息。
    static func version(of tool: CodeFormatTool, runner: CodeFormatProcessRunning) async -> String? {
        guard tool.canReportVersion else { return nil }
        guard let result = try? await runner.runFilter(
            executable: tool.executable,
            arguments: tool.versionArguments,
            input: ""
        ), result.exitCode == 0 else { return nil }
        let line = result.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return String(line.prefix(60))
    }

    /// 失败时给用户看的那一句：优先 `stderr` 里第一条非空行（工具的话最有用），其次 `stdout`。
    static func diagnostic(_ stderr: String, fallback: String) -> String {
        for source in [stderr, fallback] {
            if let line = source.split(separator: "\n").map(String.init)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}

// MARK: - 内置兜底

/// 没有外部工具时用的那一层。**它改的东西是可以逐条说完的**：
///
/// | 风格 | 改什么 | 不改什么 |
/// | --- | --- | --- |
/// | `whitespace` | 每行行尾空白、文件末尾恰好一个换行 | 行首缩进、字符串里的空白、`\r`（CRLF 是另一件事） |
/// | `braceIndent` | 上面那些 + 行首缩进按花括号深度 | 落在字符串里的整行、注释里的花括号 |
/// | `sql` | 走既有 SQL 格式化器（FR-EDIT-22 的保守规则） | 任何 token |
///
/// 「字符串里的空白一个字都不动」不是洁癖：多行模板串（JS `${...}`、Go 反引号、Rust `r#"…"#`）
/// 里的行尾空格**是内容**，改了就是改语义 —— 而这类改动在界面上看起来只是「格式化了一下」。
public enum CodeBuiltinFormatter {


    /// **JSON 美化**：断行 + 按括号深度缩进，字符串外的空白一律重排。
    ///
    /// 三条纪律：
    ///   · **只绕开字符串与转义** —— `"a{b}:,c"` 里的结构符不许当结构符（JSON 里字符串是唯一
    ///     必须保护的地方；注释 JSON 没有，所以不需要真词法）；
    ///   · 空容器保持紧凑（`{}` / `[]` 不摊成三行）；
    ///   · 收尾恰好一个换行（与 `tidy` 同口径），空输入原样返回。
    static func prettyJSON(_ text: String) -> String {
        // 第一遍：切成词元。字符串外的一切空白**直接丢**（JSON 里它没有语义）。
        var atoms: [String] = []
        var buffer = ""
        var inString = false
        var escaped = false
        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { atoms.append(trimmed) }
            buffer = ""
        }
        for character in text {
            if inString {
                buffer.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" {
                buffer.append(character)
                inString = true
                continue
            }
            if "{}[],:".contains(character) {
                flush()
                atoms.append(String(character))
                continue
            }
            buffer.append(character)
        }
        flush()
        guard !atoms.isEmpty else { return text }

        // 第二遍：按结构符排版。
        var output = ""
        var depth = 0
        func breakLine(_ level: Int) {
            output += "\n" + String(repeating: indentUnit, count: max(level, 0))
        }
        for (position, atom) in atoms.enumerated() {
            let next = position + 1 < atoms.count ? atoms[position + 1] : ""
            let previous = position > 0 ? atoms[position - 1] : ""
            switch atom {
            case "{", "[":
                output += atom
                depth += 1
                if !(atom == "{" && next == "}") && !(atom == "[" && next == "]") { breakLine(depth) }
            case "}", "]":
                depth -= 1
                if !(atom == "}" && previous == "{") && !(atom == "]" && previous == "[") { breakLine(depth) }
                output += atom
            case ",":
                output += atom
                breakLine(depth)
            case ":":
                output += ": "
            default:
                output += atom
            }
        }
        return output + "\n"
    }

    /// 缩进单位（与 SQL 格式化器、编辑器一致：4 空格）。
    public static let indentUnit = "    "

    public static func format(
        _ text: String,
        style: CodeFormatBuiltin,
        language: TextLanguage,
        databaseType: DatabaseType = .postgresql
    ) -> String {
        switch style {
        case .none:
            return text
        case .whitespace:
            return tidy(text, language: language)
        case .braceIndent:
            return reindent(tidy(text, language: language), language: language)
        case .sql:
            return SQLFormatter(databaseType: databaseType).format(text)
        case .json:
            return prettyJSON(text)
        }
    }

    /// 行尾空白 + 文件末尾恰好一个换行。
    static func tidy(_ text: String, language: TextLanguage) -> String {
        guard !text.isEmpty else { return text }
        let ns = text as NSString
        let strings = ranges(in: text, language: language, kinds: [.string])
        var lines: [String] = []
        var cursor = 0
        while true {
            let remaining = NSRange(location: cursor, length: ns.length - cursor)
            let newline = ns.range(of: "\n", options: [], range: remaining)
            let lineEnd = newline.location == NSNotFound ? ns.length : newline.location
            let line = ns.substring(with: NSRange(location: cursor, length: lineEnd - cursor))
            lines.append(trimmedTrailing(line, lineOffset: cursor, strings: strings))
            if newline.location == NSNotFound { break }
            cursor = lineEnd + 1
        }
        // 拆完之后末尾那个元素是「最后一个换行之后的内容」：空串表示文件本来就有结尾换行。
        while let last = lines.last, last.isEmpty, lines.count > 1 { lines.removeLast() }
        guard let last = lines.last, !last.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 一行去掉行尾空白；**这段空白落在字符串里就原样返回**。
    private static func trimmedTrailing(_ line: String, lineOffset: Int, strings: [NSRange]) -> String {
        let ns = line as NSString
        var end = ns.length
        while end > 0 {
            let ch = ns.character(at: end - 1)
            guard ch == 0x20 || ch == 0x09 else { break }
            end -= 1
        }
        guard end < ns.length else { return line }
        let span = NSRange(location: lineOffset + end, length: ns.length - end)
        if strings.contains(where: { NSIntersectionRange($0, span).length > 0 }) { return line }
        return ns.substring(with: NSRange(location: 0, length: end))
    }

    /// 行首缩进按花括号深度重排。
    ///
    /// 两条保护（都是实测会踩的）：
    ///   · **整行落在字符串里的行原样返回** —— 那是多行字符串的续行，行首空白是内容；
    ///   · **字符串与注释里的花括号不计数** —— 计数靠词法器给的记号区间，不靠数 `{`。
    ///     注释行本身的缩进照常重排（行首空白不是注释内容），块注释的续行只是空格变了位置。
    static func reindent(_ text: String, language: TextLanguage) -> String {
        guard !text.isEmpty else { return text }
        let ns = text as NSString
        let strings = ranges(in: text, language: language, kinds: [.string])
        let code = ranges(in: text, language: language, kinds: [.string, .comment])
        var lines: [String] = []
        var depth = 0
        var cursor = 0
        while true {
            let remaining = NSRange(location: cursor, length: ns.length - cursor)
            let newline = ns.range(of: "\n", options: [], range: remaining)
            let lineEnd = newline.location == NSNotFound ? ns.length : newline.location
            let line = ns.substring(with: NSRange(location: cursor, length: lineEnd - cursor))
            lines.append(
                reindentedLine(line, lineOffset: cursor, strings: strings, code: code, depth: &depth)
            )
            if newline.location == NSNotFound { break }
            cursor = lineEnd + 1
        }
        return lines.joined(separator: "\n")
    }

    private static func reindentedLine(
        _ line: String,
        lineOffset: Int,
        strings: [NSRange],
        code: [NSRange],
        depth: inout Int
    ) -> String {
        let ns = line as NSString
        var start = 0
        while start < ns.length {
            let ch = ns.character(at: start)
            guard ch == 0x20 || ch == 0x09 else { break }
            start += 1
        }
        // 空行（或只剩空白）：保持空行 —— 行尾空白已经在上一步去掉了。
        guard start < ns.length else { return "" }

        let contentOffset = lineOffset + start
        if strings.contains(where: { $0.location <= contentOffset && contentOffset < NSMaxRange($0) }) {
            return line
        }

        let content = ns.substring(from: start)
        // 这一行以 `}` 起头 ⇒ 它属于**上一层**：先退一层再写。
        let level = max(0, depth + (content.hasPrefix("}") ? -1 : 0))
        depth = max(0, depth + braceDelta(in: line, lineOffset: lineOffset, code: code))
        return String(repeating: indentUnit, count: level) + content
    }

    /// 这一行贡献的括号净增量（字符串 / 注释里的不算）。
    private static func braceDelta(in line: String, lineOffset: Int, code: [NSRange]) -> Int {
        let ns = line as NSString
        var delta = 0
        for index in 0..<ns.length {
            let offset = lineOffset + index
            if code.contains(where: { $0.location <= offset && offset < NSMaxRange($0) }) { continue }
            switch ns.character(at: index) {
            case 0x7B: delta += 1   // {
            case 0x7D: delta -= 1   // }
            default: break
            }
        }
        return delta
    }

    /// 记号区间（UTF-16）—— 空白规整与括号计数的**唯一依据**。
    ///
    /// 为什么不用现成的 `hasMarkedText` 那套：这里要的是「哪些字符属于字符串 / 注释」，
    /// 而那件事只有词法器知道（FR-EDIT-38 ①：语言知识来自登记表，不来自这里的判断）。
    static func ranges(in text: String, language: TextLanguage, kinds: [CodeToken.Kind]) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        return CodeLexer.tokens(in: text, language: language)
            .filter { kinds.contains($0.kind) }
            .map { NSRange($0.range, in: text) }
            .sorted { $0.location < $1.location }
    }
}
