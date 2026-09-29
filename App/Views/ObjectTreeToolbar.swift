import SwiftUI
import DoyahCore

/// 对象树顶部那一行：**视图切换（层级 / 按类型分组）+ 对象搜索 + 刷新**（FR-META-15 / FR-META-12 / FR-META-11）。
///
/// ## 为什么从 `ObjectTreeView` 里抽出来（队列 `L-89` ㈡ 第 6 条 · 分组视图那一行）
///
/// 待人工验收清单里那一行的人话是「对象树顶部在「层级视图 / 按类型分组」之间切换 →
/// **两种视图都能用；切换后选中项不丢**」。要机械判「这台开关真的在、两档都到得了」，
/// 就得**单独渲染这一行** —— 而它原来住在 `ObjectTreeView` 的 `body` 里，而那份 body 只有在
/// 「选中了连接、且根节点已经加载回来」之后才画得出来（前后分别是「请先选择连接」与
/// 「正在加载对象…」）⇒ 离屏渲染要先起一个真库、还要等异步加载落地，判据会变成在判
/// 「这台机器今天快不快」。
///
/// 与 `App/Views/LowerPaneTabStrip.swift`（第 96 轮）**同一个理由、同一个做法**：
/// 把这一行抽成独立真视图，唯一目的就是**能单独离屏渲染**；生产路径接线一字未改
/// （`ObjectTreeView.refreshRow` 现在把它装回去，`$groupByType` 还是那一个 `@State`）。
///
/// 生产路径与测试路径看到的是**同一份视图代码** —— 不是另画一张样张。
struct ObjectTreeToolbar: View {

    /// 视图模式（`false` = 层级视图 / `true` = 按类型分组）。**生产路径传入 `ObjectTreeView` 的那一个 `@State`**。
    @Binding var groupByType: Bool

    /// 根节点是否正在刷新（刷新按钮据此置灰）。
    var isRefreshing: Bool

    /// 「全库对象搜索」（FR-META-12）：与 ⌘K 里那条命令打开**同一个**面板。
    var onSearch: () -> Void

    /// 刷新根节点（FR-META-11）。
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Picker("", selection: $groupByType) {
                Text(L(.treeGroupHierarchy)).tag(false)
                Text(L(.treeGroupByType)).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .help(L(.treeGroupByType))

            Spacer()

            // 放这里是因为"找对象"是看着树时才有的念头，不必先想起来有命令面板。
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .help(L(.objectSearchTitle))

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .help(L(.treeRefreshHelp))
            .disabled(isRefreshing)
        }
    }
}
