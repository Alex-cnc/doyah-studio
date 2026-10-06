import SwiftUI
import AppKit

/// 工具栏 / 菜单快捷键的**单一事实来源**（FR-EDIT-28）。
///
/// 为什么要集中：快捷键同时出现在三个地方 —— 视图上的 `.keyboardShortcut`、
/// 按钮 tooltip、帮助面板列表。散着写必然出现「改了键、提示没改」。
/// 这里一处定义，三处引用。
///
/// 选键原则：
/// - 不占用系统级快捷键（⌘Q / ⌘W / ⌘H / ⌘M / ⌘,）；
/// - 高频动作用最短的组合（执行 ⌘↩、停止 ⌘.、查找 ⌘F）；
/// - 成组的动作用同一前缀（保存类 ⌘S / ⇧⌘S / ⌘D / ⇧⌘D）；
/// - ⌘K 归命令面板（FR-EDIT-25），登记为 `.commandPalette`，此处不得再占用。
enum AppShortcut: CaseIterable {
    /// 执行查询（需求 FR-EDIT-08 / FR-EXEC-13 明确指定 ⌘↩）。
    case execute
    case stop
    case check
    /// 执行计划面板（FR-DIAG-01）。
    case executionPlan

    case openFile
    case saveFile
    case saveFileAs
    case saveQuery
    case savedQueries
    case history

    case find
    case replace
    case goToLine
    case indent
    case outdent
    case clearEditor
    case format
    /// 工作区代码编辑器的「格式化代码」（FR-EDIT-39）。与 SQL 编辑器那条 `format` 用**同一个键**：
    /// 两者分属两个活动区（SQL 编辑器的「编辑」菜单 / 工作区页签条），不会同时出现在屏幕上；
    /// 而「格式化」在哪儿都是 ⇧⌘F 这件事，比给两个区域各发明一个键更有用。
    case formatCode

    /// 工作区 Markdown 的**任务框勾选翻转**（`FR-EDIT-48`）。
    ///
    /// 与 SQL 编辑器那条 `.goToLine`（跳转到行）**共用 ⌘L** —— 与上面 `.format` / `.formatCode`
    /// 是同一条纪律：**按语境分属**。两者分属两个编辑器（数据库 SQL 编辑区 / 工作区
    /// Markdown 文档），同一个文档里不会同时成立（生效范围由 `MarkdownEditingScope`
    /// 限死在 Markdown ⇒ SQL 那边它根本不认这一下）。
    ///
    /// **冲突登记（先例 = `FR-EDIT-27` 的 ⌘D）**：⌘L 在本表里因此有**两个主人**，登记落点
    /// 就在这一条与 `.goToLine` 的说明里（本表是快捷键的唯一事实源）；需求行那一侧的偏差
    /// 登记属契约层（`Docs/**`，归前门），本片不动。
    ///
    /// ⚠️ `.toggleTask` **不挂任何菜单项**：`FR-EDIT-48` ⑤ 要的那条菜单项
    /// （`DoyahStudioCommands` 的「编辑」组）**刻意不写 `.keyboardShortcut`** —— 菜单项一旦挂上
    /// ⌘L，AppKit 只会认其中一个（另一项变摆设），SQL 侧的 `.goToLine` 就没了。
    case toggleTask

    case safeMode
    case confirmAllWrites

    /// 智能体审批与审计面板（FR-AI-09）。
    case agentAudit

    /// 统一外发日志面板（NFR-SEC-08）。
    case egressLog

    /// 新建浏览器页签（FR-EDIT-34）。
    case newBrowserTab

    /// 数据任务面板（FR-AI-05 / FR-AI-06 / FR-AI-08）。
    case dataTask

    /// 命令面板（FR-EDIT-25）：⌘K。
    ///
    /// 在此之前 ⌘K **只写在文件头的注释里"预留"**，帮助面板因此列不出它 ——
    /// 功能有、入口也做了，但用户不知道有这个入口，等于没有。
    case commandPalette

    case help

    /// 底部终端面板（显示 / 隐藏）。
    case terminal

