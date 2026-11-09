import AppKit
import XCTest

/// `check-menu-language.py` 的 Swift 版：**菜单栏（AppKit 那一层）的每一项都要跟当前界面语言同语**
/// （队列 `L-145` 判据 · 内测清单 **丙2** 及其下一层）。
///
/// 为什么要这一条：界面快照拍不到菜单栏（它不在任何视图里）、源码判据也读不到它
/// （`NSMenuItem.title` 是运行期值）⇒ 键都登记了、表也齐全、门禁全绿，菜单栏却停在**启动语言**上
/// （实测：切完语言后 AppKit 会把 File / Edit / View / Window / Help 的顶层标题按启动语言
/// 再本地化一次，**不发任何通知**）。第二代的由头是需求提出者的原话：「中文版中显示菜单里
/// 还有 2 个英文菜单：show tab bar 和 show all tabs，窗口菜单中有 Fill、Center…」——
/// 那批项是 AppKit 在**菜单被展开的那一刻**才插进树里的，不展开就枚举不到（「没判」在观感上等于通过）。
///
/// 判的四条（每一档启动两遍：英文→中文 / 中文→英文，走用户真实的语言切换入口）：
/// ① **表内一致**：认得出的项，现标题必须等于表里该键在目标语言下的文案（**判据自己算**，
///    不信 dump 自述）；② **表外兜底**：每一项的可见标题都要跟当前界面语言同语（中文界面下不许
///    出现没有汉字的项、英文界面下不许含汉字；豁免只有应用显示名 / 语言自身的显示名 / 窗口标题）；
/// ③ **未覆盖项如实列出**：认不出又不在豁免里的项逐条点名并判红；必检的展开族（标签页栏 /
///    所有标签页 / 填充 / 居中 / 移动与调整大小 / 全屏幕平铺 / 平铺位 / 窗口标签页那一族）
///    枚举不到就是「未覆盖」—— 硬族缺即红，条件族单档缺如实登记、两档都没出现才红；
/// ④ **空跑防护 + 形状**：条目数与识别项数下限、五个系统菜单顶层必须在场、坏行判红。
///
/// 跑法（两条路，与脚本一致）：
/// · **判定逻辑**（`judge` / `judgeAll`）常跑：合成 dump 的正负例在每次 `swift test` 都跑；
/// · **真启动两档**只在 `DOYAH_MENU_LANGUAGE_GATE=1` 时跑（要 `dist/DoyahStudio.app`，
///   由 `verify-all.sh` 第 11 项在打包之后调用）；没有可执行文件时**跳过**并说明原因。
final class MenuLanguageGateTests: XCTestCase {

