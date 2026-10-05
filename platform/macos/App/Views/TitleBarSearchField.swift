import AppKit
import SwiftUI

import DoyahCore

/// 标题栏里那一枚**搜索栏**（`FR-EDIT-37`；宽度策略见队列 `L-141` 与 `Core/TitleBarSearchLayout`）。
///
/// ## 为什么不再用 `.searchable(placement: .toolbarPrincipal)`
///
/// 系统给的宽度**与窗口宽度无关**，于是需求提出者 2026-09-30 内测看到的是：
/// 「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」（甲1）。
/// 位置仍是**正中**（`.principal`，原话「标题后面居中」），但宽度改由**本策略**给：
/// 窗口变窄 ⇒ 搜索栏收敛；窄到放不下 ⇒ 整条不显示（回车入口仍在 ⌘K / 命令面板）。
///
/// ## 整框改用 AppKit 承载（2026-10-02 复测打回后的**结构性换法**）
///
/// 上一轮（第 162 轮 · `T-20261002-027`）的修法是「SwiftUI 自绘框 + 一层 AppKit 点击接力」，
/// 并给自绘的填充 / 边线 / 图标各加 `.allowsHitTesting(false)`。那套修法在**手工搭的工具条宿主**
/// 里判绿，可需求提出者在**真包**上再点一次仍然是「点不上、打不进」（原话：
/// 「这个搜索框是无法用鼠标点击到搜索框，所以也就无法输入」）。
///
/// 根子在于：只要框里还有**SwiftUI 画的层**压在 AppKit 视图之上，命中测试走的就是
/// SwiftUI 自己那条路，装饰层参不参与、接力层能不能接到，全看宿主（工具条项）怎么摆 ——
/// 判据量的那套宿主与真窗口不是同一个，绿了也说明不了真包。⇒ 这一轮不再叠层：
/// **整框就是一个 AppKit 视图**（`TitleBarSearchBoxView`），输入框是它的**子视图**，
/// 放大镜与清空按钮也都是 AppKit 控件。可见区域内**一处 SwiftUI 内容都没有**，
/// 命中测试就是普通 AppKit 那条路（点哪儿归谁一目了然）。
///
/// 边界（如实登记）：本文件里的判据（`TestsUISnapshot/TitleBarSearchClickProbeTests.swift`）
/// 与真窗口探针（`DOYAH_SEARCHBOX_PROBE`）量的是**命中测试把点击交给谁**与**留白点是否把
/// 键盘交给输入框**；「真鼠标按下去有没有光标」这一条仍要**人在场点一次**才算走完。
struct TitleBarSearchField: View {
    /// 窗口**内容区**宽度（pt）。
    let windowWidth: CGFloat

    /// 当前窗口标题原文（宽度从它量）。
    let titleText: String

    @EnvironmentObject private var appState: AppState

    var body: some View {
        let width = TitleBarSearchLayout.searchFieldWidth(
            windowWidth: windowWidth,
            titleWidth: TitleBarSearchMetrics.titleWidth(of: titleText)
        )
        if width > 0 {
            TitleBarSearchBox(
                width: width,
                text: Binding(
                    get: { appState.globalSearchQuery },
                    set: { appState.globalSearchQuery = $0 }
                ),
                // 回车把词交给**命令面板**（与 ⌘K 共用一处入口 —— 搜索栏不另做一套搜索）。
                onSubmit: { appState.presentCommandPalette(seed: appState.globalSearchQuery) }
            )
            .frame(width: width, height: TitleBarSearchMetrics.boxHeight)
            .help(L(.windowSearchPlaceholder))
        } else {
            // 这一档放不下：**整条不显示**（不做一条宽几十 pt、既遮标题又没法用的搜索框）。
            // 回车那条路仍在（⌘K → 命令面板），所以「找东西」这件事不会因此变成死路。
            EmptyView()
        }
    }
}

// MARK: - 整框（AppKit，唯一实现）

/// 搜索栏整框的**平台视图**（`NSViewRepresentable`）。
///
/// 这一层只做三件事：把宽度交给 AppKit 侧（工具条项按它定尺寸）、把文本绑定接上、
/// 把回车接到命令面板。**命中测试与焦点一个字都不在这里管** —— 那都在 `TitleBarSearchBoxView`。
struct TitleBarSearchBox: NSViewRepresentable {
    /// 整框宽度（pt）—— 与 SwiftUI 侧的 `.frame(width:)` 同值（工具条项按内在尺寸定大小）。
    let width: CGFloat

    @Binding var text: String

