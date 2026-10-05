import XCTest
@testable import DoyahCore

/// 标题栏搜索栏的**宽度策略**（队列 `L-141`，内测清单 **甲1**，需求提出者 2026-09-30 原话：
/// 「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」）。
///
/// 判据的本质是一条**不许**：**搜索栏不许长到标题带上**，任何窗口宽度下都成立。
/// 几何模型与两条不变量写在 `TitleBarSearchLayout` 的文档里 —— 这里是那个缺陷的看门人。
///
/// ## 判据必须能判红
///
/// 「标题完整可见」如果只是因为**这套量法本来就量不动**，那就是假绿。所以同一族里带**对照**：
/// **写死宽度的旧口径（`320`，即系统交给 `.searchable(placement: .toolbarPrincipal)` 的那一档）**
/// 必须在**窄窗口**上判红、在**宽窗口**上判绿 —— 这正是需求提出者看到的
/// 「全屏时没事、不是全屏就遮住标题」。两条都成立，「不越界」才作数。
///
/// ## 边界（如实登记，别当已验）
///
/// · 判的是**宽度策略**（纯逻辑），**不是** AppKit 标题栏那一层：系统把标题画在居中还是靠左、
///   交通灯到底占多少，本轮**未机器化**（真窗口才量得到）—— 模型取的是**居中标题**这一档，
///   系统画在哪一侧都不会比这更差；
/// · 不验观感（搜索框好不好看 / 位置合不合意），也不验它**能不能搜出东西**（那是命令面板既有判据）。
final class TitleBarSearchLayoutTests: XCTestCase {

    /// 实测量得的标题宽度：英文最长那一条（`Doyah Studio - Workspace` @ 13pt semibold = **167.1pt**）。
    /// 用真值而不是「随便取 200」—— 判据里的窗口宽度档位都由它推出来。
    private let englishTitleWidth: CGFloat = 167.1

    /// 中文最长那一条（`Doyah Studio - 工作区` @ 13pt semibold = **135.6pt**）。
    private let chineseTitleWidth: CGFloat = 135.6

    // MARK: - 三档：宽窗口给理想宽度 / 中档收敛 / 窄到放不下就不显示

    /// 宽窗口（全屏 / 大屏非全屏）：给理想宽度 —— 需求提出者要的是「长长的搜索栏」。
    func testWideWindowGetsIdealWidth() {
        for width in [CGFloat(1440), 1280, 1100] {
            XCTAssertEqual(
                TitleBarSearchLayout.searchFieldWidth(windowWidth: width, titleWidth: englishTitleWidth),
                TitleBarSearchLayout.idealWidth,
                "窗口 \(width)pt 上没给到理想宽度 \(TitleBarSearchLayout.idealWidth)"
            )
        }
    }

