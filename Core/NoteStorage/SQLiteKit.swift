// 第 21 轮（L-25 第 2 批）起**已接线**：本文件在 `Core/NoteStorage/` 下，属 `DoyahCore` 目标，
// `import CSQLite3` 直接对 vendored amalgamation（第 18 轮那份草稿当初就是因为模块看不见而没接上，
// 见 `Docs/开发记录-20260927-*.md`；本轮实测在 Core 目标里可编译、可跑）。
import CSQLite3
import Foundation
// 这一层是 **C 绑定**，不是笔记逻辑：三端（macOS / Windows / Linux）共用同一份 vendored `sqlite3.c`
// （见 `Vendor/sqlite3/PROVENANCE.md` 与 `Scripts/check-vendored-sqlite.py`）。
// 口径来自需求规范书 `FR-PLUG-08`（Q23 拍板）：不换系统 `libsqlite3`、不引第三方 Swift 封装 —— 两者
// 都会让「Windows 与 macOS 完全一致」不成立（系统库版本随 OS 漂移；GRDB / SwiftData / Core Data 各有平台缺口）。
//
// 设计口径（三端可复用的**薄**封装，刻意不做 ORM）：
//   · 只包「打开 / 执行 / 预编译语句 / 事务 / 类型化取值」这几件事，SQL 由调用方（笔记存储层）自己写；
//   · **失败一律抛 `SQLiteFailure`**（带 SQLite 错误码 + 驱动原话 + 出错的 SQL），不返回 `Bool`：
//     「写了但没成功」在存储层是最难查的一类缺陷；
//   · **错误码语义写在类型上**（`isBusy` / `isConstraintViolation`），调用方不必记 5 / 19 这些数字；
//   · 错误描述是**英文机器可读原文**（与 `NoteStore.LoadOutcome.failure` 同一口径：这一层不产出界面文案，
//     界面文案由语言表按出错类别组织）—— 所以这里没有中文字面量（R-45 的棘轮也就不会长）。
//
// 线程：连接内部串行化（递归锁 + `FULLMUTEX`），但**语义上的并发**仍由调用方（`NoteStore` 是 actor）负责。
// 递归锁是刻意的：`transaction { … }` 里会再调 `execute`，非递归锁会自己把自己锁死。
//
// 事务：`transaction { … }` 用 **`BEGIN IMMEDIATE`**（立刻取写锁）而不是默认的 `BEGIN`（延迟取锁）——
// 延迟事务在「读到一半要升级成写」时可能直接 `SQLITE_BUSY` 且**无法通过重试解决**（FR-PLUG-08 的口径里
// 有「并发写 + 多进程读」，这正是那类场景的经典坑）。嵌套调用自动退化成 `SAVEPOINT`。

/// SQLite C API 的 `SQLITE_TRANSIENT`（Swift 看不到这个宏，得自己造）：告诉 SQLite「把这段字节抄走」。
///
/// 刻意**不写** `sqlite3_destructor_type`（C 侧那个函数指针 typedef）：绑定层实测在
/// SwiftPM 的显式模块构建下会用「不导入 clang 模块」的方式编译（见目标注释），
/// 于是这里用等价的 **Swift 函数指针类型**，不依赖 C 类型名也能建出来。
private let sqliteTransient: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? =
    unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?.self)

/// SQLite 的错误码（**机器可读的稳定出口**）。
///
/// 为什么在 Swift 侧再写一份：C 模块只对**这个目标**可见（`import CSQLite3` 是封装层的实现细节），
/// 调用方（`Core/` 的存储层）与测试不该为了判一个码去 import C 模块 —— 那会把 C 互操作漏到门外。
/// 数字与 `sqlite3.h` 里的 `SQLITE_*` 一一对应，由 `Tests/SQLiteTests.swift` 用 `codeName` 反向钉住
/// （对不上就红），所以这份表不会悄悄漂。
public enum SQLiteResultCode {
    public static let ok: Int32 = 0
    public static let error: Int32 = 1
    public static let busy: Int32 = 5
    public static let locked: Int32 = 6
    public static let readOnly: Int32 = 8
    public static let range: Int32 = 25
    public static let notADatabase: Int32 = 26
    public static let misuse: Int32 = 21
    /// 数据类型或形状与预期不符（我们用它在"行里没有可用的 uuid"这种**库被外部写坏**的情形上报错）。
    public static let mismatch: Int32 = 20
    public static let constraint: Int32 = 19
    /// `SQLITE_CONSTRAINT | (6 << 8)`：主键冲突（扩展码）。
    public static let constraintPrimaryKey: Int32 = 1555
}

