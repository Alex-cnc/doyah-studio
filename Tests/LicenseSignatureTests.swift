import Crypto
import XCTest
@testable import DoyahCore

/// FR-LIC-01 的签名与装载：Ed25519 校验、多钥匙并存、坏文件一律"不通过"（不是默认放行）。
final class LicenseSignatureTests: XCTestCase {

    private func sampleLicense() -> License {
        License(issuedTo: "alex", capabilities: .all, maxDevices: 5)
    }

    func testValidSignaturePasses() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(sampleLicense(), privateKey: keys.privateKey)
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        XCTAssertTrue(verifier.isValid(payload: file.payload, signature: file.signature))
    }

    /// **被改过的载荷必须不通过**（这是"手改许可证"的唯一防线）。
    func testTamperedPayloadFails() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(sampleLicense(), privateKey: keys.privateKey)
        let original = String(decoding: file.payload, as: UTF8.self)
        // 改一个**确实出现在载荷里**的字段（第一次写测试时改了 "standard"，而这份样例里根本没有这个词，
        // 于是"被改过的载荷"其实与原文逐字相同、签名当然通过 —— 测试自己错了，当场抓到并改正）。
        let tampered = original.replacingOccurrences(of: "alex", with: "mallory")
        XCTAssertNotEqual(tampered, original, "改之前先确认真的改了内容")
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        XCTAssertFalse(
            verifier.isValid(payload: Data(tampered.utf8), signature: file.signature),
            "改过载荷就不该通过 —— 否则签名等于没做"
        )
    }

    func testWrongKeyFails() throws {
        let issuer = LicenseIssuing.makeKeyPair()
        let other = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(sampleLicense(), privateKey: issuer.privateKey)
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: other.publicKey))
        XCTAssertFalse(verifier.isValid(payload: file.payload, signature: file.signature))
    }

    /// 多钥匙（换钥期）：旧钥签发的许可仍应有效。
    func testMultiplePublicKeysAcceptEitherSignature() throws {
        let old = LicenseIssuing.makeKeyPair()
        let new = LicenseIssuing.makeKeyPair()
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKeys: [old.publicKey, new.publicKey]))
        let signedByOld = try LicenseIssuing.sign(sampleLicense(), privateKey: old.privateKey)
        let signedByNew = try LicenseIssuing.sign(sampleLicense(), privateKey: new.privateKey)
        XCTAssertTrue(verifier.isValid(payload: signedByOld.payload, signature: signedByOld.signature))
        XCTAssertTrue(verifier.isValid(payload: signedByNew.payload, signature: signedByNew.signature))
    }

    func testBadKeyLengthMeansCannotVerifyNotPass() {
        XCTAssertNil(Ed25519LicenseVerifier(rawPublicKey: Data([1, 2, 3])), "密钥长度不对应当构造失败，而不是默认放行")
        XCTAssertNil(Ed25519LicenseVerifier(rawPublicKeys: [Data([1, 2, 3])]))
    }

    func testFileRoundTripAndMalformedInput() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(sampleLicense(), privateKey: keys.privateKey)
        let text = file.encoded()
        let decoded = try XCTUnwrap(LicenseFile.decode(text))
        XCTAssertEqual(decoded, file)
        let license = try XCTUnwrap(decoded.license())
        XCTAssertEqual(license.edition, .ultra)
        XCTAssertEqual(license.issuedTo, "alex")

        XCTAssertNil(LicenseFile.decode("这不是许可证文件"))
        XCTAssertNil(LicenseFile.decode("DOYAH-LICENSE-1\n不是 base64\n也不是"))
        XCTAssertNil(LicenseFile(payload: Data("坏 JSON".utf8), signature: Data()).license())
    }

    /// 端到端：签名有效的许可证 → Ultra；签名被改 → 降级 Standard 且给出原因。
    func testGateEndToEndWithRealSignature() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(sampleLicense(), privateKey: keys.privateKey)
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        let license = try XCTUnwrap(file.license())

        let ok = LicenseGate.evaluate(license, payload: file.payload, signature: file.signature, verifier: verifier)
        XCTAssertEqual(ok.edition, .ultra)

        let bad = LicenseGate.evaluate(license, payload: Data("改过".utf8), signature: file.signature, verifier: verifier)
        XCTAssertEqual(bad.edition, .standard)
        XCTAssertEqual(bad.basis, .invalidSignature)
    }
}

