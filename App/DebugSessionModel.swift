import Foundation
import SwiftUI
import DoyahCore

/// 调试会话的状态机（`FR-STD-WS-TOOL-003` 的界面半）。
///
/// 分工：判定（断点账本 `DebugBreakpointSet`、分帧与断点复验 `DAPCore`、真正的 DAP 往返
/// `DAPSession`）全在 Core；这里只把**阻塞的** `DAPSession` 搬到后台线程，再把结果搬回主线程 ——
/// 一条规矩：**界面上不出现「正在调试」这种没有读完数的状态**，停住就报停在哪一行、
/// 报错就报是缺适配器还是超时（`DAPClient.Failure` 分四档，不糊成一句 debug failed）。
@MainActor
final class DebugSessionModel: ObservableObject {

    enum Phase: Equatable {
        /// 没开始。
        case idle
        /// 适配器起来了、还没停下来。
        case running
        /// 停在某文件某行（1 起）。
        case stopped(file: String, line: Int)
        /// 程序跑完了。
        case finished(reason: String)
        /// 起不来 / 中途失败（原样带原因）。
        case failed(reason: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var variables: [(name: String, value: String)] = []
    @Published private(set) var log: [String] = []
    /// 断点账本（行号槽点一下、面板里删一条，都落这一份）。
    @Published var breakpoints = DebugBreakpointSet()
    /// 要调试的程序（路径；从「调试当前文件」进来时自动填）。
    @Published var program = ""
    /// DAP 适配器路径（缺省按本机有的那个挑；找不到时如实报缺适配器）。
    @Published var adapterPath = DebugSessionModel.defaultAdapterPath

    private var session: DAPSession?
    private var threadID = 0

    /// 本机默认适配器：Xcode 自带的 `lldb-dap` 优先，其次 `/usr/bin/lldb-dap`。
    static var defaultAdapterPath: String {
        let candidates = [
            "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/Resources/lldb-dap",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap",
            "/usr/bin/lldb-dap"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[2]
    }

    var isBusy: Bool {
        switch phase {
        case .running: return true
        default: return false
        }
    }

    /// 点一下断点（行号 1 起）。
    func toggleBreakpoint(line: Int, in path: String) {
        let on = breakpoints.toggle(path: path, line: line)
        append(on ? L(.debugBreakpointAdded, line) : L(.debugBreakpointRemoved, line))
    }

    /// 开始调试（阻塞部分在后台线程跑）。
    func start() {
        let target = program.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            phase = .failed(reason: L(.debugNoProgram))
            return
        }
        guard phase != .running else { return }
        let adapter = adapterPath
        let map = breakpoints.dapMap()
        phase = .running
        variables = []
        append(L(.debugStarting, target))
        Task.detached(priority: .userInitiated) { [weak self] in
            let client = DAPClient(adapterPath: adapter)
            let session = DAPSession(client: client)
            do {
                let outcome = try session.runUntilStop(program: target, breakpoints: map)
                await MainActor.run {
                    self?.session = session
                    self?.apply(outcome, session: session)
                }
            } catch {
                await MainActor.run {
                    // 适配器没起来就别 disconnect：`request` 要等超时，会把「立刻失败」拖成 5 秒。
                    if client.isRunning { session.disconnect() }
                    self?.phase = .failed(reason: Self.describe(error))
                    self?.append(Self.describe(error))
                }
            }
        }
    }

    /// 继续 / 步过 / 步入 / 步出（四条都走 `DAPSession.step`）。
    func step(_ kind: DAPSession.Step) {
        guard let session, !isBusy else { return }
        let thread = threadID
        phase = .running
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let outcome = try session.step(kind, threadId: thread)
                await MainActor.run { self?.apply(outcome, session: session) }
            } catch {
                await MainActor.run {
                    self?.phase = .failed(reason: Self.describe(error))
                }
            }
        }
    }

    func stop() {
        session?.disconnect()
        session = nil
        phase = .idle
        variables = []
        append(L(.debugStoppedByUser))
    }

    // MARK: - 内部

    private func apply(_ outcome: DAPSession.Outcome, session: DAPSession) {
        switch outcome {
        case .stopped(let location):
            threadID = location.threadId
            phase = .stopped(file: location.file, line: location.line)
            append(L(.debugStoppedAt, location.file, location.line))
            // 变量读不到就如实空着（`try?`）：停住这件事本身已经成立，不该因为变量面板失败而报错。
            if let values = try? session.variables(threadId: location.threadId) {
                variables = values.keys.sorted().map { ($0, values[$0] ?? "") }
            }
        case .terminated(let reason):
            phase = .finished(reason: reason)
            append(L(.debugFinished, reason))
        case .timedOut(let seconds):
            phase = .failed(reason: L(.debugTimedOut, seconds))
            append(L(.debugTimedOut, seconds))
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    /// 错误说人话：四种失败分开报（缺适配器 / 启动即退 / 超时 / 对端关闭）。
    static func describe(_ error: Error) -> String {
        if let failure = error as? DAPClient.Failure {
            switch failure {
            case .adapterNotFound(let path): return L(.debugAdapterMissing, path)
            case .adapterExited(let code): return L(.debugAdapterExited, Int(code))
            case .timeout(let command, let seconds): return L(.debugTimeout, command, seconds)
            case .closed(let command): return L(.debugClosed, command)
            case .protocolBroken(let why): return L(.debugProtocolBroken, why)
            }
        }
        return ErrorPresenter.message(for: error)
    }
}
