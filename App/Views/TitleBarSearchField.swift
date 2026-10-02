import AppKit
import SwiftUI

import DoyahCore

/// 标题栏里那一枚**搜索栏**（`FR-EDIT-37`；宽度策略见队列 `L-141` 与 `Core/TitleBarSearchLayout`）。
///
/// ## 为什么不再用 `.searchable(placement: .toolbarPrincipal)`
///
/// 系统给的宽度**与窗口宽度无关**，于是需求提出者 2026-09-30 内测看到的是：
/// 「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」（甲1）。
/// 位置仍是**正中**（`.principal`，原话「标题后面居中」），但宽度改由**本策略**给：
/// 窗口变窄 ⇒ 搜索栏收敛；窄到放不下 ⇒ 整条不显示（回车入口仍在 ⌘K / 命令面板）。
///
/// ## 边界（如实登记）
///
/// · 宽度用的是**窗口内容区宽度**（标题栏与内容区同宽），由 `MainWindow` 量了传进来 ——
///   探针直接给值（离屏宿主没有窗口）；
/// · 标题宽度按**标题栏字体**（13pt semibold）实量，不是估的；AppKit 把标题画在居中还是靠左、
///   交通灯实际占多少，本轮**未机器化**（真窗口才量得到）—— 策略取的是居中标题那一档。
struct TitleBarSearchField: View {
    /// 窗口**内容区**宽度（pt）。
    let windowWidth: CGFloat

    /// 当前窗口标题原文（宽度从它量）。
    let titleText: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let width = TitleBarSearchLayout.searchFieldWidth(
            windowWidth: windowWidth,
            titleWidth: TitleBarSearchMetrics.titleWidth(of: titleText)
        )
        if width > 0 {
            field(width: width)
                .frame(width: width)
                .help(L(.windowSearchPlaceholder))
        } else {
            // 这一档放不下：**整条不显示**（不做一条宽几十 pt、既遮标题又没法用的搜索框）。
            // 回车那条路仍在（⌘K → 命令面板），所以「找东西」这件事不会因此变成死路。
            EmptyView()
        }
    }

    private func field(width: CGFloat) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            TextField(L(.windowSearchPlaceholder), text: $appState.globalSearchQuery)
                .textFieldStyle(.plain)
                .font(Theme.font(.body))
                // 回车把词交给**命令面板**（与 ⌘K 共用一处入口 —— 搜索栏不另做一套搜索）。
                .onSubmit {
                    appState.presentCommandPalette(seed: appState.globalSearchQuery)
                }
            if !appState.globalSearchQuery.isEmpty {
                Button {
                    appState.globalSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Theme.text(.tertiary))
                }
                .buttonStyle(.plain)
                .help(L(.commonClose))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.surface(.raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: Metrics.hairline)
        )
        // **看得见的框 = 能点的框**（派活单 `T-20261002-011`，合并 `T-20261001-041` / `051`）：
        // 留白与放大镜那一段由下面这层 AppKit 视图接手（真因、以及为什么不走 SwiftUI 手势，
        // 都写在 `TitleBarSearchClickRelay` 上）。宽要**让开右边那一小段** —— 清空按钮是 SwiftUI
        // 画的，而这层是 AppKit 视图（在它前面），不让开就会把 `×` 的点击抢走。
        .background(alignment: .leading) {
            TitleBarSearchClickRelay()
                .frame(
                    width: max(
                        0,
                        width - TitleBarSearchMetrics.trailingReserve(
                            hasClearButton: !appState.globalSearchQuery.isEmpty
                        )
                    )
                )
        }
    }
}

