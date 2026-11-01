import AppKit
import SwiftUI
import DoyahCore

/// 结果区的**分页条**（FR-RES-10 / `FR-STD-DB-RES-009`）：每页行数档位、页码指示、翻页。
///
/// ## 为什么整条换成 AppKit 控件（2026-11-01 B2 批次）
///
/// 原先这一条是 SwiftUI `Picker` + 四枚 `.borderless` 的 SwiftUI `Button`。离屏宿主里它们
/// **不落** `NSButton` / `NSPopUpButton`（与 `FR-STD-DB-RES-008` 换 `NSPopUpButton`、
/// `FR-STD-DB-TASK-003` 换 `PanelIconButton` 同一类实测），于是「点下一页真的会到第二页吗」
/// 「换档位会不会回到第 1 页」这两件事在自动化里**一次都量不到**，台账备注只能写「界面点击待人工点验」。
///
/// 换成真控件之后，探针 `performClick(nil)` / `selectItem + sendAction` 走的就是用户点它那条
/// action 路径；页码那句话与「仅对已加载的 N 行分页」那句标注也落成真 `NSTextField`，
/// 于是「显示的是第几页」可以逐字读出来，而不是靠状态里自己算。
///
/// 页码显示一律用 `page.pageIndex`（已被 `ResultView.page` 夹取过），而不是外部状态里那个
/// 可能越界的值 —— 否则会出现「共 1 页却写着第 3 / 1 页」。
struct ResultPagerBar: View {

    let page: ResultPage
    /// 当前每页行数（0 = 全部）。
    let pageSize: Int
    /// **已取回的行数**（RES-011 ② 的标注：客户端分页只对这一批行生效）。
    let loadedRowCount: Int

    var onChangePageSize: ((Int) -> Void)?
    var onGoToPage: ((Int) -> Void)?

    var body: some View {
        ResultPagerControls(
            page: page,
            pageSize: pageSize,
            loadedRowCount: loadedRowCount,
            onChangePageSize: onChangePageSize,
            onGoToPage: onGoToPage
        )
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(Theme.surface(.panel))
    }

    /// 档位下拉的文案（顺序 = `ResultView.pageSizeChoices`）。
    ///
    /// 抽出来是给视图与探针共用一份：少一档 / 多一档就是「用户选不到」或「选了不认」。
    static func pageSizeTitles() -> [String] {
        ResultView.pageSizeChoices.map { size in
            size == ResultView.pageSizeAll ? L(.resultPageAll) : "\(size)"
        }
    }
}

// MARK: - 真控件那一层

/// 分页条本体（真 `NSView`：`NSPopUpButton` + 四枚 `NSButton` + 两句 `NSTextField`）。
///
/// 布局用 `NSStackView`：语言 / 字号变了控件自己跟，不写死宽高（与 `PanelIconButton` 同一口径）。
final class ResultPagerControlsView: NSView {

    let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let firstButton = NSButton()
    let previousButton = NSButton()
    let nextButton = NSButton()
    let lastButton = NSButton()
    /// 页码那句话（「第 N / M 页 · 共 K 行」）。
    let indicator = NSTextField(labelWithString: "")
    /// 「仅对已加载的 N 行分页」那一句（RES-011 ② / R-21）。不分页时收起。
    let loadedNote = NSTextField(labelWithString: "")

    private let caption = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    /// 按钮 → 动作的接线（与 `PanelIconButton.Coordinator` 同一条思路）。
    weak var coordinator: ResultPagerControlsCoordinator?

