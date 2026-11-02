import Foundation
import ImageIO

/// 一张图片的**读数**（`FR-STD-WS-FS-008` ①：「图片等按各自视图」）。
///
/// 为什么读数单独一层：图片页要说的三件事 —— 这张图能不能显示（能不能解出尺寸）、
/// 多大像素、文件本身多大 —— 都不该由视图在 `body` 里现算（SwiftUI 一次更新里 `body`
/// 会被调用多次，每帧解一次图元数据在白算）。同时「能不能显示」这条**要在打开那一刻就判**：
/// 打不开的图片不该先给一个空页签再让用户盯着白屏。
///
/// 用 ImageIO 而不是 `NSImage(contentsOf:)`：后者是**懒解码**（初始化成功不代表像素读得出来），
/// 而这里要的正是「元数据读得出来」这一条硬事实 —— 它也是打开时的拒绝依据。
struct WorkspaceImageInfo: Equatable {

    /// 像素宽（第 0 帧）。
    let pixelWidth: Int
    /// 像素高（第 0 帧）。
    let pixelHeight: Int
    /// 文件字节数。
    let byteCount: Int64
    /// 帧数（GIF / HEIC 动画）；静态图 = 1。
    let frameCount: Int

    /// 读一张图的读数。**读不出来就返回 `nil`**（不是返回一堆 0 假装读到了）。
    static func read(path: String) -> WorkspaceImageInfo? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return WorkspaceImageInfo(
            pixelWidth: width,
            pixelHeight: height,
            byteCount: size,
            frameCount: CGImageSourceGetCount(source)
        )
    }

    /// `1200 × 800`（ASCII 乘号：两语界面都这么写，不用翻译）。
    var pixelText: String { "\(pixelWidth) × \(pixelHeight)" }

    /// `240 KB`（按文件的量法，与 Finder 一致）。
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
