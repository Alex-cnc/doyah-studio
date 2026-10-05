import Foundation

/// **检索路线 → 界面要如实说出的那一句**（队列 L-44，2026-09-28）。
///
/// ## 为什么要有这一层（而不是在视图里就地 `switch`）
///
/// ① **路线是 Core 的事实**：`NoteDatabase.SearchResult.Route`（`.fullText` / `.substring`）
///    由存储层给出，「这条结果是**怎么**找出来的」不该由界面自己推断；
/// ② **口径要能被单测钉住**：把「哪条路 → 哪个文案键」收成一处纯函数，映射就成了可判定的东西 ——
///    新增一条路线时 `switch` 先编译不过（穷尽性由编译器守），补了 case 却忘了配文案，
///    `Tests/NoteSearchDisclosureTests.swift` 当场判红；
/// ③ **「不必多说」也是一条口径**：全文检索命中是检索的**正常结果**，界面不该额外解释什么 ——
///    这件事写成显式的 `nil`，比让视图「看着办」更难被悄悄改掉。
///
/// 界面侧只做两件事：`key` 给了就用它出文案，`nil` 就什么都不说。
public enum NoteSearchDisclosure {

    /// 这条路要不要给用户一句话；`nil` = 这条路的正常结果**不必额外解释**。
    public static func key(for route: NoteDatabase.SearchResult.Route) -> LKey? {
        switch route {
        case .fullText:
            // 全文检索命中（查询串 ≥3 字且 trigram 有命中）：这是用户期待的那个结果，不必解释。
            return nil
        case .substring:
            // 子串兜底：查询串 < 3 字（中文里极常见，trigram 切不出 token），
            // 或 ≥3 字的短语在全文索引里落空（含空格的查询）后回退。
            // 用户必须知道「这次不是全文检索」—— 否则会把兜底的脾气当成检索的全部脾气。
            return .noteSearchSubstring
        }
    }
}
