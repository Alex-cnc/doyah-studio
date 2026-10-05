import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **标题栏搜索栏的宽度**（队列 `L-141`，内测清单 **甲1**，需求提出者 2026-09-30 原话：
/// 「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」）。
///
/// ## 量与不量什么
///
/// 量的是**真视图**（`App/Views/TitleBarSearchField.swift`）在每一档窗口宽度下**实际占多宽**：
/// 离屏宿主 `NSHostingController.sizeThatFits(in:)` —— 不需要窗口、不需要屏幕录制、不需要人在场
/// （与 `WorkspaceChromeHeightProbeTests` 同一套量法，**不渲染位图**，所以随门禁第 1 项天天跑）。
/// 宽度策略本身另有 10 条纯逻辑单测（`Tests/TitleBarSearchLayoutTests.swift`）；这里管的是
/// **界面真的照它摆**（策略绿、界面写死宽度 ⇒ 缺陷照样在）。
///
/// ## 判据必须能判红（最后一族就是这件事）
///
/// 「不越界」如果只是因为这套量法量不出差别，就是假绿。所以同一族里带**对照**：
/// 把**旧口径（系统给的写死宽度 `320`）**摆进同一个量法 —— 它必须在窄窗口上被判越界。
///
/// ## 边界（如实登记，别当已验）
///
/// · 量的是**视图宽度**，**不是** AppKit 标题栏那一层：标题画在哪一侧、交通灯实际占多少、
///   系统有没有在最后一步再插手（`NSWindow.toolbar`），本轮**未机器化**（要真窗口才量得到）；
/// · **窗口宽度的来源**（`MainWindow` 里那次 `GeometryReader` 读数）也不在本判据内 ——
///   探针直接把宽度喂给视图，等于假定它拿到的数是对的；
/// · 不验观感（好不好看 / 位置合不合意），也不验**能不能搜出东西**（那是命令面板既有判据）。
final class TitleBarSearchProbeTests: XCTestCase {

    /// 取样宽度：从大屏全屏到**非全屏的窄窗口**（内测报的是非全屏下出事）。
    /// 取 741 是因为它是「最小可用宽度再少 1pt」那一档（策略在这档收成 0）。
    private let windowWidths: [CGFloat] = [1440, 1280, 1100, 900, 800, 742, 741]

    /// 英文最长的那一条窗口标题（`Doyah Studio - Workspace`）。
    private let titleText = "Doyah Studio - Workspace"

    // MARK: - 量法

    @MainActor
    private func makeState() -> AppState {
        AppState()
    }

    /// 真视图在这一档窗口宽度下占多宽（泛型：探针里那两件视图共用同一套量法）。
    @MainActor
    private func measuredWidth<Content: View>(of field: Content, in state: AppState) -> CGFloat {
        let controller = NSHostingController(rootView: field.environmentObject(state))
        return controller.sizeThatFits(in: CGSize(width: 1440, height: 40)).width
    }

    /// 策略说这一档该给多宽。
    private func expectedWidth(windowWidth: CGFloat) -> CGFloat {
        TitleBarSearchLayout.searchFieldWidth(
            windowWidth: windowWidth,
            titleWidth: TitleBarSearchMetrics.titleWidth(of: titleText)
        )
    }

    // MARK: - 第一批：界面真的照策略摆（每一档都量真视图）

    @MainActor
    func testFieldWidthFollowsPolicyOnEveryWindowWidth() throws {
        let state = makeState()
        let titleWidth = TitleBarSearchMetrics.titleWidth(of: titleText)
        var measured: [CGFloat] = []
        for width in windowWidths {
            let value = measuredWidth(
                of: TitleBarSearchField(windowWidth: width, titleText: titleText),
                in: state
            )
            measured.append(value)
            XCTAssertEqual(
                value,
                expectedWidth(windowWidth: width),
                accuracy: 0.5,
                "窗口 \(width)pt 上量到的宽度与策略给的不一致（界面自己写了一套宽度）"
            )
            XCTAssertTrue(
                TitleBarSearchLayout.fitsWithoutCoveringTitle(
                    windowWidth: width,
                    titleWidth: titleWidth,
                    searchFieldWidth: value
                ),
                "窗口 \(width)pt：宽 \(value) 压到了标题带（甲1 就是这个）"
            )
        }
        print("TITLEBAR-SEARCH 每档宽度 -> \(measured)")
    }

