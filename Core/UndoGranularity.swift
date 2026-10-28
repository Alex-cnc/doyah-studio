import Foundation

/// 撤销步的**粒度**判定（`FR-STD-WS-EDIT-014`）：哪些编辑该合成一次撤销、哪些各自一步。
///
/// 为什么这件事要有一个 Core 里的判定而不是让编辑器各自「看着办」：
/// 一条撤销步的边界取决于**这一次动作是什么**（连续键入 / 换行 / 移行 / 注释切换 / 补全 / 片段 /
/// 格式化 / 多光标整批写回 …），而「这是什么动作」只有在调用点上才知道。判定放 Core 有两样好处：
/// ① 两个编辑面（工作区 `CodeTextView` / 数据库 `SQLTextView`）用的是**同一张表**，
///    不会出现「同一件事在两个编辑器里撤销手感不一样」；
/// ② 边界是纯函数，可以逐条判红（改坏一处 ⇒ 红），不依赖真按键事件流。
///
/// **量不出来的那一半如实写在这里**：无事件流的探针里 `NSTextView` 会把整段改动并进一层
/// （实测见 `.agent/evidence/2026-10-29-EDIT-014.md`：三次不分组替换与三次分组替换的
/// 撤销层数**都是 1**）⇒「连续输入合成一步」这一条**探针判不了**，只能人工按 ⌘Z 点验。
/// 所以本类型只做两件可机械判的事：**在哪断开**（`decide`）与**这一步叫什么**（`actionNameKey`）。
public enum UndoEditKind: String, CaseIterable, Sendable {
    /// 连续键入一个字符（词内连打）。
    case typing
    /// 连续退格 / 删除。
    case deleting
    /// 回车（含列表续行、自动缩进算出的那一份换行）。
    case newline
    /// 粘贴（含按上下文重排缩进的多行粘贴）。
    case paste
    /// 补全落地（行内灰字接受 / 语言服务的 `insertCompletion`）。
    case completion
    /// 片段模板展开。
    case snippet
    /// 自动配对（打 `(` 补 `)`、引号成对）。
    case pairing
    /// 整行上移 / 下移。
    case lineMove
    /// 复制当前行 / 选中整段。
    case duplicateLine
    /// 行注释切换。
    case commentToggle
    /// Markdown 任务框翻转（`⌘L`）。
    case taskToggle
    /// 缩进（Tab 到最后那一档 / 整段缩进）。
    case indent
    /// 格式化（整篇替换）。
    case formatting
    /// 其它整篇替换（多光标整批写回等）。
    case documentReplace

    /// 一次用户动作 = 一个撤销步：与**前一步、后一步都断开**。
    ///
    /// 只有「连续键入」与「连续删除」两类允许与同类合并 —— 这就是需求 ①「不逐字符」。
    /// 其余全是一次动作一步（需求 ②：移行 / 注释切换 / 补全各算一步）。
    public var isAtomic: Bool {
        switch self {
        case .typing, .deleting:
            return false
        default:
            return true
        }
    }

    /// 撤销菜单那一行的名字（中英齐）。**switch 不写 `default`**：新增 kind 时漏给名字就编不过，
    /// 免得界面上出现一个空动作名（用户看到的是「撤销 」后面什么都没有）。
    public var actionNameKey: LKey {
        switch self {
        case .typing: return .undoActionTyping
        case .deleting: return .undoActionDeleting
        case .newline: return .undoActionNewline
        case .paste: return .undoActionPaste
        case .completion: return .undoActionCompletion
        case .snippet: return .undoActionSnippet
        case .pairing: return .undoActionPairing
        case .lineMove: return .undoActionLineMove
        case .duplicateLine: return .undoActionDuplicateLine
        case .commentToggle: return .undoActionCommentToggle
        case .taskToggle: return .undoActionTaskToggle
        case .indent: return .undoActionIndent
        case .formatting: return .undoActionFormatting
        case .documentReplace: return .undoActionDocumentReplace
        }
    }
}

/// 这一次编辑要不要在它前面 / 后面断开一次撤销合并。
public struct UndoGroupDecision: Equatable, Sendable {
    /// 动手**前**断开：不把这一步并进上一步。
    public let breakBefore: Bool
    /// 动手**后**断开：下一步不并进这一步。
    public let breakAfter: Bool

    public init(breakBefore: Bool, breakAfter: Bool) {
        self.breakBefore = breakBefore
        self.breakAfter = breakAfter
    }
}

/// 撤销步边界的**状态机**：记着上一次动作是什么，据此回答这一次要不要断开。
///
/// 只记「上一次的类别」、不记时间：时间维度交给系统那条通路（`NSTextView` 自己的
/// 打字合并就是按事件与停顿算的），我们只负责在**类别切换**与**原子动作**处强制断开。
/// 自己再按时间断一次会把「一句话打一半、停下来想一想，再接着打」拆成两步 —— 那不是用户要的。
public struct UndoGranularity: Equatable, Sendable {
    public private(set) var previous: UndoEditKind?

    public init() {}

    public mutating func decide(_ kind: UndoEditKind) -> UndoGroupDecision {
        let mergesWithPrevious = (previous == kind) && !kind.isAtomic
        previous = kind
        return UndoGroupDecision(breakBefore: !mergesWithPrevious, breakAfter: kind.isAtomic)
    }

    /// 重新起算（换文件 / 整篇换掉时用）。
    ///
    /// **撤销 / 重做本身不需要调它**：`NSUndoManager` 在 undo / redo 之后就会断开合并，
    /// 紧接着的键入天然自成一步 —— 这里再记一次状态反而会与它打架。
    public mutating func reset() {
        previous = nil
    }
}

/// 一次替换落下来之后「选区与光标停哪」（`FR-STD-WS-EDIT-014` ③）。
///
/// 需求原文：`FR-STD-WS-EDIT-007` 那类**等长替换**不许把选区与光标顶掉
/// ——`⌘L` 只换方框里那一个字符，替换前后长度相同，用户的手指还在原来的位置上，
/// 这时把光标挪到替换末尾（很多实现的默认做法）就是**无缘无故跳一下**。
///
/// 反过来，**变长**替换（回车续行、注释切换、片段展开）必须用调用方算好的落点：
/// 长度变了，原位置的含义也变了，硬留原地反而会落到半天之前。
public struct EditSelectionPolicy {
    /// - Parameters:
    ///   - original: 替换**之前**的选区（UTF-16）。
    ///   - editRange: 被替换掉的那一段。
    ///   - replacementLength: 换成的新文本长度（UTF-16）。
    ///   - requested: 调用方（Core 的计划）算出来的落点。
    ///   - documentLength: 替换**之后**的文档长度，用来夹住落点。
    public static func after(original: NSRange,
                             editRange: NSRange,
                             replacementLength: Int,
                             requested: NSRange,
                             documentLength: Int) -> NSRange {
        if replacementLength == editRange.length {
            return clamped(original, to: documentLength)
        }
        return clamped(requested, to: documentLength)
    }

    static func clamped(_ range: NSRange, to documentLength: Int) -> NSRange {
        let location = min(max(0, range.location), documentLength)
        let length = min(max(0, range.length), documentLength - location)
        return NSRange(location: location, length: length)
    }
}
