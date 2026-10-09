import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **月视图格副条**（农历日 + 当日节气）的 App 侧探针（片 `TD-CAL-2` · 派单 `T-20261009-026`）。
///
/// ## 判的是什么
///
/// 派单上那两条现场验：
///   ① **月视图每格有农历日**（如「八月廿八」）；
///   ② **交节那天那一格有节气**（如「寒露」），其余日子不画。
///
/// 前门核验（`T-20261009-026` 的 C7）只判到「源码里有没有 `lunar` / `节气` 这些词」
/// （改前**零命中**）；「有」不等于「月视图上真的画出来了」。本探针把这两条在**真视图树**上
/// 跑成断言，并各留一张图给人判（`UISnapshot.writeBothLanguages` 落 `.build/ui-snapshots/`）。
///
/// ## 判据（可机械跑 · 每组都印读数）
///
/// · **甲 农历日到了渲染上**：月视图那一遍 `L(...)` 取到的文案里**必须**有
///   `2026-10-08` → 「八月廿八」、`2026-10-09` → 「八月廿九」（中英各一遍，英文是 `8/28` / `8/29`）；
/// · **乙 节气只画交节那天**：2026 年 10 月只有两枚节气（**寒露 10-08 / 霜降 10-23**），
///   于是那一遍里出现的节气名**恰好**是这两枚 —— 既判「画了」，也判「没多画」；
/// · **丙 农历日 + 节气同一天都在**：`10-08` 那一格两行都在（「八月廿八」与「寒露」同时出现在记录里）。
///
/// ## 边界（如实登记 · 先实测再写）
///
/// · **不是「真手点」的现场验**：SwiftUI 在离屏宿主里画的是真视图树，但**没有真人点开**这一屏 ——
///   本探针交的是**离屏渲染的真界面图**（`todos-calendar-lunar-*`），「现场验（交人工判 + 截图）」
///   里的人工那一半按 `TD-CAL-1` 的先例交给组长在解锁窗口补拍；
/// · 不碰用户数据：笔记库由 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录（没设就跳过）；
/// · 产物**不进快照清单**：图落 `.build/ui-snapshots/`（共享产物），`Scripts/check-doc-numbers.py`
///   读的是**全量跑凭证** `.build/ui-snapshots/full-run/` ⇒ 本探针不会搅动「张 / 组」那两条计数。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter LunarSubtitleProbeTests`。
final class LunarSubtitleProbeTests: XCTestCase {

    /// 宿主面积：与 `UISnapshotPanelsTests` 里那张日历月视图同一量级
    /// （那一栏单独占满时格子才够宽，四字农历日才排得下）。
    private static let size = CGSize(width: 660, height: 780)

