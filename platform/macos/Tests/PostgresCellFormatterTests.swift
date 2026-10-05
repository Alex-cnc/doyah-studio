import XCTest
import PostgresNIO
@testable import DoyahCore

/// **非文本类型在扩展查询协议下被倒成原始字节**（队列 L-74，开发循环第 79 轮）。
///
/// 缺陷原话：`inet` / `cidr` / `macaddr` / `interval` / `time` / `timetz` / 非 UTF-8 的 `bytea` /
/// 各类数组 / `point` / `money` / `bit` / 范围类型在结果表 / 行详情 / CLI 里那一格显示成
/// **驱动的内部描述**（`String(describing: buffer)`），值里带控制字符 ⇒ CLI 的表格排版被打断。
///
/// 这个文件钉四件事（改前实测命令见 `.build/l74-before.log`）：
/// 1. **逐型解码**：每一型都给一段**手工按线格式造的字节**，断言印出来的文本 —— 期望值是
///    `psql` 对同一字面量的文本形态（对照基准 = `Scripts/test-session-management.sh` §7）；
/// 2. **认得出 / 认不出的边界**：类型表里没有的，印「类型 + 字节数 + 十六进制预览」，
///    而**不再**是内部对象描述；
/// 3. **任何输出都不含控制字符**（原来那些「被打断的排版」正是控制字符引起的）；
/// 4. 类型知道但载荷是文本的（合法 UTF-8 的 `bytea`）沿用 `FR-DATA-05` 已登记的口径。
final class PostgresCellFormatterTests: XCTestCase {

    // MARK: - 夹具（手工造线格式字节，不连库）

    private func be32(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private func be64(_ value: Int64) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private func beDouble(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Array($0) }
    }

    private func network(family: UInt8, bits: UInt8, isCIDR: UInt8, address: [UInt8]) -> [UInt8] {
        [family, bits, isCIDR, UInt8(address.count)] + address
    }

    private func interval(micros: Int64, days: Int32, months: Int32) -> [UInt8] {
        be64(micros) + be32(days) + be32(months)
    }

    private func arrayPayload(elementOID: Int32, dimensions: [Int], elements: [[UInt8]?]) -> [UInt8] {
        var bytes = be32(Int32(dimensions.count)) + be32(0) + be32(elementOID)
        for length in dimensions {
            bytes += be32(Int32(length)) + be32(1)
        }
        for element in elements {
            if let element {
                bytes += be32(Int32(element.count)) + element
            } else {
                bytes += be32(-1)
            }
        }
        return bytes
    }

    /// 走产品真入口（`PostgresCellFormatter.format`），不是绕过它调内部函数。
    private func shown(_ type: PostgresDataType, _ bytes: [UInt8]) -> String? {
        PostgresCellFormatter.format(PostgresCellFormatter.cell(type, bytes: bytes))
    }

    private func assertShown(
        _ type: PostgresDataType,
        _ bytes: [UInt8],
        _ expected: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(shown(type, bytes), expected, message, file: file, line: line)
    }

    // MARK: - NULL 与文本类（既有行为不许被这一轮改坏）

    func testNullCellStaysNil() {
        XCTAssertNil(PostgresCellFormatter.format(PostgresCell(
            bytes: nil,
            dataType: .inet,
            format: .binary,
            columnName: "client_addr",
            columnIndex: 0
        )))
    }

    func testIntegerAndTextStillReadable() {
        assertShown(.int4, be32(42), "42")
        assertShown(.bool, [1], "true")
        assertShown(.text, Array("你好".utf8), "你好")
    }

    // MARK: - inet / cidr（869 / 650）

    func testInetOmitsMaskAtFullWidth() {
        assertShown(.inet, network(family: 2, bits: 32, isCIDR: 0, address: [127, 0, 0, 1]), "127.0.0.1")
    }

    func testInetIPv4WithHostBits() {
        assertShown(.inet, network(family: 2, bits: 24, isCIDR: 0, address: [192, 168, 5, 223]), "192.168.5.223/24")
    }

