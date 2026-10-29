import AppKit
import CoreImage
import DoyahCore
import SwiftUI

/// 「用 QQ 扫码接入」（`FR-AGT-LINK-CHAN-003`）。
///
/// 存在的理由：QQ 机器人的正规接入方式是**手机 QQ 扫码**（腾讯官方连接器扫码后直接返回
/// AppID / AppSecret / 主人 openid），让用户去别处抄 AppSecret 是把麻烦推给用户。
///
/// 三条边界：
/// 1. 判断全在 `AgentIMQRLogin`（Core，有判据）；这里只管起进程、读行、画图。
/// 2. 关窗 / 取消**必杀子进程**（否则连接器会在后台继续轮询二维码）。
/// 3. 桥不可用时如实说原因（没装 node / 找不到连接器），不假装在等扫码。
struct QQQRLoginSheet: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    /// 成功后的回调：宿主拿到 AppID / AppSecret 去落库（这里不自己写凭据）。
    var onSucceed: (String, String) -> Void

    @StateObject private var controller = QQLoginController()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L(.agentIMQRTitle))
                .font(Theme.font(.title))
            Text(L(.agentIMQRHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.text(.secondary).opacity(0.08))
                    .frame(width: 232, height: 232)
                if let image = controller.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 208, height: 208)
                        .accessibilityIdentifier("agent-im-qr-image")
                } else {
                    ProgressView()
                        .accessibilityIdentifier("agent-im-qr-spinner")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(controller.statusLine)
                .font(Theme.font(.caption))
                .foregroundStyle(controller.hasFailed ? Theme.status(.warning) : Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("agent-im-qr-status")

            HStack(spacing: Spacing.m) {
                DialogActionButton(systemName: "arrow.clockwise", title: L(.agentIMQRRestart)) {
                    controller.restart()
                }
                .disabled(!controller.state.allowsRestart)
                Spacer()
                DialogActionButton(systemName: "xmark", title: L(.commonClose), role: .cancel) {
                    controller.cancel()
                    dismiss()
                }
            }
        }
        .padding(Spacing.l)
        .frame(width: 420)
        .onAppear { controller.start(bridgePath: QQLoginController.defaultBridgePath) }
        .onDisappear { controller.cancel() }
        .onChange(of: controller.state) { _, state in
            guard let credentials = AgentIMQRLogin.credentials(from: state) else { return }
            onSucceed(credentials.appID, credentials.appSecret)
            dismiss()
        }
    }
}

/// 起桥、读行、切状态。**只做这三件事**，别的都在 Core。
final class QQLoginController: ObservableObject {

    @Published private(set) var state: AgentIMQRLoginState = .idle
    @Published private(set) var qrImage: NSImage?

    private var process: Process?
    private var buffer = Data()

    var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var statusLine: String {
        switch state {
        case .idle: return L(.agentIMQRStarting)
        case .showing: return L(.agentIMQRWaiting)
        case .expired: return L(.agentIMQRExpired)
        case .succeeded: return L(.agentIMQRDone)
        case .failed(let reason): return reason
        }
    }

    /// 桥脚本位置：先看环境变量，再看「应用旁边的仓库」，最后看本机开发路径。
    static var defaultBridgePath: String {
        if let override = ProcessInfo.processInfo.environment["DOYAH_QQ_BRIDGE"], !override.isEmpty {
            return override
        }
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            // 先找**打进包里的**（正式安装就靠这一条）
            (Bundle.main.resourceURL ?? bundleURL).appendingPathComponent("qq-qr-bridge.mjs"),
            // 再找应用旁边的仓库（开发期）
            bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(AgentIMQRLogin.bridgeRelativePath),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("dev/doyah/lead/studio/" + AgentIMQRLogin.bridgeRelativePath),
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return candidates[0].path
    }

    func start(bridgePath: String) {
        cancel()
        state = .idle
        qrImage = nil
        buffer.removeAll()

        let nodePath = Self.nodePath()
        guard let nodePath else {
            state = .failed(reason: L(.agentIMQRNoNode))
            return
        }
        guard FileManager.default.fileExists(atPath: bridgePath) else {
            state = .failed(reason: L(.agentIMQRNoBridge))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = AgentIMQRLogin.launchArguments(bridgePath: bridgePath)
        process.environment = AgentIMQRLogin.environment(connectorEntry: nil,
                                                         inherited: ProcessInfo.processInfo.environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()   // 桥的噪声不进界面；失败原因走 JSON 事件

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                // 桥自己退了还没拿到结果 ⇒ 不能一直转圈。
                if !self.state.isTerminal {
                    self.state = .failed(reason: L(.agentIMQRExited, Int64(finished.terminationStatus)))
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            state = .failed(reason: error.localizedDescription)
        }
    }

    func restart() {
        start(bridgePath: Self.defaultBridgePath)
    }

    /// 取消 = 杀子进程（桥收到 SIGTERM 会释放连接器，不留后台轮询）。
    func cancel() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            guard let event = AgentIMQRLogin.parse(line: line) else { continue }
            apply(event)
        }
    }

    private func apply(_ event: AgentIMQREvent) {
        state = AgentIMQRLogin.next(state, event: event)
        switch event {
        case .qr(let url):
            qrImage = Self.makeQRImage(url)
        case .succeeded:
            qrImage = nil
            cancel()
        case .failed:
            qrImage = nil
            cancel()
        case .expired:
            break
        }
    }

    static func makeQRImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width,
                                                      height: scaled.extent.height))
    }

    /// node 在图形应用里的 PATH 往往不含 `/opt/homebrew/bin`，所以按固定顺序找。
    static func nodePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
