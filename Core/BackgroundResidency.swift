import Foundation

/// 「关窗之后进程还该不该活着」（`NFR-ALL-GATE-REL-006`）的**纯决策层**。
///
/// 条文：桌面端有「随系统启动」开关（可关）；开启后登录即由本进程常驻并拉起 IM 通道，
/// **无需人工打开主窗口**；**关窗不终止通道**。
///
/// 这里只回答两个问题：关掉最后一个窗口时该终止吗？要不要在菜单栏留一个常驻入口？
/// 真正去拉 IM 通道、去建状态项由调用方做 —— 这样口径能在任一端被同一批用例盯住。
public struct ResidencyInputs: Equatable, Sendable {
    /// 用户是否勾了「随系统启动」。
    public let launchAtLogin: Bool
    /// IM 通道是否已启用（没配凭据的通道不算「该常驻」）。
    public let imChannelEnabled: Bool
    /// 用户是否按了「退出」（显式退出永远优先，常驻不许抢）。
    public let explicitQuit: Bool

    public init(launchAtLogin: Bool, imChannelEnabled: Bool, explicitQuit: Bool = false) {
        self.launchAtLogin = launchAtLogin
        self.imChannelEnabled = imChannelEnabled
        self.explicitQuit = explicitQuit
    }
}

public enum ResidencyOutcome: Equatable, Sendable {
    /// 关掉最后一个窗口就退出（默认行为）。
    case terminate
    /// 关窗不退出：进程留在后台，通道继续跑。
    case keepRunning
}

public enum BackgroundResidency {
    /// 关掉最后一个窗口时该不该终止。
    ///
    /// 三条硬规则：
    /// 1. **显式退出优先**：用户按「退出」⇒ 终止（哪怕开关开着）。
    /// 2. **两个条件都成立才常驻**：开关开着 **且** IM 通道启用。
    ///    只开开关、通道没配 ⇒ 留着进程只是白占内存，也违反「常驻是为了通道在线」的初衷。
    /// 3. **默认不常驻**：没开开关 ⇒ 关窗即退，与用户预期一致。
    public static func onLastWindowClosed(_ inputs: ResidencyInputs) -> ResidencyOutcome {
        if inputs.explicitQuit { return .terminate }
        return (inputs.launchAtLogin && inputs.imChannelEnabled) ? .keepRunning : .terminate
    }

    /// 菜单栏要不要留常驻入口（只有真常驻时才留，否则会多出一个「点了没反应」的图标）。
    public static func wantsStatusItem(_ inputs: ResidencyInputs) -> Bool {
        onLastWindowClosed(inputs) == .keepRunning
    }

    /// 一句话状态，供设置面板显示；`nil` 表示不常驻。
    public static func statusLine(_ inputs: ResidencyInputs) -> String? {
        guard onLastWindowClosed(inputs) == .keepRunning else { return nil }
        return "常驻中：关窗不退出，IM 通道继续在线"
    }
}
