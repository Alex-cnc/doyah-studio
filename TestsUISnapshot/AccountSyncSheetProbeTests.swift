import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 片 `云F` · 账号与同步界面的**离屏快照**（卡判据 ④：注册页 / 登录页 / 开关处三张读数）。
///
/// ## 判的是什么
///
/// 卡片判据 ④ 要的是「界面读数」：注册页、登录页、开关处各一张。本探针把**真视图树**
/// （`App/Views/AccountSyncSheet.swift`）离屏渲染成 PNG（中英各一遍），并把两件事判成断言：
///
///   · **`S4` 那句到了像素上**：渲染那一遍 `L(...)` 取到的文案里必须有
///     「当前不是端到端加密 —— 内容在云端可读」（英文那遍是它的英文译文）——
///     「代码里有这句」不等于「屏幕上真有」；
///   · **两页都画得出来**：注册页那遍的文案里必须有注册页自己的键（「注册」「确认口令」…），
///     且两张图都有非背景内容（`contentRatio`）。
///
/// ## 边界（如实登记）
///
/// · **不是「真人点开」的现场验**：离屏宿主里画的是真视图树，但**没有人手点**这一屏；
///   人工那一半（点开菜单、开关手感）留给组长在解锁窗口补拍；
/// · 不碰真网络与真钥匙串：注入假传输 + 内存令牌存储（与 `Tests/AccountFlowTests.swift` 同法）；
/// · 产物落 `DOYAH_SNAPSHOT_DIR`（默认 `.build/ui-snapshots/`）；本探针**不写全量跑凭证**
///   （`full-run/`），所以「快照张数」那条计数不受影响；
/// · 用例默认**跳过**（`DOYAH_UI_SNAPSHOT=1` 才跑）—— 快照是取证工具，不是回归门禁。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 DOYAH_SNAPSHOT_DIR=<目录> swift test --filter AccountSyncSheetProbe`。
final class AccountSyncSheetProbeTests: XCTestCase {

    /// 宿主面积：面板宽 520 + 一圈背景（与其它面板快照同量级）。
    private static let size = CGSize(width: 560, height: 640)

