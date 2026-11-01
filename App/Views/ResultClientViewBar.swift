import SwiftUI
import AppKit
import DoyahCore

/// 结果区的**客户端视图条**（FR-RES-08 / FR-RES-09）：
/// 排序键、筛选条件、以及 R-21 要求的「只作用于已加载行」提示 + 生成 WHERE 入口。
///
/// 为什么排序要在这里也露一次脸（表头已经能排）：
/// 表头的指示器由 AppKit 画，**只表达第一排序键**。多列排序（Shift 点击）时，
/// 用户看不到「谁是次要键、次序如何、怎么单独去掉」，所以把排序键做成可点的实体。
///
/// ## 筛选条件里的列 / 运算符为什么是 AppKit 弹出按钮（`FR-STD-DB-RES-008`）
///
/// 原来那两处是 SwiftUI `Menu`。`Menu` 落到 `SwiftUIPopupButton`，但它的**菜单项要到弹出那一刻才建**
/// （实测：`popup.itemTitles == []`、`menu.update()` 与 `menuNeedsUpdate` 都不填）⇒
/// 「换一列 / 换一个运算符」这两条在离屏探针里**量不到**，只能靠人点。
/// 换成真 `NSPopUpButton` 之后，`selectItem(withTitle:) + sendAction` 与手选走同一条 action 路径，
/// 判据就能盯着「表格里真的少了哪几行」。（与 `TitleBarSearchField` 同一类换法：要能被量，
/// 控件就得是真控件。）
struct ResultClientViewBar: View {

    let columns: [ColumnMeta]
    /// 已取回的行数（R-21 提示里要说清「仅对已加载的 N 行生效」）。
    let loadedRowCount: Int
    let filters: [ResultFilter]
    let sortDescriptors: [ResultSortDescriptor]
    /// 是否已经有客户端视图操作在生效（R-21 提示只在这时为真才说）。
    ///
    /// 这条提示以前是「条一出现就写」，而条现在**默认就在**（见 `FR-STD-DB-RES-008`：
    /// 唯一「+ 加条件」入口在条里，藏起来等于没有入口），于是它必须先问一句「做了吗」。
    let isClientViewActive: Bool

    var onChangeFilter: ((Int, ResultFilter) -> Void)?
    var onRemoveFilter: ((Int) -> Void)?
    var onAddFilter: (() -> Void)?
    var onClearFilters: (() -> Void)?
    var onClearSort: (() -> Void)?
    var onRemoveSortKey: ((Int) -> Void)?
    var onGenerateWhere: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    // 单列排序的指示器在表头上；多列才需要在这里列出来。
                    if sortDescriptors.count > 1 {
                        ForEach(Array(sortDescriptors.enumerated()), id: \.offset) { index, descriptor in
                            sortChip(rank: index + 1, descriptor: descriptor)
                        }
                        Button {
                            onClearSort?()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(Theme.font(.caption))
                        }
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .help(L(.resultSortClear))

                        Divider().frame(height: Metrics.controlHeight)
                    }

                    ForEach(Array(filters.enumerated()), id: \.offset) { index, filter in
                        filterChip(index: index, filter: filter)
                    }

