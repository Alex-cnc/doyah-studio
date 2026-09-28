import DoyahCore

/// 运行范围档位的名字：**唯一出处**。
///
/// 工具条那个「运行范围」菜单的字面、执行时写进 Output 的范围行，都取这里 ——
/// 同一个档位的名字写两遍，改文案时必有一处漂移（2026-09-27 人工点验那一族教训）。
extension ExecutionScope.Mode {
    /// 档位名。语言由调用方给（Core 不许自己选语言，见概要设计 §7「语言来源」），
    /// 所以这个映射落在 App 层而不是 `ExecutionScope` 里。
    var title: String {
        switch self {
        case .all: return L(.runScopeAll)
        case .currentStatement: return L(.runScopeCurrentStatement)
        case .selection: return L(.runScopeSelection)
        }
    }
}

/// 本次执行「跑的是哪一段」的摘要：范围名 + 本次语句数 + 脚本里一共几条语句。
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
