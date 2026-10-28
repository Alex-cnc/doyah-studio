import Foundation

// MARK: - 政策

/// 凭据落钥匙串时的**属性口径**（★00：主人 2026-10-29 当面点出「keychain 有个问题就是每次启动都要输入密码」）。
///
/// 根因是**两个**，别只治一个：
///   ① 条目建的时候既没带 `kSecAttrAccessible`、也没绑 ACL ⇒ 访问控制只剩「创建它的那个应用」，
///      而「应用」是按**代码签名**认的 ⇒ 签名一变，读就要求授权；
///   ② 构建身份不稳：曾经有身份缺失就**静默回退 ad-hoc**，ad-hoc 没有证书 ⇒
///      每次重打包都换一个「应用」⇒ 每次都弹。
///
/// 本类型治 ① 的属性面；「谁是当前那个应用」由 `CredentialRewriteLedger` 那套一次性重写治；
/// ② 由 `Scripts/build-app.sh` 的身份自检治（不许再静默回退）。
///
/// ⚠️ **一条实测边界，必须写下来**（2026-10-29 本机探针：`SecItemAdd` 后回读属性）：
/// 登录钥匙串**会吞掉** `kSecAttrAccessible` —— 带着该属性 `SecItemAdd` 返回 `errSecSuccess`，
/// 回读却是 `nil`；改用 `kSecUseDataProtectionKeychain = true` 直接 `-34018`
/// （`errSecMissingEntitlement`：数据保护钥匙串要 `keychain-access-groups` 授权，自签身份给不了）。
/// ⇒ 本常量在今天的**登录钥匙串上不产生行为差别**，它的价值是「换到数据保护钥匙串那天已经带上了」。
/// **不许**拿它当「弹窗已治」的证据；弹窗唯一的机械证据是「重写之后不再重写」（见账本）与主人点一次。
public enum CredentialStoragePolicy {
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 的原始值（实测打印 `cku`）。
    ///
    /// 为什么写字面量而不是引常量：`Security` 只有 Apple 平台有，Core 要两个平台都能编译
    /// （需求书 §10.9 P-02）。取值由判据看住，不许漂。
    public static let requiredAccessibilityRawValue = "cku"

    /// 写完条目后**必须**把当前应用显式写进 ACL（`SecAccess` + `SecTrustedApplication`）。
    ///
    /// 不显式给时，系统把「创建它的应用」隐式写进去 —— 那个「应用」按签名认，签名一换就谁都不认。
    public static let bindsCurrentApplication = true

    /// 允许随备份迁移吗：**不允许**。口令跟着备份跑到另一台机器，是「换了机器也能连生产库」的起点。
    public static let migratesWithBackup = false
}

/// 账本文件名（住在应用支持目录下；与其它配置文件并列）。
public enum CredentialRewriteLedgerFile {
    public static let fileName = "keychain-rewrite-ledger.json"
}

// MARK: - 一条记录的视图

/// 一条钥匙串记录的**可核对视图**（平台侧实现真实读写，Core 只做判定与记账）。
public protocol CredentialItemSlot {
    /// 界面 / 日志里能说的名字（**不含密文**）。
    var label: String { get }
    /// 账本里的键：同一条记录在账本里只该有一行（连接口令用连接 id，其余用固定账号名）。
    var account: String { get }
    /// 只读判断：这条在不在。**不读内容**（读内容正是会弹授权的那一步）。
    func exists() -> Bool
    func readSecret() throws -> String?
    func deleteItem() throws
    /// 按**当前签名**重写（落盘属性走 `CredentialStoragePolicy`）。
    func writeSecret(_ secret: String) throws
}

/// 平台侧读写的失败码（`OSStatus` 原样带出来，**不翻译**成「出错了」）。
public struct CredentialSlotError: Error, Equatable {
    public let code: Int32
    public init(code: Int32) { self.code = code }
}

