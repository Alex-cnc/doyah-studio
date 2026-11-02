import SwiftUI
import AppKit
import DoyahCore

/// 图片页的**自己的视图**（`FR-STD-WS-FS-008` ①「图片等按各自视图」）。
///
/// 由头：这一档原来根本不存在 —— 双击一张 `.png` 走的是「当文本打开」那条路，
/// 字节里几乎必然有 0x00 ⇒ 被判成「二进制文件」，于是用户点自己刚截的图得到一句
/// 「看起来是二进制文件」。需求 ① 要的是**按类别匹配呈现**：文本 / 代码进编辑器，
/// 图片进图片视图。
///
/// 这一层只做三件事：把图显示出来（等比缩到可用区域，不放大到糊）、把读数说出来
/// （像素尺寸 / 文件大小 / 帧数）、显示不出来时**说清是显示不出来**（不白屏）。
/// 「能不能显示」在打开那一刻已经判过一次（`WorkspaceTabsModel.openAsImage`）——
/// 这里再判一次是因为盘上的文件可能在打开之后被删 / 被换掉。
struct WorkspaceImageView: View {

    let path: String

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            caption
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = NSImage(contentsOfFile: path) {
            // 等比缩放：小图**不放大**（放大只会更糊），大图缩到装得下。
            // `ScrollView` 只在真的超出时才滚 —— 小图居中没有滚动条。
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Spacing.l)
            }
        } else {
            // 打开之后被删 / 被换成别的东西：如实说，不给一片白。
            Text(L(.workspaceImageUnreadable, (path as NSString).lastPathComponent))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .multilineTextAlignment(.center)
                .padding(Spacing.l)
        }
    }

    /// 底部读数条：`1920 × 1080 · 1.2 MB`（多帧时加一句帧数）。
    ///
    /// 为什么这些数要显示：图片页没有编辑器、没有状态栏（编码 / 换行 / 缩进都跟它无关），
    /// 用户能确认「看到的是不是原图、文件有多大」的唯一地方就是这一行。
    private var caption: some View {
        HStack(spacing: Spacing.s) {
            Text((path as NSString).lastPathComponent)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            if let info = WorkspaceImageInfo.read(path: path) {
                Text(info.frameCount > 1
                     ? "\(info.pixelText) · \(info.sizeText) · \(info.frameCount) frames"
                     : "\(info.pixelText) · \(info.sizeText)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
    }
}
