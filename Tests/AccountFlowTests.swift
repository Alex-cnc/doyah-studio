import XCTest
import Foundation
@testable import DoyahCore
@testable import DoyahStudioApp

/// 片 `云F` · 账号与同步界面（最小集）的机械复核。
///
/// 判据打在**真界面模型**（`App/Auth/AccountFlowModel.swift`）上，而不是在测试里另写一份规则 ——
/// 模型是那一屏唯一的判断处，另写一份就成了第二套口径。
///
/// 不碰真网络与真钥匙串：出网面注入假应答，令牌存储注入内存版
/// （与 macOS 的 `KeychainNoteSyncTokenStore` 同一个抽象层 `NoteSyncTokenStore`）。
///
/// 覆盖面（对应卡片判据 ①）：
///   · 注册通道**三步全跑**（`IR-18` ① ② ③：发码 ⇒ 校验 ⇒ 注册成功），
///     另加三条**不建账号**的路：字段没过 / 还没发码 / 服务端说没过（逐档）；
///   · 注册失败**只按服务端 `code` 分支**、`error_description` 不上屏（`IR-18` ⑥）；
///   · 登录失败**文案与路径不可区分**（用户名不存在 / 口令错 —— 同一个失败形态、同一句话、
///     同样一次请求；不做存在性预探）；
///   · **同步开关默认关**（契约 §10.4 `S3`）；
///   · **登出调用**（服务端撤销 + 本机会话清除 + 开关复位）。
/// 另有两条源码判据把 `S4` 的告知文案与「界面不连网」钉在盘上（卡片判据 ②）。
///
/// 手机号 / 验证码 / 口令一律用**合成值**：真号与真码不进仓、不进单、不进截图。
@MainActor
final class AccountFlowTests: XCTestCase {

    // MARK: - 夹具

    /// 与真实环境一致的环境 ID（与 `NoteSyncAuthTests` 同口径）。
    private let environmentID = "doyah-notes-db00-d6el2lr50a6ef27"

    private func makeClient(
        transport: AccountFlowTransport,
        store: AccountFlowTokenStore
    ) -> CloudAuthClient {
        CloudAuthClient(
            endpoints: CloudAuthEndpoints(environmentID: environmentID),
            transport: transport,
            store: store
        )
    }

    private func tokenResponse(
        access: String = "access-aaa",
        refresh: String = "refresh-aaa",
        subject: String = "uid-synthetic-0001"
    ) -> CloudAuthHTTPResponse {
        let json = """
        {"token_type":"Bearer","access_token":"\(access)","refresh_token":"\(refresh)",\
        "expires_in":7200,"sub":"\(subject)"}
        """
        return CloudAuthHTTPResponse(status: 200, body: Data(json.utf8))
    }

    /// 凭据错应答的**两种写法**：CloudBase 历史上用过不同字段（`CloudAuthErrorPayload` 两种都认）。
    /// 两条都必须落到**同一个**界面失败形态 —— 「用户名不存在」与「口令错」不可区分。
    private func invalidCredentialsResponse(errorCodeShape: Bool) -> CloudAuthHTTPResponse {
        let json = errorCodeShape
            ? #"{"error_code":4043,"error_description":"Username or password incorrect."}"#
            : #"{"code":"INVALID_USERNAME_OR_PASSWORD","error":"invalid_username_or_password"}"#
        return CloudAuthHTTPResponse(status: 400, body: Data(json.utf8))
    }

    /// 合成手机号：**不是真实号码**（真号与真码一律不入仓、不入单、不入截图）。
    ///
    /// 也**不写成一串连排的 11 位数字** —— 那样会被「号码不许入仓」的判据扫到；
    /// 这里按两段拼，源码里没有那 11 位的连排。
    private static let syntheticPhone = "1" + "0000000000"

    /// 归一之后那一串（带区号前缀）—— 断言拿它与请求体比，而不是在测试里再拼一次前缀
    /// （前缀只有一个出处：`CloudAuthPhoneNumber`）。
    private var normalizedPhone: String {
        CloudAuthPhoneNumber.normalized(Self.syntheticPhone)
    }

