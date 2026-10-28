import SwiftUI
import DoyahCore

/// 对话框底部的**动作行**（`FR-STD-WS-UI-014`）。
///
/// ## 它取代了什么
///
/// 此前每个 Sheet 都自己写 `HStack { Spacer(); DialogActionButton(...) ... }`：取消按钮
/// 只挂 `.keyboardShortcut(.cancelAction)` 凑 Esc、ButtonRole 一枚都没写，次序也各写各的。
/// 于是「Esc 能关」在、「这是取消」不在（系统给取消按钮的样式与读屏语义都拿不到），
/// 而且每加一个对话框就多一处可以走偏的地方。
///
/// 现在一行只填**声明**，画什么由 `DialogButtonPolicy` 一处决定：
/// 次序（取消最左 / 主按最右）、回车与 Esc 的落点、纯图标被拒、同名被拒。
///
/// ## 不许绕开它
///
/// `Tests/DialogButtonSourceTests` 扫 `App/Views/*Sheet*.swift`：不许出现纯图标的动作、
/// 取消/关闭类动作必须带 `role: .cancel`。要在对话框里加动作就走这里。
struct DialogActionRow: View {

    /// 动作声明（次序由口径决定，不由此数组的次序决定）。
    let actions: [DialogActionSpec]

    /// 这条对话框能否被用户关掉（能关就必须有取消档 —— 否则 Esc 无处可去）。
    var dismissible: Bool = true

    /// 前面那根 `Spacer`（对话框底部一般在最右；左对齐的行把它关掉）。
    var pushesTrailing: Bool = true

    /// 按 id 回传被点的动作。
    let perform: (String) -> Void

    var body: some View {
        let layout = DialogButtonPolicy.resolve(actions, dismissible: dismissible)
        HStack(spacing: Spacing.s) {
            if pushesTrailing {
                Spacer(minLength: 0)
            }
            ForEach(layout.accepted) { spec in
                actionButton(spec, layout: layout)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ spec: DialogActionSpec, layout: DialogActionLayout) -> some View {
        if let shortcut = layout.shortcut(for: spec.id) {
            base(spec).keyboardShortcut(shortcut == .default ? .defaultAction : .cancelAction)
        } else {
            base(spec)
        }
    }

    private func base(_ spec: DialogActionSpec) -> some View {
        DialogActionButton(
            systemName: spec.systemImage ?? Self.fallbackSystemName(for: spec.role),
            title: spec.title,
            role: Self.buttonRole(for: spec.role),
            isDisabled: !spec.isEnabled
        ) {
            perform(spec.id)
        }
    }

    /// 没给图标时按档位补一枚 —— 对话框里图标只是定位用的，语义由文字负责。
    static func fallbackSystemName(for role: DialogActionRole) -> String {
        switch role {
        case .cancel: return "xmark.circle"
        case .primary: return "checkmark"
        case .destructive: return "trash"
        case .neutral: return "ellipsis.circle"
        }
    }

    /// 档位 → `ButtonRole`：**取消档就是 `role: .cancel`**（这条需求的原话），破坏性给 `.destructive`。
    static func buttonRole(for role: DialogActionRole) -> ButtonRole? {
        switch role {
        case .cancel: return .cancel
        case .destructive: return .destructive
        case .neutral, .primary: return nil
        }
    }
}
