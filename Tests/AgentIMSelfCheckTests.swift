import XCTest
@testable import DoyahCore

/// IM 自检的机械判据：**问题清单要有顺序**（先修哪个写在最前），齐全时一条都不许多。
final class AgentIMSelfCheckTests: XCTestCase {

    private func facts(appID: String = "1029384756", hasSecret: Bool = true,
                       environment: AgentIMQQEnvironment? = .production,
                       receiveTasks: Bool = true, configFileExists: Bool = true) -> AgentIMSelfCheckFacts {
        AgentIMSelfCheckFacts(appID: appID, hasSecret: hasSecret, environment: environment,
                              receiveTasks: receiveTasks, configFileExists: configFileExists)
    }

    func testReadyWhenEverythingIsThere() {
        XCTAssertTrue(AgentIMSelfCheck.isReady(facts()))
        XCTAssertEqual(AgentIMSelfCheck.problems(facts()), [])
    }

    func testConfigMissingComesFirst() {
        let problems = AgentIMSelfCheck.problems(facts(hasSecret: false, configFileExists: false))
        XCTAssertEqual(problems.first, .configFileMissing, "配置没落盘时先修它，别先补字段")
    }

    func testMissingSecretIsReported() {
        XCTAssertEqual(AgentIMSelfCheck.problems(facts(hasSecret: false)), [.secretMissing])
        XCTAssertFalse(AgentIMSelfCheck.isReady(facts(hasSecret: false)))
    }

    func testNonNumericAppIDIsReported() {
        XCTAssertEqual(AgentIMSelfCheck.problems(facts(appID: "10293847x")), [.appIDNotNumeric])
        XCTAssertEqual(AgentIMSelfCheck.problems(facts(appID: "  ")), [.appIDMissing])
    }

    func testMissingEnvironmentIsReported() {
        XCTAssertEqual(AgentIMSelfCheck.problems(facts(environment: nil)), [.environmentMissing])
    }

    func testReceiveTasksOffIsNotAProblem() {
        XCTAssertTrue(AgentIMSelfCheck.isReady(facts(receiveTasks: false)), "不收任务是选择，不是缺陷")
    }
}
