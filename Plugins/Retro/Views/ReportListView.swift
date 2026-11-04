import Combine
import Foundation
import SwiftUI

import DoyahRetroCore

// `FR-R-13-08` 左侧**周报卡片列表**（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-08`（SRS v1.10）：
//   > **左侧 = 周报卡片式列表**（每期一张卡：期号 / 日期范围 / 标题 / 标签 / 封面缩略图 / 生成时间）；
//   > **右侧 = 主工作区**（富文本正文渲染 ……）；**M0 = 只读**（不做编辑器）
//   > 判据 ④：空包 / 缺件 / 编码错 ⇒ **逐条报告且不崩**（与 `FR-R-12-04` ③ 同口径）。
//
// 本文件 = 左列表这一半，**只做三件事**：
//   ① 把「扫描根」映射成一个可渲染的确定状态（`ReportListState`）—— 扫描根不可用 / 空目录 ⇒
//      **空态**，坏包逐条并列在列表尾部；任何失败都落成状态值，**不抛、不崩**（判据 ④）。
//   ② 每期一张卡（期号 / 日期 / 标题 / 摘要 / 媒体件数 / 有封面则缩略图）。
//   ③ 坏目录逐条一行报告（`ReportPackageIssue.description`，与 R-01 同口径）。
//
// **只读**（判据 ③「视图内不产生任何写回包的动作」）：本层只调 `ReportPackageScanner.scan`
// （领域层的只读扫描），全层不出现任何对包目录的写动作 —— 机械判据 = `Tools/check-readonly.py`。
//
// 本层是**视图壳**：`import SwiftUI`（GUI 框架只许出现在这一层；领域层 `DoyahRetroCore` 零 GUI 符号）。

// MARK: - `App` 固定扫描目录（`IR-05` §6.5「导入面」的机械落点）

/// 阅读器（`App`）扫的那个**固定目录** —— 契约出处 = `Docs/需求规范书.md` §6.5 `IR-05`「导入面」：
///   > Retro 扫一个**固定目录**的**直接子目录**，凡含 `index.json` 且 `report.md` 存在的即视为一个周报包。
///
/// **本目录路径在 `Plugins/Retro` 下的唯一字面量就在下面这一行**（机械判据：在 `Plugins/Retro/Sources`
/// 下 grep 本路径 ⇒ **命中 1**）。视图层 / 命令入口 / 将来任何调用方一律从 `fixedScanRootPath` 取，
/// **不各自再写一份盘上路径** —— 免得「盘上一种、代码里一种」。
///
/// **为什么落在视图层**：这是**阅读器（`App`）的固定落点**（配置），不是领域逻辑 —— `DoyahRetroCore`
/// 保持「扫描根由调用方给」的纯接口（`ReportPackageScanner.scan(rootDirectory:)`），**不把某台机器的
/// 绝对路径写进领域层**。前门（生成侧）按本路径投放后续各期包。
public enum ReportReader {
    /// 本机固定扫描目录；其**直接子目录**即各期周报包（`index.json` + `report.md`）。
    public static let fixedScanRootPath = "/Users/alex/.dsh/notes/geopolitics-weekly/packages"

    /// `fixedScanRootPath` 的 `URL` 形态（目录）。
    public static var fixedScanRootURL: URL {
        URL(fileURLWithPath: fixedScanRootPath, isDirectory: true)
    }
}

// MARK: - 列表状态（视图层的唯一数据源）

/// 左列表的状态：把「一次扫描」变成一个确定值。两个分支都**不崩**。
public enum ReportListState: Equatable {
    /// 扫描根不可用（不存在 / 不是目录）⇒ 界面出**空态**（提示一句，不崩）。
    case rootUnavailable(path: String)
    /// 扫描完成：好包逐条 + 坏包逐条（两者都可为空 ⇒ 界面出空态）。
    case scanned(packages: [ReportPackage], issues: [ReportPackageIssue])

    /// 好包逐条（非 `scanned` ⇒ 空数组）。
    public var packages: [ReportPackage] {
        if case .scanned(let packages, _) = self { return packages }
        return []
    }

    /// 坏包逐条报告（非 `scanned` ⇒ 空数组）。
    public var issues: [ReportPackageIssue] {
        if case .scanned(_, let issues) = self { return issues }
        return []
    }

    /// 是不是空态 —— 界面上该显示「本机暂无可读周报包」。
    public var isEmpty: Bool { packages.isEmpty && issues.isEmpty }
}

// MARK: - 扫描根 ⇒ 列表状态（纯映射，绝不抛）

/// 视图层与领域层之间的**唯一接线**：一次只读扫描 ⇒ 列表状态。
///
/// 硬口径：`ReportPackageScanner.scan` 会为「根不存在 / 非目录」抛 `ReportPackageError`，
/// 这里**全部吃掉**落成 `.rootUnavailable` —— 界面出空态，而不是把异常冒到视图树里崩掉（判据 ④）。
public enum ReportListPresenter {
    public static func present(root: URL) -> ReportListState {
        do {
            let result = try ReportPackageScanner.scan(rootDirectory: root)
            return .scanned(packages: result.packages, issues: result.issues)
        } catch let error as ReportPackageError {
            switch error {
            case .rootMissing(let path):
                return .rootUnavailable(path: path)
            }
        } catch {
            return .rootUnavailable(path: root.path)
        }
    }
}

// MARK: - 模型（可观察；只读刷新）

