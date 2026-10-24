import Foundation

/// 界面六态（概设 §8.4 / 详设 §5.3）。**闭集**：多一个或少一个都要先改概设。
///
/// 这套状的是「一屏该显示什么」，与数据从哪来无关 —— 所以放在 Core 里由纯函数判定，
/// 各界面（查询页签 / 对象树 / 连接清单 / 历史 / 导入导出汇总）共用同一份优先级，
/// 免得每个视图各写一套 if 链、最后六个态里总少一个。
public enum ViewState: String, Equatable, Sendable, CaseIterable {
    case loading
    case empty
    case error
    case permissionDenied
    case submitting
    case partialFailure

    /// 闭集清单（判据用：多一个状态就说明有人动了闭集）。
    public static var closedSet: [String] { allCases.map(\.rawValue).sorted() }
}

/// 六态判定（唯一真源）。优先级固定，不许调换：
/// 1. **权限不足** —— 缺能力位时任何操作都不能开始，显示别的态等于诱导；
/// 2. **提交中** —— 进行中态优先于错误（错误要等这次提交落定再报）；
/// 3. **加载中** —— 首次/刷新等待；
/// 4. **错误** —— 有错误且不在进行中；
/// 5. **部分失败** —— 有成功也有失败（导入导出汇总）；
/// 6. **空** —— 没有数据且无错误。
/// 有数据且无以上情况 ⇒ 返回 `nil`（正常内容态，不属于六态之一）。
public enum ViewStatePolicy {

    public static func decide(
        missingCapability: String? = nil,
        isSubmitting: Bool = false,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        partialFailure: (failed: Int, succeeded: Int)? = nil,
        hasData: Bool = false
    ) -> ViewState? {
        if missingCapability != nil { return .permissionDenied }
        if isSubmitting { return .submitting }
        if isLoading { return .loading }
        if let message = errorMessage, !message.isEmpty { return .error }
        if let partial = partialFailure, partial.failed > 0 { return .partialFailure }
        if !hasData { return .empty }
        return nil
    }

    /// 禁止组合（判据用）：某些态下**不许**渲染某些东西。
    /// - 错误态不许同时显示「没有数据」的引导（那是把失败伪装成空）；
    /// - 权限不足不许先展示内容再报错（灰色诱导）。
    public static func forbiddenCompanions(for state: ViewState) -> [String] {
        switch state {
        case .error: return ["emptyStateCopy", "emptyStateCTA"]
        case .permissionDenied: return ["contentPreview", "disabledTeaser"]
        case .loading, .empty, .submitting, .partialFailure: return []
        }
    }
}
