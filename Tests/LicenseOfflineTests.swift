import XCTest

/// FR-STD-ALL-LIC-001 判据 ③「全程离线可校验，无联网激活」的**源树**那一半。
///
/// 为什么不是运行时用例：单测跑在沙箱里本来就连不上网，「跑通了」证明不了
/// 「代码里没有一条联网路径」—— 那正是判据要判的东西。所以这里扫许可证这条链路
/// 上的全部文件，断言它们**一个联网符号都没有**：签名靠内置公钥、载荷读本地文件，
/// 不需要服务器参与。
///
/// **覆盖边界（如实）**：静态扫描（去注释后按符号匹配）能判住「有人新增一条 `URLSession`
/// 调用」，判不住「通过别的模块间接联网」；真抓包记未覆盖。
final class LicenseOfflineTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 许可证链路上的全部文件（签发工具也算：它要是自己联网，发行方那侧就上网了）。
    private static let licenseSources = [
        "Core/License.swift",
        "Core/LicenseLoader.swift",
        "Core/LicenseSignature.swift",
        "Core/LicensePublicKey.swift",
        "Core/LicensePresentation.swift",
        "Core/LicenseHighlights.swift",
        "Tools/LicenseTool/main.swift",
    ]

    private static let networkSymbols = [
        "URLSession", "NSURLSession", "NSURLConnection", "URLRequest",
        "CFNetwork", "import Network", "NWConnection", "dataTask",
        "Socket", "NWPath", "socket(",
    ]

    /// 去掉注释再扫：注释里写「不联网激活」不算违规，代码里写 `URLSession` 才算。
    private func strippingComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                guard trimmed.hasPrefix("//") else { return line[...] }
                return ""
            }
            .joined(separator: "\n")
    }

    func testLicensePathHasNoNetworkSymbols() throws {
        var hits: [String] = []
        for relative in Self.licenseSources {
            let code = strippingComments(try source(relative))
            for symbol in Self.networkSymbols where code.contains(symbol) {
                hits.append("\(relative): \(symbol)")
            }
        }
        XCTAssertEqual(hits, [], "许可证链路不许出现联网符号（判据 ③ 无联网激活）：\(hits)")
    }

    /// 判据 ③ 的**接线**一半：校验器只从内置公钥来、载荷只从本地文件读 ——
    /// 两者缺一个，上面那条「没有联网符号」就只是「代码里碰巧没写」，不是「结构上不需要网」。
    func testVerificationIsWiredToBuiltInKeyAndLocalFile() throws {
        let loader = try source("Core/LicenseLoader.swift")
        XCTAssertTrue(
            loader.contains("LicensePublicKey.verifier(environment: environment)"),
            "校验器必须来自内置公钥，不许另接一个远端校验服务"
        )
        XCTAssertTrue(
            loader.contains("String(contentsOf: target, encoding: .utf8)"),
            "载荷必须从本地文件读（离线可校验）"
        )

        let signature = try source("Core/LicenseSignature.swift")
        XCTAssertTrue(signature.contains("Curve25519.Signing.PublicKey"), "离线校验走 Ed25519 本地验签")
        XCTAssertTrue(signature.contains("isValidSignature("), "判定只由本地验签给出")
    }
}
