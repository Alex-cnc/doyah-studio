import Foundation
import Security

import DoyahCore

/// 钥匙串条目的**访问控制装配**（★00：主人 2026-10-29「每次启动都要输入密码」）。
///
/// 为什么要显式装配 ACL，而不是「让系统自己决定」：不显式给 ACL 时，系统把**创建它的那个应用**
/// 隐式写进条目的信任列表，而「应用」是按**代码签名**认的 —— 身份一变（重建 / 换证书 / 回退 ad-hoc），
/// 读这条记录就要求授权，于是每次启动弹一次「请输入钥匙串密码」。
/// 显式给 ACL 时，信任列表里写的是**当前这个应用**（`SecTrustedApplicationCreateFromPath(nil)` =
/// 正在运行的这个进程），并且随 `CredentialRewriteLedger` 在签名换代后重写一次。
///
/// 两条实测边界（2026-10-29 本机探针，见 `.agent/evidence/2026-10-29-keychain-prompt.md`）：
///   · `SecTrustedApplicationCreateFromPath(nil, …)` 与 `SecAccessCreate` 都返回 `errSecSuccess`，
///     带 `kSecAttrAccess` 的 `SecItemAdd` 也成功、读回成功 ⇒ 这条装配路是通的；
///   · 登录钥匙串**吞掉** `kSecAttrAccessible`（回读为 `nil`）⇒ 那个属性今天不产生行为差别，
///     只是「换到数据保护钥匙串那天已经带上」。
public enum KeychainItemAccess {

    /// 当前应用的 `SecAccess`（懒建一次；建不出来就是 `nil`，此时不加该属性 ——
    /// 加一个 `nil` 会让 `SecItemAdd` 报 `errSecParam`，比不写 ACL 更糟）。
    private static let applicationAccess: SecAccess? = makeApplicationAccess()

    private static func makeApplicationAccess() -> SecAccess? {
        guard CredentialStoragePolicy.bindsCurrentApplication else { return nil }
        var trusted: SecTrustedApplication?
        // nil = **正在运行的这个进程**（不是「任何应用」—— 用 `-A` 那种「任何应用可读」是反方向）。
        guard SecTrustedApplicationCreateFromPath(nil, &trusted) == errSecSuccess,
              let trusted else { return nil }
        var access: SecAccess?
        guard SecAccessCreate(DoyahIdentity.bundleIdentifier as CFString, [trusted] as CFArray, &access) == errSecSuccess
        else { return nil }
        return access
    }

    /// 新建条目时要带上的属性（`kSecAttrAccessible` + 显式 ACL）。
    public static func addAttributes() -> [String: Any] {
        var attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let applicationAccess {
            attributes[kSecAttrAccess as String] = applicationAccess
        }
        return attributes
    }

    /// 组装 `SecItemAdd` 的完整查询：基础键 + 载荷 + 本文件的属性口径。**唯一写入口**。
    public static func addQuery(base: [String: Any], data: Data) -> [String: Any] {
        var query = base
        query[kSecValueData as String] = data
        for (key, value) in addAttributes() {
            query[key] = value
        }
        return query
    }
}

/// 当前可执行体的**代码签名身份**（账本的「这套签名」）。
///
/// 取**指定要求串（designated requirement）**，而不是代码目录哈希（cdhash）：
/// 钥匙串 ACL 匹配用的就是 DR —— 同一张证书下重建，cdhash 变了但 DR 不变，ACL 仍然对得上。
/// 拿 cdhash 当键会「每重建一次就重写一遍条目」，而重写要读旧条目 ⇒ 每次重建白弹一次。
/// DR 取不到（未签名 / 自签缺 OID）时退回 cdhash，再取不到给空串（仍算一套，照样走一次核对）。
public enum CodeSignatureFingerprint {