/// SQLite 的一个值。刻意只映射 SQLite 的五种存储类，不做 Swift 类型推断 ——
/// 「NULL 与空串不是一回事」这类判断留给调用方显式表达。
public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])

    public var isNull: Bool { self == .null }

    public var intValue: Int64? { if case .integer(let value) = self { return value }; return nil }
    public var doubleValue: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }
    public var textValue: String? { if case .text(let value) = self { return value }; return nil }
    public var dataValue: Data? { if case .blob(let value) = self { return Data(value) }; return nil }

    /// SQLite 没有布尔类型（存 0 / 1）。这里只在**确实**是整数时给结论，其它情况返回 nil（不猜）。
    public var boolValue: Bool? {
        guard case .integer(let value) = self else { return nil }
        return value != 0
    }
}

/// 一行结果：列名有序，值按列名或下标取。列名重复时按**后出现**的那一列覆盖（SQL 的不合格写法，
/// 但真出现时不该崩）。
public struct SQLiteRow: Equatable, Sendable {
    public let columns: [String]
    public let values: [SQLiteValue]

    public init(columns: [String], values: [SQLiteValue]) {
        self.columns = columns
        self.values = values
    }

    public subscript(index: Int) -> SQLiteValue {
        guard values.indices.contains(index) else { return .null }
        return values[index]
    }

    public subscript(name: String) -> SQLiteValue {
        guard let index = columns.lastIndex(of: name) else { return .null }
        return self[index]
    }

    public func int(_ name: String) -> Int64? { self[name].intValue }
    public func text(_ name: String) -> String? { self[name].textValue }
}

/// SQLite 失败。`code` 是驱动原始错误码（不翻译、不合并），`message` 是驱动原话，
/// `operation` 说明「哪一步失败」（打开 / 执行 / 预编译 / 取值），`sql` 是出错的语句（有的话）。
///
/// **为什么保留原始码与原话**：与 `ConnectionFailure` 那条口径同源 —— 认得出就给方向，认不出就原样，
/// 绝不把猜测当结论。上层要判断「是不是锁竞争」就读 `isBusy`，而不是去匹配文案字符串。
public struct SQLiteFailure: Error, Equatable, CustomStringConvertible {
    public enum Operation: String, Equatable, Sendable {
        case open
        case execute
        case prepare
        case bind
        case step
        case close
    }

    public let code: Int32
    public let message: String
    public let operation: Operation
    public let sql: String?
    /// 扩展错误码（`sqlite3_extended_errcode`），没有时等于 `code`。
    public let extendedCode: Int32

    public init(code: Int32, message: String, operation: Operation, sql: String? = nil, extendedCode: Int32? = nil) {
        self.code = code
        self.message = message
        self.operation = operation
        self.sql = sql
        self.extendedCode = extendedCode ?? code
    }

