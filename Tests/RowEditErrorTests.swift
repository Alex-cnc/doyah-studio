import XCTest
@testable import DoyahCore

/// 详设 §6 `DATA_NO_PK` / `DATA_WRITE_CONFLICT`（概设 §4.6）。
final class RowEditErrorTests: XCTestCase {

    func testTableWithoutPrimaryKeyRefusesRowEditing() {
        let decision = RowWriteGuard.decide(hasPrimaryKey: false, affectedRows: nil)
        XCTAssertEqual(decision, .noPrimaryKey)
        XCTAssertEqual(RowWriteGuard.errorCode(for: decision), "DATA_NO_PK")
        // 反例：即使服务端说影响 1 行，也不许放行（行不可定位）
        XCTAssertEqual(
            RowWriteGuard.decide(hasPrimaryKey: false, affectedRows: 1),
            .noPrimaryKey
        )
    }

    func testZeroAffectedRowsIsConflict() {
        let decision = RowWriteGuard.decide(hasPrimaryKey: true, affectedRows: 0)
        XCTAssertEqual(decision, .writeConflict, "影响 0 行 = 行已被别人改/删，必须报冲突而不是当成功")
        XCTAssertEqual(RowWriteGuard.errorCode(for: decision), "DATA_WRITE_CONFLICT")
    }

    func testSingleRowWritePasses() {
        let decision = RowWriteGuard.decide(hasPrimaryKey: true, affectedRows: 1)
        XCTAssertEqual(decision, .write)
        XCTAssertNil(RowWriteGuard.errorCode(for: decision))
    }

    func testMultipleAffectedRowsIsRefused() {
        let decision = RowWriteGuard.decide(hasPrimaryKey: true, affectedRows: 3)
        XCTAssertEqual(decision, .affectedMultipleRows(3), "按行编辑语义只该动一行；多行说明条件不唯一")
    }
}