    var onSubmit: () -> Void

    func makeNSView(context: Context) -> TitleBarSearchBoxView {
        let box = TitleBarSearchBoxView()
        box.preferredWidth = width
        box.stringValue = text
        box.onTextChange = { newValue in
            // 回调都来自 AppKit 事件（不在 SwiftUI 更新里），直接写绑定即可。
            if text != newValue { text = newValue }
        }
        box.onSubmit = onSubmit
        return box
    }

    func updateNSView(_ box: TitleBarSearchBoxView, context: Context) {
        box.preferredWidth = width
        box.onTextChange = { newValue in
            if text != newValue { text = newValue }
        }
        box.onSubmit = onSubmit
        box.stringValue = text
    }
}

/// 输入框那枚 `NSTextField`：**窗口不是 key 时第一击也要落进来**。
///
/// macOS 的默认行为是「非活动窗口的第一次点击只激活窗口、不交给控件」（click-through）。
/// 需求提出者点的是**标题栏**那一枚 —— 只要 App 不是当前活动窗口，第一击必然"没反应"，
/// 再点一次才可能进去。搜索栏这种"点一下就要能打字"的控件不该吃这一条，
/// 所以在这里显式放行（容器那一层同理）。
final class TitleBarSearchFieldView: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// **看得见的框 = 能点的框**（派活单 `T-20261002-027` **二次复测打回**后的结构性换法）。
///
/// 整框是一个 `NSView`：自己画底与边线，里面放放大镜（`NSImageView`）、输入框
/// （`TitleBarSearchFieldView`）、清空按钮（`NSButton`）三个**真控件**。
///
/// 命中测试（真鼠标走的就是这条路）：
/// · 落在三个控件上的点击 ⇒ AppKit 自己交给它们（输入框拿去聚焦、`×` 拿去清空）；
/// · 落在**留白**（左侧放大镜那一段、上下内边距、控件之间的缝）上的点击 ⇒ 落到本视图，
///   由 `mouseDown` 把那枚输入框设为第一响应者（**直接持有的引用**，不是按类名去工具条里找 ——
///   上一轮那层接力就是"找不到目标时悄悄什么都不做"，肉眼与判据都看不出来）。
///
/// 只动**第一响应者**与光标位置：不碰文本内容、不碰绑定、不动任何 SwiftUI 状态
/// （第 162 轮的教训：点击里改 SwiftUI 状态会让这一层重排、刚拿到的第一响应者当场被收回）。
final class TitleBarSearchBoxView: NSView, NSTextFieldDelegate {

    // MARK: 对外

    /// 整框宽度（pt）。工具条项按内在尺寸定大小 ⇒ 与 SwiftUI 侧的 `.frame` 同值。
    var preferredWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// 文本变化（用户真的改动了文本才会回调；程序侧赋值不走这里）。
    var onTextChange: ((String) -> Void)?

    /// 回车。
    var onSubmit: (() -> Void)?

    /// 文本（程序侧赋值，**不**回调 `onTextChange`）。
    var stringValue: String {
        get { field.stringValue }
        set {
            guard field.stringValue != newValue else { return }
            field.stringValue = newValue
            updateClearButton()
        }
    }

    /// 整框高度（pt）—— 正文行高 + 上下各 `Spacing.xs`。
    static var boxHeight: CGFloat { TitleBarSearchMetrics.boxHeight }

    // MARK: 控件

    private let iconView = NSImageView()
    private let field = TitleBarSearchFieldView()
    private let clearButton = NSButton()