    /// 驱动码的常见名字（`sqlite3.h` 里的宏名；认不出就只给数字，不猜）。
    ///
    /// 为什么用 C 宏名而不是 Swift 侧那套 `SQLiteMacro.*` 成员名：这句话会出现在日志、错误报告与
    /// 用户的求助信息里，必须是能在 SQLite 文档与 `sqlite3.h` 里直接搜到的名字
    /// （第 21 轮接线时发现草稿里返回的是 `SQLiteMacro.busyMacro` 这种**内部实现形状**，
    /// 而同一份草稿的单测断言的是 `SQLITE_BUSY` —— 两边对不上，按单测（=文档口径）改实现）。
    public var codeName: String {
        switch code {
        case SQLiteMacro.okMacro: return "SQLITE_OK"
        case SQLiteMacro.errorMacro: return "SQLITE_ERROR"
        case SQLiteMacro.internalMacro: return "SQLITE_INTERNAL"
        case SQLiteMacro.permMacro: return "SQLITE_PERM"
        case SQLiteMacro.abortMacro: return "SQLITE_ABORT"
        case SQLiteMacro.busyMacro: return "SQLITE_BUSY"
        case SQLiteMacro.lockedMacro: return "SQLITE_LOCKED"
        case SQLiteMacro.nomemMacro: return "SQLITE_NOMEM"
        case SQLiteMacro.readonlyMacro: return "SQLITE_READONLY"
        case SQLiteMacro.interruptMacro: return "SQLITE_INTERRUPT"
        case SQLiteMacro.ioerrMacro: return "SQLITE_IOERR"
        case SQLiteMacro.corruptMacro: return "SQLITE_CORRUPT"
        case SQLiteMacro.notfoundMacro: return "SQLITE_NOTFOUND"
        case SQLiteMacro.fullMacro: return "SQLITE_FULL"
        case SQLiteMacro.cantopenMacro: return "SQLITE_CANTOPEN"
        case SQLiteMacro.protocolMacro: return "SQLITE_PROTOCOL"
        case SQLiteMacro.emptyMacro: return "SQLITE_EMPTY"
        case SQLiteMacro.schemaMacro: return "SQLITE_SCHEMA"
        case SQLiteMacro.toobigMacro: return "SQLITE_TOOBIG"
        case SQLiteMacro.constraintMacro: return "SQLITE_CONSTRAINT"
        case SQLiteMacro.mismatchMacro: return "SQLITE_MISMATCH"
        case SQLiteMacro.misuseMacro: return "SQLITE_MISUSE"
        case SQLiteMacro.nolfsMacro: return "SQLITE_NOLFS"
        case SQLiteMacro.authMacro: return "SQLITE_AUTH"
        case SQLiteMacro.formatMacro: return "SQLITE_FORMAT"
        case SQLiteMacro.rangeMacro: return "SQLITE_RANGE"
        case SQLiteMacro.notadbMacro: return "SQLITE_NOTADB"
        case SQLiteMacro.noticeMacro: return "SQLITE_NOTICE"
        case SQLiteMacro.warningMacro: return "SQLITE_WARNING"
        case SQLiteMacro.rowMacro: return "SQLITE_ROW"
        case SQLiteMacro.doneMacro: return "SQLITE_DONE"
        default: return "code \(code)"
        }
    }

    /// 锁竞争（`BUSY` / `LOCKED`）—— 调用方要重试时看这个，而不是看文案。
    public var isBusy: Bool {
        extendedCode == SQLiteMacro.busyMacro || extendedCode == SQLiteMacro.lockedMacro
            || code == SQLiteMacro.busyMacro || code == SQLiteMacro.lockedMacro
            || (extendedCode & 0xFF) == SQLiteMacro.busyMacro || (extendedCode & 0xFF) == SQLiteMacro.lockedMacro
    }

    /// 约束冲突（唯一键 / 非空 / 外键）—— 笔记库的 `UNIQUE` 冲突走这一支。
    public var isConstraintViolation: Bool {
        (extendedCode & 0xFF) == SQLiteMacro.constraintMacro || code == SQLiteMacro.constraintMacro
    }

    /// 库文件本身不适合当数据库用（不是 SQLite 格式、或已损坏）。
    public var isNotADatabase: Bool { code == SQLiteMacro.notadbMacro || code == SQLiteMacro.corruptMacro }

    /// 库（或连接）是只读的 —— 界面该说「这个库是只读的」，而不是「写入失败」。
    public var isReadOnly: Bool { code == SQLiteMacro.readonlyMacro }

    public var description: String {
        var text = "SQLite \(codeName) (\(extendedCode)) during \(operation.rawValue): \(message)"
        if let sql { text += " [sql: \(sql)]" }
        return text
    }
}

/// 一个 SQLite 连接（薄封装）。
public final class SQLiteConnection {

    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    /// 事务嵌套层数：0 = 不在事务里（`sqlite3_get_autocommit != 0` 也表达同一件事，这里另有用途：决定用
    /// `BEGIN IMMEDIATE` 还是 `SAVEPOINT`）。
    private var transactionDepth = 0

    /// 数据库文件路径（`":memory:"` 也是合法值）。
    public let path: String

