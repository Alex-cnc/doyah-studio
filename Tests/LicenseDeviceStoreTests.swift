import XCTest
@testable import DoyahCore

/// `FR-STD-ALL-LIC-005`：设备配额（默认 5 台）与**可释放**。
///
/// 台账是本地文件（`license-devices.json`），所以这一族用例全部在临时目录里跑真文件 ——
/// 不碰用户那份台账，也不靠内存假实现来「证明」落盘。
final class LicenseDeviceStoreTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-license-devices-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func store() -> LicenseDeviceStore {
        LicenseDeviceStore(fileURL: folder.appendingPathComponent(LicenseDeviceStore.fileName))
    }

    private func license(
        issuedTo: String = "alex",
        capabilities: LicenseCapabilities = .all,
        maxDevices: Int = License.defaultMaxDevices,
        expiresAt: Date? = nil,
        devices: [LicenseDevice] = []
    ) -> License {
        License(
            issuedTo: issuedTo,
            capabilities: capabilities,
            maxDevices: maxDevices,
            expiresAt: expiresAt,
            devices: devices
        )
    }

    // MARK: 配额

    func testDefaultQuotaIsFive() {
        let subject = license()
        XCTAssertEqual(subject.maxDevices, 5, "默认 5 台（已拍板）")
        XCTAssertEqual(store().quota(for: subject), 5)
        XCTAssertEqual(store().remaining(for: subject), 5, "一台没登记时额度是满的")
    }

    func testFiveDevicesFitAndTheSixthIsRejectedWithAName() throws {
        let subject = license()
        let store = store()
        for index in 1...5 {
            try store.activate(named: "设备\(index)", for: subject, now: Date(timeIntervalSince1970: Double(index)))
        }
        XCTAssertEqual(store.devices(for: subject).count, 5)
        XCTAssertEqual(store.remaining(for: subject), 0)

        XCTAssertThrowsError(try store.activate(named: "第六台", for: subject)) { error in
            guard case License.DeviceError.quotaExceeded(let max, let suggestion)? = error as? License.DeviceError else {
                return XCTFail("第 6 台必须抛出 quotaExceeded，实际：\(error)")
            }
            XCTAssertEqual(max, 5)
            XCTAssertEqual(suggestion, "设备1", "必须指名最早激活的那一台，不给人一句「已达上限」")
        }
        XCTAssertEqual(store.devices(for: subject).count, 5, "被拒的那台不许落进台账")
    }

    // MARK: 可释放

    func testReleaseFreesTheQuotaAndSurvivesAReload() throws {
        let subject = license()
        let store = store()
        for index in 1...5 {
            try store.activate(named: "设备\(index)", for: subject, now: Date(timeIntervalSince1970: Double(index)))
        }
        let oldest = try XCTUnwrap(store.devices(for: subject).first)
        try store.release(oldest.id, for: subject)

        XCTAssertEqual(store.remaining(for: subject), 1)
        // 换一个新 store（= 重开 App）：释放的结果在盘上，不是内存里的幻觉
        let reopened = store2()
        XCTAssertEqual(reopened.remaining(for: subject), 1)
        XCTAssertFalse(reopened.devices(for: subject).contains { $0.id == oldest.id })

        // 释放出来的那一格能再用
        XCTAssertNoThrow(try reopened.activate(named: "新电脑", for: subject))
        XCTAssertEqual(reopened.remaining(for: subject), 0)
    }

    func testReleaseUnknownDeviceThrows() {
        XCTAssertThrowsError(try store().release(UUID(), for: license())) { error in
            guard case License.DeviceError.unknownDevice? = error as? License.DeviceError else {
                return XCTFail("释放一台不存在的设备必须是 unknownDevice，实际：\(error)")
            }
        }
    }

    /// 台账里还没有这一位用户 ⇒ 以**许可证载荷里声明的设备**为初值（发行方那份是权威清单）。
    func testSeedsFromTheSignedPayloadWhenTheLedgerIsEmpty() {
        let declared = [LicenseDevice(name: "Studio-Mac"), LicenseDevice(name: "Old-Mac")]
        let subject = license(devices: declared)
        let store = store()
        XCTAssertEqual(store.devices(for: subject).map(\.name), ["Studio-Mac", "Old-Mac"])
        XCTAssertEqual(store.remaining(for: subject), 3)
    }

    /// 续期 / 升档是同一个人：设备不许清零（「换一份许可证 → 老机器被当成新机器」是最没道理的降级）。
    func testRenewalKeepsRegisteredDevices() throws {
        let store = store()
        let old = license(capabilities: .notesOnly)
        try store.activate(named: "Studio-Mac", for: old)
        let renewed = license(capabilities: .all, expiresAt: Date(timeIntervalSinceNow: 3600))
        XCTAssertEqual(store.devices(for: renewed).map(\.name), ["Studio-Mac"])
    }

    /// 到期只降呈现，**不影响设备管理**（换机不锁：003 的口径）。
    func testExpiredLicenseStillManagesDevices() throws {
        let subject = license(expiresAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(subject.isExpired(now: Date(timeIntervalSince1970: 2_000)))
        let store = store()
        XCTAssertNoThrow(try store.activate(named: "换来的新机", for: subject, now: Date(timeIntervalSince1970: 2_000)))
        let released = try XCTUnwrap(store.devices(for: subject).first)
        XCTAssertNoThrow(try store.release(released.id, for: subject))
    }

    // MARK: 台账

    func testLedgerIsPlainJSONKeyedByIssuedTo() throws {
        let subject = license(issuedTo: "alex")
        try store().activate(named: "Studio-Mac", for: subject)

        let url = folder.appendingPathComponent(LicenseDeviceStore.fileName)
        let data = try Data(contentsOf: url)
        let ledger = try LicenseDeviceStore.decoder().decode(LicenseDeviceStore.Ledger.self, from: data)
        XCTAssertEqual(ledger.version, LicenseDeviceStore.formatVersion)
        XCTAssertEqual(ledger.slots["alex"]?.map(\.name), ["Studio-Mac"], "台账以「开给谁」为键")

        // 另一个人另一格（同一台机器上换许可证 / 试用别人的许可证，互不干扰）
        let other = license(issuedTo: "someone-else")
        XCTAssertTrue(store().devices(for: other).isEmpty)
        XCTAssertEqual(store().remaining(for: other), 5)
    }

    /// 坏台账不许把 App 弄崩：读不出来就当空台账，初值退到载荷里的设备。
    func testCorruptLedgerIsTreatedAsEmptyNotAsACrash() throws {
        let url = folder.appendingPathComponent(LicenseDeviceStore.fileName)
        try Data("{ 这不是 JSON".utf8).write(to: url)
        let declared = [LicenseDevice(name: "Studio-Mac")]
        XCTAssertEqual(store().devices(for: license(devices: declared)).map(\.name), ["Studio-Mac"])
    }

    private func store2() -> LicenseDeviceStore {
        LicenseDeviceStore(fileURL: folder.appendingPathComponent(LicenseDeviceStore.fileName))
    }
}
