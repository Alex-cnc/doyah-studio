import XCTest
@testable import DoyahCore

/// 详设 §6 `IO_TARGET_EXISTS` / `IO_PARTIAL`（概设 §4.8）。
final class ImportExportErrorTests: XCTestCase {

    func testExistingTargetMustAskBeforeOverwrite() {
        let decision = ImportExportGuard.decideBeforeWrite(targetExists: true, overwriteApproved: false)
        XCTAssertEqual(decision, .targetExists, "目标已存在必须询问，不许静默覆盖")
        XCTAssertEqual(ImportExportGuard.errorCode(for: decision), "IO_TARGET_EXISTS")
    }

    func testApprovedOverwriteProceeds() {
        XCTAssertEqual(
            ImportExportGuard.decideBeforeWrite(targetExists: true, overwriteApproved: true),
            .proceed
        )
        XCTAssertEqual(
            ImportExportGuard.decideBeforeWrite(targetExists: false, overwriteApproved: false),
            .proceed
        )
    }

    func testPartialFailureListsBothSides() {
        let decision = ImportExportGuard.decideAfterWrite(failed: 2, succeeded: 7)
        XCTAssertEqual(decision, .partial(failed: 2, succeeded: 7), "部分失败必须分别列出失败与成功条数")
        XCTAssertEqual(ImportExportGuard.errorCode(for: decision), "IO_PARTIAL")
    }

    func testAllSucceededIsNotPartial() {
        XCTAssertEqual(ImportExportGuard.decideAfterWrite(failed: 0, succeeded: 9), .proceed)
    }
}
