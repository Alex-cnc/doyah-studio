import AppKit
import SwiftUI

import DoyahCore

/// **「回到消息底部」浮动入口**（详设 §3.39）—— 一行胶囊，落在对话区底部**保留窄条**里、可点。
///
/// ## 形态口径（判据量得到）
///
/// · **一行、22pt**（`AgentJumpToBottom.barHeight`，落在 20–24 的带里）：字取 `monoSmall`、
///   悬停给一句提示，宽度按文字收（`.fixedSize()`）—— 它不是一条通栏的装饰线；
/// · **胶囊 + 半透明毛玻璃**（`.ultraThinMaterial` + 一圈发丝描边）：条目落在空条上，
///   胶囊是本视图里唯一有底色的东西 —— 一眼看出「这里有一个可点的入口」，而不是又一块正文；
/// · **可点**：点击面是**真 `NSButton`**（`AgentJumpToBottomClickButton`），不是
///   `onTapGesture` —— 手势在离屏宿主里点不动（`DialogActionRowProbeTests` 已登记），
///   那样契约「点它 ⇒ 回到消息底部并恢复跟随」就只能靠人手点。
///
/// ## 为什么单独一件
///
/// 判据要量**它的高度**、**它底边到对话区底边的距离**，还要点它一下看滚动去了哪
/// （`AgentJumpToBottomProbeTests`）。挂在 `AgentChatView` 的私有 `@ViewBuilder` 里，
/// 探针既挂不起来也点不动。
struct AgentJumpToBottomBar: View {

    /// 点击后做什么（由宿主接到「滚到底 + 恢复跟随」）。
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 高度 = 22pt（判据按 Core 的常量对账，不在这里另写一个数）。
    static let height: CGFloat = AgentJumpToBottom.barHeight

    private static let font = Theme.font(.monoSmall)

    /// 文案（语言表 `agentChatJumpToBottom`：中文「↓ 回到消息底部」/ 英文「↓ Jump to latest」）。
    private var label: String { L(.agentChatJumpToBottom) }

    var body: some View {
        Text(label)
            .font(Self.font)
            .foregroundStyle(Theme.text(.secondary))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.m)
            .frame(height: Self.height)
            // 胶囊底 + 半透明毛玻璃：浮层不遮死下面的字（契约：不遮内容）。
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.hairline(colorScheme), lineWidth: Metrics.hairline)
            }
            .overlay {
                AgentJumpToBottomClickTarget(help: label, onActivate: onActivate)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }
}

/// 对话区底下那一格：滚动视口 + **保留窄条**（只在入口出现时占位）。
///
/// 为什么单独做成一件：契约「入口不遮正文」落在**布局关系**上 —— 条是视口**下面的兄弟**，
/// 视口到条的上沿为止，所以入口压不到任何一行正文（不是靠半透明遮一下）。
/// 把这段关系摊在 `AgentChatView` 的私有 `@ViewBuilder` 里，判据就只能读整页读数，
/// 说不出「入口在视口之外」。
///
/// ## 三件事都写在这一处
///
/// ① **不出现 ⇒ 条不存在（高 0）**：`if visible` 里的分支整个不建，`VStack` 少一格，
///    视口立刻拿回那 40pt（判据②量「隐藏态视口高 == 无入口基线的视口高」）；
/// ② **出现/消失只发生一次高度跳变**：分支上挂 `.transaction { $0.animation = nil }` ——
///    布局一处到位，不逐帧插值（判据④采样的中间值必须是 0 个）；
/// ③ **量得到**：条自己带一块透明标记（`AgentJumpToBottomStripMarker`），判据按类型读它的高，
///    条不在时读 0（不是拿整页高度去推算）。
struct AgentJumpToBottomReservedStrip<Content: View>: View {

    /// `false` = 不出现（连视图都不建 ⇒ 判据读到的高度就是 0）。
    let visible: Bool
    let onActivate: () -> Void
    private let content: () -> Content

    init(visible: Bool,
         onActivate: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.visible = visible
        self.onActivate = onActivate
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
            // **条件占位**：入口不在时这一格整个不存在（高 0，空间还给正文）。
            // 「出现 ⇒ 视口矮一条 ⇒ 关不掉」那条反对意见不成立，理由见 `AgentJumpToBottom.stripHeight`。
            if visible {
                ZStack(alignment: .bottom) {
                    AgentJumpToBottomBar(onActivate: onActivate)
                        // 底边距对话区底边 = 块间距（`Spacing.m`）；上方留 4pt 呼吸。
                        .padding(.bottom, AgentJumpToBottom.bottomGap)
                }
                .frame(height: AgentJumpToBottom.stripHeight)
                .frame(maxWidth: .infinity)
                .background(AgentJumpToBottomStripMarker())
                // 高度变化**一次到位**：不插值、不逐帧（契约④）。
                .transaction { $0.animation = nil }
            }
        }
    }
}

/// 保留窄条的**读数标记**（判据按这个类型量条高；条不在 ⇒ 找不到 ⇒ 读 0）。
///
/// 与尾部记号（`AgentTranscriptTailAnchor`）同一手法：几何事实由一个真 `NSView` 报出来，
/// 判据不去拿「整页高度 − 别的高度」推算 —— 那是同一份布局的第二个答案。
final class AgentJumpToBottomStripView: NSView {}

struct AgentJumpToBottomStripMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentJumpToBottomStripView { AgentJumpToBottomStripView() }
    func updateNSView(_ view: AgentJumpToBottomStripView, context: Context) {}
}

/// 入口的**点击面**：一整块透明 `NSButton`，铺满胶囊。
///
/// 为什么不写 `Button { } label: { … }`：SwiftUI 的 `Button` 在离屏宿主里不落 `NSButton`
/// （`DialogActionRowProbeTests` 实测登记），判据点不动它。这个包装是**真的** `NSButton`：
/// 生产里点它、探针里 `performClick(nil)` 点它，走的是同一条 action。
struct AgentJumpToBottomClickTarget: NSViewRepresentable {

    let help: String
    let onActivate: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivate: onActivate) }

    func makeNSView(context: Context) -> AgentJumpToBottomClickButton {
        let button = AgentJumpToBottomClickButton()
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

    func updateNSView(_ view: AgentJumpToBottomClickButton, context: Context) {
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

/// 入口的按钮本体（**单独一个类型**：判据按类型找它，量到的就是入口的高度与位置）。
final class AgentJumpToBottomClickButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
