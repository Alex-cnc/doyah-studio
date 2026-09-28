import XCTest
@testable import DoyahCore

/// **AI 产物 → 笔记**的桥（DOYAH-10 / 任务 1）：元信息要对、行数据不许进、指纹要稳定。
final class AICaptureTests: XCTestCase {

    private func context() -> DiagnosisContext {
        DiagnosisContext(
            question: "这条查询为什么慢？",
            target: "postgres@192.168.5.217:5432/dsh_db（8.4.10）",
            evidence: [
                DiagnosisContextBuilder.makeEvidence(
                    id: "e1", kind: .statement, sql: "SELECT * FROM orders", rows: [], language: .simplifiedChinese
                ),
                DiagnosisContextBuilder.makeEvidence(
                    id: "e2", kind: .executionPlan, sql: "EXPLAIN SELECT * FROM orders",
                    rows: [["Seq Scan on orders  (cost=0.00..431.00 rows=21 width=8)"], ["  Filter: (id > 1)"]], language: .simplifiedChinese
                )
            ]
        )
    }

    private func report() -> DiagnosisAdviceReport {
        DiagnosisAdvice.parse(
            reply: "结论: 全表扫描 [依据: e2]\n建议: CREATE INDEX ON orders (id)",
            context: context(), language: .simplifiedChinese
        )
    }

    func testDiagnosisNoteKeepsConclusionsCitationsAndSQL() {
        let note = AICapture.diagnosisNote(
            question: "这条查询为什么慢？", target: context().target, context: context(), report: report(), language: .simplifiedChinese
        ).makeNote()
        XCTAssertEqual(note.source.kind, .diagnosis)
        XCTAssertEqual(note.source.connectionName, "192.168.5.217", "来源只留主机名，不留连接串")
        XCTAssertTrue(note.body.contains("全表扫描"))
        XCTAssertTrue(note.body.contains("e2"), "引用编号要留在笔记里")
        XCTAssertTrue(note.body.contains("CREATE INDEX ON orders (id)"))
        XCTAssertTrue(note.body.contains("EXPLAIN SELECT * FROM orders"), "取证 SQL 可复跑，要留")
    }

    /// **行数据不进笔记**：证据里那两行计划文本（rows）不该出现在正文里。
    func testDiagnosisNoteNeverCarriesEvidenceRowData() {
        let note = AICapture.diagnosisNote(
            question: "q", target: context().target, context: context(), report: report(), language: .simplifiedChinese
        ).makeNote()
        XCTAssertFalse(note.containsRowData)
        XCTAssertFalse(note.body.contains("cost=0.00..431.00"), "证据行数据不允许进笔记正文")
        XCTAssertTrue(note.body.contains("共 2 行"), "但'取到几行'这类说明要留 —— 那是元信息不是数据")
    }

    func testFingerprintIsStableAndSensitiveToContent() {
        let first = AICapture.diagnosisNote(question: "q", target: context().target, context: context(), report: report(), language: .simplifiedChinese)
        let second = AICapture.diagnosisNote(question: "q", target: context().target, context: context(), report: report(), language: .simplifiedChinese)
        XCTAssertEqual(first.source.fingerprint, second.source.fingerprint, "同一份产物必须算出同一个指纹")
        XCTAssertNotNil(first.source.fingerprint)

        let other = DiagnosisAdvice.parse(reply: "结论: 换个说法 [依据: e2]", context: context(), language: .simplifiedChinese)
        let third = AICapture.diagnosisNote(question: "q", target: context().target, context: context(), report: other, language: .simplifiedChinese)
        XCTAssertNotEqual(first.source.fingerprint, third.source.fingerprint, "结论不同就是另一份产物")
    }

    func testMaintenanceNoteRecordsStatesReasonsAndUnparsableLines() {
        let review = MaintenancePlanner.makePlan(
            from: """
            task: analyze | 更新统计 | sql: ANALYZE public.customers
            task: reindex | 重建索引 | sql: REINDEX INDEX public.orders_pkey
            task: backup | 备份 | command: pg_dump -Fc analytics
            想删掉一张表
            """,
            policy: MaintenancePolicy(),
            language: .simplifiedChinese
        )
        let note = AICapture.maintenanceNote(
            planText: "task: analyze | 更新统计 | sql: ANALYZE public.customers",
            review: review,
            target: "postgres@192.168.5.217:5432/dsh_db",
            language: .simplifiedChinese
        ).makeNote()
        XCTAssertEqual(note.source.kind, .maintenance)
        XCTAssertTrue(note.body.contains("已拒绝"), "被限流拒绝的条目要记下来（含理由）")
        XCTAssertTrue(note.body.contains("没看懂的行"))
        XCTAssertTrue(note.body.contains("想删掉一张表"), "看不懂的行原样保留")
    }

