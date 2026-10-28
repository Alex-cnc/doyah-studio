import XCTest
@testable import DoyahCore

/// 站点兼容的身份与降级口径（`FR-STD-WS-WEB-004`）。
///
/// 这一组盯住**能被机械判死**的那半边：UA 形状 / 不许带产品名 / 站点存储缺省口径 /
/// 弹窗必须有可见结果 / 证书失败必须问人。真站点上的「登录流程一致、第三方 Cookie、
/// 下载与文件选择」只能人工点验，不在这一组里假装覆盖。
final class BrowserIdentityTests: XCTestCase {

    // MARK: UA（需求 ①）

    /// 三件齐全才是常规浏览器：平台串、`Version/`、`Safari/`。
    func testUserAgentShapeMatchesARegularDesktopSafari() {
        let ua = BrowserIdentity.userAgent
        XCTAssertTrue(ua.hasPrefix("Mozilla/5.0 (Macintosh;"), ua)
        XCTAssertTrue(ua.contains("AppleWebKit/\(BrowserIdentity.webKitVersion)"), ua)
        XCTAssertTrue(ua.contains("Version/\(BrowserIdentity.safariVersion)"), ua)
        XCTAssertTrue(ua.hasSuffix("Safari/\(BrowserIdentity.webKitVersion)"), ua)
    }

    /// **不许带产品名**：那正是「内嵌面板」的标记，站点见到就降级（需求 ①）。
    /// 两条路一起断：UA 原文里没有，引擎也不许再把名字拼上去。
    func testUserAgentCarriesNoProductName() {
        let lowered = BrowserIdentity.userAgent.lowercased()
        XCTAssertFalse(lowered.contains("doyah"), BrowserIdentity.userAgent)
        XCTAssertFalse(lowered.contains("doyahstudio"), BrowserIdentity.userAgent)
        XCTAssertNil(BrowserIdentity.applicationNameForUserAgent)
    }

    /// 确定性：同一台机器每次拿到的必须是同一串（站点按 UA 分流时，摇摆会让问题查不出来）。
    func testUserAgentIsDeterministicAndPinned() {
        XCTAssertEqual(BrowserIdentity.userAgent, BrowserIdentity.userAgent)
        XCTAssertEqual(BrowserIdentity.safariVersion, "18.0")
        XCTAssertEqual(BrowserIdentity.webKitVersion, "605.1.15")
    }

    // MARK: 站点存储（需求 ②）

    func testDefaultStorageKeepsLoginStateAcrossRestarts() {
        XCTAssertEqual(BrowserStoragePolicy.default, .persistent)
        XCTAssertFalse(BrowserStoragePolicy.default.isEphemeral)
        XCTAssertTrue(BrowserStoragePolicy.default.allowsThirdPartyCookies)
        XCTAssertEqual(BrowserIdentity.storagePolicy, .persistent)
    }

    /// 临时会话是**声明式降级**：它自己就得承认第三方 Cookie 不按常规工作。
    func testEphemeralStorageIsADeclaredDowngrade() {
        XCTAssertTrue(BrowserStoragePolicy.ephemeral.isEphemeral)
        XCTAssertFalse(BrowserStoragePolicy.ephemeral.allowsThirdPartyCookies)
        // 两档必须真的不同 —— 否则「降级」只是一句话。
        XCTAssertNotEqual(
            BrowserStoragePolicy.ephemeral.allowsThirdPartyCookies,
            BrowserStoragePolicy.default.allowsThirdPartyCookies
        )
    }

    // MARK: 弹窗（需求 ③）

    /// `target=_blank` / `window.open` 一律有可见结果 —— 没有「什么都不做」这一档。
    func testPopupAlwaysHasAVisibleResult() {
        let url = URL(string: "https://example.com/landing")!
        let notice = BrowserPopupPolicy.decide(url: url, language: .simplifiedChinese)
        XCTAssertEqual(notice.url, url)
        XCTAssertTrue(notice.message.contains(url.absoluteString), notice.message)
        XCTAssertTrue(notice.offersSystemBrowser)

        // 页面没给地址：也得说一句，而不是静默。
        let bare = BrowserPopupPolicy.decide(url: nil, language: .simplifiedChinese)
        XCTAssertNil(bare.url)
        XCTAssertFalse(bare.message.isEmpty)
        XCTAssertFalse(bare.offersSystemBrowser)

        // 空白弹窗（`about:blank`）也是要给结果的：地址非空 ⇒ 按「有地址」那一档走。
        let blank = BrowserPopupPolicy.decide(url: URL(string: "about:blank"), language: .simplifiedChinese)
        XCTAssertEqual(blank.url?.absoluteString, "about:blank")
        XCTAssertFalse(blank.message.isEmpty)
    }

    /// 提示跟着调用方的语言走（Core 不许自己挑语言）。
    func testPopupMessageFollowsTheCallerLanguage() {
        let url = URL(string: "https://example.com/a")!
        let zh = BrowserPopupPolicy.decide(url: url, language: .simplifiedChinese).message
        let en = BrowserPopupPolicy.decide(url: url, language: .english).message
        XCTAssertNotEqual(zh, en)
        XCTAssertFalse(en.contains("弹窗"), en)
        // 两种语言都得带上地址（用户要据此决定下一步）。
        XCTAssertTrue(zh.contains(url.absoluteString))
        XCTAssertTrue(en.contains(url.absoluteString))
    }

    // MARK: 证书（需求 ④）

    func testCertificateClassifyCoversTheThreeFailures() {
        XCTAssertNil(BrowserCertificateFailure.classify(trusted: true, hostnameMatches: true, expired: false))
        XCTAssertEqual(
            BrowserCertificateFailure.classify(trusted: false, hostnameMatches: true, expired: true),
            .expired
        )
        XCTAssertEqual(
            BrowserCertificateFailure.classify(trusted: false, hostnameMatches: false, expired: false),
            .hostnameMismatch
        )
        XCTAssertEqual(
            BrowserCertificateFailure.classify(trusted: false, hostnameMatches: true, expired: false),
            .untrustedAnchor
        )
    }

    /// 证书问题**必须问人**：既不许自动放行，也不许白屏。
    func testCertificatePromptAlwaysAsksTheUser() {
        for failure in BrowserCertificateFailure.allCases {
            let zh = BrowserCertificatePolicy.prompt(for: failure, language: .simplifiedChinese)
            XCTAssertTrue(zh.offersContinue && zh.offersCancel)
            XCTAssertFalse(zh.reason.isEmpty)
            XCTAssertTrue(zh.message.contains(zh.reason), zh.message)

            let en = BrowserCertificatePolicy.prompt(for: failure, language: .english)
            XCTAssertNotEqual(zh.message, en.message)
            XCTAssertFalse(en.message.contains("证书"), en.message)
        }
    }

    // MARK: 明文拒绝内嵌环境（需求 ⑤）

    func testSystemBrowserMessageCarriesTheAddress() {
        let url = URL(string: "https://example.com/secure")!
        let zh = BrowserCompatibility.systemBrowserMessage(url: url, language: .simplifiedChinese)
        let en = BrowserCompatibility.systemBrowserMessage(url: url, language: .english)
        XCTAssertTrue(zh.contains(url.absoluteString), zh)
        XCTAssertTrue(en.contains(url.absoluteString), en)
        XCTAssertNotEqual(zh, en)
    }
}
