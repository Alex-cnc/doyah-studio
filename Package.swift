// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DoyahCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DoyahCore",
            targets: ["DoyahCore"]
        )
    ],
    dependencies: [
        // 依赖一律**随仓库带走**（Vendor/，见 §8.2）：版本可复现、离线可构建，
        // 不因为上游发新版就把这个工程编不过。许可证随目录一起留档（都是 Apache-2.0）。
        .package(path: "Vendor/postgres-nio"),
        .package(path: "Vendor/mysql-nio"),
        // SQLite 的 vendored amalgamation（公有领域，见 Vendor/sqlite3/LICENSE.txt）。
        // 提供 `CSQLite3` 这个 clang 模块：三端共用**同一份** `sqlite3.c`，
        // 系统 `libsqlite3` / 第三方 Swift 封装都不用（理由写在下面 DoyahCore 的注释里）。
        // 台账在 `Scripts/vendored-sqlite.json`，门禁 `Scripts/check-vendored-sqlite.py`
        // 逐字节核对；行为另由 `Scripts/smoke-vendored-sqlite.sh` 现编现跑证据。
        .package(path: "Vendor/sqlite3"),
        // 许可校验要 Ed25519 签名（FR-LIC-01）：用 **swift-crypto** 而不是 Apple 的 CryptoKit ——
        // Core 要保持平台中立（同一个 Core 将来要给 Doyah Notes 的 Windows / 安卓 / 鸿蒙版复用）。
        // 它本来就在依赖树里（NIO SSL 用），这里只是**显式声明**，不新增依赖树。
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        // **周报（Retro）阅读器的装配面**（片 `M7-HOST` · 派单 `T-20261009-080`）：
        // Retro 的视图层 `DoyahRetroUI` 走**本地路径依赖**取（前门口径：两锚仓在本机并列 ——
        // `~/dev/doyah/lead/{studio,retro}`）。这里必须是**绝对路径**：Studio 的每个卡片都在
        // worktree 里（`.worktrees/<卡号>/`，离 Retro 锚仓 6 层上溯、离主仓 1 层）⇒
        // 相对路径一合回主仓就断。
        //
        // Pinned Retro commit: 592b1bcd27ffa023ba3c7890426a2c9a1f31fa0b
        //   · 该提交（`合入 wt/m7-ui-prod`）起，Retro 的 `platform/macos/Package.swift` 的
        //     `products:` 才有 `DoyahRetroUI`（前置片 `M7-UI-PROD` 的那一笔）；
        //   · 指向前门线克隆 `~/.dsh/projects/DoyahRetro`（`master` @ `b057b18`）会报
        //     `product 'DoyahRetroUI' … not found in package 'macos'` —— 那条路走不通（已实测）。
        //   · 路径依赖本身**钉不住 commit**（SwiftPM 的 path 依赖吃的是工作树），所以这里
        //     用一行注释把「本机盘上那份应当是哪一笔」写下来；换锚仓 / 推进锚仓时**同时改这一行**。
        .package(path: "/Users/alex/dev/doyah/lead/retro/platform/macos")
    ],
    targets: [
        // SQLite 的 vendored C 目标（FR-PLUG-08 / Q23 拍板：桌面各端笔记存储统一到本地 SQLite）。
        //
        // 为什么是**编进产品的一份源码**、而不是系统库或第三方 Swift 封装：
        //   · 系统 `libsqlite3`（`import SQLite3`）版本随 OS 漂移，同一个构建在 macOS 14 与 26 上
        //     是两个不同的 SQLite —— 「三端完全一致」当场不成立，Windows / Linux 更是没有它；
        //   · GRDB 官方只支持 Apple + Linux，Windows 还是社区探索；SwiftData / Core Data 是 Apple 独占；
        //   · 而 amalgamation 是**公有领域**：随仓库带走源码、编译进口、随产品分发都不需要额外授权。
        // 编译宏在 `Vendor/sqlite3/Package.swift` 上（版本、来源、哈希见 `Vendor/sqlite3/PROVENANCE.md`），
        // 由 `Scripts/check-vendored-sqlite.py` 逐个钉住 —— 宏掉了不会有任何症状，只有行为悄悄变掉。
        .target(
            name: "DoyahCore",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CSQLite3", package: "sqlite3")
            ],
            path: "Core"
        ),
        // 平台适配层：只有这里可以 import 平台专属框架（Security / Darwin …）。
        // Core 不含任何平台依赖，这条边界由模块依赖关系强制，而不是靠自觉 ——
        // 见 Scripts/check-core-portability.py（静态闸门）与需求书 §0.8。
        .target(
            name: "DoyahPlatform",
            dependencies: ["DoyahCore"],
            path: "Platform/macOS"
        ),
        .executableTarget(
            name: "DoyahCLI",
            dependencies: ["DoyahCore"],
            path: "CLI"
        ),
        // 许可签发工具（**发行方侧**，不进 .app 包）：keygen / issue / verify / inspect。
        // 为什么单列一个可执行目标：签发要用**私钥**，而私钥不该出现在任何会被分发的东西里 ——
        // 工具与 App 共用 Core 的 `License` 模型与签名实现，但**打包脚本只打 App**。
        .executableTarget(
            name: "doyah-license-tool",
            dependencies: ["DoyahCore"],
            path: "Tools/LicenseTool"
        ),
        // 让 SwiftPM 也能编译 App 源码（Xcode 工程之外的第二条验证路径）。
        // 打包成 .app 由 Scripts/build-app.sh 负责。
        .executableTarget(
            name: "DoyahStudioApp",
            dependencies: [
                "DoyahCore",
                "DoyahPlatform",
                // 周报阅读器（片 `M7-HOST`）：路径依赖的 identity 是**末段目录名** `macos`
                // （不是包名 `DoyahRetroCore`）—— 写成包名会报 unknown package。
                .product(name: "DoyahRetroUI", package: "macos")
            ],
            path: "App",
            // Resources 由 Scripts/build-app.sh 装进 .app；SwiftPM 不处理 .icns/.png，
            // 不排除会报 unhandled files。
            exclude: ["DoyahStudio.entitlements", "Resources"]
        ),
        .testTarget(
            name: "DoyahCoreTests",
            dependencies: [
                "DoyahCore",
                // 账号与同步界面（片 `云F`）：本目标里那一条判据要打在**真界面模型**上
                // （`App/Auth/AccountFlowModel.swift`），而不是在测试里另写一份规则 ——
                // 所以这里多一条到 App 可执行目标的依赖。SwiftPM 本来就会为
                // `DoyahUISnapshotTests` 编出 App（测试目标依赖可执行目标是允许的），
                // 故本条**不增加**构建量；Xcode 工程（`project.yml`）那一侧不跟这条
                // ——两份构建系统的差异本就是登记过的已知边界（`Docs/发布方案.md` §2）。
                "DoyahStudioApp",
            ],
            path: "Tests"
        ),
        // 界面快照（队列 L-01）：用 `ImageRenderer` **离屏渲染真视图树**成 PNG。
        //
        // 为什么单列一个 test target 并依赖 `DoyahStudioApp`：要取证的是**真界面**，
        // 而不是 `Scripts/design-mock.swift` 那种照着重画的样张；SwiftPM 允许测试目标依赖可执行目标，
        // 于是不用把 App 拆成库、也不用给生产代码开后门。
        // 用例**默认跳过**（`DOYAH_UI_SNAPSHOT=1` 才跑）—— 快照是取证工具，不是回归门禁。
        .testTarget(
            name: "DoyahUISnapshotTests",
            dependencies: [
                "DoyahStudioApp",
                "DoyahCore",
                "DoyahPlatform",
                // 宿主装配探针（片 `M7-HOST`）要**直接**读 Retro 侧的真值
                // （`ReportListModel.fixed()` 的扫描读数，判据 ④）—— 不靠传递依赖转一手。
                .product(name: "DoyahRetroUI", package: "macos")
            ],
            path: "TestsUISnapshot"
        ),
        // 平台适配层的测试单独一个 target：真实书签这类用例必须跑在**真实实现**上，
        // 放在 Core 测试里就只能测假实现，等于把最有价值的一条覆盖丢掉。
        .testTarget(
            name: "DoyahPlatformTests",
            dependencies: ["DoyahCore", "DoyahPlatform"],
            path: "TestsPlatform"
        )
    ]
)
