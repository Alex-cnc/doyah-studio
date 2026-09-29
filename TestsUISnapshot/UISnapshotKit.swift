import AppKit
import CryptoKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **界面快照基建**（队列 L-01）。
///
/// ## 为什么是这条路
///
/// - `Scripts/design-mock.swift` 是**照着重画**的样张 —— 它证明"设计长这样"，证明不了"真界面长这样"；
/// - 屏幕录制权限还没拿到，助理截不了运行中 App 的图（spec §7「桌面操作能力」）；
/// - `SwiftUI.ImageRenderer` 是**离屏**渲染**真视图树**：不需要辅助功能、不需要屏幕录制、
///   不需要图形会话里的窗口 —— 于是 spec §5.2 的"静态观感类"条目第一次有了可复现的机器证据。
///
/// ## 三条纪律
///
/// 1. **不进每轮门禁**：`Scripts/verify-core.sh` 的 `swift test` 会**编译**本 target，但用例默认
///    `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1` 才跑）。快照是**取证工具**，塞进门禁只会拖慢门禁并制造假失败。
/// 2. **产物落在 `.build/ui-snapshots/`**（`.build/` 已在 `.gitignore` 里）—— 快照是**证据**，不是交付物。
/// 3. **每张图都要带断言**：渲染完立刻校验"非空白"（非背景像素占比下限）并把像素尺寸写进清单。
///    只产出 PNG 不断言的话，一张全白的图也会被当成"界面没问题"。
enum UISnapshot {

    static let enableKey = "DOYAH_UI_SNAPSHOT"

    static var isEnabled: Bool { ProcessInfo.processInfo.environment[enableKey] == "1" }

    /// 工程根（由 `#filePath` 反推，不依赖 cwd）。
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TestsUISnapshot/
        .deletingLastPathComponent()   // <root>/

    /// 产物目录：默认 `.build/ui-snapshots/`，可用 `DOYAH_SNAPSHOT_DIR` 覆盖。
    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["DOYAH_SNAPSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return packageRoot.appendingPathComponent(".build/ui-snapshots", isDirectory: true)
    }

    // MARK: - 清单

    struct Record: Codable {
        var name: String
        var file: String
        var width: Int
        var height: Int
        var scale: Double
        var scheme: String
        var bytes: Int
        /// 非背景像素占比（0~1）。用来挡"渲染成空白但文件不为空"这种假绿。
        var contentRatio: Double
        /// 实际画出内容的那条渲染路径（含两条路径各自的占比，便于排障）。
        var renderer: String
        /// 这一遍用的是哪种语言（队列 L-13）。生产界面由用户选择决定，快照由**宿主语境**决定。
        var language: String
        /// 这一遍 `L(...)` 实际取到的**文案**（去重并排序）。
        ///
        /// 为什么要落进清单：语言快照光有「两张图不一样」说明不了差在哪，也不足以判「语言有没有
        /// 到像素上」。把它记下来之后，判据可以做成**两侧对照**（见
        /// `Scripts/check-ui-snapshot-languages.py`）：文案不同 ⇒ 像素必须不同；注册为语言无关的
        /// 那几张（文案只走到 `.help` / 无障碍标签）像素必须**相同** —— 两个方向都能机械查。
        var localizedStrings: [String]
    }

    private(set) static var records: [Record] = []

    // MARK: - 渲染

    enum SnapshotError: Error, CustomStringConvertible {
        case renderFailed(String)
        case encodeFailed(String)
        /// 两条渲染路径都没画出内容：`(快照名, 各路径的内容占比说明)`
        case blank(String, String)

        var description: String {
            switch self {
            case .renderFailed(let name): return "渲染没产出位图：\(name)"
            case .encodeFailed(let name): return "PNG 编码失败：\(name)"
            case .blank(let name, let detail): return "快照没有内容：\(name)（各渲染路径的内容占比：\(detail)）"
            }
        }
    }