    /// 中档（窄的非全屏窗口）：**收敛** —— 这是甲1 的正题（原来这一档不收敛）。
    func testNarrowWindowShrinks() {
        // 900 / 800 / 750 三档实测：337.8 / 237.8 / 187.8（= 窗口宽度 − 2×(90 + 167.1 + 24)）
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 900, titleWidth: englishTitleWidth),
            337.8,
            accuracy: 0.05
        )
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 800, titleWidth: englishTitleWidth),
            237.8,
            accuracy: 0.05
        )
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 750, titleWidth: englishTitleWidth),
            187.8,
            accuracy: 0.05
        )
        // 收敛后的宽度**必须小于**理想宽度，否则「收敛」是假的。
        XCTAssertLessThan(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 800, titleWidth: englishTitleWidth),
            TitleBarSearchLayout.idealWidth
        )
    }

    /// 再窄一档：连最小可用宽度都不到 ⇒ **收成 0**（不显示），不做「宽 40pt 的搜索框」。
    func testTooNarrowHidesInsteadOfSliver() {
        for width in [CGFloat(741), 700, 640, 420] {
            XCTAssertEqual(
                TitleBarSearchLayout.searchFieldWidth(windowWidth: width, titleWidth: englishTitleWidth),
                0,
                "窗口 \(width)pt 上还挤着一条搜索框 —— 那一档既不显示标题也不能用"
            )
        }
    }

    /// 下限那一步：**恰好**够最小宽度 ⇒ 给最小宽度；再少 1pt ⇒ 收成 0（不取绝对值、不四舍五入）。
    func testMinimumStepBoundary() {
        // available = 窗口宽度 − 562.2 ⇒ 743 给 180.8（第一个 ≥ minimumWidth 的档）、742 给 179.8 ⇒ 收成 0。
        let justEnough = TitleBarSearchLayout.searchFieldWidth(windowWidth: 743, titleWidth: englishTitleWidth)
        XCTAssertGreaterThanOrEqual(justEnough, TitleBarSearchLayout.minimumWidth)
        XCTAssertLessThan(justEnough, TitleBarSearchLayout.idealWidth)
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 742, titleWidth: englishTitleWidth),
            0
        )
    }

    /// **标题越短，搜索栏越长** —— 同一窗口宽度下，中文标题（135.6pt）比英文（167.1pt）多让出 63pt。
    func testShorterTitleLeavesMoreRoom() {
        let english = TitleBarSearchLayout.searchFieldWidth(windowWidth: 800, titleWidth: englishTitleWidth)
        let chinese = TitleBarSearchLayout.searchFieldWidth(windowWidth: 800, titleWidth: chineseTitleWidth)
        XCTAssertEqual(chinese - english, 63, accuracy: 0.05)
        // 中文标题那一档仍在理想宽度以内（不是无限长）。
        XCTAssertLessThanOrEqual(chinese, TitleBarSearchLayout.idealWidth)
    }

    // MARK: - 不变量（这两条才是判据本体）

    /// 不变量 ①：**任何**窗口宽度下都不越界 —— 窗口**越宽**，给出的宽度**不更窄**（没有「忽然缩回去」的段落）。
    func testWidthIsMonotoneNonDecreasingAsWindowGrows() {
        var previous = TitleBarSearchLayout.searchFieldWidth(
            windowWidth: 320,
            titleWidth: englishTitleWidth
        )
        for width in stride(from: CGFloat(321), through: 2400, by: 1) {
            let current = TitleBarSearchLayout.searchFieldWidth(
                windowWidth: width,
                titleWidth: englishTitleWidth
            )
            XCTAssertGreaterThanOrEqual(
                current,
                previous,
                "窗口 \(width)pt 上搜索栏比更窄的窗口还窄 —— 收敛不是单调的"
            )
            previous = current
        }
    }

    /// 不变量 ②：窗口宽度扫一遍，**每一档都不压到标题带**（含隐藏档）。
    func testNeverCoversTitleAcrossAllWidths() {
        for width in stride(from: CGFloat(320), through: 2400, by: 1) {
            let field = TitleBarSearchLayout.searchFieldWidth(
                windowWidth: width,
                titleWidth: englishTitleWidth
            )
            XCTAssertTrue(
                TitleBarSearchLayout.fitsWithoutCoveringTitle(
                    windowWidth: width,
                    titleWidth: englishTitleWidth,
                    searchFieldWidth: field
                ),
                "窗口 \(width)pt：给出的宽度 \(field) 压到了标题带"
            )
        }
    }

    // MARK: - 对照：这条判据真的能判红（写死宽度的旧口径）

    /// **旧口径（写死 320）**：宽窗口上没事、窄窗口上必遮标题 —— 正是需求提出者看到的那一幕。
    /// 若这条对照判绿，说明上面的不变量没有任何内容（量法失效）。
    func testFixedWidthBaselineCoversTitleOnNarrowWindows() {
        let legacyWidth: CGFloat = 320
        // 宽窗口：站得住（所以「全屏时没事」）。
        for width in [CGFloat(1440), 1280, 1100] {
            XCTAssertTrue(
                TitleBarSearchLayout.fitsWithoutCoveringTitle(
                    windowWidth: width,
                    titleWidth: englishTitleWidth,
                    searchFieldWidth: legacyWidth
                ),
                "对照失效：窗口 \(width)pt 上写死 320 也不越界 ⇒ 本判据量不出甲1"
            )
        }
        // 窄窗口：越界（所以「不是全屏就遮住标题」）。
        for width in [CGFloat(800), 750, 741] {
            XCTAssertFalse(
                TitleBarSearchLayout.fitsWithoutCoveringTitle(
                    windowWidth: width,
                    titleWidth: englishTitleWidth,
                    searchFieldWidth: legacyWidth
                ),
                "对照失效：窗口 \(width)pt 上写死 320 居然不越界"
            )
        }
    }

    // MARK: - 退化输入：不猜、不崩

    /// 零 / 负 / 非数（NaN、无穷）一律按「放不下」处置 —— 不许取绝对值、不许把 NaN 传下去。
    func testDegenerateInputsYieldZeroInsteadOfGuessing() {
        XCTAssertEqual(TitleBarSearchLayout.searchFieldWidth(windowWidth: 0, titleWidth: 0), 0)
        XCTAssertEqual(TitleBarSearchLayout.searchFieldWidth(windowWidth: -500, titleWidth: 100), 0)
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: .nan, titleWidth: englishTitleWidth),
            0
        )
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: 1200, titleWidth: .nan),
            0
        )
        XCTAssertEqual(
            TitleBarSearchLayout.searchFieldWidth(windowWidth: .infinity, titleWidth: englishTitleWidth),
            0,
            "无穷宽度不该被当成「很大」而给出理想宽度 —— 那是猜"
        )
        XCTAssertFalse(
            TitleBarSearchLayout.fitsWithoutCoveringTitle(
                windowWidth: .nan,
                titleWidth: 100,
                searchFieldWidth: .nan
            )
        )
    }

    // MARK: - 源锚点：界面那一侧真的按这里给的宽度摆

    /// 判据不只看数学：那一枚搜索栏的**宽度必须来自本策略**，且它仍摆在工具条的**正中**位
    /// （写死 `width: 320` 这类旧写法会让整条策略变成没人用的摆设）。
    func testMainWindowTakesWidthFromThisPolicy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let field = try String(
            contentsOf: root.appendingPathComponent("App/Views/TitleBarSearchField.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            field.contains("TitleBarSearchLayout.searchFieldWidth("),
            "标题栏搜索栏没有从 TitleBarSearchLayout 取宽度 —— 策略与界面各写一套"
        )
        XCTAssertTrue(
            field.contains("TitleBarSearchMetrics.titleWidth(of: titleText)"),
            "标题宽度没有按标题栏字体实量（估一个数等于把策略的输入写死）"
        )
        let window = try String(
            contentsOf: root.appendingPathComponent("App/Views/MainWindow.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            window.contains("ToolbarItem(placement: .principal)"),
            "搜索栏不在工具条的**正中**位（FR-EDIT-37 原话「标题后面居中」）"
        )
        XCTAssertTrue(
            window.contains("TitleBarSearchField(windowWidth: contentWidth"),
            "窗口宽度没有量了传进搜索栏（策略拿不到一个真实宽度就退回写死）"
        )
    }
}