    /// `S4` 要求逐字写出的那句（中 / 英）—— 与 `Core/Localization.swift` 的 `.accountSyncNotice` 同一句。
    private static let noticeZH = "当前不是端到端加密 —— 内容在云端可读"
    private static let noticeEN = "This is not end-to-end encrypted — content is readable in the cloud"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    @MainActor
    func testAccountSheetPagesRenderAndCarryTheS4Notice() throws {
        let signIn = try UISnapshot.writeBothLanguages(
            "account-sync-signin",
            size: Self.size
        ) {
            AccountSyncSheet(client: Self.offlineClient())
        }

        let signUp = try UISnapshot.writeBothLanguages(
            "account-sync-signup",
            size: Self.size
        ) {
            AccountSyncSheet(client: Self.offlineClient(), page: .signUp)
        }

        // ① 两张图都画出了内容（不是空白底）
        for pair in [signIn, signUp] {
            for record in pair.records {
                XCTAssertGreaterThan(
                    record.contentRatio,
                    0.002,
                    "\(record.name) 几乎没有内容（疑似渲染成空白）"
                )
                print(
                    "🖼️ \(record.name)  \(record.width)×\(record.height) @\(record.scale)x"
                        + "  \(record.bytes) B  内容占比 \(String(format: "%.4f", record.contentRatio))"
                        + "  \(record.file)"
                )
            }
        }

        // ② S4 那句**到了像素上**（中英各一遍：文案取自语言表，不是源码里的一句死话）
        XCTAssertTrue(
            signIn.records[0].localizedStrings.contains(Self.noticeZH),
            "中文那遍的文案里没有 S4 那句：\(signIn.records[0].localizedStrings)"
        )
        XCTAssertTrue(
            signIn.records[1].localizedStrings.contains(Self.noticeEN),
            "英文那遍的文案里没有 S4 那句的英文译文：\(signIn.records[1].localizedStrings)"
        )
        XCTAssertTrue(
            signUp.records[0].localizedStrings.contains(Self.noticeZH),
            "注册页那一遍也必须带着 S4 那句（告知不随页面藏起来）"
        )

        // ③ 注册页那一遍真的是注册页（不是登录页画重了）
        let signUpTexts = Set(signUp.records[0].localizedStrings)
        XCTAssertTrue(signUpTexts.contains("注册"), "注册页那一遍缺「注册」：\(signUpTexts)")
        XCTAssertTrue(signUpTexts.contains("确认口令"), "注册页那一遍缺「确认口令」：\(signUpTexts)")
        XCTAssertTrue(signIn.textsDiffer, "中英两遍的文案必须不同（否则语言没有到像素上）")

        // ④ 开关处那一片区域的读数（同一张中文图上的裁剪：开关 + S4 那句所在的那一条）
        let signInZH = signIn.records[0].file
        if let pixels = UISnapshot.pixelSize(ofPNGAt: signInZH) {
            print("🖼️ 登录页那张的像素尺寸 \(pixels.width)×\(pixels.height) —— \(signInZH)")
        }
        let region = (leading: 60, top: 650, width: 1000, height: 175)
        if let band = UISnapshot.region(
            ofPNGAt: signInZH,
            leading: region.leading,
            top: region.top,
            width: region.width,
            height: region.height
        ) {
            print(
                "🖼️ 开关处裁剪区（leading \(region.leading) / top \(region.top) / \(region.width)×\(region.height)）"
                    + "  墨迹 \(band.ink) / \(band.pixelCount) 像素"
                    + "  底色 \(band.background)"
            )
        } else {
            XCTFail("开关处那一片裁不出来 —— 图不存在或区域越界（\(signInZH)）")
        }

        // 第三张**独立成文件**：开关处那一片（判据 ④ 要三张读数，第三张就是它）。
        let section = try Self.crop(
            from: signInZH,
            named: "account-sync-sync-section-zh",
            leading: region.leading,
            top: region.top,
            width: region.width,
            height: region.height
        )
        print("🖼️ 开关处（独立文件） \(section)")
    }

    /// 把一张已落盘 PNG 的一片裁成独立文件（判据 ④ 的第三张读数）。
    ///
    /// 为什么自己裁而不是让快照工具再渲染一次：开关处与登录页是**同一棵视图树**的一部分，
    /// 再渲染一次会得到第二份「真相」（将来版面一改，两处就各说各话）。
    private static func crop(
        from sourcePath: String,
        named name: String,
        leading: Int,
        top: Int,
        width: Int,
        height: Int
    ) throws -> String {
        guard let image = NSImage(contentsOfFile: sourcePath),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = source.cropping(
                  to: CGRect(x: leading, y: top, width: width, height: height)
              ) else {
            throw NSError(domain: "AccountSyncSheetProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "裁图失败：\(sourcePath)",
            ])
        }
        let representation = NSBitmapImageRep(cgImage: cropped)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AccountSyncSheetProbe", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "PNG 编码失败：\(name)",
            ])
        }
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        return url.path
    }

    // MARK: - 夹具

    /// 不碰真网络 / 真钥匙串的客户端（假传输 + 内存令牌存储）。
    private static func offlineClient() -> CloudAuthClient {
        CloudAuthClient(
            endpoints: CloudAuthEndpoints(environmentID: AccountFlowModel.environmentID),
            transport: ProbeTransport(),
            store: ProbeTokenStore()
        )
    }
}

/// 出网替身：任何时候都回「凭据错」——探针只画界面，不发真请求。
private final class ProbeTransport: CloudAuthTransport, @unchecked Sendable {
    func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        throw CloudAuthError.transport("probe")
    }
}

/// 令牌存储替身：内存版（探针不碰真钥匙串）。
private final class ProbeTokenStore: NoteSyncTokenStore, @unchecked Sendable {
    func setSession(_ session: NoteSyncSession) throws {}
    func session() throws -> NoteSyncSession? { nil }
    func deleteSession() throws {}
}
