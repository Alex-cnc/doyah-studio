import XCTest
@testable import DoyahCore

/// **密钥只走一处出口**：`LLMRequest.apiKey` ⇒ `Authorization` 头。
///
/// 由头（2026-10-16 实机踩到）：AI 助手配置面板的「测试连接」第一版**漏了 `apiKey`**，
/// 发出去的是**裸请求**，端点原样回 **401** —— 看上去像"用户的 key 不对"，
/// 实际是代码里少带了一个参数。任何**新造**的模型请求都必须显式带上它，这两条把这个陷阱钉在判据里。
final class LLMStreamingAuthTests: XCTestCase {

    /// 测试用的假密钥（**不是真密钥**，只为断言装配位置）。
    private let fakeKey = "sk-test-not-a-real-key"

    func testRequestWithoutAPIKeyCarriesNoAuthorizationHeader() throws {
        let request = LLMRequest(endpoint: URL(string: "https://api.deepseek.com/v1")!, model: "deepseek-v4-flash",
                                 systemPrompt: "s", userPrompt: "u")
        let urlRequest = try OpenAICompatibleClient.makeURLRequest(request)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"),
                     "没带 key 的请求**不许**出现 Authorization 头（出现了就说明别处偷偷补了 key，口径会分叉）")
    }

    func testAPIKeyTravelsOnlyInTheAuthorizationHeader() throws {
        var request = LLMRequest(endpoint: URL(string: "https://api.deepseek.com/v1")!, model: "deepseek-v4-flash",
                                 systemPrompt: "s", userPrompt: "u")
        request.apiKey = fakeKey

        let urlRequest = try OpenAICompatibleClient.makeURLRequest(request)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer \(fakeKey)",
                       "带了 key 就必须进 Authorization 头 —— 否则端点回 401，而人会去怀疑自己的 key")

        let body = String(data: urlRequest.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains(fakeKey), "密钥**不许**写进请求体（免得被日志 / 审计顺走）")
    }
}
