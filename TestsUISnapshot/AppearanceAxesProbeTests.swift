import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 外观**两轴正交**的 App 侧探针（队列 `L-85`）—— 开发循环第 83 轮。
///
/// ## 为什么需要它
///
/// `Tests/AppearanceAxesTests.swift` 守的是 Core 里的纯逻辑（三态真值表、组合可枚举、门槛两态都过），
/// 但「**切一轴不会把另一轴重置**」这件事**只有在真管理器 + 真 `UserDefaults` 上才成立或不成立**：
/// 深浅档住在 `AppState.appearanceMode`（键 `appearance.mode`），配色住在 `DesignThemeManager`
/// （键 `ui.designTheme`）—— 两个对象各写各的键，是**约定**，不是类型系统保证的东西。
/// 有人在 `select(_:)` 里顺手多写一行、或把键名写错，Core 单测完全照不到。
///
/// ## 口径
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与快照同一条纪律：取证才跑，每轮门禁不跑；
/// · 断言落在**行为**上：切 N 次主题 / 切 N 次深浅档之后，另一轴的落盘值**一字未变**；
/// · **不留痕**：进来先记两个键的原值（含「从没设过」这一态），`defer` 里逐键还原。
///   本探针跑在 `swift test` 的测试进程里，`UserDefaults.standard` 是**测试进程自己的域**
///   （不是 App 的 `studio.doyah.DoyahStudio`），所以它本来就碰不到用户的真实偏好；
///   还原这一步仍然要做 —— 同一次运行里后续用例还要读这两个键。
///
/// 边界（如实登记）：它验的是**本机 macOS 上这两个对象的互不干扰**；不验「改系统外观后界面是否
/// 重画」（那一条要真人点验：改系统外观 → 应用与终端同时跟着变；再切主题 → 深浅档不被打回）。
final class AppearanceAxesProbeTests: XCTestCase {

    private let appearanceKey = AppearancePreference.Storage.appKey
    private let themeKey = DesignTheme.Storage.key

    /// 两轴互不读取：切主题 → 深浅键不动；切深浅 → 主题键不动。
    @MainActor
    func testSwitchingOneAxisNeverResetsTheOther() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针要写 `UserDefaults`（跑完逐键还原）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let defaults = UserDefaults.standard
        // 原值可能是「从没设过」（nil）—— 还原时必须还原成 nil，不能顺手写一个默认值进去。
        let originalAppearanceRaw = defaults.string(forKey: appearanceKey)
        let originalThemeRaw = defaults.string(forKey: themeKey)
        defer {
            if let originalAppearanceRaw { defaults.set(originalAppearanceRaw, forKey: appearanceKey) }
            else { defaults.removeObject(forKey: appearanceKey) }
            DesignThemeManager.shared.select(DesignTheme.resolve(id: originalThemeRaw))
            if let originalThemeRaw { defaults.set(originalThemeRaw, forKey: themeKey) }
            else { defaults.removeObject(forKey: themeKey) }
        }

        let state = AppState()
        let manager = DesignThemeManager.shared

        // 起点：把两轴都设成**确定**的值。注意 `select(_:)` 对「选的就是当前那个」会早退（不写盘），
        // 所以先岔开一次，保证「设成科技蓝」这一步真的落了一次盘 —— 否则下面的键断言会拿 nil 当证据。
        state.appearanceMode = .followSystem
        if manager.selected == .techBlue { manager.select(.roseGold) }
        manager.select(.techBlue)
        XCTAssertEqual(defaults.string(forKey: appearanceKey), AppearancePreference.followSystem.rawValue)
        XCTAssertEqual(defaults.string(forKey: themeKey), DesignTheme.techBlue.id)

        // ① 切配色轴：三遍（含回到起点），深浅轴的值与落盘键都不许动。
        for theme in DesignTheme.all + [DesignTheme.techBlue] {
            manager.select(theme)
            XCTAssertEqual(manager.selected, theme, "主题没选上")
            XCTAssertEqual(
                state.appearanceMode, .followSystem,
                "切到 \(theme.id) 之后深浅档被改了 —— 配色轴串进了深浅轴"
            )
            XCTAssertEqual(
                defaults.string(forKey: appearanceKey), AppearancePreference.followSystem.rawValue,
                "切到 \(theme.id) 之后深浅键被写了 —— 两轴共用一个键？"
            )
            XCTAssertEqual(
                defaults.string(forKey: themeKey), theme.id,
                "切到 \(theme.id) 之后主题键没跟上 —— 选了不落盘，重启就丢"
            )
        }

        // ② 切深浅轴：三态各一遍，主题的值与落盘键都不许动。
        for mode in AppearancePreference.allCases {
            state.appearanceMode = mode
            XCTAssertEqual(
                manager.selected, DesignTheme.techBlue,
                "切到 \(mode.rawValue) 之后主题被改了 —— 深浅轴串进了配色轴"
            )
            XCTAssertEqual(
                defaults.string(forKey: themeKey), DesignTheme.techBlue.id,
                "切到 \(mode.rawValue) 之后主题键被写了"
            )
            XCTAssertEqual(
                defaults.string(forKey: appearanceKey), mode.rawValue,
                "切到 \(mode.rawValue) 之后深浅键没跟上"
            )
        }

        // ③ 组合可达：两轴各自设成**非默认**值之后，两个键各自是各自的（谁也没覆盖谁）。
        state.appearanceMode = .alwaysLight
        manager.select(.roseGold)
        XCTAssertEqual(defaults.string(forKey: appearanceKey), AppearancePreference.alwaysLight.rawValue)
        XCTAssertEqual(defaults.string(forKey: themeKey), DesignTheme.roseGold.id)

        // ④ 组合真的**生效到取值那一层**：深浅档变了，取到的值表**还是这一份**（配色不跟着深浅走）。
        //    两轴的组合在**调用点现算**（`resolvesToDark` × `theme.palette`），生产侧不存组合对象 ——
        //    这里就用同一条路算一遍，证明「组合 = 两个独立取值」。
        let isDark = state.appearanceMode.resolvesToDark(systemIsDark: true)
        XCTAssertFalse(isDark, "「总是浅色」在系统深色下也必须出浅色")
        XCTAssertEqual(manager.theme.palette.id, .roseGold, "深浅档变了，配色却换了")

        // ⑤ 宿主语境覆盖（快照用）不落盘：拍一张图不许改用户偏好（判据 G ⑤ 的运行时对照）。
        let beforeOverride = defaults.string(forKey: themeKey)
        manager.beginHostTheme(.beanGreen)
        defer { manager.endHostTheme() }
        XCTAssertEqual(manager.theme, .beanGreen, "宿主覆盖没生效")
        XCTAssertEqual(defaults.string(forKey: themeKey), beforeOverride, "宿主覆盖写了盘")
        XCTAssertEqual(manager.selected, .roseGold, "宿主覆盖动了用户的落盘选择")
    }
}
