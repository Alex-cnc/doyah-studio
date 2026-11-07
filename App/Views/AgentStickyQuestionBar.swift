import AppKit
import SwiftUI

import DoyahCore

/// **当前轮用户问题的吸顶条**（详设 §3.34）—— 一行、钉在对话区顶端、点一下跳回原话。
///
/// ## 三条形态口径
///
/// · **一行**（高度 = `AgentStickyQuestion.barHeight` = 20pt，契约① 上限 28pt）：
///   问题多长都只占一行，宽度吃不下就中间省略（`.truncationMode(.middle)`：头尾都还在，
///   人一眼能认出是哪一句）；
/// · **不透明**：它压住的是对话区顶部那一格（滚动区在它**下面**，见 `AgentChatView.transcript`），
///   底色取 `Theme.surface(.content)`，滚过去的字不会从条后面透出来；
/// · **可点**：点击面是**真 `NSButton`**（`AgentStickyClickTarget`），不是 `onTapGesture`
///   —— 手势在离屏宿主里点不动（`DialogActionRowProbeTests` 已登记），那样契约③
///   「点吸顶条 ⇒ 滚回该条用户消息」就只能靠人手点。
///
/// ## 为什么单独一件
///
/// 判据要量**它的高度**与**它点下去之后滚动去了哪**（`AgentChatStickyQuestionProbeTests`）。
/// 挂在 `AgentChatView` 的私有 `@ViewBuilder` 里，探针既挂不起来也点不动。
struct AgentStickyQuestionBar: View {

    /// 用户的原话（未一行化 —— 本视图自己折，`help` 里给全文）。
    let text: String
    /// 点击后做什么（由宿主接到「滚回这条消息」）。
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 高度 = 一行（与 Core 的判定常量同一个数，判据读 `AgentStickyQuestion.barHeight`）。
    static let height: CGFloat = AgentStickyQuestion.barHeight

    private static let font = Theme.font(.mono)

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 与消息流里用户行同一个字形、同一列（§5.3.8.1 ②）：一眼认得出「这是我说的话」。
            Text(">")
                .font(Self.font)
                .foregroundStyle(Theme.chat(.user, colorScheme))
                .frame(width: Spacing.l, alignment: .leading)
            Text(AgentStickyQuestion.lineText(text))
                .font(Self.font)
                .foregroundStyle(Theme.chat(.user, colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                // 悬停给全文（契约①：一行装不下时，全文要能看见）。
                .help(text)
            Spacer(minLength: Spacing.s)
            // 「点了会往上走」的提示字形：不给它，这一行看起来只是标题，没人会去点。
            Text("↑").font(Self.font).foregroundStyle(Theme.text(.tertiary))
        }
        .padding(.horizontal, Spacing.l)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 不透明底：条下面就是滚动区，滚过去的正文不许透出来。
        .background(Theme.surface(.content))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairline(colorScheme))
                .frame(height: Metrics.hairline)
        }
        .overlay {
            AgentStickyClickTarget(help: L(.agentChatStickyQuestionJump), onActivate: onActivate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L(.agentChatStickyQuestionJump) + "：" + AgentStickyQuestion.lineText(text))
    }
}

/// 对话区那一列的**形状**：吸顶条（出现时）+ 内容区（滚动区）。
///
/// 为什么把它单独做成一件：契约②（不遮内容）与契约④（不重排行）都落在**布局关系**上 ——
/// 条是滚动区**上面**的兄弟视图，视口从条下面起，内容一行都不用让。把这段关系摊在
/// `AgentChatView` 的私有 `@ViewBuilder` 里，判据就只能读整页读数，说不出「行没被重排」。
/// 单独成件之后，探针能把**同一份**布局配着真行（思考区 / 工具块）挂起来，量两边的行高。
struct AgentStickyQuestionColumn<Content: View>: View {

    /// `nil` = 不吸顶（条不出现，内容从顶格开始）。
    let sticky: AgentStickyQuestion?
    /// 点条之后做什么（宿主接到「滚回这条消息」）。
    let onActivate: () -> Void
    private let content: () -> Content

    init(sticky: AgentStickyQuestion?,
         onActivate: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.sticky = sticky
        self.onActivate = onActivate
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if let sticky {
                AgentStickyQuestionBar(text: sticky.text, onActivate: onActivate)
            }
            content()
        }
    }
}

/// 吸顶条的**点击面**：一整块透明 `NSButton`，铺满条的高度。
///
/// 为什么不用 `Button { } label: { ... }`：SwiftUI 的 `Button` 在离屏宿主里不落 `NSButton`
/// （`DialogActionRowProbeTests` 实测登记），判据点不动它。这个包装是**真的** `NSButton`：
/// 生产里点它、探针里 `performClick(nil)` 点它，走的是同一条 action。
struct AgentStickyClickTarget: NSViewRepresentable {

    let help: String
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivate: onActivate) }

    func makeNSView(context: Context) -> AgentStickyClickButton {
        let button = AgentStickyClickButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate)
        button.toolTip = help
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(help)
        return button
    }

    func updateNSView(_ view: AgentStickyClickButton, context: Context) {
        context.coordinator.onActivate = onActivate
        view.toolTip = help
        view.setAccessibilityLabel(help)
    }

    final class Coordinator: NSObject {
        var onActivate: () -> Void
        init(onActivate: @escaping () -> Void) { self.onActivate = onActivate }
        @objc func activate() { onActivate() }
    }
}

/// 吸顶条的按钮本体（**单独一个类型**：判据按类型找它，量到的就是条的点击面高度）。
final class AgentStickyClickButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
