import Combine
import Foundation
import SwiftUI

import DoyahRetroCore

// `FR-R-13-10` **触发面 UI**（Retro macOS · Alpha 4 首片 B · 任务卡 `t_811e5b11` · 派单 `T-20261009-085`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-10`（SRS v1.15 · 人类主人 2026-10-09 拍板 C）：
//   ① **手动**「生成本期」按钮 ② **用户可配置的本地定时触发**（周期 / 时刻 / 开关）
//   ③ 触发入口 = 本机生成侧等价入口（核心层 `GenerationTrigger`）④ 失败 ⇒ 记缺期 + **界面明确提示（不静默）**
//   ⑤ 不变量：本进程**无对外网络出口**、不持密钥、不直写 Notes 库。
//
// 本文件 = **首片 A 的核心层**（`DoyahRetroCore/GenerationTrigger.swift`）的**界面接线**，四件事：
//   ① 手动「生成本期」按钮 ⇒ 调 `GenerationTrigger.trigger(...)`（默认执行器 `ProcessGenerationExecuting`）；
//   ② **定时三键**（周期 / 时刻 / 开关）落 `UserDefaults`（键名唯一出处 = `GenerationSettingKey`）；
//   ③ **缺期提示**（不静默）：读扫描根同级的 `missed-periods.jsonl`，本月有缺期 ⇒ 给一行可见提示；
//   ④ 生成**成功**后 ⇒ 调既有重扫入口（`ReportListModel.reload()`），**不新建第二套扫描**。
//
// 硬口径（照派单「组长定夺」逐条落）：
//   · **调度器必须可注入**：定义 `GenerationScheduling` 协议 + 默认实现 `TimerGenerationScheduler`
//     （内部用 `Timer`）—— **模型只持 `any GenerationScheduling`，从不直接持 `Timer` 运行实例**；
//     单元测试**一律注入桩**，不真等时间、不真跑生成侧。
//   · **入口与落点一律复用 A**：执行走 `GenerationTrigger.trigger(...)`；缺期落点只用
//     `GenerationSpec.missedPeriodLogURL(nextToScanRoot:)`。**本层不 spawn 进程、不自造第二个缺期落点。**
//   · **只读边界（如实登记）**：本层对**周报包目录**零写调用 —— 读 `missed-periods.jsonl` 只是**读**；
//     三键落的是 `UserDefaults`（应用配置面，**不在**任何周报包目录内）⇒ 判据 `Tools/check-readonly.py`
//     的扫描面里**一个写记号都没有** —— 判据本体逐行扫写 API 记号（不做注释剔除），本层一处都不出现。
//   · **GUI 框架只许出现在视图层**：本文件 `import` = `Combine` / `Foundation` / `SwiftUI`（领域层零 GUI 符号）。

// MARK: - 定时三键（`UserDefaults` · 唯一出处）

/// 本地定时触发的**三个设置键**（周期 / 时刻 / 开关）—— 三个键名**各只在这里写一次**
/// （机械判据：`Plugins/Retro/Views` 下各命中 1；别处一律从这三个常量取，
/// **不各自再写一份键名字面量**）。
public enum GenerationSettingKey {
    /// 周期（存 `GenerationCycle.rawValue`）。
    public static let cycle = "doyahRetroGenerationCycle"
    /// 时刻（`HH:mm`）。
    public static let timeOfDay = "doyahRetroGenerationTimeOfDay"
    /// 开关（本地定时触发是否启用）。
    public static let enabled = "doyahRetroGenerationEnabled"
}

/// 本地定时触发的**周期**。
public enum GenerationCycle: String, CaseIterable, Hashable {
    /// 每天。
    case daily
    /// 每周（与生成侧「每周一」排程同口径）。
    case weekly

    /// 界面上的一行标签。
    public var label: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        }
    }
}

// MARK: - 期号（「生成本期」按当前周取）

/// 期号（`IR-05` 不变量 1 的 ISO 周形态，如 `2026-W41`）。
public enum GenerationPeriod {
    /// 某一时刻所属的 ISO 周期号（`YYYY-Www`）。
    public static func isoWeek(of date: Date, calendar: Calendar = GenerationPeriod.isoCalendar) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// ISO 周口径的日历（周一为首日 · 至少 4 天落在第一周）。
    public static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }
}

// MARK: - 到点计算（纯函数 · 注入 `now` / `calendar` 即可复算）

