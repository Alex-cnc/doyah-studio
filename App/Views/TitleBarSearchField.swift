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
            field
                .frame(width: width)
                .help(L(.windowSearchPlaceholder))
        } else {
            // 这一档放不下：**整条不显示**（不做一条宽几十 pt、既遮标题又没法用的搜索框）。
            // 回车那条路仍在（⌘K → 命令面板），所以「找东西」这件事不会因此变成死路。
            EmptyView()
        }
    }

    private var field: some View {
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
    }
}

/// 标题宽度的**实量**（唯一出处）—— 策略只吃一个数，数从这里来。
enum TitleBarSearchMetrics {
    /// 标题栏字体：macOS 用**系统字号**（13pt）加 semibold，与标题栏实际绘制一致。
    static var titleFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    static func titleWidth(of title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: titleFont]).width
    }
}
