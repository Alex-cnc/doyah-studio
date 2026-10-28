import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **三处编辑面的底色是不是同一档** —— `FR-STD-WS-UI-011` 的 ① / ②。
///
/// 需求原文：① 三处编辑面同一主题下底色一致（色值相同）；② 切浅色 / 深色与切主题时三处同步成套，
/// 无一处保留旧色；③ 源码里编辑面不出现系统默认底色与硬编码色值。
///
/// ## ③ 早有人判，① / ② 从没量过（本片补的就是这两条）
/// ③ 由 `Scripts/check-editor-surface-tokens.py` 判（源码级：每处编辑面都挂 `.editorSurface()`、
/// 唯一出处走令牌、AppKit 三面仍写 `Surface.content` + `TextTone.primary`；25 例自证能判红）。
/// 它**判不到** ① / ②：令牌是**动态色**（`NSColor(name:dynamicProvider:)`），深浅两套值只在
/// **绘制那一刻**按窗口外观求值 —— 源码里三行一模一样的令牌，画出来仍可能三样。
///
/// ## 量法（与 R47 页签条同一个套路：离屏窗口 + 真布局）
/// 每个编辑面按**产品里那一处用的同一个视图类型**建一间不上屏的 `NSWindow`（`NSHostingView`），
/// 给确定大小与外观 ⇒ `layoutIfNeeded` + 跑一小段 runloop（SwiftUI 布局下一跳才落，不跑拿到的是
/// 0×0 退化帧）⇒ 在 AppKit 树里找到那块 `NSTextView` ⇒ **按它的 frame 算取样矩形**
/// （不写死坐标：版式一改，写死的坐标会量到别处去还照样绿）⇒ `cacheDisplay` 落 PNG ⇒
/// 取矩形内**众数色**与主题令牌值逐通道比（容差 8，PNG 往返实测偏移 ≤4）。
///
/// ## 判据（七例，每例都能判红）
/// ① 深色三面各等于该主题 `content` 令牌，且三面互为同一个色值；
/// ② 浅色同口径；
/// ③ 五个主题逐个：三面都等于**该主题**的令牌、且互相同值；
/// ④ 切深浅：每一面都要变（差 > 8）——「无一处保留旧色」；
/// ⑤ 切主题（科技蓝 ↔ 玫瑰金）：每一面都要变；
/// ⑥ **对照件**：一块没走令牌的裸 `NSTextView`（系统底色）必须**判得出不一样**
///   （否则前五条是「量法分辨不了两种底色」的假绿）；
/// ⑦ **空跑防护**：取样框必须落在 `NSTextView` 框内、那块视图高度够、PNG 字节数有下限。
final class EditorSurfaceTokenParityProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 三处编辑面

    enum EditSurface: String {
        case workspace
        case sql
        case notes
        case bareControl   // 对照件：没走令牌的裸 `NSTextView`（刻意不在 `panels` 里）

        /// 参与「三处同底」的三面。
        static let panels: [EditSurface] = [.workspace, .sql, .notes]

        var label: String {
            switch self {
            case .workspace: return "工作区代码编辑器（CodeEditorView）"
            case .sql: return "数据库 SQL 编辑器（SQLEditorView）"
            case .notes: return "笔记正文（NotesRichTextEditor）"
            case .bareControl: return "对照件 · 裸 NSTextView（系统底色）"
            }
        }

        var fileTag: String { self == .bareControl ? "control" : rawValue }

        @MainActor
        @ViewBuilder
        func drawing() -> some View {
            switch self {
            case .workspace:
                CodeEditorView(
                    tabID: UUID(),
                    text: "",
                    language: .sql,
                    onTextChange: { _ in },
                    onSave: {},
                    onFormat: {}
                )
            case .sql:
                SQLEditorView(text: "", databaseType: .postgresql, diagnostics: [], tabID: UUID())
            case .notes:
                NotesSurface()
            case .bareControl:
                BareTextView()
            }
        }
    }

    /// 笔记正文富文本面：三件绑定都就地造（不碰真实笔记库）。
    private struct NotesSurface: View {
        @State private var text = ""
        @State private var spans: [NoteSpan] = []
        @StateObject private var controller = NotesRichTextController()

        var body: some View {
            NotesRichTextEditor(text: $text, spans: $spans, controller: controller)
        }
    }

    /// 对照件：一块**没走令牌**的裸 `NSTextView` —— 它画的是系统 `textBackgroundColor`
    /// （内测清单甲2 的原病）。同一套量法必须判得出它与令牌色不一样，否则前面几条是假绿。
    private struct BareTextView: NSViewRepresentable {
        func makeNSView(context: Context) -> NSScrollView { NSTextView.scrollableTextView() }
        func updateNSView(_ view: NSScrollView, context: Context) {}
    }

    // MARK: - 量法

    struct Reading {
        var surface: EditSurface
        var rgb: (red: Int, green: Int, blue: Int)
        var expected: (red: Int, green: Int, blue: Int)
        var sample: (leading: Int, top: Int, width: Int, height: Int)
        var textView: NSRect
        var pngBytes: Int

        var delta: Int {
            max(
                abs(rgb.red - expected.red),
                max(abs(rgb.green - expected.green), abs(rgb.blue - expected.blue))
            )
        }

        var line: String {
            "\(surface.label)：实测 \(rgb) ／ 令牌 \(expected)（差 \(delta)）"
                + "· 取样 \(sample) · 文本视图 \(textView)"
        }
    }

    private static let size = CGSize(width: 720, height: 420)
    private static let scale: CGFloat = 2
    private static let stateDirectory = UISnapshot.outputDirectory
        .deletingLastPathComponent()
        .appendingPathComponent("ui-snapshot-state", isDirectory: true)

    /// 离屏窗口的持有者：只持有、不关闭（关掉会带着渲染过程中的宿主一起走，实测 R47 同款）。
    @MainActor private static var retainedWindows: [NSWindow] = []

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    /// 渲染一面、取一次底色读数（主题与外观都按参数摆好；`defer` 还原宿主主题，不落盘）。
    @MainActor
    private func measure(
        _ surface: EditSurface, theme: DesignTheme, scheme: NSAppearance.Name
    ) throws -> Reading {
        let previous = DesignThemeManager.shared.beginHostTheme(theme)
        defer {
            if let previous { DesignThemeManager.shared.beginHostTheme(previous) }
            else { DesignThemeManager.shared.endHostTheme() }
        }

        let size = Self.size
        let appearance = NSAppearance(named: scheme)
        let hosting = NSHostingView(
            rootView: AnyView(surface.drawing().frame(width: size.width, height: size.height))
        )
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        // SwiftUI 布局是「下一跳」落的：不跑 runloop 拿到的是 0×0 退化帧（R47 实测两次）。
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        Self.retainedWindows.append(window)

        guard let textView = Self.firstTextView(in: hosting) else {
            XCTFail("\(surface.label) 的视图树里找不到 `NSTextView` —— 编辑面没被建出来")
            throw UISnapshot.SnapshotError.renderFailed("\(surface.rawValue)：没有 NSTextView")
        }
        let frame = textView.convert(textView.bounds, to: hosting)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * Self.scale),
            pixelsHigh: Int(size.height * Self.scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("位图分配失败")
            throw UISnapshot.SnapshotError.renderFailed("bitmap")
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw UISnapshot.SnapshotError.encodeFailed(surface.rawValue)
        }
        try FileManager.default.createDirectory(at: Self.stateDirectory, withIntermediateDirectories: true)
        let url = Self.stateDirectory.appendingPathComponent(
            "editor-surface-parity-\(surface.fileTag)-\(theme.id)"
                + "-\(scheme == .darkAqua ? "dark" : "light").png"
        )
        try data.write(to: url)

        // 取样框**按文本视图自己的 frame 算**（横向 45…95%、纵向 45…92%）：空正文里这一块没有字，
        // 也没有光标（光标在左上）。版式一改，这条算式跟着变，不会量到编辑面外面去。
        let leading = (frame.minX + frame.width * 0.45) * Self.scale
        let trailing = (frame.minX + frame.width * 0.95) * Self.scale
        let topEdge = (size.height - frame.maxY) * Self.scale      // 位图行序自上而下
        let top = topEdge + frame.height * Self.scale * 0.45
        let bottom = topEdge + frame.height * Self.scale * 0.92
        let box = (
            leading: Int(leading.rounded()),
            top: Int(top.rounded()),
            width: Int((trailing - leading).rounded()),
            height: Int((bottom - top).rounded())
        )
        guard let band = UISnapshot.region(
            ofPNGAt: url.path, leading: box.leading, top: box.top, width: box.width, height: box.height
        ) else {
            XCTFail("\(surface.label) 的取样矩形落在图外 —— 取样框要按文本视图的 frame 算，不该越界")
            throw UISnapshot.SnapshotError.renderFailed("\(surface.rawValue)：取样越界")
        }

        let expected = UISnapshot.channels(of: theme.palette.content.hex(dark: scheme == .darkAqua))
        return Reading(
            surface: surface,
            rgb: (Int(band.background.0), Int(band.background.1), Int(band.background.2)),
            expected: expected,
            sample: box,
            textView: frame,
            pngBytes: data.count
        )
    }

    // MARK: - 断言

    private func assertToken(_ reading: Reading, tolerance: Int = 8) {
        XCTAssertLessThanOrEqual(
            reading.delta, tolerance,
            "\(reading.line) —— 这一面没画该主题该深浅档的 `content` 令牌"
                + "（`FR-STD-WS-UI-011` ③：底色只许取内容面令牌）"
        )
    }

    private func channelsDelta(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        max(abs(lhs.0 - rhs.0), max(abs(lhs.1 - rhs.1), abs(lhs.2 - rhs.2)))
    }

    /// 三面互为同一个色值（容差 4：三面走同一条解码路径，实测应为 0）。
    private func assertSameBase(_ readings: [Reading], tolerance: Int = 4, note: String) {
        guard let base = readings.first else {
            XCTFail("\(note)：一面都没量到")
            return
        }
        for reading in readings.dropFirst() {
            let delta = channelsDelta(reading.rgb, base.rgb)
            XCTAssertLessThanOrEqual(
                delta, tolerance,
                "\(note)：\(reading.surface.label) \(reading.rgb) 与 \(base.surface.label) \(base.rgb)"
                    + " 差 \(delta) —— 三处编辑面**不同底**（`FR-STD-WS-UI-011` ①）"
            )
        }
    }

    // MARK: - 判据 ① 深色

    @MainActor
    func testThreeSurfacesPaintTheSameContentTokenInDark() throws {
        var readings: [Reading] = []
        for surface in EditSurface.panels {
            let reading = try measure(surface, theme: .techBlue, scheme: .darkAqua)
            print("🎨 \(reading.line)")
            assertToken(reading)
            readings.append(reading)
        }
        assertSameBase(readings, note: "深色 · 科技蓝")
    }

    // MARK: - 判据 ② 浅色

    @MainActor
    func testThreeSurfacesPaintTheSameContentTokenInLight() throws {
        var readings: [Reading] = []
        for surface in EditSurface.panels {
            let reading = try measure(surface, theme: .techBlue, scheme: .aqua)
            print("🎨 \(reading.line)")
            assertToken(reading)
            readings.append(reading)
        }
        assertSameBase(readings, note: "浅色 · 科技蓝")
    }

    // MARK: - 判据 ③ 五个主题逐个

    @MainActor
    func testThreeSurfacesAgreeOnEveryTheme() throws {
        for theme in DesignTheme.all {
            var readings: [Reading] = []
            for surface in EditSurface.panels {
                let reading = try measure(surface, theme: theme, scheme: .darkAqua)
                assertToken(reading)
                readings.append(reading)
            }
            print(
                "🎨 主题 \(theme.id)："
                    + readings.map { "\($0.surface.rawValue)=\($0.rgb)" }.joined(separator: " / ")
            )
            assertSameBase(readings, note: "深色 · 主题 \(theme.id)")
        }
    }

    // MARK: - 判据 ④ 切深浅：三面一起变（无一处保留旧色）

    @MainActor
    func testSwitchingAppearanceChangesEverySurface() throws {
        for surface in EditSurface.panels {
            let dark = try measure(surface, theme: .techBlue, scheme: .darkAqua)
            let light = try measure(surface, theme: .techBlue, scheme: .aqua)
            let delta = channelsDelta(dark.rgb, light.rgb)
            print(
                "🎨 切深浅 · \(surface.label)：深 \(dark.rgb)（令牌 \(dark.expected)）"
                    + " / 浅 \(light.rgb)（令牌 \(light.expected)）差 \(delta)"
            )
            assertToken(dark)
            assertToken(light)
            XCTAssertGreaterThan(
                delta, 8,
                "\(surface.label) 切深浅之后底色只差 \(delta)（深 \(dark.rgb) / 浅 \(light.rgb)）"
                    + " —— 这一面停在了旧色上（`FR-STD-WS-UI-011` ②：三处同步成套）"
            )
        }
    }

    // MARK: - 判据 ⑤ 切主题：三面一起变

    @MainActor
    func testSwitchingThemeChangesEverySurface() throws {
        // 科技蓝 ↔ 玫瑰金：两者的深色 content 实测 (11,26,42) / (38,20,26)，差 27 ⇒ 判得出来。
        // （科技蓝 ↔ 深空苍穹 只差 6，**刻意不用来判「变了没有」** —— 那样的门槛会把判据做成恒真。）
        for surface in EditSurface.panels {
            let techBlue = try measure(surface, theme: .techBlue, scheme: .darkAqua)
            let roseGold = try measure(surface, theme: .roseGold, scheme: .darkAqua)
            let delta = channelsDelta(techBlue.rgb, roseGold.rgb)
            print(
                "🎨 切主题 · \(surface.label)：科技蓝 \(techBlue.rgb) / 玫瑰金 \(roseGold.rgb) 差 \(delta)"
            )
            assertToken(techBlue)
            assertToken(roseGold)
            XCTAssertGreaterThan(
                delta, 8,
                "\(surface.label) 切主题之后底色只差 \(delta)（科技蓝 \(techBlue.rgb) / 玫瑰金 \(roseGold.rgb)）"
                    + " —— 这一面停在旧主题上（`FR-STD-WS-UI-011` ②）"
            )
        }
    }

    // MARK: - 判据 ⑥ 对照件：这套量法必须分得出「没走令牌」的底色

    @MainActor
    func testBareTextViewIsNotTheContentToken() throws {
        let control = try measure(.bareControl, theme: .techBlue, scheme: .darkAqua)
        print("🎨 对照件（裸 NSTextView，系统底色）：\(control.line)")
        XCTAssertGreaterThan(
            control.delta, 8,
            "对照件（没走令牌的裸 `NSTextView`）在同一套量法下取到的底色 \(control.rgb)"
                + " 与令牌 \(control.expected) 差不出 8 以上 ⇒ 这套量法分辨不了两种底色，"
                + "前面几条「三面同值」不算数（同 R47 的对照件纪律）"
        )
    }

    // MARK: - 判据 ⑦ 空跑防护：取样框真的落在编辑面里

    @MainActor
    func testSampleWindowLandsInsideEveryTextView() throws {
        for surface in EditSurface.panels {
            let reading = try measure(surface, theme: .techBlue, scheme: .darkAqua)
            print("🎨 取样面 · \(reading.line)")
            XCTAssertGreaterThan(
                reading.textView.height, 60,
                "\(surface.label) 的 `NSTextView` 只有 \(reading.textView.height)pt 高 —— 像是没布局出来"
            )
            XCTAssertGreaterThan(
                reading.textView.width, 200,
                "\(surface.label) 的 `NSTextView` 只有 \(reading.textView.width)pt 宽 —— 像是没布局出来"
            )
            XCTAssertGreaterThan(
                reading.pngBytes, 20_000,
                "\(surface.label) 的渲染只有 \(reading.pngBytes) 字节 —— 像是渲染成了空白"
            )
            XCTAssertGreaterThan(
                reading.sample.width, 40,
                "\(surface.label) 的取样框只有 \(reading.sample.width) 像素宽 —— 采不到底色"
            )
            XCTAssertGreaterThan(
                reading.sample.height, 20,
                "\(surface.label) 的取样框只有 \(reading.sample.height) 像素高 —— 采不到底色"
            )
        }
    }
}
