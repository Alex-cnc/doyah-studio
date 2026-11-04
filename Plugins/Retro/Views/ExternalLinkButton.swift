import SwiftUI

// `FR-R-13-09` 视频② —— **外链点击打开**（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-09`：
//   > **② 外链点击打开**（浏览器 / 系统播放器，**视图内不嵌 iframe**）
// 判据 ②：外链 ⇒ **点击打开系统默认处理**（不留白、不崩）。
//
// 口径（三条，别越界）：
//   · 打开动作走 SwiftUI 的 `openURL` 环境动作 ⇒ **交给系统默认程序**（浏览器 / 系统播放器）；
//   · **本仓不嵌 iframe / WebView** —— 本目录（乃至本目标）**没有 WebKit 依赖**，代码里没有内嵌
//     浏览器的分支（`FR-R-13-09` 视频② 的硬口径）；
//   · 「这是不是一条合法外链」**不在这里判** —— 由领域层 `MediaResolve` 定
//     （`http` / `https` 两 scheme 才算外链，其余 scheme 归「拒绝 + 占位」）。
//
// **只读**：本视图不碰盘、不写任何文件。

/// 外链按钮：点击 ⇒ 交系统默认处理。
public struct ExternalLinkButton: View {
    public let url: URL
    /// 按钮文案（空 ⇒ 用 URL 原文）。
    public let title: String

    @Environment(\.openURL) private var openURL

    public init(url: URL, title: String = "") {
        self.url = url
        self.title = title
    }

    public var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(title.isEmpty ? url.absoluteString : title, systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.link)
        .help(url.absoluteString)
    }
}
