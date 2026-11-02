import Foundation

/// 日历上「把一行拖到另一格」的载荷（`FR-NTS-TODO-STATE-001` 判据③「日历上可直接完成 / 改期」）。
///
/// 三条口径（与笔记那一侧的 `NoteDragPayload` 同形）：
///  ① **唯一生产点 / 唯一解点**：视图不自己拼字符串 —— 拼法与解法不一致的症状是
///     「拖过去什么都没发生」，而拖拽失败**没有任何报错**（人只会以为这功能坏了）；
///  ② 载荷只带**那一条任务的身份**（`Todo.id`）：拖拽不搬数据、不预生成副本 ——
///     「改到哪一天」由落点那一格给（日历不另存任务，`FR-NTS-TODO-STATE-002`）；
///  ③ 认不出 / 解不开 ⇒ `nil`（调用方如实说一句，不猜是哪一条、也不猜改到哪天）。
public enum TodoDragPayload {

    /// 前缀让载荷自带「这是待办拖拽」这一层（以后别的列表也拖字符串时不会互相误解）。
    private static let prefix = "todo:"

    /// 生产载荷（界面上唯一一处调用点：`AppState.todoDragPayload`）。
    public static func encode(_ id: UUID) -> String {
        prefix + id.uuidString
    }

    /// 解载荷：前缀不对 / 尾巴不是 UUID ⇒ `nil`（不抛错 —— 拖拽失败不该弹框）。
    public static func decode(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let tail = String(trimmed.dropFirst(prefix.count))
        return UUID(uuidString: tail)
    }
}
