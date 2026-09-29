import DoyahCore
import SwiftUI

// MARK: - 一行的渲染体（队列 L-90 未完成的那半：行级跳过重算）

/// 一行的**渲染体**：单独成 `View` + `Equatable` ⇒ 只有真正变了的行才重算 `body`。
///
/// ## 为什么（2026-09-29 需求提出者选定「B：彻底根治」）
///
/// 现场：**左键选中比右键还慢**。原因不在鼠标 —— 左键会改 `selectedTreeObject`，
/// 而这一改让**整棵树重算**：原先所有行都是 `ObjectTreeView` 里的一个 `private func`，
/// 父视图作废时它们全部重算 `body`（几十行的文本 / 图标 / 旋转角全部重建）。
///
/// 修法：把行渲染抽成独立 `View` 并实现 `Equatable`（`.equatable()` 走 `EquatableView`：
/// 相等就**不重算 body**）。相等比较只看**会影响这一行长什么样的东西**：
/// 行模型（含展开态 / 加载中 / 错误 / 子节点 / 缩进）、是否选中、空态文案、外观深浅。
/// `onToggle` 是闭包、每次重建都是新值 ⇒ **必须排除**，否则永远不相等、等于没优化。
///
/// 证据口子：`bodyEvaluations` 只在调试开关打开时累加，右键日志会把「距离上一次右键
/// 这一批行重算了多少次」打出来 —— 优化前 ≈ 行数、优化后 ≈ 1~2 行。
struct ObjectTreeRowContent: View, Equatable {
    let row: ObjectTreeVisibleRow
    let isSelected: Bool
    let emptyText: String
    let isDarkAppearance: Bool
    let onToggle: () -> Void

    /// 这一批行一共算了几次 `body`（取证用；见 `ObjectTreeRightClickLog`）。
    static var bodyEvaluations = 0

    static func == (lhs: ObjectTreeRowContent, rhs: ObjectTreeRowContent) -> Bool {
        lhs.row == rhs.row
            && lhs.isSelected == rhs.isSelected
            && lhs.emptyText == rhs.emptyText
            && lhs.isDarkAppearance == rhs.isDarkAppearance
        // `onToggle` 刻意不参与比较：闭包每次重建都是新值，比了就等于放弃优化。
    }

    var body: some View {
        if ObjectTreeRightClickLog.isEnabled { Self.bodyEvaluations += 1 }
        return HStack(spacing: Spacing.s) {
            if row.isGroupHeader {
                Color.clear.frame(width: 12, height: 12)
            } else if row.isExpandable {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.text(.secondary))
                        .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }

            Image(systemName: row.object.symbolName)
                .font(Theme.font(.caption))
                .foregroundStyle(Self.color(for: row.object.kind))
                .frame(width: 14)

            Text(row.object.name)
                .font(Theme.font(.caption))
                .fontWeight(row.isGroupHeader ? .semibold : .regular)
                .lineLimit(1)

            if let detail = row.object.detail {
                Text(detail)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)
            }
        }
        .padding(.leading, CGFloat(row.depth) * Metrics.listIndent)
        // 点击区**铺满整行**：默认只覆盖内容宽度 ⇒ 标签右边那一截空白点不到，
        // 表现就是「经常选不中」（2026-09-29 需求提出者实测）。`maxWidth: .infinity`
        // 之后 `contentShape` 覆盖的是整行，选中高亮也随之一整行铺开（树的常规做法）。
        .frame(maxWidth: .infinity, alignment: .leading)
        // 选中态要看得见：⌘K 里「浏览数据 / 查看 DDL / 合成数据」都作用在选中项上。
        .background(
            isSelected
                ? Theme.accentColor.opacity(isDarkAppearance ? Overlay.Selection.darkAlpha : Overlay.Selection.lightAlpha)
                : Color.clear
        )
    }

    /// 按对象类型上色（纯函数，与搬出前逐字一致）。
    static func color(for kind: DatabaseObject.Kind) -> Color {
        switch kind {
        case .server: return .accentColor
        case .database: return .blue
        case .schema: return .purple
        case .table: return .green
        case .view: return .teal
        case .column: return .secondary
        case .function: return .orange
        case .sequence: return .indigo
        }
    }
}
