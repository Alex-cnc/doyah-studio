import Foundation
import Combine
import DoyahCore
import DoyahPlatform

/// 片 `云F` · **账号与同步界面的流程模型** —— 界面上每一个判断只有这一处，视图只照它画。
///
/// 为什么模型在 App 侧、而认证调用在 Core：本片要判的都是**界面状态**（当前在哪一页、
/// 开关开机时是什么值、按下提交之后显示哪句话），而「用户名 + 口令」的认证调用仍只出现在
/// 共享逻辑层的同步模块里（`Core/NoteSync/CloudAuth.swift`，片 `云C` 已合入）——
/// 契约 §6.4「接口面纪律」：网络调用只允许在共享逻辑层的同步模块内，**界面不直接连网**。
/// 所以本文件是**装配缝**：它把 `CloudAuthClient` 组装起来（出网传输 + 钥匙串令牌存储），
/// 视图那一层只认本模型，连 `URLSession` 这个词都不会出现。
///
/// 四条口径写在这里，免得被下一个改它的人重新猜一遍：
///
///  ① **登录失败只有一句话**（`FR-AUTH-02`）：服务端对「用户名不存在」与「口令错」回同一个
///     `4043`（`CloudAuthError.isInvalidCredentials`），到界面就只允许一种失败形态
///     （`.credentials`）—— 既不做「先问这个账号在不在」的预探（那会同时改**耗时**与**存在性**），
///     也不把服务端的错误码透给用户看。
///  ② **同步开关默认关**（契约 §10.4 `S3`：由用户显式开启；服务端不得代开）。
///     开关旁边**常显** `S4` 那句逐字告知 —— 原文落 `Core/Localization.swift` 的
///     `.accountSyncNotice`（屏幕上显示的就是它）。
///  ③ **没核验就不建账号**（`FR-AUTH-01`）：注册页只做字段校验；当前 `CloudAuthClient`
///     只落了登录 / 刷新 / 登出（`IR-18` 的登录三面），**没有 signUp 面** ⇒ 本片按卡片停手线 ②
///     **不自行扩接口**：校验通过也只是停在「缺核验通道」这一步，**不建半个账号**（缺口登记为卡片）。
///  ④ **登出即断同步**：登出后同步开关复位（没有账号就没有「同步到云端」这件事，
///     下次登录要用户再明确开一次 —— 不替用户记着）。
@MainActor
final class AccountFlowModel: ObservableObject {

    // MARK: - 页面

