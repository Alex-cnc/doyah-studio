import Foundation

// MARK: - 对话框动作的档位

/// 一枚对话框动作在**语义**上的档位（`FR-STD-WS-UI-014`）。
///
/// 为什么不直接沿用 `ButtonRole`：`ButtonRole` 是 SwiftUI 的类型，而「取消只有一枚、
/// 主按只有一枚、破坏性动作不许抢回车」这些判定要在 Core 里就能跑（`Tests/` 里逐条判红）。
/// 视图层只在最后一步把这里的档位翻成 `ButtonRole` / `KeyboardShortcut`。
public enum DialogActionRole: String, CaseIterable, Sendable {
    /// 取消 / 关闭 / 稍后 —— Esc 的落点。
    case cancel
    /// 不带语义的第三枚（例如「浏览…」「恢复默认」）。
    case neutral
    /// 这条对话框的主按 —— 回车的落点。
    case primary
    /// 会不可逆地改东西的那一枚（删除 / 丢弃）。
    case destructive
}

/// 键盘快捷键的落点（视图层翻成 `KeyboardShortcut.defaultAction` / `.cancelAction`）。
public enum DialogActionShortcut: String, Sendable {
    case `default`
    case cancel
}

/// 一枚对话框动作的声明。
public struct DialogActionSpec: Identifiable, Equatable, Sendable {
    public let id: String
    /// 可见文字。空 / 只有空白 ⇒ 这是一枚**纯图标动作**（对话框里不许出现的东西）。
    public let title: String
    /// 图标名（可空 —— 没有图标也是合法的文字按钮）。
    public let systemImage: String?
    public let role: DialogActionRole
    public let isEnabled: Bool

    public init(
        id: String,
        title: String,
        systemImage: String? = nil,
        role: DialogActionRole = .neutral,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
    }

    /// 去掉两端空白之后的可见文字。
    ///
    /// 为什么要 trim：「 」这种只有空格的标题在渲染上就是一枚无字图标，
    /// 而 `title.isEmpty` 判不出它来 —— 判据要判到看得见的东西上。
    public var visibleTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 纯图标动作：没有可见文字。对话框 / 表单里**不许有**这种动作。
    public var isIconOnly: Bool {
        visibleTitle.isEmpty
    }
}

// MARK: - 违规

/// 一条违规。**每一档都带涉事的 id** —— 「有几个坏了」这种报告没法定位。
public enum DialogActionViolation: Equatable, Sendable {
    /// 纯图标动作（无可见文字）。对话框里省不出空间，只省掉了「这是什么」。
    case iconOnly(ids: [String])
    /// 同一行里两枚动作文字相同 —— 用户与截图都分不清点的是哪一枚。
    case duplicateTitle(title: String, ids: [String])
    /// 两条取消：Esc 该关谁说不清。
    case duplicateCancel(ids: [String])
    /// 可关的对话框没有取消档 —— 用户只能强行关窗。
    case missingCancel
    /// 两枚主按：回车该按哪一个说不清。
    case duplicatePrimary(ids: [String])

    /// 机器可读的码（日志与判据读它，不读人话）。
    public var code: String {
        switch self {
        case .iconOnly: return "dialog.action.iconOnly"
        case .duplicateTitle: return "dialog.action.duplicateTitle"
        case .duplicateCancel: return "dialog.action.duplicateCancel"
        case .missingCancel: return "dialog.action.missingCancel"
        case .duplicatePrimary: return "dialog.action.duplicatePrimary"
        }
    }

    /// 涉事 id（`missingCancel` 没有 id —— 它缺的正是那一枚）。
    public var ids: [String] {
        switch self {
        case .iconOnly(let ids): return ids
        case .duplicateTitle(_, let ids): return ids
        case .duplicateCancel(let ids): return ids
        case .duplicatePrimary(let ids): return ids
        case .missingCancel: return []
        }
    }
}

// MARK: - 投影结果

