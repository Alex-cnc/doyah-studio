import XCTest
@testable import DoyahCore

/// 钥匙串条目核对（★00：主人 2026-10-29 当面点出「每次启动都要输入密码」）的**判定层**判据。
///
/// 这一层能机械判的是「**这一条该不该重写、重写时按什么顺序、账本怎么前进**」；
/// 「启动到底还弹不弹」只能主人点一次（实现列因此留 🟡）。
///
/// 反例（各判红一次，见 `.agent/evidence/2026-10-29-keychain-prompt.md`）：
/// ① `needsRewrite` 恒回 false（账本记过就永不再看）⇒ 签名变了那 2 例红（换了身份却照旧弹）；
/// ② `reconcile` 把「先读」挪到「先删」之后 ⇒ 读失败那 2 例红（凭据当场丢）；
/// ③ 失败也记账 ⇒ 3 例红（治不好的凭据从此静默地永远弹窗）。
final class CredentialItemReconciliationTests: XCTestCase {

    // MARK: - 替身

    /// 按脚本回放的一条记录：调用序列全记下来，判据就判「做了什么、按什么顺序」。
    private final class FakeSlot: CredentialItemSlot {
        enum Call: Equatable {
            case exists, read, delete, write(String)
        }

        let label: String
        let account: String
        var present: Bool
        var secret: String?
        var readError: CredentialSlotError?
        var deleteError: CredentialSlotError?
        var writeError: CredentialSlotError?
        var calls: [Call] = []

        init(
            label: String,
            account: String? = nil,
            present: Bool = true,
            secret: String? = "s3cret",
            readError: CredentialSlotError? = nil,
            deleteError: CredentialSlotError? = nil,
            writeError: CredentialSlotError? = nil
        ) {
            self.label = label
            self.account = account ?? label
            self.present = present
            self.secret = secret
            self.readError = readError
            self.deleteError = deleteError
            self.writeError = writeError
        }

        func exists() -> Bool {
            calls.append(.exists)
            return present
        }

        func readSecret() throws -> String? {
            calls.append(.read)
            if let readError { throw readError }
            return secret
        }

        func deleteItem() throws {
            calls.append(.delete)
            if let deleteError { throw deleteError }
        }

        func writeSecret(_ secret: String) throws {
            calls.append(.write(secret))
            if let writeError { throw writeError }
        }
    }

    private let sigA = "cdhash-AAAA"
    private let sigB = "cdhash-BBBB"

    // MARK: - ① 账本为空 ⇒ 按当前签名重写一遍（这就是治「每次启动弹」的那一步）

    func testEmptyLedgerRewritesExistingItemInReadDeleteWriteOrder() {
        let slot = FakeSlot(label: "模型 API Key")
        var ledger = CredentialRewriteLedger()
        let outcome = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(outcome, .rewrote)
        XCTAssertEqual(slot.calls, [.exists, .read, .delete, .write("s3cret")],
                       "顺序写死：先读、再删、最后按当前签名写回 —— 反过来就是先毁后读")
        XCTAssertEqual(ledger.accounts, ["模型 API Key"])
        XCTAssertEqual(ledger.signatureFingerprint, sigA)
    }

    func testMissingItemIsSkippedAndNotRecorded() {
        let slot = FakeSlot(label: "IM Secret", present: false)
        var ledger = CredentialRewriteLedger()
        let outcome = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(outcome, .missing)
        XCTAssertEqual(slot.calls, [.exists], "没有这条就别读内容、更别凭空造一条空记录")
        XCTAssertTrue(ledger.accounts.isEmpty, "不存在的条目不该记账（以后真存了还得核一次）")
    }

    // MARK: - ② 同一套签名只重写一次（不许每次启动都读写一遍）

    func testSameSignatureRewritesOnlyOnce() {
        let slot = FakeSlot(label: "连接口令")
        var ledger = CredentialRewriteLedger()
        _ = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)

