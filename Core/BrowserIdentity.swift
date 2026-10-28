import Foundation

/// 浏览器页签的**站点身份**（`FR-STD-WS-WEB-004`）：对站点而言它必须是一个常规浏览器，
/// 不是「某个应用的内嵌面板」。
///
/// 三件事在这一层定死，平台层只许照抄、不许各写一份：
///
/// 1. **确定性 UA**：版本号写在这里，不取运行时随机量 —— 同一台机器每次拿到的必须是同一串；
///    否则「浏览器页签里能登录、重启后不能」这类问题查不出来（站点按 UA 分流）。
/// 2. **不带产品名**：`WKWebView` 会把 `applicationNameForUserAgent` 拼进 UA 尾巴，那正是
///    「内嵌面板」的标记 —— 站点见到它就降级（需求 ①）。
/// 3. **三件齐全**：平台串、`Version/x`、`Safari/…` 同时出现，缺一个就会被判成非浏览器。
public struct BrowserIdentity: Sendable, Equatable {

    /// 与常规桌面 Safari 一致的版本（站点按版本给能力；改这里等于改产品对站点的身份）。
    public static let safariVersion = "18.0"

    /// WebKit 引擎版本（`AppleWebKit/…` 与 `Safari/…` 用的是同一个）。
    public static let webKitVersion = "605.1.15"

    /// 平台串：与 macOS 上的常规 Safari 同形（不暴露进程 / 机型 / 构建号）。
    public static let platformToken = "Macintosh; Intel Mac OS X 10_15_7"

    /// 交给渲染引擎的 UA 原文。
    public static let userAgent =
        "Mozilla/5.0 (\(platformToken)) AppleWebKit/\(webKitVersion) (KHTML, like Gecko) "
        + "Version/\(safariVersion) Safari/\(webKitVersion)"

    /// `nil` = **不往 UA 尾巴上拼产品名**（`WKWebView.applicationNameForUserAgent` 的语义）。
    public static let applicationNameForUserAgent: String? = nil

    /// 站点存储与 Cookie 的口径（需求 ②）。
    public static let storagePolicy: BrowserStoragePolicy = .default
}

/// 站点存储口径：登录态与第三方 Cookie 必须**跨导航与重启**活着（`FR-STD-WS-WEB-004` ②）。
///
/// 「临时会话」是**声明式降级**而不是隐藏开关：调用方选了它就得自己说出来，
/// 因为站点会因此把「登录跳转回来后还是登录态」这条行为降级 —— 静默降级等于骗人。
public enum BrowserStoragePolicy: String, Sendable, CaseIterable {

    /// 常规浏览器的行为：脏数据落盘、登录态跨重启。
    case persistent

    /// 关掉即清（无痕式）。
    case ephemeral

    /// 缺省 = 持久化（需求 ② 的原话：第三方 Cookie 与站点存储按常规行为工作）。
    public static let `default`: BrowserStoragePolicy = .persistent

    public var isEphemeral: Bool { self == .ephemeral }

    /// 第三方 Cookie 是否按常规行为工作（临时会话里必然不是）。
    public var allowsThirdPartyCookies: Bool { self == .persistent }
}

/// 页面要求开新窗口（`target=_blank` / `window.open`）时的可见结果（`FR-STD-WS-WEB-004` ③）。
///
/// **没有「什么都不做」这一档**：静默无反应正是用户报的那类缺陷（点了链接像没点）。
/// 要么真的转成一个页签（`.url != nil` 且 `canOpenInTab`），要么至少给出一句带地址的提示。
public struct BrowserPopupNotice: Equatable, Sendable {

    /// 要打开的地址（页面没给地址时是 `nil`）。
    public let url: URL?

    /// 直接显示给用户的一句话（已按调用方语言拼好）。
    public let message: String

    /// 是否给出「用系统浏览器打开」这条出口。
    public let offersSystemBrowser: Bool

    public init(url: URL?, message: String, offersSystemBrowser: Bool) {
        self.url = url
        self.message = message
        self.offersSystemBrowser = offersSystemBrowser
    }
}

