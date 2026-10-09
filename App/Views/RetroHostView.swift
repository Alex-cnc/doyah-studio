import DoyahCore
import DoyahRetroUI
import SwiftUI

/// 周报（Retro）阅读器在 Studio 里的**宿主装配**（片 `M7-HOST` · 派单 `T-20261009-080`）。
///
/// ## 一句话口径
///
/// 活动栏点 `Retro` ⇒ 右边出一台**真的只读阅读器**。视图代码**一个字都不复制进本仓**：
/// 期次卡片列表与正文渲染都在 Retro 仓的 `DoyahRetroUI` 里（`FR-R-13`「视图归 Retro 仓」），
/// 本文件只做三件事 —— **建模型**、**把它们摆在一起**、**给「没选中」一个空态**。
///
/// ## 三条不越界
///
///   · **扫描目录不另传参**：模型走 Retro 侧的唯一出处 `ReportListModel.fixed()`
///     （= `ReportReader.fixedScanRootPath`）。本仓**不出现那个盘上路径的第二份字面量** ——
///     宿主另传一个根，就是「两处真值」，迟早对不上（判据 ②：那个路径串在本仓 `Core/` `App/` 零命中）。
///   · **只读**：本文件不打开、不写任何包目录；Retro 侧 `Tools/check-readonly.py` 已钉住视图层那一半。
///   · **不扩许可模型**：Retro 是「报告阅读器」，不在三档卖点矩阵里 ⇒ **不新增能力位**
///     （见 `ActivityBarItem.retro` 的注释）。
///
/// ## 为什么整台阅读器作为**一块**装在这里，而不是把列表抬进 Studio 左栏
///
/// 阅读器要的是「**同一份模型**下的列表 + 正文」：左边选中哪一期，右边就渲染哪一期。
/// 拆到 Studio 的左栏 / 右栏两处，模型就会被两侧各建一份（两次扫描，选中项也对不上）——
/// 所以装配收在这一个文件里（与 `NotesAreaView` 的三栏同一形状）。
///
/// ## 装配面只取一个产品
///
/// 依赖里只声明 `DoyahRetroUI`（`.product(name: "DoyahRetroUI", package: "macos")`）——
/// 包内领域层 `DoyahRetroCore` 是它的**传递**依赖，所以本文件**不命名**那边任何类型：
/// 「选中那一期」全程用**类型推断**传下去（`model.selectedPackage` ⇒ `ReportDetailView(package:)`）。
/// 这样依赖面就正好是前门给的那一个 product，不夹带第二个。
struct RetroHostView: View {

    /// 阅读器模型（Retro 侧 `@MainActor` 类型）。用 `@StateObject` ⇒ **同一实例跨重绘**：
    /// 否则每次重绘都重扫一遍目录，用户选中的那一期也会被重置。
    @StateObject private var model = ReportListModel.fixed()

    var body: some View {
        HSplitView {
            // 左：期次卡片列表（`FR-R-13-08` 判据 ①）。中缝可拖（`HSplitView` 的本分）。
            ReportListView(model: model)
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 460)
            // 右：选中那一期的只读正文（`FR-R-13-08` 判据 ②③）。
            readingArea
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 右半边：选中哪一期就渲染哪一期；没选中 ⇒ 空态 —— **不崩**（判据 ④：
    /// 坏包 / 缺件走的是列表里那条逐条报告，右半边照旧出空态）。
    ///
    /// 渲染本体是 Retro 仓的 `ReportDetailView`（本仓**不重写**块渲染与媒体去向 ——
    /// 那是 `FR-R-13-09` 的面）。
    @ViewBuilder
    private var readingArea: some View {
        if let package = model.selectedPackage {
            ReportDetailView(package: package)
        } else {
            RetroReadingEmptyState()
        }
    }
}

/// 阅读器右半边**没选中任何一期**时的空态。
private struct RetroReadingEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "newspaper")
                .font(.system(size: 28))
                .foregroundStyle(Theme.text(.tertiary))
            Text(L(.retroReadingEmptyHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface(.content))
    }
}

/// 周报区在 Studio **左栏**的占位。
///
/// 为什么左栏不再放第二份导航：阅读器是**一整块**（见 `RetroHostView` 头注释）——
/// 它的期次列表就在它自己左边。左栏这里留一句说明，而不是一片空白：
/// 248pt 的空白面板看着像界面坏了，用户会去点它。
struct RetroSidebarPlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.s) {
            Spacer(minLength: 0)
            Image(systemName: "newspaper")
                .font(.system(size: 22))
                .foregroundStyle(Theme.text(.tertiary))
            Text(L(.retroSidebarHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