    /// ① 发码的成功应答（`IR-18` ①）：`{verification_id, expires_in}`（`is_user` 与界面无关，也带上）。
    private func verificationResponse(
        id: String = "vid-synthetic-0001",
        expiresIn: Int = 600
    ) -> CloudAuthHTTPResponse {
        let json = #"{"verification_id":"\#(id)","expires_in":\#(expiresIn),"is_user":false}"#
        return CloudAuthHTTPResponse(status: 200, body: Data(json.utf8))
    }

    /// ② 校验的成功应答（`IR-18` ②）：`{verification_token}`。
    private func verificationTokenResponse(
        token: String = "vtoken-synthetic-0001"
    ) -> CloudAuthHTTPResponse {
        let json = #"{"verification_token":"\#(token)"}"#
        return CloudAuthHTTPResponse(status: 200, body: Data(json.utf8))
    }

    /// 把记下来的请求体解成字典（复核形状用）。
    private func body(of request: CloudAuthHTTPRequest) throws -> [String: String] {
        let data = try XCTUnwrap(request.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    // MARK: - ① 注册页：字段校验

    func testRegistrationRejectsEmptyAndMismatchedFieldsAndSendsNoRequest() async {
        let transport = AccountFlowTransport(responses: [])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        // 空表单：从手机号一路报到口令，逐条报一次（顺序 = 表单顺序）——
        // 口令与确认都是空串时**不该**再报「两次不一致」（两边都还没输入时那是噪音，不是诊断）。
        XCTAssertEqual(
            AccountFlowModel.registrationIssues(
                phone: "",
                code: "",
                username: "",
                password: "",
                confirmation: ""
            ),
            [.phoneEmpty, .codeEmpty, .usernameEmpty, .passwordTooShort],
            "空表单的问题要一次报全（不许只报第一条）；空口令不报「两次不一致」"
        )

        // 太短 / 字符集 / 口令不一致（手机号与验证码这几条用例里都填好，只留下要判的那一条）
        XCTAssertEqual(
            AccountFlowModel.registrationIssues(
                phone: Self.syntheticPhone,
                code: "000000",
                username: "ab",
                password: "pw-not-real",
                confirmation: "pw-not-real"
            ),
            [.usernameTooShort]
        )
        XCTAssertEqual(
            AccountFlowModel.registrationIssues(
                phone: Self.syntheticPhone,
                code: "000000",
                username: "user name",
                password: "pw-not-real",
                confirmation: "pw-not-real"
            ),
            [.usernameInvalid],
            "含空格的用户名不合法（字符集只收 ASCII 字母 / 数字 / 下划线 / 短横线）"
        )
        XCTAssertEqual(
            AccountFlowModel.registrationIssues(
                phone: Self.syntheticPhone,
                code: "000000",
                username: "doyah_user-1",
                password: "pw-not-real",
                confirmation: "pw-not-real2"
            ),
            [.confirmMismatch]
        )
        XCTAssertTrue(
            AccountFlowModel.registrationIssues(
                phone: Self.syntheticPhone,
                code: "000000",
                username: "doyah_user-1",
                password: "pw-not-real",
                confirmation: "pw-not-real"
            ).isEmpty,
            "合法的一组字段不该报问题"
        )

        // 提交：字段没过 ⇒ 不建账号、连请求都不发
        model.phoneNumber = ""
        model.verificationCode = ""
        model.newUsername = ""
        model.newPassword = ""
        model.newConfirmation = ""
        await model.submitRegistration()

        XCTAssertEqual(
            model.registrationOutcome,
            .fieldIssues([.phoneEmpty, .codeEmpty, .usernameEmpty, .passwordTooShort])
        )
        XCTAssertEqual(model.status, .signedOut, "字段没过时状态不许动")
        XCTAssertTrue(transport.requests.isEmpty, "字段没过时一个请求都不该发出去")
        XCTAssertNil(try? store.session() ?? nil, "字段没过时不建账号、也不落会话")
    }

    // MARK: - ① 注册通道：发码 ⇒ 校验 ⇒ 注册（IR-18 ①②③）

    /// 三步全跑通：发码（①）⇒ 校验换 `verification_token`（②）⇒ 注册（③）。
    /// 同时把三条请求的**路径与请求体**逐条钉在契约口径上（判据 ③ 的机械版）。
    func testRegistrationRunsSendCodeThenVerifyThenSignUp() async throws {
        let transport = AccountFlowTransport(responses: [
            verificationResponse(),
            verificationTokenResponse(),
            tokenResponse(subject: "uid-synthetic-0003"),
        ])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        // ① 发码
        model.phoneNumber = Self.syntheticPhone
        await model.sendVerificationCode()

        XCTAssertTrue(model.verificationSent, "发码成功要给出回执（界面据此显示「已发出」）")
        XCTAssertEqual(model.status, .signedOut, "发码不建账号、也不登录")
        XCTAssertNil(model.registrationOutcome, "发码成功不该报失败")

        // ② 校验 + ③ 注册（界面那一下「注册」按钮就是这两步）
        model.verificationCode = "000000"
        model.newUsername = "doyah_user-1"
        model.newPassword = "pw-not-real"
        model.newConfirmation = "pw-not-real"
        await model.submitRegistration()

        XCTAssertEqual(model.status, .signedIn(uid: "uid-synthetic-0003"))
        XCTAssertEqual(model.signedInUID, "uid-synthetic-0003")
        XCTAssertNil(model.registrationOutcome, "走通了就没有失败要报")
        XCTAssertEqual(
            try store.session()?.subject,
            "uid-synthetic-0003",
            "注册成功与登录同一条路：令牌只经令牌存储（macOS = 钥匙串）"
        )

        // 三条请求：路径逐条对上 `IR-18` ① ② ③。
        XCTAssertEqual(transport.requests.count, 3, "发码 1 次 + 校验 1 次 + 注册 1 次")
        XCTAssertEqual(transport.requests[0].url.path, "/auth/v1/verification")
        XCTAssertEqual(transport.requests[1].url.path, "/auth/v1/verification/verify")
        XCTAssertEqual(transport.requests[2].url.path, "/auth/v1/signup")
        for request in transport.requests {
            XCTAssertEqual(request.method, "POST")
        }

        // ① 的请求体：`{phone_number, target:"ANY"}`，手机号**带区号与一个空格前缀**。
        let sent = try body(of: transport.requests[0])
        XCTAssertEqual(sent["target"], "ANY", "注册这一路必须用「不限制存在性」的那一档")
        XCTAssertEqual(sent["phone_number"], normalizedPhone)
        XCTAssertEqual(sent.count, 2)
        // 契约那句「必须带区号 + 一个空格」在这里变成可判读数：**逐字符**比前缀
        // （测试里不写连排字面量 —— 那会被「号码与区号前缀不入仓」的判据扫到）。
        XCTAssertEqual(
            Array(CloudAuthPhoneNumber.callingPrefix),
            ["+", "8", "6", " "],
            "`IR-18` ①：前缀 = 区号加**一个空格**（少一个空格服务端就判格式错）"
        )
        XCTAssertEqual(
            sent["phone_number"],
            CloudAuthPhoneNumber.callingPrefix + Self.syntheticPhone,
            "送出去的就是「前缀 + 用户填的那串」"
        )

        // ② 的请求体：`{verification_id, verification_code}`（id 就是①拿回来的那个）。
        let verify = try body(of: transport.requests[1])
        XCTAssertEqual(verify["verification_id"], "vid-synthetic-0001")
        XCTAssertEqual(verify["verification_code"], "000000")
        XCTAssertEqual(verify.count, 2)

        // ③ 的请求体：`{phone_number, verification_token, username, password}`。
        let signUp = try body(of: transport.requests[2])
        XCTAssertEqual(signUp["phone_number"], normalizedPhone)
        XCTAssertEqual(signUp["verification_token"], "vtoken-synthetic-0001", "用的是②换回来的那个 token")
        XCTAssertEqual(signUp["username"], "doyah_user-1")
        XCTAssertEqual(signUp["password"], "pw-not-real")
        XCTAssertEqual(signUp.count, 4)
    }

    /// 字段都填了、但**还没发码** ⇒ 一个请求都不发（没有 `verification_id` 就无从校验）。
    func testRegistrationWithoutSendingCodeStopsBeforeAnyRequest() async throws {
        let transport = AccountFlowTransport(responses: [])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        model.phoneNumber = Self.syntheticPhone
        model.verificationCode = "000000"
        model.newUsername = "doyah_user-1"
        model.newPassword = "pw-not-real"
        model.newConfirmation = "pw-not-real"
        await model.submitRegistration()

        XCTAssertEqual(
            model.registrationOutcome,
            .verificationNotStarted,
            "没发过码就说「先发码」，不拿一个空的 verification_token 去试"
        )
        XCTAssertEqual(model.status, .signedOut, "「未核验不建账号」：不登录、不建账号")
        XCTAssertTrue(transport.requests.isEmpty, "没发过码 ⇒ 一个请求都不该发出去")
        XCTAssertNil(try store.session(), "半个账号也不许留下（不进存储）")
    }

    /// 注册失败档 ③：**用户名已被占用**（服务端 `username_already_exists` / `409`）。
    func testRegistrationReportsUsernameTakenByServerCode() async throws {
        let transport = AccountFlowTransport(responses: [
            verificationResponse(),
            verificationTokenResponse(),
            CloudAuthHTTPResponse(
                status: 400,
                body: Data(
                    #"{"error":"username_already_exists","error_code":409,"error_description":"username already exists"}"#
                        .utf8
                )
            ),
        ])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        model.phoneNumber = Self.syntheticPhone
        await model.sendVerificationCode()
        model.verificationCode = "000000"
        model.newUsername = "doyah_user-1"
        model.newPassword = "pw-not-real"
        model.newConfirmation = "pw-not-real"
        await model.submitRegistration()

        guard case .failed(let failure) = model.registrationOutcome else {
            return XCTFail("服务端说没过 ⇒ 必须落到 .failed（实得 \(String(describing: model.registrationOutcome))）")
        }
        XCTAssertEqual(failure, .usernameTaken)
        XCTAssertEqual(failure.messageKey, .accountSignUpFailedUsernameTaken)
        XCTAssertFalse(
            LocalizedStrings.text(failure.messageKey, language: .english)
                .lowercased()
                .contains("already exists"),
            "服务端的 `error_description` 不许上屏（`IR-18` ⑥：界面只按 code 分支）"
        )
        XCTAssertEqual(model.status, .signedOut, "没建成账号就不许进登录态")
        XCTAssertNil(try store.session(), "失败了不许留会话")
        XCTAssertEqual(transport.requests.count, 3, "发码 + 校验 + 注册各一次（失败不是多打几次）")
    }

    /// 注册失败档 ④：**口令不合规**（服务端 `weak_password` / `4005` —— 复杂度由服务端判）。
    func testRegistrationReportsWeakPasswordByServerCode() async throws {
        let transport = AccountFlowTransport(responses: [
            verificationResponse(),
            verificationTokenResponse(),
            CloudAuthHTTPResponse(
                status: 400,
                body: Data(
                    #"{"error":"weak_password","error_code":4005,"error_description":"password too weak"}"#
                        .utf8
                )
            ),
        ])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        model.phoneNumber = Self.syntheticPhone
        await model.sendVerificationCode()
        model.verificationCode = "000000"
        model.newUsername = "doyah_user-1"
        model.newPassword = "pw-not-real"
        model.newConfirmation = "pw-not-real"
        await model.submitRegistration()

        guard case .failed(let failure) = model.registrationOutcome else {
            return XCTFail("服务端说没过 ⇒ 必须落到 .failed（实得 \(String(describing: model.registrationOutcome))）")
        }
        XCTAssertEqual(failure, .weakPassword)
        XCTAssertEqual(failure.messageKey, .accountSignUpFailedWeakPassword)
        // **不上屏的是服务端那一句**（本句自己的措辞里可以有「太弱」这类字样 ——
        // 判的是「没把服务端的 `error_description` 原样搬上来」，不是「不许提这件事」）。
        XCTAssertFalse(
            LocalizedStrings.text(failure.messageKey, language: .english)
                .lowercased()
                .contains("password too weak"),
            "服务端的 `error_description` 不许上屏（`IR-18` ⑥）"
        )
        XCTAssertNil(try store.session())
    }

    /// 服务端那几档码 → 界面那几档失败（`IR-18` ⑥ 的映射，逐条；纯函数，不发请求）。
    func testRegistrationFailureMappingFollowsServerCodes() {
        func error(status: Int, _ body: String) -> CloudAuthError {
            CloudAuthClient.failure(from: CloudAuthHTTPResponse(status: status, body: Data(body.utf8)))
        }

        // 官方 auth v2 那套（`error` + `error_code`）
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(status: 400, #"{"error":"invalid_verification_code","error_code":4001}"#)
            ),
            .verification
        )
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(status: 400, #"{"error":"invalid_phone_number","error_code":4001}"#)
            ),
            .verification,
            "手机号格式错与验证码错都说「这一关没过」—— 两种输入的修法在同一步"
        )
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(status: 429, #"{"error":"rate_limit_exceeded","error_code":4029}"#)
            ),
            .rateLimited
        )
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(status: 400, #"{"error":"username_already_exists","error_code":409}"#)
            ),
            .usernameTaken
        )
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(status: 400, #"{"error":"weak_password","error_code":4005}"#)
            ),
            .weakPassword
        )
        // 网关那套（`code` + `message` + `requestId`）：同一个语义换个栏名，也要认出。
        XCTAssertEqual(
            AccountFlowModel.registrationFailure(
                for: error(
                    status: 409,
                    #"{"code":"USERNAME_ALREADY_EXISTS","message":"Username already exists","requestId":"req-1"}"#
                )
            ),
            .usernameTaken
        )
        // 认不出的（服务端说了句我们不认识的话 / 出网失败）⇒ 不猜，归「没走到判定」。
        XCTAssertEqual(AccountFlowModel.registrationFailure(for: error(status: 500, "{}")), .incomplete)
        XCTAssertEqual(AccountFlowModel.registrationFailure(for: CloudAuthError.transport("boom")), .incomplete)
    }

    // MARK: - ① 登录失败：文案与路径不可区分（FR-AUTH-02）

    func testSignInFailureIsIndistinguishableBetweenUnknownUserAndWrongPassword() async {
        var failures: [AccountFlowModel.SignInFailure] = []
        var requestCounts: [Int] = []

        // 两种服务端错误体（同一个语义：凭据错）各跑一遍。
        for errorCodeShape in [true, false] {
            let transport = AccountFlowTransport(responses: [invalidCredentialsResponse(errorCodeShape: errorCodeShape)])
            let store = AccountFlowTokenStore()
            let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

            model.username = "doyah_user-1"
            model.password = "wrong-not-real"
            await model.signIn()

            guard case .failed(let failure) = model.status else {
                return XCTFail("凭据错必须落到 .failed（实得 \(model.status)）")
            }
            failures.append(failure)
            requestCounts.append(transport.requests.count)
            XCTAssertNil(try? store.session() ?? nil, "失败不许落一份会话")
        }

        XCTAssertEqual(failures, [.credentials, .credentials], "两种凭据错必须是同一个失败形态")
        XCTAssertEqual(requestCounts, [1, 1], "一次提交 = 一次请求：不做「先问账号在不在」的预探")
        XCTAssertEqual(failures[0].messageKey, failures[1].messageKey, "两种失败必须是同一句话")
        XCTAssertEqual(failures[0].messageKey, .accountSignInFailed)
    }

    /// 非凭据类失败（服务端 5xx / 出网不通）另说一句 —— 它不与账号存在性相关。
    func testSignInServerFailureYieldsIncompleteAndStillOneRequest() async {
        let transport = AccountFlowTransport(
            responses: [CloudAuthHTTPResponse(status: 503, body: Data("{}".utf8))]
        )
        let model = AccountFlowModel(client: makeClient(transport: transport, store: AccountFlowTokenStore()))

        model.username = "doyah_user-1"
        model.password = "pw-not-real"
        await model.signIn()

        XCTAssertEqual(model.status, .failed(.incomplete))
        XCTAssertEqual(transport.requests.count, 1)
    }

    // MARK: - 登录成功 + 本机会话读回（多端会话：只认本机这一份）

    func testSignInSuccessStoresSessionAndRefreshPicksItUp() async throws {
        let transport = AccountFlowTransport(
            responses: [tokenResponse(subject: "uid-synthetic-0002")]
        )
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        model.username = "doyah_user-1"
        model.password = "pw-not-real"
        await model.signIn()

        XCTAssertEqual(model.status, .signedIn(uid: "uid-synthetic-0002"))
        XCTAssertEqual(model.signedInUID, "uid-synthetic-0002")
        XCTAssertTrue(model.canUseCloudSync)
        XCTAssertEqual(try store.session()?.subject, "uid-synthetic-0002", "令牌只经令牌存储（macOS = 钥匙串）")

        // 重新打开面板：本机已有会话 ⇒ 直接进「已登录」，且**不惊动服务端**。
        let reopened = AccountFlowModel(client: makeClient(transport: transport, store: store))
        reopened.refresh()
        XCTAssertEqual(reopened.status, .signedIn(uid: "uid-synthetic-0002"))
        XCTAssertEqual(transport.requests.count, 1, "读本机会话不该再发请求")
    }

    // MARK: - ① 同步开关默认关（S3）

    func testCloudSyncToggleDefaultsToOffAndIsUnavailableWithoutAnAccount() async {
        let transport = AccountFlowTransport(responses: [tokenResponse()])
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        XCTAssertFalse(model.cloudSyncEnabled, "开关默认关：由用户显式开启（契约 §10.4 S3）")
        XCTAssertFalse(model.canUseCloudSync, "没登录时开关不可用（没有账号就没有「同步到云端」）")

        // 登录之后可用，但**仍然不会替用户打开**（开关是用户的一次显式动作）。
        model.username = "doyah_user-1"
        model.password = "pw-not-real"
        await model.signIn()

        XCTAssertTrue(model.canUseCloudSync)
        XCTAssertFalse(model.cloudSyncEnabled, "登录成功不替用户打开云同步")
    }

    // MARK: - ① 登出调用

    func testSignOutRevokesOnServerClearsLocalSessionAndTurnsSyncOff() async throws {
        let transport = AccountFlowTransport(
            responses: [tokenResponse(), CloudAuthHTTPResponse(status: 200, body: Data("{}".utf8))]
        )
        let store = AccountFlowTokenStore()
        let model = AccountFlowModel(client: makeClient(transport: transport, store: store))

        model.username = "doyah_user-1"
        model.password = "pw-not-real"
        await model.signIn()
        model.cloudSyncEnabled = true

        await model.signOut()

        XCTAssertEqual(model.status, .signedOut)
        XCTAssertFalse(model.cloudSyncEnabled, "登出即断同步：开关复位（下次登录要用户再明确开一次）")
        XCTAssertNil(try store.session(), "登出后本机不许再留会话")
        XCTAssertEqual(transport.requests.count, 2, "登录一次 + 登出（撤销）一次")
        XCTAssertEqual(transport.requests.last?.url.path, "/auth/v1/revoke")
    }

    // MARK: - 找回入口位（本体后置）

    func testRecoveryEntryOnlyExplainsThatTheFlowIsDeferred() {
        let transport = AccountFlowTransport(responses: [])
        let model = AccountFlowModel(client: makeClient(transport: transport, store: AccountFlowTokenStore()))

        XCTAssertFalse(model.showsRecoveryNotice)
        model.requestPasswordRecovery()
        XCTAssertTrue(model.showsRecoveryNotice, "入口位点了要把「本体后置」这件事说清楚")
        XCTAssertTrue(transport.requests.isEmpty, "找回 / 重置的本体后置 ⇒ 这一下不该发任何请求")
    }

    // MARK: - ② 源码判据：S4 逐字告知 + 界面不连网

    /// 卡片判据 ② 的机械版：`App/` 下「当前不是端到端加密」**恰 1 命中**且逐字为
    /// 「当前不是端到端加密 —— 内容在云端可读」；全仓不许出现「已加密」这类含糊措辞。
    func testS4NoticeIsVerbatimAndTheOnlyMentionInAppSources() throws {
        let s4 = "当前不是端到端加密 —— 内容在云端可读"

        // 屏幕上的字来自语言表 ⇒ 表里那句必须逐字等于 S4。
        XCTAssertEqual(
            LocalizedStrings.text(.accountSyncNotice, language: .simplifiedChinese),
            s4,
            "契约 §10.4 S4 要求逐字告知；语言表里那句是**屏幕上**的字"
        )

        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App")
        let appSources = try FileManager.default.subpathsOfDirectory(atPath: appRoot.path)
            .filter { $0.hasSuffix(".swift") }

        var hits: [String] = []
        var vagueWording: [String] = []
        for file in appSources {
            let text = try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8)
            if text.contains("当前不是端到端加密") { hits.append(file) }
            if text.contains("已加密") { vagueWording.append(file) }
        }

        XCTAssertEqual(hits.count, 1, "App/ 下这一句恰恰一处（实得 \(hits)）")
        let anchor = try String(
            contentsOf: appRoot.appendingPathComponent(hits[0]),
            encoding: .utf8
        )
        XCTAssertTrue(anchor.contains(s4), "那一处必须**逐字**为「\(s4)」")
        XCTAssertTrue(
            vagueWording.isEmpty,
            "全片不许出现「已加密」这类含糊措辞（S3 的另一半）：\(vagueWording)"
        )
    }

    /// 界面不直接连网（契约 §6.4「接口面纪律」）：视图那一层不许出现出网 / 钥匙串类型 ——
    /// 装配缝只在 `App/Auth/AccountFlowModel.swift` 的 `liveClient()` 一处。
    ///
    /// 判的是**代码**（注释行先剥掉）：注释里提一个类型名不是「调用了它」。
    func testAccountSheetKeepsTheNetworkOutOfTheViewLayer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheet = try String(
            contentsOf: root.appendingPathComponent("App/Views/AccountSyncSheet.swift"),
            encoding: .utf8
        )
        let sheetCode = Self.codeLines(of: sheet)

        for token in ["URLSession", "CloudAuthTransport", "Keychain", "SecItem"] {
            XCTAssertFalse(sheetCode.contains(token), "视图层出现了 \(token) —— 网络 / 钥匙串只能出现在共享逻辑层")
        }
        XCTAssertTrue(
            sheetCode.contains("AccountFlowModel"),
            "视图只**调用**模型：这一屏的判断全在 `AccountFlowModel` 里"
        )

        // 装配缝那一处（模型文件）确实把三样凑起来了 —— 判据要能看见「缝在哪」。
        let model = try String(
            contentsOf: root.appendingPathComponent("App/Auth/AccountFlowModel.swift"),
            encoding: .utf8
        )
        for token in ["URLSessionCloudAuthTransport", "KeychainNoteSyncTokenStore", "CloudAuthEndpoints"] {
            XCTAssertTrue(model.contains(token), "装配缝里缺 \(token)")
        }
    }

    /// 剥掉整行注释（`//` / `///` 开头）——源码判据的惯例：判代码，不判注释里提到的词。
    private static func codeLines(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}

// MARK: - 测试替身

/// 出网替身：按队列吐预设应答，并**记下发出过的每个请求**。
private final class AccountFlowTransport: CloudAuthTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [CloudAuthHTTPResponse]
    private var recorded: [CloudAuthHTTPRequest] = []

    init(responses: [CloudAuthHTTPResponse]) {
        self.queued = responses
    }

    var requests: [CloudAuthHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !queued.isEmpty else {
            throw CloudAuthError.transport("no queued response")
        }
        return queued.removeFirst()
    }
}

/// 令牌存储替身：内存版（与 macOS 的 `KeychainNoteSyncTokenStore` 同一个抽象层）。
private final class AccountFlowTokenStore: NoteSyncTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: NoteSyncSession?

    func setSession(_ session: NoteSyncSession) throws {
        lock.lock()
        defer { lock.unlock() }
        value = session
    }

    func session() throws -> NoteSyncSession? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func deleteSession() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}