    /// 工程根（`#filePath` 反推，不依赖 cwd）—— 本 target 不依赖测试支持文件。
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    enum Gate {
        /// 汉字（`\u4e00-\u9fff`）—— 与脚本同一字符集。
        static func hasHan(_ text: String) -> Bool {
            text.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
        }

        static let sectionMark = "# DOYAH-MENU-DUMP v1"
        static let sectionIds = ["A", "C", "B"]
        static let scenarios: [(name: String, launch: String, language: String)] = [
            ("switch-en-to-zh", "en", "zh-Hans"),
            ("switch-zh-to-en", "zh-Hans", "en"),
        ]
        static let systemTopLevelKeys = ["menuSystemFile", "menuSystemEdit", "menuSystemView", "menuSystemWindow", "menuSystemHelp"]
        static let languageTitles = ["简体中文", "English"]
        static let floors: [String: (items: Int, recognized: Int)] = [
            "A": (50, 45), "C": (80, 75),
        ]

        struct Line {
            var depth: Int
            var kind: String
            var selector: String
            var title: String
            var key: String
            var target: String
            var verdict: String
            var submenuTitle: String = ""
        }

        struct Stats {
            var items = 0
            var recognized = 0
            var unrecognized = 0
            var mismatch = 0
            var uncovered = 0
            var coverage: [String: Bool] = [:]
            var notes: [String] = []
        }

        /// 认不出的项里，允许它认不出的理由；不在豁免里的返回 nil。
        static func whitelistReason(_ item: Line, appName: String) -> String? {
            if item.selector == "menuAction:", languageTitles.contains(item.title) { return "语言自身的显示名" }
            if item.selector == "submenuAction:", item.title == appName { return "应用显示名（专有名词）" }
            if item.selector == "makeKeyAndOrderFront:" { return "窗口列表项（标题 = 窗口标题）" }
            return nil
        }

        /// 必检的「展开族」：AppKit 在**菜单展开时**才插进树里的项。
        /// 每一项 = (名字, 判据, 是否条件性)。条件族随窗口标签页状态浮动。
        static let requiredOpenItems: [(label: String, match: (Line) -> Bool, conditional: Bool)] = [
            ("显示菜单：标签页栏（`toggleTabBar:`）", { $0.selector == "toggleTabBar:" }, true),
            ("显示菜单：所有标签页（`toggleTabOverview:`）", { $0.selector == "toggleTabOverview:" }, true),
            ("窗口菜单：填充 / 居中（`_zoomFill:` / `_zoomCenter:`）", { ["_zoomFill:", "_zoomCenter:"].contains($0.selector) }, false),
            ("窗口菜单：移动与调整大小（子菜单标题，无 selector）", { ["Move & Resize", "移动与调整大小"].contains($0.title) }, false),
            ("窗口菜单：全屏幕平铺（子菜单标题，无 selector）", { ["Full Screen Tile", "全屏幕平铺"].contains($0.title) }, false),
            ("窗口菜单：平铺位（左 / 右 / 上 / 下）", { ["_zoomLeft:", "_zoomRight:", "_zoomTop:", "_zoomBottom:"].contains($0.selector) }, false),
            ("窗口菜单：分组标题（二等分 / 四等分 / 排列）", { ["Halves", "Quarters", "Arrange", "二等分", "四等分", "排列"].contains($0.title) }, false),
            ("窗口菜单：恢复上一个大小（`_zoomUntile:`）", { $0.selector == "_zoomUntile:" }, false),
            ("窗口菜单：全部最小化 / 全部缩放", { ["miniaturizeAll:", "zoomAll:"].contains($0.selector) }, false),
            ("窗口菜单：窗口标签页那一族（上一个 / 下一个 / 新窗口 / 合并）",
             { ["selectPreviousTab:", "selectNextTab:", "moveTabToNewWindow:", "mergeAllWindows:"].contains($0.selector) }, false),
        ]

        static func parseSections(_ text: String) -> (sections: [String: [Line]], problems: [String]) {
            var problems: [String] = []
            var sections: [String: [Line]] = [:]
            var current: String?
            for raw in text.components(separatedBy: "\n") {
                if raw.hasPrefix(sectionMark) {
                    let marker = raw.dropFirst(sectionMark.count)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " —-"))
                    current = marker.split(separator: " ").first.map(String.init) ?? "?"
                    sections[current!, default: []] = []
                    continue
                }
                if raw.hasPrefix("#") || raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                guard let section = current else {
                    problems.append("段标之前就有条目行：\(raw)")
                    continue
                }
                let parts = raw.components(separatedBy: "|")
                guard parts.count >= 7 else {
                    problems.append("坏行（段数 \(parts.count) < 7）：\(raw)")
                    continue
                }
                guard let depth = Int(parts[0]) else {
                    problems.append("坏行（深度不是数字）：\(raw)")
                    continue
                }
                var verdict = parts[6]
                var submenu = ""
                if let range = verdict.range(of: " submenu=") {
                    submenu = String(verdict[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    verdict = String(verdict[..<range.lowerBound])
                }
                sections[section, default: []].append(
                    Line(depth: depth, kind: parts[1], selector: parts[2], title: parts[3],
                         key: parts[4], target: parts[5], verdict: verdict, submenuTitle: submenu)
                )
            }
            if sections.isEmpty {
                problems.append("dump 里找不到段标 `\(sectionMark)`（探针没写出来 / 格式变了）")
            }
            return (sections, problems)
        }

        static func appName(_ sections: [String: [Line]]) -> String {
            for lines in sections.values {
                for item in lines where item.depth == 0 && item.kind != "separator" && !item.title.isEmpty {
                    return item.title
                }
            }
            return "?"
        }

        /// 可见标题的语言是否跟**当前界面语言**同语。返回 nil = 同语。
        static func languageProblem(_ title: String, _ language: String) -> String? {
            let han = Gate.hasHan(title)
            if language == "zh-Hans" {
                return han ? nil : "中文界面下这一项没有汉字（疑似英文 / 停在启动语言）"
            }
            return han ? "英文界面下这一项含汉字（疑似中文 / 停在启动语言）" : nil
        }

        static func judgeSection(_ sectionId: String, _ lines: [Line], language: String, appName: String)
            -> (problems: [String], stats: Stats) {
            var problems: [String] = []
            var stats = Stats()
            var keysPresent: Set<String> = []
            var items: [Line] = []
            for item in lines where item.kind != "separator" {
                items.append(item)
                stats.items += 1
                let exempt = whitelistReason(item, appName: appName)
                if item.target != "-" {
                    stats.recognized += 1
                    keysPresent.insert(item.key)
                    if item.target != item.title {
                        stats.mismatch += 1
                        problems.append("[\(sectionId)] 停在启动语言：`\(item.title)`（应得 `\(item.target)` / 键 `\(item.key)`）")
                    } else if item.verdict.hasPrefix("MISMATCH") {
                        problems.append("[\(sectionId)] dump 自述与实测不符（自述 MISMATCH、实测一致）：`\(item.title)`")
                    }
                } else {
                    stats.unrecognized += 1
                    if exempt == nil {
                        stats.uncovered += 1
                        problems.append("[\(sectionId)] 未覆盖项（认不出 ⇒ 自愈不碰它 ⇒ 停在启动语言）："
                                        + "`\(item.title)` selector=`\(item.selector)`")
                    }
                }
                if exempt == nil, let problem = languageProblem(item.title, language) {
                    problems.append("[\(sectionId)] \(problem)：`\(item.title)` selector=`\(item.selector)`")
                }
                if !item.submenuTitle.isEmpty, exempt == nil,
                   let problem = languageProblem(item.submenuTitle, language) {
                    problems.append("[\(sectionId)] \(problem)（子菜单自己的标题）：`\(item.submenuTitle)` selector=`\(item.selector)`")
                }
            }
            if let floor = floors[sectionId] {
                if stats.items < floor.items {
                    problems.append("[\(sectionId)] 空跑防护：条目数 \(stats.items) < 下限 \(floor.items)")
                }
                if stats.recognized < floor.recognized {
                    problems.append("[\(sectionId)] 空跑防护：识别出来的项 \(stats.recognized) < 下限 \(floor.recognized)")
                }
            }
            if sectionId == "A" {
                let missing = systemTopLevelKeys.filter { !keysPresent.contains($0) }
                if !missing.isEmpty {
                    problems.append("[A] 系统菜单顶层标题不在场：\(missing.joined(separator: " / "))（菜单树没建成 ⇒ 这一档不算过）")
                }
            }
            if sectionId == "C" {
                for required in requiredOpenItems {
                    let present = items.contains(where: required.match)
                    stats.coverage[required.label] = present
                    if present { continue }
                    if required.conditional {
                        stats.notes.append("未覆盖（如实登记 · 不作通过）：条件性必检项 `\(required.label)` 本段没枚举到")
                    } else {
                        problems.append("[C] 未覆盖：必检项 `\(required.label)` 在本段里**枚举不到**"
                                        + "（AppKit 没插进来 / 探针没展开 / 写法变了）—— 枚举不到不许默认通过")
                    }
                }
            }
            return (problems, stats)
        }

        struct AllReading {
            var problems: [String] = []
            var notes: [String] = []
            var stats: [String: Stats] = [:]
        }

        static func judgeAll(_ dumps: [String: String]) -> AllReading {
            var reading = AllReading()
            for scenario in scenarios {
                guard let text = dumps[scenario.name] else {
                    reading.problems.append("档 `\(scenario.name)` 没有 dump")
                    continue
                }
                let parsed = parseSections(text)
                reading.problems.append(contentsOf: parsed.problems.map { "档 `\(scenario.name)`：\($0)" })
                let name = appName(parsed.sections)
                for sectionId in sectionIds {
                    guard let lines = parsed.sections[sectionId] else {
                        reading.problems.append("档 `\(scenario.name)`：缺 `\(sectionId)` 段（探针没展开菜单 / 格式变了 ⇒ 这一档判不了）")
                        continue
                    }
                    let one = judgeSection(sectionId, lines, language: scenario.language, appName: name)
                    reading.stats["\(scenario.name)/\(sectionId)"] = one.stats
                    reading.problems.append(contentsOf: one.problems.map { "档 `\(scenario.name)` 段 `\(sectionId)`：\($0)" })
                    reading.notes.append(contentsOf: one.stats.notes.map { "\(scenario.name)/\(sectionId) · \($0)" })
                }
            }
            if dumps.count != scenarios.count {
                reading.problems.append("两档没有都跑到（拿到 \(dumps.count) 档）")
            }
            // 条件族：单档缺 = 如实登记；**两档都没出现** = 判红（只可能是探针没展开 / 写法变了）。
            var seen: [String: Bool] = [:]
            for one in reading.stats.values {
                for (label, present) in one.coverage { seen[label] = (seen[label] ?? false) || present }
            }
            for required in requiredOpenItems where required.conditional {
                if seen[required.label] != true {
                    reading.problems.append("条件性必检项 `\(required.label)` 在这一轮两档**一次都没枚举到** ⇒ 判红"
                                            + "（探针没展开菜单 / AppKit 改了写法）")
                }
            }
            return reading
        }
    }