    /// 打开数据库。默认**读写 + 不存在就建**；`readOnly` 用于「只读地看一眼」的场景。
    ///
    /// 打开后立刻设 `busy_timeout`（默认 5 秒）：笔记库的口径是「并发写 + 多进程读」，
    /// 锁竞争要**等一下**而不是立刻失败 —— 而等待的上限必须是显式的数字，所以它是参数。
    public init(path: String, readOnly: Bool = false, busyTimeout milliseconds: Int32 = 5000) throws {
        var handle: OpaquePointer?
        // 单线程库（`THREADSAFE=0`）下 `MUTEX` 标志没有意义；这里它们是给 `THREADSAFE=1` 用的。
        var flags = SQLiteMacro.open_fullmutexMacro
        flags |= readOnly ? SQLiteMacro.open_readonlyMacro : (SQLiteMacro.open_readwriteMacro | SQLiteMacro.open_createMacro)
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLiteMacro.okMacro, handle != nil else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no message"
            let extended = handle.map { sqlite3_extended_errcode($0) } ?? result
            if let handle { sqlite3_close_v2(handle) }
            throw SQLiteFailure(code: result, message: message, operation: .open, sql: path, extendedCode: extended)
        }
        self.handle = handle
        self.path = path
        sqlite3_busy_timeout(handle, milliseconds)

