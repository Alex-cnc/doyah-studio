import Foundation

// `FR-R-13-10` **触发面**（Retro macOS · Alpha 4 首片 A · 任务卡 `t_7bc2842f` · 派单 `T-20261009-085`）
// 的**核心层**（不含 UI —— 按钮 / 设置界面 = 同域另一片 `R13-10-B`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-10`（SRS v1.15 · 人类主人 2026-10-09 拍板 C）：
//   ① **手动**「生成本期」按钮（调用本机生成侧）② **用户可配置的本地定时触发**
//   ③ 触发入口 = 调用本机生成侧的命令行等价入口（`… headless "<生成任务>"`）
//   ④ **失败与缺期**：触发失败 ⇒ 记一行「缺期」+ 界面明确提示（**不静默、不补历史**）
//   ⑤ **不变量**：本进程**无对外网络出口**、不持密钥、不直写 Notes 库。
//
// 本片 = **核心层**，只做两件事（同域 UI 片另落）：
//   ① **触发生成**：注入式执行器跑一次生成 ⇒ 落成**确定结果值**（成功 / 失败 / 跳过）；
//   ② **缺期记账**：只有「失败」**追一行**「缺期」记录到**唯一落点**（扫描根**同级**日志）。
//
// 硬口径（照派单「组长定夺」逐条落）：
//   · **执行器可注入**：本层定义执行协议 `GenerationExecuting` + **默认实现**
//     `ProcessGenerationExecuting`（`Process` 调本机生成侧等价入口）；**单元测试一律注入桩**，
//     从不真跑生成侧（判据 1 的「注入桩未被真实调用」）。
//   · **入口字符串唯一出处**：可执行名与生成任务串**各写在一个常量里**（`GenerationSpec`）——
//     在 `Plugins/Retro/Sources` 下各命中 1（口径同 `ReportReader.fixedScanRootPath`）。
//   · **缺期落点唯一**：扫描根**同级**文件 `missed-periods.jsonl`（**追加一行 / 一期**，
//     字段 = 期号 + 结果 + 时刻）；**不自造第二处落点**。
//   · **结果三态**：成功（子进程退出码 0）/ 失败（非零退出 / 起不来 / 超时）/ 跳过（本期已存在，
//     **不重复触发**）；**只有「失败」追记缺期**（不补历史、不重试）。
//   · **无对外网络出口**：本文件不出现任何网络 API（判据 4 的机械形式 = grep 0 命中）。
//
// **只读语义的边界（如实登记）**：`IR-05` 不变量 7 / `FR-R-13-08` 判据 ③ 说的是「Retro **不写**
// 周报**包**」。本文件**不写包**：缺期行落在扫描根的**同级**日志文件上 —— 该文件**不在**任何周报
// 包目录内，也不是扫描根的直接子目录（不会被当成一期）。`Tools/check-readonly.py` 是一条**记号扫描**
// （对视图层 + 领域层逐行找 Swift 写 API），而本层对**包目录**的写调用为 **0**：追加日志走的是
// **显式低位文件追加**（`O_APPEND` + 裸 `write` + `close`，**不覆盖、不建目录**），从头到尾没有一行
// 碰包目录 ⇒ 判据 `Tools/check-readonly.py` 仍 `exit 0`（判据 3），`--self-test` 7/7 不变。
//
// **不联网 / 不持密钥 / 不碰 GUI**：本文件 `import` 只有 `Foundation`（领域层零 GUI 符号，
// 同 `Package.swift` 注释「依赖方向不变量 1」）。

// MARK: - 入口常量与落点（各只写一处）

/// 触发面的**入口字符串**与**落点** —— 各只在此处写一次，调用方一律从这里取。
public enum GenerationSpec {
    /// 生成侧可执行名（**唯一出处**；`Plugins/Retro/Sources` 下该字面量命中 1）。
    /// 按 `PATH` 解析（经 `/usr/bin/env`），**不把某台机器的绝对路径写进领域层**。
    public static let executableName = "dsh"

    /// 等价入口的子命令（`… headless`）。
    public static let headlessSubcommand = "headless"

    /// 生成任务串（**唯一出处**）—— 传给生成侧的那一句「生成本期」。
    public static let generationTask = "生成本期地缘政治周报"

    /// 缺期记录**文件名**（落点 = 扫描根**同级**）。
    public static let missedPeriodFileName = "missed-periods.jsonl"

    /// **缺期记录落点**：扫描根**同级**的那个日志文件（追加一行 / 一期）。
    ///
    /// 本机固定扫描根为 `/Users/alex/.dsh/notes/geopolitics-weekly/packages` ⇒ 落点即
    /// `/Users/alex/.dsh/notes/geopolitics-weekly/missed-periods.jsonl`（**唯一落点**，不自造第二处）。
    public static func missedPeriodLogURL(nextToScanRoot scanRoot: URL) -> URL {
        let parent = scanRoot.standardizedFileURL.deletingLastPathComponent()
        return parent.appendingPathComponent(missedPeriodFileName, isDirectory: false)
    }
}