/// 一行对话框动作**该长什么样**：画哪几枚、按什么次序、谁是回车、谁是 Esc，以及哪里违规。
public struct DialogActionLayout: Equatable, Sendable {
    /// 可以画的（有可见文字的）动作，已按口径排好序。
    public let accepted: [DialogActionSpec]
    /// 被拒的（纯图标）动作 —— 不画。**不静默吞掉**：`violations` 里同时留一条。
    public let rejected: [DialogActionSpec]
    /// 回车落点。
    public let defaultActionID: String?
    /// Esc 落点。
    public let cancelActionID: String?
    /// 违规清单（空 = 合规）。
    public let violations: [DialogActionViolation]

    public var isCompliant: Bool { violations.isEmpty }

    /// 某一枚动作该挂哪个快捷键（`nil` = 不挂）。
    public func shortcut(for id: String) -> DialogActionShortcut? {
        if id == defaultActionID { return .default }
        if id == cancelActionID { return .cancel }
        return nil
    }
}

// MARK: - 口径

/// 对话框动作的口径（唯一一处）。
///
/// ## 为什么收在一处
///
/// 需求原文是「Sheet / Form 内无纯图标按钮，取消为 `role: .cancel`」。这句话本该是**结构**，
/// 但此前它只是一句文案：25 个对话框各自手搭动作行，取消按钮靠 `.keyboardShortcut(.cancelAction)`
/// 凑 Esc、ButtonRole 一个都没写，于是「Esc 能关」在、而「这是取消」不在（读屏与系统样式都拿不到）。
/// 收成一份纯函数投影之后，三件事同时变成可判的：**画哪几枚 / 什么次序 / 谁拿回车与 Esc**。
///
/// ## 三条会让人掉进去的口径
///
/// 1. **次序是排出来的，不是声明顺序**：取消在最左（macOS 口径），主按在最右（回车的位置）。
///    破坏性动作排在主按之前 —— 它永远不是回车，把它摆到最右会让人「顺手一回车就删了」。
/// 2. **纯图标是被拒，不是被修**：给一个空标题的按钮补一句自动文案，等于让编译期猜语义；
///    正确处置是把它挡在门外（不画 + 违规），让调用点自己补文字。
/// 3. **同名两条也是违规**：两枚「保存」在截图与读屏里无法区分，这不是美观问题。
public enum DialogButtonPolicy {

    /// 把一份动作声明投成「该画的那一行」。
    ///
    /// - Parameters:
    ///   - specs: 声明顺序（次序由本函数决定，不由声明顺序决定）。
    ///   - dismissible: 这条对话框能不能被用户关掉（能关就必须有取消档）。
    public static func resolve(_ specs: [DialogActionSpec], dismissible: Bool) -> DialogActionLayout {
        let rejected = specs.filter(\.isIconOnly)
        let accepted = specs.filter { !$0.isIconOnly }

        var violations: [DialogActionViolation] = []
        if !rejected.isEmpty {
            violations.append(.iconOnly(ids: rejected.map(\.id)))
        }

        // 同名：按可见文字分组，保持首次出现的次序（确定性）
        var titleOrder: [String] = []
        var titleIDs: [String: [String]] = [:]
        for spec in accepted {
            let key = spec.visibleTitle
            if titleIDs[key] == nil { titleOrder.append(key) }
            titleIDs[key, default: []].append(spec.id)
        }
        for title in titleOrder where (titleIDs[title]?.count ?? 0) > 1 {
            violations.append(.duplicateTitle(title: title, ids: titleIDs[title] ?? []))
        }

        let cancels = accepted.filter { $0.role == .cancel }
        if cancels.count > 1 {
            violations.append(.duplicateCancel(ids: cancels.map(\.id)))
        } else if cancels.isEmpty, dismissible {
            violations.append(.missingCancel)
        }

        let primaries = accepted.filter { $0.role == .primary }
        if primaries.count > 1 {
            violations.append(.duplicatePrimary(ids: primaries.map(\.id)))
        }

        let ordered = cancels
            + accepted.filter { $0.role == .neutral }
            + accepted.filter { $0.role == .destructive }
            + primaries

        return DialogActionLayout(
            accepted: ordered,
            rejected: rejected,
            defaultActionID: primaries.first?.id,
            cancelActionID: cancels.first?.id,
            violations: violations
        )
    }
}