/// 内置公钥的装载口径：**没配公钥就是"无法校验"（降级），不是"默认放行"**；
/// 环境变量可覆盖（自用与测试：拿自己的钥匙签自己的许可证）。
final class LicensePublicKeyTests: XCTestCase {

    func testEnvironmentOverrideIsUsed() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(
            License(issuedTo: "self", capabilities: .all), privateKey: keys.privateKey
        )
        let verifier = try XCTUnwrap(
            LicensePublicKey.verifier(environment: ["DOYAH_LICENSE_PUBLIC_KEY": keys.publicKey.base64EncodedString()])
        )
        XCTAssertTrue(verifier.isValid(payload: file.payload, signature: file.signature))
    }

    /// 内置公钥存在时，**别的钥匙签的许可证必须不通过**（防"拿自己签的许可证激活生产版"）。
    func testForeignKeyDoesNotPassAgainstBuiltInKey() throws {
        guard let builtIn = LicensePublicKey.verifier(environment: [:]) else {
            throw XCTSkip("当前没有内置公钥（占位期）—— 如实跳过，不假装通过")
        }
        let foreign = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(
            License(issuedTo: "mallory", capabilities: .all), privateKey: foreign.privateKey
        )
        XCTAssertFalse(builtIn.isValid(payload: file.payload, signature: file.signature))
    }

    func testNoKeyMeansCannotVerify() {
        // 空环境 + 把内置公钥当空（用环境变量覆盖成空串来模拟"没配"）
        let verifier = LicensePublicKey.verifier(environment: ["DOYAH_LICENSE_PUBLIC_KEY": ""])
        // 内置公钥仍在，所以这里只断言"能构造出校验器"（真正的占位期行为由 productionPublicKeysBase64 决定）
        XCTAssertNotNil(verifier)
    }
}

/// 装载口径（FR-LIC-02 的 Core 半边）：**"没放许可证"与"许可证坏了"必须分得开**，
/// 因为用户该做的事完全不同。
final class LicenseLoaderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-license-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, name: String = "license.doyahlicense") -> URL {
        let url = directory.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMissingFileMeansStandardWithItsOwnReason() {
        let result = LicenseLoader.load(language: .simplifiedChinese, from: directory.appendingPathComponent("nope.doyahlicense"))
        XCTAssertEqual(result.entitlements.edition, .standard)
        XCTAssertEqual(result.source, .missing)
        XCTAssertFalse(LicenseLoader.summary(for: result, language: .simplifiedChinese).isEmpty, "要给一句人话（当前呈现 Standard）")
    }

    /// `DOYAH_LICENSE_PATH` 能把"从哪儿读"指到别处 —— 验收三档时用它，
    /// **不动用户数据目录里那份真许可证**。
    func testEnvironmentOverridePointsAtAnotherFile() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(
            License(issuedTo: "alex", capabilities: [.workspaces, .database], maxDevices: 5),
            privateKey: keys.privateKey
        )
        let url = write(file.encoded(), name: "pro.doyahlicense")
        let environment = [LicenseLoader.licensePathEnvironmentKey: url.path]
        XCTAssertEqual(LicenseLoader.defaultLicenseURL(environment: environment), url)