    /// 渲染一张快照并落盘。`content` 拿到的视图**不要**自己设 frame —— 尺寸由这里统一给。
    ///
    /// `language` 非空时进入**宿主语境**（`LocalizationManager.beginHostLanguage`）：
    /// 这一遍 `L(...)` 全部按它出文案，并把文案记进记录（不写用户偏好、不动用户选择）。
    /// 常规调用请用 `writeBothLanguages` —— 单语言的 `write` 留给"确实只拍一面"的场合。
    @MainActor
    @discardableResult
    static func write<V: View>(
        _ name: String,
        size: CGSize,
        scheme: ColorScheme = .light,
        scale: CGFloat = 2,
        minimumContentRatio: Double = 0.002,
        language: AppLanguage? = nil,
        @ViewBuilder content: () -> V
    ) throws -> Record {
        // 一开一关必须成对：渲染中途抛错也不能把语境留在栈上（否则后面每一张都会串语言）。
        let scope = language.map { LocalizationManager.beginHostLanguage($0) }
        defer { if scope != nil { LocalizationManager.endHostLanguage() } }

        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 合成在**窗口底色**上：真运行时这些视图背后就有这一层（面板自己不带不透明底），
        // 不铺的话导出的 PNG 是透明底 —— 看图的人分不清"这里是空白"还是"这里什么都没画"，
        // 而"什么都没画"恰恰是快照要抓的失败态。
        //
        // 注意 `.environment` 必须在**最外层**：写在 ZStack 内部时，后面的 `.background`
        // 之类会落在它的作用域之外，深色一遍就会用系统真实外观去解析动态色。
        let view = ZStack {
            Theme.surface(.window)
            content()
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)

        // 三条渲染路径都试，取能画出内容的那条（见 `renderer` 字段：证据要说明**怎么来的**）。
        //
        // 实测（本机 / Swift 6.4）：
        // · `ImageRenderer` 对 **`ScrollView`** 与 **`NSViewRepresentable`** 两种容器画不出内容 ——
        //   `ScrollView { Text(…) }`、工作区 Home 页、结果表主体（`ResultGrid` 是 AppKit 自绘）
        //   都渲染成**整幅背景**或干脆是系统的"不可渲染"占位图，结果表只画出 SwiftUI 那半边（工具栏）。
        // · 无窗口的 `NSHostingView` + `cacheDisplay` 能画 `ScrollView`，但 **AppKit 自绘的
        //   `List` / 侧栏**画不出来（第 10 轮实测：连接列表整幅背景）；
        // · 给它一个**离屏窗口**（路径一）后连 `List` 也能画出来。
        // 所以顺序是：窗口宿主 → 无窗口宿主 → `ImageRenderer`，**先密后疏**，
        // 并把 Apple 的占位图在选路阶段就淘汰掉（否则它比真界面还"有内容"，见 `placeholderShare`）。
        let attempts: [(label: String, render: () throws -> CGImage)] = [
            ("NSWindow+NSHostingView", { try windowHostedImage(view, size: size, scale: scale, scheme: scheme) }),
            ("NSHostingView", { try hostedImage(view, size: size, scale: scale, scheme: scheme) }),
            ("ImageRenderer", { try imageRenderer(view, size: size, scale: scale) }),
        ]

        var attemptsLog: [String] = []
        var picked: (label: String, image: CGImage, ratio: Double)?
        for attempt in attempts {
            do {
                let image = try attempt.render()
                // 占位图**先判**：Apple 那条"不可渲染"的路（黄底红圈）在像素上很密，
                // 非空白占比能到 0.18，光看占比会把一张占位图当成"界面没问题"（第 10 轮实测就是这么被骗的）。
                if let share = placeholderShare(image) {
                    attemptsLog.append("\(attempt.label)=不可渲染占位图（黄 \(String(format: "%.2f", share.yellow))/红 \(String(format: "%.2f", share.red))）")
                    continue
                }
                let ratio = contentRatio(of: image)
                attemptsLog.append("\(attempt.label)=\(String(format: "%.3f", ratio))")
                if ratio >= minimumContentRatio {
                    picked = (attempt.label, image, ratio)
                    break
                }
            } catch {
                attemptsLog.append("\(attempt.label)=失败(\(error))")
            }
        }

        guard let picked else {
            throw SnapshotError.blank(name, attemptsLog.joined(separator: " / "))
        }

        let cgImage = picked.image
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodeFailed(name)
        }
        let url = directory.appendingPathComponent("\(name).png", isDirectory: false)
        try data.write(to: url, options: .atomic)

        let ratio = picked.ratio

