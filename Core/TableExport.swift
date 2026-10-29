import Foundation

/// 整表 / 整库导出（FR-STD-DB-IO-002）的**计划与账**。
///
/// 由头（2026-10-29 第七十批实测）：这条需求的**取数机制早就在**——`CursorPaging` 服务端游标 +
/// `ResultStreamWriter` 流式写盘，CLI 的 `export --table` / `export --all-tables` 已真机验证
/// （12 万行 / 27 MB，内存增量远小于数据量，见需求规格 R-036）。真正缺的是**图形界面的入口**：
/// 对象树的右键菜单里一个导出条目都没有，于是「整表 / 整库导出」对用户来说等于不存在。
///
/// 因此本文件只放纯判定（**不许碰 IO**）：① 整表导出那条 `SELECT` 怎么拼；
/// ② 整库导出每张表落哪个文件；③ 逐表结局怎么记账、怎么报「行数与文件路径」（验收要点 ④）。
/// 取数走 `CursorFetcher`、写盘走 `ResultStreamWriter`，两者都不在这里。
///
/// 口径（写死在这里，调用方不许各写一份）：
/// * 整表导出 = `SELECT * FROM <限定名>`，**不加 `ORDER BY`** —— 为了顺序排一次要把全量读进内存，
///   正好毁掉流式的意义；而没有 `ORDER BY` 的查询本来就不保证顺序，所以账里如实写这一条
///   （`orderGuaranteed = false`），不假装导出文件的顺序与界面上的网格一致。
/// * 表名 / schema 只拒**结构性非法**（空名、含 `\0`）：**不用 `PrivilegeProbe.isValidIdentifier`**
///   那一道 —— 它要求首字符是字母或下划线，会把 `My Table`、`order items` 这类**合法**的
///   引用名一起拒掉（PG 里它们完全正常），而真正的注入面是引号转义：`quoteIdentifier` 会把
///   名字里的 `"` 双写、名字整体包在引号里。判据钉住的就是这一点（`Tests/TableExportTests`）。
/// * 服务端游标只有 PostgreSQL 有（`BEGIN` / `DECLARE` / `FETCH` / `CLOSE`）⇒
///   `streamingSupported(_:)` **一处**回答「这个连接能不能走流式」，界面据此决定给不给入口 ——
///   不让用户在 MySQL / GBase 上点一个必然失败的按钮。
/// * 敏感列**今天不排除**（需求否定面写着「不含敏感列除非你显式勾选」）：「哪些列算敏感」没有
///   口径，本文件不自己发明一张名单；账里用 `sensitiveColumnsExcluded: false` 如实记着，
///   免得后来的人以为「已经排除了」。
public enum TableExport {

    /// 计划阶段的拒绝理由。文案由调用方从语言表搬进来（Core 不留面向用户的字面量）。
    public enum Issue: Error, Equatable, CustomStringConvertible {
        /// 表名为空（对象树里不该出现，但入口是公开的，不能靠「调用的人都传对了」）。
        case emptyTableName
        /// 名字里含 `\0`：它既不是合法标识符，也没法安全地放进一条语句。
        case invalidIdentifier(String)
        /// 这个连接没有服务端游标 ⇒ 走不了流式。
        case streamingUnsupported(DatabaseType)

        public var description: String {
            switch self {
            case .emptyTableName: return "table name is empty"
            case .invalidIdentifier(let name): return "identifier contains NUL: \(name)"
            case .streamingUnsupported(let type): return "no server-side cursor for \(type.rawValue)"
            }
        }
    }

    // MARK: - 取数能力

    /// 这个连接能不能走服务端游标（= 能不能真的流式导出）。
    ///
    /// 判据只有一条：`CursorPaging` 生成的语句是 PostgreSQL 语义。查表放在 Core 而不是界面，
    /// 是为了让「菜单给不给这一项」与「执行时拦不拦」读同一处 —— 两处各写一份的话，
    /// 菜单会给出一个点了必然报错的按钮。
    public static func streamingSupported(_ dbType: DatabaseType) -> Bool {
        dbType == .postgresql
    }