    /// 窗口变窄 ⇒ **只减不增**（量的是真视图，不是模型）。
    @MainActor
    func testMeasuredWidthIsMonotoneNonIncreasing() throws {
        let state = makeState()
        var previous: CGFloat = .greatestFiniteMagnitude
        for width in windowWidths {
            let value = measuredWidth(
                of: TitleBarSearchField(windowWidth: width, titleText: titleText),
                in: state
            )
            XCTAssertLessThanOrEqual(value, previous, "窗口 \(width)pt 上比更窄的窗口还宽 —— 收敛不是单调的")
            previous = value
        }
    }

    /// 窄到放不下那一档：**整条不显示**（量出来是 0，不是一条几十 pt 的搜索框）。
    @MainActor
    func testTooNarrowWindowRendersNothing() throws {
        let state = makeState()
        let value = measuredWidth(
            of: TitleBarSearchField(windowWidth: 741, titleText: titleText),
            in: state
        )
        XCTAssertLessThanOrEqual(value, 1, "741pt 这一档还画了一条 \(value)pt 的搜索框")
    }

    // MARK: - 对照：这条判据真的能判红（旧口径 = 系统给的写死宽度）

    /// 旧口径（写死 `320`）在**同一套量法**下：宽窗口不越界、窄窗口必越界 —— 正是内测看到的那一幕
    /// （「不是全屏时……遮住了标题」）。这条若判绿，上面几条不变量等于没内容。
    @MainActor
    func testLegacyFixedWidthWouldCoverTitleOnNarrowWindows() throws {
        let state = makeState()
        let titleWidth = TitleBarSearchMetrics.titleWidth(of: titleText)
        let fitsWidths: [CGFloat] = [1440, 1280, 1100, 900]
        let coversWidths: [CGFloat] = [800, 742, 741]
        for width in fitsWidths + coversWidths {
            let value = measuredWidth(of: LegacyFixedWidthSearchField(), in: state)
            XCTAssertEqual(
                value,
                LegacyFixedWidthSearchField.width,
                accuracy: 0.5,
                "对照件的宽度量不出来 ⇒ 这套量法失效"
            )
            let fits = TitleBarSearchLayout.fitsWithoutCoveringTitle(
                windowWidth: width,
                titleWidth: titleWidth,
                searchFieldWidth: value
            )
            if fitsWidths.contains(width) {
                XCTAssertTrue(fits, "对照失效：宽窗口 \(width)pt 上写死宽度也不越界")
            } else {
                XCTAssertFalse(fits, "对照失效：窄窗口 \(width)pt 上写死宽度居然不越界 ⇒ 本判据量不出甲1")
            }
        }
    }

    // MARK: - 标题宽度是**量**出来的，不是估的

    @MainActor
    func testTitleWidthIsMeasuredWithTitleBarFont() throws {
        let long = TitleBarSearchMetrics.titleWidth(of: "Doyah Studio - Workspace")
        let short = TitleBarSearchMetrics.titleWidth(of: "Doyah Studio - Notes")
        XCTAssertEqual(
            long,
            167.1,
            accuracy: 1.0,
            "英文最长标题在标题栏字体下的实量宽度变了 —— 策略里的档位要跟着复核"
        )
        XCTAssertLessThan(short, long)
        // 同一窗口宽度下，标题越短 ⇒ 搜索栏越长（界面那一侧同样成立）。
        let state = makeState()
        let longField = measuredWidth(
            of: TitleBarSearchField(windowWidth: 800, titleText: "Doyah Studio - Workspace"),
            in: state
        )
        let shortField = measuredWidth(
            of: TitleBarSearchField(windowWidth: 800, titleText: "Doyah Studio - Notes"),
            in: state
        )
        print("TITLEBAR-SEARCH 800pt 上 长标题 \(longField) / 短标题 \(shortField)")
        XCTAssertGreaterThan(shortField, longField)
    }
}

/// **对照件**：旧口径的搜索栏（写死宽度，与系统交给 `.searchable(placement: .toolbarPrincipal)`
/// 的那一档同量级）。只为证明本判据**能判红** —— 它不是产品代码，**不接进任何界面**。
private struct LegacyFixedWidthSearchField: View {
    static let width: CGFloat = 320

    var body: some View {
        Color.clear.frame(width: Self.width, height: 24)
    }
}
