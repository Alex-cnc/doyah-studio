import Foundation

/// **AI 产物 → 笔记** 的桥（DOYAH-10 / 任务 1）。
///
/// 为什么单列一层：AI 的三条能力（诊断 FR-AI-03、维护编排 FR-AI-04、MCP FR-AI-10）各自产出不同形状的结果，
/// 而"存进笔记"必须**同一套元信息**（来源类型 / 连接名 / 指纹 / 时间），否则半年后在笔记里
/// 分不清这条是诊断结论还是维护计划，也不知道当时连的是哪个库。
///
/// **三条边界在类型上落地**（与 `NoteDraft` 一起构成"不能绕过"的约束）：
///   ① 证据里的**行数据不进笔记**（只留编号、种类、说明与取证 SQL）—— 需要带数据必须走显式 `.withRowData()`；
///   ② 来源只记**连接名字**；
///   ③ 指纹可复算（同一份产物重复保存能识别出来）。
public enum AICapture {

    /// **skill 草稿**：AI 攒出来的提示词 / 步骤 / 写法（DOYAH-10 的核心场景）。
    ///
    /// - Parameter defaultTag: 调用方**没给 tags** 时用的那一个标签 —— **文本，不是语言**
    ///   （队列 L-65 第 3 批 + `FR-PLUG-03`）：笔记侧**只收文本与标识**，语言是宿主的事，
    ///   「这一族该显示成什么语言」由宿主渲染好再进来（判据 = `check-plugin-assembly.py`
    ///   判据 03 的类型白名单：`String` / `String?` / `[String]` / `[String]?`）。
    public static func skillNote(
        title: String,
        body: String,
        connectionName: String? = nil,
        tags: [String]? = nil,
        defaultTag: String
    ) -> NoteDraft {
        NoteDraft(
            title: title,
            body: body,
            tags: tags ?? [defaultTag],
            source: NoteSource(kind: .skill, connectionName: connectionName)
        )
    }

    /// 纯 SQL 收藏。
    ///
    /// - Parameter tag: 这条收藏的标签 —— 同上，**是文本不是语言**。
    public static func sqlNote(
        sql: String,
        connectionName: String?,
        title: String? = nil,
        tag: String
    ) -> NoteDraft {
        NoteDraft(
            title: title ?? firstLine(of: sql),
            body: "```sql\n\(sql)\n```",
            tags: [tag],
            source: NoteSource(kind: .sql, connectionName: connectionName)
        )
    }

    // MARK: - 内部

    /// 从"目标"字符串里取连接名：`user@host:port/db（版本）` → 尽量给一个**人能认出来**的短名。
    /// 注意这里**只是显示用**，来源里绝不存连接串（口令更不可能）。
    static func connectionName(from target: String) -> String? {
        guard let at = target.firstIndex(of: "@") else { return target.isEmpty ? nil : target }
        let hostPart = target[target.index(after: at)...]
        let host = hostPart.split(separator: ":").first.map(String.init) ?? String(hostPart)
        return host.isEmpty ? nil : host
    }

    static func stableHash(_ text: String) -> String {
        // FNV-1a：小、确定、跨平台（不引哈希库，也不用 `Hasher` —— 后者每次进程启动都不一样）。
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func firstLine(of sql: String) -> String {
        let line = sql.split(separator: "\n").first.map(String.init) ?? "SQL"
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}

// **本文件一个本地化取值入口都没有，这是有意的**（队列 L-65 第 3 批 + `FR-PLUG-03`）：
// 笔记侧只收文本与标识 —— 要显示成什么语言是**宿主**的事，渲染好的文本再进来。
// 第一版把 `language: AppLanguage` 当形参加进来，被 `check-plugin-assembly.py` 判据 03 当场拦下
// （类型白名单只有 `String` / `String?` / `[String]` / `[String]?`）—— 那条判据是对的：
// 语言进笔记侧，等于让笔记侧替宿主选语言，是本轮正在销掉的那个形状的另一种写法。
