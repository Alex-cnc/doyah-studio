import Foundation
import PostgresNIO

/// 把 PostgresNIO 返回的二进制 Cell 转成**用户可读的字符串**（结果表 / 行详情 / CLI 三处共用）。
///
/// ## 这一版修的是什么（队列 L-74，开发循环第 79 轮）
///
/// PostgresNIO 在扩展查询协议下要求 binary 结果格式，而这里原先只覆盖
/// bool / 整型 / 浮点 / numeric / text 族 / uuid / 日期时间 —— 其余类型（`inet` / `cidr` /
/// `macaddr` / `interval` / `time` / `timetz` / 非 UTF-8 的 `bytea` / 各类数组 / `point` /
/// `money` / `bit` / 范围类型）**落到最后那一句 `String(describing: buffer)`**：用户拿到的不是值，
/// 是**驱动内部对象的描述**，而且里面带控制字符 ⇒ CLI 的表格排版当场被打断（一行值劈成好几行）。
///
/// ## 现在的口径（一句话可推翻，落在 `Docs/概要设计.md` §3.9）
///
/// 1. **覆盖到的类型按型解码**，形态**对齐 psql**（同一串字符；对照基准见
///    `Scripts/test-session-management.sh` §7 —— 同一批字面量 psql 与我们的 CLI 逐条相等）；
/// 2. **覆盖不到的类型如实说「认不出」**：`[类型名 字节数B] \x十六进制`，
///    而不是把内部描述倒给用户、也不再印控制字符；
/// 3. **任何输出都不许含控制字符**（除了文本类类型原样保留的内容）—— 否则排版被打断；
/// 4. 类型**已知但值特殊**的（合法 UTF-8 的 `bytea`）沿用 `FR-DATA-05` 已登记的口径：
///    按 UTF-8 显示为文本（`\x48656c6c6f` → `Hello`），非法字节序列才印 `\x…`。
///
/// **为什么兜底标记是全语言中立的**：这句要出现在结果表 / 行详情 / CLI 三处，而 Core
/// **不知道用户选的语言**（语言住在 App 侧，Core 是库；把语言塞进服务层是另一条口径）。
/// 与其在 Core 里猜一个语言（或写死中文，撞 R-45 的棘轮），不如用一个不带语言的记号。
public enum PostgresCellFormatter {
    /// 兜底标记里十六进制预览的字节上限。
    static let hexPreviewLimit = 16

    public static func format(_ cell: PostgresCell) -> String? {
        guard let buffer = cell.bytes else {
            return nil
        }
        let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []

        if let decoded = decode(cell.dataType, bytes: bytes) {
            return decoded
        }

        // 服务端已经给了文本格式（老路径：不是所有查询都走 binary）。
        if cell.format == .text, let text = String(bytes: bytes, encoding: .utf8) {
            return text
        }

        // 类型认不出，但载荷本身就是文本（合法 UTF-8 且无控制字符）⇒ 原样显示：
        // 这是 `FR-DATA-05` 已登记的口径（合法 UTF-8 的 bytea 显示为文本），同时让
        // 自定义枚举之类「binary 里其实就是文本」的类型仍然可读。
        if let text = plainText(bytes) {
            return text
        }

        return unreadable(cell.dataType, bytes: bytes)
    }

    /// 按类型解一段字节（供数组元素 / 范围边界复用，也供单测逐型钉住）。
    ///
    /// 返回 `nil` = **这个类型我们不认识**（上层印「认不出」标记），不是「值是 NULL」。
    public static func decode(_ type: PostgresDataType, bytes: [UInt8]) -> String? {
        if let known = decodeKnownType(cell(type, bytes: bytes)) {
            return known
        }

        switch type {
        case .inet:
            return PostgresWireValue.networkAddress(bytes, alwaysIncludeMask: false)
        case .cidr:
            return PostgresWireValue.networkAddress(bytes, alwaysIncludeMask: true)
        case .macaddr, .macaddr8:
            return PostgresWireValue.macAddress(bytes)
        case .bytea:
            return byteaText(bytes)
        case .interval:
            return PostgresWireValue.interval(bytes)
        case .time:
            return PostgresWireValue.timeOfDay(bytes)
        case .timetz:
            return PostgresWireValue.timeWithZone(bytes)
        case .bit, .varbit:
            return PostgresWireValue.bitString(bytes)
        case .money:
            return PostgresWireValue.money(bytes)
        case .point:
            return PostgresWireValue.point(bytes)
        case .box:
            return PostgresWireValue.box(bytes)
        case .lseg:
            return PostgresWireValue.lseg(bytes)
        case .line:
            return PostgresWireValue.line(bytes)
        case .circle:
            return PostgresWireValue.circle(bytes)
        case .path:
            return PostgresWireValue.path(bytes)
        case .polygon:
            return PostgresWireValue.polygon(bytes)
        default:
            break
        }

        if let subtype = Self.rangeSubtypes[type.rawValue] {
            return PostgresWireValue.range(bytes, subtype: subtype) { subtype, payload in
                decode(PostgresDataType(subtype), bytes: payload)
            }
        }
        if let subtype = Self.multirangeSubtypes[type.rawValue] {
            return PostgresWireValue.multirange(bytes, subtype: subtype) { subtype, payload in
                decode(PostgresDataType(subtype), bytes: payload)
            }
        }
        if Self.arrayElementOIDs[type.rawValue] != nil {
            return PostgresWireValue.array(bytes) { elementType, payload in
                decode(PostgresDataType(elementType), bytes: payload)
                    ?? unreadable(PostgresDataType(elementType), bytes: payload)
            }
        }
        return nil
    }

