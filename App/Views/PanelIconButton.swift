import AppKit
import SwiftUI

/// 面板工具条上的**图标动作**（真 `NSButton`）。
///
/// ## 为什么不是 SwiftUI `Button`
///
/// 与 `ResultFilterPopup`（真 `NSPopUpButton`）/ `TitleBarSearchBox`（整框 AppKit）同一条理由：
/// 离屏宿主里 SwiftUI `Button` **不落** `NSButton`、`NSHostingView` 的无障碍树也**不构建**
/// （本机实测：合成鼠标事件投进去 `count` 不动、`accessibilityChildren()` = 0；
/// 见 `TestsUISnapshot/DialogActionRowProbeTests` 文件头那一段）。
/// ⇒ 「这一枚点了到底发生什么」在自动化里**一次都量不到**，只能靠人点；而「导出 / 复制 / 清空」
/// 恰恰是验收要点里写着要点的三枚。
///
/// 换成真 `NSButton` 之后，探针 `performClick(nil)` 走的就是用户点它那条 action 路径
/// （不是另开一个入口，也不是拿实现里的闭包自己调一遍）。
///
/// ## 外观口径
///
/// 无边框 + 只画图标 + 次要文字色（与原先 SwiftUI `Image(systemName:)` 那一版同形）；
/// 尺寸交给符号配置（`pointSize` 跟正文字号），不写死宽高 —— 语言 / 字号变了它自己跟。
/// 提示同时挂 `toolTip`（鼠标悬停）与无障碍标签（读屏），与原先 `.help(...)` + `.accessibilityLabel(...)`
/// 两件事一一对应。
struct PanelIconButton: NSViewRepresentable {

    let systemName: String
    /// 悬停提示（鼠标停上去那句）。
    let help: String
    /// 读屏标签；不给时用 `help`（图标按钮自身没有文字，缺了它读屏只会念「按钮」）。
    var label: String? = nil
    /// 正文字号 —— 与所在那一条的 `Theme.font(.caption)` 同源，图标不会比字大一圈。
    var pointSize: CGFloat = 11
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        button.setAccessibilityRole(.button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: label ?? help
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        button.toolTip = help
        button.setAccessibilityLabel(label ?? help)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func fire() {
            action()
        }
    }
}
