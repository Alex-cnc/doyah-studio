import XCTest

/// 查询工具栏的**形态判据**：工具条上不许出现文字控件（FR-EXEC-13 / FR-EDIT-08）。
///
/// 为什么需要一条源树判据：需求里写的是「图标按钮工具栏，**不使用文字按钮**」（`FR-EXEC-13` / `FR-EDIT-08`），
/// 需求提出者 2026-09-24 的原话是「工具条上就应该是干干净净的一堆按钮，或者可选的下拉框对象等，
/// 而不应该在这里留一长串文本」。但这条口径**一直没有判据** —— 2026-09-27 人工点验时发现事务控件整块是
/// 文字（分段选择器 + 两个文字按钮 + 文字徽标），而三书里这一条一直写着 ✅。
/// 口径写在文档里而判据缺席，就会以「上次说过了还犯」的形式复发；这里把它变成机械判据。
///
/// **判据的边界**（写清楚，免得以后被误伤或被绕开）：
/// - 禁（工具条顶层 = `QueryToolbar.body` 区段 + 整个 `TransactionControl`）：`Picker(`、
///   `.pickerStyle(.segmented)`、`Button(L(`、`Label(L(`、`Text(L(`。
///   * 分段控件的每一段都必须写字，所以 `.segmented` 一律禁；`Picker` 的其它形态同样禁 ——
///     工具条上的控件要么是按钮、要么是下拉菜单。
///   * `Button(L(` / `Label(L(` / `Text(L(` 会直接渲染文案，工具条上只允许图标 + 提示。
/// - 允许：`Menu`（下拉框）—— 需求提出者明确把「可选的下拉框对象」划在允许一侧；
///   菜单**内部**的 `Button(L(...))` 是下拉里的一项、不在工具条上，故判据只扫工具条顶层区段。
/// - 仍要求 `.help(` 存在：可发现性不许靠「把提示也删掉」来实现。
final class QueryToolbarConventionTests: XCTestCase {

    /// 判据本身写成可被喂任意文本的函数 —— 这样负例自证（③）跑的是同一份逻辑。
    private static let forbidden: [(shape: String, why: String)] = [
        ("Picker(", "工具条上不许出现选择器控件（分段控件的段只能写字）"),
        (".pickerStyle(.segmented)", "工具条上不许出现分段控件"),
        ("Button(L(", "按钮标题不许是文字 —— 用图标 + `.help` 提示"),
        ("Label(L(", "徽标不许是文字 —— 用图标 + 数据"),
        ("Text(L(", "工具条上不许直接渲染文案")
    ]

    private func violations(in text: String) -> [String] {
        Self.forbidden.filter { hits($0.shape, in: text) }.map { "\($0.shape)：\($0.why)" }
    }