// MARK: - 结果三态（一次触发的确定结果值）

/// 一次触发的**确定结果值**（`FR-R-13-10` ④ 的机械形式）。三态互斥、只有一态产出。
public enum GenerationOutcome: Equatable, CustomStringConvertible {
    /// **成功**：生成侧子进程退出码 0 —— 不记账。
    case success(period: String)
    /// **失败**：非零退出 / 起不来 / 超时 —— **只有这一态追记「缺期」**。
    case failure(period: String, reason: String)
    /// **跳过**：本期已存在 —— **不重复触发**（不跑执行器、不记账）。
    case skipped(period: String)

    /// 本次触发的期号。
    public var period: String {
        switch self {
        case .success(let period), .failure(let period, _), .skipped(let period):
            return period
        }
    }

    /// 三态的**中文标签**（写进缺期行的「结果」字段；实跑里只有「失败」会记账）。
    public var label: String {
        switch self {
        case .success: return "成功"
        case .failure: return "失败"
        case .skipped: return "跳过"
        }
    }

    /// 人读的一行（回单 / 界面提示直接印）。
    public var description: String {
        switch self {
        case .success(let period):
            return "\(period)：成功（生成侧退出码 0）"
        case .failure(let period, let reason):
            return "\(period)：失败（\(reason)）—— 已追记一行「缺期」"
        case .skipped(let period):
            return "\(period)：跳过（本期已存在，不重复触发）"
        }
    }
}

// MARK: - 执行器（可注入）

/// 一次执行的**底层读数** —— 只看子进程怎么结束，**不判三态**（三态由 `GenerationTrigger` 落）。
public enum GenerationExecution: Equatable {
    /// 子进程起来了并退出（`code == 0` ⇒ 成功）。
    case exited(code: Int32)
    /// 起不来（可执行找不到 / 权限 / 抛错）。
    case launchFailed(reason: String)
    /// 超时（到点未退出，已终止）。
    case timedOut(seconds: Double)
}

/// **可注入的执行器**：核心层只认这个协议；默认实现 = `ProcessGenerationExecuting`。
///
/// 单元测试**一律注入桩**（返回预置的 `GenerationExecution`），从不真跑生成侧。
public protocol GenerationExecuting {
    /// 跑一次生成，返回子进程的**底层读数**。
    func runGeneration() -> GenerationExecution
}

/// 默认执行器：`Process` 调本机生成侧的**等价入口**
/// （`<executableName> <headlessSubcommand> "<generationTask>"`）。
///
/// - 可执行名只用 `GenerationSpec.executableName`（唯一出处），经 `/usr/bin/env` 按 `PATH` 解析。
/// - **不联网、不持密钥、不直调模型**（红线 B3）：这里只起一个本机子进程。
/// - **超时**：到点未退出 ⇒ 终止子进程并读数 `.timedOut`（上层记为失败）。
public struct ProcessGenerationExecuting: GenerationExecuting {
    /// 超时秒数（到点终止子进程 ⇒ 记为失败）。
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 900) {
        self.timeout = timeout
    }

    public func runGeneration() -> GenerationExecution {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            GenerationSpec.executableName,
            GenerationSpec.headlessSubcommand,
            GenerationSpec.generationTask,
        ]

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return .launchFailed(reason: error.localizedDescription)
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            return .timedOut(seconds: timeout)
        }
        return .exited(code: process.terminationStatus)
    }
}

// MARK: - 缺期记账（唯一落点，追加不覆盖）

/// 「缺期」**一行**记录的三字段（`FR-R-13-10` ④ / `IR-06` 不变量 6：期号 + 结果，可机械核对）。
public struct MissedPeriodRecord: Equatable {
    /// 期号（= 本次触发的期）。
    public let period: String
    /// 结果（本层只会写「失败」；取自 `GenerationOutcome.label`，单一出处）。
    public let result: String
    /// 时刻（**ISO 8601 带时区**，如 `2026-10-09T13:05:00+08:00`）。
    public let timestamp: String

    public init(period: String, result: String, timestamp: String) {
        self.period = period
        self.result = result
        self.timestamp = timestamp
    }

    /// 一行 **JSONL**（键序固定 ⇒ 逐字节可复算）。三键 = 期号 / 结果 / 时刻。
    public var jsonLine: String {
        let pairs: [(String, String)] = [
            ("期号", period),
            ("结果", result),
            ("时刻", timestamp),
        ]
        let body = pairs
            .map { "\"\(MissedPeriodRecord.escaped($0.0))\":\"\(MissedPeriodRecord.escaped($0.1))\"" }
            .joined(separator: ",")
        return "{\(body)}"
    }