/// 由「周期 + 时刻」算**下一次到点** —— 纯函数（不读时钟、不读环境）。
public enum GenerationTimer {
    /// 缺省时刻（`HH:mm`）= 08:30（与生成侧周排程同口径）。
    public static let defaultTimeOfDayText = "08:30"

    /// 下一次到点时刻：`now` 之后**第一个**符合「周期 + 时刻」的时刻。
    ///
    /// - 每天 ⇒ 今天 / 明天的那一时刻；
    /// - 每周 ⇒ 下一个**周一**的那一时刻（周一 = `.weekday == 2`，ISO 口径）。
    public static func nextFire(
        cycle: GenerationCycle,
        timeOfDay: String,
        now: Date,
        calendar: Calendar = GenerationPeriod.isoCalendar
    ) -> Date {
        let (hour, minute) = parse(timeOfDay) ?? (8, 30)
        var candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        switch cycle {
        case .daily:
            if candidate <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
        case .weekly:
            while calendar.component(.weekday, from: candidate) != calendar.firstWeekday {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            if candidate <= now {
                candidate = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) ?? candidate
            }
        }
        return candidate
    }

    /// `HH:mm` ⇒ (时, 分)；非法 ⇒ `nil`（非法输入不回退，交由调用方取缺省）。
    static func parse(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }
}

// MARK: - 调度（可注入）

/// **可注入的调度协议**：触发面**模型只认这个协议，从不直接持 `Timer` 运行实例**。
///
/// 单元测试**一律注入桩**（记安排 / 手动触发），**不真等时间**。
public protocol GenerationScheduling: AnyObject {
    /// 安排**一次**到点回调（重复调用覆盖上一次，不叠加）。
    func schedule(nextFire: Date, onFire: @escaping @MainActor () -> Void)
    /// 取消已安排的到点回调（没有 ⇒ 无操作）。
    func cancel()
}

/// 默认调度器 = `GenerationScheduling` 的一个实现（内部用 `Timer` 到点回调）。
///
/// **模型从不持它的 `Timer`** —— `GenerationTriggerModel` 只持 `any GenerationScheduling`
/// （判据 ⑤：单测恒注入桩，本类型的 `Timer` 在测试里一次都不被建）。
public final class TimerGenerationScheduler: GenerationScheduling {
    private var timer: Timer?

    public init() {}

    public func schedule(nextFire: Date, onFire: @escaping @MainActor () -> Void) {
        cancel()
        let interval = max(0, nextFire.timeIntervalSinceNow)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in onFire() }
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 缺期日志读面（只读 · 落点复用 A）

/// `missed-periods.jsonl` 的**一行**（三键与核心层 `MissedPeriodRecord` 同名：期号 / 结果 / 时刻）。
public struct MissedPeriodEntry: Equatable {
    public let period: String
    public let result: String
    public let timestamp: String

    public init(period: String, result: String, timestamp: String) {
        self.period = period
        self.result = result
        self.timestamp = timestamp
    }

    /// 时刻（ISO 8601 带时区）⇒ `Date`；解析不了 ⇒ `nil`。
    public var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}

/// 缺期日志的**只读**读面：读扫描根**同级**文件 ⇒ 逐行解析（坏行跳过、**不崩**）。
///
/// 落点**唯一出处** = `GenerationSpec.missedPeriodLogURL(nextToScanRoot:)`（核心层）——本层不自造第二处。
public enum MissedPeriodLogReader {
    /// 逐行读缺期日志（文件不在 / 读不出 ⇒ 空数组）。
    public static func read(nextToScanRoot scanRoot: URL) -> [MissedPeriodEntry] {
        let url = GenerationSpec.missedPeriodLogURL(nextToScanRoot: scanRoot)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parse)
    }

    /// **本月**缺期（按记录的「时刻」与 `reference` 落在同一年月）。
    public static func thisMonth(
        nextToScanRoot scanRoot: URL,
        reference: Date,
        calendar: Calendar = GenerationPeriod.isoCalendar
    ) -> [MissedPeriodEntry] {
        read(nextToScanRoot: scanRoot).filter { entry in
            guard let date = entry.date else { return false }
            return calendar.isDate(date, equalTo: reference, toGranularity: .month)
        }
    }

