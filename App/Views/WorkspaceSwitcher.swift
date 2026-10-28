import DoyahCore
import SwiftUI

/// 「切换工作区」的**唯一入口**（`FR-STD-WS-FS-010`）。
///
/// 两个落点共用这一份：文件树标头那一枚（`WorkspaceSwitchMenu`）与首页「最近打开的工作区」里的
/// 每一行（`WorkspaceKnownRow`）。两边都读同一个来源（`workspace.knownWorkspaces`）、
/// 都调同一个动作（`workspace.switchTo(_:)`）—— 这类「同一动作两个入口」最容易只补用户点到的
/// 那一处、留下第二处形态不一致（`FR-EDIT-44` 那次的搜索框就吃过这个亏）。

/// 一行怎么写：活动的打勾、不可用的把理由写在**同一行**里。
///
/// 只置灰不给理由，用户看到的是一条点不动的灰行 —— 他会以为界面坏了，
/// 而不是「那个文件夹被删了，得重新选一次」。
func workspaceRowText(_ item: KnownWorkspace) -> String {
    if item.isActive { return "✓ \(item.displayName)" }
    if let reason = workspaceShortReason(item.availability) {
        return "\(item.displayName) · \(reason)"
    }
    return item.displayName
}

/// 不可用那一档的短句（列表行里用；长句留给 `WorkspaceStore.noticeText` 的提示条）。
func workspaceShortReason(_ availability: WorkspaceAvailability) -> String? {
    switch availability {
    case .available: return nil
    case .missing: return L(.workspaceUnavailableShortMissing)
    case .denied: return L(.workspaceUnavailableShortDenied)
    case .notAuthorized, .unresolved: return L(.workspaceUnavailableShortUnresolved)
    }
}

/// 文件树标头那一枚：点开是**已知工作区列表** + 「选择文件夹…」。
///
/// 标头原来那枚直接弹目录选择器 —— 换一个工作区要重新走一遍授权弹窗，
/// 而常用的那几个其实早就授权过了。
struct WorkspaceSwitchMenu: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        Menu {
            ForEach(workspace.knownWorkspaces) { item in
                Button {
                    Task { await workspace.switchTo(item.id) }
                } label: {
                    Text(workspaceRowText(item))
                }
                // 不可用的**不许点**（切过去会得到一个画不出内容的工作区，还把原来那个停掉）。
                .disabled(!item.isUsable)
                .help(workspaceShortReason(item.availability) ?? (item.path ?? ""))
            }
            if !workspace.knownWorkspaces.isEmpty { Divider() }
            Button(L(.workspaceChoose)) {
                Task { await workspace.pickAndChoose() }
            }
        } label: {
            Image(systemName: "folder.badge.gearshape")
                .font(Theme.font(.caption))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L(.workspaceSwitch))
        .accessibilityLabel(Text(L(.workspaceSwitch)))
    }
}

/// 首页「最近打开的工作区」里的一行（与标头菜单同一个列表、同一个动作）。
struct WorkspaceKnownRow: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let item: KnownWorkspace

    var body: some View {
        Button {
            Task { await workspace.switchTo(item.id) }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.isActive ? "folder.fill" : "folder")
                    .font(Theme.font(.caption))
                    .foregroundStyle(item.isActive ? Theme.text(.primary) : Theme.text(.tertiary))
                VStack(alignment: .leading, spacing: 0) {
                    Text(workspaceRowText(item))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.primary))
                        .lineLimit(1)
                    Text(item.path ?? "")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.hair)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isUsable)
        .help(item.path ?? "")
        .accessibilityLabel(Text(workspaceRowText(item)))
        .accessibilityValue(item.isActive ? Text(L(.workspaceSwitchActive)) : Text(""))
    }
}