        let record = Record(
            name: name,
            file: url.path,
            width: cgImage.width,
            height: cgImage.height,
            scale: Double(scale),
            scheme: scheme == .dark ? "dark" : "light",
            bytes: data.count,
            contentRatio: ratio,
            renderer: "\(picked.label)（尝试 \(attemptsLog.joined(separator: "、"))）",
            language: (language ?? LocalizationManager.shared.language).rawValue,
            localizedStrings: (scope?.observed ?? []).sorted()
        )
        records.append(record)
        print("📷 \(name)  \(cgImage.width)×\(cgImage.height)px  \(data.count) B  内容占比 \(String(format: "%.3f", ratio))  [\(picked.label)]  \(record.language)  文案 \(record.localizedStrings.count) 条  → \(url.path)")
        return record
    }

    // MARK: - 两种语言各一遍（队列 L-13）

    /// 在**指定语言**的宿主语境里取一段文案（快照用例的判据用，队列 L-18）。
    ///
    /// 为什么需要它：判据要拿「这一句应该长什么样」去比渲染记录里的 `localizedStrings` ——
    /// 而 `L(...)` 在没有宿主语境时按**用户偏好**出文案（本机是中文，别的机器可能不是），
    /// 拿它当期望值会在其中一遍上错位。走 `beginHostLanguage` 之后取值，
    /// 期望值与那一遍渲染**同一条路**，于是「中文那遍比中文期望值 / 英文那遍比英文期望值」成立。
    @MainActor
    static func localizedText(_ language: AppLanguage, _ body: () -> String) -> String {
        _ = LocalizationManager.beginHostLanguage(language)
        defer { LocalizationManager.endHostLanguage() }
        return body()
    }

    /// 一组「同一张图 · 两种语言」的产物。
    struct LanguagePair {
        /// 不带语言后缀的原名称（语言后缀由 `writeBothLanguages` 加）。
        var base: String
        /// 顺序固定：`coverageLanguages` 的顺序（中文在前、英文在后）。
        var records: [Record]
        /// 两遍各自观测到的文案是否不同 —— 判据的另一半，见 `Scripts/check-ui-snapshot-languages.py`。
        var textsDiffer: Bool
    }

    /// 快照要覆盖的语言（顺序即产物与记录的顺序）。
    static let coverageLanguages: [AppLanguage] = [.simplifiedChinese, .english]

    static func languageSuffix(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "-zh"
        case .english: return "-en"
        }
    }

    /// 一张图在**两种语言**各拍一遍（队列 L-13）。产物名 = 原名称 + `-zh` / `-en`
    /// （原有的 `-dark` 之类留在原名里，于是深色那组就是 `xxx-dark-zh` / `-en`）。
    ///
    /// 为什么把两遍**绑在一次调用**里，而不是让每个用例各写两处：漏拍一边、或者两边名字不成对，
    /// 都**不会报错** —— 只会让"语言覆盖"悄悄缺一半，而图看起来照样正常（第 10/11 轮那两次
    /// 「判据太松」就是同一族）。绑在一起之后，配对是**构造出来的**，不靠自觉维护。
    ///
    /// 每遍都**重新构造**视图树（`@ViewBuilder` 闭包可重复调用）：两遍互不共享状态，
    /// 也不会把上一遍的排版带进下一遍。
    @MainActor
    @discardableResult
    static func writeBothLanguages<V: View>(
        _ name: String,
        size: CGSize,
        scheme: ColorScheme = .light,
        scale: CGFloat = 2,
        minimumContentRatio: Double = 0.002,
        @ViewBuilder content: () -> V
    ) throws -> LanguagePair {
        XCTAssertFalse(
            name.hasSuffix("-zh") || name.hasSuffix("-en"),
            "快照名不要自己带语言后缀（由 writeBothLanguages 统一加）：\(name)"
        )

        var records: [Record] = []
        for language in coverageLanguages {
            records.append(
                try write(
                    "\(name)\(languageSuffix(language))",
                    size: size,
                    scheme: scheme,
                    scale: scale,
                    minimumContentRatio: minimumContentRatio,
                    language: language
                ) {
                    content()
                }
            )
        }

        let textsDiffer = Set(records[0].localizedStrings) != Set(records[1].localizedStrings)
        print(
            "🔤 \(name)  两遍文案 \(textsDiffer ? "不同" : "相同")"
                + "（zh \(records[0].localizedStrings.count) 条 / en \(records[1].localizedStrings.count) 条）"
                + "  —— 文案不同就必须换来不同的像素，判定在 Scripts/check-ui-snapshot-languages.py"
        )
        return LanguagePair(base: name, records: records, textsDiffer: textsDiffer)
    }

    /// 路径一：`SwiftUI.ImageRenderer`（不需要 AppKit 宿主，但对滚动容器与 AppKit 子视图画不出内容）。
    @MainActor
    private static func imageRenderer<V: View>(_ view: V, size: CGSize, scale: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw SnapshotError.renderFailed("ImageRenderer") }
        return image
    }

    /// 路径一：**离屏窗口**里的 `NSHostingView`（本轮新增）。
    ///
    /// 为什么需要这一条（第 10 轮实测）：`List` / 侧栏这类 AppKit 自绘容器在**没有窗口**的
    /// 宿主里画不出内容（`cacheDisplay` 拿到的是整幅背景），于是退到 `ImageRenderer`，
    /// 而它给出的是 Apple 的"不可渲染"占位图 —— 一张黄底红圈的图。给宿主一个真实的
    /// `NSWindow`（**不** order、不显示）后 AppKit 才会真正 tile 这些控件。
    ///
    /// 窗口刻意不上屏：无人值守的机器上不该"闪一下"。这里只用它的布局与 backing store 通道。
    @MainActor
    private static func windowHostedImage<V: View>(
        _ view: V, size: CGSize, scale: CGFloat, scheme: ColorScheme
    ) throws -> CGImage {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
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

        let rep = try bitmap(size: size, scale: scale)
        hostDisplay(hosting, into: rep)
        return try cgImage(from: rep, label: "NSWindow+NSHostingView")
    }

    /// 路径二：`NSHostingView` 真实布局 + `cacheDisplay`（打印/导出同一条路）。
    /// 没有窗口的宿主：SwiftUI 那半边能画，AppKit 自绘容器画不出来（所以要配上路径一）。
    @MainActor
    private static func hostedImage<V: View>(_ view: V, size: CGSize, scale: CGFloat, scheme: ColorScheme) throws -> CGImage {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let rep = try bitmap(size: size, scale: scale)
        hostDisplay(hosting, into: rep)
        return try cgImage(from: rep, label: "NSHostingView")
    }

    /// 位图自己按 `scale` 建（`cacheDisplay` 会按 rep 的 `size` 换算），这样离屏也有 2× 图。
    private static func bitmap(size: CGSize, scale: CGFloat) throws -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { throw SnapshotError.renderFailed("位图分配失败") }
        rep.size = size
        return rep
    }

    private static func hostDisplay(_ hosting: NSView, into rep: NSBitmapImageRep) {
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
    }

    private static func cgImage(from rep: NSBitmapImageRep, label: String) throws -> CGImage {
        guard let image = rep.cgImage else { throw SnapshotError.renderFailed("\(label)（取不到位图）") }
        return image
    }

    /// Apple 那条「这个视图我画不出来」的占位图的配色（实测像素值）。
    ///
    /// 为什么必须单独识别它：这张图**相当密**（本机实测：黄 81.4% + 红 18.1%，内容占比 0.185），
    /// 「非空白」那道断言拦不住 —— 它比绝大多数真界面都"有内容"。第 10 轮实测就踩了这个坑：
    /// `List` 这类 AppKit 自绘容器在**无窗口**宿主里画不出内容，退到 `ImageRenderer` 后
    /// 拿回来的正是这张占位图，于是被当成有效证据落进清单。
    ///
    /// 判据写成颜色而不是"看起来像"：命中（黄占比 > 0.4 且红占比 > 0.03）就在**选路阶段**
    /// 淘汰该条路径。容差 8 用来抗色彩空间换算。
    static func placeholderShare(_ image: CGImage) -> (yellow: Double, red: Double)? {
        guard let buffer = rgbaBuffer(of: image) else { return nil }
        let yellow: (Int, Int, Int) = (255, 204, 0)
        let red: (Int, Int, Int) = (255, 56, 60)
        var yellowCount = 0
        var redCount = 0
        var total = 0
        for index in stride(from: 0, to: buffer.pixels.count, by: 4) {
            total += 1
            let r = Int(buffer.pixels[index])
            let g = Int(buffer.pixels[index + 1])
            let b = Int(buffer.pixels[index + 2])
            if abs(r - yellow.0) <= 8, abs(g - yellow.1) <= 8, abs(b - yellow.2) <= 8 {
                yellowCount += 1
            } else if abs(r - red.0) <= 8, abs(g - red.1) <= 8, abs(b - red.2) <= 8 {
                redCount += 1
            }
        }
        guard total > 0 else { return nil }
        let yellowShare = Double(yellowCount) / Double(total)
        let redShare = Double(redCount) / Double(total)
        guard yellowShare > 0.4, redShare > 0.03 else { return nil }
        return (yellowShare, redShare)
    }

    /// 非背景像素占比：把图重画进 8 位 RGBA 缓冲，逐点与"左上角像素"比较。
    ///
    /// 为什么用左上角当背景基准而不是取众数：界面快照的左上角在**所有**目标视图里
    /// 都是空白底色（面板内边距），这个前提比"众数是背景"更稳定 —— 结果表这种大面积
    /// 文字+网格的图，众数可能直接落在文字色上。
    private static func contentRatio(of image: CGImage) -> Double {
        guard let buffer = rgbaBuffer(of: image), buffer.width > 0, buffer.height > 0 else { return 0 }
        let pixels = buffer.pixels

        let baseline = (pixels[0], pixels[1], pixels[2], pixels[3])
        var differing = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            // 容差 6：抗锯齿与压缩噪点不该被算成"内容"。
            // **四个通道都要比**：原先只比 RGB 时，"透明底上的黑色文字"整幅被判成空白
            // （预乘 alpha 下透明像素与纯黑像素的 RGB 都是 0）—— 这正是本轮踩到的坑。
            if abs(Int(pixels[index]) - Int(baseline.0)) > 6
                || abs(Int(pixels[index + 1]) - Int(baseline.1)) > 6
                || abs(Int(pixels[index + 2]) - Int(baseline.2)) > 6
                || abs(Int(pixels[index + 3]) - Int(baseline.3)) > 6 {
                differing += 1
            }
        }
        return Double(differing) / Double(buffer.width * buffer.height)
    }

    /// 把 `CGImage` 重画进 8 位 RGBA 缓冲，供逐点分析（内容占比 / 占位图识别共用）。
    private static func rgbaBuffer(of image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
            guard let base = raw.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (buffer, width, height)
    }

    /// 类级收尾：整组用例跑完再写清单。
    ///
    /// 为什么要一个共用入口：清单里的 `records` 是**跨用例、跨测试类**累积的静态数组，
    /// 而"谁最后跑完"由 XCTest 决定。于是每个测试类都在类级收尾里调这里 ——
    /// 后跑的那一类写出来的就是**全量**清单（先跑的那一类写的会被后一个覆盖，但内容更全）。
    static func finishManifestIfEnabled() {
        guard isEnabled, !records.isEmpty else { return }
        do {
            if let url = try writeManifest(extra: ["snapshotCount": String(records.count)]) {
                print("🧾 清单：\(url.path)（\(records.count) 张）")
            }
        } catch {
            print("⚠️ 清单写入失败：\(error)")
        }
    }

    /// 把本轮清单写成 `manifest.json`：谁在什么时候渲染了什么、多大、内容占比多少。
    /// 不写空清单覆盖上一轮产物（`records` 为空时说明这一轮什么都没渲染）。
    static func writeManifest(extra: [String: String] = [:]) throws -> URL? {
        guard !records.isEmpty else { return nil }
        let directory = outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("manifest.json", isDirectory: false)

        var payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "snapshots": records.map { record -> [String: Any] in
                [
                    "name": record.name,
                    "file": record.file,
                    "width": record.width,
                    "height": record.height,
                    "scale": record.scale,
                    "scheme": record.scheme,
                    "bytes": record.bytes,
                    "contentRatio": record.contentRatio,
                    "renderer": record.renderer,
                    "language": record.language,
                    "localizedStrings": record.localizedStrings
                ]
            }
        ]
        for (key, value) in extra { payload[key] = value }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 像素取色（队列 L-85：令牌必须到像素上）

    /// 取一张**已落盘**的 PNG 上某一点的像素（sRGB，0~255 三通道）。
    ///
    /// 为什么要有这个口子：`Scripts/check-ui-snapshot-languages.py` 已经能机械判「**语言**有没有到像素上」
    /// （比两张 PNG 的哈希），而「**令牌**有没有到像素上」此前只能靠人读图。两轴（深浅 × 配色）
    /// 组合起来是 6 张图，人读得过来、但不该靠人读。
    ///
    /// **容差不是猜的**（实测，第 83 轮）：这张图从 `CGImage` → `NSBitmapImageRep` → PNG → 读回，
    /// 通道值会偏移最多 4 —— 实测深色 `window #02070A` 读回 `#02060A`（G −1）、
    /// 浅色 `window #F1F5FA` 读回 `#F4F7FB`（+3 / +2 / +1）。所以调用方比对时容差取 8：
    /// 既容得下这条往返，又小于「换一个主题」在这套值上的差异（深色 `window` 三主题实测
    /// #02060A / #03160A / #1A070B，至少有一个通道差 16 以上 ⇒ 拿错主题当场红）。
    static func sampledRGB(ofPNGAt path: String, at point: CGPoint) -> (red: Int, green: Int, blue: Int)? {
        guard let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let x = min(max(Int(point.x.rounded()), 0), rep.pixelsWide - 1)
        let y = min(max(Int(point.y.rounded()), 0), rep.pixelsHigh - 1)
        guard let raw = rep.colorAt(x: x, y: y) else { return nil }
        let color = raw.usingColorSpace(.sRGB) ?? raw
        return (
            red: Int((color.redComponent * 255).rounded()),
            green: Int((color.greenComponent * 255).rounded()),
            blue: Int((color.blueComponent * 255).rounded())
        )
    }

    /// 把 0xRRGGBB 拆成三通道（与 `sampledRGB` 的形态对齐，供断言直接比）。
    static func channels(of hex: UInt32) -> (red: Int, green: Int, blue: Int) {
        (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
    }

    // MARK: - 取样带（队列 L-89 ㈡：字形有没有跟着字体变）

    /// 一张**已落盘** PNG 上「距图底 N 像素起、高 H 像素」的横向条带（RGBA，8 位/通道）。
    ///
    /// 为什么要有这个口子：「预览的字形跟着字体走」（清单 `FR-EDIT-26` ⑤）此前只能靠人看一眼图 ——
    /// 而面板里**能吃的字体不止预览一处**（终端预览同样吃它），所以判据不能只比「两张图不一样」，
    /// 得比**一个受控的条带**：这条带在换字体时该变、在上方文案增减时不该变（两个方向都由对照用例判）。
    struct Band {
        var width: Int
        var height: Int
        var bytes: [UInt8]
        /// **背景色参照**（带内出现最多的那个像素值）：一条带上的颜色只有几种（框底色 / 字色 / 边框），
        /// 众数就是底色。
        var background: (UInt8, UInt8, UInt8, UInt8)
        /// 与**底色**差 > 6 的像素数 —— 「这一带真的画了东西」的最小证据。
        /// 为什么不用「左上角像素」当参照（`contentRatio` 那条路）：那一条的前提是**画的左上角一定是留白**，
        /// 而取样带正落在文本框内部、左上角可能就是字（本轮实测：拿首像素当参照会数出 94% 的「墨迹」）。
        var ink: Int

        var pixelCount: Int { width * height }
    }

    /// 一张**已落盘** PNG 上「距图顶 N 像素、高 H 像素」的横向条带。
    ///
    /// 与 `band(fromBottom:)` 同族，但**从上边量**：那条给"贴着面板底部"的元素用，
    /// 这条给"贴着顶部"的工具条那一行用（下方面板的工具条就在图的顶部）。
    /// 为什么非要一个"从上量"的口子：`NSBitmapImageRep` 的行序自上而下，从底量再换算回来，
    /// 判据里就会到处出现 `总高 − 底 − 高` 这种算式 —— 算式写错一次就会静默判错地方。
    static func topBand(ofPNGAt path: String, fromTop: Int = 0, height: Int) -> Band? {
        guard let size = pixelSize(ofPNGAt: path) else { return nil }
        return region(ofPNGAt: path, leading: 0, top: fromTop, width: size.width, height: height)
    }

    /// 一张**已落盘** PNG 上「距左边 N 像素、宽 W 像素」的竖直列带。
    ///
    /// 为什么要按列切：「页签头在**左侧**、右侧那排按钮**位置不动**」是**版面**判据 ——
    /// 页签从 1 个变 3 个时，左半边必须变、右半边必须逐像素不变。只比整张图"有没有变"
    /// 判不出"变在哪一侧"（页签头挂到右边同样会让整张图变）。
    static func columnBand(ofPNGAt path: String, fromLeading: Int, width: Int) -> Band? {
        guard let size = pixelSize(ofPNGAt: path) else { return nil }
        return region(ofPNGAt: path, leading: fromLeading, top: 0, width: width, height: size.height)
    }

    /// 一张已落盘 PNG 的像素尺寸（给上面两个"按边切"的口子算另一边有多长）。
    static func pixelSize(ofPNGAt path: String) -> (width: Int, height: Int)? {
        guard let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// 「距图底 N 像素、高 H 像素」的横向条带（`FR-EDIT-26` ⑤ 那条判据用的口子）——
    /// 现在只是 `region` 的一个薄包装。
    static func band(ofPNGAt path: String, fromBottom: Int, height: Int) -> Band? {
        guard let size = pixelSize(ofPNGAt: path) else { return nil }
        return region(
            ofPNGAt: path,
            leading: 0,
            top: size.height - (fromBottom + height),
            width: size.width,
            height: height
        )
    }

    /// 从一张已落盘 PNG 上取一块矩形（**像素坐标、左上为原点、自上而下**）。
    ///
    /// 三个口子（`band` / `topBand` / `columnBand`）共用这一套裁剪与统计：免得"带"的定义
    /// （怎么裁、底色怎么定、墨迹怎么算）各写一遍 —— 那是第二份真相的开头（第 64 / 83 轮的旧账）。
    /// 越界的部分按边界夹取；裁出来是空的 ⇒ `nil`（不是"零差异"）。
    static func region(ofPNGAt path: String, leading: Int, top: Int, width: Int, height: Int) -> Band? {
        guard let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.bitmapData else { return nil }
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh
        let bytesPerPixel = max(1, rep.bitsPerPixel / 8)
        let rowBytes = rep.bytesPerRow

        // `NSBitmapImageRep` 的行序是**自上而下**（与 `sampledRGB` 的 `colorAt` 同一套坐标），
        // 所以 `top` 直接就是行号。
        let startY = min(max(top, 0), pixelHeight)
        let endY = min(max(startY + height, 0), pixelHeight)
        let startX = min(max(leading, 0), pixelWidth)
        let endX = min(max(startX + width, 0), pixelWidth)
        guard pixelWidth > 0, endY > startY, endX > startX else { return nil }

        let width = endX - startX
        var bytes = [UInt8](repeating: 0, count: width * (endY - startY) * 4)
        for (row, y) in (startY..<endY).enumerated() {
            for (column, x) in (startX..<endX).enumerated() {
                let source = y * rowBytes + x * bytesPerPixel
                let destination = (row * width + column) * 4
                bytes[destination] = data[source]
                bytes[destination + 1] = bytesPerPixel > 1 ? data[source + 1] : data[source]
                bytes[destination + 2] = bytesPerPixel > 2 ? data[source + 2] : data[source]
                bytes[destination + 3] = bytesPerPixel > 3 ? data[source + 3] : 255
            }
        }

        var counts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) {
            counts[key(bytes, index), default: 0] += 1
        }
        let dominant = counts.max { $0.value < $1.value }?.key ?? 0
        let background = (
            UInt8((dominant >> 24) & 0xFF),
            UInt8((dominant >> 16) & 0xFF),
            UInt8((dominant >> 8) & 0xFF),
            UInt8(dominant & 0xFF)
        )
        var ink = 0
        for index in stride(from: 0, to: bytes.count, by: 4) where isDifferent(bytes, index, to: background) {
            ink += 1
        }
        return Band(width: width, height: endY - startY, bytes: bytes, background: background, ink: ink)
    }

    private static func key(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        (UInt32(bytes[index]) << 24) | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8) | UInt32(bytes[index + 3])
    }

    /// 两条带的**差异像素数**（任一通道差 > 6 即算差异）。尺寸不一致 ⇒ `nil`（不是「相同」）。
    static func differingPixels(_ lhs: Band, _ rhs: Band) -> Int? {
        guard lhs.width == rhs.width, lhs.height == rhs.height, lhs.bytes.count == rhs.bytes.count else {
            return nil
        }
        var count = 0
        for index in stride(from: 0, to: lhs.bytes.count, by: 4) where isDifferent(lhs.bytes, index, other: rhs.bytes) {
            count += 1
        }
        return count
    }

    private static func isDifferent(
        _ bytes: [UInt8], _ index: Int, to reference: (UInt8, UInt8, UInt8, UInt8)
    ) -> Bool {
        abs(Int(bytes[index]) - Int(reference.0)) > 6
            || abs(Int(bytes[index + 1]) - Int(reference.1)) > 6
            || abs(Int(bytes[index + 2]) - Int(reference.2)) > 6
            || abs(Int(bytes[index + 3]) - Int(reference.3)) > 6
    }

    private static func isDifferent(_ lhs: [UInt8], _ index: Int, other rhs: [UInt8]) -> Bool {
        for channel in 0..<4 where abs(Int(lhs[index + channel]) - Int(rhs[index + channel])) > 6 {
            return true
        }
        return false
    }

    // MARK: - 许可证（三档呈现要用真签名，不能"假装备注"）

    /// 临时密钥对（每次运行现生成，不落仓库）。
    struct TierKeys { var privateKey: Data; var publicKey: Data }

    static let tierKeys = LicenseIssuing.makeKeyPair()

    static var licenseDirectory: URL {
        outputDirectory.deletingLastPathComponent().appendingPathComponent("ui-snapshot-licenses", isDirectory: true)
    }

    /// 签一份指定档位的临时许可证，**用环境变量把 AppState 指过去**，然后让它自己重读。
    ///
    /// 走的是产品里真实存在的两条路（`DOYAH_LICENSE_PATH` / `DOYAH_LICENSE_PUBLIC_KEY`）与真实的
    /// `reloadLicense()`（用户放好许可证、不重启就生效的那个动作）—— 不是测试专用的后门。
    @MainActor
    @discardableResult
    static func applyLicense(_ edition: LicenseEdition, to state: AppState) throws -> LicenseLoader.LoadResult {
        let license = License(
            issuedTo: "ui-snapshot",
            capabilities: edition.capabilities,
            maxDevices: License.defaultMaxDevices,
            expiresAt: nil,
            devices: [LicenseDevice(name: "snapshot-runner")]
        )
        let file = try LicenseIssuing.sign(license, privateKey: tierKeys.privateKey)
        let url = licenseDirectory.appendingPathComponent("snapshot-\(edition.rawValue).doyahlicense", isDirectory: false)
        try FileManager.default.createDirectory(at: licenseDirectory, withIntermediateDirectories: true)
        try file.encoded().write(to: url, atomically: true, encoding: .utf8)

        setenv(LicenseLoader.licensePathEnvironmentKey, url.path, 1)
        setenv("DOYAH_LICENSE_PUBLIC_KEY", tierKeys.publicKey.base64EncodedString(), 1)
        state.reloadLicense()
        return state.licenseLoad
    }

    /// 清掉这一轮的临时许可指向（不给后续用例留脏环境）。
    @MainActor
    static func clearLicense(from state: AppState) {
        unsetenv(LicenseLoader.licensePathEnvironmentKey)
        unsetenv("DOYAH_LICENSE_PUBLIC_KEY")
        state.reloadLicense()
    }

    // MARK: - 活宿主（同一份视图实例上：等状态 / 点控件 / 反复取图）

    /// 一份**活着的**离屏宿主：视图实例一直不销毁，于是可以在它身上
    /// ① 泵运行循环等异步加载落地、② 真点一下控件、③ 反复取图对比**切换前后**。
    ///
    /// ## 为什么 `write` / `writeBothLanguages` 够不着
    ///
    /// 那两个入口**每张图都重建视图树**（`@ViewBuilder` 闭包重新求值）—— 判「在同一个界面上
    /// 点一下开关之后，原来选中的那一项还在不在」这类**跨时刻**的事时，"重建"这个动作本身
    /// 就把被测的那件事抹掉了（重建的视图是一份全新的 `@State`）。队列 `L-89` ㈡ 第 6 条
    /// （分组视图那一行的人话：「两种视图都能用；**切换后选中项不丢**」）正需要同一实例上的前后两态。
    ///
    /// ## 口径与 `write` 完全一致
    ///
    /// 渲染与落盘走的是同一套私有路径（`bitmap` / `hostDisplay` / PNG 编码 / `Record`），
    /// 所以「非空白」判据、记录字段、清单写入口径都一样；窗口同样**不上屏**
    /// （无人值守的机器上不该闪一下）。语言仍由**宿主语境**决定（调用方 `beginHostLanguage` 包住），
    /// 观测到的文案由调用方从 `HostScope.observed` 传进来 —— 与 `write` 的取法同源。
    @MainActor
    final class LiveHost<V: View> {

        let window: NSWindow
        let hosting: NSHostingView<V>
        private let size: CGSize

        init(_ rootView: V, size: CGSize, scheme: ColorScheme = .light) {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            self.size = size
            hosting = NSHostingView(rootView: rootView)
            hosting.appearance = appearance
            hosting.frame = CGRect(origin: .zero, size: size)

            window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            settle()
        }

        /// 重排 + 重绘一次（泵循环里反复调它）。
        func settle() {
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }

        /// 泵运行循环直到 `condition` 成立或超时；返回是否成立。
        ///
        /// **异步加载必须等**（拉取元数据要走几趟数据库往返）：不等就取图，判的是
        /// 「这台机器今天快不快」，而不是界面。（与第 99 轮那条「`断开` 是发出去就不管的异步 ⇒
        /// 断言必须限时轮询」同一个教训。）
        @discardableResult
        func pump(until condition: () -> Bool, timeout: TimeInterval = 20, interval: TimeInterval = 0.05) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                settle()
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
            settle()
            return condition()
        }

        /// 泵固定时长（没有可判条件时用，例如「点完开关之后让渲染发生」）。
        func pump(_ seconds: TimeInterval = 0.5) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                settle()
            }
        }

        /// 这一次渲染的**内容指纹**（PNG 字节的 SHA256）。
        ///
        /// 用途：判「两档是不是真的画成了两个样子」时，不必落两份盘再比像素 —— 比指纹更快。
        func signature() throws -> String {
            settle()
            let rep = try UISnapshot.bitmap(size: size, scale: 2)
            UISnapshot.hostDisplay(hosting, into: rep)
            let image = try UISnapshot.cgImage(from: rep, label: "LiveHost.signature")
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw SnapshotError.encodeFailed("LiveHost.signature")
            }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        /// 宿主视图树里的第一个 `NSSegmentedControl`。
        ///
        /// SwiftUI 的 `.pickerStyle(.segmented)` 在 macOS 上落到 `NSSegmentedControl`
        /// 的子类（`SwiftUISegmentedControl`，实测 2026-09-29 / macOS 27）——于是
        /// 「点一下这个开关」在**同进程内**做得到：`selectedSegment` + `sendAction` 就是真点击，
        /// **不需要辅助功能授权**（合成事件只有跨进程才要授权）。
        var firstSegmentedControl: NSSegmentedControl? {
            Self.findSegmentedControl(in: hosting)
        }

        static func findSegmentedControl(in view: NSView) -> NSSegmentedControl? {
            for subview in view.subviews {
                if let control = subview as? NSSegmentedControl { return control }
                if let found = findSegmentedControl(in: subview) { return found }
            }
            return nil
        }

        /// 宿主视图树里**所有**的弹窗按钮。
        ///
        /// SwiftUI 的 `Picker`（默认 `.menu` 档）在 macOS 上落到 `NSPopUpButton`（实测 2026-09-29 /
        /// macOS 27）。为什么一次拿全部而不是「取第一个」：一个面板上常有好几台同形状的 `Picker`
        /// （`EgressLogSheet` 就有三台：类别 / 结果 / **页签**）——「页签那一台在不在、可不可点、
        /// 里面有没有那个页签」得先按**条目文案**把它们挑出来；取第一个只会在顺序变化时判错东西。
        /// 读的是控件的 `itemTitles` / `isEnabled`，即**界面上的事实**，不是模型里的推断。
        var popUpButtons: [NSPopUpButton] {
            Self.findViews(ofType: NSPopUpButton.self, in: hosting)
        }

        /// 宿主视图树里**所有**的文本输入控件（地址栏那种）。
        var textFields: [NSTextField] {
            Self.findViews(ofType: NSTextField.self, in: hosting)
        }

        static func findViews<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
            var found: [T] = []
            if let match = view as? T { found.append(match) }
            for subview in view.subviews {
                found.append(contentsOf: findViews(ofType: type, in: subview))
            }
            return found
        }

        /// 取一张图、落盘、把记录写进清单（口径与 `write` 相同）。
        @MainActor
        @discardableResult
        func capture(
            name: String,
            scale: CGFloat = 2,
            language: AppLanguage? = nil,
            observed: Set<String> = []
        ) throws -> Record {
            settle()
            let rep = try UISnapshot.bitmap(size: size, scale: scale)
            UISnapshot.hostDisplay(hosting, into: rep)
            let image = try UISnapshot.cgImage(from: rep, label: "LiveHost")
            if let share = UISnapshot.placeholderShare(image) {
                throw SnapshotError.blank(
                    name,
                    "LiveHost=不可渲染占位图（黄 \(String(format: "%.2f", share.yellow))/红 \(String(format: "%.2f", share.red))）"
                )
            }
            let ratio = UISnapshot.contentRatio(of: image)
            guard ratio >= 0.002 else {
                throw SnapshotError.blank(name, "LiveHost=\(String(format: "%.3f", ratio))")
            }
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw SnapshotError.encodeFailed(name)
            }
            let directory = UISnapshot.outputDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).png", isDirectory: false)
            try data.write(to: url, options: .atomic)

            let record = Record(
                name: name,
                file: url.path,
                width: image.width,
                height: image.height,
                scale: Double(scale),
                scheme: "light",
                bytes: data.count,
                contentRatio: ratio,
                renderer: "LiveHost（同一实例）",
                language: (language ?? LocalizationManager.shared.language).rawValue,
                localizedStrings: observed.sorted()
            )
            UISnapshot.records.append(record)
            print("📷 \(name)  \(image.width)×\(image.height)px  \(data.count) B  内容占比 \(String(format: "%.3f", ratio))  [LiveHost]  \(record.language)  文案 \(record.localizedStrings.count) 条  → \(url.path)")
            return record
        }
    }
}

// MARK: - 视图宿主

extension View {
    /// 按 `DoyahStudioApp.swift` 根部的注入顺序补上环境对象。
    ///
    /// 只有 genuinely 需要的对象会被真正读到；但**一次性把根视图那套注入全给上**，
    /// 是因为少了任何一个都会在渲染时崩（SwiftUI 对缺失的 `@EnvironmentObject` 直接 fatalError），
    /// 而"这次要哪几个"会随视图演进而变 —— 让宿主跟着根视图走，比逐张图猜依赖稳。
    @MainActor
    func snapshotEnvironment(
        state: AppState,
        workspace: WorkspaceStore,
        tabs: WorkspaceTabsModel,
        accent: AccentManager = .shared,
        localization: LocalizationManager = .shared,
        terminal: TerminalModel
    ) -> some View {
        environmentObject(state)
            .environmentObject(workspace)
            .environmentObject(tabs)
            .environmentObject(accent)
            .environmentObject(localization)
            .environmentObject(terminal)
    }
}