    // MARK: - 合成 dump（判定逻辑的证据，每次 swift test 都跑）

    enum Synthetic {
        static let chineseCore: [String] = [
            "0|UNRECOGNIZED|submenuAction:|Doyah Studio|submenuAction:|-|unknown submenu=Doyah Studio",
            "1|system|orderFrontStandardAboutPanel:|关于 Doyah Studio|menuSystemAbout|关于 Doyah Studio|ok",
            "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
            "1|title|menuAction:|新建查询|menuNewQuery|新建查询|ok",
            "0|title|submenuAction:|编辑|menuSystemEdit|编辑|ok",
            "1|system|undo:|撤销|menuSystemUndo|撤销|ok",
            "0|title|submenuAction:|显示|menuSystemView|显示|ok",
            "1|title|menuAction:|工作区视图|menuViewWorkspace|工作区视图|ok",
            "0|title|submenuAction:|语言|menuLanguage|语言|ok",
            "1|UNRECOGNIZED|menuAction:|简体中文|menuAction:|-|unknown",
            "1|UNRECOGNIZED|menuAction:|English|menuAction:|-|unknown",
            "0|title|submenuAction:|窗口|menuSystemWindow|窗口|ok",
            "1|system|performMiniaturize:|最小化|menuSystemMinimize|最小化|ok",
            "1|system|performZoom:|缩放|menuSystemZoom|缩放|ok",
            "1|system|arrangeInFront:|全部置于顶层|menuSystemBringAllToFront|全部置于顶层|ok",
            "1|UNRECOGNIZED|makeKeyAndOrderFront:|Doyah Studio - 工作区|makeKeyAndOrderFront:|-|unknown",
            "0|title|submenuAction:|帮助|menuSystemHelp|帮助|ok",
            "1|system|toggleSidebar:|显示/隐藏边栏|menuSystemToggleSidebar|显示/隐藏边栏|ok",
        ]
        /// **只有展开菜单才会出现**的那一族（C 段相对 A 段多出来的部分 = 本代判据的覆盖面）。
        static let chineseOpen: [String] = [
            "1|system|toggleTabBar:|显示标签页栏|menuSystemShowTabBar|显示标签页栏|ok",
            "1|system|toggleTabOverview:|显示所有标签页|menuSystemShowAllTabs|显示所有标签页|ok",
            "1|system|miniaturizeAll:|全部最小化|menuSystemMinimizeAll|全部最小化|ok",
            "1|system|zoomAll:|全部缩放|menuSystemZoomAll|全部缩放|ok",
            "1|system|_zoomFill:|填充|menuSystemFill|填充|ok",
            "1|system|_zoomCenter:|居中|menuSystemCenter|居中|ok",
            "1|system|submenuAction:|移动与调整大小|menuSystemMoveAndResize|移动与调整大小|ok submenu=移动与调整大小",
            "2|system|-|二等分|menuSystemHalves|二等分|ok",
            "2|system|_zoomLeft:|左侧|menuSystemZoomLeft|左侧|ok",
            "2|system|_zoomRight:|右侧|menuSystemZoomRight|右侧|ok",
            "2|system|_zoomTop:|顶部|menuSystemZoomTop|顶部|ok",
            "2|system|_zoomBottom:|底部|menuSystemZoomBottom|底部|ok",
            "2|system|_zoomUntile:|恢复上一个大小|menuSystemReturnToPreviousSize|恢复上一个大小|ok",
            "1|system|submenuAction:|全屏幕平铺|menuSystemFullScreenTile|全屏幕平铺|ok submenu=全屏幕平铺",
            "2|system|_tileLeft:|屏幕左侧|menuSystemTileLeft|屏幕左侧|ok",
            "2|system|_tileRight:|屏幕右侧|menuSystemTileRight|屏幕右侧|ok",
            "1|system|selectPreviousTab:|显示上一个标签页|menuSystemShowPreviousTab|显示上一个标签页|ok",
            "1|system|selectNextTab:|显示下一个标签页|menuSystemShowNextTab|显示下一个标签页|ok",
            "1|system|moveTabToNewWindow:|将标签页移到新窗口|menuSystemMoveTabToNewWindow|将标签页移到新窗口|ok",
            "1|system|mergeAllWindows:|合并所有窗口|menuSystemMergeAllWindows|合并所有窗口|ok",
        ]
        static let filler: [String] = [
            "1|title|menuAction:|外观…|menuAppearance|外观…|ok",
            "1|title|menuAction:|连接设置…|menuConnectionSettings|连接设置…|ok",
            "1|title|menuAction:|数据库统计|databaseStatsTitle|数据库统计|ok",
            "1|title|menuAction:|服务器级对象…|menuServerObjects|服务器级对象…|ok",
            "1|title|menuAction:|Schema 对比与同步|schemaDiffTitle|Schema 对比与同步|ok",
            "1|title|menuAction:|ER 图…|menuERDiagram|ER 图…|ok",
        ]

