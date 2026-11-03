import XCTest

/// `check-menu-language`（`verify-all` 第 11 项）**探针自身**的接线判据。
///
/// 为什么要有这一条：这条门禁的红有**两种**，一种是产品真的停在启动语言，另一种是**探针根本没跑成**。
/// 2026-11-03 实测到的就是后一种，而且它长得像前者 —— 主线程卡在
/// `-[NSMenu popUpMenuPositioningItem:atLocation:inView:appearance:]` 里 40 分钟没回来
/// （`sample` 的调用栈），于是两档都「等了 120 秒没等到 dump」，台账上只能记「未执行」。
/// 根因：收起器排的是 `DispatchQueue.main.asyncAfter`，而菜单跟踪期间 run loop 走的是
/// `NSEventTracking` 模式，主队列那一路**不保证**被抽 ⇒ `cancelTracking()` 一次没触发。
/// 改成挂在 `RunLoop.main` 的 `.common` 模式（含 `NSEventTracking`）后同一份包秒出 dump。
///
/// 这条判据钉住两件事，防它悄悄退回旧写法（退回去**不会**让任何测试变红，只会让第 11 项
/// 又变成「未执行」—— 而「未执行」在台账上跟通过长得一样近，这就是必须有机器判据的理由）：
///   ① 收起器只许挂 `RunLoop.main.add(_, forMode: .common)`，`openEveryTopLevelMenu` 体内
///      **零** `DispatchQueue.main.asyncAfter`；
///   ② 每次 `popUp` 前后都要往 stderr 写一行点名菜单（哪一天又挂住，日志能直接说是哪个菜单，
///      不必再 `sample` 进程）。
///
/// **覆盖边界（铁律 13）**：判的是**源码写法**，不是运行期真收敛 —— 真收敛由门禁本体的
/// 两档真启动读数负责（那是外部权威系统：真 AppKit、真窗口服务器）。
/// **负例（铁律 14）**：`testCheckerFlagsDispatchCancellerInFixture` 喂两段夹具，
/// 旧写法必须判红、新写法必须判绿。
final class MainMenuProbeWiringTests: XCTestCase {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var localizerSource: URL {
        repositoryRoot.appendingPathComponent("App/MainMenuLocalizer.swift")
    }

    // MARK: - 判据本体（纯函数，好让负例喂夹具）

    /// 取一个 `static func <name>` 的函数体（大括号配平；找不到返回 nil）。
    static func body(ofFunction name: String, in source: String) -> String? {
        guard let head = source.range(of: "static func \(name)") else { return nil }
        guard let open = source.range(of: "{", range: head.upperBound..<source.endIndex) else { return nil }
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open.upperBound..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// 剥注释（行注释 + 块注释，`/* */` 可嵌套）—— 注释里写「以前用的是 DispatchQueue」是记录，不是违规。
    static func strippingComments(_ text: String) -> String {
        var out = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if depth == 0, rest.hasPrefix("//") {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            }
            if rest.hasPrefix("/*") {
                depth += 1
                index = text.index(index, offsetBy: 2)
                continue
            }
            if depth > 0 {
                if rest.hasPrefix("*/") {
                    depth -= 1
                    index = text.index(index, offsetBy: 2)
                } else {
                    if text[index] == "\n" { out.append("\n") }
                    index = text.index(after: index)
                }
                continue
            }
            out.append(text[index])
            index = text.index(after: index)
        }
        return out
    }

    /// 返回 `openEveryTopLevelMenu` 函数体里的违规清单（空 = 合规）。
    static func violations(inBody body: String) -> [String] {
        let code = strippingComments(body)
        var found: [String] = []
        if code.contains("DispatchQueue.main.asyncAfter") {
            found.append("收起器又用回了 DispatchQueue.main.asyncAfter（菜单跟踪期间不保证被抽 ⇒ popUp 会挂住）")
        }
        if !code.contains("forMode: .common") {
            found.append("收起器没挂 .common 模式（NSEventTracking 模式下定时器不会到点）")
        }
        if !code.contains("menu-expand:") {
            found.append("popUp 前后没往 stderr 点名菜单（挂住时无法从日志判断是哪个菜单）")
        }
        return found
    }

    // MARK: - 判据 ① / ②：真源码

    func testRealSourceKeepsCancellersInCommonMode() throws {
        let source = try String(contentsOf: Self.localizerSource, encoding: .utf8)
        let body = try XCTUnwrap(
            Self.body(ofFunction: "openEveryTopLevelMenu", in: source),
            "App/MainMenuLocalizer.swift 里找不到 openEveryTopLevelMenu —— 函数改名了？本判据要同批跟改"
        )
        XCTAssertGreaterThan(body.count, 400, "函数体只有 \(body.count) 字 —— 取体失败，判据会变成空跑")
        XCTAssertEqual(Self.violations(inBody: body), [], "探针接线违规：\(Self.violations(inBody: body))")
    }

    // MARK: - 负例（铁律 14）

    func testCheckerFlagsDispatchCancellerInFixture() {
        // 旧写法（2026-11-03 之前那一版）：收起器走主队列，且没有 stderr 点名
        let old = """
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            for delay in [0.6, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { submenu.cancelTracking() }
            }
            _ = submenu.popUp(positioning: nil, at: NSPoint(x: 30, y: 30), in: nil)
        }
        """
        let oldViolations = Self.violations(inBody: old)
        XCTAssertTrue(
            oldViolations.contains { $0.contains("DispatchQueue.main.asyncAfter") },
            "负例失败：旧写法必须判红（实测它会让 popUp 挂 40 分钟）"
        )
        XCTAssertTrue(oldViolations.contains { $0.contains("stderr") }, "负例失败：缺 stderr 点名必须判红")

        // 新写法（现在是产品里那一版）：.common 定时器 + 前后点名
        let current = """
        var cancellers: [Timer] = []
        for delay in [0.6, 1.6] {
            let timer = Timer(timeInterval: delay, repeats: false) { _ in submenu.cancelTracking() }
            RunLoop.main.add(timer, forMode: .common)
            cancellers.append(timer)
        }
        FileHandle.standardError.write(Data("menu-expand: pass=\\(passes) popUp `\\(item.title)`\\n".utf8))
        _ = submenu.popUp(positioning: nil, at: NSPoint(x: 30, y: 30), in: nil)
        """
        XCTAssertEqual(Self.violations(inBody: current), [], "正例被判红：合规写法必须判绿")

        // 注释里提到旧写法不算违规（否则本判据会把自己的说明文档判红）
        let commented = "// 以前用 DispatchQueue.main.asyncAfter，会挂住\n" + current
        XCTAssertEqual(Self.violations(inBody: commented), [], "注释里的历史记录被判红：剥注释坏了")
    }
}