        // 读写连接默认开 **WAL**：本产品的存储口径就是「并发写 + 多进程读」（`FR-PLUG-08` 的判据之一），
        // 而 `journal_mode` 是**库头里的一个开关**（设一次跟着库走），不是每连接的参数。
        // 只读连接不开 —— 切换日志模式本身是一次写操作。
        // 为什么放在绑定层的默认里而不是让每个调用方自己设：忘了设不会报错、只会在并发时
        // 变成「database is locked」，是那类「不查到最后看不出哪里错」的缺陷。
        if !readOnly {
            try execute("PRAGMA journal_mode = WAL")
        }
    }

    deinit { try? close() }

    /// 关连接。**幂等**（第二次调用无动作）—— 析构与显式关闭不会打架。
    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        self.handle = nil
        transactionDepth = 0
        let result = sqlite3_close_v2(handle)
        guard result == SQLiteMacro.okMacro else {
            throw SQLiteFailure(code: result, message: "close failed", operation: .close)
        }
    }

    /// 关掉没有？关掉之后再调任何方法都会抛 `SQLITE_MISUSE`。
    public var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return handle != nil
    }

    // MARK: - 执行

    /// 执行一段 SQL（可以含多条语句，脚本式用法：建表、PRAGMA、迁移）。
    /// 有结果行也不返回 —— 要读结果用 `query(_:_:)`。
    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        try executeLocked(sql)
    }

    /// 查询：返回全部结果行。绑定值是**显式**的 `SQLiteValue` 数组（参数化查询，不做字符串拼接）。
    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepareLocked(sql: sql)
        defer { statement.finalize() }
        try statement.bind(bindings)
        var rows: [SQLiteRow] = []
        while try statement.step() {
            rows.append(statement.currentRow())
        }
        return rows
    }

    /// 带参数执行（写入 / 更新 / 删除）：**参数化**，不拼字符串；不读结果行。
    ///
    /// 为什么单独一个重载而不是让调用方去用 `query`：写入语句用 `query` 读行是「形状对、意思不对」，
    /// 而这条路径在笔记库里是每一次保存都会走的 —— 让调用点一眼看出「这是写」比省一个方法值钱。
    public func execute(_ sql: String, _ bindings: [SQLiteValue]) throws {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepareLocked(sql: sql)
        defer { statement.finalize() }
        try statement.bind(bindings)
        while try statement.step() {}
    }

    /// 单个标量（第一行第一列）；没有行时返回 nil。`count(*)` 这类用法不必先建行类型。
    public func scalar(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> SQLiteValue? {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepareLocked(sql: sql)
        defer { statement.finalize() }
        try statement.bind(bindings)
        guard try statement.step() else { return nil }
        return statement.value(at: 0)
    }

    public func scalarInt(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int64? {
        try scalar(sql, bindings)?.intValue
    }

    public func scalarText(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> String? {
        try scalar(sql, bindings)?.textValue
    }

    public func tableExists(_ name: String) throws -> Bool {
        let count = try scalarInt(
            "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name = ?",
            [.text(name)]
        )
        return (count ?? 0) > 0
    }

    /// 建表语句的清单（迁移用：确认 schema 真在库里，而不是"我以为建过了"）。
    public func schemaObjects(kind: String = "table") throws -> [String] {
        try query("SELECT name FROM sqlite_master WHERE type = ? ORDER BY name", [.text(kind)])
            .compactMap { $0.text("name") }
    }

    // MARK: - 元信息

    /// 最近一次 `INSERT` 的 rowid。
    public var lastInsertRowID: Int64 {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    /// 最近一次语句影响的行数。
    public var changeCount: Int {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return 0 }
        return Int(sqlite3_changes(handle))
    }

    /// `PRAGMA` 取值（如 `journal_mode` / `user_version` / `foreign_keys`）。
    /// 走 `query` 而不是 `execute`：`journal_mode` 这类会因为 PRAGMA 返回一行而失败。
    public func pragma(_ name: String) throws -> SQLiteValue? {
        try scalar("PRAGMA \(name)")
    }

    /// 设 `PRAGMA`（`key = value`）。值来自**代码里的常量**，不是用户输入 —— 参数化查询不适用 PRAGMA，
    /// 所以这里把「不许拼用户输入」写成一条注释而不是一个机制（调用方只有本工程）。
    public func setPragma(_ statement: String) throws {
        try execute("PRAGMA \(statement)")
    }

    /// 是否在显式事务里（`sqlite3_get_autocommit` == 0）。
    public var isInTransaction: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return false }
        return sqlite3_get_autocommit(handle) == 0
    }

    /// 事务：正常返回则 `COMMIT`，抛错则 `ROLLBACK` 并把错误原样抛出。
    ///
    /// 用 `BEGIN IMMEDIATE`（见文件头注释）；嵌套调用退化成 `SAVEPOINT`，因此**内层失败不会**把外层
    /// 已经写好的东西一起回滚掉 —— 那是「一次失败丢掉一批笔记」的经典成因。
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        _ = try requireHandle(operation: .execute, sql: "BEGIN")
        let depth = transactionDepth
        transactionDepth += 1
        let opener = depth == 0 ? "BEGIN IMMEDIATE" : "SAVEPOINT doyah_\(depth)"
        let closer = depth == 0 ? "COMMIT" : "RELEASE doyah_\(depth)"
        let undoer = depth == 0 ? "ROLLBACK" : "ROLLBACK TO doyah_\(depth)"
        try executeLocked(opener)
        do {
            let value = try body()
            try executeLocked(closer)
            transactionDepth = depth
            return value
        } catch {
            // 回滚本身失败（例如连接已断）也**不掩盖**原始错误 —— 用户要看到的是最初失败的那一步。
            try? executeLocked(undoer)
            transactionDepth = depth
            throw error
        }
    }

    // MARK: - 内部

    private func executeLocked(_ sql: String) throws {
        let handle = try requireHandle(operation: .execute, sql: sql)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLiteMacro.okMacro else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            if let errorMessage { sqlite3_free(errorMessage) }
            throw SQLiteFailure(
                code: result,
                message: message,
                operation: .execute,
                sql: sql,
                extendedCode: sqlite3_extended_errcode(handle)
            )
        }
        if let errorMessage { sqlite3_free(errorMessage) }
    }

    private func prepareLocked(sql: String) throws -> SQLiteStatement {
        let handle = try requireHandle(operation: .prepare, sql: sql)
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLiteMacro.okMacro, let statement else {
            throw SQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(handle)),
                operation: .prepare,
                sql: sql,
                extendedCode: sqlite3_extended_errcode(handle)
            )
        }
        return SQLiteStatement(handle: statement, connection: handle, sql: sql)
    }

    private func requireHandle(operation: SQLiteFailure.Operation, sql: String) throws -> OpaquePointer {
        guard let handle else {
            throw SQLiteFailure(code: SQLiteMacro.misuseMacro, message: "the connection is closed", operation: operation, sql: sql)
        }
        return handle
    }

    // MARK: - 版本自证（三端一致的第一步：先能说清"跑的是哪一份 SQLite"）

    /// 运行期读到的 SQLite 版本（来自我们 vendored 的那一份源码）。
    public static var libraryVersion: String {
        String(cString: sqlite3_libversion())
    }

    /// amalgamation 的源码标识（版本 + 时间戳 + 提交哈希）：换源会对不上。
    public static var librarySourceID: String {
        String(cString: sqlite3_sourceid())
    }

    /// 全部编译宏（`sqlite3_compileoption_get` 遍历）。
    public static var compileOptions: [String] {
        var options: [String] = []
        var index: Int32 = 0
        while let option = sqlite3_compileoption_get(index) {
            options.append(String(cString: option))
            index += 1
        }
        return options
    }

    /// 某个编译宏有没有生效（`SQLITE_ENABLE_FTS5` 这类）。**这是宏的机械判据** ——
    /// 宏写在 `Package.swift` 里但没起作用时，单测会当场红，而不是等用户发现"检索怎么没生效"。
    public static func isCompiled(with option: String) -> Bool {
        sqlite3_compileoption_used(option) != 0
    }
}

