import Foundation

// MARK: - 片段模板（`FR-STD-WS-NAV-005`）
//
// 需求四条：① 按语言给片段（SQL 的 `select` / `join` 骨架、Markdown 表格等）；
// ② 触发后插入骨架、**可跳占位符**；③ 片段表**可扩展**，新增片段不改核心代码；
// ④ 片段表与**语言表同源**。
//
// 落法：**骨架是数据、判定是纯函数** ——
//   · 片段逐条登记在语言表里（`CodeLanguageDefinitions.snippets`，与 `formats` / `folds`
//     同一条做法：加一条片段 = 加一行数据，引擎一行不改）；
//   · 本文件只做三件纯事：**解析骨架**（占位符 → 插入文本 + 落点表）、
//     **认触发词**（光标前那个词，且光标不在字符串 / 注释里）、**跟会话**（Tab 依次跳落点）。
//
// 为什么「光标在字符串 / 注释里不触发」：在 `'sele|ct'` 里粘一段 `SELECT … FROM …` 是纯粹的破坏，
// 而掩码取自**词法器**（与着色 / 折叠同一份切分）—— 另写一套引号识别早晚与着色分叉。

/// 一条片段：触发词 + 骨架。
///
/// 骨架里的占位符写法（与 VS Code 同一族的形状，只保留能机械判定的那几种）：
/// · `$1` / `${1}` —— 第 1 个落点（不选中任何字符，插入点停在那儿）
/// · `${1:默认文本}` —— 第 1 个落点，默认文本先插进去并**被选中**（接着打字就是替换它）
/// · `$0` —— 收尾位置（最后一个落点之后按 Tab 就停在这儿）
/// · `$$` / `\$` —— 字面的 `$`（否则「金额」这类正文里的 `$` 会被吃掉）
public struct SnippetTemplate: Sendable, Equatable {
    /// 触发词（打字打到这个词再按 Tab）。**小写登记，匹配时不区分大小写** ——
    /// 写 SQL 的人习惯把关键字大写，而片段表只该有一行。
    public let trigger: String
    /// 骨架原文（占位符未解开）。
    public let body: String

    public init(trigger: String, body: String) {
        self.trigger = trigger
        self.body = body
    }
}

/// 骨架里的一个落点（解析结果）。
///
/// `offset` / `length` 都是**相对这份骨架文本**（默认文本已就位之后）的 UTF-16 位置，
/// 与编辑器里的 `NSRange` 同一口径 —— 换算只发生在会话层（`SnippetSession`），
/// 让「解析」这件事与「文档现在有多长」无关。
public struct SnippetStop: Hashable, Sendable {
    /// 占位符序号（1 起；`$0` 不占落点，只定收尾位置）。
    public let index: Int
    /// 在这个落点上的位置（默认文本的起点）。
    public let offset: Int
    /// 默认文本的 UTF-16 长度（`0` = 插入点，不选中任何东西）。
    public let length: Int

    public init(index: Int, offset: Int, length: Int) {
        self.index = index
        self.offset = offset
        self.length = length
    }

    public var range: NSRange { NSRange(location: offset, length: length) }
}

/// 解开占位符之后的一份骨架。
public struct SnippetBody: Equatable, Sendable {
    /// 真正要插进文档的文本（占位符已换成各自的默认文本）。
    public let text: String
    /// 落点表（按序号升序、同序号按位置升序）。
    public let stops: [SnippetStop]
    /// `$0` 的位置（相对 `text`）；没有 `$0` 就是 `nil`（收尾落到骨架末尾）。
    public let finish: Int?

    public init(text: String, stops: [SnippetStop], finish: Int?) {
        self.text = text
        self.stops = stops
        self.finish = finish
    }
}

/// 骨架解析：占位符 → 插入文本 + 落点表。**纯函数、确定性**（同一份骨架跑两遍逐字节相同）。
public enum SnippetParser {

