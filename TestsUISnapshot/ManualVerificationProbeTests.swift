import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「待人工验收清单」**B 类**（快照 / 探针可代劳）条目的机器判据 —— 队列 `L-89` ㈠（开发循环第 90 轮）。
///
/// ## 为什么需要它
///
/// 2026-09-29 需求提出者的原话：「昨晚手工测试发现太费劲了，结果本地智能体把 10 条测试自己跑了 8 条，
/// 你再检查一下很多测试条目是不是真的需要我手工点一下」。审计把 46 条「需要人工」拆开之后，
/// **B 类 13 条**被判定为「快照 / 探针可代劳」—— 本文件是这 13 条里的**第一批**。
///
/// ## 判据的形状（与「人工看一眼」的区别在哪）
///
/// 人在界面里点验时看的是「开关关掉之后，下面那几个字段**一个都不该出现**」这类
/// **状态 → 界面**的对应关系。本文件把同一件事折成**两态渲染的对照**：同一个视图在
/// 状态 A / 状态 B 各渲染一遍，断言某句文案**只在其中一遍**出现
/// （`UISnapshot.Record.localizedStrings` 记的就是那一遍 `L(...)` 实际取到的文案，
/// 正是「有没有到界面上」的证据）。于是这几条不再需要人到场。
///
/// ## 三条纪律（与 `UISnapshotKit` 同源）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 取证工具，不进每轮门禁；
/// · 断言落在**文案出现 / 不出现**上，不靠人读图（图另有 `check-ui-snapshot-languages.py` 守）；
/// · 不写用户数据：只构造内存里的配置，不连库、不落盘偏好。例外是沙箱那条要读**进程环境变量**（只读）。
///
/// ## 边界（如实登记，不乱承诺）
///
/// · 「PG 六项 / MySQL 五项、MySQL 下 `Verify Full` 显示成 `Verify Identity`」由
///   `Tests/SSLModeDialectTests` 7 项守（那是**下拉选项**，走 `SSLMode.displayName`，
///   不是 `L(...)`）；本文件守的是**收窄说明有没有到界面上**。
/// · 沙箱那一条的**环境依据**是 `APP_SANDBOX_CONTAINER_ID`（沙箱进程自带标记）——
///   探针进程本身跟着**跑它的 shell**：同一条用例在带 / 不带该变量的两次运行里各覆盖一面。
///   `Scripts/run-manual-verification-probes.sh` 就是照这个跑两遍的。
final class ManualVerificationProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针要渲染真视图树：DOYAH_UI_SNAPSHOT=1 才跑（与快照同一条纪律：取证才跑，门禁不跑）"
        )
    }

    /// 表单很长（十几个字段 + 隧道一段）：视口给足，免得 **Form 的懒加载**把下半截根本不构造 ——
    /// 那样「文案没出现」会是**假绿**（界面其实是对的，只是没建到那一行）。
    private let formSize = CGSize(width: 620, height: 1700)

    // MARK: - 装配

    @MainActor
    private func form(_ configuration: ConnectionConfig) -> ConnectionFormView {
        ConnectionFormView(
            configuration: configuration,
            existingConnections: [],
            storedPassword: { nil },
            onSave: { _, _, _ in }
        )
    }

    /// 普通连接（无隧道）。
    private var plainConfig: ConnectionConfig {
        ConnectionConfig(
            name: "本地库",
            dbType: .postgresql,
            port: 5432,
            database: "demo",
            username: "alex"
        )
    }

    /// 开了隧道的连接（表单里那一段该整段出现）。
    private var tunnelConfig: ConnectionConfig {
        ConnectionConfig(
            name: "跳板机库",
            dbType: .postgresql,
            port: 5432,
            database: "demo",
            username: "alex",
            sshTunnel: SSHTunnelConfig(
                isEnabled: true,
                host: "jump.example.com",
                port: 22,
                username: "alex",
                authentication: .agent,
                hostKeyPolicy: .acceptNew,
                connectTimeoutSeconds: 15
            )
        )
    }

    // MARK: - 断言工具

    /// 这一遍渲染里，`key` 按它的语言应当长成什么样（与渲染**同一条取值路径**）。
    @MainActor
    private func text(_ language: AppLanguage, _ key: LKey) -> String {
        UISnapshot.localizedText(language) { L(key) }
    }

    /// 「这些文案在**这两遍**（中 / 英）里都该 / 都不该出现」。
    @MainActor
    private func assertPresence(
        _ pair: UISnapshot.LanguagePair,
        side: String,
        keys: [LKey],
        shouldAppear: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for record in pair.records {
            let language = AppLanguage(rawValue: record.language) ?? .simplifiedChinese
            let observed = Set(record.localizedStrings)
            for key in keys {
                let expected = text(language, key)
                let found = observed.contains(expected)
                XCTAssertEqual(
                    found,
                    shouldAppear,
                    "\(side)·\(language.rawValue)：文案「\(expected)」\(shouldAppear ? "应当出现" : "不该出现")，"
                        + "实际\(found ? "出现了" : "没出现")（快照 \(record.name)）",
                    file: file,
                    line: line
                )
            }
        }
    }

    // MARK: - ① FR-CONN-18 界面：隧道一段的字段显隐

    @MainActor
    func testTunnelSectionFieldsFollowTheSwitch() throws {
        let off = try UISnapshot.writeBothLanguages("manual-check-tunnel-off", size: formSize) {
            form(plainConfig)
        }
        let on = try UISnapshot.writeBothLanguages("manual-check-tunnel-on", size: formSize) {
            form(tunnelConfig)
        }

        // ① 开关本身**两态都在**（它是显隐的把手，不能跟着一起消失）。
        assertPresence(off, side: "隧道关", keys: [.sshEnableLabel], shouldAppear: true)
        assertPresence(on, side: "隧道开", keys: [.sshEnableLabel], shouldAppear: true)

        // ② 关掉时：隧道那一段的文案**一个都不该出现**（需求原话：「关掉时一个都不显示」）。
        let fieldKeys: [LKey] = [
            .sshSectionSubtitle, .sshHostLabel, .sshPortLabel, .sshUserLabel,
            .sshAuthLabel, .sshHostKeyLabel,
        ]
        assertPresence(off, side: "隧道关", keys: fieldKeys, shouldAppear: false)
        assertPresence(off, side: "隧道关·测试按钮", keys: [.sshTestButton], shouldAppear: false)

        // ③ 打开时：同一批文案**都在**（含「测试隧道」按钮）。
        assertPresence(on, side: "隧道开", keys: fieldKeys, shouldAppear: true)
        assertPresence(on, side: "隧道开·测试按钮", keys: [.sshTestButton], shouldAppear: true)

        // ④ 两态不能只是"图不一样"：文案集必须真的不同 —— 否则②③断言的是同一件事的两种假绿。
        XCTAssertNotEqual(
            Set(off.records[0].localizedStrings),
            Set(on.records[0].localizedStrings),
            "隧道关 / 开两遍的文案集相同 ⇒ 显隐这件事根本没到界面上"
        )
    }

    // MARK: - ② R-53 界面：SSL 模式按方言收窄（不静默改）

    /// 老配置 / 手改文件里可能存着该方言不支持的模式（典型：MySQL 上存着 PG 专属的 `allow`）。
    @MainActor
    func testSSLModeNarrowingReachesTheInterface() throws {
        let mysqlOld = ConnectionConfig(
            name: "老 MySQL 配置", dbType: .mysql, port: 3306, database: "dsh", username: "root",
            sslMode: .allow
        )
        let pgOld = ConnectionConfig(
            name: "老 PG 配置", dbType: .postgresql, port: 5432, database: "dsh", username: "alex",
            sslMode: .allow
        )
        let mysqlNormal = ConnectionConfig(
            name: "MySQL 新配置", dbType: .mysql, port: 3306, database: "dsh", username: "root",
            sslMode: .prefer
        )

        let narrowed = try UISnapshot.writeBothLanguages("manual-check-ssl-mysql-allow", size: formSize) {
            form(mysqlOld)
        }
        let pgAllow = try UISnapshot.writeBothLanguages("manual-check-ssl-pg-allow", size: formSize) {
            form(pgOld)
        }
        let mysqlPrefer = try UISnapshot.writeBothLanguages("manual-check-ssl-mysql-prefer", size: formSize) {
            form(mysqlNormal)
        }

        for record in narrowed.records {
            let language = AppLanguage(rawValue: record.language) ?? .simplifiedChinese
            // 收窄说明的期望值：**存的是 allow、落到了 MySQL 的默认 prefer**（两句都按方言取名）。
            let expected = UISnapshot.localizedText(language) {
                L(.connectionFormSSLModeAdjusted, SSLMode.allow.displayName, SSLMode.prefer.displayName(for: .mysql))
            }
            XCTAssertTrue(
                record.localizedStrings.contains(expected),
                "MySQL + 老配置 allow：界面上应当出现收窄说明「\(expected)」（实际文案集里没有）"
            )
        }

        // PG 支持 allow ⇒ 既不该有收窄说明，也不该有「MySQL 系没有 Allow」那句小字。
        let adjustedTexts = narrowed.records.map { rec -> String in
            let language = AppLanguage(rawValue: rec.language) ?? .simplifiedChinese
            return UISnapshot.localizedText(language) {
                L(.connectionFormSSLModeAdjusted, SSLMode.allow.displayName, SSLMode.prefer.displayName(for: .postgresql))
            }
        }
        for (record, unexpected) in zip(pgAllow.records, adjustedTexts) {
            XCTAssertFalse(
                record.localizedStrings.contains(unexpected),
                "PG 自己支持 allow ⇒ 不该出现收窄说明（快照 \(record.name)）"
            )
        }
        assertPresence(pgAllow, side: "PG + allow", keys: [.connectionFormSSLModeNarrowed], shouldAppear: false)

        // MySQL 正常档位：没有收窄说明，但有「只列它实际支持的几档」那句小字。
        assertPresence(mysqlPrefer, side: "MySQL + prefer", keys: [.connectionFormSSLModeNarrowed], shouldAppear: true)
        let preferAdjusted = mysqlPrefer.records.map { rec -> String in
            let language = AppLanguage(rawValue: rec.language) ?? .simplifiedChinese
            return UISnapshot.localizedText(language) {
                L(.connectionFormSSLModeAdjusted, SSLMode.allow.displayName, SSLMode.prefer.displayName(for: .mysql))
            }
        }
        for (record, unexpected) in zip(mysqlPrefer.records, preferAdjusted) {
            XCTAssertFalse(
                record.localizedStrings.contains(unexpected),
                "没被收窄（本来就存 prefer）⇒ 不该出现收窄说明（快照 \(record.name)）"
            )
        }

        // 三态的文案集两两不同 —— 否则上面那几条断言可能只是在比同一张图。
        XCTAssertNotEqual(
            Set(narrowed.records[0].localizedStrings),
            Set(mysqlPrefer.records[0].localizedStrings),
            "收窄态与正常态的文案集相同 ⇒ 收窄没收窄看不出来"
        )
        XCTAssertNotEqual(
            Set(narrowed.records[0].localizedStrings),
            Set(pgAllow.records[0].localizedStrings),
            "MySQL 收窄态与 PG 正常态的文案集相同 ⇒ 方言差异没到界面上"
        )
    }

    // MARK: - ③ FR-CONN-18 沙箱告知（环境依据：APP_SANDBOX_CONTAINER_ID）

    @MainActor
    func testSandboxNoticeFollowsTheBuildEnvironment() throws {
        let pair = try UISnapshot.writeBothLanguages("manual-check-ssh-sandbox-notice", size: formSize) {
            form(tunnelConfig)
        }

        let mark = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
        let side = mark == nil ? "普通构建（无沙箱标记）" : "沙箱构建（标记 \(mark!)）"

        // 两面都要判：带标记 ⇒ 该说明必须在；不带 ⇒ 必须不在。
        assertPresence(pair, side: "沙箱告知·\(side)", keys: [.sshSandboxNotice], shouldAppear: mark != nil)

        // 顺带把「隧道按钮与说明在同一态下都在」钉住：沙箱那一遍不该因为多了一行而少半段。
        assertPresence(pair, side: "沙箱告知·\(side)", keys: [.sshEnableLabel, .sshTestButton], shouldAppear: true)

        print("🧪 沙箱告知这一遍跑的是：\(side)（另一面由带 / 不带 APP_SANDBOX_CONTAINER_ID 的另一次运行覆盖）")
    }

    override class func tearDown() {
        UISnapshot.finishManifestIfEnabled()
        super.tearDown()
    }
}