    /// 形状匹配**要认标识符边界**：`modeButton(L(` 里含有子串 `Button(L(`，但它是一个自定义方法名，
    /// 不是"文字标题按钮"。第一版判据就是这么误伤了自己的代码 —— 所以这里按前一个字符判定，
    /// 并以 ③ 的正反两例钉住（该报的报、不该报的不报）。
    private func hits(_ shape: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let found = text.range(of: shape, range: searchStart..<text.endIndex) {
            let precededByIdentifierCharacter: Bool = {
                guard shape.first?.isLetter == true, found.lowerBound > text.startIndex else { return false }
                let previous = text[text.index(before: found.lowerBound)]
                return previous.isLetter || previous.isNumber || previous == "_"
            }()
            if !precededByIdentifierCharacter { return true }
            searchStart = found.upperBound
        }
        return false
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: ① 事务控件：整块都在工具条上

    func testTransactionControlHasNoTextControls() throws {
        let text = try source("App/Views/TransactionControl.swift")
        XCTAssertGreaterThan(text.count, 1_000, "读到的内容太短，这条判据不成立")
        XCTAssertEqual(violations(in: text), [], "事务控件是工具条上的一块：不许出现文字控件")
        XCTAssertTrue(text.contains(".help("), "图标按钮必须带提示 —— 可发现性不能靠删提示实现")
        XCTAssertTrue(text.contains(".hoverHint("), "状态徽标的说明走即时悬停提示（见 HoverHint）")
    }

    // MARK: ② 查询工具条：只扫顶层区段

    func testQueryToolbarTopRowHasNoTextControls() throws {
        let text = try source("App/Views/QueryToolbar.swift")
        guard let start = text.range(of: "var body: some View {"),
              let end = text.range(of: "// MARK: - 文件", range: start.upperBound..<text.endIndex) else {
            return XCTFail("找不到工具条顶层区段 —— 判据的锚点变了，请更新这条判据，不要删掉它")
        }
        let topRow = String(text[start.upperBound..<end.lowerBound])
        XCTAssertGreaterThan(topRow.count, 600, "顶层区段读到的内容太短，这条判据不成立")
        XCTAssertEqual(violations(in: topRow), [], "工具条顶层只允许按钮、下拉菜单与图标")
        XCTAssertTrue(
            topRow.contains("TransactionControl("),
            "事务控件应当仍挂在工具条上 —— 这条判据不是靠「把它挪出工具条」通过的"
        )
    }

    // MARK: ③ 负例自证：判据必须真的抓得住旧写法

    func testCheckerCatchesTheOldTextControl() {
        let old = """
        Picker("", selection: binding) {
            Text(L(.transactionModeAuto)).tag(TransactionMode.autoCommit)
        }
        .pickerStyle(.segmented)
        Button(L(.transactionCommit)) { }
        Label(L(.transactionOpenBadge, 3), systemImage: "arrow.triangle.2.circlepath")
        """
        let found = violations(in: old)
        XCTAssertEqual(found.count, Self.forbidden.count, "旧写法应当五种形状全中，实际抓到：\(found)")
    }

    /// ③′ 反例自证：**不该报红的不许报红** —— 自定义方法名里含 `Button(L(` 不算文字按钮
    /// （第一版判据就是在这里咬到自己代码的）。
    func testCheckerDoesNotFireOnNameSubstrings() {
        let legitimate = """
        modeButton(L(.transactionModeAuto), target: .autoCommit, current: mode)
        someLabel(L(.transactionCommit))
        """
        XCTAssertEqual(violations(in: legitimate), [], "方法名里的子串不是文字控件，判据不许误伤")
    }

    // MARK: ⑤ 工具条里的即时提示必须向上弹

    /// 提示是**宿主视图树内的 overlay**：overlay 不改变绘制顺序，伸出宿主边界就会落到后面的兄弟视图之下。
    /// 工具条下面是 SQL 编辑器（`NSTextView`，AppKit 承载）—— 2026-09-27 人工点验实测：提示出现了、但被编辑器挡住。
    /// 所以工具条里的 `.hoverHint(` 必须显式给 `placement: .above`。
    func testToolbarHoverHintsPointUpward() throws {
        // 事务控件：必须至少有一处即时提示，且每一处都显式给了方向。
        let control = try source("App/Views/TransactionControl.swift")
        var index = control.startIndex
        var calls = 0
        while let found = control.range(of: ".hoverHint(", range: index..<control.endIndex) {
            calls += 1
            let following = control[found.upperBound...].prefix(160)
            XCTAssertTrue(
                following.contains("placement: .above"),
                "工具条里的 .hoverHint( 必须显式给 placement: .above（向下弹会被编辑器盖住）"
            )
            index = found.upperBound
        }
        XCTAssertGreaterThan(calls, 0, "事务状态徽标应当保留即时提示 —— 不许靠删掉提示来过关")

        // 工具条本体：现在没有提示，将来加的话同样必须显式给方向。
        let toolbar = try source("App/Views/QueryToolbar.swift")
        var cursor = toolbar.startIndex
        while let found = toolbar.range(of: ".hoverHint(", range: cursor..<toolbar.endIndex) {
            let following = toolbar[found.upperBound...].prefix(160)
            XCTAssertTrue(
                following.contains("placement:"),
                "QueryToolbar 里的 .hoverHint( 必须显式给 placement"
            )
            cursor = found.upperBound
        }
    }

    // MARK: ④ 末例：扫的真文件不是空的（路径写错时不许一路绿）

    func testTargetsExist() throws {
        for relative in ["App/Views/QueryToolbar.swift", "App/Views/TransactionControl.swift"] {
            let text = try source(relative)
            XCTAssertGreaterThan(text.count, 1_000, "\(relative) 内容太短，路径可能写错了")
        }
    }
}
