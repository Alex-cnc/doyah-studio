// swift-tools-version: 5.10
import PackageDescription

// **vendored SQLite 的包声明**（FR-PLUG-08 / Q23 拍板：桌面各端笔记存储统一到本地 SQLite）。
//
// 为什么把 C 目标做成**独立的小包**而不是根包里的一个 target：与 `Vendor/postgres-nio` /
// `Vendor/mysql-nio` 同一个形状 —— 本仓库对依赖的既有口径就是「随仓库带走的路径依赖」，
// 装一个东西进来不该顺手发明第二种形状。C 源码与头文件因此按 SwiftPM 规范布局（见下面 `path`）。
//
// ⚠️ 与形状**无关**的一件已知缺陷（第 18 轮查清，别重复踩）：Swift 目标只要**引用本地包里的
// clang 模块**达到一定规模，SwiftPM 就会把它判进**显式模块构建**档
// （`-explicit-swift-module-map-file` + `-Xcc -fno-implicit-modules`），而那一档的模块表里
// **没有**本地包的 clang 模块 ⇒ `import CSQLite3` 不报错、但**一个声明都看不到**
// （所有 API 都 "cannot find in scope"，看着像函数名拼错）。换包形状、换 scratch/cache 路径、
// 关预构建模块、补 `-fimplicit-modules` 都试过，不解。Swift 侧绑定层因此**暂未接线**
// （草稿在 `Docs/design/待接线-SQLiteKit/`，排除过程在 `Docs/开发记录-*.md` 第 18 轮）。
// 这一条不影响本包本身：`Scripts/smoke-vendored-sqlite.py` 直接调 clang 编它、跑它、断言它。
//
// 编译宏逐个有理由，见 `../PROVENANCE.md` 与 `Scripts/vendored-sqlite.json` 的 `requiredCompileOptions`：
// 宏掉了不会有任何症状（编译过、单测过），只有行为悄悄变掉，所以由 `Scripts/check-vendored-sqlite.py` 钉住。
let package = Package(
    name: "sqlite3",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CSQLite3", targets: ["CSQLite3"])
    ],
    targets: [
        .target(
            name: "CSQLite3",
            path: "Sources/CSQLite3",
            // 头文件目录里放 `sqlite3.h`（官方交付物）与 `CSQLite3.h`（与目标同名的伞头）。
            // 伞头是**构建系统需要的**，不是产品代码：公共头目录里没有与目标同名的头时，
            // SwiftPM 生成的模块图是「伞目录」形状（`umbrella "<目录>"`），有同名头时是
            // 「伞头」形状（`umbrella header "CSQLite3.h"`）—— 后者是显式的、可预期的，故选它。
            publicHeadersPath: "include",
            cSettings: [
                // 序列化模式：宿主是多线程的，连接可能被多个线程碰到。
                .define("SQLITE_THREADSAFE", to: "1"),
                // FR-PLUG-08 的判据之一「要按条件查与全文检索」—— FTS5 不在默认编译里。
                .define("SQLITE_ENABLE_FTS5", to: "1"),
                // 不需要动态扩展加载（少一个 dlopen 面），也就用不着 sqlite3ext.h。
                .define("SQLITE_OMIT_LOAD_EXTENSION", to: "1"),
                // 双引号不许当字符串字面量：列名写错时**当场报错**，而不是被静默当成字符串。
                .define("SQLITE_DQS", to: "0")
            ]
        )
    ]
)
