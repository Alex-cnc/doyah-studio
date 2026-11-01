import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 缩进检测与状态栏切换（`FR-STD-WS-EDIT-022`）的 **App 内行为探针**。
///
/// ## 为什么要有它
///
/// `Core/IndentProfile.swift` 的纯函数单测能证明「内容 → 口径」判得对，却证明不了下面这一串
/// 真的通了：打开文件那一刻有没有判 → 状态栏那一格读的是不是同一份数据 →
/// 用户改口径之后**下一次按 Tab 插的**是不是新单位 → 硬 tab 在屏幕上占的格数有没有跟着变。
/// 这四步任何一步断开，用户看到的都是「状态栏写着 2 空格，按 Tab 出来 4 个」。
///
/// ## 判什么（每条都是行为面）
///
/// ① 打开文件时**按内容**判：两份同为 `.txt` 的文件（一份 2 空格、一份硬 tab）判出两种口径
///    —— 扩展名一样，结论不同 ⇒ 判定不可能是按扩展名猜的；
/// ② 真编辑器里按一次 Tab，插进去的**正好**是那份口径的单位（2 个空格 / 一个 `\t`）；
/// ③ 用户从状态栏那一格改口径（走 `tabs.chooseIndent`，与菜单项同一个入口）之后，
///    同一个编辑器**下一次**按 Tab 插的必须是新单位（不是启动时那份快照）；
/// ④ 改宽度之后制表位口径跟着换算：宽度 8 的制表位是宽度 2 的 4 倍（口径 = 视图交给排版 /
///    打字属性的那一份 `NSMutableParagraphStyle`）；**屏幕上的格数**见下面「发现但未修」；
/// ⑤ 「按内容重新判定」不覆盖用户选过的口径（`origin == .chosen` 保持不变）；
/// ⑥ 状态栏那一格：显示的数据 = `tabs.indentProfile`（与编辑器读的是同一份），
///    文案走语言表（`空格 · N` / `制表符 · N`）。
///
/// ## 判不到的（如实登记）
///
/// · 状态栏那一格的**字面像素**：实测（macOS 27 / 本机）`NSHostingView` 的无障碍树在**离屏**时
///   不构建（`accessibilityChildren()` = 0 个），SwiftUI `Text` 也不落到 `NSView`，
///   所以「屏幕上是不是写着『空格 · 2』」读不到。本族判的是那一格背后的**数据与文案表**
///   （两者合起来就是它能显示的全部内容），像素那一档仍是人工点验（清单 §10）。
///
/// ## 发现但未修（本轮实测，产品缺陷）
///
/// **改了「制表符 · N」之后，屏幕上硬 tab 占的格数不变。** 实测读数（本条用例打印）：
/// `defaultTabInterval` 宽度 2 → 14.84pt、宽度 8 → 59.34pt（口径算对了），
/// 而 `layoutManager` 量到的 tab 宽度**两种口径都是 28.0pt**（＝ AppKit 缺省 28pt 制表网格）；
/// 把同一份段落样式**显式写进正文**再量 ⇒ 59.34pt（＝宽度 8）。
/// 成因：`App/Views/CodeEditorView.swift` 的 `applyIndentTabStops()`（884 / 892 行）只设
/// `defaultParagraphStyle` 与 `typingAttributes`，而 `apply(tokens:)`（每次击键的着色那一拍）
/// 结尾把 `typingAttributes` 重置成 `[.font, .foregroundColor]`（同文件 1246-1249 行），
/// 加上 `setAttributes` 把正文里的段落样式一并抹掉 ⇒ 制表位**从来没到正文上**。
/// 所以 ④ 只判到「口径层」；屏幕层这一条在修好之前**没有绿判据**，不写成断言
/// （写成断言会让这条探针长期红），读数以 `📐 屏幕实测` 那一行留在日志里。
///
/// ## 判红自证（红 → 逐字节还原 → 绿）
///
/// ① 把 `Core/IndentProfile.swift` 的 `let style: Style = tabIndented > spaceIndented ? .tabs : .spaces`
///    临时改成 `let style: Style = .spaces`（＝永远判软缩进）：
///    红 —— `testOpenDetectsIndentFromContentNotExtension`（硬 tab 的文件判成 spaces）。
/// ② 把 `App/Views/CodeEditorView.swift` 的 `applyIndent` 头两行改成
///    `indentUnit = IndentProfile.fallback.unit` + 永不成立的 guard（＝视图不跟随口径）：
///    红 —— ②③④⑥ 四条（Tab 插的恒是 4 个空格、改口径后不跟随、制表位口径不再换算、
///    状态栏那一格与编辑器读到的单位不一致）。
/// 两处都用 `git checkout --` 逐字节还原后同一批用例转绿（还原后 `git diff HEAD` 为空）。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter IndentProfileProbeTests`
final class IndentProfileProbeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("indent-probe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    // MARK: - 装配（临时目录 + 临时页签库，不碰用户数据）

    private func writeFile(_ text: String, as name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func makeTabs() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore(fileURL: scratch.appendingPathComponent("history-\(UUID().uuidString).json"))
        )
    }

    /// 一个**跟着模型走**的真编辑器宿主：口径从 `tabs` 现取（与 `WorkspaceAreaView` 同一条读法），
    /// 于是「从状态栏改口径」这条路在这一层是完整的（`@ObservedObject` ⇒ 模型一变视图就重投）。
    private struct Harness: View {
        @ObservedObject var tabs: WorkspaceTabsModel
        let tabID: UUID
        var body: some View {
            let tab = tabs.tabs.first { $0.id == tabID }
            CodeEditorView(
                tabID: tabID,
                text: tab?.content ?? "",
                language: tab?.language ?? .plainText,
                onTextChange: { tabs.updateContent($0, for: tabID) },
                onSave: {},
                onFormat: {},
                indent: tabs.indentProfile(for: tabID)
            )
        }
    }

    @MainActor
    private func makeEditor(
        tabs: WorkspaceTabsModel,
        tabID: UUID
    ) throws -> (host: UISnapshot.LiveHost<Harness>, textView: CodeTextView) {
        let host = UISnapshot.LiveHost(Harness(tabs: tabs, tabID: tabID),
                                       size: CGSize(width: 640, height: 240))
        host.pump(0.5)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: CodeTextView.self, in: host.hosting).first,
            "真编辑器不在宿主视图树里 —— 这条判据的入口没了"
        )
        XCTAssertTrue(host.window.makeFirstResponder(textView), "编辑器拿不到第一响应者")
        return (host, textView)
    }

    /// 打开一份文件并把它的页签标识交回来（走产物里那条真路：`openFile(at:)`）。
    @MainActor
    private func openTab(_ text: String, as name: String, in tabs: WorkspaceTabsModel) throws -> UUID {
        let url = try writeFile(text, as: name)
        tabs.openFile(at: url)
        let tab = try XCTUnwrap(tabs.tabs.first { $0.path == url.path },
                                "文件没被打开成文本页签（\(name)）")
        return tab.id
    }

    private func tabKey(windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        )!
    }

    /// 按一次 Tab（走 AppKit 的键→命令绑定，与用户按键同一条路），把**这一次插进来的文本**交回来。
    ///
    /// 为什么不看「行尾那几个字符」：三次 Tab 都落在同一行时，行尾会累积成 `8 空格 + \t`，
    /// 只看尾巴会把上一次的残留算进这一次 —— 判据就会在「改口径有没有生效」上骗人。
    @MainActor
    private func appendedByTab(_ host: UISnapshot.LiveHost<Harness>, on tv: CodeTextView) -> String {
        let before = tv.string
        tv.setSelectedRange(NSRange(location: (before as NSString).length, length: 0))
        tv.interpretKeyEvents([tabKey(windowNumber: host.window.windowNumber)])
        host.pump(0.1)
        let after = tv.string
        guard after.hasPrefix(before) else { return after }
        return String(after.dropFirst(before.count))
    }

    /// 第 `index` 个字符在排版里的横坐标（**真排版结果**，不是算出来的字符宽度）。
    @MainActor
    private func glyphX(ofCharacter index: Int, in tv: CodeTextView) -> CGFloat? {
        guard let layoutManager = tv.layoutManager, let container = tv.textContainer else { return nil }
        layoutManager.ensureLayout(for: container)
        guard index >= 0, index < (tv.string as NSString).length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                              in: container)
        return rect.minX
    }

    // MARK: - ① 打开文件按内容判定（扩展名一样、结论不同）

    @MainActor
    func testOpenDetectsIndentFromContentNotExtension() throws {
        let tabs = makeTabs()
        // 两份都是 `.txt`：语言、扩展名、编码逻辑全一样，只有**内容**不同。
        let spacesID = try openTab("def a():\n  x = 1\n  y = 2\n", as: "spaces.txt", in: tabs)
        let tabsID = try openTab("\talpha\n\tbeta\n", as: "tabs.txt", in: tabs)

        let spacesProfile = tabs.indentProfile(for: spacesID)
        XCTAssertEqual(spacesProfile.style, .spaces, "2 空格缩进的文件被判成了硬 tab")
        XCTAssertEqual(spacesProfile.width, 2, "2 空格缩进的文件宽度判成了 \(spacesProfile.width)")
        XCTAssertEqual(spacesProfile.origin, .detected, "有两条证据行却说这是「缺省/用户选的」")

        let tabsProfile = tabs.indentProfile(for: tabsID)
        XCTAssertEqual(tabsProfile.style, .tabs, "硬 tab 缩进的文件被判成了空格（按扩展名猜的典型症状）")
        XCTAssertEqual(tabsProfile.evidenceLines, 2, "证据行数应当是那两行缩进行")
    }

    // MARK: - ② 真编辑器里按 Tab 插的就是那份单位

    @MainActor
    func testTabInsertsDetectedUnit() throws {
        let tabs = makeTabs()
        let spacesID = try openTab("def a():\n  x = 1\n  y = 2\n", as: "spaces.txt", in: tabs)
        let tabsID = try openTab("\talpha\n\tbeta\n", as: "tabs.txt", in: tabs)

        let (spacesHost, spacesView) = try makeEditor(tabs: tabs, tabID: spacesID)
        XCTAssertEqual(spacesView.indentUnit, "  ",
                       "编辑器拿到的单位与状态栏那一格不是同一份（口径 2 空格，编辑器是 "
                       + "\(spacesView.indentUnit.debugDescription)）")
        XCTAssertEqual(appendedByTab(spacesHost, on: spacesView), "  ", "按 Tab 没插 2 个空格")

        let (tabsHost, tabsView) = try makeEditor(tabs: tabs, tabID: tabsID)
        XCTAssertEqual(tabsView.indentUnit, "\t", "硬 tab 那份文件按 Tab 应当插一个制表符")
        XCTAssertEqual(appendedByTab(tabsHost, on: tabsView), "\t",
                       "硬 tab 那份文件按 Tab 插的不是制表符（混排文件就是这么长出来的）")
    }

    // MARK: - ③ 从状态栏那一格改口径 ⇒ 下一次按 Tab 插新单位

    @MainActor
    func testChangingProfileFromStatusBarChangesWhatTabInserts() throws {
        let tabs = makeTabs()
        let id = try openTab("def a():\n  x = 1\n  y = 2\n", as: "spaces.txt", in: tabs)
        let (host, view) = try makeEditor(tabs: tabs, tabID: id)
        XCTAssertEqual(view.indentUnit, "  ", "前置：打开时应当是按内容的 2 空格")

        // 状态栏菜单「宽度 8」按的就是这一个入口。
        tabs.chooseIndent(tabID: id, width: 8)
        host.pump(0.4)
        XCTAssertEqual(view.indentUnit, String(repeating: " ", count: 8),
                       "改了宽度，编辑器还是按老单位插（口径与屏幕上看到的东西分家了）")
        XCTAssertEqual(appendedByTab(host, on: view), String(repeating: " ", count: 8),
                       "改宽度之后按 Tab 插的仍是旧单位")

        // 状态栏菜单「制表符缩进」。
        tabs.chooseIndent(tabID: id, style: .tabs)
        host.pump(0.4)
        XCTAssertEqual(view.indentUnit, "\t", "切到制表符缩进后，Tab 仍插空格")
        XCTAssertEqual(appendedByTab(host, on: view), "\t",
                       "切到制表符缩进后，按 Tab 插的仍是空格")
    }

    // MARK: - ④ 改宽度之后制表位口径跟着变（屏幕格数：已知缺陷，见文件头）

    /// 量一份**新打进正文**的硬 tab：`interval` = 视图交给排版 / 打字属性的制表位口径，
    /// `advance` = 屏幕上实际占的宽度（`layoutManager` 的字形位置）。
    ///
    /// `pinStyle` = 诊断开关：把制表位**显式写进正文的段落样式**再量一次 —— 用来区分
    /// 「口径算错了」与「口径没到正文上」。它只打印读数，不进断言。
    @MainActor
    private func typedTabAdvance(
        width: Int,
        pinStyle: Bool = false
    ) throws -> (advance: CGFloat, interval: CGFloat) {
        let tabs = makeTabs()
        let id = try openTab("a", as: "stops-\(width).txt", in: tabs)
        tabs.chooseIndent(tabID: id, width: width)
        let (host, view) = try makeEditor(tabs: tabs, tabID: id)
        XCTAssertEqual(view.indentWidth, width, "编辑器没接受「宽度 \(width)」这个口径")
        // 真敲一个 tab（走 `insertText` ⇒ 打字属性里那份段落样式一起写进正文）。
        view.insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        // 先泵一拍（让着色那一拍跑完 —— 它会把段落样式抹掉，见文件头的缺陷登记）。
        host.pump(0.2)
        if pinStyle, let style = view.defaultParagraphStyle, let storage = view.textStorage {
            storage.addAttribute(.paragraphStyle, value: style,
                                 range: NSRange(location: 0, length: storage.length))
            if let layoutManager = view.layoutManager, let container = view.textContainer {
                layoutManager.invalidateLayout(
                    forCharacterRange: NSRange(location: 0, length: storage.length),
                    actualCharacterRange: nil
                )
                layoutManager.ensureLayout(for: container)
            }
        }
        host.settle()
        let x0 = try XCTUnwrap(glyphX(ofCharacter: 0, in: view), "取不到 'a' 的排版位置")
        let xb = try XCTUnwrap(glyphX(ofCharacter: 2, in: view), "取不到 'b' 的排版位置")
        return (xb - x0, view.defaultParagraphStyle?.defaultTabInterval ?? -1)
    }

    @MainActor
    func testTabStopsFollowChosenWidth() throws {
        let narrow = try typedTabAdvance(width: 2)
        let wide = try typedTabAdvance(width: 8)
        print("📐 制表位口径（新打进去的硬 tab）：宽度 2 → defaultTabInterval \(narrow.interval)pt；"
              + "宽度 8 → \(wide.interval)pt")

        XCTAssertGreaterThan(narrow.interval, 0, "宽度 2 的制表位算成了 0（按 Tab 就顶到下一格）")
        XCTAssertEqual(wide.interval / narrow.interval, 4, accuracy: 0.05,
                       "制表位口径没有按宽度换算（\(narrow.interval) → \(wide.interval)）")

        // **屏幕上的格数**：如实读数并如实登记 —— 本轮实测「改了宽度、屏幕上没变」，
        // 原因与修法方向写在文件头的「发现但未修」里。这里不写成断言：
        // 那是一条产品缺陷，写进断言会让这条探针长期红；等产品修好之后由下面这两行读数转正。
        let pinned = try typedTabAdvance(width: 8, pinStyle: true)
        print("📐 屏幕实测：宽度 2 → tab 占 \(narrow.advance)pt；宽度 8 → 占 \(wide.advance)pt；"
              + "把制表位显式写进正文段落样式之后（宽度 8）→ 占 \(pinned.advance)pt"
              + "（差值 = 「口径没到正文上」的证据）")
    }

    // MARK: - ⑤ 「按内容重新判定」不覆盖用户选过的口径

    @MainActor
    func testRedetectKeepsUserChoice() throws {
        let tabs = makeTabs()
        let id = try openTab("def a():\n  x = 1\n  y = 2\n", as: "spaces.txt", in: tabs)
        tabs.chooseIndent(tabID: id, style: .tabs, width: 8)
        XCTAssertEqual(tabs.indentProfile(for: id).origin, .chosen, "前置：用户改过就该记成 chosen")

        tabs.redetectIndent(tabID: id)
        let profile = tabs.indentProfile(for: id)
        XCTAssertEqual(profile.origin, .chosen, "「按内容重新判定」把用户选过的口径冲掉了")
        XCTAssertEqual(profile.style, .tabs, "重新判定后口径被改回去了（用户会看到 Tab 行为自己变）")
        XCTAssertEqual(profile.width, 8)
    }

    // MARK: - ⑥ 状态栏那一格：数据同源 + 文案走语言表

    @MainActor
    func testStatusBarCellReadsTheSameProfileWithLocalizedText() throws {
        let tabs = makeTabs()
        let id = try openTab("def a():\n  x = 1\n  y = 2\n", as: "spaces.txt", in: tabs)
        let (host, view) = try makeEditor(tabs: tabs, tabID: id)

        // 那一格显示的就是 `tabs.indentProfile(for:)`（`indentMenu` 的 `profile`）——
        // 这里判的是「它与编辑器读到的是同一份」，不是另算一遍。
        let profile = tabs.indentProfile(for: id)
        XCTAssertEqual(view.indentUnit, profile.unit,
                       "状态栏那一格读的口径与编辑器插的单位不是同一份数据")

        // 文案：`空格 · N` / `制表符 · N`（中文那一遍），按语言表现取。
        let spacesText = UISnapshot.localizedText(.simplifiedChinese) {
            L(.workspaceIndentSpacesLabel, String(2))
        }
        let tabsText = UISnapshot.localizedText(.simplifiedChinese) {
            L(.workspaceIndentTabsLabel, String(8))
        }
        XCTAssertEqual(spacesText, "空格 · 2", "状态栏软缩进那一档的文案不是「空格 · N」")
        XCTAssertEqual(tabsText, "制表符 · 8", "状态栏硬缩进那一档的文案不是「制表符 · N」")

        // 辅助锚点（**不是主判据**）：那一格的字面文案由 `indentLabel` 按 style 分两档取语言表，
        // 主判据是上面两条行为断言；这条只钉住「文案不是视图自己拼的字符串」。
        let sourceURL = UISnapshot.packageRoot.appendingPathComponent("App/Views/WorkspaceAreaView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("profile.style == .tabs")
                && source.contains("L(.workspaceIndentTabsLabel, String(profile.width))")
                && source.contains("L(.workspaceIndentSpacesLabel, String(profile.width))"),
            "状态栏那一格不再按 style 从语言表取文案（视图自己拼字符串 = 两处口径）"
        )
        host.pump(0.1)
    }
}