    func testInetIPv6CompressesZeroRun() {
        let address: [UInt8] = [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        assertShown(.inet, network(family: 3, bits: 64, isCIDR: 0, address: address), "2001:db8::1/64")
    }

    func testInetIPv6AllZeroAndIPv4Mapped() {
        let allZero = [UInt8](repeating: 0, count: 16)
        assertShown(.inet, network(family: 3, bits: 128, isCIDR: 0, address: allZero), "::")
        let mapped: [UInt8] = [UInt8](repeating: 0, count: 10) + [0xff, 0xff, 1, 2, 3, 4]
        assertShown(.inet, network(family: 3, bits: 128, isCIDR: 0, address: mapped), "::ffff:1.2.3.4")
    }

    func testCidrAlwaysCarriesMask() {
        assertShown(.cidr, network(family: 2, bits: 8, isCIDR: 1, address: [10, 0, 0, 0]), "10.0.0.0/8")
        // 与 inet 的差别就在这：cidr 即便满位也写 `/bits`（psql 里 `cidr '1.2.3.4/32'` → `1.2.3.4/32`）
        assertShown(.cidr, network(family: 2, bits: 32, isCIDR: 1, address: [1, 2, 3, 4]), "1.2.3.4/32")
    }

    func testMalformedNetworkIsNotGuessed() {
        // 4 字节头 + 声明 16 字节地址却只给 4 字节 ⇒ 如实说认不出，不许硬猜
        XCTAssertEqual(shown(.inet, [2, 32, 0, 16, 127, 0, 0, 1])?.hasPrefix("[INET"), true)
    }

    // MARK: - macaddr / macaddr8（829 / 774）

    func testMacaddr() {
        assertShown(.macaddr, [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03], "08:00:2b:01:02:03")
    }

    func testMacaddr8() {
        assertShown(.macaddr8, [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03, 0x04, 0x05], "08:00:2b:01:02:03:04:05")
    }

    // MARK: - bytea（17）

    func testByteaOfValidUTF8StaysText() {
        // FR-DATA-05 已登记的口径：`\x48656c6c6f` → `Hello`
        assertShown(.bytea, Array("Hello".utf8), "Hello")
    }

    func testByteaOfInvalidUTF8IsHex() {
        assertShown(.bytea, [0xff, 0xfe, 0x01], "\\xfffe01")
    }

    // MARK: - interval（1186）

    func testIntervalAllComponents() {
        assertShown(
            .interval,
            interval(micros: 4 * 3_600_000_000 + 5 * 60_000_000 + 6_500_000, days: 3, months: 14),
            "1 year 2 mons 3 days 04:05:06.5"
        )
    }

    func testIntervalNegativeMonthsSplitIntoYearsAndMons() {
        assertShown(.interval, interval(micros: 0, days: 0, months: -13), "-1 years -1 mons")
    }

    func testIntervalPositiveTimeAfterNegativeDaysKeepsPlusSign() {
        assertShown(.interval, interval(micros: 3_600_000_000, days: -1, months: 0), "-1 days +01:00:00")
    }

    func testIntervalNegativeTimeKeepsMinusSign() {
        assertShown(.interval, interval(micros: -500_000, days: 0, months: 0), "-00:00:00.5")
    }

    func testIntervalZeroAndLargeHours() {
        assertShown(.interval, interval(micros: 0, days: 0, months: 0), "00:00:00")
        assertShown(.interval, interval(micros: 25 * 3_600_000_000, days: 0, months: 0), "25:00:00")
    }

    // MARK: - time / timetz（1083 / 1266）

    func testTimeOfDay() {
        assertShown(.time, be64(12 * 3_600_000_000 + 34 * 60_000_000 + 56_789_000), "12:34:56.789")
    }

    func testTimeMidnightUpperBound() {
        assertShown(.time, be64(24 * 3_600_000_000), "24:00:00")
    }

    func testTimeWithZoneEastAndWest() {
        let noon = Int64(12 * 3_600_000_000 + 34 * 60_000_000 + 56_000_000)
        assertShown(.timetz, be64(noon) + be32(-28_800), "12:34:56+08")
        assertShown(.timetz, be64(noon) + be32(14_400), "12:34:56-04")
        assertShown(.timetz, be64(noon) + be32(-19_800), "12:34:56+05:30")
    }

    // MARK: - bit / varbit（1560 / 1562）

    func testBitString() {
        assertShown(.bit, be32(5) + [0b1010_1000], "10101")
        assertShown(.varbit, be32(3) + [0b1010_0000], "101")
    }

    // MARK: - money（790）

    func testMoneyKeepsCentsAndNoCurrencySymbol() {
        // 如实登记的边界：binary 里只有「分」，货币符号与千分位由服务端 lc_monetary 决定
        assertShown(.money, be64(123_456), "1234.56")
        assertShown(.money, be64(-5), "-0.05")
    }

    // MARK: - 几何类型

    func testPoint() {
        assertShown(.point, beDouble(1.5) + beDouble(2.5), "(1.5,2.5)")
        assertShown(.point, beDouble(2) + beDouble(-3), "(2,-3)")
    }

    func testBoxPrintsHighCornerFirst() {
        let bytes = beDouble(3) + beDouble(4) + beDouble(1) + beDouble(2)
        assertShown(.box, bytes, "(3,4),(1,2)")
    }

    func testSegmentLineAndCircle() {
        let segment = beDouble(1) + beDouble(2) + beDouble(3) + beDouble(4)
        assertShown(.lseg, segment, "[(1,2),(3,4)]")
        assertShown(.line, beDouble(2) + beDouble(-1) + beDouble(0), "{2,-1,0}")
        assertShown(.circle, beDouble(1) + beDouble(2) + beDouble(3), "<(1,2),3>")
    }

    func testPathOpenClosedAndPolygon() {
        let points = beDouble(1) + beDouble(2) + beDouble(3) + beDouble(4)
        assertShown(.path, [0] + be32(2) + points, "[(1,2),(3,4)]")
        assertShown(.path, [1] + be32(2) + points, "((1,2),(3,4))")
        let polygon = be32(3) + beDouble(1) + beDouble(2) + beDouble(3) + beDouble(4) + beDouble(5) + beDouble(6)
        assertShown(.polygon, polygon, "((1,2),(3,4),(5,6))")
    }

    // MARK: - 数组（任意 `*[]`）

    func testIntegerArray() {
        let payload = arrayPayload(elementOID: 23, dimensions: [3], elements: [be32(1), be32(2), be32(3)])
        assertShown(.int4Array, payload, "{1,2,3}")
    }

    func testArrayWithNullElement() {
        let payload = arrayPayload(elementOID: 23, dimensions: [3], elements: [be32(1), nil, be32(3)])
        assertShown(.int4Array, payload, "{1,NULL,3}")
    }

    func testTextArrayQuotesOnlyWhatNeedsQuoting() {
        let payload = arrayPayload(
            elementOID: 25,
            dimensions: [5],
            elements: ["a b", "c,d", "e\"f", "NULL", ""].map { Array($0.utf8) }
        )
        assertShown(.textArray, payload, "{\"a b\",\"c,d\",\"e\\\"f\",\"NULL\",\"\"}")
    }

    func testTwoDimensionalArray() {
        let payload = arrayPayload(
            elementOID: 23,
            dimensions: [2, 2],
            elements: [be32(1), be32(2), be32(3), be32(4)]
        )
        assertShown(.int4Array, payload, "{{1,2},{3,4}}")
    }

    func testEmptyArray() {
        assertShown(.int4Array, arrayPayload(elementOID: 23, dimensions: [0], elements: []), "{}")
    }

    func testByteaArrayQuotesBackslashElements() {
        let payload = arrayPayload(elementOID: 17, dimensions: [1], elements: [[0xff, 0xfe]])
        assertShown(.byteaArray, payload, "{\"\\\\xfffe\"}")
    }

    func testInetArrayElementCarriesItsOwnMask() {
        let payload = arrayPayload(
            elementOID: 869,
            dimensions: [1],
            elements: [network(family: 2, bits: 24, isCIDR: 0, address: [10, 0, 0, 1])]
        )
        assertShown(.inetArray, payload, "{10.0.0.1/24}")
    }

    // MARK: - 范围类型

    func testInt4RangeBindings() {
        let closedLower = [UInt8(0x02)] + be32(4) + be32(1) + be32(4) + be32(10)
        assertShown(PostgresDataType(3904), closedLower, "[1,10)")
    }

    func testEmptyAndUnboundedRanges() {
        assertShown(PostgresDataType(3904), [0x01], "empty")
        // 下界无穷、上界闭 [0x04]，上界 5
        let unboundedLower = [UInt8(0x08 | 0x04)] + be32(4) + be32(5)
        assertShown(PostgresDataType(3904), unboundedLower, "(,5]")
    }

    func testInt8RangeKeepsLargeBounds() {
        // 子类型 oid 来自台账表：numrange(3906) → numeric(1700)。这里用 int8range 钉住
        // 「非 int4 的整型子类型」也能解（大整数不丢精度）。
        let big = Int64(9_000_000_000)
        let payload = [UInt8(0x02)] + be32(8) + be64(big) + be32(8) + be64(big + 10)
        assertShown(PostgresDataType(3926), payload, "[9000000000,9000000010)")
    }

    func testMultirangeIsArrayOfRanges() {
        let first = [UInt8(0x02)] + be32(4) + be32(1) + be32(4) + be32(3)
        let second = [UInt8(0x02)] + be32(4) + be32(5) + be32(4) + be32(7)
        let payload = be32(2) + be32(Int32(first.count)) + first + be32(Int32(second.count)) + second
        assertShown(PostgresDataType(4451), payload, "{[1,3),[5,7)}")
    }

    // MARK: - 认不出的类型：如实说认不出

    func testUnrecognizedTypeNamesItselfInsteadOfDumpingInternals() {
        let marker = shown(PostgresDataType(9999), [0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual(marker, "[UNKNOWN 9999 4B] \\x01020304")
    }

    func testUnrecognizedTypePreviewIsTruncated() {
        let bytes = (0 ..< 40).map { UInt8($0) }
        let marker = shown(PostgresDataType(9999), bytes)
        XCTAssertEqual(marker?.hasPrefix("[UNKNOWN 9999 40B] \\x00010203"), true)
        XCTAssertEqual(marker?.hasSuffix("…"), true)
    }

    func testUnrecognizedTypeWithTextPayloadShowsTheText() {
        // 自定义枚举之类：binary 里其实就是文本 ⇒ 原样显示（否则「认不出」会把可读的东西藏起来）
        assertShown(PostgresDataType(9999), Array("active".utf8), "active")
    }

    func testControlCharactersNeverReachTheUser() {
        // 改前实测（队列 L-74）：这些类型的值印出来带控制字符，CLI 的表格排版当场被打断。
        // 这里把那一批现场逐条过一遍：**任何输出都不许含控制字符**。
        let cases: [(PostgresDataType, [UInt8])] = [
            (.inet, network(family: 2, bits: 32, isCIDR: 0, address: [127, 0, 0, 1])),
            (.cidr, network(family: 2, bits: 8, isCIDR: 1, address: [10, 0, 0, 0])),
            (.macaddr, [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03]),
            (.interval, interval(micros: 3_600_000_000, days: 1, months: 0)),
            (.time, be64(45_296_000_000)),
            (.timetz, be64(45_296_000_000) + be32(-28_800)),
            (.bytea, [0xff, 0xfe, 0x01]),
            (.point, beDouble(1) + beDouble(2)),
            (.money, be64(123_456)),
            (.bit, be32(5) + [0b1010_1000]),
            (PostgresDataType(3904), [UInt8(0x02)] + be32(4) + be32(1) + be32(4) + be32(10)),
            (.int4Array, arrayPayload(elementOID: 23, dimensions: [3], elements: [be32(1), be32(2), be32(3)])),
            (.byteaArray, arrayPayload(elementOID: 17, dimensions: [1], elements: [[0xff, 0xfe]])),
            (PostgresDataType(9999), [0x02, 0x00, 0x04, 0x7f, 0x00, 0x00, 0x01]),
        ]
        for (type, bytes) in cases {
            let text = shown(type, bytes)
            XCTAssertNotNil(text, "\(type) 应该有可读形态")
            let hasControl = (text ?? "").unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
            XCTAssertFalse(hasControl, "\(type) 的输出含控制字符：\(text ?? "<nil>")")
        }
    }

    // MARK: - 每一种范围 / 多范围都登记了（oid 表在 Scripts/cell-decode-coverage.json）

    func testTimestampWithZoneRangeKeepsItsOwnText() {
        // 边界的时间写法沿用本产品既有的 ISO 8601（与 psql 的 `"2026-01-01 00:00:00+08"` 不同，
        // 登记在证据脚本 Scripts/test-session-management.sh §7 的「有意不同」表里）。
        // 载荷取 `tstzrange('2026-01-01+08','2026-02-01+08')` 的二进制值。
        let payload = [UInt8(0x02)] + be32(8) + be64(820_512_000_000_000) + be32(8) + be64(823_190_400_000_000)
        assertShown(PostgresDataType(3910), payload, "[2025-12-31T16:00:00Z,2026-01-31T16:00:00Z)")
    }

    func testDateRangeKeepsItsBounds() {
        // `daterange('2026-01-01','2026-02-01')`：子类型 date 是「自 2000-01-01 起的天数」。
        let payload = [UInt8(0x02)] + be32(4) + be32(9_497) + be32(4) + be32(9_528)
        assertShown(PostgresDataType(3912), payload, "[2026-01-01T00:00:00Z,2026-02-01T00:00:00Z)")
    }

    func testEveryRangeAndMultirangeTypeIsRegistered() {
        // 范围 3904 / 3906 / 3908 / 3910 / 3912 与多范围 4451 / 4532 / 4533 / 4534 / 4535 / 4536
        // 都必须登记在表里 —— 少一个，下面这句就会印出「认不出」标记而不是空范围 / 空多范围。
        for oid: UInt32 in [3904, 3906, 3908, 3910, 3912] {
            assertShown(PostgresDataType(oid), [0x01], "empty")
        }
        for oid: UInt32 in [4451, 4532, 4533, 4534, 4535, 4536] {
            assertShown(PostgresDataType(oid), be32(0), "{}")
        }
    }
}