    /// 账号面两页（最小集：注册页 + 登录页）。
    enum Page: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var titleKey: LKey {
            switch self {
            case .signIn: return .accountTabSignIn
            case .signUp: return .accountTabSignUp
            }
        }
    }

    // MARK: - 状态

    /// 账号面的状态机。文案一律以**键**带出来（`Status` 里不存译文）—— 界面用 `L(…)` 渲染，
    /// 于是「文案只有一个出处」（NFR-I18N-02）在类型上就成立。
    enum Status: Equatable {
        /// 没登录（初始态；也可能是刚登出）。
        case signedOut
        /// 正在请求（按钮禁用，避免连点两次发出两次请求）。
        case working
        case failed(SignInFailure)
        /// 已登录。`uid` = 云端归属主键（`NoteSyncSession.subject`），展示给用户看「登的是哪个账号」。
        case signedIn(uid: String)
    }

    /// 登录失败的两种形态。**凭据错只有一档**（见文件注释 ①）。
    enum SignInFailure: Equatable {
        /// 用户名或口令不对。**不区分**是哪一个不对（`FR-AUTH-02` 的「文案与耗时不可区分」）。
        case credentials
        /// 请求没走到判定（出网失败 / 服务端非凭据类错误）。文案是语言表里的一句话，
        /// **不携带任何来自应答的字段** —— 少一个能被用来判断账号存在性的信号。
        case incomplete

        /// 这一档失败要说的话（界面用 `L(…)` 渲染）。写在模型里而不是视图里：
        /// 「失败该说哪句话」也是判断，判据要能直接读它（`Tests/AccountFlowTests.swift`）。
        var messageKey: LKey {
            switch self {
            case .credentials: return .accountSignInFailed
            case .incomplete: return .accountSignInIncomplete
            }
        }
    }

    /// 注册页的字段问题（`FR-AUTH-01` 的客户端校验面）。**逐条**给出，不只报第一条 ——
    /// 一次报全，用户不必「改一条、再被打回一次」。
    enum FieldIssue: String, CaseIterable, Equatable {
        case usernameEmpty
        case usernameTooShort
        case usernameInvalid
        case passwordTooShort
        case confirmMismatch

        var messageKey: LKey {
            switch self {
            case .usernameEmpty: return .accountFieldUsernameEmpty
            case .usernameTooShort: return .accountFieldUsernameTooShort
            case .usernameInvalid: return .accountFieldUsernameInvalid
            case .passwordTooShort: return .accountFieldPasswordTooShort
            case .confirmMismatch: return .accountFieldConfirmMismatch
            }
        }
    }

    /// 注册提交的结果（界面照它画）。两条路**都不建账号**，分开说是因为原因不同。
    enum RegistrationOutcome: Equatable {
        /// 字段没过 ⇒ 连请求都不发。
        case fieldIssues([FieldIssue])
        /// 字段过了，但**没有可用的核验 / 建账号通道** ⇒ 仍然不建账号
        /// （`FR-AUTH-01` 的「未验证不建账号」这一支在当前接口面上的样子）。
        case verificationUnavailable
    }

    // MARK: - 字段口径（唯一出处）

    /// 用户名长度下限与上限；`FR` 侧只写「用户名 + 密码」，长度是客户端自己的可读口径。
    static let usernameMinimumLength = 3
    static let usernameMaximumLength = 32
    /// 口令长度下限。**只判长度、不判复杂度**：复杂度规则要么写死在客户端（改了就要发版、
    /// 且会与将来服务端的规则分叉），要么由服务端在 signUp 时给 —— 那是 signUp 面接线后的事。
    static let passwordMinimumLength = 8

    /// 注册页的字段校验 —— **唯一出处**（视图不自己判，判据也读它）。
    ///
    /// 用户名先**去掉首尾空白**（复制粘贴常带），再判空 / 长度 / 字符集；
    /// 字符集刻意收在 ASCII（字母 / 数字 / 下划线 / 短横线）：用户名要进出登录框、
    /// URL 与云端凭据表，中英文混用的名字在这些地方会各自出问题。
    static func registrationIssues(
        username: String,
        password: String,
        confirmation: String
    ) -> [FieldIssue] {
        var issues: [FieldIssue] = []
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            issues.append(.usernameEmpty)
        } else if name.count < usernameMinimumLength {
            issues.append(.usernameTooShort)
        } else if !isValidUsername(name) {
            issues.append(.usernameInvalid)
        }

        if password.count < passwordMinimumLength {
            issues.append(.passwordTooShort)
        }

        if password != confirmation {
            issues.append(.confirmMismatch)
        }

        return issues
    }

    /// 用户名字符集与上限（长度下限由 `registrationIssues` 先说，免得两条口径各报一次）。
    static func isValidUsername(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= usernameMaximumLength else { return false }
        return name.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }

    /// 认证错误 → 界面那两种失败形态（`FR-AUTH-02`：凭据错只有一档）。
    static func failure(for error: Error) -> SignInFailure {
        if let auth = error as? CloudAuthError, case .invalidCredentials = auth {
            return .credentials
        }
        return .incomplete
    }

    // MARK: - 依赖

    private let client: CloudAuthClient

    // MARK: - 界面状态（唯一出处）

    @Published var page: Page = .signIn

    /// 登录页字段。
    @Published var username = ""
    @Published var password = ""

    /// 注册页字段。
    @Published var newUsername = ""
    @Published var newPassword = ""
    @Published var newConfirmation = ""

    @Published private(set) var status: Status = .signedOut

    /// 云同步开关 —— **默认关**（契约 §10.4 `S3`），**持久化**（片 `云D`：写入端 `AppState`
    /// 的触发点要读它，所以开关不能只活在这一次面板里 —— 两处各读一份就成了「一个开着、
    /// 一个当关」）。落键与缺省见 `CloudSyncPreference`（Core 侧的**唯一出处**）。
    @Published var cloudSyncEnabled = CloudSyncPreference.isEnabled() {
        didSet { CloudSyncPreference.setEnabled(cloudSyncEnabled) }
    }

    /// 注册页最近一次提交的结果（`nil` = 还没提交过）。
    @Published private(set) var registrationOutcome: RegistrationOutcome?

    /// 「找回 / 重置口令」入口位：点了只把「本体后置」这件事说清楚（边界：入口位，本体后置）。
    @Published private(set) var showsRecoveryNotice = false

    init(client: CloudAuthClient) {
        self.client = client
    }

    // MARK: - 读

    /// 当前有没有登录。
    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    /// 开关能不能动：**没有账号就没有「同步到云端」**（`S1`/`S2` 的前提是账号下同步）。
    var canUseCloudSync: Bool { isSignedIn }

    /// 登录中的 `uid`（没登录为 `nil`）。
    var signedInUID: String? {
        if case .signedIn(let uid) = status { return uid }
        return nil
    }

    // MARK: - 动作

    /// 打开面板时调一次：本机钥匙串里若已有会话，直接进「已登录」。
    ///
    /// **只读本机这一份、不惊动服务端**：多端会话（`FR-AUTH-05`）下同一 `uid` 可以在别的设备上
    /// 各有一份会话，这里认的是**本机**的；读不出来（钥匙串不可用）按未登录处理，
    /// 不让一个坏掉的存储把界面卡在「正在请求」。
    func refresh() {
        if let session = (try? client.currentSession()) ?? nil {
            status = .signedIn(uid: session.subject)
        } else {
            status = .signedOut
        }
    }

    /// 登录（`IR-18`，用户名 + 口令）。
    ///
    /// **一次提交 = 一次请求**，中间没有任何预探或分支（见文件注释 ①）：
    /// 两条失败路径在界面上的表现是同一个值、同一句话、同样一次请求 ——
    /// 「耗时不可区分」在机械面就是这条（不去做「先问账号在不在」这种能同时泄露耗时与存在性的事）。
    ///
    /// 同步调用在**主 actor 之外**跑（`CloudAuthClient` 的接口是同步的，不挪走会把界面卡住
    /// 一个网络往返）。
    func signIn() async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        let client = self.client

        status = .working
        registrationOutcome = nil

        let outcome: SignInOutcome = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try client.signIn(username: name, password: secret))
            } catch let error as CloudAuthError {
                return .failure(error)
            } catch {
                // 走到这儿说明出网层抛了非 `CloudAuthError` —— 按「没走到判定」处理，
                // 不给用户看反射出来的技术串（那句既读不懂、也可能带上请求细节）。
                return .failure(.transport("unexpected"))
            }
        }.value

        switch outcome {
        case .success(let session):
            // 登录成功**不动同步开关**：开不开云同步是用户显式的一次动作（口径 ②），
            // 不因为「登上了」就替他打开。
            status = .signedIn(uid: session.subject)
        case .failure(let error):
            status = .failed(Self.failure(for: error))
        }
    }

    /// 登出（`IR-18`）：请服务端撤销刷新令牌，**然后**清掉本机会话。
    ///
    /// 本地清理在 `CloudAuthClient.signOut` 里放在最后且不依赖网络结果 ⇒ 离线也登得掉；
    /// 这里再把同步开关复位（口径 ④）。
    func signOut() async {
        let client = self.client
        _ = await Task.detached(priority: .userInitiated) {
            try? client.signOut()
        }.value

        cloudSyncEnabled = false
        status = .signedOut
    }

    /// 注册页提交（`FR-AUTH-01`）。
    ///
    /// **不建账号是这条路径的常态**，两种原因分开说：
    ///   · 字段没过 ⇒ 逐条报问题，连请求都不发；
    ///   · 字段过了但**没有建账号的通道**（`CloudAuthClient` 现状只有登录 / 刷新 / 登出）
    ///     ⇒ 停在「缺核验通道」这一步。
    ///
    /// 于是「未（核验）不建账号」在当前接口面上**恒成立**：根本没有建账号的代码路径，
    /// 也没有「先建一个再说」的兜底 —— 缺口登记为卡片，由接口面落定后另片接线。
    func submitRegistration() {
        let issues = Self.registrationIssues(
            username: newUsername,
            password: newPassword,
            confirmation: newConfirmation
        )
        registrationOutcome = issues.isEmpty ? .verificationUnavailable : .fieldIssues(issues)
    }

    /// 「找回 / 重置口令」入口位（本体后置 —— 本片只把这件事说清楚）。
    func requestPasswordRecovery() {
        showsRecoveryNotice = true
    }
}

