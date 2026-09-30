import XCTest
@testable import DoyahCore

/// 队列 `L-65` 第 5 批（开发循环第 123 轮）：MySQL / GBase 驱动那八句话的**可达性**与
/// 「语言随调用方走」。
///
/// 门禁 `check-literal-language.py` 判的是**形状**（调用点写不写死语言、死译文销没销账、
/// 形参在不在）—— 「英文译文是不是真换了一句」只有真取值才知道。L-65 前四批每一族都配了
/// 同族断言，这一批不例外：**两种语言必须真的不同**，相同就说明语言又没跟着调用方走。
final class MySQLWordingTests: XCTestCase {

    private func pairs() -> [(String, String)] {
        [
            (MySQLWording.connectTimedOut(seconds: 30, language: .simplifiedChinese),
             MySQLWording.connectTimedOut(seconds: 30, language: .english)),
            (MySQLWording.hostResolveFailed(host: "db.example.com", detail: "nodename nor servname", language: .simplifiedChinese),
             MySQLWording.hostResolveFailed(host: "db.example.com", detail: "nodename nor servname", language: .english)),
            (MySQLWording.lastInsertID("7", language: .simplifiedChinese),
             MySQLWording.lastInsertID("7", language: .english)),
            (MySQLWording.statementTimeout(seconds: "5", language: .simplifiedChinese),
             MySQLWording.statementTimeout(seconds: "5", language: .english)),
            (MySQLWording.cancelNoConnectionID(language: .simplifiedChinese),
             MySQLWording.cancelNoConnectionID(language: .english)),
            (MySQLWording.cancelStatementMissing(language: .simplifiedChinese),
             MySQLWording.cancelStatementMissing(language: .english)),
            (MySQLWording.cancelDispatchFailed(detail: "connection refused", language: .simplifiedChinese),
             MySQLWording.cancelDispatchFailed(detail: "connection refused", language: .english)),
            (MySQLWording.copyUnsupported(language: .simplifiedChinese),
             MySQLWording.copyUnsupported(language: .english)),
        ]
    }

    /// 八句话逐句：两种语言都在、都非空、**必须不同**（相同 = 语言没跟着调用方走），
    /// 而且不等于键名（取值失败时会回键名 —— 那样界面会出现 `mysqlCopyUnsupported` 这种东西）。
    func testEverySentenceDiffersBetweenLanguages() {
        let list = pairs()
        XCTAssertEqual(list.count, 8, "八句话一句都不能少（漏一句就是一条死译文）")
        for (index, pair) in list.enumerated() {
            XCTAssertFalse(pair.0.isEmpty, "第 \(index + 1) 句的中文是空的")
            XCTAssertFalse(pair.1.isEmpty, "第 \(index + 1) 句的英文是空的")
            XCTAssertNotEqual(pair.0, pair.1, "第 \(index + 1) 句两种语言必须不同（否则英文译文不可达）")
            XCTAssertFalse(pair.0.hasPrefix("mysql"), "第 \(index + 1) 句回的是键名 —— 语言表没取到")
        }
    }

    /// 句子里必须带上**实际值**：主机名 / 底层原串 / 秒数 / 自增 ID 一处都不能丢
    /// （丢人的是「超时了」而不说多久 —— 那和报错不点库名是同一类）。
    func testSentencesCarryTheActualValues() {
        XCTAssertTrue(MySQLWording.hostResolveFailed(host: "db.example.com", detail: "boom", language: .english).contains("db.example.com"))
        XCTAssertTrue(MySQLWording.hostResolveFailed(host: "db.example.com", detail: "boom", language: .english).contains("boom"))
        XCTAssertTrue(MySQLWording.statementTimeout(seconds: "5", language: .english).contains("5"))
        XCTAssertTrue(MySQLWording.lastInsertID("42", language: .english).contains("42"))
        XCTAssertTrue(MySQLWording.cancelDispatchFailed(detail: "connection refused", language: .english).contains("connection refused"))
        XCTAssertTrue(MySQLWording.connectTimedOut(seconds: 30, language: .english).contains("30"))
    }

    /// 语言**随连接对象走**（同 `MCPServerSession.language` 的理由：这几句人话挂在**这一次连接**上，
    /// 由启动它的那个人决定）。创建时说英文，这个连接上那八句就是英文 ——
    /// 工厂那两个分支也必须把语言带下去（漏给语言 ⇒ 又退回「Core 自己选」）。
    func testConnectionAndFactoryCarryTheCallersLanguage() {
        let mysql = ConnectionConfig(
            name: "wording",
            dbType: .mysql,
            host: "127.0.0.1",
            port: 3306,
            database: "d",
            username: "u",
            sslMode: .disable
        )
        XCTAssertEqual(MySQLService(config: mysql, password: nil, language: .english).language, .english)
        let viaFactory = DatabaseServiceFactory.make(for: mysql, password: nil, language: .english)
        XCTAssertEqual((viaFactory as? MySQLService)?.language, .english)

        let gbase = ConnectionConfig(
            name: "wording-gbase",
            dbType: .gbase8a,
            host: "127.0.0.1",
            port: 5258,
            database: "d",
            username: "u",
            sslMode: .disable
        )
        let service = DatabaseServiceFactory.make(for: gbase, password: nil, language: .simplifiedChinese)
        XCTAssertTrue(service is GBaseService, "GBase 仍走委托给 MySQLService 的那条路")
    }

    /// 超时那一条走的是 `LocalizedError` **协议入口**（不带语言语境）：它只回 payload 里
    /// **已按调用方语言渲染好的整句**，不在这里选语言 —— 这是概要设计 §7 第 49 轮那条口径
    /// （「协议入口不许写死语言」）在 MySQL 侧的同一次落地。
    func testTimeoutErrorReturnsTheSentenceGivenByTheCaller() {
        let english = MySQLWording.connectTimedOut(seconds: 3, language: .english)
        let error = MySQLService.MySQLServiceError.timedOut(seconds: 3, message: english)
        XCTAssertEqual(error.errorDescription, english, "协议入口必须原样回 payload，不许自己再选语言")
        XCTAssertNotEqual(
            error.errorDescription,
            MySQLWording.connectTimedOut(seconds: 3, language: .simplifiedChinese)
        )
    }
}