    /// 最近一次画出来的页码（箭头按**显示的那个**页翻，不按状态里可能越界的值）。
    private var renderedPageIndex = 0
    private var renderedPageCount = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        caption.stringValue = L(.resultPageSize)
        caption.font = Theme.nsFont(.caption)
        caption.textColor = .secondaryLabelColor
        caption.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        sizePopup.isBordered = false
        sizePopup.bezelStyle = .inline
        sizePopup.font = Theme.nsFont(.caption)
        sizePopup.controlSize = .small
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged(_:))
        sizePopup.setAccessibilityLabel(L(.resultPageSize))
        sizePopup.addItems(withTitles: ResultPagerBar.pageSizeTitles())

        configure(firstButton, symbol: "chevron.left.2", help: L(.resultPageFirst),
                  selector: #selector(goFirst))
        configure(previousButton, symbol: "chevron.left", help: L(.resultPagePrevious),
                  selector: #selector(goPrevious))
        configure(nextButton, symbol: "chevron.right", help: L(.resultPageNext),
                  selector: #selector(goNext))
        configure(lastButton, symbol: "chevron.right.2", help: L(.resultPageLast),
                  selector: #selector(goLast))

        indicator.font = Theme.nsFont(.caption)
        indicator.textColor = .secondaryLabelColor
        indicator.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        loadedNote.font = Theme.nsFont(.caption)
        loadedNote.textColor = .tertiaryLabelColor
        loadedNote.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [caption, sizePopup, firstButton, previousButton, indicator, nextButton, lastButton] {
            stack.addArrangedSubview(view)
        }
        // 右侧弹簧：中间那组翻页控件靠右，与原先两个 `Spacer` 同形。
        let spring = NSView()
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spring.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.insertArrangedSubview(spring, at: 2)
        stack.addArrangedSubview(loadedNote)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.controlHeight),
        ])
    }

    private func configure(_ button: NSButton, symbol: String, help: String, selector: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        // 提示就是探针认得出「哪一枚是下一页」的依据，也是用户唯一能分辨四枚箭头的地方。
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.setAccessibilityRole(.button)
        button.target = self
        button.action = selector
    }

    /// 把一页的状态画出来（唯一渲染入口：初建与每次更新都走它）。
    func render(page: ResultPage, pageSize: Int, loadedRowCount: Int) {
        renderedPageIndex = page.pageIndex
        renderedPageCount = max(page.pageCount, 1)

        let choices = ResultView.pageSizeChoices
        if let index = choices.firstIndex(of: pageSize), sizePopup.numberOfItems > index {
            sizePopup.selectItem(at: index)
        }

        indicator.stringValue = L(
            .resultPageIndicator,
            page.pageIndex + 1,
            renderedPageCount,
            page.totalRows
        )

        // RES-011 ② / R-21：客户端分页只作用于**已取回的那些行**。不分页（「全部」档）时这句没有意义。
        let isPaged = pageSize > 0
        loadedNote.stringValue = isPaged ? L(.resultPageClientOnlyNote, loadedRowCount) : ""
        loadedNote.isHidden = !isPaged

        // 边界上的箭头灰掉：用户点不动就知道走到头了（而不是点了没反应）。
        let canGoBack = page.pageIndex > 0
        let canGoForward = page.pageIndex < renderedPageCount - 1
        firstButton.isEnabled = canGoBack
        previousButton.isEnabled = canGoBack
        nextButton.isEnabled = canGoForward
        lastButton.isEnabled = canGoForward
    }

    // MARK: 动作

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        let choices = ResultView.pageSizeChoices
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        coordinator?.onChangePageSize?(choices[sender.indexOfSelectedItem])
    }

    /// 四枚箭头各自的落点（越界由 `ResultGridState.adopt` 再夹一次）。
    @objc private func goFirst() { coordinator?.onGoToPage?(0) }
    @objc private func goPrevious() { coordinator?.onGoToPage?(max(renderedPageIndex - 1, 0)) }
    @objc private func goNext() { coordinator?.onGoToPage?(renderedPageIndex + 1) }
    @objc private func goLast() { coordinator?.onGoToPage?(max(renderedPageCount - 1, 0)) }
}

/// SwiftUI ↔ AppKit 的桥（与 `ResultFilterPopup` 同一条路）。
struct ResultPagerControls: NSViewRepresentable {

    let page: ResultPage
    let pageSize: Int
    let loadedRowCount: Int
    var onChangePageSize: ((Int) -> Void)?
    var onGoToPage: ((Int) -> Void)?

    func makeCoordinator() -> ResultPagerControlsCoordinator {
        ResultPagerControlsCoordinator(
            onChangePageSize: onChangePageSize,
            onGoToPage: onGoToPage
        )
    }

    func makeNSView(context: Context) -> ResultPagerControlsView {
        let view = ResultPagerControlsView(frame: .zero)
        view.coordinator = context.coordinator
        view.render(page: page, pageSize: pageSize, loadedRowCount: loadedRowCount)
        return view
    }

    func updateNSView(_ view: ResultPagerControlsView, context: Context) {
        context.coordinator.onChangePageSize = onChangePageSize
        context.coordinator.onGoToPage = onGoToPage
        view.coordinator = context.coordinator
        view.render(page: page, pageSize: pageSize, loadedRowCount: loadedRowCount)
    }
}

final class ResultPagerControlsCoordinator: NSObject {
    var onChangePageSize: ((Int) -> Void)?
    var onGoToPage: ((Int) -> Void)?

    init(
        onChangePageSize: ((Int) -> Void)?,
        onGoToPage: ((Int) -> Void)?
    ) {
        self.onChangePageSize = onChangePageSize
        self.onGoToPage = onGoToPage
    }
}
