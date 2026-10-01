import AppKit
import DoyahCore

/// 菜单栏的语言自愈（NFR-I18N-03）。
///
/// **为什么需要「自愈」而不是只在切换时改一次**
///
/// SwiftUI 只重建 `.commands` 里的菜单标题，菜单里的叶子项不会随语言刷新
/// （实测记录见 `DoyahCore.MenuLocalization` 的注释）。既然 SwiftUI 不会把它刷新，
/// 我们就只能自己改 `NSMenuItem.title`；但只在「切换语言」那一刻改是不可靠的：
/// 之后任何一次 SwiftUI 重建菜单图、系统重新加载 NIB/菜单、或上一次改动没落到全部条目，
/// 都会留下中英混排的菜单——而用户看到的正是这个。
///
/// 所以除了切换时改，还在**菜单每次展开前**再自愈一次：
/// 用户唯一能看见菜单的时刻就是它被展开时，在那里保证正确，
/// 就不依赖于"之前某次改动有没有生效"。收起时再兜一次，避免残留到下一次。
///
/// 为什么不干脆整棵菜单自己用 AppKit 建：那样要放弃 SwiftUI 的
/// `.keyboardShortcut` / `CommandGroup(replacing:)` 等系统集成，
/// 还要自己重造「文件 / 编辑 / 窗口」这些系统菜单，代价远大于收益。
enum MainMenuLocalizer {

    @MainActor private static var observing = false

    /// 「补刷窗口」的截止时刻：语言切换后的头几秒里，**窗口每次刷新都顺手把菜单栏对齐一次**。
    ///
    /// 为什么需要这么密：`setLanguage` 之后 SwiftUI 会重建命令图，那次重建把系统菜单标题恢复成
    /// **启动语言**（实测重建落在切换后 0.2~0.5 秒之间）—— 只在掐好的时间点补刷，
    /// 总有一小段窗口对不上（菜单栏会「新语言 → 启动语言 → 新语言」闪一下）。
    /// 挂到窗口刷新上，这段窗口就缩到一帧以内；代价是走一遍菜单、**不一样才写 title**。
    @MainActor private static var healUntil: Date = .distantPast

    /// 补刷窗口的长度（秒）。
    ///
    /// 为什么是「一段窗口」而不是某个时间点：SwiftUI 重建命令图之后，AppKit 还会按**启动语言**
    /// 把系统菜单（`File` / `Edit` / `View` / `Window` / `Help`）的标题再本地化一次 —— 实测这一笔
    /// 落在我们改完之后 **0.3 秒内**、且**不发任何通知**（队列 `L-145` 第 141 轮的时间线）。
    /// 只在某一刻改一次，那一笔就盖在它后面；窗口开着，这几秒里窗口每次刷新都会再对齐一遍。
    private static let healWindow: TimeInterval = 3

    /// 「回头看」的时刻表（秒）—— 改完之后回头验一遍，还差就再改，改得动才继续。
    ///
    /// 为什么需要它（队列 `L-145` 第 141 轮实测）：AppKit 在启动 / 命令图重建之后，会把五个
    /// **系统菜单**（`File` / `Edit` / `View` / `Window` / `Help`）的顶层标题按**启动语言**再本地化
    /// 一次 —— 那一笔落在我们改完 **0.3 秒内**，而且**不发任何通知**：`NSMenu.didAddItem`、
    /// `didBeginTracking`、窗口刷新都不响（实测时间线：顶栏被改回英文后一路停到 18 秒）。没有通知
    /// 可挂，就只能自己回头看；只在「刚才真的改过东西」之后回头看，于是它自带终止条件。
    private static let followUpDelays: [TimeInterval] = [0.4, 1.2, 3.0, 6.0]
    @MainActor private static var followUpIndex = 0

    /// 在 App 启动时调用一次：挂上「展开 / 收起 / 启动完成」三个时点的自愈。
    nonisolated static func start() {
        DispatchQueue.main.async { MainActor.assumeIsolated { install() } }
    }