    /// 锚点月份：**2026 年 10 月** —— 它是「寒露 / 霜降」两枚节气的月份，
    /// 且与跑这一轮那天（2026-10-09）分得开（月度可复现，不跟时钟走）。
    private static let anchorYear = 2026
    private static let anchorMonth = 10

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要碰笔记库（待办那一屏读库）⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
                + "（绝不允许往真实用户数据目录里写测试夹具）"
        )
    }

    // MARK: - 装配

    private func record(_ line: String) { print("🧪 TD-CAL-2 \(line)") }

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("td-cal-2-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    /// 那一遍渲染里实际取到的文案（去重集合）。
    @MainActor
    private func localizedStrings(of pair: UISnapshot.LanguagePair, index: Int) -> Set<String> {
        Set(pair.records[index].localizedStrings)
    }

    /// 判据里拿「这一句应该长什么样」—— 与渲染那一遍**同一条路**（`beginHostLanguage` 包住）。
    @MainActor
    private func text(_ language: AppLanguage, _ key: LKey) -> String {
        UISnapshot.localizedText(language) { L(key) }
    }

    // MARK: - 判据

    @MainActor
    func testMonthGridCarriesLunarDayAndTermSubtitle() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）：\(load.entitlements.basis)")

        let calendar = Calendar.current
        let anchor = try XCTUnwrap(
            calendar.date(from: DateComponents(year: Self.anchorYear, month: Self.anchorMonth, day: 1)),
            "构造不出 \(Self.anchorYear)-\(Self.anchorMonth)-01"
        )
        host.state.todos = []
        host.state.todoPane = .calendar
        host.state.todoCalendarView = .month
        host.state.todoCalendarAnchor = anchor
        host.state.todoCalendarSelectedDay = nil

        // 前置：本实现确实把这两天的农历算成了注释里那两个（Core 判据的读数在这里再印一遍，
        // 免得「图不对」时还得回头翻另一条判据）。
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        let info = try XCTUnwrap(
            LunarCalendar.dayInfo(for: day, calendar: calendar), "2026-10-08 取不到农历日"
        )
        self.record("2026-10-08 农历 \(info.lunar.month)/\(info.lunar.day)，节气 \(String(describing: info.term))")
        XCTAssertEqual(info.term, .coldDew, "2026-10-08 该是寒露")
        let plain = try XCTUnwrap(
            LunarCalendar.dayInfo(
                for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9))),
                calendar: calendar
            )
        )
        XCTAssertNil(plain.term, "2026-10-09 不该有节气")
        XCTAssertEqual(plain.lunar.day, 29, "2026-10-09 该是农历八月廿九")

        let pairs = try [
            UISnapshot.writeBothLanguages("todos-calendar-lunar", size: Self.size, scheme: .light) {
                TodoPaneView().snapshotEnvironment(
                    state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
                )
            },
            UISnapshot.writeBothLanguages("todos-calendar-lunar-dark", size: Self.size, scheme: .dark) {
                TodoPaneView().snapshotEnvironment(
                    state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
                )
            }
        ]
        XCTAssertEqual(pairs.count, 2, "浅色 / 深色两遍都要拍到")

        for pair in pairs {
            XCTAssertEqual(pair.records.count, 2, "\(pair.base)：中英两遍都要在")
            // 甲：农历日到了渲染上（10-08 与 10-09 两天，中英各一）。
            let zh = localizedStrings(of: pair, index: 0)
            let en = localizedStrings(of: pair, index: 1)
            XCTAssertTrue(zh.contains("八月廿八"), "\(pair.base)：中文那遍没有「八月廿八」")
            XCTAssertTrue(zh.contains("八月廿九"), "\(pair.base)：中文那遍没有「八月廿九」")
            XCTAssertTrue(en.contains("8/28"), "\(pair.base)：英文那遍没有 `8/28`")
            XCTAssertTrue(en.contains("8/29"), "\(pair.base)：英文那遍没有 `8/29`")
            // 乙：节气恰好是 10 月那两枚（画了，且没多画）。
            let zhTerms = Set(SolarTerm.allCases.map { text(.simplifiedChinese, $0.key) })
            let enTerms = Set(SolarTerm.allCases.map { text(.english, $0.key) })
            let zhOnScreen = zhTerms.intersection(zh)
            let enOnScreen = enTerms.intersection(en)
            self.record("\(pair.base) 屏幕上出现的节气：zh=\(zhOnScreen.sorted()) en=\(enOnScreen.sorted())")
            XCTAssertEqual(
                zhOnScreen, [text(.simplifiedChinese, .lunarTermColdDew), text(.simplifiedChinese, .lunarTermFrostDescent)],
                "\(pair.base)：2026 年 10 月该只有寒露 / 霜降两枚节气"
            )
            XCTAssertEqual(
                enOnScreen, [text(.english, .lunarTermColdDew), text(.english, .lunarTermFrostDescent)],
                "\(pair.base)：2026 年 10 月该只有 Cold Dew / Frost's Descent 两枚节气"
            )
            // 丙：10-08 那一格两行都在（农历日 + 节气同一天）。
            XCTAssertTrue(zh.contains("八月廿八") && zh.contains("寒露"), "\(pair.base)：10-08 那一格两行没同时在")
        }
    }
}