    /// 一行 JSONL ⇒ 一条记录（缺键 / 坏 JSON ⇒ `nil`，跳过不崩）。
    static func parse(_ line: Substring) -> MissedPeriodEntry? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let object = value as? [String: Any],
              let period = object["期号"] as? String,
              let result = object["结果"] as? String,
              let timestamp = object["时刻"] as? String
        else { return nil }
        return MissedPeriodEntry(period: period, result: result, timestamp: timestamp)
    }
}

// MARK: - 触发面模型（可观察）

/// 触发面的**模型**：定时三键设置 + 一次触发的确定结果 + 缺期提示 + 生成后重扫回调。
///
/// - 手动「生成本期」⇒ `generateNow()`（走核心层 `GenerationTrigger.trigger`）；
/// - 定时 ⇒ `setEnabled(true)` 起安排；开关关 / 周期·时刻改 ⇒ 重排（**同一协议**，桩可注入）；
/// - 缺期提示 ⇒ `refreshMissedPeriodNotice()`（**不静默**）；
/// - 生成**成功** ⇒ `onGenerated()`（**复用既有重扫入口**，不新建第二套扫描）。
///
/// 依赖**全部可注入**：`defaults` / `executing` / `scheduler` / `now` / `onGenerated` —— 单测一律注入桩，
/// 从不真跑生成侧、从不真等时间。
@MainActor
public final class GenerationTriggerModel: ObservableObject {

    // MARK: 设置（定时三键）

    /// 周期。
    @Published public private(set) var cycle: GenerationCycle
    /// 时刻（`HH:mm`）。
    @Published public private(set) var timeOfDay: String
    /// 开关。
    @Published public private(set) var isScheduledEnabled: Bool

    // MARK: 读数（结果 / 提示 · 都不静默）

    /// 最近一次触发的人读一行（没触发过 ⇒ `nil`）。
    @Published public private(set) var lastOutcomeLine: String?
    /// **本月缺期**的可见提示（没有 ⇒ `nil`）。
    @Published public private(set) var missedPeriodNotice: String?
    /// 调度器安排的下一次到点（没安排 ⇒ `nil`）。
    @Published public private(set) var nextFireDate: Date?

    // MARK: 依赖（全可注入）

    /// 扫描根（其直接子目录即各期包；缺期落点 = 其**同级**）。
    public let scanRoot: URL
    private let defaults: UserDefaults
    private let executing: GenerationExecuting
    private let scheduler: GenerationScheduling
    private let now: () -> Date
    private let onGenerated: @MainActor () -> Void

    public init(
        scanRoot: URL,
        defaults: UserDefaults = .standard,
        executing: GenerationExecuting = ProcessGenerationExecuting(),
        scheduler: GenerationScheduling = TimerGenerationScheduler(),
        now: @escaping () -> Date = Date.init,
        onGenerated: @escaping @MainActor () -> Void = {}
    ) {
        self.scanRoot = scanRoot
        self.defaults = defaults
        self.executing = executing
        self.scheduler = scheduler
        self.now = now
        self.onGenerated = onGenerated

        // 三键读出（缺省值 = 每周 · 08:30 · 关）。
        let storedCycle = defaults.string(forKey: GenerationSettingKey.cycle) ?? ""
        self.cycle = GenerationCycle(rawValue: storedCycle) ?? .weekly
        self.timeOfDay = defaults.string(forKey: GenerationSettingKey.timeOfDay) ?? GenerationTimer.defaultTimeOfDayText
        self.isScheduledEnabled = defaults.bool(forKey: GenerationSettingKey.enabled)

        refreshMissedPeriodNotice()
        if isScheduledEnabled { scheduleNext() }
    }

    // MARK: 手动「生成本期」

    /// 手动「生成本期」⇒ 跑一次触发生成；**成功**后调重扫入口（`onGenerated`）。
    @discardableResult
    public func generateNow() -> GenerationOutcome {
        let outcome = GenerationTrigger.trigger(
            period: currentPeriod,
            scanRoot: scanRoot,
            executing: executing,
            now: now
        )
        lastOutcomeLine = outcome.description
        if case .success = outcome { onGenerated() }
        refreshMissedPeriodNotice()
        return outcome
    }

    /// 「本期」期号 = **当前周**的 ISO 周（如 `2026-W41`）。
    public var currentPeriod: String {
        GenerationPeriod.isoWeek(of: now())
    }

    // MARK: 定时三键（写回 `UserDefaults` + 重排）

    /// 设周期（写回 `UserDefaults`；开着定时 ⇒ 重排到点）。
    public func setCycle(_ cycle: GenerationCycle) {
        self.cycle = cycle
        defaults.set(cycle.rawValue, forKey: GenerationSettingKey.cycle)
        rescheduleIfEnabled()
    }