/// 与判定有关的几个 `OSStatus`，按实测钉住（`swift` 打印过）。
public enum CredentialKeychainStatus {
    public static let success: Int32 = 0
    public static let itemNotFound: Int32 = -25300
    public static let authFailed: Int32 = -25293
    public static let duplicateItem: Int32 = -25299
    public static let interactionNotAllowed: Int32 = -25308
    public static let missingEntitlement: Int32 = -34018
}

// MARK: - 账本

/// 「哪些条目已经按**当前这套签名**重写过」的账。
///
/// **为什么需要账本，而不是每次都探一下能不能读**：
/// 探「读它会不会弹框」这件事本身就要去读 —— 而那一下正是会弹框的那一下（实测：
/// `kSecUseAuthenticationUIFail` 管的是数据保护钥匙串的 LAContext 条目，登录钥匙串的 ACL 授权框
/// 它拦不住）。所以不能靠探测判断，只能靠**记账**：同一套签名下重写过一次就不再动，
/// 签名一变（重建 / 换身份 / 回退 ad-hoc）就整批再重写一次 —— 而这正好就是主人报的症状的治法。
public struct CredentialRewriteLedger: Codable, Equatable {
    /// 当前这套签名是哪一套。取不到时为空串（**不是**「不用管」：空串也只算一套，照样会走一次重写）。
    public private(set) var signatureFingerprint: String
    /// 已经按这套签名重写成功的条目键。
    public private(set) var accounts: Set<String>

    public init(signatureFingerprint: String = "", accounts: Set<String> = []) {
        self.signatureFingerprint = signatureFingerprint
        self.accounts = accounts
    }

    /// 这一条还要不要重写。
    public func needsRewrite(account: String, fingerprint: String) -> Bool {
        signatureFingerprint != fingerprint || !accounts.contains(account)
    }

    /// 记一笔成功。**签名变了就先清空**：旧签名下的记录对新签名没有意义。
    public mutating func markRewritten(account: String, fingerprint: String) {
        if signatureFingerprint != fingerprint {
            signatureFingerprint = fingerprint
            accounts = []
        }
        accounts.insert(account)
    }

    // 解不出来时**回落成空账本**（而不是抛错）：空账本 = 这一轮会把现有条目按当前签名重写一遍，
    // 也就是「最坏情况多弹一次」，而抛错会让调用方要么崩、要么整段跳过 —— 那才是真的治不好。
    public static func decode(_ data: Data) -> CredentialRewriteLedger {
        (try? JSONDecoder().decode(CredentialRewriteLedger.self, from: data)) ?? CredentialRewriteLedger()
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // 同一份账本两遍逐字节相同
        return (try? encoder.encode(self)) ?? Data()
    }
}

// MARK: - 判定与执行

/// 一条记录的实际处置结局。
public enum CredentialSlotOutcome: Equatable {
    case kept
    case missing
    /// 会重写，但内容为空 —— 没有东西要保，也不该凭空造一条空记录（记账，免得每次启动都去读它）。
    case empty
    case rewrote
    case readFailed(code: Int32)
    case deleteFailed(code: Int32)
    case writeFailed(code: Int32)
}

/// 一次核对的总账（**读数只用它**，不另数一遍）。
public struct CredentialReconcileReport: Equatable {
    public struct Entry: Equatable {
        public let label: String
        public let outcome: CredentialSlotOutcome
    }

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    mutating func record(_ label: String, _ outcome: CredentialSlotOutcome) {
        entries.append(Entry(label: label, outcome: outcome))
    }

    public func count(_ outcome: CredentialSlotOutcome) -> Int {
        entries.filter { $0.outcome == outcome }.count
    }

    /// 带载荷的那几档（`readFailed(code:)` 之类）没法当值传，用谓词数。
    public func count(where predicate: (CredentialSlotOutcome) -> Bool) -> Int {
        entries.filter { predicate($0.outcome) }.count
    }