// MARK: - 装配面

extension AccountFlowModel {

    /// CloudBase 环境 ID（云A 落的 `.cloudbase/project.json` 里那一串；**不是 secret** ——
    /// 契约 §6.4 账号行：客户端只持 publishable key，**任何 secret 不进客户端**）。
    ///
    /// 为什么先写在这里、不去读 `.cloudbase/project.json`：那份文件是 **tcb CLI 的配置**
    /// （云A 的交付物，不该被运行时依赖，也不进 .app 包）。本片是最小集，先把「一个出处」
    /// 立在这里；等端到端接线（`云D`/`云G`）时再收进正式的配置面 —— 已登记在卡片上。
    ///
    /// `nonisolated`：这两个静态成员是**装配常量**，不碰实例状态；标成非隔离之后
    /// 视图的默认实参（`AccountSyncSheet(client: …)`）才能在非隔离的 `init` 里取值。
    nonisolated static let environmentID = "doyah-notes-db00-d6el2lr50a6ef27"

    /// 真装配：网关端点 + `URLSession` 出网 + **系统钥匙串**令牌存储（`IR-18`：令牌不落明文文件）。
    ///
    /// 这是本片唯一一处把三样东西凑到一起的地方（视图那一层不碰其中任何一样）。
    nonisolated static func liveClient() -> CloudAuthClient {
        CloudAuthClient(
            endpoints: CloudAuthEndpoints(environmentID: environmentID),
            transport: URLSessionCloudAuthTransport(),
            store: KeychainNoteSyncTokenStore()
        )
    }
}

/// 出网调用的结果（只在模型内部传递）。写成具名类型而不是 `Result<…, Error>`：
/// 跨 actor 带走的值都在这两档里，`Error` 那档只可能是 `CloudAuthError`。
private enum SignInOutcome: Sendable {
    case success(NoteSyncSession)
    case failure(CloudAuthError)
}
