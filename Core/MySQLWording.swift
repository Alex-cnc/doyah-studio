import Foundation

/// **MySQL / GBase 驱动那几句人话的唯一出处**（队列 `L-65` 第 5 批 · 开发循环第 123 轮）。
///
/// **为什么单列一个文件**：`Core/MySQLService.swift` 在数据库侧**阶段性冻结**
/// （ADR-25，冻结点 `67fc5e6`，只增不改）。需求提出者 2026-09-30 拍板（`Q42`：
/// 「写死语言必须清零」）给的落法就是**新增文件** —— 把文案渲染搬到这儿，
/// 旧文件只留「语言从哪来」这一件事（`MySQLService.language`，由创建它的调用方给定）。
///
/// **口径（与 L-65 前四批一字不差）**：语言一律**由调用方给、不留默认值**；
/// 这里不读全局语言、不问界面 —— 谁渲染谁把 `language:` 递进来
/// （界面传 `effectiveLanguage`、命令行显式传中文、单测各传各的）。
public enum MySQLWording {
    /// 连接（含 TLS 与认证）超时。`MySQLServiceError.timedOut` 的 payload 就是它。
    public static func connectTimedOut(seconds: Int, language: AppLanguage) -> String {
        LocalizedStrings.format(.mysqlConnectTimedOut, language: language, String(seconds))
    }

    /// 主机名解析不了（连地址都还没交给驱动）。
    public static func hostResolveFailed(host: String, detail: String, language: AppLanguage) -> String {
        LocalizedStrings.format(.mysqlHostResolveFailed, language: language, host, detail)
    }

    /// 语句末尾那条「最后一个自增 ID」提示（结果集上的 notice）。
    public static func lastInsertID(_ value: String, language: AppLanguage) -> String {
        LocalizedStrings.format(.mysqlLastInsertID, language: language, value)
    }

    /// 语句超时（`seconds` 是给人看的字串：已知给秒数、未知给「—」）。
    public static func statementTimeout(seconds: String, language: AppLanguage) -> String {
        LocalizedStrings.format(.mysqlStatementTimeout, language: language, seconds)
    }

    /// 取消路径之一：没拿到服务端连接号（`CONNECTION_ID()`），下发不了 `KILL QUERY`。
    public static func cancelNoConnectionID(language: AppLanguage) -> String {
        LocalizedStrings.text(.mysqlCancelNoConnectionID, language: language)
    }

    /// 取消路径之二：该方言没给取消语句。
    public static func cancelStatementMissing(language: AppLanguage) -> String {
        LocalizedStrings.text(.mysqlCancelStatementMissing, language: language)
    }

    /// 取消路径之三：取消连接建不起来 / 语句没发出去（`detail` 是底层原串）。
    public static func cancelDispatchFailed(detail: String, language: AppLanguage) -> String {
        LocalizedStrings.format(.mysqlCancelDispatchFailed, language: language, detail)
    }

    /// `COPY … FROM STDIN` 是 PG 的通道；MySQL 侧如实说「不支持」。
    public static func copyUnsupported(language: AppLanguage) -> String {
        LocalizedStrings.text(.mysqlCopyUnsupported, language: language)
    }
}
