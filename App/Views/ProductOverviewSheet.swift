import AppKit
import DoyahCore
import SwiftUI

/// 产品功能介绍（`FR-STD-WS-HELP-003`）。
///
/// **为什么单独有这一页**：主人 2026-11-04 当面指出 —— Notes 的「关于」写了功能描述、Tuner 也有，
/// Studio 这两处（系统关于面板 / 帮助菜单）**只印了名字与版本**，用户打开后仍然不知道这软件能干什么。
/// 这一页就是补这件事：一份**按模块分组、逐条与菜单对应**的能力清单。
///
/// 内容只有两个来源，都走 `LKey`，中英各一整段：
///   · `.productOverviewBody` —— 正文（`## 分组` + `· 条目` 两种行前缀，本视图按前缀排版）
///   · `.productOverviewTitle` / `.productOverviewSubtitle` —— 抬头与一句说明
/// 故意不把每一条都拆成独立键：这是一份**说明书**，不是界面控件文案；拆成几十个键以后
/// 中英两侧一定会各改一半（历史上「英文行夹汉字」就是这么来的）。
struct ProductOverviewSheet: View {

    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 660, height: 620)
    }

    // MARK: - 抬头

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L(.productOverviewTitle))
                    .font(.title2.weight(.semibold))
                Text(L(.productOverviewSubtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("product-overview-version")
            }
        }
        .padding(Spacing.l)
    }

    private var footer: some View {
        HStack {
            Spacer()
            DialogActionButton(systemName: "xmark", title: L(.commonClose), role: .cancel) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.m)
    }

    // MARK: - 正文解析

    /// 正文按行切成「分组（`## `）/ 条目（`· `）/ 普通行」三种块。
    /// 前缀就是格式约定，写文档的人不用懂 SwiftUI。
    private enum Block {
        case section(String)
        case bullet(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        L(.productOverviewBody)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> Block in
                let s = String(line)
                if s.hasPrefix("## ") { return .section(String(s.dropFirst(3))) }
                if s.hasPrefix("· ") { return .bullet(String(s.dropFirst(2))) }
                return .paragraph(s)
            }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .section(let title):
            Text(title)
                .font(.headline)
                .padding(.top, Spacing.s)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("·").foregroundStyle(.secondary)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)
        case .paragraph(let text):
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
