// ⚠️ 本文件由 `Scripts/gen-sqlite-constants.py` **生成**，不要手改。
// 重跑生成器即可；「生成物 ↔ 头文件」是否一致由 `python3 Scripts/gen-sqlite-constants.py --check` 判
// —— **已接进 `Scripts/verify-all.sh` 第 18 项**（与 `--self-test` 一起跑；队列 L-43、第 30 轮），
// 生成物被手改一行、或头文件换版后没重生成，闭环当场报红并指名本文件。
//
// 为什么有这份「Swift 侧的常量表」：第 18 轮实测，Swift 侧**大量**引用 C 宏常量会把绑定目标判进
// SwiftPM 的显式模块构建档，而那一档下 vendored 的 clang 模块进不了模块表 —— 症状是
// `import CSQLite3` 不报错、所有声明却「cannot find in scope」。
// 口径因此是：**Swift 只调用 C 函数、不引用 C 宏**，宏的值从头文件生成。
// 第 21 轮接线时 `import CSQLite3` 在 `DoyahCore` 目标里可用（Core 已编译通过、单测跑过）；
// **宏引用的规模阈值本轮未再复测**，所以这条纪律照旧保留。
//
// 值来源：`Vendor/sqlite3/Sources/CSQLite3/include/sqlite3.h`（版本见 `Vendor/sqlite3/PROVENANCE.md`）。

import Foundation

/// SQLite 的 C 宏常量（值从 vendored 头文件生成；只收正文实际用到的那些）。
internal enum SQLiteMacro {
    internal static let abortMacro: Int32 = 4
    internal static let authMacro: Int32 = 23
    internal static let blobMacro: Int32 = 4
    internal static let busyMacro: Int32 = 5
    internal static let cantopenMacro: Int32 = 14
    internal static let constraintMacro: Int32 = 19
    internal static let corruptMacro: Int32 = 11
    internal static let doneMacro: Int32 = 101
    internal static let emptyMacro: Int32 = 16
    internal static let errorMacro: Int32 = 1
    internal static let floatMacro: Int32 = 2
    internal static let formatMacro: Int32 = 24
    internal static let fullMacro: Int32 = 13
    internal static let integerMacro: Int32 = 1
    internal static let internalMacro: Int32 = 2
    internal static let interruptMacro: Int32 = 9
    internal static let ioerrMacro: Int32 = 10
    internal static let lockedMacro: Int32 = 6
    internal static let mismatchMacro: Int32 = 20
    internal static let misuseMacro: Int32 = 21
    internal static let nolfsMacro: Int32 = 22
    internal static let nomemMacro: Int32 = 7
    internal static let notadbMacro: Int32 = 26
    internal static let notfoundMacro: Int32 = 12
    internal static let noticeMacro: Int32 = 27
    internal static let okMacro: Int32 = 0
    internal static let open_createMacro: Int32 = 4
    internal static let open_fullmutexMacro: Int32 = 65536
    internal static let open_readonlyMacro: Int32 = 1
    internal static let open_readwriteMacro: Int32 = 2
    internal static let permMacro: Int32 = 3
    internal static let protocolMacro: Int32 = 15
    internal static let rangeMacro: Int32 = 25
    internal static let readonlyMacro: Int32 = 8
    internal static let rowMacro: Int32 = 100
    internal static let schemaMacro: Int32 = 17
    internal static let textMacro: Int32 = 3
    internal static let toobigMacro: Int32 = 18
    internal static let warningMacro: Int32 = 28
}
