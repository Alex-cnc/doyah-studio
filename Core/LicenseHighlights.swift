import Foundation

/// 「关于」页上那段**给人看的能力描述**（主人 2026-10-29 令：
/// 「根据 license 控制的功能增加产品能力描述，只需要最亮点的主要功能，用普通用户看得懂的语言」）。
///
/// 三条口径，每条都对着一种写坏的方式：
/// 1. **只写亮点**：五条封顶，一条只讲一件事 —— 写成功能清单就没人读；
/// 2. **说人话**：不出现内部编号（`FR-` / `§` / `Q`）、不出现「能力位」「档位」这类内部词；
/// 3. **和授权对得上**：每条挂 `required` 能力位，界面据此读「已含」或「需某版」，
///    口径与 `LicenseEditionCatalog` 同一个来源（`LicenseEdition.capabilities`），不另立一套。
public struct LicenseHighlight: Equatable, Sendable {

    /// 小标题（用普通话说「这件事是什么」）。
    public var titleKey: LKey
    /// 一句话（说清「你能拿它干什么」，不是「它有什么字段」）。
    public var lineKey: LKey
    /// 哪一档起有这个能力（决定「需 X 版」那一行字）。
    public var edition: LicenseEdition
    /// 需要的能力位（判定「我现在有没有」）。
    public var required: LicenseCapabilities

    public init(titleKey: LKey, lineKey: LKey,
                edition: LicenseEdition, required: LicenseCapabilities) {
        self.titleKey = titleKey
        self.lineKey = lineKey
        self.edition = edition
        self.required = required
    }
}

public enum LicenseHighlights {

    /// 五条，顺序即界面顺序：**先说他天天要用的**（查库 / 写代码 / 让 AI 干活），再说记东西。
    public static let all: [LicenseHighlight] = [
        LicenseHighlight(titleKey: .licDoDatabaseTitle, lineKey: .licDoDatabaseLine,
                         edition: .pro, required: [.database]),
        LicenseHighlight(titleKey: .licDoCodeTitle, lineKey: .licDoCodeLine,
                         edition: .pro, required: [.workspaces]),
        LicenseHighlight(titleKey: .licDoAgentTitle, lineKey: .licDoAgentLine,
                         edition: .pro, required: [.workspaces]),
        LicenseHighlight(titleKey: .licDoNotesTitle, lineKey: .licDoNotesLine,
                         edition: .standard, required: [.notes]),
        LicenseHighlight(titleKey: .licDoLinkTitle, lineKey: .licDoLinkLine,
                         edition: .ultra, required: [.notes, .database]),
    ]

    /// 这条能力**现在**有没有（按能力位判，不按档位名判 —— 名字会改，位不会）。
    public static func isIncluded(_ highlight: LicenseHighlight,
                                  in capabilities: LicenseCapabilities) -> Bool {
        !highlight.required.isEmpty && capabilities.isSuperset(of: highlight.required)
    }

    /// 当前档位下，这条要不要标「需 X 版」（已含的不标）。
    public static func upgradeTarget(for highlight: LicenseHighlight,
                                     in capabilities: LicenseCapabilities) -> LicenseEdition? {
        isIncluded(highlight, in: capabilities) ? nil : highlight.edition
    }
}
