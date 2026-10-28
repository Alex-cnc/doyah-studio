import XCTest
@testable import DoyahCore

/// 高危任务执行前的**逐条**审批（`FR-STD-DB-TASK-002`）。
///
/// 需求三条判据在这里各自成组：
/// ① 审批框**逐条**列出每条语句与目标库（拆句 / 序号 / 类别 / 目标库 / 各自影响面）；
/// ② **未确认不发送任何语句**（批准才整批交出，拒绝交出一张空表 —— 结构性保证，不是约定）；
/// ③ 拒绝后状态是「已拒绝」且能在历史里看到（`TaskRunRecord.Status.rejected` 与 `skipped` 分开）。
///
/// 反例成对：这批用例直接对着「拆分 / 决策 / 影响面」三处取值断言 —— 把任一处改坏
/// （例如拒绝时也交出语句、把 `pending` 当 `rows(0)`、拆句改成按空白切）都会立刻红。
final class HighRiskTaskApprovalTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ① 逐条列出

    /// 三条语句 ⇒ 三行，序号 1 起、类别取首词 —— 这就是「逐条列出」的最小形状。
    func testSplitsEveryStatementWithOwnIndexAndKind() throws {
        let sql = """
        TRUNCATE TABLE public.orders_archive;
        INSERT INTO public.orders_archive SELECT * FROM public.orders;
        UPDATE public.orders_archive SET note = 'x' WHERE id = 1;
        """

        let plan = try HighRiskTaskApproval.plan(sql: sql, targetDatabase: "shop")

        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.statements.map(\.index), [1, 2, 3], "序号必须 1 起且连续")
        XCTAssertEqual(plan.statements.map(\.kind), ["TRUNCATE", "INSERT", "UPDATE"])
        XCTAssertTrue(plan.statements.allSatisfy { !$0.sql.isEmpty })
    }

    /// 每条语句都自带目标库：拆开的行不许出现「只有第一行有库名、其余空着」。
    func testEveryLineCarriesTheTargetDatabase() throws {
        let plan = try HighRiskTaskApproval.plan(
            sql: "DELETE FROM t1; DELETE FROM t2;",
            targetDatabase: "shop"
        )

        XCTAssertEqual(plan.targetDatabase, "shop")
        XCTAssertEqual(plan.statements.map(\.targetDatabase), ["shop", "shop"])
    }

    /// 没有目标库时**如实留空**（界面写「未指定」），不许编一个库名出来。
    func testMissingTargetDatabaseStaysNilInsteadOfBeingInvented() throws {
        let plan = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1;", targetDatabase: "   ")

        XCTAssertNil(plan.targetDatabase)
        XCTAssertNil(plan.statements.first?.targetDatabase)
    }

    /// 空脚本 ⇒ 拒绝建单（`noStatements`）：不许造一张没有内容的审批单糊弄人。
    func testEmptyScriptIsRefused() {
        for sql in ["", "   \n ", ";;  ;"] {
            XCTAssertThrowsError(try HighRiskTaskApproval.plan(sql: sql, targetDatabase: "shop")) { error in
                XCTAssertEqual(error as? HighRiskTaskApproval.PlanError, .noStatements)
            }
        }
    }

    /// 直接喂语句列表时，空白那一条要点名是第几条（不静默丢掉 —— 丢掉就等于少审一条）。
    func testBlankStatementInListIsRefusedWithItsIndex() {
        XCTAssertThrowsError(
            try HighRiskTaskApproval.plan(statements: ["DELETE FROM t1;", "  "], targetDatabase: "shop")
        ) { error in
            XCTAssertEqual(error as? HighRiskTaskApproval.PlanError, .blankStatement(index: 2))
        }
    }

    /// 认不出首词（只有注释 / 只有符号）⇒ `OTHER`，不猜成某个 DML 类别。
    func testKindFallsBackToOtherWhenTheFirstWordIsNotAKeyword() {
        XCTAssertEqual(HighRiskTaskApproval.kind(of: "-- 只是注释\n"), "OTHER")
        XCTAssertEqual(HighRiskTaskApproval.kind(of: "::"), "OTHER")
        XCTAssertEqual(HighRiskTaskApproval.kind(of: "insert into t values (1);"), "INSERT")
        XCTAssertEqual(HighRiskTaskApproval.kind(of: "  delete from t;"), "DELETE")
    }

    /// 数据任务「覆盖写入」编译出来的正是两条语句 —— 端到端钉住「要审的到底有哪些条」。
    func testOverwriteTaskProducesTwoListableStatements() throws {
        let task = DataTaskDefinition(
            name: "订单归档",
            specs: "把订单搬进归档表，用覆盖方式。",
            source: .init(schema: "public", table: "orders", columns: ["id", "total"]),
            target: .init(schema: "public", table: "orders_archive", writeMode: .overwrite),
            schedule: .manual,
            createdAt: epoch,
            updatedAt: epoch
        )

        let statements = try DataTaskRunner.writeStatements(for: task)
        let plan = try HighRiskTaskApproval.plan(statements: statements, targetDatabase: "shop")

        XCTAssertEqual(plan.count, 2, "覆盖写入 = TRUNCATE + INSERT，两条都要被审")
        XCTAssertEqual(plan.statements.map(\.kind), ["TRUNCATE", "INSERT"])
        XCTAssertEqual(plan.statements.map(\.index), [1, 2])
    }

    // MARK: - ② 未确认不发送任何语句

    /// 批准 ⇒ **整批**按原顺序交出（不是只交第一条、也不是重排）。
    func testApproveSendsTheWholeBatchInOriginalOrder() throws {
        let plan = try HighRiskTaskApproval.plan(
            sql: "TRUNCATE TABLE t; INSERT INTO t SELECT * FROM s;",
            targetDatabase: "shop"
        )

        let outcome = HighRiskTaskApproval.outcome(for: plan, decision: .approve)

        XCTAssertTrue(outcome.sendsAnything)
        XCTAssertEqual(outcome.statements.count, plan.count)
        XCTAssertEqual(outcome.statements.map(\.sql), plan.statements.map(\.sql))
        XCTAssertEqual(outcome.statements.map(\.index), [1, 2])
    }

    /// 拒绝 ⇒ 一条都不发（返回值里没有任何语句可发），并带上机器码 `rejected`。
    func testRejectSendsNothingAtAll() throws {
        let plan = try HighRiskTaskApproval.plan(
            sql: "TRUNCATE TABLE t; INSERT INTO t SELECT * FROM s;",
            targetDatabase: "shop"
        )

        let outcome = HighRiskTaskApproval.outcome(for: plan, decision: .reject)

        XCTAssertFalse(outcome.sendsAnything)
        XCTAssertTrue(outcome.statements.isEmpty, "拒绝之后调用方拿不到任何语句 —— 这是结构性的，不是约定")
        XCTAssertEqual(outcome, .sendNothing(reason: "rejected"))
    }

    /// 空计划（构造层面已拦，这里钉住决策口自己的兜底）⇒ 批准也交不出语句。
    func testApproveOfEmptyPlanStillSendsNothing() {
        let empty = HighRiskTaskApproval.Plan(targetDatabase: "shop", statements: [], fingerprint: "x")
        XCTAssertEqual(
            HighRiskTaskApproval.outcome(for: empty, decision: .approve),
            .sendNothing(reason: "emptyPlan")
        )
    }

    // MARK: - ① 影响面：逐条各存一份，估不出来不许冒充 0

    /// 默认是 `pending`，**不是** `rows(0)`：0 是「一条都不命中」这个具体答案。
    func testImpactDefaultsToPendingNotZeroRows() throws {
        let plan = try HighRiskTaskApproval.plan(
            sql: "DELETE FROM t1; DELETE FROM t2;",
            targetDatabase: "shop"
        )

        XCTAssertEqual(plan.pendingImpactCount, 2)
        for statement in plan.statements {
            XCTAssertEqual(statement.impact, .pending)
            XCTAssertFalse(statement.impactIsSettled)
        }
    }

    /// 盖上一条的影响面只影响那一条（逐条各存一份，不许整批共用一个数）。
    func testSetImpactMarksOnlyThatStatement() throws {
        var plan = try HighRiskTaskApproval.plan(
            sql: "TRUNCATE TABLE t; INSERT INTO t SELECT * FROM s;",
            targetDatabase: "shop"
        )

        XCTAssertTrue(plan.setImpact(.rows(12), forIndex: 2))

        XCTAssertEqual(plan.statement(at: 1)?.impact, .pending)
        XCTAssertEqual(plan.statement(at: 2)?.impact, .rows(12))
        XCTAssertEqual(plan.pendingImpactCount, 1)
        XCTAssertTrue(plan.statement(at: 2)?.impactIsSettled ?? false)
    }

    /// 序号不存在 ⇒ 返回 `false` 且**不偷偷多一行**（否则审批单上会冒出没人发过的语句）。
    func testSetImpactWithUnknownIndexDoesNotGrowThePlan() throws {
        var plan = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1;", targetDatabase: "shop")

        XCTAssertFalse(plan.setImpact(.rows(3), forIndex: 9))
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.statement(at: 9), nil)
    }

    /// 估不出来时原因码原样留着（界面翻人话），不被压成 0 行。
    func testUnavailableImpactKeepsItsReasonCode() throws {
        var plan = try HighRiskTaskApproval.plan(
            sql: "TRUNCATE TABLE t; INSERT INTO t SELECT * FROM s;",
            targetDatabase: "shop"
        )

        plan.setImpact(.unavailable("notDataChange"), forIndex: 1)

        XCTAssertEqual(plan.statement(at: 1)?.impact, .unavailable("notDataChange"))
        XCTAssertNotEqual(plan.statement(at: 1)?.impact, .rows(0))
    }

    // MARK: - 计划身份

    /// 同一批算出同一个指纹（跨进程也一样），换一处参数就不再是同一张单。
    func testFingerprintIsStableAndSensitiveToEveryPart() throws {
        let a = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1; DELETE FROM t2;", targetDatabase: "shop")
        let b = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1; DELETE FROM t2;", targetDatabase: "shop")
        let otherDatabase = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1; DELETE FROM t2;", targetDatabase: "stage")
        let otherStatement = try HighRiskTaskApproval.plan(sql: "DELETE FROM t1; DELETE FROM t3;", targetDatabase: "shop")

        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertNotEqual(a.fingerprint, otherDatabase.fingerprint, "换库不是同一张单")
        XCTAssertNotEqual(a.fingerprint, otherStatement.fingerprint, "换一条语句不是同一张单")
    }

    /// `A;B` 与 `AB` 不许算成同一批（分隔符必须进指纹）。
    func testFingerprintSeparatesStatementBoundaries() throws {
        let two = try HighRiskTaskApproval.plan(statements: ["DELETE FROM t1;", "DELETE FROM t2;"], targetDatabase: "shop")
        let one = try HighRiskTaskApproval.plan(
            statements: ["DELETE FROM t1;DELETE FROM t2;"],
            targetDatabase: "shop"
        )

        XCTAssertNotEqual(two.count, one.count)
        XCTAssertNotEqual(two.fingerprint, one.fingerprint)
    }

    // MARK: - ③ 拒绝留痕

    /// 拒绝是**一种结果**，不是「跳过」：状态码与展示名都必须分开。
    func testRejectedStatusIsDistinctFromSkipped() {
        XCTAssertEqual(TaskRunRecord.Status.rejected.rawValue, "rejected")
        XCTAssertNotEqual(TaskRunRecord.Status.rejected, .skipped)
        XCTAssertEqual(TaskRunRecord.Status.rejected.displayName, "已拒绝")
        XCTAssertTrue(TaskRunRecord.Status.allCases.contains(.rejected))
        XCTAssertFalse(TaskRunRecord.Status.rejected.displayName.isEmpty)
    }

    /// 拒绝那一次执行能被写成一条可读的历史记录（挂在任务上、带时刻与原因）。
    func testRejectedRunRecordRoundTripsAndReadsAsRejected() throws {
        let record = TaskRunRecord(
            taskID: UUID(),
            plannedAt: epoch,
            startedAt: epoch,
            finishedAt: epoch,
            status: .rejected,
            rowsWritten: nil,
            message: "本次执行未获批准，没有写库。"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TaskRunRecord.self, from: data)

        XCTAssertEqual(decoded.status, .rejected)
        XCTAssertEqual(decoded.startedAt, epoch, "执行时刻要留在历史里")
        XCTAssertNotNil(decoded.message)
    }
}
