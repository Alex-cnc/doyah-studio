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
        // 周报（Retro）的 macOS 代码**2026-11-03 起随本仓走**（人类主人拍板：Retro 的 macOS
        // 实现与 Notes 同构、一并进 Studio 仓）⇒ 原先那条指向 `lead/retro/platform/macos`
        // 的**绝对路径本地包依赖已删除**（它让别人 clone 下来编不过）。代码现在在
        // `Plugins/Retro/`，由下面三个 target 直接编译，不再有第二个包。
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
            path: ".",
            // 插件面（概设 §7 P3，2026-10-13）：笔记的**自有逻辑**搬进 `Plugins/Notes/Sources/`
            // 后仍编进 `DoyahCore` 模块（同模块搬家 = 「移动 + 接口收口」，不重写、不引 import 面震荡）；
            // 需要宿主类型的三个视图在 `Plugins/Notes/Views/`，归 `DoyahStudioApp`（见下一个 target）。
            sources: ["Core", "Plugins/Notes/Sources"]
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
            // 为什么 CLI 也要平台模块：`agent im` 的 Secret 必须写进**和 App 同一条**
            // 钥匙串记录（`agent-im-qq`）—— 命令行写一处、界面读另一处，就会变成
            // 「CLI 说配了、面板说没配」。`DoyahPlatform` 目前只含 macOS 实现，
            // Linux 侧落地时需给出对应的凭据存储并在 CLI 里换这一处注入。
            dependencies: ["DoyahCore", "DoyahPlatform"],
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
                // 周报阅读器（片 `M7-HOST`，装配面自 2026-11-03 起）：同一包内的 target，
                // 不再是跨包 product ⇒ 模块名 `DoyahRetroUI` 不变，外部 import 一个字不用改。
                "DoyahRetroUI"
            ],
            path: ".",
            // Resources 由 Scripts/build-app.sh 装进 .app；SwiftPM 不处理 .icns/.png，
            // 不排除会报 unhandled files。
            exclude: ["DoyahStudio.entitlements", "Resources"],
            // 插件面（概设 §7 P3，2026-10-13）：笔记那三个**需要宿主类型**的视图搬进
            // `Plugins/Notes/Views/` 后仍编进宿主模块（它们读 `AppState`，跨模块就看不见）。
            // `exclude` 必须排在 `sources` 之前 —— SwiftPM 对参数顺序有硬要求。
            sources: ["App", "Plugins/Notes/Views"]
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
                "DoyahRetroUI"
            ],
            path: "TestsUISnapshot"
        ),
        // ------------------------------------------------------------------
        // 周报（Retro）· macOS 实现（2026-11-03 从 `lead/retro/platform/macos` 迁入）
        //
        // 为什么是**三个独立 target**、而不是照 Notes 那样并进 `DoyahCore`：
        //   · **模块名不许碎**：`DoyahRetroCore` 被同包的 `DoyahRetroUI` / 测试 / 命令入口
        //     直接 `import`，也被 `Plugins/Retro/plugin.json` 的 `entryTarget` 认作装配面。
        //     并进 `DoyahCore` 就要改十来处 import，收益为零。
        //   · **有一处真冲突**：Retro 的 `MarkdownBlock`（周报正文块）与 Core 的
        //     `MarkdownBlock`（笔记 Markdown AST，`Core/MarkdownDocument.swift:80`）同名同形
        //     不同义 ⇒ 同模块编译直接红。改名属于「顺手改产品 API」，迁移不该夹带。
        // 文件布局仍与 Notes 同构（`Plugins/<插件>/Sources` + `Views`），差别只在「谁编译它」。
        // ------------------------------------------------------------------
        // 领域层：周报包（`IR-05`）模型 + 解析 + 扫描 + 触发 + 记账。**零 GUI 符号**，
        // 只碰 Foundation ⇒ 可被命令入口与将来的别端复用。
        .target(
            name: "DoyahRetroCore",
            path: "Plugins/Retro/Sources"
        ),
        // 视图层（R-04）：左期次卡片列表 + 右只读渲染 + 本地视频内联 + 外链按钮。
        // **只有这一层可以 import GUI 框架**（SwiftUI / AppKit / AVKit）；判定「只读」的
        // 机械判据 = `Plugins/Retro/Tools/check-readonly.py`。
        .target(
            name: "DoyahRetroUI",
            dependencies: ["DoyahRetroCore"],
            path: "Plugins/Retro/Views"
        ),
        // 命令入口（R-05）：扫一个根 ⇒ 逐期读数打成确定性 JSON 到 stdout。只依赖领域层。
        .executableTarget(
            name: "DoyahRetroCLI",
            dependencies: ["DoyahRetroCore"],
            path: "Plugins/Retro/CLI"
        ),
        // Retro 的两套测试原样搬进来（target 名与目录名都沿用）：
        // `--filter "Retro"` 能选中（SwiftPM 的匹配串含 target 名）。
        .testTarget(
            name: "DoyahRetroCoreTests",
            dependencies: ["DoyahRetroCore"],
            path: "Plugins/Retro/Tests/DoyahRetroCoreTests"
        ),
        // 视图层的「不崩」自检（`FR-R-13-08` 判据 ④）：空扫描根 / 缺 index.json / 坏 JSON /
        // 缺 report.md ⇒ 空态或逐条报告，不崩。
        .testTarget(
            name: "DoyahRetroUITests",
            dependencies: ["DoyahRetroCore", "DoyahRetroUI"],
            path: "Plugins/Retro/Tests/DoyahRetroUITests"
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