    public static func parse(_ body: String) -> SnippetBody {
        var output = ""
        var stops: [SnippetStop] = []
        var finish: Int?
        let characters = Array(body)
        var index = 0

        /// 落一个落点：先记位置，再把默认文本接进正文。
        func record(number: Int, defaultValue: String) {
            if number == 0 {
                // `$0` 只定收尾位置；`${0:…}` 的默认文本按口径不插（收尾位置没有「要填的东西」）。
                if finish == nil { finish = (output as NSString).length }
                return
            }
            let offset = (output as NSString).length
            let length = (defaultValue as NSString).length
            output += defaultValue
            stops.append(SnippetStop(index: number, offset: offset, length: length))
        }

        while index < characters.count {
            let character = characters[index]

            // 转义：`\$` / `\}` ⇒ 字面字符（不算占位符、也不吃掉反斜杠）。
            if character == "\\", index + 1 < characters.count,
               characters[index + 1] == "$" || characters[index + 1] == "}" {
                output.append(characters[index + 1])
                index += 2
                continue
            }

            guard character == "$" else {
                output.append(character)
                index += 1
                continue
            }

            // `$$` ⇒ 字面 `$`。
            if index + 1 < characters.count, characters[index + 1] == "$" {
                output.append("$")
                index += 2
                continue
            }

            // `${N}` / `${N:默认}`
            if index + 1 < characters.count, characters[index + 1] == "{" {
                var cursor = index + 2
                var digits = ""
                while cursor < characters.count, characters[cursor].isASCII, characters[cursor].isNumber {
                    digits.append(characters[cursor])
                    cursor += 1
                }
                if !digits.isEmpty, let number = Int(digits), cursor < characters.count {
                    if characters[cursor] == "}" {
                        record(number: number, defaultValue: "")
                        index = cursor + 1
                        continue
                    }
                    if characters[cursor] == ":" {
                        var inner = cursor + 1
                        var defaultValue = ""
                        while inner < characters.count {
                            if characters[inner] == "\\", inner + 1 < characters.count,
                               characters[inner + 1] == "}" {
                                defaultValue.append("}")
                                inner += 2
                                continue
                            }
                            if characters[inner] == "}" { break }
                            defaultValue.append(characters[inner])
                            inner += 1
                        }
                        if inner < characters.count, characters[inner] == "}" {
                            record(number: number, defaultValue: defaultValue)
                            index = inner + 1
                            continue
                        }
                    }
                }
                // 认不出的 `${…` ⇒ **原样落字符**，不吞用户的下一个字符（悄悄吃字符最难查）。
            }

            // `$N`
            if index + 1 < characters.count, characters[index + 1].isASCII, characters[index + 1].isNumber {
                var cursor = index + 1
                var digits = ""
                while cursor < characters.count, characters[cursor].isASCII, characters[cursor].isNumber {
                    digits.append(characters[cursor])
                    cursor += 1
                }
                if let number = Int(digits) {
                    record(number: number, defaultValue: "")
                    index = cursor
                    continue
                }
            }

            // 光秃秃一个 `$`（正文里的金额、shell 变量都长这样）⇒ 字面。
            output.append("$")
            index += 1
        }

        stops.sort { left, right in
            left.index == right.index ? left.offset < right.offset : left.index < right.index
        }
        return SnippetBody(text: output, stops: stops, finish: finish)
    }
}

/// 一次展开：哪一段被换掉、换成什么、落点在哪（都还是**相对骨架**的口径）。
public struct SnippetExpansion: Equatable, Sendable {
    /// 被替换掉的触发词范围（文档内绝对位置）。
    public let replaceRange: NSRange
    /// 解开占位符之后的骨架。
    public let body: SnippetBody
    /// 命中的是哪一条（触发词，便于读数与判据点名）。
    public let trigger: String

    public init(replaceRange: NSRange, body: SnippetBody, trigger: String) {
        self.replaceRange = replaceRange
        self.body = body
        self.trigger = trigger
    }

    public var insertion: String { body.text }
}

/// 触发判定：光标前那个词 + 该不该展开。**纯函数**（词法掩码也只读传进来的那份文本）。
public enum SnippetEngine {