                    Button {
                        onAddFilter?()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help(L(.resultFilterAdd))
                }
                .padding(.vertical, Spacing.hair)
            }

            Spacer(minLength: Spacing.s)

            // R-21：客户端排序 / 筛选只作用于已取回的行 —— 不写这一句，用户会把它当成服务端过滤。
            // 但**只有在真有客户端操作时才写**：条默认在场（「+」在条里），一进来就喊一句
            // 「仅对已加载的行生效」，等于每次查询都提醒用户一件还没发生的事。
            if isClientViewActive {
                Text(L(.resultFilterClientOnlyNote, loadedRowCount))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .fixedSize()
            }

            if !filters.isEmpty {
                ToolbarIconButton(systemName: "wand.and.stars", help: L(.resultFilterGenerateWhere)) { onGenerateWhere?() }
                ToolbarIconButton(systemName: "xmark.bin", help: L(.resultFilterClear)) { onClearFilters?() }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(Theme.surface(.panel))
    }

    // MARK: 排序键

    private func sortChip(rank: Int, descriptor: ResultSortDescriptor) -> some View {
        let name = columns.indices.contains(descriptor.columnIndex)
            ? columns[descriptor.columnIndex].name
            : "?"
        return HStack(spacing: Spacing.xs) {
            Text("\(rank)")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(name)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.primary))
            Image(systemName: descriptor.order.isAscending ? "arrow.up" : "arrow.down")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            Button {
                onRemoveSortKey?(descriptor.columnIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help(L(.resultSortClear))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(Theme.surface(.raised))
        )
    }

    // MARK: 筛选条件

    private func filterChip(index: Int, filter: ResultFilter) -> some View {
        HStack(spacing: Spacing.xs) {
            // 换列：真 `NSPopUpButton`（理由见本文件头部）。
            ResultFilterPopup(
                titles: columns.map(\.name),
                selectedIndex: filter.columnIndex,
                onSelect: { columnIndex in
                    var updated = filter
                    updated.columnIndex = columnIndex
                    onChangeFilter?(index, updated)
                }
            )
            .fixedSize()

            // 换运算符：「为空 / 不为空」这两档不需要值，选它们时输入框会跟着消失。
            ResultFilterPopup(
                titles: ResultFilterOperator.allCases.map(filterOperatorLabel),
                selectedIndex: ResultFilterOperator.allCases.firstIndex(of: filter.op) ?? 0,
                onSelect: { opIndex in
                    let all = ResultFilterOperator.allCases
                    guard all.indices.contains(opIndex) else { return }
                    var updated = filter
                    updated.op = all[opIndex]
                    onChangeFilter?(index, updated)
                }
            )
            .fixedSize()

            if filter.op.requiresValue {
                TextField(L(.resultFilterValue), text: Binding(
                    get: { filter.value },
                    set: { newValue in
                        var updated = filter
                        updated.value = newValue
                        onChangeFilter?(index, updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(Theme.font(.data))
                .frame(width: 110)
            }

            // 大小写只对文本比较有意义（数值、空值判断用不到）。
            if filter.op.requiresValue {
                Button {
                    var updated = filter
                    updated.caseSensitive.toggle()
                    onChangeFilter?(index, updated)
                } label: {
                    Image(systemName: filter.caseSensitive ? "textformat" : "textformat.size")
                        .font(Theme.font(.caption))
                        .foregroundStyle(filter.caseSensitive ? Theme.accentColor : Theme.text(.tertiary))
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .help(L(.resultFilterCaseSensitive))
            }

            Button {
                onRemoveFilter?(index)
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help(L(.resultFilterRemove))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(Theme.surface(.raised))
        )
    }
}

/// 运算符的界面文案。放在视图层是因为它要 `L(...)`（Core 只提供稳定标识）。
func filterOperatorLabel(_ op: ResultFilterOperator) -> String {
    switch op {
    case .contains: return L(.filterOpContains)
    case .notContains: return L(.filterOpNotContains)
    case .equals: return L(.filterOpEquals)
    case .notEquals: return L(.filterOpNotEquals)
    case .greaterThan: return L(.filterOpGreaterThan)
    case .greaterThanOrEqual: return L(.filterOpGreaterThanOrEqual)
    case .lessThan: return L(.filterOpLessThan)
    case .lessThanOrEqual: return L(.filterOpLessThanOrEqual)
    case .isEmpty: return L(.filterOpIsEmpty)
    case .isNotEmpty: return L(.filterOpIsNotEmpty)
    }
}

// MARK: - 列 / 运算符选择（AppKit）

/// 筛选条件里那颗「选一个值」的弹出按钮（列名、运算符都用它）。
///
/// 为什么不用 SwiftUI `Menu`：`Menu` 的菜单项在**弹出那一刻**才建 —— 离屏探针里
/// `itemTitles` 恒为空、`menu.update()` 也填不进东西，于是「换列 / 换运算符」这条
/// 只能靠人点（台账备注原来就写着「界面点击待人工点验」）。
/// 真 `NSPopUpButton` 的 items 是静态的：`selectItem(withTitle:) + sendAction`
/// 与手选走**同一条** action 路径，判据就能盯着「表格里真的变了哪几行」。
struct ResultFilterPopup: NSViewRepresentable {

    /// 候选文案（列名 / 运算符文案），顺序即下标。
    let titles: [String]
    /// 当前选中项的下标。
    let selectedIndex: Int
    /// 用户换了选项。参数是选中的下标（越界不给）。
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = Theme.nsFont(.caption)
        button.controlSize = .small
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        // items 只在候选真的变了时才重建：每次 SwiftUI 更新都重建会把正在展开的菜单收掉
        // （用户点开菜单、状态又被别处刷新 ⇒ 菜单凭空消失）。
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if titles.indices.contains(selectedIndex), button.indexOfSelectedItem != selectedIndex {
            button.selectItem(at: selectedIndex)
        }
    }

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard index >= 0 else { return }
            onSelect(index)
        }
    }
}