    /// 设时刻（`HH:mm`；写回 `UserDefaults`；开着定时 ⇒ 重排到点）。
    public func setTimeOfDay(_ text: String) {
        timeOfDay = text
        defaults.set(text, forKey: GenerationSettingKey.timeOfDay)
        rescheduleIfEnabled()
    }

    /// 设开关（写回 `UserDefaults`）：开 ⇒ 安排到点；关 ⇒ 取消安排。
    public func setEnabled(_ enabled: Bool) {
        isScheduledEnabled = enabled
        defaults.set(enabled, forKey: GenerationSettingKey.enabled)
        if enabled { scheduleNext() } else { cancelSchedule() }
    }

    // MARK: 缺期提示（非静默）

    /// 重读缺期日志 ⇒ **本月有缺期就给一行可见提示**（没有 ⇒ 清空）。
    public func refreshMissedPeriodNotice() {
        let entries = MissedPeriodLogReader.thisMonth(nextToScanRoot: scanRoot, reference: now())
        guard let latest = entries.last else {
            missedPeriodNotice = nil
            return
        }
        missedPeriodNotice = "本月缺期 \(entries.count) 条 —— 最近「\(latest.period)」（\(latest.result)）；"
            + "见扫描根同级 missed-periods.jsonl"
    }

    // MARK: 调度内部

    /// 按「周期 + 时刻」安排下一次到点（到点回调 = 同一条 `generateNow()` 入口）。
    private func scheduleNext() {
        let date = GenerationTimer.nextFire(cycle: cycle, timeOfDay: timeOfDay, now: now())
        nextFireDate = date
        scheduler.schedule(nextFire: date) { [weak self] in
            self?.fireScheduled()
        }
    }

    /// **到点**：跑一次生成，**再排下一次**。
    ///
    /// 「周期」的语义就是**每天 / 每周重复**（不是一次性）—— `GenerationScheduling.schedule`
    /// 只承担**一次**到点回调（重复调用覆盖上一次、不叠加），**重排由本模型承担**：到点后
    /// 按**当前三键**重算下一次并再排；若期间用户关了开关 ⇒ `isScheduledEnabled == false` ⇒
    /// 不再重排（`setEnabled(false)` 已 `cancel()`）。
    private func fireScheduled() {
        generateNow()
        if isScheduledEnabled { scheduleNext() }
    }

    /// 取消安排（开关关 ⇒ 到点清零）。
    private func cancelSchedule() {
        scheduler.cancel()
        nextFireDate = nil
    }

    /// 开着定时 ⇒ 按当前三键重排（周期 / 时刻改动后调用）。
    private func rescheduleIfEnabled() {
        if isScheduledEnabled { scheduleNext() }
    }
}

// MARK: - 视图（生成区 = 手动按钮 + 定时三键 + 缺期提示 + 结果行）

/// 触发面**视图**：手动「生成本期」按钮 + 定时三键（周期 / 时刻 / 开关）+ 缺期提示（**不静默**）
/// + 最近一次结果一行。
///
/// 视图**只做画**：所有判定（三态 / 缺期 / 到点）都在模型与核心层，视图不自行 spawn 进程、不判盘。
public struct GenerationTriggerView: View {
    @ObservedObject private var model: GenerationTriggerModel

    public init(model: GenerationTriggerModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("生成本期") { model.generateNow() }
                if let next = model.nextFireDate {
                    Text("下次到点 \(Self.text(next))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("定时触发", isOn: Binding(
                get: { model.isScheduledEnabled },
                set: { model.setEnabled($0) }
            ))

            HStack(spacing: 8) {
                Picker("周期", selection: Binding(
                    get: { model.cycle },
                    set: { model.setCycle($0) }
                )) {
                    ForEach(GenerationCycle.allCases, id: \.self) { cycle in
                        Text(cycle.label).tag(cycle)
                    }
                }
                .frame(maxWidth: 150)

                TextField("时刻 HH:mm", text: Binding(
                    get: { model.timeOfDay },
                    set: { model.setTimeOfDay($0) }
                ))
                .frame(maxWidth: 110)
            }
            .font(.caption)

            if let notice = model.missedPeriodNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let line = model.lastOutcomeLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 到点的一行文本（`yyyy-MM-dd HH:mm`）。
    private static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
