import XCTest
@testable import DoyahCore

/// `FR-NTS-ALL-LIC-001`（Notes「授权与定价：当前不设付费墙」）的机器判据。
///
/// 为什么要有这一条：这一条在台账里原本只有一句**备注**（「`BillingClient` 命中数 0」），
/// 那是人查过一次的读数，不是判据 —— 下次有人在笔记面板里接一个内购 SDK，
/// 没有任何东西会红。这里把三句判据落成可跑的断言：
///
/// ① **应用内无计费 SDK 依赖**：产品源码（`App/` `Core/` `Plugins/` `Tools/` + `Package.swift`）
///    去注释后扫计费符号，命中必须为 0；
/// ② **全部功能在未付费状态下可用**（Notes 面）：无许可证 = Standard 档，而 Standard 档**必须**含
///    笔记能力位；且 Notes 插件源码里**一句授权代码都不许有**（不读许可证就没有「降级」可言）；
/// ③ **出现计费代码而本条未改 ⇒ 判红**：本判据绑在台账那一行的口径上 —— 那条的「需求」格
///    一旦不再写「不设付费墙」，说明主人改了定价口径，①② 必须同批重写；
///    没改口径而代码里冒出计费符号 ⇒ ① 直接红。
///
/// **覆盖边界（铁律 13，如实）**
/// - 扫的：上面四目录下全部 `.swift` + `Package.swift`（含测试外的产品代码），**去注释后**按符号匹配。
/// - 判不住的：把计费藏进 xcframework / 二进制依赖、或从系统里间接调起 App Store 收据校验 ——
///   静态扫描看不见；真收据校验与真机支付流程未做。
/// - 判不住的：② 的「全部功能可用」只到「标准档能力位含笔记 + Notes 源码零授权符号」这一层，
///   界面逐一面板点验未做。
///
/// **负例（铁律 14）**：`testScannerFlagsBillingCodeButIgnoresComments` 用两段夹具 ——
/// 真代码里写 `import StoreKit` 必须命中，注释里写同一句必须不命中。另有本跳手工反例：
/// 往 `App/AppState.swift` 顶部真加一行 `import StoreKit` ⇒ 本族判红，还原后 `sha256` 逐字节一致。
final class NoPaywallTests: XCTestCase {

    // MARK: - 判据 ①：计费符号

    /// 计费 SDK 与付费墙符号。只收**不会误伤 Combine「订阅」**的形状：
    /// 不扫「订阅」这个词（界面订阅视图模型遍地都是），只扫 SDK 名与付费墙专有词。
    private static let billingSymbols = [
        "import StoreKit",
        "StoreKit.",
        "SKPaymentQueue",
        "SKProduct(",
        "SKMutablePayment",
        "Product.purchase",
        "purchase(options:",
        "BillingClient",
        "com.android.billingclient",
        "RevenueCat",
        "Purchases.shared",
        "SwiftyStoreKit",
        "inAppPurchase",
        "paywall",
        "付费墙",
        "立即购买",
        "解锁全部功能",
    ]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 产品源码目录（相对仓根）。`Scripts/` 是门禁脚本、`Tests/` 是判据本身，都不算产品代码。
    private static let productRoots = ["App", "Core", "Plugins", "Tools"]

    /// 扫一组 `(相对路径, 原文)`，返回「路径: 符号」的命中清单。
    /// 做成静态纯函数是为了让负例能喂夹具，而不是只能靠改真文件。
    /// 注释整段剥掉：注释里写「不许出现 `import StoreKit`」是规矩，不是违规。
    static func billingHits(in files: [(path: String, text: String)]) -> [String] {
        var hits: [String] = []
        for file in files {
            let code = strippingComments(file.text)
            for symbol in billingSymbols where code.contains(symbol) {
                hits.append("\(file.path): \(symbol)")
            }
        }
        return hits
    }

