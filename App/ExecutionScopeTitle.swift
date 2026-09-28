import DoyahCore

/// 「这次跑的是哪一段」的名字：**唯一出处**。
///
/// 写进 Output 的那行范围交代、以及将来任何界面要显示它，都取这里 ——
/// 同一个说法写两遍，改文案时必有一处漂移（2026-09-27 那一族教训）。
extension ExecutionScope.Source {
    /// 来源名（选中片段 / 整篇）。语言由调用方给（Core 不许自己选语言，见概要设计 §7「语言来源」），
    /// 所以这个映射落在 App 层而不是 `ExecutionScope` 里。
    var title: String {
        switch self {
        case .selection: return L(.execSourceSelection)
        case .wholeScript: return L(.execSourceWholeScript)
        }
    }
}

/// 本次执行「跑的是哪一段」的摘要：来源名 + 本次语句数 + 脚本里一共几条语句。
///
/// 三个字段都**显式标注类型**：`L(...)` 的实参类型要能被 `Scripts/check-format-arguments.py`
/// 解析出来（裸的局部变量属于"类型不明"，要去占那份全局预算 —— 那是留给既有欠账的）。
struct ExecutionScopeSummary: Equatable {
    var scopeName: String
    var runningStatements: Int
    var scriptStatements: Int

    /// 脚本里还有没跑的语句（要**明说没跑**，不能只跑一条了事）。
    var skipsStatements: Bool { scriptStatements > runningStatements }
}
