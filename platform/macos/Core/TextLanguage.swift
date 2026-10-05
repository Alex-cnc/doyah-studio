import Foundation

/// 工作区里「这是什么语言的文本」的判定（FR-EDIT-36 / FR-EDIT-38）。
///
/// 为什么单独一层：判语言这件事被**三个**地方同时需要 —— 打开文件时决定用什么高亮、
/// 补全时决定给哪套候选、保存时决定用什么缩进 / 注释风格。各写一份迟早不一致
/// （典型症状：`.tsx` 打开是纯文本，但补全却给了 JS 关键字）。
///
/// **本文件不持有任何语言知识。** 语言表（叫什么、认哪些扩展名 / 文件名、按什么规则着色）
/// 一律登记在 `Core/CodeLanguageDefinitions.swift`；这里只有"语言的标识"与三个转发。
/// 为什么这样切：FR-EDIT-38 ① 要的口径是「**新增语言不改核心代码**」，而知识写在哪个文件
/// 是能机械核对的（`Scripts/check-language-registry.py` 的源锚点判据）。
///
/// **为什么是 `RawRepresentable` 结构体而不是 `enum`**：`enum` 的 `case` 本身也是知识
/// （新增一个语言得改这个核心文件）。现在新增语言 = 登记表加一条 + 本类型末尾加一行
/// `static let`，**两处都在语言定义文件里**；本文件一行都不用动。
public struct TextLanguage: RawRepresentable, Hashable, Sendable, CaseIterable {
    /// 与登记表的 `language` 同一个值（`sql` / `javascript` / `plainText`…）。
    public let rawValue: String

    /// 只有**登记过**的 id 才构造得出来 —— 未知 id 给 `nil`，不静默造一个"看起来像语言"
    /// 的东西（`plainText` 是显式的回落值，不是兜底垃圾箱）。
    public init?(rawValue: String) {
        guard CodeLanguageRegistry.definition(id: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// 登记表内部用：表里那一行自己就是定义，不必回头再查一次（也避免初始化期的循环）。
    init(registered id: String) { self.rawValue = id }

    /// 全部登记语言（次序 = 登记表次序，`plainText` 在最后）。
    public static var allCases: [TextLanguage] { CodeLanguageRegistry.all.map(\.language) }

    /// 这份语言的**全部定义** —— 唯一事实源，下面几个属性都只是它的转发。
    public var definition: CodeLanguageDefinition { CodeLanguageRegistry.definition(of: self) }
    /// 界面上的语言名（ASCII 专有名词，见登记表注释）。
    public var displayName: String { definition.displayName }
    /// 这个语言是否支持**代码编辑**（关键字着色 + 补全）。
    ///
    /// `plainText` / `markdown` / `yaml` / `shell` 识别得了，但不高亮关键字 —— 这里不是
    /// "能不能打开"，而是"要不要按代码去着色与补全"。
    public var isCode: Bool { definition.isCode }
    /// 扩展名（小写、不含点）。顺序不重要，**一张表只在一个地方**（登记表）。
    public var fileExtensions: [String] { definition.fileExtensions }
    /// 没有扩展名但**一眼能认出**的文件名（小写）。
    public var fileNames: [String] { definition.fileNames }

    /// 按路径判语言：**文件名优先，其次扩展名**，都不认就纯文本（FR-EDIT-38 ④）。
    ///
    /// `path` 可以是绝对路径、相对路径或只有一个文件名 —— 只看最后一段。
    public static func detect(path: String) -> TextLanguage { CodeLanguageRegistry.detect(path: path) }
}