    public static func current() -> String {
        let path = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
        guard !path.isEmpty else { return "" }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return "" }
        if let requirement = designatedRequirement(of: staticCode) { return requirement }
        return signingInformationFingerprint(of: staticCode)
    }

    private static func designatedRequirement(of code: SecStaticCode) -> String? {
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else { return nil }
        let value = text as String
        return value.isEmpty ? nil : value
    }

    private static func signingInformationFingerprint(of code: SecStaticCode) -> String {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let data = dictionary[kSecCodeInfoUnique as String] as? Data,
              !data.isEmpty else { return "" }
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

/// 一条真实钥匙串记录（`kSecClassGenericPassword`：service + account）。
///
/// 与三个既有的 store（`KeychainSecretStore` / `KeychainAgentKeyStore` /
/// `KeychainAgentIMSecretStore` / `KeychainNoteSyncTokenStore`）**同一条记录**，
/// 只是这里只做「核对与重写」这一件事，业务读写仍走各自的 store —— 不另起一套键。
public struct KeychainCredentialSlot: CredentialItemSlot {
    public let service: String
    public let account: String
    public let label: String

    public init(service: String, account: String, label: String) {
        self.service = service
        self.account = account
        self.label = label
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// 只读属性判断（**不带** `kSecReturnData`：那一步才会触发授权框）。
    public func exists() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func readSecret() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialSlotError(code: status) }
        guard let data = result as? Data else {
            throw CredentialSlotError(code: errSecInternalError)
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteItem() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialSlotError(code: status)
        }
    }

    public func writeSecret(_ secret: String) throws {
        try write(Data(secret.utf8))
    }

    private func write(_ data: Data) throws {
        let status = SecItemAdd(KeychainItemAccess.addQuery(base: baseQuery, data: data) as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 正常路已经先删再写；走到这里说明 delete 与实际状态不一致（并发写 / 上次半成功）。
            // 再删一次重试一遍，仍失败就如实把码交出去，不假装成功。
            let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw CredentialSlotError(code: deleteStatus)
            }
            let retryStatus = SecItemAdd(KeychainItemAccess.addQuery(base: baseQuery, data: data) as CFDictionary, nil)
            guard retryStatus == errSecSuccess else { throw CredentialSlotError(code: retryStatus) }
            return
        }
        guard status == errSecSuccess else { throw CredentialSlotError(code: status) }
    }
}

/// 把「本机所有凭据条目」列成待核对的槽位（**一处列全**，不许漏族 —— 漏了哪一族就哪一族继续弹）。
public enum KeychainCredentialSlots {

    /// - Parameters:
    ///   - connectionIDs: 现有连接的口令条目（每条一个 account = 连接 id）。
    ///   - connectionLabel: 连接名字（只用于报告里说人话）。
    public static func standard(
        connectionIDs: [UUID],
        connectionLabel: (UUID) -> String,
        service: String = DoyahIdentity.keychainServiceName
    ) -> [KeychainCredentialSlot] {
        var slots: [KeychainCredentialSlot] = connectionIDs.map { id in
            KeychainCredentialSlot(
                service: service,
                account: id.uuidString,
                label: connectionLabel(id)
            )
        }
        slots.append(
            KeychainCredentialSlot(
                service: service,
                account: KeychainAgentKeyStore.defaultAccount,
                label: "模型 API Key"
            )
        )
        for kind in AgentIMChannelCredentialKind.allCases {
            slots.append(
                KeychainCredentialSlot(
                    service: service,
                    account: kind.secretAccount,
                    label: "IM 通道 Secret（\(kind.rawValue)）"
                )
            )
        }
        slots.append(
            KeychainCredentialSlot(
                service: service,
                account: KeychainNoteSyncTokenStore.defaultAccount,
                label: "账号会话令牌"
            )
        )
        return slots
    }
}

/// 跑一次核对并把账本落盘（应用启动时调一次；幂等）。
///
/// 为什么落盘：不落盘的话每次启动都以为「没重写过」⇒ 每次启动都去读一遍旧条目 ⇒
/// 每次都弹 —— 那正是主人报的症状，治它靠的是**记账**，不是更努力地读写。
public enum KeychainCredentialReconciler {

    public static func ledgerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(CredentialRewriteLedgerFile.fileName, isDirectory: false)
    }

    /// - Returns: 报告（`summaryLine()` 一行读数）+ 新账本。
    @discardableResult
    public static func run(
        connectionIDs: [UUID],
        connectionLabel: (UUID) -> String,
        service: String = DoyahIdentity.keychainServiceName,
        ledgerURL: URL? = nil
    ) -> CredentialReconcileReport {
        let slots = KeychainCredentialSlots.standard(
            connectionIDs: connectionIDs,
            connectionLabel: connectionLabel,
            service: service
        )
        return run(slots: slots, ledgerURL: ledgerURL)
    }

    @discardableResult
    public static func run(slots: [any CredentialItemSlot], ledgerURL: URL? = nil) -> CredentialReconcileReport {
        let url = ledgerURL ?? Self.ledgerURL()
        let ledger = (try? Data(contentsOf: url)).map(CredentialRewriteLedger.decode) ?? CredentialRewriteLedger()
        let result = CredentialReconciler.reconcile(
            slots: slots,
            fingerprint: CodeSignatureFingerprint.current(),
            ledger: ledger
        )
        // 账本只在有进展时写：没有进展（全 kept / missing）就不碰盘，少一次无谓的文件改动。
        if result.ledger != ledger, !result.ledger.encoded().isEmpty {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? result.ledger.encoded().write(to: url, options: .atomic)
        }
        return result.report
    }
}