    /// 清空按钮离右边、与输入框之间的间距（与上一轮 `trailingReserve` 同一个口径）。
    private var clearButtonTrailing: NSLayoutConstraint!
    private var fieldTrailing: NSLayoutConstraint!

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: Self.boxHeight)
    }

    // MARK: 生命周期

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        TitleBarSearchBoxProbe.schedule(for: self)
    }

    // MARK: 画

    override func draw(_ dirtyRect: NSRect) {
        let inset = Metrics.hairline / 2
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: Radius.control,
            yRadius: Radius.control
        )
        Theme.nsColor(Surface.raised).setFill()
        path.fill()
        Theme.hairlineNSColor.setStroke()
        path.lineWidth = Metrics.hairline
        path.stroke()
    }

    // MARK: 命中测试与焦点

    /// 窗口不是 key 时，第一击也要落进来（理由见 `TitleBarSearchFieldView`）。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 落在**留白**上的点击：把键盘交给同一框里的输入框，并把光标放到词尾
    /// （与"点在框里"的直觉一致）。不碰文本、不碰绑定。
    override func mouseDown(with event: NSEvent) {
        focusField()
    }

    private func focusField() {
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }

    // MARK: 装配

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: L(.windowSearchPlaceholder)
        )?.withSymbolConfiguration(.init(textStyle: .body, scale: .small))
        iconView.contentTintColor = Theme.nsColor(TextTone.tertiary)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.nsFont(.body)
        field.textColor = Theme.nsColor(TextTone.primary)
        field.placeholderString = L(.windowSearchPlaceholder)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        (field.cell as? NSTextFieldCell)?.isScrollable = true
        (field.cell as? NSTextFieldCell)?.wraps = false
        field.delegate = self
        field.target = self
        field.action = #selector(handleSubmit)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.imagePosition = .imageOnly
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: L(.commonClose)
        )?.withSymbolConfiguration(.init(textStyle: .body, scale: .small))
        clearButton.contentTintColor = Theme.nsColor(TextTone.tertiary)
        clearButton.target = self
        clearButton.action = #selector(handleClear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        clearButtonTrailing = clearButton.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Spacing.s
        )
        fieldTrailing = field.trailingAnchor.constraint(
            equalTo: clearButton.leadingAnchor,
            constant: -Spacing.xs
        )
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.s),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Spacing.xs),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: TitleBarSearchMetrics.fieldHeight),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButtonTrailing,
            fieldTrailing,
        ])
        // 无障碍：整框报一个名字，里面那枚输入框仍是可读可写的标准控件。
        setAccessibilityElement(false)
        field.setAccessibilityLabel(L(.windowSearchPlaceholder))
        updateClearButton()
    }

    private func updateClearButton() {
        // 空词时 `×` 不显示（与上一轮同一个观感）。它**仍在布局里**（宽度不让出来）——
        // 这样点右侧那一段要么落进输入框、要么落到本视图被转发成聚焦，不会是"点上去什么都没发生"。
        clearButton.isHidden = field.stringValue.isEmpty
    }

    // MARK: 动作

    @objc private func handleSubmit() {
        // 先把词**落定**到绑定（面板的 seed 读的就是它），再交出去 —— 顺序不能反。
        onTextChange?(field.stringValue)
        onSubmit?()
    }

    @objc private func handleClear() {
        field.stringValue = ""
        updateClearButton()
        onTextChange?("")
        focusField()
    }

    func controlTextDidChange(_ obj: Notification) {
        // **刻意不在这里写绑定**：每敲一个字都改 SwiftUI 状态 ⇒ 工具条那一项跟着重排，
        // 而 SwiftUI 更新里那点动静会把 AppKit 的**编辑会话**收掉（字段编辑器被撤掉）——
        // 于是"字打进去了，但按回车没反应、也没有面板"。
        //
        // 真窗口实测（`DOYAH_SEARCHBOX_PROBE`）：**空框**里按回车 ⇒ 面板起得来；
        // **打了字**再按回车 ⇒ 面板起不来；同一时刻直接打 `target/action` ⇒ 面板起得来
        // ⇒ 断的不是"出口"，是"回车的键根本没走到动作"。
        //
        // 所以文本在 AppKit 这一侧是**唯一实时的**，只在"落定"时同步给绑定：
        // 回车（`handleSubmit`）、点 `×`（清空）、编辑结束（`controlTextDidEndEditing`）。
        updateClearButton()
    }

    /// 编辑结束（失焦）也算落定：这时候同步一次，免得"打了字又去点别处"之后词丢了。
    func controlTextDidEndEditing(_ obj: Notification) {
        onTextChange?(field.stringValue)
    }
}

// MARK: - 真窗口探针

/// **真窗口**里的命中地图（`DOYAH_SEARCHBOX_PROBE=<文件路径>`）。
///
/// 为什么要有它：上一轮那套判据量的宿主是**手工搭的工具条窗口**，而缺陷出现在 App 自己那个
/// 窗口里（SwiftUI 自己的工具条接线）—— 判据与真包之间那一段是空档。这个探针把量法搬进
/// **产品自己的窗口**：等窗口真的起来、这一枚真的进了视图树之后，
///
/// ① 逐个采样点问**真那条命中测试**（`window.contentView.hitTest`）「这一点会交给谁」；
/// ② 报输入框的 `isEnabled / isEditable / isSelectable`（需求提出者怀疑过的 `enabled=false`
///    —— 这是能直接读到的一手数据，不必猜）；
/// ③ 在**留白**那一点造一次合成 `mouseDown` 打给命中目标，看第一响应者有没有变成输入框的
///    字段编辑器（这一条正是"点留白能不能打字"的机器版）；
/// ④ 写完文件就退出（探针是一次性进程，不留在屏幕上）。
enum TitleBarSearchBoxProbe {

