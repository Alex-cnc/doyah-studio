import SwiftUI
import DoyahCore

/// 「模型档位」这一节（`FR-AI-32` 多 Provider / 多模型的配置面）。
///
/// 为什么单拎成一个视图：这一节的动作（新增 / 复制 / 删除 / 改名 / 测试连接）要能被
/// 离屏探针**按真控件**量到（`TestsUISnapshot/AgentProfileEditorProbeTests.swift`）。
/// 挂在设置面板里时它只是一个 `Section`，拆出来不改变任何布局。
///
/// 口径：
/// - 档 = 端点 + 模型名 + 超时 + **一把独立密钥**（密钥本体在钥匙串，档里只存条目键）；
/// - 切档 = 换一整套（下一次请求就用新档，不必重启）；
/// - 测试连接测的是**这一档的草稿**（眼前这份），不是盘上那份。
struct AgentProfileEditor: View {

    let profiles: [AgentProfile]
    @Binding var selectedProfileID: String?
    @Binding var name: String
    /// 还能不能再加一档（到上限 `AgentConfiguration.maximumProfileCount` 就为假）。
    let canAdd: Bool
    /// 能不能删（只剩一档时为假 —— 删到空等于没有可用配置）。
    let canDelete: Bool
    /// 增删改的结论行（回落到哪一档 / 为什么删不了）。
    let line: String?
    /// 测试连接的结论行（四档结局的人话）。
    let testLine: String?
    /// 测试在途：按钮置灰（同一档不许并发压两次）。
    let isTesting: Bool

    var onAdd: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}
    var onTest: () -> Void = {}

    var body: some View {
        Group {
            AgentProfilePicker(items: profiles,
                               selection: $selectedProfileID,
                               label: L(.agentProfileSection))

            TextField(L(.agentProfileName), text: $name)
                .accessibilityIdentifier("agent-profile-name")

            HStack(spacing: Spacing.s) {
                AgentProfileActionButton(
                    title: L(.agentProfileAdd),
                    isEnabled: canAdd,
                    help: canAdd ? L(.agentProfileAdd)
                        : L(.agentProfileLimitReached, Int64(AgentConfiguration.maximumProfileCount)),
                    action: onAdd
                )
                .disabled(!canAdd)
                AgentProfileActionButton(
                    title: L(.agentProfileDuplicate),
                    isEnabled: canAdd && selectedProfileID != nil,
                    help: L(.agentProfileDuplicate),
                    action: onDuplicate
                )
                .disabled(!(canAdd && selectedProfileID != nil))
                AgentProfileActionButton(
                    title: L(.agentProfileDelete),
                    isEnabled: canDelete,
                    help: canDelete ? L(.agentProfileDelete) : L(.agentProfileLastOne),
                    isDestructive: true,
                    action: onDelete
                )
                .disabled(!canDelete)
                AgentProfileActionButton(
                    title: L(.agentProfileTest),
                    isEnabled: !isTesting && selectedProfileID != nil,
                    help: L(.agentProfileTest),
                    action: onTest
                )
                .disabled(isTesting || selectedProfileID == nil)
            }

            if let testLine {
                Text(testLine)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agent-profile-test-line")
            }
            if let line {
                Text(line)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agent-profile-line")
            }
            Text(L(.agentProfileKeyHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 档位那一节的四枚动作（**真 `NSButton`**）：新增 / 复制 / 删除 / 测试此档。
///
/// 与 `AgentApprovalActionButton` 同一条实测：离屏宿主里 SwiftUI `Button` **不落** `NSButton`、
/// 无障碍树也不构建 ⇒「这一枚在只剩一档时是不是灰的」「点下去派发没派发」在自动化里一次都量不到。
/// 这四枚动作恰恰是 `FR-AI-32` 判据 ② / ④ 的正体（删到空必须拒、在途必须灰），
/// 所以它们落成 AppKit 控件；外观与 `.bordered` + `.controlSize(.small)` 同形。
struct AgentProfileActionButton: NSViewRepresentable {

    let title: String
    var isEnabled: Bool = true
    var help: String = ""
    var isDestructive: Bool = false
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.title = title
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        context.coordinator.isEnabled = isEnabled
        apply(to: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.isEnabled = isEnabled
        if button.title != title { button.title = title }
        apply(to: button)
    }

    private func apply(to button: NSButton) {
        button.isEnabled = isEnabled
        button.toolTip = help.isEmpty ? nil : help
        button.setAccessibilityLabel(title)
        button.contentTintColor = isDestructive ? .systemRed : nil
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        /// 灰着的那一枚**不派发**：AppKit 的 `performClick` 一般已经挡住，这里再挡一道 ——
        /// 「看似灰着、实际还能点」是这类动作最坏的坏法（删掉最后一档就再没有可用配置）。
        var isEnabled = true

        init(action: @escaping () -> Void) { self.action = action }

        @objc func fire() {
            guard isEnabled else { return }
            action()
        }
    }
}

/// 档选择器（**真 `NSPopUpButton`**）。
///
/// 为什么不用 SwiftUI `Picker`：离屏宿主里 `Picker` 不落 `NSPopUpButton` ⇒
/// 「下拉里到底是不是三档、选中的是哪一档」在自动化里量不到（本仓 `PanelIconButton` /
/// `AgentApprovalActionButton` 同一类实测）。档清单本身是 `FR-AI-32` 的正体，
/// 所以它落成 AppKit 控件。
struct AgentProfilePicker: NSViewRepresentable {

    let items: [AgentProfile]
    @Binding var selection: String?
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.controlSize = .small
        popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.pick(_:))
        popUp.setAccessibilityLabel(label)
        popUp.setAccessibilityIdentifier("agent-profile-picker")
        rebuild(popUp)
        return popUp
    }

    func updateNSView(_ popUp: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if popUp.itemTitles != items.map(displayName) {
            rebuild(popUp)
        } else {
            applySelection(popUp)
        }
    }

    private func displayName(_ profile: AgentProfile) -> String {
        profile.name.isEmpty ? profile.id : profile.name
    }

    private func rebuild(_ popUp: NSPopUpButton) {
        popUp.removeAllItems()
        for profile in items {
            let item = NSMenuItem(title: displayName(profile), action: nil, keyEquivalent: "")
            item.representedObject = profile.id
            popUp.menu?.addItem(item)
        }
        applySelection(popUp)
    }

    private func applySelection(_ popUp: NSPopUpButton) {
        guard let selection, let index = items.firstIndex(where: { $0.id == selection }) else { return }
        if popUp.indexOfSelectedItem != index { popUp.selectItem(at: index) }
    }

    final class Coordinator: NSObject {
        var selection: Binding<String?>

        init(selection: Binding<String?>) { self.selection = selection }

        @objc func pick(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard index >= 0, let id = sender.item(at: index)?.representedObject as? String else { return }
            selection.wrappedValue = id
        }
    }
}
