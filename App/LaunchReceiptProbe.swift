import AppKit
import Foundation
import SwiftUI

import DoyahCore
import DoyahPlatform

/// 冷启动收据探针（`NFR-ALL-GATE-PERF-001`：冷启动到可交互 ≤ 2 s）。
///
/// ## 它做什么
///
/// 只在一个环境变量开着时工作（`DOYAH_LAUNCH_RECEIPT=<落盘路径>`，与
/// `DOYAH_MENU_DUMP` 同一套「取证才开」的纪律）：`DoyahStudioApp.init` 第一行打起点
/// （**内核**给的进程创建时刻，见 `ProcessStartTime`），根视图出现后过一圈运行循环，
/// 把一份 `LaunchReceipt` 原子写到那个路径，然后什么都不做。
///
/// 没开这个变量时每个函数都在第一个 guard 里返回 —— 正常启动路径上不测量、不写盘。
///
/// ## 为什么终点是「根视图出现 + 一圈运行循环」
///
/// `onAppear` 触发时视图树已经建好、接线（对话循环、端点、配额回写…）也已跑完，
/// 再让事件循环转一圈 = 这一帧真的画出去了。**不含** GPU 上屏合成与首次使用时的
/// 图标/字体磁盘缓存冷态差异 —— 那两条记在台账的「未覆盖」里。
///
/// ## 负例开关
///
/// `DOYAH_LAUNCH_ARTIFICIAL_DELAY_MS=<毫秒>`：在打终点之前先睡这么久。
/// 判据要能证明「超阈值必须判红」，没有这个开关就只能靠改台账数字去演 ——
/// 那样证明的是台账，不是判据。它只在收据探针开着时才生效。
enum LaunchReceiptProbe {

    /// 收据落盘路径（开着才测）。
    static let environmentKey = "DOYAH_LAUNCH_RECEIPT"
    /// 人为拖慢（负例用）。
    static let artificialDelayKey = "DOYAH_LAUNCH_ARTIFICIAL_DELAY_MS"
    /// 构建口径（可空；Release 包由构建脚本设，便于台账写清「这一次量的是哪个包」）。
    static let buildFlavorKey = "DOYAH_BUILD_FLAVOR"

    private static let lock = NSLock()
    private static var timeline: LaunchTimeline?
    private static var receiptURL: URL?
    private static var startFellBackToFirstLine = false

    static var isEnabled: Bool {
        (ProcessInfo.processInfo.environment[environmentKey] ?? "").isEmpty == false
    }

    /// `DoyahStudioApp.init()` 的**第一句**调用。
    static func begin() {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return }
        let processStart = ProcessStartTime.current()
        let start = processStart ?? Date()
        lock.lock()
        defer { lock.unlock() }
        timeline = LaunchTimeline(processStart: start)
        receiptURL = URL(fileURLWithPath: path)
        startFellBackToFirstLine = (processStart == nil)
    }

    static func mark(_ phase: LaunchTimeline.Phase) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        timeline?.mark(phase)
    }

    /// 根视图出现时调用一次（可重入：`onAppear` 会因主题 / 语言切换再跑）。
    static func markRootViewAppeared() {
        guard isEnabled else { return }
        // 负例开关：先睡，再打终点 —— 于是「这一遍慢」既体现在收据里，也体现在外部墙钟上。
        if let raw = ProcessInfo.processInfo.environment[artificialDelayKey],
           let milliseconds = Double(raw), milliseconds > 0, milliseconds.isFinite {
            Thread.sleep(forTimeInterval: milliseconds / 1000)
        }

        lock.lock()
        guard var timeline, let url = receiptURL else {
            lock.unlock()
            return
        }
        timeline.mark(.rootViewAppeared)
        self.timeline = timeline
        let fellBack = startFellBackToFirstLine
        lock.unlock()

        let fallbackNote = fellBack ? "processStart=firstLine" : nil
        let buildLabel = [ProcessInfo.processInfo.environment[buildFlavorKey], fallbackNote]
            .compactMap { $0 }
            .joined(separator: ";")
        do {
            let receipt = try LaunchReceipt(
                timeline: timeline,
                build: buildLabel.isEmpty ? nil : buildLabel
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try receipt.encoded().write(to: url, options: .atomic)
        } catch {
            // 写不下去不弹框、不打断用户：收据是取证件，缺失时测量脚本会如实报「没收到」。
            StartupLog.write("启动收据写失败：\(error)")
        }
    }
}

/// 挂在根视图上的那一枚零尺寸标记：它一出现就说明根视图真的建好并首帧画了。
struct LaunchReceiptMarker: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                // 让事件循环转一圈：`onAppear` 里的 `DispatchQueue.main.async` 排在首帧之后。
                DispatchQueue.main.async {
                    LaunchReceiptProbe.markRootViewAppeared()
                }
            }
    }
}