    // MARK: - 菜单 dump（队列 L-145 的诊断口子）

    /// 环境变量 `DOYAH_MENU_DUMP=<文件路径>` ⇒ 启动后把整棵 `NSApp.mainMenu` 写出来并退出。
    ///
    /// 为什么需要它：菜单栏是**唯一**只有 AppKit 那棵树知道的东西 —— 界面快照拍不到（它不在任何
    /// 视图里）、源码判据读不到（`NSMenuItem.title` 是运行期值）、单测也只验表本身。
    /// 「中文菜单里还有英文项」这句话里，**哪两项**只有 dump 说得清。
    ///
    /// 三项判定逐项打出来（`认得出？· 认成了哪个键 · 目标语言应当是什么`），
    /// 于是三种可能的原因能一次分开：selector 不在表里 / 标题不在表里 / 键在但目标语言缺译。
    ///
    /// **只读**：不改任何 `NSMenuItem`，也不落盘用户偏好（跑完 `exit(0)`）。
    nonisolated static func dumpIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DOYAH_MENU_DUMP"], !path.isEmpty else { return }
        let delay = Double(environment["DOYAH_MENU_DUMP_DELAY"] ?? "") ?? 3.0
        // 可选：一串时刻（秒，逗号分隔）——每个时刻往 `startup.log` 记一行**顶栏现在是什么语言**。
        // 「改完又被改回去」这种 bug 只有时间线说得清（队列 `L-145`）。
        if let raw = environment["DOYAH_MENU_DUMP_TIMELINE"] {
            for field in raw.split(separator: ",") {
                guard let moment = Double(field.trimmingCharacters(in: .whitespaces)) else { continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + moment) {
                    MainActor.assumeIsolated {
                        guard let menu = NSApp.mainMenu else { return }
                        StartupLog.write("菜单栏时间线 t=\(field)s 顶栏=\(topLevelTitles(of: menu))")
                    }
                }
            }
        }
        // 可选：先按**真实路径**切一次语言（`LocalizationManager.setLanguage`，与用户点菜单同一个入口）
        // —— 复现「启动时是一种语言、用户切成另一种」这个场景，而不是只在启动参数上做文章。
        if let raw = environment["DOYAH_MENU_DUMP_SWITCH"], let target = AppLanguage(rawValue: raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 2) {
                MainActor.assumeIsolated { LocalizationManager.shared.setLanguage(target) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                // A = 原样（此刻 `NSApp.mainMenu` 长什么样）；B = 菜单被展开时那条自愈路
                // （`NSMenu.didBeginTrackingNotification` 的观察者做的正是 `refresh`）。
                // 两段分开写：A≠B 才说明「自愈只在展开时生效」，A=B 说明「walk 真的没走到它」。
                var report = menuReport(headline: "A 原样（未展开菜单）")
                refresh(to: LocalizationManager.shared.language)
                report += menuReport(headline: "B 展开菜单时那条自愈路之后")
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data(report.utf8))
                exit(0)
            }
        }
    }

    /// 走一遍菜单树，逐项写出「selector / 现标题 / 判定」。`@MainActor` 因为只有主线程能读菜单。
    @MainActor
    static func menuReport(headline: String) -> String {
        let language = LocalizationManager.shared.language
        let appName = appDisplayName
        var lines: [String] = [
            "# DOYAH-MENU-DUMP v1 — \(headline)",
            "# lang=\(language.rawValue)"
                + " appKitLaunchLocalizations=\(Bundle.main.preferredLocalizations.joined(separator: ","))"
                + " appleLanguages=\((UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.joined(separator: ",") ?? "?")"
        ]
        var unrecognized: [String] = []
        var mismatched: [String] = []
        guard let mainMenu = NSApp.mainMenu else {
            lines.append("# 菜单树为空（`NSApp.mainMenu` 为 nil）")
            return lines.joined(separator: "\n") + "\n"
        }

        func walk(_ menu: NSMenu, depth: Int) {
            for item in menu.items {
                let selector = item.action.map { NSStringFromSelector($0) }
                let title = item.title
                // 分隔符：没有标题也没有 action —— 不是文案，不进判定。
                if item.isSeparatorItem {
                    lines.append("\(depth)|separator|-|\(title)|-|-|-")
                    continue
                }
                let diagnosis = MenuLocalization.lookup(
                    title: title,
                    selector: selector,
                    appName: appName,
                    to: language
                )
                let kind: String
                let key: String
                let target: String
                switch diagnosis {
                case let .system(systemKey, expected):
                    kind = "system"
                    key = systemKey.rawValue
                    target = expected
                case let .title(titleKey, expected):
                    kind = "title"
                    key = titleKey.rawValue
                    target = expected
                case let .unrecognized(selector):
                    kind = "UNRECOGNIZED"
                    key = selector ?? "-"
                    target = "-"
                    unrecognized.append("\(title) [selector=\(selector ?? "-")]")
                }
                let matches: String
                if target == "-" {
                    matches = "unknown"
                } else {
                    matches = target == title ? "ok" : "MISMATCH"
                    if target != title {
                        mismatched.append("\(title) → \(target)（key=\(key)）")
                    }
                }
                // `key=` 那一格放：recognized 时是键名；unrecognized 时是 selector（认不出的证据）。
                let submenuTitle = item.submenu.map { " submenu=\($0.title)" } ?? ""
                lines.append("\(depth)|\(kind)|\(selector ?? "-")|\(title)|\(key)|\(target)|\(matches)\(submenuTitle)")
                if let submenu = item.submenu {
                    walk(submenu, depth: depth + 1)
                }
            }
        }
        walk(mainMenu, depth: 0)

        lines.append("# 认不出的项 \(unrecognized.count)：\(unrecognized.joined(separator: " ｜ "))")
        lines.append("# 与目标语言不一致的项 \(mismatched.count)：\(mismatched.joined(separator: " ｜ "))")
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func install() {
        guard !observing else { return }
        observing = true
        let names: [Notification.Name] = [
            NSMenu.didBeginTrackingNotification,
            NSMenu.didEndTrackingNotification,
            NSApplication.didFinishLaunchingNotification,
            // 命令图被重建时菜单项会被换掉（标题也跟着回到启动语言）——补一个**因果**时点，
            // 比只靠"切换后掐几个时间点补刷"可靠（那条仍然留着，见 `LocalizationManager.setLanguage`）。
            NSMenu.didAddItemNotification,
            // 语言切换后的头几秒：窗口每次刷新都对齐一次（见 `healUntil` 的说明）。
            NSWindow.didUpdateNotification,
            // 回到本应用时（菜单栏重新可见）再对齐一次 —— 那是它唯一被看见的时刻之一。
            NSApplication.didBecomeActiveNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // 窗口刷新很频繁：只在补刷窗口里动手，平时一次都不做。
                    if name == NSWindow.didUpdateNotification, Date() >= healUntil { return }
                    refresh(to: LocalizationManager.shared.language)
                }
            }
        }
        // 启动完成前 `NSApp.mainMenu` 可能还没建好，所以顺便立刻试一次。
        refresh(to: LocalizationManager.shared.language)
        // **启动也要开补刷窗口**（队列 `L-145` 的第 141 轮实测）：AppKit 会在应用启动后把
        // File / Edit / View / Window / Help 这五个**系统菜单**的顶层标题按**启动语言**再本地化
        // 一次（实测：我们把顶栏改成中文后，0.3 秒内它自己变回英文，而这一次**不会**发任何通知 ——
        // 只改一次的话，它就一直停在英文，直到用户点开某个菜单）。补刷窗口开在启动时刻，
        // 这几秒里的窗口刷新就会把那一笔盖回来。
        healUntil = Date().addingTimeInterval(healWindow)
        // 诊断口子：`DOYAH_MENU_DUMP=<文件>` 时把整棵菜单写出来就退出（默认什么都不做）。
        dumpIfRequested()
    }

    /// 按目标语言刷新菜单栏。
    ///
    /// 入口刻意保持 `nonisolated`：调用方 `LocalizationManager` 是个普通 `ObservableObject`，
    /// 不该为了改菜单栏被强制成主 actor；AppKit 那一段在 `MainActor` 上执行。
    nonisolated static func refresh(to language: AppLanguage) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { apply(language) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { apply(language) } }
        }
    }

    @MainActor
    private static func apply(_ language: AppLanguage) {
        guard let mainMenu = NSApp.mainMenu else { return }
        let changed = retitle(mainMenu, to: language)
        guard changed > 0 else {
            // 这一遍什么都不用改 ⇒ 说明上一次改名站住了，回头看到此为止。
            followUpIndex = 0
            return
        }
        // 留痕：**什么时候、改了几项**。菜单栏是唯一没有判据盯着的地方，
        // 「改完又被谁改回去」只有时间线说得清（队列 `L-145`）。
        StartupLog.write("菜单栏自愈：\(changed) 项 → \(language.rawValue)（顶栏=\(topLevelTitles(of: mainMenu))）")
        scheduleFollowUp(language)
    }

    /// 排一次「回头看」：按时刻表逐条来；用完配额还在被改回去 ⇒ 如实留一行（不假装修好）。
    @MainActor
    private static func scheduleFollowUp(_ language: AppLanguage) {
        guard followUpIndex < followUpDelays.count else {
            StartupLog.write("菜单栏自愈：回头看完 \(followUpDelays.count) 次仍被改回启动语言 —— 菜单栏那一层还有别的写入方")
            return
        }
        let delay = followUpDelays[followUpIndex]
        followUpIndex += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { apply(language) }
        }
    }

    /// 顶层菜单标题，用来看「栏上那一排」现在是什么语言。
    @MainActor
    static func topLevelTitles(of menu: NSMenu) -> String {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: " ")
    }

    /// 语言切换时调用：在接下来几秒里把「窗口刷新」当成补刷时机（见 `healUntil`）。
    ///
    /// 入口与 `refresh` 一样保持 `nonisolated`（调用方是普通 `ObservableObject`）。
    nonisolated static func beginHealing() {
        DispatchQueue.main.async { MainActor.assumeIsolated { healUntil = Date().addingTimeInterval(healWindow) } }
    }

    /// 应用显示名（系统菜单里"关于 / 隐藏 / 退出 / 帮助"都带它，不该写死在文案表里）。
    @MainActor
    private static var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? "DoyahStudio"
    }

    @MainActor
    private static func retitle(_ menu: NSMenu, to language: AppLanguage) -> Int {
        var changed = 0
        let appName = appDisplayName
        for item in menu.items {
            // 先按 **action selector** 认（系统菜单项走这条，与启动语言无关），
            // 认不出再按标题认（自有菜单项、以及没有 action 的顶层菜单标题）。
            let byAction = item.action.map {
                MenuLocalization.retitled(action: NSStringFromSelector($0), appName: appName, to: language)
            } ?? nil
            // 只在真的不一致时才写：避免对着已经正确的菜单反复置脏、白刷一次界面。
            if let retitled = byAction ?? MenuLocalization.retitled(item.title, to: language),
               retitled != item.title {
                item.title = retitled
                changed += 1
                // **菜单栏顶层项还要改 `NSMenu.title`**：AppKit 显示的是子菜单自己的 title，
                // 只写 `item.title` 在菜单栏上看不出来（2026-09-24 实测：File/Edit/View 不动，
                // 它们下面的子项却都变了）。子菜单标题不是用户可见文案时改它无副作用。
                if item.submenu?.title != retitled { item.submenu?.title = retitled }
            }
            if let submenu = item.submenu {
                changed += retitle(submenu, to: language)
            }
        }
        return changed
    }
}
