import Foundation
import XCTest

/// 「右键挂在**每一行**上，不是整棵树一份」（`FR-META-14` 的形态判据）。
///
/// 2026-09-29 需求提出者实测原话：「直接点右键几乎无法选择任意对象，要先鼠标左键点一个对象才有几率
/// 右键打开，很难选择到数据对象」。根因：整棵树渲染成**一个** `List` 行（为了行距可控），
/// 右键菜单也只挂一份、目标由「悬停记录」在**呈现那一刻**算 —— 而整树重算（一选中就重算）之后
/// SwiftUI 会补一个假的 `mouseExited` 把悬停记录清掉，于是必须先左键点一下（把行钉进兜底）才行。
///
/// ## 锚点归位（2026-09-30，修队列 `L-103` 的 10 条 HEAD 红灯）
///
/// 2026-09-29 23:25–23:36 的交互会话把**行渲染体搬进** `App/Views/ObjectTreeRowContent.swift`、
/// 把右键**交给 AppKit 捕获器自己给出**（`ObjectTreeRightClick.swift::menu(for:)` →
/// `ObjectTreeAppKitMenu.build`）⇒ SwiftUI 的 `.contextMenu` 与「整树兜底菜单」**都不在盘上了**，
/// 本篇原先钉的那些锚点跟着失效（判据红了 9 处，**而实现是对的**）。
///
/// 归位的口径：**判据钉的是「这一行自己的对象决定这一行的菜单」这件事**，不是某一种实现写法。
/// 传法从 `.contextMenu { items(object: row.object) }` 换成
/// `RowMouseCatcher(makeMenu: { ObjectTreeAppKitMenu.build(object: row.object, …) })`，
/// 判据就钉新入口的那三件事（每行一个捕获器 / 菜单由这一行现建 / 目标就是 `row.object`），
/// 并把「不许退回整树一份 + 悬停解析」立成反面判据。**语义一字未改，强度不减。**
final class ObjectTreeRowMenuConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 剥掉行注释：锚点要在**代码**里找 —— 免得判据被正文里成段的说明文字误伤，
    /// 也免得它随注释变长而失效（这条纪律见 `AGENT-SPEC.md` §9）。
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// `ForEach(visibleRows)` 里那一行的接线 —— **按括号配平取到闭合处**。
    ///
    /// 不许用 `prefix(N)` 这种「字数窗口」：实现的注释与空行一变长，锚点就滑出窗口 ⇒ 假红
    /// （`L-103` 那 10 条里就有一条是这么红的）。边界由**结构**给出，不由字数给出。
    private func rowWiring() throws -> String {
        let text = code(try source("App/Views/ObjectTreeView.swift"))
        guard let start = text.range(of: "ForEach(visibleRows) { row in") else { return "" }
        let rest = text[start.lowerBound...]
        var depth = 0
        var index = rest.startIndex
        while index < rest.endIndex {
            let character = rest[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(rest[..<rest.index(after: index)]) }
            }
            index = rest.index(after: index)
        }
        return String(rest)
    }

    func testEveryRowCarriesItsOwnContextMenu() throws {
        let body = try rowWiring()
        XCTAssertFalse(body.isEmpty,
                       "找不到 `ForEach(visibleRows)` —— 判据锚点变了，请更新这条判据而不是删掉它")

        XCTAssertTrue(body.contains("RowMouseCatcher("),
                      "每一行都要挂自己的鼠标捕获器（右键给本行菜单、左键给零等待选中）")
        guard let menu = body.range(of: "makeMenu: {") else {
            return XCTFail("行里找不到 `makeMenu:` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let closure = String(body[menu.lowerBound...].prefix(300))
        XCTAssertTrue(closure.contains("ObjectTreeAppKitMenu.build("),
                      "菜单必须由这一行现建（`ObjectTreeAppKitMenu.build`）—— 整树只剩一份 = 右键又要靠悬停记录（老毛病）")
        XCTAssertTrue(closure.contains("object: row.object"),
                      "行级菜单的目标必须是**这一行自己的对象**（`row.object`），不能是全局解析出来的目标")
        XCTAssertFalse(closure.contains("selectedTreeObject") || closure.contains("ObjectTreeMenuTarget.resolve("),
                       "目标不许经「已选中 / 悬停」这类全局解析 —— 那正是「点数据库却弹服务器菜单」的来源")

        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertFalse(view.contains("menuTargetObject"),
                       "整树兜底菜单（`object: menuTargetObject`）不许回来：它按悬停 / 上次选中算目标")
    }

    /// 点击区必须铺满整行 —— 只覆盖内容宽度时「标签右边那一截」点不到，表现就是「经常选不中」。
    ///
    /// 归位（2026-09-30）：命中判定的宿主从 SwiftUI 的 `.contentShape(Rectangle())` 换成了
    /// **AppKit 捕获器的 `hitTest`**（捕获器是 `overlay`，框跟着行框走）⇒ 「铺满宽度」这一条
    /// 现在落在行渲染体的 `frame(maxWidth: .infinity, alignment: .leading)` 上；两层都在才算数。
    func testRowHitAreaSpansFullWidth() throws {
        let content = try source("App/Views/ObjectTreeRowContent.swift")
        XCTAssertTrue(content.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
                      "行渲染体要先铺满宽度（`maxWidth: .infinity`）—— 否则标签右侧的空白点不到，"
                      + "捕获器那层 overlay 也只有内容那么宽")

        let body = try rowWiring()
        XCTAssertTrue(body.contains(".overlay(") && body.contains("RowMouseCatcher("),
                      "每一行上面要盖一层捕获器（`overlay`）—— 行的命中归属由它判，不再靠 SwiftUI 的 contentShape")
    }

    /// **右键归属交给 AppKit 自己判**（不碰任何坐标）：每一行自己接右键。
    ///
    /// 2026-09-29 两轮坐标换算都栽了：第一版把左下原点当左上 ⇒ 静静不生效；
    /// 第二版按屏幕坐标换算能命中，但**每行差一行**（需求提出者：「每次都选到下面的对象去了」）。
    /// 结论：行的归属是 AppKit `hitTest` / `menu(for:)` 的本职，不要自己算。
    func testRightClickIsOwnedByEachRowNotByCoordinates() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("RowMouseCatcher("),
                      "每一行都要挂自己的鼠标捕获器（右键给菜单、左键给零等待选中）")
        XCTAssertTrue(view.contains("ObjectTreeAppKitMenu.build("),
                      "捕获器要注入按本行对象现建的 AppKit 菜单（`ObjectTreeAppKitMenu.build`）")
        XCTAssertTrue(view.contains("appState.selectTreeObject(row.object)"),
                      "捕获到右键就把那一行设为选中")
        XCTAssertFalse(view.contains("RightClickRowSelector("),
                       "不许再退回「指针坐标 ↔ 行框」那套 —— 两轮都错在坐标系/差一行")

        let helper = try source("App/Views/ObjectTreeRightClick.swift")
        XCTAssertTrue(helper.contains("override func hitTest"), "用 hitTest 精确控制「只接右键」")
        // 归位（2026-09-30）：判据原先钉一行三元式，实现改成了 `switch`（多了左键那一支）⇒ 改钉
        // switch 的三个语义位：右键拿走、左键（行首箭头区外）拿走、其余一律放行。
        XCTAssertTrue(helper.contains("switch NSApp.currentEvent?.type"),
                      "只接右键：先看当前事件类型（命中归属由 AppKit 自己判）")
        XCTAssertTrue(helper.contains("case .rightMouseDown:"),
                      "右键要拦下来自己给菜单")
        XCTAssertTrue(helper.contains("case .leftMouseDown where !chevronZone.contains(point.x):"),
                      "左键也要拦（零等待），但行首箭头那一小块必须放行给 SwiftUI 按钮")
        XCTAssertTrue(helper.contains("return nil"),
                      "其余事件一律返回 nil 放行给 SwiftUI，否则行选择与展开箭头全被挡")
        XCTAssertTrue(helper.contains("override func menu(for event: NSEvent) -> NSMenu?"),
                      "命中视图必须**自己实现 menu(for:)** —— 否则 AppKit 会问到侧栏连接行那份「断开连接」")
        XCTAssertTrue(helper.contains("return makeMenu?()"),
                      "menu(for:) 必须返回本行的 NSMenu（不是 nil、也不是别人的）")
        XCTAssertTrue(helper.contains("DOYAH_TREE_RIGHTCLICK_DEBUG"), "无界面权限时的取证口子")
    }

    /// **行级跳过重算**（队列 `L-90` 未完成的那半，2026-09-29 需求提出者选定「B：彻底根治」）。
    ///
    /// 现场：**左键选中比右键还慢** —— 左键改选中态 ⇒ 整棵树重算，几十行全部重建 body。
    /// 修法：行渲染抽成独立 `Equatable` 视图 + `.equatable()`（相等就不重算 body），
    /// 并且 `==` 必须**排除闭包**（每次重建都是新闭包，比了就永远不相等 = 白优化）。
    ///
    /// 归位（2026-09-30）：行渲染体从 `ObjectTreeRows.swift` 搬进自己的文件
    /// `App/Views/ObjectTreeRowContent.swift`（同一件事的住处变了）⇒ 判据跟着搬，语义与强度不变，
    /// 并补一条「取证计数器要真被消费」。
    func testRowContentSkipsRebuildWhenUnchanged() throws {
        let rows = try source("App/Views/ObjectTreeRows.swift")
        XCTAssertTrue(rows.contains("struct ObjectTreeVisibleRow: Identifiable, Equatable"),
                      "行模型要 Equatable —— 否则行渲染体没法做相等比较")

        let content = try source("App/Views/ObjectTreeRowContent.swift")
        XCTAssertTrue(content.contains("struct ObjectTreeRowContent: View, Equatable"),
                      "行渲染体必须独立成 View 并 Equatable")
        XCTAssertTrue(content.contains("static func == (lhs: ObjectTreeRowContent, rhs: ObjectTreeRowContent) -> Bool"),
                      "相等比较要显式写出来（默认合成会把闭包也比进去）")
        XCTAssertTrue(content.contains("`onToggle` 刻意不参与比较"),
                      "闭包必须排除在相等比较之外，否则永远不相等、等于没优化")
        XCTAssertTrue(content.contains("bodyEvaluations"),
                      "要留取证计数器：右键日志会打出「距上次右键重算了几次 body」")
        XCTAssertTrue(try source("App/Views/ObjectTreeRightClick.swift").contains("ObjectTreeRowContent.bodyEvaluations"),
                      "计数器必须真被右键日志消费 —— 只声明不读 = 取证是假的")

        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("ObjectTreeRowContent(") && view.contains(".equatable()"),
                      "行必须走 `ObjectTreeRowContent(...).equatable()`")
        XCTAssertFalse(view.contains("private func color(for kind: DatabaseObject.Kind)"),
                       "按类型上色已搬进行渲染体（`ObjectTreeRowContent.color`）—— 视图里不要再留一份")
    }

    /// **展开只走双击与右箭头，绝不走单击**（2026-09-29 需求提出者原话）：
    /// 「单击选择某个对象时不要去查数据并自动展开下一级，只有用户双击或选择前面的右箭头才展开，
    /// 不然体验真的很差」。原先单击既选中又展开 ⇒ 每点一下都发一条元数据查询 + 整树重算。
    ///
    /// 归位（2026-09-30）：判据原先用 `prefix(300)` 当「单击那一支的正文」—— 那是**靠字数赌边界**，
    /// 实现里多打一行日志就跨进双击分支 ⇒ 假红（正是本轮 `L-103` 那 10 条里的一条）。
    /// 现在按 `} else if event.clickCount == 2 {` **切出真正的分支正文**，边界由结构给出、不由字数给出。
    func testSingleClickSelectsOnlyAndNeverExpands() throws {
        // 单击 / 双击都改由 AppKit 捕获器处理（零等待；SwiftUI 的单击会被双击判定窗口延后）。
        let helper = try source("App/Views/ObjectTreeRightClick.swift")
        guard let single = helper.range(of: "if event.clickCount == 1 {") else {
            return XCTFail("找不到 clickCount == 1 分支 —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let rest = String(helper[single.lowerBound...])
        guard let double = rest.range(of: "} else if event.clickCount == 2 {") else {
            return XCTFail("找不到 clickCount == 2 分支 —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let singleBody = String(rest[rest.startIndex..<double.lowerBound])
        XCTAssertTrue(singleBody.contains("onSelect?()"), "单击必须选中")
        XCTAssertFalse(singleBody.contains("onDoubleClick?()"),
                       "单击**不许**展开（会连带发元数据查询 + 整树重算）")

        let doubleBody = String(rest[double.lowerBound...].prefix(400))
        XCTAssertTrue(doubleBody.contains("onDoubleClick?()"), "双击必须触发展开")

        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("if row.isExpandable {"),
                      "双击回调里对可展开节点必须展开")
        XCTAssertTrue(view.contains("chevronZone(for: row)"),
                      "行首箭头那一小块必须放行给 SwiftUI（否则箭头被拦掉）")
    }

    /// **左键也要零等待**（2026-09-29 需求提出者第三次说手感：「同样选某个对象，右键总比左键快」）。
    /// 根因：SwiftUI 同一行同时挂单击与双击手势时，单击必须等双击判定窗口（~250–300ms）过期。
    /// 修法：左键也交给 AppKit 捕获器（`clickCount` 原生、零等待），只把行首箭头留给 SwiftUI。
    func testLeftClickIsHandledByAppKitWithoutDoubleTapDelay() throws {
        let helper = try source("App/Views/ObjectTreeRightClick.swift")
        XCTAssertTrue(helper.contains("override func mouseDown(with event: NSEvent)"),
                      "左键必须在 AppKit 侧处理（SwiftUI 的单击会被双击判定窗口延后）")
        XCTAssertTrue(helper.contains("case .leftMouseDown where !chevronZone.contains(point.x)"),
                      "左键要拦，但行首箭头那一小块必须放行给 SwiftUI 按钮")

        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertFalse(view.contains(".onTapGesture"),
                       "视图里不许再有 SwiftUI 点击手势 —— 它们才是那个 250ms 延迟的来源")
    }
}