/// 「**看得见的框 = 能点的框**」那半（派活单 `T-20261002-011`，合并 `T-20261001-041` / `051`）。
///
/// ## 真因（2026-10-02 在真窗口上量的点击地图）
///
/// 画出来的框是 **360×24**，而真正能聚焦的只有内层 `TextField` 那一块 **332×16** ⇒
/// 「左边放大镜那 22pt」「上下各 4pt 留白」「右边 4pt」点上去**进不了控件**：没有光标、
/// 拿不到第一响应者、打进去的键也没落点（需求提出者原话：「点上去没有光标 / 不能打出字母」）。
/// 8 点点击地图（真窗口 · 窗口 active+key · 进程内合成点击）实测：只有落在输入框矩形里的 3 点聚焦。
///
/// ## 为什么不走 SwiftUI 手势
///
/// 先试过 `@FocusState` + `.onTapGesture`：**同一次点击先聚焦、随即被打回窗口** ——
/// 手势那一笔状态变更让这一层重排，刚拿到的第一响应者当场被收回（实测：加上手势之后，
/// 连原生那一小块也判 0）。⇒ 接管放在 **AppKit** 这一层，且**一个字都不改 SwiftUI 状态**。
///
/// ## 只接「谁也没要」的点击
///
/// 这层是**背景**（挂在输入框与清空按钮之下）：命中测试先把点击交给真控件；落到这层上的
/// 就是留白那几处 —— 此时把**第一响应者**交给同一框里的那枚输入框。
/// 边界（如实登记）：只动第一响应者，**不碰文本与选区**（落点仍由 AppKit 自己决定）。
struct TitleBarSearchClickRelay: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView { RelayView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// 承接留白点击的那一层。
    final class RelayView: NSView {

        override func mouseDown(with event: NSEvent) {
            guard let field = RelayView.searchField(beside: self) else {
                super.mouseDown(with: event)
                return
            }
            window?.makeFirstResponder(field)
        }

        /// **同一根工具条里**那枚输入框（唯一出处）。
        ///
        /// 口径：只在本工具条里找 —— 侧栏那枚搜索框不在工具条里，别的窗口更不会误伤；
        /// 并排掉 AppKit 自己的标题字段（`_NSToolbarTitleField` 也是 `NSTextField`）。
        static func searchField(beside view: NSView) -> NSTextField? {
            var node: NSView? = view
            while let current = node, !NSStringFromClass(type(of: current)).contains("NSToolbar") {
                node = current.superview
            }
            guard let scope = node else { return nil }
            return firstField(in: scope)
        }

        private static func firstField(in view: NSView) -> NSTextField? {
            for subview in view.subviews {
                if let field = subview as? NSTextField,
                   !NSStringFromClass(type(of: field)).contains("NSToolbarTitleField") {
                    return field
                }
                if let found = firstField(in: subview) { return found }
            }
            return nil
        }
    }
}

/// 标题宽度的**实量**（唯一出处）—— 策略只吃一个数，数从这里来。
enum TitleBarSearchMetrics {
    /// 标题栏字体：macOS 用**系统字号**（13pt）加 semibold，与标题栏实际绘制一致。
    static var titleFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    /// 整框点击接力那层**右边要让开**的那一小段（清空按钮那一段；没有按钮时是 0）。
    ///
    /// 为什么要让：接力层是 AppKit 视图，而清空按钮是 SwiftUI 画的 —— AppKit 这层在它前面，
    /// 不让开就会把 `×` 的点击抢走。取值**实量**：`×` 图标宽度 + 图标两侧的间距
    /// （2026-10-02 真窗口实测：`xmark.circle.fill` `.imageScale(.small)` 那枚按钮 = 17×13，
    /// 于 `Spacing.xs + clearButtonSymbolWidth + Spacing.s` 就是它那一段）。
    static func trailingReserve(hasClearButton: Bool) -> CGFloat {
        hasClearButton ? (Spacing.xs + clearButtonSymbolWidth + Spacing.s) : 0
    }

    /// `×` 那枚 SF Symbol 的宽度（pt）—— **实量**，与 `titleWidth(of:)` 同一口径：不估。
    static var clearButtonSymbolWidth: CGFloat {
        NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?.size.width ?? 13
    }

    static func titleWidth(of title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: titleFont]).width
    }
}
