import AppKit
import DoyahCore
import SwiftUI

/// 对象树里那几种「不是对象行」的行（正在加载 / 加载失败 / 空态）。
///
/// ## 为什么要单独成文件
///
/// 这三种行原先由 `ObjectTreeView` 里一个 `private func placeholderRow(…)` 画。失败那一行还挂着
/// 「重试」入口（`FR-STD-DB-META-006` ③）—— 而**入口是 SwiftUI `Button`**：离屏宿主里它不落
/// `NSButton`（同 `PanelIconButton` 文件头的实测），于是「点了重试真的重新取了一次数吗」
/// 只能靠人点。搬出来之后，探针能把这一行**单独**装进活宿主，按下那枚真按钮。
///
/// ## 重试入口为什么是文字按钮
///
/// 这里同时是「可读错误」与「怎么办」的并置：一枚孤零零的 ↻ 在红字旁边到底指什么，得靠悬停才知道；
/// 且纯图标按钮还得另配 help / 无障碍标签 —— 文字本身就够了。
/// 出不出这枚入口**不在这里判**（判定全在 `Core/ObjectTreeRetry`，视图只把结果传进来）。
struct ObjectTreePlaceholderRow: View {

    let text: String
    /// 缩进层级（失败那一行画在它父节点下一层）。
    let depth: Int
    let systemImage: String?
    let color: Color
    /// 重试入口（`nil` = 这一档不出入口，见 `ObjectTreeRetry.evaluate`）。
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.font(.caption))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(Theme.font(.caption))
                .foregroundStyle(color)
                .lineLimit(3)
                .textSelection(.enabled)
            if let retry {
                ObjectTreeRetryButton(title: L(.commonRetry), action: retry)
            }
        }
        .padding(.leading, CGFloat(depth) * Metrics.listIndent + Metrics.listIndent + Spacing.xs)
    }
}

/// 失败那一行上的「重试」——**真 `NSButton`**（带下划线的文字按钮）。
///
/// 为什么不是 SwiftUI `Button`：离屏宿主里 SwiftUI 按钮不落 `NSButton` ⇒ 探针 `performClick(nil)`
/// 无从下手，「点了之后到底有没有重新取一次数」只能靠人点。
/// 换成真按钮之后，探针按下的就是用户按的那一条 action 路径（不是另开一个入口）。
struct ObjectTreeRetryButton: NSViewRepresentable {

    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .noImage
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        button.setAccessibilityRole(.button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        button.toolTip = title
        button.setAccessibilityLabel(title)
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