        static func section(_ id: String, _ headline: String, _ rows: [String]) -> [String] {
            [Gate.sectionMark + " — " + id + " " + headline] + rows
        }

        struct Options {
            var mismatch = false
            var rogue = false
            var dropHelp = false
            var short = false
            var badLine = false
            var noMark = false
            var missingOpen = false
            var staleSubmenu = false
            var englishInChinese = false
            var chineseInEnglish = false
            var dropC = false
            var missingTabs = false
        }

        static func dump(_ options: Options = Options()) -> String {
            var a = chineseCore + Array(repeating: filler, count: 12).flatMap { $0 }
            var c = a + chineseOpen
            if options.mismatch {
                let wrong = "0|title|submenuAction:|File|menuSystemFile|文件|MISMATCH"
                a[2] = wrong
                c[2] = wrong
            }
            if options.englishInChinese {
                let row = "1|system|someNewAction:|Undo|menuSystemUndo|Undo|ok"
                a.append(row)
                c.append(row)
            }
            if options.chineseInEnglish {
                let row = "1|system|someNewAction:|文档设置|someNewAction:|文档设置|ok"
                a.append(row)
                c.append(row)
            }
            if options.rogue {
                let row = "0|UNRECOGNIZED|someNewSystemItem:|Something|someNewSystemItem:|-|unknown"
                a.append(row)
                c.append(row)
            }
            if options.dropHelp {
                a = a.filter { !$0.contains("menuSystemHelp") }
                c = c.filter { !$0.contains("menuSystemHelp") }
            }
            if options.missingTabs {
                c = c.filter { !$0.contains("toggleTabBar:") && !$0.contains("toggleTabOverview:") }
            }
            if options.staleSubmenu {
                c = c.map { $0.replacingOccurrences(of: "submenu=移动与调整大小", with: "submenu=Move & Resize") }
            }
            if options.missingOpen {
                c = c.filter { !$0.contains("_zoomFill:") && !$0.contains("_zoomCenter:") }
            }
            if options.short {
                a = Array(a.prefix(3))
                c = Array(c.prefix(3))
            }
            var rows = section("A", "原样（未展开菜单）", a)
            if !options.dropC {
                rows += section("C", "各菜单展开过一次之后（含 AppKit 展开时才插进来的项）", c)
            }
            rows += section("B", "展开菜单时那条自愈路之后", c)
            var text = rows.joined(separator: "\n") + "\n# 尾注\n"
            if options.noMark {
                text = rows.filter { !$0.hasPrefix(Gate.sectionMark) }.joined(separator: "\n") + "\n"
            }
            if options.badLine {
                text = text.replacingOccurrences(of: "\n# 尾注\n", with: "\n这不是一行合法的 dump\n# 尾注\n")
            }
            return text
        }