    /// 光标前那一「词」（ASCII 标识符口径：`[A-Za-z0-9_]`）。
    ///
    /// 为什么只认 ASCII：片段触发词是写法约定（`select` / `join` / `table`），
    /// 中文变量名里没有片段可展开；把中文也当词会让 `整表` 这类正文被认成触发词。
    public static func word(beforeCaretIn text: String, caret: Int) -> (word: String, range: NSRange)? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        var start = caret
        while start > 0, isWordUnit(ns.character(at: start - 1)) { start -= 1 }
        guard start < caret else { return nil }
        let word = ns.substring(with: NSRange(location: start, length: caret - start))
        return (word, NSRange(location: start, length: caret - start))
    }

    /// 这一刻该不该展开、展开成什么。`nil` = 不展开（**交还默认实现**，Tab 照旧缩进）。
    ///
    /// 四条闸门（顺序即口径）：
    /// 1. 片段表为空（这门语言没登记片段）⇒ 不展开；
    /// 2. 光标前那个词必须**恰好**是一个触发词（大小写不敏感）—— `selects` / `myselect` 都不算；
    /// 3. 光标后面紧邻的还是词字符（在词中间按 Tab）⇒ 不展开；
    /// 4. **触发词本身**落在字符串 / 注释里 ⇒ 不展开（掩码取自词法器，与着色同一份切分）。
    ///
    /// 第 4 条判的是**那个词的范围**、不是光标位置：在 `'select'` 里光标停在右引号前、
    /// 或在 `-- select` 的注释行尾 —— 这两种现场里「光标那一位」都可能刚好落在掩码之外一格，
    /// 按光标判就会在注释 / 字符串里粘一段 SQL 骨架（实测这类一格之差的判据最容易假绿）。
    public static func expansion(
        in text: String,
        caret: Int,
        templates: [SnippetTemplate],
        language: TextLanguage
    ) -> SnippetExpansion? {
        guard !templates.isEmpty else { return nil }
        guard let (word, range) = word(beforeCaretIn: text, caret: caret) else { return nil }
        let ns = text as NSString
        if caret < ns.length, isWordUnit(ns.character(at: caret)) { return nil }
        let wordRange = range.location..<(range.location + range.length)
        for span in CodeLexer.protectedSpans(in: text, language: language)
        where span.overlaps(wordRange) {
            return nil
        }
        let lowered = word.lowercased()
        guard let template = templates.first(where: { $0.trigger.lowercased() == lowered }) else {
            return nil
        }
        return SnippetExpansion(
            replaceRange: range,
            body: SnippetParser.parse(template.body),
            trigger: template.trigger
        )
    }

    static func isWordUnit(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
    }
}

/// 片段会话：插入之后「Tab 依次跳落点」的那份状态。
///
/// **状态住在文档坐标里**（绝对偏移），由调用方在每次编辑时喂 `noteEdit` 平移 ——
/// 否则用户在每个落点上打的字数一变，后面所有落点就全错位，Tab 会跳到一段无关的文字里。
///
/// 会话的三种下场（口径写死，不猜）：
/// · 落点跳完 ⇒ `advance()` 回 `nil`，调用方丢掉会话、Tab 回到缩进；
/// · 用户在**落点之间**改动（跨落点 / 两个落点中间的地方）⇒ `noteEdit` 回 `false`，
///   会话作废 —— 宁可不跳，也不跳到一个猜出来的位置；
/// · 插进去的骨架长度对不上（外部整篇替换）⇒ 同样作废。
public struct SnippetSession: Equatable, Sendable {

    /// 落点（文档绝对位置、按序号顺序）。
    public private(set) var stops: [SnippetStop]
    /// 当前停在哪个落点（下标）。
    public private(set) var active: Int
    /// 收尾位置（文档绝对位置）；`nil` = 骨架末尾。
    public private(set) var finishOffset: Int
    /// 已经跳完了（再按 Tab 就该交还缩进）。
    public private(set) var isFinished: Bool

    /// 插入完成那一刻，文档应当有多长（用来兜「外部整篇替换」。每次平移跟着改）。
    public private(set) var documentLength: Int

