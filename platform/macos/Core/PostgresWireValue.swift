import Foundation

/// Postgres **线格式（binary）的纯解码**：一串字节进去、文本形态出来。
///
/// ## 为什么单列一个文件（队列 L-74，开发循环第 79 轮）
///
/// `Core/PostgresCellFormatter.swift` 管的是「这个 cell 该怎么显示」；这里管的是
/// 「这一串字节按 Postgres 的 binary 约定**是什么值**」。两者分开的收益是：这一层是**纯函数、
/// 零依赖**（只有 Foundation），单测可以**造一段字节、断言文本**，不必连库、不必造 Cell。
///
/// ## 三条纪律
///
/// 1. **对齐 psql 的文本形态，不另立一套**：用户拿 psql 的输出与我们的界面比对时，
///    两边应该印出同一串字符。对照基准 = `Scripts/test-session-management.sh` §7 ——
///    同一批字面量分别经 psql（文本形态）与我们的 CLI（binary 解码）印出，**逐条相等**才算过。
/// 2. **拿不准就返回 nil**：上层会印「认不出」标记（类型名 + 字节数 + 十六进制预览）。
///    这里不许硬猜、不许把半截东西当值返回 —— 猜错的值比一句「认不出」危险得多。
/// 3. **不看平台**：只用 Foundation（Core 平台中立，见需求书 §0.8）。IPv4/IPv6 的点分 /
///    冒号分写法是自己实现的（`inet_ntop` 是平台 API），IPv6 压缩按 RFC 5952。
enum PostgresWireValue {

    // MARK: - 基本读取（都是大端）

    static func int32(_ bytes: ArraySlice<UInt8>) -> Int32? {
        guard bytes.count >= 4 else { return nil }
        let slice = Array(bytes.prefix(4))
        let value = UInt32(slice[0]) << 24 | UInt32(slice[1]) << 16 | UInt32(slice[2]) << 8 | UInt32(slice[3])
        return Int32(bitPattern: value)
    }

    static func int64(_ bytes: ArraySlice<UInt8>) -> Int64? {
        guard bytes.count >= 8 else { return nil }
        var value: UInt64 = 0
        for byte in bytes.prefix(8) {
            value = value << 8 | UInt64(byte)
        }
        return Int64(bitPattern: value)
    }

    static func double(_ bytes: ArraySlice<UInt8>) -> Double? {
        guard bytes.count >= 8 else { return nil }
        var bits: UInt64 = 0
        for byte in bytes.prefix(8) {
            bits = bits << 8 | UInt64(byte)
        }
        return Double(bitPattern: bits)
    }

    /// 与 psql 一致的浮点写法（PG 12 起默认 `extra_float_digits=1` ⇒ **最短可往返**表示，
    /// 与 Swift 的 `String(Double)` 同族；差别只在整数值：PG 印 `2`，Swift 印 `2.0`）。
    static func number(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        var text = String(value)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text
    }