/// 预编译语句（`internal`：对外只暴露「执行 / 查询」两种形状，少一个要维护的 API 面）。
final class SQLiteStatement {

    private let handle: OpaquePointer
    private let connection: OpaquePointer
    private let sql: String
    private var finalized = false

    init(handle: OpaquePointer, connection: OpaquePointer, sql: String) {
        self.handle = handle
        self.connection = connection
        self.sql = sql
    }

    deinit { finalize() }

    func finalize() {
        guard !finalized else { return }
        finalized = true
        sqlite3_finalize(handle)
    }

    func bind(_ values: [SQLiteValue]) throws {
        guard sqlite3_bind_parameter_count(handle) == Int32(values.count) else {
            throw SQLiteFailure(
                code: SQLiteMacro.rangeMacro,
                message: "expected \(sqlite3_bind_parameter_count(handle)) parameter(s), got \(values.count)",
                operation: .bind,
                sql: sql
            )
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(handle, index)
            case .integer(let number): result = sqlite3_bind_int64(handle, index, number)
            case .real(let number): result = sqlite3_bind_double(handle, index, number)
            case .text(let text):
                result = sqlite3_bind_text(handle, index, text, -1, sqliteTransient)
            case .blob(let bytes):
                result = bytes.withUnsafeBufferPointer { buffer in
                    sqlite3_bind_blob(handle, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
                }
            }
            guard result == SQLiteMacro.okMacro else {
                throw SQLiteFailure(
                    code: result,
                    message: String(cString: sqlite3_errmsg(connection)),
                    operation: .bind,
                    sql: sql,
                    extendedCode: sqlite3_extended_errcode(connection)
                )
            }
        }
    }

    /// 前进一行。`true` = 有行；`false` = 结束（`SQLITE_DONE`）。
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLiteMacro.rowMacro: return true
        case SQLiteMacro.doneMacro: return false
        default:
            throw SQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(connection)),
                operation: .step,
                sql: sql,
                extendedCode: sqlite3_extended_errcode(connection)
            )
        }
    }

    var columnCount: Int32 { sqlite3_column_count(handle) }

    func columnName(at index: Int32) -> String {
        guard let name = sqlite3_column_name(handle, index) else { return "" }
        return String(cString: name)
    }

    /// 五种存储类**原样**取出来：`printf` 那套隐式转换（数字被当文本、文本被当数字）在这里不发生。
    func value(at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(handle, index) {
        case SQLiteMacro.integerMacro: return .integer(sqlite3_column_int64(handle, index))
        case SQLiteMacro.floatMacro: return .real(sqlite3_column_double(handle, index))
        case SQLiteMacro.textMacro:
            guard let text = sqlite3_column_text(handle, index) else { return .null }
            return .text(String(cString: text))
        case SQLiteMacro.blobMacro:
            guard let blob = sqlite3_column_blob(handle, index) else { return .blob([]) }
            let count = Int(sqlite3_column_bytes(handle, index))
            return .blob(Array(Data(bytes: blob, count: count)))
        default: return .null
        }
    }

    func currentRow() -> SQLiteRow {
        let count = columnCount
        var columns: [String] = []
        var values: [SQLiteValue] = []
        columns.reserveCapacity(Int(count))
        values.reserveCapacity(Int(count))
        for index in 0..<count {
            columns.append(columnName(at: index))
            values.append(value(at: index))
        }
        return SQLiteRow(columns: columns, values: values)
    }
}
