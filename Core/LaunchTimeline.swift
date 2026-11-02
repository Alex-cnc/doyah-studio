import Foundation

/// 冷启动计时（`NFR-ALL-GATE-PERF-001`：App 冷启动到可交互 ≤ 2 s，本机 SSD）。
///
/// ## 为什么这一半放进 Core
///
/// 「进程起点 → 根视图出现」是一段纯算术，不该只有在真启动一次 App 时才判得住：
/// 算术这一半由 `Tests/LaunchTimelineTests` 逐条钉住（含**收据读回** —— 台账类文件的
/// 序列化踩过「写 ISO8601、读 Double」那种「写进去了但读回是空」的坑，见
/// `LicenseDeviceStore` 那一笔），真启动那一半由 `Scripts/measure-cold-start.py`
/// 量（它只读本类型写出的收据）。
///
/// ## 三个口径写死在一处
///
/// - **起点** = 内核记录的进程创建时刻（`p_starttime`，平台层 `ProcessStartTime` 取），
///   不是「我第一次执行到的那一行」：后者会把 dyld / 动态链接 / 静态初始化算作免费 ——
///   而这正是冷启动里最不可控的一段。
/// - **终点** = 根视图出现之后再过一圈运行循环（首帧真的画了）。
/// - **判** = 毫秒数与阈值比；阈值只从 `Scripts/perf-baseline.json` 来，
///   本类型**只收参数、不存数字**（判据的输入必须只有一个写者）。
///
/// ## 边界（如实登记）
///
/// 量的是「进程创建 → 首帧」，**不含** GPU 上屏合成、不含磁盘缓存冷热区分
/// （同一次测量里前几遍会吃文件缓存 —— 所以 `Scripts/measure-cold-start.py` 跑多遍取中位数，
/// 并把每一遍的读数都打出来，不挑最快的那个）。
public struct LaunchTimeline: Equatable, Sendable {

    /// 三个可打点的位置。刻意只有这三个：打点越多越像「随便记点什么」，
    /// 而判据只用首尾两点 —— 中间那点用来解释「慢在哪一段」。
    public enum Phase: String, CaseIterable, Sendable {
        /// 进程起点（内核给的时刻）
        case processStart
        /// `DoyahStudioApp.init()` 走完（配置、单实例判定、语言自愈这些同步工作做完）
        case appInitialised
        /// 根视图出现（首帧）
        case rootViewAppeared
    }

    public let processStart: Date
    private var marks: [Phase: Date]

    public init(processStart: Date) {
        self.processStart = processStart
        self.marks = [.processStart: processStart]
    }

    /// 打点。**首次即定**：视图重建 / 主题切换会再走一遍 `onAppear`，
    /// 若允许覆盖，终点会被一次「重新布局」往后推 —— 那量到的就不是启动。
    public mutating func mark(_ phase: Phase, at date: Date = Date()) {
        guard marks[phase] == nil else { return }
        marks[phase] = date
    }

    public var interactiveAt: Date? { marks[.rootViewAppeared] }

    /// 从进程起点到某一点（含起点自身 = 0）的毫秒数。
    /// 时刻早于起点（系统时钟回拨 / 起点取自内核与 `Date()` 不同源）⇒ `nil`，
    /// **不夹成 0**：0 会被下游读成「极快」，把异常伪装成好成绩。
    public func milliseconds(at phase: Phase) -> Double? {
        guard let at = marks[phase] else { return nil }
        return Self.milliseconds(from: processStart, to: at)
    }

    /// 从进程起点到终点的毫秒数；终点没到 ⇒ `nil`（**不是 0**，理由同上）。
    public var elapsedMilliseconds: Double? { milliseconds(at: .rootViewAppeared) }

