import AppKit
import DoyahCore
import SwiftUI

/// **产品形象**：应用图标本体（`NSApp.applicationIconImage`）。
///
/// 为什么取运行时图标而不是再塞一份图片资源：`AppIcon` 只有一处出处（打包脚本写进
/// `Contents/Resources/AppIcon.icns` 并在 `Info.plist` 登记），这里取同一份就不会出现
/// 「首页图标换了、Dock 没换」那种两份真相。换图标只改一处。
///
/// 用途：工作区首页品牌段、Agent 对话欢迎页的抬头。
struct BrandMark: View {
    var size: CGFloat = 28
    /// 是否带圆角描边（浅壁纸上用；深色背景可关）。
    var bordered: Bool = false

    var body: some View {
        Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: Metrics.hairline)
                }
            }
            .accessibilityHidden(true)
    }
}

/// `NSApp` 在 SwiftUI 预览/单测里可能为空，这里给个安全取值。
private let NSApp: NSApplication? = NSApplication.shared
