import Foundation

/// 「这条语句大概会改多少行」的估计（§9.1.16 缺口：审批单只给 SQL 与风险等级，不给影响面）。
///
/// 为什么要它：批准一条 `DELETE` 前，人真正想知道的是**规模** —— 3 行和 30 万行的决定完全不一样，
/// 而「语句类别 = DELETE · 风险 = 高」这两格给不出这个区别。
///
/// **来源只有一个**：数据库自己的优化器（PostgreSQL 的 `EXPLAIN (FORMAT JSON)` 里
/// 根节点的 `Plan Rows`）。不在本地自己数、不按表总行数猜 —— 猜出来的数字比没有更糟：
/// 人会拿它当依据去点「批准」。
///
/// **安全边界**：这里只生成 `EXPLAIN` 语句（**不带 `ANALYZE`**），所以它**不会执行**目标语句。
/// 带 `ANALYZE` 的版本会真的改数据 —— 那正是本类型拒绝的东西。
public enum AgentPlanRows {

    /// 估计结果。给界面的是**机器码**，人话在界面那层翻（Core 不做本地化）。
    public enum Estimate: Equatable, Sendable {
        /// 优化器给的预计行数（`0` 是合法值：`WHERE` 一列都不命中时它就是 0）。
        case rows(Int)
        /// 估不出来，附一个原因码（`notDataChange` / `dialectUnsupported` / `noAnswer` / `parseFailed`）。
        case unavailable(String)
    }

    /// 允许套 `EXPLAIN` 的语句首词：**只放改数据的**。
    ///
    /// 只读语句不估 —— 它没有「会影响多少行」这个问题，界面上该写「不适用」而不是「0 行」。
    static let dataChangeKeywords: Set<String> = ["update", "delete", "insert", "merge"]

    /// 把一条 DML 包成 `EXPLAIN (FORMAT JSON) …`。
    ///
    /// 返回 `nil` 的情形都**不该猜**：空语句 / 只读语句 / 多语句（`;` 分隔）。
    /// 多语句尤其危险：`EXPLAIN` 只作用在第一条，后半截会原样被执行。
    public static func explainStatement(for sql: String) -> String? {
        var statement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while statement.hasSuffix(";") {
            statement = String(statement.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !statement.isEmpty else { return nil }
        // 多语句：去掉尾分号后正文里还有 `;` ⇒ 拒绝（见上面的理由）。
        guard !statement.contains(";") else { return nil }

        let first = statement
            .split(whereSeparator: { $0.isWhitespace || $0 == "(" })
            .first
            .map { String($0).lowercased() } ?? ""
        guard dataChangeKeywords.contains(first) else { return nil }
        return "EXPLAIN (FORMAT JSON) " + statement
    }

    /// 从 `EXPLAIN (FORMAT JSON)` 的输出里取根节点的 `Plan Rows`。
    ///
    /// **实测口径（2026-10-23 · 217 上的 PG 18.6）**：改进数据的语句，根节点是
    /// `"Node Type": "ModifyTable"`（带 `"Operation": "Update"/"Delete"/…`），而它的
    /// **`Plan Rows` 是 0** —— 那是 `ModifyTable` 节点**自己输出**的行数（只有带 `RETURNING`
    /// 才非 0），不是「会改多少行」。真正的预估在**子节点**（`Plans[0]`，如 `Seq Scan`，实测 500）。
    /// ⇒ 只读根节点会稳定报 0，人会以为「这条只改 0 行」然后放心批准 —— 这是最危险的那种假数。
    ///
    /// 所以规则是：`ModifyTable` 一族**根 0 就取第一个子节点**；`RETURNING` 那种根非 0 的照用根。
    /// 老版本 PG（根节点直接叫 `Update` / `Delete` / `Insert` / `Merge`）同样按这条走。
    public static func rows(fromExplainJSON json: String) -> Int? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let root: [String: Any]?
        if let array = parsed as? [Any] {
            root = array.compactMap { $0 as? [String: Any] }.first
        } else {
            root = parsed as? [String: Any]
        }
        guard let plan = root?["Plan"] as? [String: Any] else { return nil }

        let nodeType = (plan["Node Type"] as? String) ?? ""
        let rootRows = planRowsValue(plan)

        if modificationNodes.contains(nodeType) {
            // 根 0 ⇒ 看子节点（见上面那段实测口径）；根非 0（带 RETURNING）⇒ 根就是答案。
            if let rootRows, rootRows > 0 { return rootRows }
            if let plans = plan["Plans"] as? [Any],
               let child = plans.compactMap({ $0 as? [String: Any] }).first,
               let childRows = planRowsValue(child) {
                return childRows
            }
        }
        return rootRows
    }

    /// 「改进数据」的节点名（PG 17+ 统一叫 `ModifyTable`，更早的版本按动作各叫各的）。
    static let modificationNodes: Set<String> = ["ModifyTable", "Update", "Delete", "Insert", "Merge"]

    /// 一个计划节点上的 `Plan Rows`（数字 / NSNumber / 文本三种写法都认）。
    static func planRowsValue(_ node: [String: Any]) -> Int? {
        if let value = node["Plan Rows"] as? Int { return value }
        if let number = node["Plan Rows"] as? NSNumber { return number.intValue }
        if let text = node["Plan Rows"] as? String { return Int(text) }
        return nil
    }

    /// 组装给界面的结论：有 JSON 但读不出行数 ⇒ `parseFailed`，压根没答 ⇒ `noAnswer`。
    public static func estimate(json: String?) -> Estimate {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable("noAnswer")
        }
        guard let rows = rows(fromExplainJSON: json) else { return .unavailable("parseFailed") }
        return .rows(rows)
    }
}