    func testSkillNoteIsThePlaceForAICraftedKnowHow() {
        let note = AICapture.skillNote(
            title: "MySQL 时区排查步骤",
            body: "1) SELECT @@global.time_zone\n2) 看 TIMESTAMP 列",
            connectionName: "DemoMySQL",
            // 笔记侧收的是**文本**（默认标签由宿主渲染好再进来，见 `skillNote(defaultTag:)`）。
            defaultTag: LocalizedStrings.text(.aiNoteTagSkill, language: .simplifiedChinese)
        ).makeNote()
        XCTAssertEqual(note.source.kind, .skill)
        XCTAssertEqual(note.source.connectionName, "DemoMySQL")
        XCTAssertEqual(note.tags, ["技能"])
        XCTAssertFalse(note.containsRowData)
    }

    func testSQLNoteUsesFirstLineAsTitle() {
        let sql = "SELECT id, name\nFROM customers\nWHERE id > 1"
        let note = AICapture.sqlNote(
            sql: sql,
            connectionName: nil,
            tag: LocalizedStrings.text(.aiNoteTagSQL, language: .simplifiedChinese)
        ).makeNote()
        XCTAssertEqual(note.source.kind, .sql)
        XCTAssertEqual(note.title, "SELECT id, name")
        XCTAssertTrue(note.body.contains("```sql"))
    }

    /// 存进本地库再读回来，元信息不丢（桥与存储合起来才是"能用"）。
    func testCapturedNoteSurvivesStoreRoundTrip() async throws {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-ai-capture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = NoteStore(fileURL: fileURL)
        let saved = try await store.upsert(
            AICapture.diagnosisNote(question: "q", target: context().target, context: context(), report: report(), language: .simplifiedChinese)
        )
        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].source.kind, .diagnosis)
        XCTAssertEqual(loaded[0].source.fingerprint, saved.source.fingerprint)
        XCTAssertEqual(loaded[0].source.connectionName, "192.168.5.217")
    }

    /// **笔记侧收文本、不收语言；语言在宿主侧渲染**（队列 L-65 第 3 批 + `FR-PLUG-03`）：
    /// `AICapture.skillNote` / `sqlNote` 的标签参数是 `String`（判据 = 闭环第 10 项的类型白名单），
    /// 于是「显示成哪种语言」由宿主决定 —— 两个语言值在这里都能进来，两份译文都真的可达。
    func testCapturedNoteIsWrittenInTheGivenLanguage() {
        let zhSkill = AICapture.skillNote(
            title: "t", body: "b",
            defaultTag: LocalizedStrings.text(.aiNoteTagSkill, language: .simplifiedChinese)
        ).makeNote()
        let enSkill = AICapture.skillNote(
            title: "t", body: "b",
            defaultTag: LocalizedStrings.text(.aiNoteTagSkill, language: .english)
        ).makeNote()
        XCTAssertEqual(zhSkill.tags, ["技能"])
        XCTAssertEqual(enSkill.tags, ["skill"])
        XCTAssertEqual(
            AICapture.sqlNote(
                sql: "SELECT 1", connectionName: nil,
                tag: LocalizedStrings.text(.aiNoteTagSQL, language: .english)
            ).makeNote().tags,
            ["sql"]
        )

        let zhDiagnosis = AICapture.diagnosisNote(
            question: "q", target: context().target, context: context(), report: report(), language: .simplifiedChinese
        ).makeNote()
        let enDiagnosis = AICapture.diagnosisNote(
            question: "q", target: context().target, context: context(), report: report(), language: .english
        ).makeNote()
        XCTAssertTrue(zhDiagnosis.body.contains("目标："))
        XCTAssertTrue(enDiagnosis.body.contains("Target:"), "英文界面上存出来的笔记正文也是英文")
        XCTAssertNotEqual(zhDiagnosis.body, enDiagnosis.body, "语言不是摆设")
    }
}