    /// 两点的毫秒差；负值 / 非有限值 ⇒ `nil`。
    public static func milliseconds(from start: Date, to end: Date) -> Double? {
        let value = end.timeIntervalSince(start) * 1000
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// 冷启动收据（App 在「可交互」那一刻写下，测量脚本读它）。
///
/// 时间一律存**自 1970 的秒（Double）**，不存 ISO8601 字符串：
/// 存字符串就得在两处（写 / 读）各选一次格式，选歪了就是「写进去了、读回来是空的」。
public struct LaunchReceipt: Codable, Equatable, Sendable {

    public static let schema = "doyah-launch-receipt/1"

    public let schema: String
    public let processStartEpoch: Double
    public let interactiveEpoch: Double
    /// 进程起点 → 可交互的毫秒数（与上面两个时刻同源，避免读方自己再算一遍算错）
    public let elapsedMs: Double
    /// 三个打点各自相对起点的毫秒数（缺哪个就没有那个键 —— 如实，不补 0）
    public let phasesMs: [String: Double]
    /// 构建口径（Debug / Release / 架构 …），由 App 侧从环境变量抄进来，可空
    public let build: String?
    public let writtenAt: String

    public init(timeline: LaunchTimeline, build: String? = nil, writtenAt: Date = Date()) throws {
        guard let interactive = timeline.interactiveAt, let elapsed = timeline.elapsedMilliseconds else {
            throw LaunchReceiptError.notInteractiveYet
        }
        self.schema = Self.schema
        self.processStartEpoch = timeline.processStart.timeIntervalSince1970
        self.interactiveEpoch = interactive.timeIntervalSince1970
        self.elapsedMs = elapsed
        var phases: [String: Double] = [:]
        for phase in LaunchTimeline.Phase.allCases {
            if let value = timeline.milliseconds(at: phase) { phases[phase.rawValue] = value }
        }
        self.phasesMs = phases
        self.build = build
        self.writtenAt = String(format: "%.3f", writtenAt.timeIntervalSince1970)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LaunchReceipt {
        let receipt = try JSONDecoder().decode(LaunchReceipt.self, from: data)
        guard receipt.schema == LaunchReceipt.schema else {
            throw LaunchReceiptError.unknownSchema(receipt.schema)
        }
        // 读回自查：三个数必须自洽（写坏 / 手改过的收据不许悄悄当成绩用）。
        let recomputed = (receipt.interactiveEpoch - receipt.processStartEpoch) * 1000
        guard recomputed.isFinite, recomputed >= 0, abs(recomputed - receipt.elapsedMs) <= 1.0 else {
            throw LaunchReceiptError.inconsistent(elapsedMs: receipt.elapsedMs, recomputedMs: recomputed)
        }
        return receipt
    }
}

/// 收据读写失败的原因。**只给机器码、不给句子**：Core 不出用户可见文案
/// （文案在 `Scripts/measure-cold-start.py` 与诊断输出里，那里才是读给用户看的地方）。
public enum LaunchReceiptError: Error, Equatable {
    case notInteractiveYet
    case unknownSchema(String)
    case inconsistent(elapsedMs: Double, recomputedMs: Double)

    public var code: String {
        switch self {
        case .notInteractiveYet: return "not-interactive-yet"
        case .unknownSchema(let schema): return "unknown-schema:\(schema)"
        case .inconsistent: return "inconsistent-timestamps"
        }
    }
}

/// 冷启动门槛的判定（阈值由调用方给 —— 唯一来源是 `Scripts/perf-baseline.json`）。
public enum LaunchBudget {

    public enum Verdict: Equatable, Sendable {
        /// 达标
        case within(measuredMs: Double, limitMs: Double)
        /// 超阈值
        case over(measuredMs: Double, limitMs: Double)
        /// 量不到 / 阈值本身不成立 —— **不是通过**
        case unmeasurable(reason: String)

        public var isPassing: Bool {
            if case .within = self { return true }
            return false
        }

        public var measuredMs: Double? {
            switch self {
            case .within(let measured, _), .over(let measured, _): return measured
            case .unmeasurable: return nil
            }
        }

        /// 机器码（`within` / `over` / `unmeasurable:<理由码>`）—— 句子由调用方拼。
        public var code: String {
            switch self {
            case .within: return "within"
            case .over: return "over"
            case .unmeasurable(let reason): return "unmeasurable:\(reason)"
            }
        }
    }

    /// 多遍里的代表值：中位数（偶数个取偏小那一侧的下中位数 —— 与 Swift 测里 `median` 同口径）。
    public static func median(_ values: [Double]) -> Double? {
        let usable = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !usable.isEmpty else { return nil }
        return usable[(usable.count - 1) / 2]
    }

    /// 单份收据 → 判定。
    public static func evaluate(_ receipt: LaunchReceipt?, limitMs: Double) -> Verdict {
        guard limitMs.isFinite, limitMs > 0 else {
            return .unmeasurable(reason: "limit-not-positive")
        }
        guard let receipt else {
            return .unmeasurable(reason: "no-receipt")
        }
        let measured = receipt.elapsedMs
        guard measured.isFinite, measured >= 0 else {
            return .unmeasurable(reason: "elapsed-not-finite")
        }
        return measured <= limitMs
            ? .within(measuredMs: measured, limitMs: limitMs)
            : .over(measuredMs: measured, limitMs: limitMs)
    }

    /// 多遍 → 判定（口径：**中位数**达标即可，不挑最快那一遍；每一遍的读数都要在被判的输出里）。
    public static func evaluate(runs: [Double], limitMs: Double) -> Verdict {
        guard limitMs.isFinite, limitMs > 0 else {
            return .unmeasurable(reason: "limit-not-positive")
        }
        guard !runs.isEmpty else { return .unmeasurable(reason: "no-runs") }
        guard let representative = median(runs) else {
            return .unmeasurable(reason: "runs-not-finite")
        }
        return representative <= limitMs
            ? .within(measuredMs: representative, limitMs: limitMs)
            : .over(measuredMs: representative, limitMs: limitMs)
    }
}