    static let environmentKey = "DOYAH_SEARCHBOX_PROBE"

    static func schedule(for box: TitleBarSearchBoxView) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[environmentKey], !path.isEmpty else { return }
        let delay = Double(environment["DOYAH_SEARCHBOX_PROBE_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            write(box, to: path)
        }
    }

    /// 采样网格：7 列 × 3 行（含四角与正中）。可见框内的**每一个**采样点都要有人接。
    private static let columns = 7
    private static let rows = 3

    private static func write(_ box: TitleBarSearchBoxView, to path: String) {
        guard let window = box.window, let content = window.contentView else { return }
        var lines: [String] = []
        let appearance = window.effectiveAppearance.name.rawValue

        lines.append("probe=search-box-hit-map")
        lines.append("window.title=\(window.title)")
        lines.append("window.isKeyWindow=\(window.isKeyWindow)")
        lines.append("window.isMainWindow=\(window.isMainWindow)")
        lines.append("window.appearance=\(appearance)")

        let boxInWindow = box.convert(box.bounds, to: nil)
        lines.append("box.frameInWindow=\(describe(boxInWindow))")
        lines.append("box.frameInContent=\(describe(box.convert(box.bounds, to: content)))")
        lines.append("box.intrinsicContentSize=\(describe(CGRect(origin: .zero, size: box.intrinsicContentSize)))")
        lines.append("box.subviews=\(box.subviews.map { NSStringFromClass(type(of: $0)) }.joined(separator: ","))")

        let field = box.controls.field
        let clearButton = box.controls.clearButton
        // **真实那条路**：鼠标事件先在**窗口框架视图**（`NSThemeFrame`）上做命中测试 ——
        // 标题栏那一层是它的**兄弟**（与内容视图并列），从 `contentView` 出发**看不见标题栏**
        // （这就是上一轮"量了却量不到点上"的同一个坑：入口挑错，量法就成了摆设）。
        let root = window.contentView?.superview ?? content
        lines.append("hitTest.entry=\(NSStringFromClass(type(of: root)))")
        lines.append("field.isEnabled=\(field.isEnabled)")
        lines.append("field.isEditable=\(field.isEditable)")
        lines.append("field.isSelectable=\(field.isSelectable)")
        lines.append("field.acceptsFirstMouse=\(field.acceptsFirstMouse(for: nil))")
        lines.append("field.frameInWindow=\(describe(field.convert(field.bounds, to: nil)))")
        lines.append("field.placeholder=\(field.placeholderString ?? "-")")
        lines.append("clearButton.isHidden=\(clearButton.isHidden)")
        lines.append("clearButton.frameInWindow=\(describe(clearButton.convert(clearButton.bounds, to: nil)))")

        lines.append("firstResponder.before=\(describe(firstResponder: window))")

        // ① 逐点：真那条命中测试会把这一点交给谁。
        var paddingPoint: NSPoint?
        var paddingTarget: NSView?
        for row in 0...(rows - 1) {
            for column in 0...(columns - 1) {
                let unit = CGPoint(
                    x: CGFloat(column) / CGFloat(columns - 1),
                    y: CGFloat(row) / CGFloat(rows - 1)
                )
                let inBox = NSPoint(
                    x: box.bounds.minX + unit.x * (box.bounds.width - 1),
                    y: box.bounds.minY + unit.y * (box.bounds.height - 1)
                )
                let inWindow = box.convert(inBox, to: nil)
                let target = root.hitTest(inWindow)
                let contentTarget = content.hitTest(inWindow)
                let name = target.map { NSStringFromClass(type(of: $0)) } ?? "nil"
                let owner: String
                switch target {
                case let view as NSView where view === field: owner = "field"
                case let view as NSView where view === clearButton: owner = "clearButton"
                case let view as NSView where view === box: owner = "box"
                case .some: owner = "other"
                case .none: owner = "nil"
                }
                lines.append(
                    "point[\(column),\(row)]=\(owner) class=\(name) "
                        + "contentViewEntry="
                        + (contentTarget.map { NSStringFromClass(type(of: $0)) } ?? "nil")
                        + " inWindow=\(describe(CGRect(origin: inWindow, size: .zero)))"
                )
                // 第一列与中间那一行必是留白（放大镜那一段）。
                if column == 0, row == 1, paddingPoint == nil {
                    paddingPoint = inWindow
                    paddingTarget = target ?? box
                }
            }
        }

        // ② 留白点按下：第一响应者应当变成输入框的字段编辑器。
        if let location = paddingPoint, let target = paddingTarget {
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
            lines.append("padding.target=\(NSStringFromClass(type(of: target)))")
            if let event {
                target.mouseDown(with: event)
            }
            lines.append("firstResponder.afterPaddingClick=\(describe(firstResponder: window))")
            lines.append("fieldHasFocus=\(describe(fieldHasFocus: window, field: field))")
        }

        // ③ 回车那条路，**两条都要量**：
        //
        // · 真键盘那条 = 字段编辑器吃到回车（`insertNewline:`）—— 这是人按 Return 时真正发生的一步；
        // · 直接打动作那条 = `target/action`（判"出口有没有接上"）。
        //
        // 只量后者会漏掉"回车的键根本没走到动作"这一层（需求提出者实测：按回车面板不弹）。
        lines.append("submit.fieldAction=\(field.action.map { NSStringFromSelector($0) } ?? "nil")")
        window.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let editor = field.currentEditor() as? NSTextView
        lines.append("submit.editor=\(editor.map { NSStringFromClass(type(of: $0)) } ?? "nil")")
        lines.append("submit.responderWhenEditing=\(describe(firstResponder: window))")

        // **先像人那样敲几个字**（走字段编辑器 ⇒ 会真的触发 `controlTextDidChange` ⇒ 绑定那一趟），
        // 再按回车 —— 只量"空框回车"会漏掉"框里有词时"这条路（需求提出者就是打了字再回车的）。
        let typed = "probe"
        editor?.insertText(typed, replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        lines.append("submit.afterTyping.boxText=\(field.stringValue)")
        lines.append("submit.afterTyping.editorText=\(editor?.string ?? "nil")")

        lines.append("submit.sheets.before=\(window.sheets.count)")
        editor?.insertNewline(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        lines.append("submit.sheets.afterKeyboard=\(window.sheets.count)")
        window.sheets.forEach { $0.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        lines.append("submit.sheets.afterClose=\(window.sheets.count)")
        if let action = field.action {
            _ = field.target?.perform(action)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        lines.append("submit.sheets.afterAction=\(window.sheets.count)")
        lines.append(
            "submit.windows="
                + NSApp.windows.map { "\(NSStringFromClass(type(of: $0))):visible=\($0.isVisible)" }
                    .joined(separator: ",")
        )

        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(("search-box probe written: \(path)\n").utf8))
        // 探针是一次性进程：写完就走（与菜单 dump 探针同一条口径）。
        exit(0)
    }

    private static func describe(_ rect: CGRect) -> String {
        "(\(round(rect.minX)),\(round(rect.minY)),\(round(rect.width)),\(round(rect.height)))"
    }

    private static func describe(firstResponder window: NSWindow) -> String {
        window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil"
    }

    /// 焦点是否真的在输入框上：窗口的第一响应者要么是输入框自己，
    /// 要么是它拉起来的**字段编辑器**（`NSTextView`，`delegate` 指回输入框）。
    private static func describe(fieldHasFocus window: NSWindow, field: NSTextField) -> Bool {
        if window.firstResponder === field { return true }
        if let editor = window.firstResponder as? NSTextView,
           let delegate = editor.delegate,
           (delegate as AnyObject) === field {
            return true
        }
        return false
    }
}

/// 探针要读的几个控件（唯一出处：`TitleBarSearchBoxView` 自己）。
extension TitleBarSearchBoxView {
    var controls: (field: NSTextField, clearButton: NSButton) {
        (field, clearButton)
    }
}

// MARK: - 度量

/// 标题宽度与整框几何的**实量**（唯一出处）—— 策略只吃一个数，数从这里来。
enum TitleBarSearchMetrics {
    /// 标题栏字体：macOS 用**系统字号**（13pt）加 semibold，与标题栏实际绘制一致。
    static var titleFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    /// 输入框那一行的高度（pt）—— 正文行高的**实量**（13pt 系统字 = 16pt，真窗口量到的也是 16）。
    static var fieldHeight: CGFloat {
        let font = Theme.nsFont(.body)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// 整框高度（pt）—— 输入框行高 + 上下各 `Spacing.xs`（真窗口量到的是 24）。
    static var boxHeight: CGFloat { fieldHeight + 2 * Spacing.xs }

    static func titleWidth(of title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: titleFont]).width
    }
}