    // MARK: - 整表导出

    /// 整表导出用的那条查询。
    ///
    /// - 限定名走 `SQLGenerator.qualifiedName`（方言自己决定要不要 schema 前缀）；
    /// - **不加 `ORDER BY`**，理由见本文件头部；
    /// - 列名不复述（`*`）—— 排除列是下一步的事（敏感列口径未定，见头部）。
    public static func selectSQL(
        table: String,
        schema: String?,
        dialect: any SQLDialect
    ) throws -> String {
        let name = table.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Issue.emptyTableName }
        guard !name.contains("\0") else { throw Issue.invalidIdentifier(name) }
        let schemaName = schema?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemaName, !schemaName.isEmpty, schemaName.contains("\0") {
            throw Issue.invalidIdentifier(schemaName)
        }
        let qualified = SQLGenerator.qualifiedName(
            table: name,
            schema: (schemaName?.isEmpty == false) ? schemaName : nil,
            dialect: dialect
        )
        return "SELECT * FROM \(qualified)"
    }

    // MARK: - 整库导出

    /// 一张表的落点：表 → 文件名（**只给文件名**，目录由调用方定）。
    public struct Entry: Equatable, Sendable {
        public var table: String
        public var schema: String?
        public var fileName: String

        public init(table: String, schema: String?, fileName: String) {
            self.table = table
            self.schema = schema
            self.fileName = fileName
        }
    }

    /// 把「这张库里有哪些表」投成一组落点。
    ///
    /// 三条口径：
    /// * **顺序 = 输入顺序**（调用方按表名 `ORDER BY` 取，导出顺序因此可复现，也便于对照）；
    /// * **文件名要能落在任何文件系统上**：路径分隔符、控制字符、前后空白一律换掉，`..` 这种
    ///   整名退化成占位 —— 表名是数据库里的标识符，它可以合法地含 `/` 与空格，直接拿来当文件名
    ///   会在创建文件那一步失败（或者更糟：写到一个意料之外的目录里）；
    /// * **撞名顺延**：净化之后可能两张表落到同一个名字（`a/b` 与 `a:b` 都变成 `a_b`），
    ///   第二条起加 `-2`、`-3`；**不许静默覆盖** —— 那等于少导出一张表而账上说成功。
    public static func entries(
        schema: String?,
        tables: [String],
        format: ResultExportFormat
    ) -> [Entry] {
        let ext = format.fileExtension
        var used: Set<String> = []
        var result: [Entry] = []
        for table in tables {
            let base = safeBaseName(table)
            var candidate = "\(base).\(ext)"
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(base)-\(suffix).\(ext)"
                suffix += 1
            }
            used.insert(candidate.lowercased())
            result.append(Entry(table: table, schema: schema, fileName: candidate))
        }
        return result
    }

    /// 表格名 → 可落盘的文件名主体（不含扩展名）。
    ///
    /// 保留 Unicode（中文表名照原样，别转成拼音或下划线 —— 用户按名字找文件）；
    /// 只把**文件名层面不安全**的字符换掉，并把结果收在 1…120 个字符：
    /// 太长的名字在多数文件系统上会被无声截断，截断后正好撞上另一张表的概率不低。
    public static func safeBaseName(_ table: String) -> String {
        let forbidden: Set<Character> = ["/", ":", "\\", "\0", "*", "?", "\"", "<", ">", "|"]
        var characters: [Character] = []
        for character in table.trimmingCharacters(in: .whitespacesAndNewlines) {
            if forbidden.contains(character) || character.isNewline || character.isWhitespace {
                characters.append("_")
            } else {
                characters.append(character)
            }
        }
        var name = String(characters)
        // 纯点号（`.` / `..`）是目录引用的名字，不是文件名的名字。
        if name.allSatisfy({ $0 == "." }) { name = "table" }
        if name.isEmpty { name = "table" }
        // 以点开头会被多数工具当成隐藏文件（用户在访达里看不见自己刚导出的东西）。
        if name.hasPrefix(".") { name = "_" + name }
        if name.count > 120 { name = String(name.prefix(120)) }
        return name
    }

    // MARK: - 账

    /// 一张表的结局。`path` 与 `failure` **互斥**：写成文件了才有路径，没写成才有原因。
    public struct Receipt: Equatable, Sendable {
        public var table: String
        public var rows: Int
        public var path: String?
        public var failure: String?

        public init(table: String, rows: Int, path: String?, failure: String?) {
            self.table = table
            self.rows = rows
            self.path = path
            self.failure = failure
        }

        public var isSuccess: Bool { path != nil && failure == nil }

        public static func succeeded(table: String, rows: Int, path: String) -> Receipt {
            Receipt(table: table, rows: rows, path: path, failure: nil)
        }

        public static func failed(table: String, reason: String) -> Receipt {
            Receipt(table: table, rows: 0, path: nil, failure: reason)
        }
    }

    /// 逐表结局的账。
    ///
    /// 为什么要有它：整库导出是「一串表各导一次」，其中一张失败**不许**把前面的成果也一起
    /// 变成「失败」—— 用户要的是「哪几张成了、哪几张没成、各多少行」，不是一句「导出失败」。
    public struct Ledger: Equatable, Sendable {
        public private(set) var receipts: [Receipt]

        public init(receipts: [Receipt] = []) {
            self.receipts = receipts
        }

        public mutating func record(_ receipt: Receipt) {
            receipts.append(receipt)
        }

        public var succeededCount: Int { receipts.filter(\.isSuccess).count }
        public var failedCount: Int { receipts.count - succeededCount }

        /// 只有成功的那些表贡献行数（失败的读数不可信，不并进来凑一个好看的总数）。
        public var succeededRows: Int { receipts.filter(\.isSuccess).reduce(0) { $0 + $1.rows } }

        public var isEmpty: Bool { receipts.isEmpty }

        /// 验收要点 ④「完成后报告行数与文件路径」的唯一出处。
        ///
        /// 文案全部由调用方给（`TableExport.Labels`）：Core 不进语言表，只负责把
        /// 「哪一行、多少行、到哪个文件」按**记录的先后**排出来，并在末尾给一行汇总。
        public func report(labels: Labels, orderGuaranteed: Bool = false) -> String {
            var lines: [String] = []
            for receipt in receipts {
                if let path = receipt.path, receipt.failure == nil {
                    lines.append(labels.row(receipt.table, receipt.rows, path))
                } else {
                    lines.append(labels.failedRow(receipt.table, receipt.failure ?? ""))
                }
            }
            lines.append(labels.summary(succeededCount, failedCount, succeededRows))
            if !orderGuaranteed { lines.append(labels.orderNote) }
            return lines.joined(separator: "\n")
        }
    }

    /// 报告文案的来源（界面按当前语言填）。用闭包而不是字符串模板：
    /// 每一行的实参与模板写在同一句里，语言表对账才不会把「模板有占位符、实参 0 个」判成假红。
    public struct Labels: Sendable {
        public var row: @Sendable (String, Int, String) -> String
        public var failedRow: @Sendable (String, String) -> String
        public var summary: @Sendable (Int, Int, Int) -> String
        public var orderNote: String

        public init(
            row: @escaping @Sendable (String, Int, String) -> String,
            failedRow: @escaping @Sendable (String, String) -> String,
            summary: @escaping @Sendable (Int, Int, Int) -> String,
            orderNote: String
        ) {
            self.row = row
            self.failedRow = failedRow
            self.summary = summary
            self.orderNote = orderNote
        }
    }
}