    /// 治不好、必须让主人知道的那几条 —— **不吞**。
    public var problems: [Entry] {
        entries.filter {
            switch $0.outcome {
            case .kept, .missing, .empty, .rewrote:
                return false
            case .readFailed, .deleteFailed, .writeFailed:
                return true
            }
        }
    }

    /// 一行读数（控制台 / 面板用；同一份报告两遍必须逐字相同 ⇒ 不带时间戳）。
    public func summaryLine() -> String {
        let done = count(.kept) + count(.empty)
        let problems = entries.count - done - count(.missing) - count(.rewrote)
        var parts = [
            "凭据核对 \(entries.count) 条",
            "已可用 \(done)",
            "本次按当前签名重写 \(count(.rewrote))"
        ]
        parts.append(problems == 0 ? "读不出来 / 写不进去 0 条" : "读不出来 / 写不进去 \(problems) 条")
        return parts.joined(separator: " · ")
    }
}

public enum CredentialReconciler {

    /// 纯判定（三条口径写死在这里，平台侧不再写一遍）：
    ///   · 没有这条 ⇒ `missing`（不凭空造）；
    ///   · 这套签名下已经重写过 ⇒ `keep`（**不读内容**：读正是会弹授权的那一步）；
    ///   · 其余 ⇒ `rewrite`（读 → 删 → 按当前签名写回）。
    public static func decide(
        exists: Bool,
        needsRewrite: Bool
    ) -> CredentialReconcileDecision {
        if !exists { return .missing }
        return needsRewrite ? .rewrite : .keep
    }

    /// 全部核一遍，返回报告与**新账本**。一条失败不影响其余。
    ///
    /// 账本只在**成功**时前进（`rewrote` / `empty`）：失败的那条下次启动还会再试一次 ——
    /// 反过来「失败也记账」会让一条治不好的凭据从此静默地永远弹窗。
    public static func reconcile(
        slots: [any CredentialItemSlot],
        fingerprint: String,
        ledger: CredentialRewriteLedger
    ) -> (report: CredentialReconcileReport, ledger: CredentialRewriteLedger) {
        var report = CredentialReconcileReport()
        var ledger = ledger
        for slot in slots {
            let outcome = reconcile(slot, fingerprint: fingerprint, ledger: &ledger)
            report.record(slot.label, outcome)
        }
        return (report, ledger)
    }

    /// 一条的处置。顺序写死在 `switch` 里：`read → delete → write`。
    ///
    /// 为什么**先读**再删：删了再读就永远读不回来 —— 读失败那一步必须发生在任何破坏性动作之前。
    public static func reconcile(
        _ slot: any CredentialItemSlot,
        fingerprint: String,
        ledger: inout CredentialRewriteLedger
    ) -> CredentialSlotOutcome {
        let exists = slot.exists()
        switch decide(exists: exists, needsRewrite: ledger.needsRewrite(account: slot.account, fingerprint: fingerprint)) {
        case .missing:
            return .missing
        case .keep:
            return .kept
        case .rewrite:
            let secret: String?
            do {
                secret = try slot.readSecret()
            } catch let error as CredentialSlotError {
                return .readFailed(code: error.code)
            } catch {
                return .readFailed(code: CredentialKeychainStatus.authFailed)
            }
            guard let secret, !secret.isEmpty else {
                ledger.markRewritten(account: slot.account, fingerprint: fingerprint)
                return .empty
            }
            do {
                try slot.deleteItem()
            } catch let error as CredentialSlotError {
                return .deleteFailed(code: error.code)
            } catch {
                return .deleteFailed(code: CredentialKeychainStatus.itemNotFound)
            }
            do {
                try slot.writeSecret(secret)
            } catch let error as CredentialSlotError {
                return .writeFailed(code: error.code)
            } catch {
                return .writeFailed(code: CredentialKeychainStatus.duplicateItem)
            }
            ledger.markRewritten(account: slot.account, fingerprint: fingerprint)
            return .rewrote
        }
    }
}

/// 一条记录该不该动。
public enum CredentialReconcileDecision: Equatable {
    case missing
    case keep
    case rewrite
}
