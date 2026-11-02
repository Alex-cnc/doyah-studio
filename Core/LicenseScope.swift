import Foundation

/// **授权范围口径**（`FR-STD-ALL-LIC-004`）：一份许可证管哪几块、哪几块**根本不归它管**。
///
/// 两条拍板口径落成代码，不落在文档里（文档会漂，代码不会）：
///
/// 1. **桌面三块是一套**：工作区 / 数据库 / 笔记共用同一套授权，没有「只买数据库」「只买笔记」
///    这种单块商品 —— `LicenseEdition.from` 早已把「只授权一块」判成无效档位，这里把同一句话
///    落到**面**上：`LicenseCapabilities` 的位只许来自桌面三块（`onlyDesktopSurfaces`），
///    多出第四块就是「我们不卖的东西」，判红。
/// 2. **移动端不在管辖范围**：`Doyah Notes` 的 iOS / 安卓 / 鸿蒙版**不读许可证、不降级、不提一句**。
///    所以这里给移动端**不留能力位**（位只有 1 / 2 / 4），`governs(.mobileNotes)` 恒 `false`，
///    `requiredCapability(for: .mobileNotes)` 恒 `nil`（nil 是「不归授权管」，不是「没授权」）。
///
/// 判据：`Tests/LicenseScopeTests` 逐条钉住上面两句；给移动端加一个能力位、或让 `governs`
/// 对移动端返回 true ⇒ 那组断言必须判红。
public enum LicenseSurface: String, CaseIterable, Sendable {
    case desktopWorkspaces
    case desktopDatabase
    case desktopNotes
    case mobileNotes

    public var isDesktop: Bool {
        switch self {
        case .desktopWorkspaces, .desktopDatabase, .desktopNotes: return true
        case .mobileNotes: return false
        }
    }

    public var isMobile: Bool { !isDesktop }

    /// 这个面对应的能力位。**移动端没有位**（`nil`）—— 不建位，就没有「没授权」这种状态可言。
    public var capability: LicenseCapabilities? {
        switch self {
        case .desktopWorkspaces: return .workspaces
        case .desktopDatabase: return .database
        case .desktopNotes: return .notes
        case .mobileNotes: return nil
        }
    }
}

public enum LicenseScope {

    /// 桌面三块（一份许可证里的一套）。
    public static let desktopSet: [LicenseSurface] = [.desktopWorkspaces, .desktopDatabase, .desktopNotes]

    /// 不归授权管的那些面（只有移动端；将来若加别的端也在这里表态）。
    public static let ungovernedSurfaces: [LicenseSurface] = [.mobileNotes]

    /// 这个面归不归授权管。**移动端恒 false**：不读许可证就不存在「降级」。
    public static func governs(_ surface: LicenseSurface) -> Bool { surface.isDesktop }

    /// 这个面要哪个能力位（移动端 `nil` = 不归授权管，不是「没授权」）。
    public static func requiredCapability(for surface: LicenseSurface) -> LicenseCapabilities? {
        surface.capability
    }

    /// 一份许可证现在开出哪几个面。**移动端永远不在结果里** —— 结构上就进不来，
    /// 所以「到期后移动端被锁」这种事故不可能由这里发生。
    public static func grantedSurfaces(_ capabilities: LicenseCapabilities) -> [LicenseSurface] {
        desktopSet.filter { surface in
            guard let bit = surface.capability else { return false }
            return capabilities.contains(bit)
        }
    }

    /// 能力位是否只由桌面三块组成（「一套」的机器判据）。
    ///
    /// 空集也算「不合规」：一份什么也不给的许可证不是「最小档」，是坏件（`LicenseGate` 会先
    /// 以 `unknownEdition` 降级）。多出第四块位 ⇒ 我们不卖这种组合 ⇒ 也判不合规，
    /// 与 `LicenseEdition.from` 把「只授权一块」判成 `nil` 是同一个口径。
    public static func onlyDesktopSurfaces(_ capabilities: LicenseCapabilities) -> Bool {
        let allowed = LicenseCapabilities.all
        return !capabilities.isEmpty && allowed.isSuperset(of: capabilities)
    }
}