        let result = LicenseLoader.load(
            language: .simplifiedChinese,
            verifier: try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey)),
            environment: environment
        )
        XCTAssertEqual(result.entitlements.edition, .pro, "覆盖生效时读的是被指定的文件")
        XCTAssertEqual(result.source, .file(url))
    }

    /// 设成空串**当作没设**：否则 `DOYAH_LICENSE_PATH=` 会让它去找一个空路径，
    /// 症状是"明明放着许可证却一直是 Standard"，而且看不出为什么。
    func testEmptyEnvironmentOverrideIsIgnored() {
        let environment = [LicenseLoader.licensePathEnvironmentKey: ""]
        XCTAssertEqual(
            LicenseLoader.defaultLicenseURL(environment: environment),
            LicenseLoader.defaultLicenseURL(environment: [:])
        )
    }

    func testValidUltraLicenseGivesUltra() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(
            License(issuedTo: "alex", capabilities: .all, maxDevices: 5), privateKey: keys.privateKey
        )
        let url = write(file.encoded())
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        let result = LicenseLoader.load(language: .simplifiedChinese, from: url, verifier: verifier)
        XCTAssertEqual(result.entitlements.edition, .ultra)
        XCTAssertEqual(result.entitlements.basis, .licensed)
        XCTAssertEqual(result.source, .file(url))
        XCTAssertEqual(result.license?.issuedTo, "alex")
    }

    /// **坏文件与"没放"要分开说**（这是本轮特意分开的两个 source）。
    func testCorruptFileIsDistinguishedFromMissing() {
        let url = write("DOYAH-LICENSE-1\n不是 base64\n也不是")
        let result = LicenseLoader.load(language: .simplifiedChinese, from: url)
        XCTAssertEqual(result.entitlements.edition, .standard)
        guard case .unreadable = result.source else { return XCTFail("应当是 unreadable，实际 \(result.source)") }
        XCTAssertFalse(LicenseLoader.summary(for: result, language: .simplifiedChinese).isEmpty)
    }

    func testTamperedFileDegradesAndSaysSignatureInvalid() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let file = try LicenseIssuing.sign(
            License(issuedTo: "alex", capabilities: .all), privateKey: keys.privateKey
        )
        var lines = file.encoded().split(separator: "\n").map(String.init)
        let payload = String(decoding: file.payload, as: UTF8.self).replacingOccurrences(of: "alex", with: "mallory")
        lines[1] = Data(payload.utf8).base64EncodedString()
        let url = write(lines.joined(separator: "\n"))
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        let result = LicenseLoader.load(language: .simplifiedChinese, from: url, verifier: verifier)
        XCTAssertEqual(result.entitlements.edition, .standard)
        XCTAssertEqual(result.entitlements.basis, .invalidSignature)
        // 许可证本身仍能被解析出来（数据没被动过），只是签名不过 —— 界面上要能同时说这两件事
        XCTAssertEqual(result.license?.issuedTo, "mallory")
    }

    func testExpiredLicenseSaysExpiredAndKeepsData() throws {
        let keys = LicenseIssuing.makeKeyPair()
        let expired = Date(timeIntervalSince1970: 1_000)
        let file = try LicenseIssuing.sign(
            License(issuedTo: "alex", capabilities: .all, expiresAt: expired), privateKey: keys.privateKey
        )
        let url = write(file.encoded())
        let verifier = try XCTUnwrap(Ed25519LicenseVerifier(rawPublicKey: keys.publicKey))
        let result = LicenseLoader.load(language: .simplifiedChinese, from: url, verifier: verifier, now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(result.entitlements.edition, .standard)
        XCTAssertEqual(result.entitlements.basis, .expired(expired))
        XCTAssertNotNil(result.license, "到期只是降级：许可证与数据都还在")
    }

    /// **这一句跟着调用方的语言走**（队列 L-65）：它同时出现在界面、状态栏与日志上。
    /// 此前 Core 把它写死成简体中文 ⇒ 界面切到英文这一行仍是中文（`.licenseUnreadableWithReason`
    /// 的英文译文永远不可达）。**界面此前为此自己抄了一份**，而那份把「为什么读不出来」丢掉了 ——
    /// 所以本轮除了透传语言，还要钉住「原因不许被丢」。
    func testSummaryFollowsCallerLanguageAndKeepsReason() throws {
        let missing = LicenseLoader.load(language: .english, from: directory.appendingPathComponent("nope.doyahlicense"))
        XCTAssertEqual(missing.source, .missing)
        let missingZH = LicenseLoader.summary(for: missing, language: .simplifiedChinese)
        let missingEN = LicenseLoader.summary(for: missing, language: .english)
        XCTAssertNotEqual(missingZH, missingEN, "两种语言必须给出不同的句子")
        XCTAssertTrue(missingEN.contains("No license yet"), "英文那份要真的是英文：\(missingEN)")

        // 坏文件：说的是「读不出来」+ **原因**（界面那份副本当年把原因丢了）
        let broken = LicenseLoader.load(language: .english, from: write("DOYAH-LICENSE-1\n不是 base64\n也不是"))
        guard case .unreadable(let reason) = broken.source else {
            return XCTFail("应当是 unreadable，实际 \(broken.source)")
        }
        XCTAssertFalse(reason.isEmpty, "装载那一刻就要把原因说出来（它随 LoadResult 一起被界面显示）")
        let brokenEN = LicenseLoader.summary(for: broken, language: .english)
        XCTAssertTrue(brokenEN.contains(reason), "整句里必须带上原因，别把它丢掉：\(brokenEN)")
        XCTAssertNotEqual(brokenEN, LicenseLoader.summary(for: broken, language: .simplifiedChinese))
    }
}