        slot.calls.removeAll()
        let second = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(second, .kept)
        XCTAssertEqual(slot.calls, [.exists],
                       "已经按这套签名重写过的条目，连内容都不许读 —— 读正是会弹授权的那一下")
    }

    func testSignatureChangeForcesOneMoreRewriteAndResetsLedger() {
        var ledger = CredentialRewriteLedger()
        let first = FakeSlot(label: "连接口令")
        _ = CredentialReconciler.reconcile(first, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(ledger.accounts, ["连接口令"])

        let again = FakeSlot(label: "连接口令")
        let outcome = CredentialReconciler.reconcile(again, fingerprint: sigB, ledger: &ledger)
        XCTAssertEqual(outcome, .rewrote, "换了签名就等于换了一个「应用」⇒ 必须重写，否则照旧弹窗")
        XCTAssertEqual(again.calls, [.exists, .read, .delete, .write("s3cret")])
        XCTAssertEqual(ledger.signatureFingerprint, sigB)
    }

    // MARK: - ③ 读不出来绝不删（「丢凭据」的唯一闸门）

    func testReadFailureNeverDeletesAndDoesNotAdvanceLedger() {
        let slot = FakeSlot(label: "连接口令",
                            readError: CredentialSlotError(code: CredentialKeychainStatus.authFailed))
        var ledger = CredentialRewriteLedger()
        let outcome = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(outcome, .readFailed(code: CredentialKeychainStatus.authFailed))
        XCTAssertEqual(slot.calls, [.exists, .read], "读失败之后一次删除都不许发生：删了就再也读不回来了")
        XCTAssertTrue(ledger.accounts.isEmpty, "失败不许记账 —— 下次启动还得再试一次")
    }

    func testEmptySecretIsRecordedButNotRewritten() {
        let slot = FakeSlot(label: "空条目", secret: "")
        var ledger = CredentialRewriteLedger()
        let outcome = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(outcome, .empty)
        XCTAssertEqual(slot.calls, [.exists, .read], "内容是空的：没有东西要保，也不该重写一条空记录")
        XCTAssertEqual(ledger.accounts, ["空条目"], "空条目也要记账，否则每次启动都去读它（可能每次都弹）")
    }

    // MARK: - ④ 失败不许装成完成

    func testDeleteFailureSkipsTheWriteAndIsNotRecorded() {
        let slot = FakeSlot(label: "连接口令",
                            deleteError: CredentialSlotError(code: CredentialKeychainStatus.authFailed))
        var ledger = CredentialRewriteLedger()
        let outcome = CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &ledger)
        XCTAssertEqual(outcome, .deleteFailed(code: CredentialKeychainStatus.authFailed))
        XCTAssertEqual(slot.calls, [.exists, .read, .delete],
                       "删不掉就别写：同一 (service, account) 上再 Add 只会报 errSecDuplicateItem")
        XCTAssertTrue(ledger.accounts.isEmpty)
    }

    func testWriteFailureIsNotCountedAsRewritten() {
        let slot = FakeSlot(label: "连接口令",
                            writeError: CredentialSlotError(code: CredentialKeychainStatus.duplicateItem))
        var ledger = CredentialRewriteLedger()
        let result = CredentialReconciler.reconcile(slots: [slot], fingerprint: sigA, ledger: ledger)
        ledger = result.ledger
        XCTAssertEqual(result.report.count(.rewrote), 0, "写失败不许计入「已重写」")
        XCTAssertEqual(result.report.count(where: { if case .writeFailed = $0 { return true } else { return false } }), 1)
        XCTAssertEqual(result.report.problems.count, 1, "治不好的那几条必须出现在 problems 里，不许静默")
        XCTAssertTrue(ledger.accounts.isEmpty, "写失败不记账")
    }

    // MARK: - ⑤ 多条：一条失败不拖累其余，读数只认报告

    func testOneFailureDoesNotStopTheRest() {
        let slots: [FakeSlot] = [
            FakeSlot(label: "连接口令"),
            FakeSlot(label: "模型 API Key", readError: CredentialSlotError(code: CredentialKeychainStatus.authFailed)),
            FakeSlot(label: "IM Secret"),
            FakeSlot(label: "会话令牌", present: false),
        ]
        let result = CredentialReconciler.reconcile(slots: slots, fingerprint: sigA, ledger: CredentialRewriteLedger())
        XCTAssertEqual(result.report.entries.map(\.label), ["连接口令", "模型 API Key", "IM Secret", "会话令牌"],
                       "顺序与输入一致（面板 / 日志按这个顺序读）")
        XCTAssertEqual(result.report.entries.map(\.outcome), [
            .rewrote,
            .readFailed(code: CredentialKeychainStatus.authFailed),
            .rewrote,
            .missing,
        ])
        XCTAssertEqual(result.ledger.accounts, ["连接口令", "IM Secret"], "记账只记成功的那几条")
    }

    func testSummaryLineIsDeterministicAndCountsEveryBucket() {
        let make: () -> [FakeSlot] = {
            [FakeSlot(label: "a"), FakeSlot(label: "b", present: false)]
        }
        let first = CredentialReconciler.reconcile(slots: make(), fingerprint: self.sigA, ledger: CredentialRewriteLedger())
        let second = CredentialReconciler.reconcile(slots: make(), fingerprint: self.sigA, ledger: CredentialRewriteLedger())
        XCTAssertEqual(first.report.summaryLine(), second.report.summaryLine(),
                       "同一份输入两遍必须逐字相同（不带时间戳、不带指针地址）")

        // 第二轮：账本已前进 ⇒ 同一批条目变成「已可用」
        let third = CredentialReconciler.reconcile(slots: make(), fingerprint: sigA, ledger: first.ledger)
        XCTAssertTrue(third.report.summaryLine().contains("已可用 1"), third.report.summaryLine())
        XCTAssertTrue(third.report.summaryLine().contains("本次按当前签名重写 0"), third.report.summaryLine())
        XCTAssertTrue(third.report.summaryLine().contains("读不出来 / 写不进去 0 条"), third.report.summaryLine())
    }

    // MARK: - ⑥ 账本本身：能存能读、坏了要往安全侧落

    func testLedgerRoundTripsAndIsByteStable() {
        var ledger = CredentialRewriteLedger()
        ledger.markRewritten(account: "b", fingerprint: sigA)
        ledger.markRewritten(account: "a", fingerprint: sigA)
        let first = ledger.encoded()
        let second = ledger.encoded()
        XCTAssertEqual(first, second, "同一份账本两遍必须逐字节相同（键序固定）")
        XCTAssertEqual(CredentialRewriteLedger.decode(first), ledger)
    }

    func testCorruptLedgerFallsBackToEmptyWhichRewritesOnceMore() {
        let corrupt = Data("{ this is not json".utf8)
        let ledger = CredentialRewriteLedger.decode(corrupt)
        XCTAssertEqual(ledger, CredentialRewriteLedger(), "解不出来就回落成空账本：最坏多弹一次，而不是崩或整段跳过")
        let slot = FakeSlot(label: "连接口令")
        var mutable = ledger
        XCTAssertEqual(CredentialReconciler.reconcile(slot, fingerprint: sigA, ledger: &mutable), .rewrote)
    }

    func testMarkRewrittenResetsAccountsWhenSignatureChanges() {
        var ledger = CredentialRewriteLedger()
        ledger.markRewritten(account: "a", fingerprint: sigA)
        ledger.markRewritten(account: "b", fingerprint: sigA)
        ledger.markRewritten(account: "c", fingerprint: sigB)
        XCTAssertEqual(ledger.accounts, ["c"], "旧签名下的记录对新签名没有意义")
        XCTAssertEqual(ledger.signatureFingerprint, sigB)
    }

    // MARK: - ⑦ 政策与状态码：钉住实测取值，不许漂

    func testStoragePolicyPinsMeasuredValues() {
        XCTAssertEqual(CredentialStoragePolicy.requiredAccessibilityRawValue, "cku",
                       "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly 的原始值，实测打印为 cku")
        XCTAssertTrue(CredentialStoragePolicy.bindsCurrentApplication,
                      "必须显式把当前应用写进 ACL：不写就由系统按「谁建的」隐式决定，签名一换就弹")
        XCTAssertFalse(CredentialStoragePolicy.migratesWithBackup, "凭据不许随备份迁到别的机器")
        XCTAssertEqual(CredentialKeychainStatus.itemNotFound, -25300)
        XCTAssertEqual(CredentialKeychainStatus.interactionNotAllowed, -25308)
        XCTAssertEqual(CredentialKeychainStatus.missingEntitlement, -34018)
    }

    func testDecisionTable() {
        XCTAssertEqual(CredentialReconciler.decide(exists: false, needsRewrite: true), .missing)
        XCTAssertEqual(CredentialReconciler.decide(exists: true, needsRewrite: false), .keep)
        XCTAssertEqual(CredentialReconciler.decide(exists: true, needsRewrite: true), .rewrite)
    }
}
