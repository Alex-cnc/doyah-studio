import SwiftUI
import DoyahCore

/// 提示的**弹出方向**。
///
/// **为什么需要"向上"这一档**（2026-09-27 人工点验发现）：提示是画在**宿主所在视图树内**的 overlay，
/// 而 overlay **不改变父视图的绘制顺序** —— 一旦它伸出父视图的边界，就会落在后面那些兄弟视图之下。
/// 查询工具条的下方正是 SQL 编辑器（`NSTextView`，由 AppKit 承载），于是"向下弹"的提示被它盖住
/// （需求提出者实测原话：「鼠标移到黄色图标上，看上去有一个 tip 出现，但是被编辑框挡住了」）。
/// 工具条里的提示因此必须用 `.above` —— 留在工具条/上下文栏这一条带内，那一段没有 AppKit 承载视图。
///
/// 上下文栏里那个 ⓘ 仍用默认的 `.below`（它的下方是工具条，纯 SwiftUI，向下弹一直是好的）。
enum HoverHintPlacement {
    /// 向下弹：宿主下方必须是纯 SwiftUI 区域（例如上下文栏的 ⓘ 之于工具条）。
    case below
    /// 向上弹：宿主下方有 AppKit 承载视图（编辑器 / 终端 / 结果网格）时用这一档。
    case above
}

/// **即时**悬停提示（替代系统 tooltip）。
///
/// 为什么不用 `.help`：系统 tooltip 的首次延迟是**秒级**的，实测反馈「悬停响应的时间太长了，
/// 应该是鼠标悬停即时弹出，我等了好几秒还以为没反应」。对"看一眼就走"的信息来说，
/// 即时出现才是这类提示的全部价值 —— 慢半拍就等于没有。
///
/// 做法：`onHover` + 一个画在**同一窗口内**的小面板（不是系统 tooltip 窗口）：
/// 立刻出现、移开即消失、`allowsHitTesting(false)` 不挡鼠标、位置贴着宿主上方或下方、与宿主右对齐。
///
/// **它是 overlay，不是浮层窗口** —— 所以"能不能被看见"取决于那一块区域上有没有别的兄弟视图：
/// 提示不会盖住后画的兄弟（编辑器就是后画的那个）。选方向的口径见 `HoverHintPlacement`。
private struct HoverHintModifier: ViewModifier {
    let text: String
    var placement: HoverHintPlacement = .below

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .topTrailing) {
                if isHovering, !text.isEmpty {
                    hint
                        // 让开宿主自身（宿主大约一行高），否则提示会盖住鼠标。
                        .offset(y: placement == .below ? HintStyle.offsetY : -HintStyle.offsetY)
                        .allowsHitTesting(false)
                        .zIndex(1)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: HintStyle.fadeDuration), value: isHovering)
    }

    private var hint: some View {
        Text(text)
            .font(Theme.font(.caption))
            .foregroundStyle(Theme.text(.primary))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Theme.surface(.raised))
                    .shadow(
                        color: .black.opacity(HintStyle.shadowAlpha),
                        radius: HintStyle.shadowRadius,
                        y: HintStyle.shadowOffsetY
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Theme.text(.tertiary).opacity(HintStyle.borderAlpha))
            )
    }
}

/// 提示框的几个与"内容无关"的度量（集中放，便于统一调）。
private enum HintStyle {
    /// 与宿主的间距：宿主大约一行高，提示整体挪开这一段才不盖住鼠标。
    /// 上下两个方向对称（向上一档是 `-offsetY`）。
    static let offsetY: CGFloat = 22
    static let fadeDuration: Double = 0.08
    static let shadowAlpha: Double = 0.18
    static let shadowRadius: CGFloat = 4
    static let shadowOffsetY: CGFloat = 2
    static let borderAlpha: Double = 0.25
}

extension View {
    /// 即时悬停提示（见 `HoverHintModifier`）。传空串则不显示。
    ///
    /// - Parameter placement: 弹出方向。**宿主下方是 AppKit 承载视图**（编辑器 / 终端 / 结果网格）时必须给
    ///   `.above`，否则提示会被那个视图盖住 —— 具体见 `HoverHintPlacement`。
    func hoverHint(_ text: String, placement: HoverHintPlacement = .below) -> some View {
        modifier(HoverHintModifier(text: text, placement: placement))
    }
}
