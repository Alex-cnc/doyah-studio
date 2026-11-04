import AVKit
import SwiftUI

// `FR-R-13-09` 视频① —— **本地文件内联播放**（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-09`：
//   > **视频** = **① 本地文件内联播放**（白名单 `mp4` / H.264 + AAC，见 `IR-05` 不变量 5）
//   > + **② 外链点击打开**（浏览器 / 系统播放器，**视图内不嵌 iframe**）
//
// 本视图只承担 ①：**包内 `mp4`** 拿 `AVPlayer` 内联播（`VideoPlayer`）。判定「这是不是白名单视频」
// **不在这里** —— 由领域层 `MediaResolve` 定（R-03：扩展名白名单 / 越界 / 缺失同一套口径），
// 本视图只接受一个**已经判定过**的包内绝对路径。
// ②（外链）**不在本视图**：走 `ExternalLinkButton`（交系统默认处理，本目录不嵌 iframe / WebView）。
//
// **如实登记**：本层只保证「把这一个本地 `mp4` 交给系统播放器内联播」；**编码级**白名单
// （H.264 + AAC 是不是真在里面）由播放器解码时才知道，本片**不声称**已校验编码
// （与 R-03 `MediaPolicy.swift` 文件头同一条登记）。文件读不出时由系统播放器出错误画面 ——
// 本视图不崩、不做额外接管。

/// 本地文件内联播放器（白名单 `mp4`）。
public struct VideoPlayerView: View {
    /// 包内**绝对路径**（由 `MediaResolve.inlineVideo` 给出）。
    public let url: URL
    /// 图注（`report.md` 里 `![alt](…)` 的 alt；可空）。
    public let caption: String

    public init(url: URL, caption: String = "") {
        self.url = url
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(minWidth: 320, minHeight: 180)
            HStack(spacing: 8) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                }
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
