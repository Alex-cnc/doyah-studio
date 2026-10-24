import XCTest
@testable import DoyahCore

/// 详设 §6 `LIC_NO_CAPABILITY`（概设 §3 授权判定：缺哪个位、怎么给；禁灰色诱导）。
final class LicenseCapabilityTests: XCTestCase {

    func testMissingCapabilityIsNamed() {
        let decision = CapabilityGate.decide(required: "cloudSync", granted: ["notes", "agent"])
        XCTAssertEqual(decision, .missing(capability: "cloudSync"))
        XCTAssertEqual(CapabilityGate.errorCode(for: decision), "LIC_NO_CAPABILITY")
    }

    func testGrantedCapabilityPasses() {
        let decision = CapabilityGate.decide(required: "notes", granted: ["notes"])
        XCTAssertEqual(decision, .allowed)
        XCTAssertNil(CapabilityGate.errorCode(for: decision))
        XCTAssertNil(CapabilityGate.message(for: decision, language: .simplifiedChinese))
    }

    func testMessageNamesCapabilityAndWhereToGrant() {
        let decision = CapabilityGate.decide(required: "cloudSync", granted: [])
        let zh = CapabilityGate.message(for: decision, language: .simplifiedChinese)
        let en = CapabilityGate.message(for: decision, language: .english)
        XCTAssertTrue(zh?.contains("cloudSync") == true, "必须点名缺哪个位")
        XCTAssertTrue(zh?.contains("许可证页") == true, "必须说去哪儿给")
        XCTAssertTrue(en?.contains("cloudSync") == true)
        XCTAssertFalse(zh?.contains("升级以解锁") == true, "禁诱导话术")
    }
}