    /// 覆盖不到的类型：**点名类型 + 字节数 + 十六进制预览**（全语言中立，见类头注释）。
    static func unreadable(_ type: PostgresDataType, bytes: [UInt8]) -> String {
        let preview = bytes.prefix(hexPreviewLimit).map { String(format: "%02x", $0) }.joined()
        let ellipsis = bytes.count > hexPreviewLimit ? "…" : ""
        return "[\(type) \(bytes.count)B] \\x\(preview)\(ellipsis)"
    }

    /// 合法 UTF-8 且**不含控制字符**才算文本（控制字符会打断 CLI 的表格排版）。
    static func plainText(_ bytes: [UInt8]) -> String? {
        guard let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        guard !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return text
    }

    /// `bytea`：合法 UTF-8 按文本（`FR-DATA-05` 已登记），否则按 Postgres 的十六进制写法。
    static func byteaText(_ bytes: [UInt8]) -> String {
        plainText(bytes) ?? PostgresWireValue.hex(bytes)
    }

    private static func decodeKnownType(_ cell: PostgresCell) -> String? {
        switch cell.dataType {
        case .bool:
            if let value = try? cell.decode(Bool.self) {
                return value ? "true" : "false"
            }
        case .int2:
            if let value = try? cell.decode(Int16.self) {
                return String(value)
            }
        case .int4:
            if let value = try? cell.decode(Int32.self) {
                return String(value)
            }
        case .int8:
            if let value = try? cell.decode(Int64.self) {
                return String(value)
            }
        case .oid:
            if let value = try? cell.decode(Int.self) {
                return String(value)
            }
        case .float4:
            if let value = try? cell.decode(Float.self) {
                return String(value)
            }
        case .float8:
            if let value = try? cell.decode(Double.self) {
                return String(value)
            }
        case .numeric:
            if let value = try? cell.decode(Decimal.self) {
                return String(describing: value)
            }
        case .text, .varchar, .bpchar, .name, .json, .jsonb, .xml:
            if let value = try? cell.decode(String.self) {
                return value
            }
        case .uuid:
            if let value = try? cell.decode(UUID.self) {
                return value.uuidString
            }
        case .date, .timestamp, .timestamptz:
            if let value = try? cell.decode(Date.self) {
                return ISO8601DateFormatter().string(from: value)
            }
        default:
            break
        }
        return nil
    }

    /// 造一个只用来**解码**的 Cell（`decodeKnownType` 与单测都走这条，避免两套读法）。
    static func cell(_ type: PostgresDataType, bytes: [UInt8]) -> PostgresCell {
        var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        return PostgresCell(bytes: buffer, dataType: type, format: .binary, columnName: "", columnIndex: 0)
    }

    // MARK: - 类型表（oid 一律取自真库 `pg_type`，不凭记忆写）

    /// 数组类型 oid → 元素类型 oid（元素实际怎么解由载荷头部自带的 oid 决定，
    /// 这张表只用来**认出这是一个数组**）。
    static let arrayElementOIDs: [UInt32: UInt32] = [
        199: 114, 143: 142, 629: 628, 651: 650, 719: 718, 775: 774, 791: 790,
        1000: 16, 1001: 17, 1002: 18, 1003: 19, 1005: 21, 1007: 23, 1009: 25,
        1014: 1042, 1015: 1043, 1016: 20, 1017: 600, 1018: 601, 1019: 602, 1020: 603,
        1021: 700, 1022: 701, 1027: 604, 1028: 26, 1040: 829, 1041: 869,
        1182: 1082, 1183: 1083, 1185: 1184, 1187: 1186, 1231: 1700, 1270: 1266,
        1561: 1560, 1563: 1562, 2951: 2950, 3807: 3802,
        3905: 3904, 3907: 3906, 3909: 3908, 3911: 3910, 3913: 3912, 3927: 3926,
        6150: 4451, 6151: 4532, 6152: 4533, 6153: 4534, 6155: 4535, 6157: 4536,
    ]

    /// 范围类型 oid → 子类型 oid（边界的引号由边界自己的文本决定，见 `PostgresWireValue.range`）。
    static let rangeSubtypes: [UInt32: UInt32] = [
        3904: 23,     // int4range
        3926: 20,     // int8range
        3906: 1700,   // numrange
        3912: 1082,   // daterange
        3908: 1114,   // tsrange
        3910: 1184,   // tstzrange
    ]

    /// 多范围类型 oid → 子类型 oid。
    static let multirangeSubtypes: [UInt32: UInt32] = [
        4451: 23,     // int4multirange
        4532: 1700,   // nummultirange
        4533: 1114,   // tsmultirange
        4534: 1184,   // tstzmultirange
        4535: 1082,   // datemultirange
        4536: 20,     // int8multirange
    ]
}