        /// 合成 dump 的英文字面（造英文方向的红绿路；真方向的证据是真启动那两档）。
        static let english: [String: String] = [
            "Doyah Studio": "Doyah Studio", "关于 Doyah Studio": "About Doyah Studio",
            "文件": "File", "新建查询": "New Query", "编辑": "Edit", "撤销": "Undo",
            "显示": "View", "工作区视图": "Workspace View", "语言": "Language", "窗口": "Window",
            "最小化": "Minimize", "缩放": "Zoom", "全部置于顶层": "Bring All to Front", "帮助": "Help",
            "显示/隐藏边栏": "Toggle Sidebar", "Doyah Studio - 工作区": "Doyah Studio - 工作区",
            "显示标签页栏": "Show Tab Bar", "显示所有标签页": "Show All Tabs", "全部最小化": "Minimize All",
            "全部缩放": "Zoom All", "填充": "Fill", "居中": "Center", "移动与调整大小": "Move & Resize",
            "二等分": "Halves", "左侧": "Left", "右侧": "Right", "顶部": "Top", "底部": "Bottom",
            "恢复上一个大小": "Return to Previous Size", "全屏幕平铺": "Full Screen Tile",
            "屏幕左侧": "Left of Screen", "屏幕右侧": "Right of Screen",
            "显示上一个标签页": "Show Previous Tab", "显示下一个标签页": "Show Next Tab",
            "将标签页移到新窗口": "Move Tab to New Window", "合并所有窗口": "Merge All Windows",
            "外观…": "Appearance…", "连接设置…": "Connection Settings…", "数据库统计": "Database statistics",
            "服务器级对象…": "Server-level Objects…", "Schema 对比与同步": "Schema diff and sync", "ER 图…": "ER Diagram…",
        ]

