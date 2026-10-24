import XCTest
@testable import DoyahCore

/// 详设 §6 `DDL_PREVIEW_REQUIRED`（概设 §4.7：未预览不得执行）。
final class DDLPreviewGateTests: XCTestCase {

    func testNeverPreviewedIsRefused() {
        let decision = DDLPreviewGate.decide(script: "ALTER TABLE t ADD COLUMN c INT;", previewedScript: nil)
        XCTAssertEqual(decision, .previewRequired)
        XCTAssertEqual(DDLPreviewGate.errorCode(for: decision), "DDL_PREVIEW_REQUIRED")
    }

    func testPreviewThenEditInvalidatesPreview() {
        let decision = DDLPreviewGate.decide(
            script: "ALTER TABLE t ADD COLUMN c2 INT;",
            previewedScript: "ALTER TABLE t ADD COLUMN c INT;"
        )
        XCTAssertEqual(decision, .previewStale, "预览后改过脚本 ⇒ 旧预览作废，必须重新预览")
        XCTAssertEqual(DDLPreviewGate.errorCode(for: decision), "DDL_PREVIEW_REQUIRED")
    }

    func testPreviewedAndUnchangedIsAllowed() {
        let script = "CREATE INDEX idx_orders_date ON orders(created_at);"
        let decision = DDLPreviewGate.decide(script: script, previewedScript: script)
        XCTAssertEqual(decision, .allowed)
        XCTAssertNil(DDLPreviewGate.errorCode(for: decision))
    }
}