/// 左列表的模型：持有扫描根 + 当前状态 + 选中期号。
///
/// 只读：`reload()` 只重跑一次只读扫描，**没有任何写回包的入口**（M0 不做编辑器）。
@MainActor
public final class ReportListModel: ObservableObject {
    @Published public private(set) var state: ReportListState
    /// 选中的**期号**（= 包目录名，`IR-05` 不变量 1）；右区据此取包。
    @Published public var selectedDirectoryName: String?

    /// 扫描根（本机盘上一层的目录，其直接子目录即各期包）。
    public let root: URL

    public init(root: URL) {
        self.root = root
        self.state = ReportListPresenter.present(root: root)
    }

    /// 按 `App` 的**固定扫描目录**（`ReportReader.fixedScanRootPath`）建一个模型 —— 阅读器的常规入口。
    ///
    /// 路径不在这里重复写：**唯一出处 = `ReportReader`**（视图层与命令入口共用一份）。
    public static func fixed() -> ReportListModel {
        ReportListModel(root: ReportReader.fixedScanRootURL)
    }

    /// 重新扫描一次（只读）。坏包不会中断整轮 —— 逐条进 `state.issues`。
    public func reload() {
        state = ReportListPresenter.present(root: root)
    }

    /// 当前选中的那一期（没选中 / 选中的是坏目录 ⇒ `nil`）。
    public var selectedPackage: ReportPackage? {
        guard let selectedDirectoryName else { return nil }
        return state.packages.first { $0.directoryName == selectedDirectoryName }
    }
}

// MARK: - 视图

/// 左侧周报卡片列表。每期一张卡；坏目录逐条一行报告；空 ⇒ 空态。
///
/// **触发面接线**（`FR-R-13-10` · 首片 B）：列表顶部挂生成区（`GenerationTriggerView`）—— 与左列表
/// **同一个扫描根**；生成**成功**后经 `onGenerated` 调**既有** `reload()` 入口重扫（**不新建第二套扫描**）。
/// 除这处接线外，本文件既有的只读语义**一字未改**（仍旧只调 `ReportPackageScanner.scan`，无写回入口）。
public struct ReportListView: View {
    @ObservedObject private var model: ReportListModel
    /// 生成区模型（触发面）：扫描根与左列表同源；生成成功后复用既有重扫入口。
    ///
    /// **按视图身份持有（`@StateObject`，不是 `@ObservedObject`）**：真实宿主
    /// （Studio 侧 `App/Views/RetroHostView.swift`）在 `body` 里构造本视图
    /// （`ReportListView(model: model)`）⇒ 宿主每次重绘都会**重跑本视图的 `init`**。
    /// 若用 `@ObservedObject` 在 `init` 里现建，模型会**整体重建**：结果行 / 缺期提示 / 已排的
    /// 到点全丢，还会每次重绘重读一遍缺期日志、重复排一个定时器。`@StateObject` 的自动闭包
    /// **只在首次装配时求值一次** ⇒ 跨重绘保持同一实例。**宿主调用点不需要动** —— 宿主侧
    /// 的 `ReportListModel` 同样以 `@StateObject` 持有（同一条口径）。
    @StateObject private var trigger: GenerationTriggerModel

    public init(model: ReportListModel) {
        self.model = model
        _trigger = StateObject(wrappedValue: GenerationTriggerModel(scanRoot: model.root, onGenerated: { model.reload() }))
    }

    /// 显式装配（宿主可注入已建好的触发面模型 —— 例如单测 / 宿主统一持有）。
    public init(model: ReportListModel, trigger: GenerationTriggerModel) {
        self.model = model
        _trigger = StateObject(wrappedValue: trigger)
    }

    public var body: some View {
        List(selection: $model.selectedDirectoryName) {
            Section("生成本期（触发面）") {
                GenerationTriggerView(model: trigger)
            }

            if model.state.isEmpty {
                Text("本机暂无可读周报包")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.state.packages, id: \.directoryName) { package in
                ReportCardRow(package: package)
                    .tag(package.directoryName)
            }

            if !model.state.issues.isEmpty {
                Section("未成为周报包的目录（逐条报告）") {
                    ForEach(model.state.issues, id: \.directoryName) { issue in
                        ReportIssueRow(issue: issue)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("周报")
        .toolbar {
            Button("重新扫描") { model.reload() }
        }
    }
}

// MARK: - 一张卡 / 一条报告

/// 每期一张卡：期号 / 日期 / 标题 / 摘要 / 媒体件数（有封面则缩略图）。
struct ReportCardRow: View {
    let package: ReportPackage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let coverURL = resolvedCoverURL {
                InlineImageView(alt: "", url: coverURL, maxWidth: 64, showsCaption: false)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(package.metadata.id)
                        .font(.headline)
                    Text(package.metadata.published)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(package.metadata.title)
                    .font(.subheadline)
                if !package.metadata.summary.isEmpty {
                    Text(package.metadata.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("媒体 \(package.metadata.mediaCount) 件")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// 封面（`index.json` 的 `cover`，契约要求**相对路径**）⇒ 包内绝对路径；取不到 ⇒ 不显示缩略图。
    /// 去向判定交给领域层 `MediaResolve`（白名单 / 越界 / 缺失同一套口径），视图层不自行猜。
    private var resolvedCoverURL: URL? {
        guard let cover = package.metadata.cover else { return nil }
        let outcome = MediaResolve.resolve(reference: cover, packageDirectory: package.directoryURL)
        if case .inlineImage(_, let url) = outcome.resolution { return url }
        return nil
    }
}

/// 一条坏目录报告（`ReportPackageIssue` 的人读一行）。
struct ReportIssueRow: View {
    let issue: ReportPackageIssue

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(issue.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