    static func hex(_ bytes: [UInt8]) -> String {
        "\\x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 网络地址（inet 869 / cidr 650）

    /// binary：`[family:1][bits:1][is_cidr:1][addrlen:1][addr:addrlen]`，
    /// family `2` = IPv4、`3` = IPv6。
    ///
    /// 掩码位数的写法**实测过**（psql 16.2，两种形态不一样）：
    ///   · `inet` —— 位数等于满位（IPv4 32 / IPv6 128）时**不写** `/bits`
    ///     （`inet '127.0.0.1'` 印 `127.0.0.1`、`inet '1.2.3.4/24'` 印 `1.2.3.4/24`）；
    ///   · `cidr` —— **一律写** `/bits`（`cidr '1.2.3.4/32'` 印 `1.2.3.4/32`）。
    static func networkAddress(_ bytes: [UInt8], alwaysIncludeMask: Bool) -> String? {
        guard bytes.count >= 4 else { return nil }
        let family = bytes[0]
        let bits = bytes[1]
        let addressLength = Int(bytes[3])
        guard addressLength == 4 || addressLength == 16, bytes.count >= 4 + addressLength else { return nil }
        let address = Array(bytes[4 ..< 4 + addressLength])
        switch (family, addressLength) {
        case (2, 4):
            guard bits <= 32 else { return nil }
            return ipv4Text(address) + maskSuffix(bits: bits, fullWidth: 32, alwaysInclude: alwaysIncludeMask)
        case (3, 16):
            guard bits <= 128 else { return nil }
            return ipv6Text(address) + maskSuffix(bits: bits, fullWidth: 128, alwaysInclude: alwaysIncludeMask)
        default:
            return nil
        }
    }

    private static func maskSuffix(bits: UInt8, fullWidth: UInt8, alwaysInclude: Bool) -> String {
        if !alwaysInclude, bits == fullWidth {
            return ""
        }
        return "/\(bits)"
    }

    static func ipv4Text(_ bytes: [UInt8]) -> String {
        bytes.map { String($0) }.joined(separator: ".")
    }

    /// IPv6 的文本形态：小写、每段去前导零、**最长的一段零压缩成 `::`**（RFC 5952；
    /// 长度相同时压最左边那一段）；IPv4-mapped（`::ffff:a.b.c.d`）按点分写 —— 与 PG 一致。
    static func ipv6Text(_ bytes: [UInt8]) -> String {
        let groups = (0 ..< 8).map { UInt16(bytes[$0 * 2]) << 8 | UInt16(bytes[$0 * 2 + 1]) }

        let isIPv4Mapped = groups[0 ..< 5].allSatisfy { $0 == 0 } && groups[5] == 0xFFFF
        if isIPv4Mapped {
            return "::ffff:" + ipv4Text(Array(bytes[12 ..< 16]))
        }

        var bestStart = -1
        var bestLength = 0
        var index = 0
        while index < 8 {
            guard groups[index] == 0 else {
                index += 1
                continue
            }
            var run = 0
            while index + run < 8, groups[index + run] == 0 {
                run += 1
            }
            if run > bestLength {
                bestLength = run
                bestStart = index
            }
            index += run
        }
        if bestLength < 2 {
            bestStart = -1
            bestLength = 0
        }

        var head: [String] = []
        var tail: [String] = []
        for (position, group) in groups.enumerated() {
            let text = String(group, radix: 16)
            if bestStart >= 0, position >= bestStart, position < bestStart + bestLength {
                continue
            }
            if bestStart >= 0, position < bestStart {
                head.append(text)
            } else if bestStart >= 0 {
                tail.append(text)
            } else {
                head.append(text)
            }
        }
        if bestStart < 0 {
            return head.joined(separator: ":")
        }
        return head.joined(separator: ":") + "::" + tail.joined(separator: ":")
    }

    /// macaddr（829）= 6 字节 / macaddr8（774）= 8 字节，小写、冒号分。
    static func macAddress(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6 || bytes.count == 8 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    // MARK: - 时间类

    /// interval（1186）：`[time:8][day:4][month:4]`（微秒 / 天 / 月）。
    /// 写法照 PG 的 `EncodeInterval`：年与月分开印、每段带**自己的符号**；时间段的符号 `-`，
    /// 而当天或月为负、时间为正时前面补 `+`（`interval '-1 day 01:00:00'` 在 psql 里印
    /// `-1 days +01:00:00`）；全零印 `00:00:00`。
    static func interval(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 16,
              let micros = int64(bytes[0 ..< 8]),
              let days = int32(bytes[8 ..< 12]),
              let months = int32(bytes[12 ..< 16])
        else { return nil }

        var parts: [String] = []
        if months != 0 {
            let years = months / 12
            let remainderMonths = months % 12
            if years != 0 {
                parts.append("\(years) year\(years == 1 ? "" : "s")")
            }
            if remainderMonths != 0 {
                parts.append("\(remainderMonths) mon\(remainderMonths == 1 ? "" : "s")")
            }
        }
        if days != 0 {
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        if micros != 0 {
            let isNegative = micros < 0
            let magnitude = isNegative ? -micros : micros
            let sign = isNegative ? "-" : ((months < 0 || days < 0) ? "+" : "")
            parts.append(sign + clockText(magnitude))
        }
        if parts.isEmpty {
            return "00:00:00"
        }
        return parts.joined(separator: " ")
    }

    /// time（1083）：`[微秒:8]`（自午夜起）。
    static func timeOfDay(_ bytes: [UInt8]) -> String? {
        guard let micros = int64(bytes.prefix(8)), micros >= 0 else { return nil }
        return clockText(micros)
    }

    /// timetz（1266）：`[微秒:8][时区秒:4]`，时区是**西为正**的秒数（+08:00 存的是 -28800）。
    /// 文本形态末尾带 ±HH 或 ±HH:MM（分量为 0 时只写小时，psql 里 `timetz '08:00:00-04'` → `-04`）。
    static func timeWithZone(_ bytes: [UInt8]) -> String? {
        guard let micros = int64(bytes.prefix(8)), let zone = int32(bytes[8 ..< 12]), micros >= 0 else { return nil }
        let minutes = abs(Int(zone)) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        let sign = zone <= 0 ? "+" : "-"
        let offset = remainder == 0
            ? String(format: "%@%02d", sign, hours)
            : String(format: "%@%02d:%02d", sign, hours, remainder)
        return clockText(micros) + offset
    }

    /// `HH:MM:SS[.微秒]`（小数末尾的零去掉；小时不设上限 —— interval 会有 `25:00:00`）。
    static func clockText(_ micros: Int64) -> String {
        let hours = micros / 3_600_000_000
        let minutes = (micros % 3_600_000_000) / 60_000_000
        let seconds = (micros % 60_000_000) / 1_000_000
        let fraction = micros % 1_000_000
        var text = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        if fraction != 0 {
            var digits = String(format: "%06d", fraction)
            while digits.hasSuffix("0") {
                digits.removeLast()
            }
            text += "." + digits
        }
        return text
    }

    // MARK: - 位串 / 金额

    /// bit（1560）/ varbit（1562）：`[位数:4][字节]`，高位在前。
    static func bitString(_ bytes: [UInt8]) -> String? {
        guard let bitCount = int32(bytes.prefix(4)), bitCount >= 0 else { return nil }
        let payload = Array(bytes.dropFirst(4))
        guard payload.count >= (Int(bitCount) + 7) / 8 else { return nil }
        var text = ""
        for position in 0 ..< Int(bitCount) {
            let byte = payload[position / 8]
            let mask = UInt8(1 << (7 - position % 8))
            text += (byte & mask) == 0 ? "0" : "1"
        }
        return text
    }

    /// money（790）：`[分:8]`。**如实登记边界**：binary 里只有「分」，没有货币符号、
    /// 也没有千分位（那两个由服务端 `lc_monetary` 决定）⇒ 这里只印数字（`1234.56`），
    /// 不假装知道货币单位（psql 里同一值印 `$1,234.56`）。
    static func money(_ bytes: [UInt8]) -> String? {
        guard let cents = int64(bytes.prefix(8)) else { return nil }
        let isNegative = cents < 0
        let magnitude = isNegative ? -cents : cents
        let text = "\(magnitude / 100)." + String(format: "%02d", magnitude % 100)
        return (isNegative ? "-" : "") + text
    }

    // MARK: - 几何类

    static func point(_ bytes: [UInt8]) -> String? {
        guard let x = double(bytes[0 ..< 8]), let y = double(bytes[8 ..< 16]) else { return nil }
        return "(\(number(x)),\(number(y)))"
    }

    /// box（603）：`[高x][高y][低x][低y]` —— 文本形态是**高角在前**（psql 里
    /// `box '(1,2),(3,4)'` 印 `(3,4),(1,2)`）。
    static func box(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 32,
              let highX = double(bytes[0 ..< 8]), let highY = double(bytes[8 ..< 16]),
              let lowX = double(bytes[16 ..< 24]), let lowY = double(bytes[24 ..< 32])
        else { return nil }
        return "(\(number(highX)),\(number(highY))),(\(number(lowX)),\(number(lowY)))"
    }

    /// lseg（601）：`[x1][y1][x2][y2]`。
    static func lseg(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 32,
              let x1 = double(bytes[0 ..< 8]), let y1 = double(bytes[8 ..< 16]),
              let x2 = double(bytes[16 ..< 24]), let y2 = double(bytes[24 ..< 32])
        else { return nil }
        return "[(\(number(x1)),\(number(y1))),(\(number(x2)),\(number(y2)))]"
    }

    /// line（628）：`[A][B][C]`（方程 Ax + By + C = 0）。
    static func line(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 24,
              let a = double(bytes[0 ..< 8]), let b = double(bytes[8 ..< 16]), let c = double(bytes[16 ..< 24])
        else { return nil }
        return "{\(number(a)),\(number(b)),\(number(c))}"
    }

    /// circle（718）：`[中心x][中心y][半径]`。
    static func circle(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 24,
              let x = double(bytes[0 ..< 8]), let y = double(bytes[8 ..< 16]), let radius = double(bytes[16 ..< 24])
        else { return nil }
        return "<(\(number(x)),\(number(y))),\(number(radius))>"
    }

    /// path（602）：`[闭合:1][点数:4][点…]` —— 闭合用 `((…))`、开放用 `[(…)]`。
    static func path(_ bytes: [UInt8]) -> String? {
        guard let isClosed = bytes.first, let count = int32(bytes[1 ..< 5]), count >= 0 else { return nil }
        guard let points = pointList(bytes, offset: 5, count: Int(count)) else { return nil }
        return isClosed == 0 ? "[\(points)]" : "(\(points))"
    }

    /// polygon（604）：`[点数:4][点…]`。
    static func polygon(_ bytes: [UInt8]) -> String? {
        guard let count = int32(bytes.prefix(4)), count >= 0 else { return nil }
        guard let points = pointList(bytes, offset: 4, count: Int(count)) else { return nil }
        return "(\(points))"
    }

    private static func pointList(_ bytes: [UInt8], offset: Int, count: Int) -> String? {
        guard bytes.count >= offset + count * 16 else { return nil }
        var points: [String] = []
        for index in 0 ..< count {
            let base = offset + index * 16
            guard let x = double(bytes[base ..< base + 8]), let y = double(bytes[base + 8 ..< base + 16]) else { return nil }
            points.append("(\(number(x)),\(number(y)))")
        }
        return points.joined(separator: ",")
    }

    // MARK: - 数组（任意 `*[]` 类型）

    /// binary：`[维数:4][有 NULL:4][元素类型 oid:4]{[本维长度:4][本维下界:4]}[元素…]`，
    /// 元素是 `[长度:4][字节]`，长度 `-1` = NULL。
    ///
    /// **元素自己怎么解由调用方给**（`decode`）—— 数组里可能是任何类型（numeric / uuid / 时间…），
    /// 那些类型交给驱动自己的解码器（见 `PostgresCellFormatter.decode`）。
    static func array(_ bytes: [UInt8], decode: (UInt32, [UInt8]) -> String) -> String? {
        guard let dimensions = int32(bytes[0 ..< 4]), dimensions >= 0, dimensions <= 8,
              let elementOID = uint32(bytes[8 ..< 12])
        else { return nil }

        var lengths: [Int] = []
        var cursor = 12
        for _ in 0 ..< Int(dimensions) {
            guard let length = int32(bytes[cursor ..< cursor + 4]), length >= 0 else { return nil }
            lengths.append(Int(length))
            cursor += 8   // 长度 4 + 下界 4（下界不参与文本形态）
        }

        func readElements(dimension: Int) -> String? {
            var items: [String] = []
            for _ in 0 ..< lengths[dimension] {
                if dimension == lengths.count - 1 {
                    guard let length = int32(bytes[cursor ..< cursor + 4]) else { return nil }
                    cursor += 4
                    if length >= 0 {
                        let payload = Array(bytes[cursor ..< cursor + Int(length)])
                        cursor += Int(length)
                        items.append(quotedElement(decode(elementOID, payload)))
                    } else {
                        items.append("NULL")
                    }
                } else {
                    guard let nested = readElements(dimension: dimension + 1) else { return nil }
                    items.append(nested)
                }
            }
            return "{" + items.joined(separator: ",") + "}"
        }

        if dimensions == 0 {
            return "{}"
        }
        return readElements(dimension: 0)
    }

    /// 数组元素 / 多维数组里的引用规则（照 PG 的 `array_out`）：含 `{}`、`,`、`"`、`\`
    /// 或空白，是空串，或（不分大小写）等于 `NULL` ⇒ 加引号并把 `"`、`\` 转义。
    static func quotedElement(_ text: String) -> String {
        let needsQuotes = text.isEmpty
            || text.caseInsensitiveCompare("NULL") == .orderedSame
            || text.contains { character in
                character == "{" || character == "}" || character == "," || character == "\""
                    || character == "\\" || character == " " || character == "\t"
                    || character == "\n" || character == "\r"
            }
        guard needsQuotes else { return text }
        var escaped = ""
        for character in text {
            if character == "\"" || character == "\\" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "\"" + escaped + "\""
    }

    // MARK: - 范围类型

    /// binary：`[标志位:1]` + 可选的「下界长度:4 + 下界」与「上界长度:4 + 上界」。
    /// 标志位：`0x01` 空 / `0x02` 下界闭 / `0x04` 上界闭 / `0x08` 下界无穷 / `0x10` 上界无穷。
    ///
    /// 边界的引号**按边界自己的文本判**（照 PG）：整型 / 数字 / 日期的边界不加引号
    /// （`[1,10)`、`[2026-01-01,2026-02-01)`），含空白的时间戳边界加
    /// （`["2026-01-01 00:00:00+08",…)`）—— 不是按类型一刀切。
    static func range(
        _ bytes: [UInt8],
        subtype: UInt32,
        decode: (UInt32, [UInt8]) -> String?
    ) -> String? {
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 != 0 {
            return "empty"
        }
        var cursor = 1

        func readBound(infinite: Bool) -> String? {
            if infinite {
                return ""
            }
            guard let length = int32(bytes[cursor ..< cursor + 4]), length >= 0 else { return nil }
            cursor += 4
            let payload = Array(bytes[cursor ..< cursor + Int(length)])
            cursor += Int(length)
            guard let text = decode(subtype, payload) else { return nil }
            return quotedElement(text)
        }

        guard let lower = readBound(infinite: flags & 0x08 != 0),
              let upper = readBound(infinite: flags & 0x10 != 0)
        else { return nil }
        let opening = flags & 0x02 != 0 ? "[" : "("
        let closing = flags & 0x04 != 0 ? "]" : ")"
        return opening + lower + "," + upper + closing
    }

    /// multirange：`[段数:4]` + 每段 `[长度:4][范围字节]`（没有数组那层「维数 / 元素 oid」头）。
    static func multirange(
        _ bytes: [UInt8],
        subtype: UInt32,
        decode: (UInt32, [UInt8]) -> String?
    ) -> String? {
        guard let count = int32(bytes.prefix(4)), count >= 0 else { return nil }
        var cursor = 4
        var items: [String] = []
        for _ in 0 ..< Int(count) {
            guard let length = int32(bytes[cursor ..< cursor + 4]), length >= 0 else { return nil }
            cursor += 4
            let payload = Array(bytes[cursor ..< cursor + Int(length)])
            cursor += Int(length)
            guard let text = range(payload, subtype: subtype, decode: decode) else {
                return nil
            }
            // **不**给整段范围加引号：PG 的 multirange 输出就是「各段范围文本用逗号连接」
            // （实测 `int4multirange` → `{[1,3),[5,7)}`、`tstzmultirange` →
            // `{["2026-01-01 00:00:00+08",...)` —— 引号只出现在边界需要它的地方）。
            items.append(text)
        }
        return "{" + items.joined(separator: ",") + "}"
    }

    // MARK: - 小工具

    private static func uint32(_ bytes: ArraySlice<UInt8>) -> UInt32? {
        guard let value = int32(bytes) else { return nil }
        return UInt32(bitPattern: value)
    }
}
