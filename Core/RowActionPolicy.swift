import Foundation

/// 列表行 / 分组标题上的**行内动作**（`FR-STD-WS-UI-013`：悬停才出、常驻不占位）。
///
/// 这一处只回答三个问题，视图不再各写一遍：
///   1. **这一行该有哪几枚**（目录 3 枚：新建 / 删除 / 改名；文件与符号链接 2 枚：删除 / 改名）；
///   2. **此刻画不画**（悬停才画；正在行内改名的那一行例外 —— 见 `isVisible`）；
///   3. **标识怎么拼**（探针按标识数「这一行画了几枚动作」，两个面共用同一套拼法 ⇒
///      不会出现「一处叫这个名字、一处叫那个名字，探针只数得到一半」）。
///
/// 放进 Core 的理由与其它模块一致：口径能单测；而界面探针也照着**同一份**口径去数像素 ——
/// 「目录三枚、文件两枚」若在视图与判据里各写一份，改一处忘另一处这种事没有任何门禁看得见。
public enum RowAction: String, CaseIterable, Sendable, Hashable {
    case create = "plus"
    case delete = "minus"
    case rename = "pencil"

    /// SF Symbol 名（与标识里那一段同字：`plus` / `minus` / `pencil` —— 省掉一层映射表）。
    public var symbolName: String { rawValue }
}

public enum RowActionPolicy {

    /// 行内动作的标识前缀。探针按它扫「这一行有没有画动作、画了几枚」。
    public static let identifierPrefix = "workspace-action-"

    /// 分组标题上那枚「＋」的标识前缀（同一套口径：分组标题也是「悬停才出」）。
    public static let groupAddIdentifierPrefix = "connection-group-plus-"

    /// 这一行该有哪几枚。顺序 = 画出来的顺序（左→右：新建 · 删除 · 改名）。
    ///
    /// 符号链接按文件处理（2 枚）：它不可展开、也不该让人往里新建东西。
    public static func actions(isDirectory: Bool) -> [RowAction] {
        isDirectory ? [.create, .delete, .rename] : [.delete, .rename]
    }

    /// 画不画。
    ///
    /// **悬停才画**是需求 ① 的全部内容（未悬停 ⇒ 动作数 0，行宽也不因它变）。
    /// 一个例外：**正在行内改名**的那一行始终画 —— 鼠标一移开按钮就没了，
    /// 用户就再也点不到这一行上「改名之外」的入口（原本就这么定的，本片不改它，只是把它写进唯一口径里）。
    /// 选中**不是**理由：选中一行再把鼠标移开，动作必须跟着收起，否则侧栏里会留下一条常驻图标行。
    public static func isVisible(isHovered: Bool, isRenaming: Bool) -> Bool {
        isHovered || isRenaming
    }

    /// 某一枚动作在某一行的标识（唯一出处：视图与探针都从这里取）。
    public static func accessibilityIdentifier(_ action: RowAction, path: String) -> String {
        identifierPrefix + action.rawValue + "-" + path
    }

    /// 分组标题上那枚「＋」的标识（唯一出处）。
    public static func groupAddAccessibilityIdentifier(_ groupID: String) -> String {
        groupAddIdentifierPrefix + groupID
    }
}