    /// 插入之后建立会话：`location` = 骨架插进来的起点。
    public static func starting(after expansion: SnippetExpansion, at location: Int) -> SnippetSession {
        let length = (expansion.insertion as NSString).length
        let stops = expansion.body.stops.map {
            SnippetStop(index: $0.index, offset: $0.offset + location, length: $0.length)
        }
        let finish = expansion.body.finish.map { $0 + location } ?? (location + length)
        return SnippetSession(
            stops: stops,
            active: 0,
            finishOffset: finish,
            isFinished: stops.isEmpty,
            documentLength: location + length
        )
    }

    /// 当前落点的选区（`nil` = 没有落点可停）。
    public var activeRange: NSRange? {
        guard active >= 0, active < stops.count else { return nil }
        return stops[active].range
    }

    /// Tab：跳下一个落点。跳完最后一个 ⇒ 回收尾位置（长度 0）并把会话标成结束。
    public mutating func advance() -> NSRange? {
        guard !isFinished else { return nil }
        if active + 1 < stops.count {
            active += 1
            return stops[active].range
        }
        isFinished = true
        return NSRange(location: finishOffset, length: 0)
    }

    /// 报告一次编辑（`range` = 文档绝对位置；`replacementLength` = 换进去的 UTF-16 长度）。
    /// 返回 `false` = 会话作废（调用方丢掉它，Tab 回到缩进）。
    @discardableResult
    public mutating func noteEdit(range: NSRange, replacementLength: Int) -> Bool {
        let delta = replacementLength - range.length
        let editEnd = range.location + range.length
        guard let current = activeRange else { return false }

        if range.location >= current.location, editEnd <= current.location + current.length {
            // ① 在当前落点之内改（替换默认文本）⇒ 只改这一段长度，后面的整体平移。
            stops[active] = SnippetStop(
                index: stops[active].index,
                offset: stops[active].offset,
                length: max(0, stops[active].length + delta)
            )
            shiftStops(from: active + 1, by: delta)
            if finishOffset >= editEnd { finishOffset += delta }
            documentLength += delta
            return true
        }
        if editEnd <= current.location {
            // ② 编辑整体在**当前落点之前** ⇒ 当前及之后的落点全平移。
            shiftStops(from: active, by: delta)
            if finishOffset >= editEnd { finishOffset += delta }
            documentLength += delta
            return true
        }
        let last = stops[stops.count - 1]
        if range.location >= last.offset + last.length {
            // ③ 编辑整体在**最后一个落点之后** ⇒ 落点不动，只挪收尾位置（若它在编辑点之后）。
            if finishOffset >= editEnd { finishOffset += delta }
            documentLength += delta
            return true
        }
        // ④ 其余（跨落点、落在两个落点之间）⇒ 不猜。
        return false
    }

    private mutating func shiftStops(from start: Int, by delta: Int) {
        guard delta != 0, start < stops.count else { return }
        var cursor = max(0, start)
        while cursor < stops.count {
            stops[cursor] = SnippetStop(
                index: stops[cursor].index,
                offset: stops[cursor].offset + delta,
                length: stops[cursor].length
            )
            cursor += 1
        }
    }
}

/// 片段表的取用与合并（`FR-STD-WS-NAV-005` ③④）。
public enum SnippetCatalog {

    /// 这门语言的片段（**从语言表来** —— 片段表与语言表同源，不在别处另存一份）。
    public static func templates(for language: TextLanguage) -> [SnippetTemplate] {
        CodeLanguageRegistry.definition(of: language).snippets
    }

    /// 把一份**自定义**片段表并进内置表（扩展点：用户表 / 插件表都走这一处）。
    ///
    /// 合并口径（写死，免得同一件事两处各判一次）：
    /// · 同触发词（不区分大小写）时**自定义那一条胜出** —— 用户要覆盖内置骨架是这个入口唯一的用途；
    /// · 其余按各自原有顺序拼接（自定义在前），不重新排序：片段表的顺序就是「同触发词取第一条」的次序。
    public static func merged(base: [SnippetTemplate], custom: [SnippetTemplate]) -> [SnippetTemplate] {
        guard !custom.isEmpty else { return base }
        guard !base.isEmpty else { return custom }
        let customTriggers = Set(custom.map { $0.trigger.lowercased() })
        return custom + base.filter { !customTriggers.contains($0.trigger.lowercased()) }
    }
}