    /// 查询归档（FR-EDIT-31）。
    case archive

    // 多光标与列编辑（FR-EDIT-27）。**注意**：需求原文写的是 ⌘D，
    // 但 ⌘D 已绑定「保存查询」（见 `.saveQuery`），所以这里用 ⌥⌘D，
    // 并把这条偏差登记在需求行与帮助面板里 —— 冲突是实测出来的，不静默改需求。
    case selectNextOccurrence
    case addCursorAbove
    case addCursorBelow

    var key: KeyEquivalent {
        switch self {
        case .execute: return .return
        case .stop: return "."
        case .check: return "e"
        case .executionPlan: return "p"
        case .openFile: return "o"
        case .saveFile: return "s"
        case .saveFileAs: return "s"
        case .saveQuery: return "d"
        case .savedQueries: return "d"
        case .history: return "h"
        case .find: return "f"
        case .replace: return "f"
        case .goToLine: return "l"
        // 与 `.goToLine` 同键（⌘L），按语境分属 —— 见上面 `case toggleTask` 的说明。
        case .toggleTask: return "l"
        case .indent: return "]"
        case .outdent: return "["
        case .clearEditor: return "k"
        case .format: return "f"
        case .formatCode: return "f"
        case .safeMode: return "s"
        case .confirmAllWrites: return "w"
        case .agentAudit: return "a"
        case .egressLog: return "e"
        case .newBrowserTab: return "b"
        case .dataTask: return "t"
        case .commandPalette: return "k"
        case .help: return "/"
        case .terminal: return "j"
        case .archive: return "r"
        case .selectNextOccurrence: return "d"
        case .addCursorAbove: return "\u{F700}"
        case .addCursorBelow: return "\u{F701}"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .execute, .openFile, .saveFile, .saveQuery, .indent, .outdent, .goToLine, .find, .commandPalette, .toggleTask:
            return [.command]
        case .stop:
            return [.command]
        case .check, .executionPlan, .saveFileAs, .savedQueries, .history, .clearEditor, .format, .formatCode, .agentAudit, .egressLog, .newBrowserTab, .dataTask, .help, .terminal, .archive:
            return [.command, .shift]
        case .replace, .safeMode, .confirmAllWrites,
             .selectNextOccurrence, .addCursorAbove, .addCursorBelow:
            return [.command, .option]
        }
    }

    /// 「⌘↩」这样的展示文本（tooltip 与帮助面板共用）。
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key.character {
        case "\u{F700}": text += "↑"
        case "\u{F701}": text += "↓"
        case "\u{F702}": text += "←"
        case "\u{F703}": text += "→"
        default: text += key == .return ? "↩" : String(key.character)
        }
        return text
    }

    /// 按钮 tooltip：`执行 SQL（⌘↩）`。
    ///
    /// 提示文案本身**不再内嵌按键**，统一由这里追加，避免两处各写一份。
    func help(_ title: String) -> String {
        "\(title)（\(display)）"
    }

    /// 这一条对应的 AppKit 修饰键。
    ///
    /// 为什么需要一次换算：菜单与 tooltip 走 SwiftUI 的 `EventModifiers`，而编辑器里的
    /// `performKeyEquivalent` 拿到的是 `NSEvent`（`NSTextView` 有焦点时 SwiftUI 的
    /// `.keyboardShortcut` 收不到按键，只能在那一层自己判）。两边判的必须是**同一份定义**
    /// —— 这里把修饰键换算过去，视图里就不再出现 `[.command]` 那种字面量。
    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    /// 这一次按键是不是这一条（键 + 修饰键都取本表）。
    ///
    /// 只比「**恰好**这些修饰键」，与 `.keyboardShortcut` 的语义一致：多按了别的修饰键
    /// （例如 `.toggleTask` 上的 ⇧⌘L）就不算它，按键照旧交还系统。
    func matches(_ event: NSEvent) -> Bool {
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard pressed == eventModifiers,
              let typed = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return typed == String(key.character).lowercased()
    }
}
