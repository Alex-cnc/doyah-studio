import Foundation

/// 「登录即启动」的**兜底通道**：`~/Library/LaunchAgents/<label>.plist`。
///
/// 为什么需要它：`SMAppService.mainApp` 要求应用有正规签名（Developer ID / App Store）。
/// 本机装的是 ad-hoc 签名的 beta 包（`TeamIdentifier=not set`，位置在 `~/Applications`），
/// `SMAppService.status` 返回 `.notFound` ⇒ 决策层报 `.unavailable`，开关永远点不亮。
/// 而主人的真实诉求是「系统更新重启后 QQ 通道别断」（2026-11-16 真机事实），
/// LaunchAgent 是同一台机器上未签名应用唯一可靠的等价做法。
///
/// 边界（都要如实报，不许假装成功）：
/// 1. 只对**当前这个可执行文件路径**生效；应用换位置（重建到别的目录）要重写一次。
/// 2. 文件在用户的 `~/Library/LaunchAgents` 里 —— 可删、可审计，卸载应用时一并清掉。
/// 3. 它只负责「登录即启动」；常驻与关窗后不断线由 `BackgroundResidency` 管。
public enum LaunchAgentLoginItem {

    /// 固定的 label（与 bundle id 一致，便于一眼认出是谁的）。
    public static let label = "studio.doyah.DoyahStudio.launch-at-login"

    /// plist 正文（纯函数：可被用例逐字段判，不碰磁盘）。
    ///
    /// 用 `PropertyListSerialization` 生成，不手写 XML 头：手写那版把
    /// `-//Apple//DTD PLIST 1.0//EN` 当成英文展示文案塞进了 Core（棘轮 B 当场报红），
    /// 而且路径里的 `&` `<` `>` 还得自己转义 —— 交给序列化器一次就对了。
    public static func plist(executablePath: String, label: String = label) -> String {
        let body: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: body,
                                                             format: .xml,
                                                             options: 0),
              let xml = String(data: data, encoding: .utf8) else {
            return ""
        }
        return xml
    }

    /// plist 该放哪（`~/Library/LaunchAgents/<label>.plist`）。
    public static func url(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           label: String = label) -> URL {
        home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    /// 当前是否已登记（判据用；不猜系统状态）。
    public static func isInstalled(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 写/删。失败一律 `throws`，调用方把原因说出来，不许静默。
    public static func install(executablePath: String, at url: URL = url()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(plist(executablePath: executablePath).utf8).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    public static func remove(at url: URL = url()) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