public enum BrowserPopupPolicy {

    /// 一次判定。**永远**回一个可见结果（地址为空也回一句「拦住了一个没有地址的弹窗」）。
    public static func decide(url: URL?, language: AppLanguage) -> BrowserPopupNotice {
        guard let url, !url.absoluteString.isEmpty else {
            return BrowserPopupNotice(
                url: nil,
                message: LocalizedStrings.text(.browserPopupBlockedNoURL, language: language),
                offersSystemBrowser: false
            )
        }
        return BrowserPopupNotice(
            url: url,
            message: LocalizedStrings.format(
                .browserPopupBlockedNotice,
                language: language,
                url.absoluteString
            ),
            offersSystemBrowser: true
        )
    }
}

/// 证书失败的类别（`FR-STD-WS-WEB-004` ④：给可读原因与「继续 / 取消」，不白屏）。
public enum BrowserCertificateFailure: String, Sendable, CaseIterable {

    /// 证书过期。
    case expired

    /// 证书与站点名不符。
    case hostnameMismatch

    /// 签发者不受信任（自签 / 链断 / 根证书不在系统信任里）。
    case untrustedAnchor

    /// 系统信任评估的结论 → 类别。`trusted == true` 时返回 `nil`（没有失败）。
    public static func classify(
        trusted: Bool,
        hostnameMatches: Bool,
        expired: Bool
    ) -> BrowserCertificateFailure? {
        if trusted { return nil }
        if expired { return .expired }
        if !hostnameMatches { return .hostnameMismatch }
        return .untrustedAnchor
    }
}

/// 证书失败时要给用户看的那一屏（原因 + 两个出口）。
///
/// **没有「静默继续」这一档**：既不许自动放行，也不许只留一句白屏 —— 需求原话是
/// 「证书错误给可读原因与『继续 / 取消』」。
public struct BrowserCertificatePrompt: Equatable, Sendable {

    /// 分类原因（如「证书已过期」）。
    public let reason: String

    /// 整句提示（原因 + 风险说明），可直接上屏。
    public let message: String

    /// 有「继续访问」这一档。
    public let offersContinue: Bool

    /// 有「取消」这一档。
    public let offersCancel: Bool

    public init(reason: String, message: String, offersContinue: Bool, offersCancel: Bool) {
        self.reason = reason
        self.message = message
        self.offersContinue = offersContinue
        self.offersCancel = offersCancel
    }
}

public enum BrowserCertificatePolicy {

    /// 一次判定：永远**要用户自己决定**（`offersContinue` / `offersCancel` 恒为真）。
    ///
    /// 为什么把「继续」放在用户手里：这里是站点身份的最后一关，程序替用户按下去
    /// 等于把中间人风险静默接受掉。
    public static func prompt(
        for failure: BrowserCertificateFailure,
        language: AppLanguage
    ) -> BrowserCertificatePrompt {
        let reasonKey: LKey
        switch failure {
        case .expired: reasonKey = .browserCertificateExpired
        case .hostnameMismatch: reasonKey = .browserCertificateHostnameMismatch
        case .untrustedAnchor: reasonKey = .browserCertificateUntrustedAnchor
        }
        let reason = LocalizedStrings.text(reasonKey, language: language)
        return BrowserCertificatePrompt(
            reason: reason,
            message: LocalizedStrings.format(.browserCertificatePrompt, language: language, reason),
            offersContinue: true,
            offersCancel: true
        )
    }
}

/// 站点明文拒绝内嵌环境时的说法与出口（`FR-STD-WS-WEB-004` ⑤）。
///
/// 需求原话：站点强制硬件密钥 / 受版权保护内容时**如实说明并给出「用常规浏览器打开」**，
/// 不假装能过 —— 所以这里只产出一句实话 + 一个地址，没有「再试一次骗过去」的路径。
public enum BrowserCompatibility {

    public static func systemBrowserMessage(url: URL, language: AppLanguage) -> String {
        LocalizedStrings.format(
            .browserNeedsSystemBrowser,
            language: language,
            url.absoluteString
        )
    }
}