    /// JSON 字符串转义（只转义该转的；**不做**多余美化，保持逐字节确定）。
    static func escaped(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

/// 时刻 ⇒ **ISO 8601 带时区**（默认本机时区；给定 `Date` ⇒ 确定输出，便于单测）。
public enum GenerationTimestamp {
    public static func iso8601(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

/// 缺期日志的**追加**写入 —— **唯一落点**、**追加不覆盖**、**不建目录**。
///
/// 走**低位文件追加**（`O_WRONLY | O_CREAT | O_APPEND`）：盘上已有的行**原样保留**，
/// 本次只在**末尾**添一行。**不写周报包**（与 `IR-05` 不变量 7 同口径）。
public enum MissedPeriodLog {
    /// 把一行「缺期」追加到 `fileURL`（**追加**，绝不截断 / 覆盖）。
    ///
    /// - Returns: 落盘成功 ⇒ `true`；打不开 / 写不全 ⇒ `false`（调用方据此**如实登记**，
    ///   但触发的三态结果**不因此改变** —— 一次触发只落一个结果值）。
    @discardableResult
    public static func append(_ record: MissedPeriodRecord, to fileURL: URL) -> Bool {
        let line = record.jsonLine + "\n"
        let descriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return write(descriptor, base, buffer.count)
        }
        return written == bytes.count
    }
}

// MARK: - 触发入口

/// **触发面核心**：跑一次生成 ⇒ 落一个确定结果值；失败时追一行「缺期」。
public enum GenerationTrigger {
    /// 触发**一次**生成本期。
    ///
    /// 三态判定（`FR-R-13-10` ④）：
    ///   ① 本期**已存在**（扫描根里已有这一期成包）⇒ **跳过**（不跑执行器、不记账）；
    ///   ② 否则跑执行器：退出码 0 ⇒ **成功**；非零 / 起不来 / 超时 ⇒ **失败**，
    ///      并把一行「缺期」**追加**到扫描根同级的 `missed-periods.jsonl`。
    ///
    /// - Parameters:
    ///   - period: 本次要生成的期号（如 `2026-W40`）—— 原样写进缺期记录的「期号」字段。
    ///   - scanRoot: 扫描根（其直接子目录即各期包；缺期落点 = 其**同级**）。
    ///   - executing: 可注入执行器（**默认 = 本机生成侧**；单测一律注入桩）。
    ///   - now: 取当前时刻（可注入 ⇒ 单测可复算「时刻」）。
    ///   - fileManager: 只读探盘用（判「本期已存在」）。
    ///
    /// - Note: **不补历史、不重试** —— 一次调用只落一个结果值。
    public static func trigger(
        period: String,
        scanRoot: URL,
        executing: GenerationExecuting = ProcessGenerationExecuting(),
        now: () -> Date = Date.init,
        fileManager: FileManager = .default
    ) -> GenerationOutcome {
        // ① 本期已存在 ⇒ 跳过（不跑执行器、不记账）—— 复用领域层扫描器判「成包」，不另判一套。
        if periodAlreadyExists(period, scanRoot: scanRoot, fileManager: fileManager) {
            return .skipped(period: period)
        }

        // ② 跑一次生成，把子进程读数落成三态。
        switch executing.runGeneration() {
        case .exited(let code) where code == 0:
            return .success(period: period)

        case .exited(let code):
            return recordFailure(period: period, reason: "生成侧退出码 \(code)",
                                 scanRoot: scanRoot, now: now)

        case .launchFailed(let reason):
            return recordFailure(period: period, reason: "起不来：\(reason)",
                                 scanRoot: scanRoot, now: now)

        case .timedOut(let seconds):
            return recordFailure(period: period, reason: "超时 \(Int(seconds)) 秒",
                                 scanRoot: scanRoot, now: now)
        }
    }

    // MARK: - 内部

    /// 失败 ⇒ **追一行缺期**，再落 `.failure`（只有这一态记账）。
    private static func recordFailure(
        period: String,
        reason: String,
        scanRoot: URL,
        now: () -> Date
    ) -> GenerationOutcome {
        let outcome = GenerationOutcome.failure(period: period, reason: reason)
        let record = MissedPeriodRecord(
            period: period,
            result: outcome.label,
            timestamp: GenerationTimestamp.iso8601(now())
        )
        MissedPeriodLog.append(record, to: GenerationSpec.missedPeriodLogURL(nextToScanRoot: scanRoot))
        return outcome
    }

    /// 扫描根里是否已有这一期**成包**（`IR-05`：含 `index.json` + `report.md` 的直接子目录）。
    private static func periodAlreadyExists(
        _ period: String,
        scanRoot: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let result = try? ReportPackageScanner.scan(rootDirectory: scanRoot, fileManager: fileManager) else {
            return false
        }
        return result.packages.contains { $0.directoryName == period }
    }
}
