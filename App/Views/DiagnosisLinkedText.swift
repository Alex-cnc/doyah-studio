import DoyahCore
import SwiftUI

/// 结论里带**可点对象名**的一段话（`FR-STD-DB-DIAG-006` 判据 ②：结论里的对象名可点击跳到对应节点）。
///
/// 为什么用 `AttributedString` + `OpenURLAction` 而不是把句子切成 `HStack` 里的 `Text` + `Button`：
/// 后者不肯换行 —— 一句长结论会被挤成一行然后截断，用户读到的是半句话。
/// `Text` + 链接属性由 AppKit 自己排版（换行、连字、双向文本都归它），
/// 「点一下去哪儿」由**这一层**决定（`OpenURLAction` 截住，绝不交给系统浏览器）。
///
/// 切段是 Core 的纯函数（`DiagnosisObjectLinker`），这里只负责渲染与派发：
/// 判据与产品读的是同一份切段结果，不存在「判的是另一套匹配规则」。
struct DiagnosisLinkedText: View {

    let text: String
    let targets: [DiagnosisObjectLinker.Target]
    let onOpen: (DiagnosisObjectLinker.Target) -> Void

    var body: some View {
        Text(attributed)
            .font(Theme.font(.body))
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard let target = DiagnosisObjectLinker.Target(url: url) else {
                    // 不是我们的对象链接：什么都不做（也不弹浏览器）。
                    return .discarded
                }
                onOpen(target)
                return .handled
            })
    }

    private var attributed: AttributedString {
        DiagnosisObjectLinker.attributed(text, targets: targets)
    }
}
