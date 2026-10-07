import Foundation

/// 笔记编辑区的**自动保存**口径（片 `N2-4` · 人类主人令 `T-20261007-006` 第二节第六条）。
///
/// 两条触发，缺一条就不算「自动」：
///   ① **停顿即存**：最后一次改动之后 `pauseWindow` 之内没有新的改动 ⇒ 落库一次；
///   ② **切走即存**：任何「离开这一条笔记」的入口（点另一条 / 换范围 / 换模块 / 新建）
///      先把手上的改动快照下来、排进写库队列 —— 否则「编辑完直接点开另一条」这几秒里敲的字全丢。
///
/// 四条刻意的口径（都在 `App/AppState.swift` 的「自动保存」那一节落地）：
///   · **不阻塞输入**：计时走 `Task.sleep`（挂起，不占主线程、不卡键盘）—— 人类主人令里
///     「不许把自动保存做成阻塞输入」那一条说的就是这件事；
///   · **不新增库字段**：草稿直接写进 `notes` 那张表，走的就是手动「保存」同一条写路
///     （`NoteLibrary.upsert`）⇒ 没有 schema 迁移，也**没有**「发现未保存草稿，是否恢复？」
///     那类弹窗（同一节的验收判据④：**全程无弹窗**）；
///   · **失败要看得见**：`NoteSaveState.failed` 带一句给人看的原因，工具条与状态栏各说一次
///     （验收判据⑥「失败路径有可见线索」），绝不静默失败；
///   · **状态只有一个出处**：`NoteSaveState` —— 工具条画它、状态栏说它、机器判据也读它。
public enum NoteAutosave {

    /// **停顿窗口**：停手这么久 ⇒ 落库一次。
    ///
    /// 为什么是 1.5 s：工作区编辑器那两档合并窗口（0.12 / 0.45 s）是**画面**的事，
    /// 这里换的是**写盘** —— 窗口太短等于每敲几个字写一次库；也不能太长：
    /// 强杀（`kill -9`）时丢掉的就是「最后一次落盘之后」的这段时间（验收判据③）。
    public static let pauseWindow: Duration = .milliseconds(1500)

    /// 工具条那枚状态文字的**可读名字**（`accessibilityIdentifier`）。
    /// 判据按它找那一个视图，`App/Views/NotesPanel.swift` 只引用这一处 ——
    /// 判据与界面认的是同一个名字，谁也不能各写一份字符串。
    public static let statusIdentifier = "notes-editor-save-state"
}

/// **编辑器的保存状态**（片 `N2-4`）：工具条与状态栏读它、机器判据也读它 ——
/// 「现在编辑器里这一份到底落库了没有」**只此一个出处**。
public enum NoteSaveState: Equatable, Sendable {
    /// 编辑器里没有未落库的改动（初始态，或刚写完）。
    case idle
    /// 有改动、还在停顿窗口里等着落库。
    case pending
    /// 正在写库。
    case saving
    /// **写库失败**：带一句给人看的原因（工具条 + 状态栏各说一次，不静默）。
    case failed(String)

    /// 工具条上那句话的文案键。
    ///
    /// `idle` 给 `nil`：**没有未落库的改动就不该占地方** —— 常态下多一行永远亮着的状态字，
    /// 会被读成「这行字本来就长这样」，反而看不出「现在有东西没存」（`L-50` 同族：
    /// 一直亮着的提示等于没有提示）。三态各有各的话，键都在语言表里（中英齐）。
    public var languageKey: LKey? {
        switch self {
        case .idle: return nil
        case .pending: return .notesAutoSavePending
        case .saving: return .notesAutoSaveSaving
        case .failed: return .notesAutoSaveFailed
        }
    }

    /// 出错那一档的补充说明（悬停提示用）：只有 `failed` 有 —— 它就是「为什么没存上」。
    public var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }

    /// 是不是出错那一档（工具条据此换色；判据据此认「有可见线索」）。
    public var isFailure: Bool { failureReason != nil }
}
