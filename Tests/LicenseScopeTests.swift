import XCTest
@testable import DoyahCore

/// `FR-STD-ALL-LIC-004`：授权范围口径 —— **桌面三块是一套、移动端不在管辖**。
///
/// 这两句话如果只写在文档里，下一跳加一个「移动端笔记」能力位、或者给 `governs` 加一个
/// 「移动端也受管」的分支，没有任何东西会红。所以钉成断言：
/// 位只有 1/2/4、`governs(移动端)` 恒 false、`grantedSurfaces` 永远出不来移动端。
final class LicenseScopeTests: XCTestCase {

    // MARK: 桌面三块是一套

    func testOneLicenseCoversExactlyTheThreeDesktopBlocks() {
        XCTAssertEqual(
            Set(LicenseScope.desktopSet),
            Set([.desktopWorkspaces, .desktopDatabase, .desktopNotes]),
            "一份许可证管的就是桌面这三块"
        )
        XCTAssertEqual(
            Set(LicenseScope.desktopSet.compactMap(\.capability)),
            Set([LicenseCapabilities.workspaces, .database, .notes]),
            "三块各有自己的位，且恰好就是这三个"
        )
    }

    /// 能力位只许由桌面三块组成（「一套」的机器判据）。多出第四块 = 我们不卖的组合。
    func testCapabilitiesOutsideTheDesktopSetAreRefused() {
        XCTAssertTrue(LicenseScope.onlyDesktopSurfaces(.all))
        XCTAssertTrue(LicenseScope.onlyDesktopSurfaces(.notesOnly))
        XCTAssertTrue(LicenseScope.onlyDesktopSurfaces([.workspaces, .database]))

        // 空集不是「最小档」，是坏件
        XCTAssertFalse(LicenseScope.onlyDesktopSurfaces([]))
        // 第四块（例如将来给移动端留的位）：不卖，判不合规
        XCTAssertFalse(LicenseScope.onlyDesktopSurfaces(LicenseCapabilities(rawValue: 1 << 3)))
        XCTAssertFalse(LicenseScope.onlyDesktopSurfaces([.all, LicenseCapabilities(rawValue: 1 << 3)]))
    }

    /// 单块授权不是商品（与 `LicenseEdition.from` 把「只授权一块」判成 `nil` 同一口径）。
    ///
    /// **例外是笔记那一块**：`notesOnly` 就是 Standard（入口档，三档里最底下那一档），
    /// 它是「只开一块」但确实是卖的一款 —— 判据要能分清这两种「一块」。
    func testSingleBlockIsNotAnEditionExceptNotes() {
        XCTAssertNil(LicenseEdition.from([.workspaces]), "只授权工作区一块不是我们卖的档位")
        XCTAssertNil(LicenseEdition.from([.database]), "只授权数据库一块不是我们卖的档位")
        XCTAssertEqual(LicenseEdition.from(.notesOnly), .standard, "只有笔记 = Standard（入口档）")
    }

    // MARK: 移动端不在管辖

    func testNoCapabilityBitIsReservedForMobile() {
        XCTAssertTrue(LicenseScope.ungovernedSurfaces.contains(.mobileNotes))
        XCTAssertNil(
            LicenseSurface.mobileNotes.capability,
            "移动端不建能力位：不建位就不存在「没授权」这种状态"
        )
        // 位的值只有 1 / 2 / 4 三个（1<<0 … 1<<2）—— 第四个位一出现就说明有人给移动端建了位
        XCTAssertEqual(LicenseCapabilities.all.rawValue, 0b111)
        XCTAssertNil(
            LicenseEdition.from(LicenseCapabilities(rawValue: 1 << 3)),
            "1<<3 这种位不该能推导出档位"
        )
    }

    func testMobileSurfacesAreNotGoverned() {
        for surface in LicenseSurface.allCases where surface.isMobile {
            XCTAssertFalse(LicenseScope.governs(surface), "\(surface.rawValue) 不归许可证管")
            XCTAssertNil(
                LicenseScope.requiredCapability(for: surface),
                "\(surface.rawValue) 没有能力位（nil = 不管辖，不是没授权）"
            )
        }
        for surface in LicenseSurface.allCases where surface.isDesktop {
            XCTAssertTrue(LicenseScope.governs(surface), "\(surface.rawValue) 归许可证管")
            XCTAssertNotNil(LicenseScope.requiredCapability(for: surface))
        }
    }

    /// 不管许可证是什么样，「开出的面」里都不会冒出移动端 —— 结构上就进不来。
    func testGrantedSurfacesNeverIncludeMobile() {
        let samples: [LicenseCapabilities] = [
            .all, .notesOnly, [.workspaces, .database], [], [.database],
            LicenseCapabilities(rawValue: 1 << 3),
            LicenseCapabilities(rawValue: 0b1111),
        ]
        for capabilities in samples {
            let surfaces = LicenseScope.grantedSurfaces(capabilities)
            XCTAssertFalse(
                surfaces.contains(.mobileNotes),
                "能力位 \(capabilities.rawValue) 不该开出移动端"
            )
            XCTAssertTrue(
                surfaces.allSatisfy { LicenseScope.desktopSet.contains($0) },
                "开出的面只许来自桌面三块"
            )
        }
    }

    /// Standard 只开笔记那一块（与 `LicenseEdition.standard.capabilities` 同一个事实）。
    func testStandardGrantsOnlyTheNotesSurface() {
        XCTAssertEqual(LicenseScope.grantedSurfaces(.notesOnly), [.desktopNotes])
        XCTAssertEqual(
            Set(LicenseScope.grantedSurfaces(.all)),
            Set(LicenseScope.desktopSet)
        )
    }
}