        static func toEnglish(_ text: String) -> String {
            let lines = text.components(separatedBy: "\n").map { line -> String in
                if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty || !line.contains("|") {
                    return line
                }
                var parts = line.components(separatedBy: "|")
                guard parts.count >= 7 else { return line }
                parts[3] = english[parts[3]] ?? parts[3]
                if parts[5] != "-" { parts[5] = english[parts[5]] ?? parts[5] }
                if let range = parts[6].range(of: " submenu=") {
                    let tail = String(parts[6][range.upperBound...])
                    parts[6] = String(parts[6][..<range.lowerBound]) + " submenu=" + (english[tail] ?? tail)
                }
                return parts.joined(separator: "|")
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - 判定逻辑的负例（常跑）

    func testSyntheticGreenPairPasses() {
        let reading = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(reading.problems.isEmpty, "两档合成 dump 应判绿：\(reading.problems)")
    }

    func testStoppedAtLaunchLanguageIsRed() {
        let reading = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(mismatch: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(reading.problems.contains { $0.contains("停在启动语言") }, "停在启动语言必须判红：\(reading.problems)")
    }

    func testUnrecognizedUnregisteredItemIsRed() {
        let reading = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(rogue: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(reading.problems.contains { $0.contains("未覆盖项") }, "认不出且没登记必须判红：\(reading.problems)")
    }

    func testMissingSystemMenuAndEmptyRunAreRed() {
        let missing = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(dropHelp: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(missing.problems.contains { $0.contains("系统菜单顶层标题不在场") }, "缺 Help 必须判红：\(missing.problems)")

        let short = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(short: true)),
                                   "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump(Synthetic.Options(short: true)))])
        XCTAssertTrue(short.problems.contains { $0.contains("空跑防护") }, "条目数不够必须判红：\(short.problems)")
    }

    func testMissingOpenFamilyAndSectionShapeAreRed() {
        let missing = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(missingOpen: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(missing.problems.contains { $0.contains("未覆盖：必检项") }, "展开族缺项必须判红：\(missing.problems)")

        let noSection = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(dropC: true)),
                                       "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(noSection.problems.contains { $0.contains("缺 `C` 段") }, "缺 C 段必须判红：\(noSection.problems)")

        let bad = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(badLine: true)),
                                 "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(bad.problems.contains { $0.contains("坏行") }, "坏行必须判红：\(bad.problems)")

        let noMark = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(noMark: true)),
                                    "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(noMark.problems.contains { $0.contains("找不到段标") }, "没有段标必须判红：\(noMark.problems)")
    }

    /// 表外兜底：表里**也**写错了（target == title）时，语言一致性必须抓到。
    func testLanguageFallbackCatchesWrongTable() {
        let zh = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(englishInChinese: true)),
                                "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(zh.problems.contains { $0.contains("没有汉字") }, "中文界面下的英文项必须判红：\(zh.problems)")

        let en = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(),
                                "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump(Synthetic.Options(chineseInEnglish: true)))])
        XCTAssertTrue(en.problems.contains { $0.contains("含汉字") }, "英文界面下的中文项必须判红：\(en.problems)")
    }

    /// 子菜单**自己的标题**也要同语（真 dump 里出现过 `item 标题已中文、submenu 还停在 `Move & Resize`）。
    func testStaleSubmenuTitleIsRed() {
        let reading = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(staleSubmenu: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(reading.problems.contains { $0.contains("子菜单自己的标题") }, "子菜单标题必须判红：\(reading.problems)")
    }

    /// 条件族（标签页栏那两条）：单档缺 ⇒ 如实登记、不判红；两档都没出现 ⇒ 判红。
    func testConditionalFamilyRules() {
        let oneSide = Gate.judgeAll(["switch-en-to-zh": Synthetic.dump(Synthetic.Options(missingTabs: true)),
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(oneSide.problems.isEmpty, "单档缺条件族应判绿并如实登记：\(oneSide.problems)")
        XCTAssertTrue(oneSide.notes.contains { $0.contains("未覆盖（如实登记") }, "应留下如实登记的读数：\(oneSide.notes)")

        let bothSides = Gate.judgeAll([
            "switch-en-to-zh": Synthetic.dump(Synthetic.Options(missingTabs: true)),
            "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump(Synthetic.Options(missingTabs: true))),
        ])
        XCTAssertTrue(bothSides.problems.contains { $0.contains("一次都没枚举到") }, "两档都缺必须判红：\(bothSides.problems)")
    }

    /// 只改一个字节（File → 应得 文件）就该判红。
    func testSingleByteDriftIsRed() {
        let drifted = Synthetic.dump().replacingOccurrences(
            of: "0|title|submenuAction:|文件|menuSystemFile|文件|ok",
            with: "0|title|submenuAction:|File|menuSystemFile|文件|ok")
        let reading = Gate.judgeAll(["switch-en-to-zh": drifted,
                                     "switch-zh-to-en": Synthetic.toEnglish(Synthetic.dump())])
        XCTAssertTrue(reading.problems.contains { $0.contains("停在启动语言") }, "一个字节的漂移必须判红：\(reading.problems)")
    }

    // MARK: - 真启动两档（要 dist/DoyahStudio.app；由 verify-all 第 11 项调用）

    func testRealMenuTreeFollowsInterfaceLanguage() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_MENU_LANGUAGE_GATE"] == "1" else {
            throw XCTSkip("真启动两档只在打包之后跑（DOYAH_MENU_LANGUAGE_GATE=1，见 Scripts/verify-all.sh 第 11 项）")
        }
        let binary = Self.packageRoot.appendingPathComponent("dist/DoyahStudio.app/Contents/MacOS/DoyahStudio")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("没有可执行文件 \(binary.path)（先 ./Scripts/build-app.sh）")
        }
        var dumps: [String: String] = [:]
        var problems: [String] = []
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-menu-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let domain = "studio.doyah.DoyahStudio"
        let backup = scratch.appendingPathComponent("prefs.plist")
        _ = run("/usr/bin/defaults", ["export", domain, backup.path])
        defer { _ = run("/usr/bin/defaults", ["import", domain, backup.path]) }

        for scenario in Gate.scenarios {
            let target = scratch.appendingPathComponent("\(scenario.name).txt")
            if let ok = try? collect(binary: binary, launch: scenario.launch, switchTo: scenario.language,
                                     target: target), ok {
                dumps[scenario.name] = try String(contentsOf: target, encoding: .utf8)
            } else {
                problems.append("档 `\(scenario.name)` 没跑出可用的 dump（等了超时 / 进程提前退出）")
            }
        }
        let reading = Gate.judgeAll(dumps)
        problems.append(contentsOf: reading.problems)
        XCTAssertTrue(problems.isEmpty, "菜单栏这一层没过（\(problems.count) 条）：\n" + problems.joined(separator: "\n"))
    }

    private func collect(binary: URL, launch: String, switchTo: String, target: URL) throws -> Bool {
        try? FileManager.default.removeItem(at: target)
        var environment = ProcessInfo.processInfo.environment
        environment["DOYAH_MENU_DUMP"] = target.path
        environment["DOYAH_MENU_DUMP_DELAY"] = "8"
        environment["DOYAH_MENU_DUMP_SWITCH"] = switchTo
        environment["DOYAH_MENU_DUMP_OPEN"] = "1"
        let process = Process()
        process.executableURL = binary
        process.arguments = ["-AppleLanguages", "(\(launch))", "-app.language", launch]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
               let size = attributes[.size] as? Int, size > 0 {
                // 落盘是 `write(atomically:)`（换名），不会写一半；等半秒再读。
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            if !process.isRunning { return false }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    @discardableResult
    private func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