    /// 剥注释（行注释 + 块注释，`/* */` 可嵌套）。字符串字面量不特殊处理 ——
    /// 计费符号出现在字面量里同样可疑，宁可判红让人来看一眼。
    static func strippingComments(_ text: String) -> String {
        var out = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if depth == 0, rest.hasPrefix("//") {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            }
            if rest.hasPrefix("/*") {
                depth += 1
                index = text.index(index, offsetBy: 2)
                continue
            }
            if depth > 0 {
                if rest.hasPrefix("*/") {
                    depth -= 1
                    index = text.index(index, offsetBy: 2)
                } else {
                    if text[index] == "\n" { out.append("\n") }
                    index = text.index(after: index)
                }
                continue
            }
            out.append(text[index])
            index = text.index(after: index)
        }
        return out
    }

    /// 收集产品源码：四目录下全部 `.swift`（递归）+ 仓根 `Package.swift`。
    private static func productSources() throws -> [(path: String, text: String)] {
        var files: [(String, String)] = []
        let manager = FileManager.default
        for root in productRoots {
            let base = repositoryRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                files.append((relative, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        let manifest = repositoryRoot.appendingPathComponent("Package.swift")
        if manager.fileExists(atPath: manifest.path) {
            files.append(("Package.swift", try String(contentsOf: manifest, encoding: .utf8)))
        }
        files.sort { $0.0 < $1.0 }
        return files
    }

    func testProductSourcesCarryNoBillingCode() throws {
        let files = try Self.productSources()
        XCTAssertGreaterThan(files.count, 100, "扫到的产品源文件太少（\(files.count) 份）—— 路径解析坏了？")
        let hits = Self.billingHits(in: files)
        XCTAssertEqual(
            hits, [],
            "判据 ①：App 内不许有计费 SDK ／ 付费墙（命中 \(hits.count) 处）：\(hits.prefix(8))"
        )
    }

    // MARK: - 判据 ②：未付费（Standard 档）时笔记面完整可用

    func testStandardEditionCoversTheNotesSurface() {
        XCTAssertTrue(
            LicenseEdition.standard.capabilities.contains(.notes),
            "无许可证 = Standard 档，Standard 不含笔记能力位 ⇒ 未付费用户的功能被拿掉了"
        )
    }

    func testNotesSourcesContainNoLicenseGating() throws {
        let files = try Self.productSources().filter { $0.path.hasPrefix("Plugins/Notes/") }
        XCTAssertGreaterThan(files.count, 20, "Notes 插件源文件太少（\(files.count) 份）—— 路径解析坏了？")
        let gatingSymbols = ["LicenseGate", "LicenseScope", "LicenseLoader", "requiredCapability", "entitlements"]
        var hits: [String] = []
        for file in files {
            let code = Self.strippingComments(file.text)
            for symbol in gatingSymbols where code.contains(symbol) {
                hits.append("\(file.path): \(symbol)")
            }
        }
        XCTAssertEqual(
            hits, [],
            "判据 ②：Notes 面不许读许可证（不读就没有降级）：\(hits.prefix(8))"
        )
    }

    // MARK: - 判据 ③：判据绑在台账那一行的口径上

    func testPaywallBanIsBoundToTheLedgerRow() throws {
        let ledger = Self.repositoryRoot.appendingPathComponent("Docs/Doyah产品开发计划任务清单-macOS.md")
        let text = try String(contentsOf: ledger, encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("| FR-NTS-ALL-LIC-001 |") }) else {
            return XCTFail("台账里找不到 FR-NTS-ALL-LIC-001 这一行 —— 判据 ③ 失去锚点")
        }
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let requirement = cells.count > 2 ? cells[2] : ""
        XCTAssertTrue(
            requirement.contains("不设付费墙"),
            "判据 ③：台账这一条的口径已被改动（『不设付费墙』不再成立）⇒ 本族判据必须同批重写，不许留着旧断言假装还在管"
        )
    }

    // MARK: - 负例（铁律 14）

    func testScannerFlagsBillingCodeButIgnoresComments() {
        let fixtures: [(path: String, text: String)] = [
            ("App/Fake.swift", "import SwiftUI\nimport StoreKit\nstruct A {}\n"),
            ("Core/FakeComment.swift", "// 注意：不许 import StoreKit\n/* 也不许 SKPaymentQueue */\nlet a = 1\n"),
            ("Plugins/Notes/Fake.swift", "let marker = \"BillingClient\"\n"),
        ]
        let hits = Self.billingHits(in: fixtures)
        XCTAssertEqual(hits.count, 2, "负例：真代码与字面量里的计费符号必须判红、注释里的不许判红 —— 实得 \(hits)")
        XCTAssertTrue(hits.contains { $0.hasPrefix("App/Fake.swift") }, "负例：`import StoreKit` 必须被命中")
        XCTAssertTrue(hits.contains { $0.hasPrefix("Plugins/Notes/Fake.swift") }, "负例：字面量里的计费名也要命中")
        XCTAssertFalse(hits.contains { $0.hasPrefix("Core/FakeComment.swift") }, "负例：注释里的计费名不许判红")
    }
}
