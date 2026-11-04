import Foundation

// 媒体白名单与**引用形态判定**（Retro macOS · M0 第 3 片 · 派单卡 `t_b92f9c11`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-09`（多媒体契约，媒体形态 = **组合**）：
//   > **图片** = 包内 `assets/` 相对路径**内联显示**；**视频** = **① 本地文件内联播放**
//   > （白名单 `mp4` / H.264 + AAC，见 `IR-05` 不变量 5）+ **② 外链点击打开**（浏览器 /
//   > 系统播放器，**视图内不嵌 iframe**）；白名单外格式**原位降级为占位**（不报错、不崩）；
//   > 媒体缺失 / 路径越界（`../`）⇒ **逐条报告 + 占位**。
// 白名单 = `Docs/需求规范书.md` §6.5 `IR-05` 不变量 5：
//   > 图片 `png` / `jpg` / `jpeg` / `webp` / `gif`；视频 `mp4`（H.264 + AAC）。
//
// 本片**只做策略与解析**（媒体分类 / 引用形态 / 去向往哪走）—— **不接播放器、不写视图**
// （视图层 = R-04）；故本文件只 `import Foundation`，**不 import 任何 GUI 框架**
// （概要设计 §2.2「依赖方向不变量 1」）。外链那条去向也只是**一个待系统处理的标记**，
// **不设 iframe / WebView 分支**（`FR-R-13-09` 视频② 明令「视图内不嵌 iframe」）。
//
// **如实登记**：契约的视频白名单写「`mp4`（H.264 + AAC）」= 容器 + 两路编码。本层只按**扩展名**
// 判**容器**白名单；**编码级**校验（H.264 / AAC 是不是真在里面）要真解码，属播放层（不在本片）
// ⇒ 本层**不声称**已校验编码，只声称「容器在白名单内 + 引用形态合法」。这条不许被读成「视频白名单
// 已全判」——差的就是编码那一半。

// MARK: - 媒体种类（`IR-05` 不变量 5 的两条白名单）

/// 一类可**内联**的媒体。两条：图片 / 视频（视频 = **本地文件内联播放**）。
public enum MediaKind: Equatable, CustomStringConvertible {
    case image
    case video

    public var description: String {
        switch self {
        case .image: return "图片"
        case .video: return "视频"
        }
    }
}

// MARK: - 白名单（`IR-05` 不变量 5 的唯一事实源）

/// 媒体白名单的**唯一事实源** —— 图片五条扩展名 + 视频一条。
///
/// 扩展名一律**小写、不带点**；比对时把引用里的扩展名小写化（`PNG` ⇄ `png` 同判）——
/// 盘上大小写混写很常见，不该因大小写把一张合法图片判成占位。
public enum MediaWhitelist {
    /// 图片：`png` / `jpg` / `jpeg` / `webp` / `gif`。
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]
    /// 视频：`mp4`（容器）。编码约束（H.264 + AAC）见文件头「如实登记」。
    public static let videoExtensions: Set<String> = ["mp4"]

    /// 白名单里**全部**扩展名（图片 ∪ 视频）—— 供判据点清单用，避免各处手抄一份会漂。
    public static var allExtensions: Set<String> { imageExtensions.union(videoExtensions) }

    /// 扩展名 ⇒ 白名单内的媒体种类；白名单外 ⇒ `nil`。
    public static func kind(forFileExtension fileExtension: String) -> MediaKind? {
        let normalized = fileExtension.lowercased()
        if imageExtensions.contains(normalized) { return .image }
        if videoExtensions.contains(normalized) { return .video }
        return nil
    }

    /// 从引用串里取**扩展名**（末段最后一个 `.` 之后、非空）；取不到 ⇒ `nil`。
    ///
    /// 只做**词法**切分（不碰盘、不认查询串）—— 引用是包内相对路径（`IR-05` 不变量 3），
    /// 没有 `?` / `#` 这类东西。`assets/trend.PNG` ⇒ `"PNG"`（大小写保留，比对时再小写化）；
    /// `assets/README` ⇒ `nil`；`assets/` ⇒ `nil`。
    public static func fileExtension(of reference: String) -> String? {
        let lastComponent = reference
            .split(separator: "/", omittingEmptySubsequences: false)
            .last
            .map(String.init) ?? reference
        guard let dot = lastComponent.lastIndex(of: ".") else { return nil }
        let suffix = lastComponent[lastComponent.index(after: dot)...]
        return suffix.isEmpty ? nil : String(suffix)
    }
}

// MARK: - 引用形态（`IR-05` 不变量 3「媒体按相对路径引用」）

/// 一条媒体引用的**形态**（三取一）。判定**只做词法**，不碰盘。
public enum MediaReferenceForm: Equatable {
    /// 包内相对路径（`assets/trend.png`）—— 可锚在包目录上解析。
    case relativePath(String)
    /// 外链（`http:` / `https:`）—— **交系统默认处理**（点击打开浏览器 / 系统播放器；
    /// 本层**不嵌 iframe / WebView**，见 `FR-R-13-09` 视频②）。
    case externalLink(URL)
    /// 非相对形态：**绝对路径**（`/…`）/ 其它 scheme（`data:` base64 / `file:` …）。
    /// `IR-05` 不变量 3 明令不用绝对路径、不内嵌 base64 ⇒ 这类**拒绝 + 报告**。
    case notRelative
}

/// 引用形态判定（纯词法）。**外链**只认 `http` / `https` 两种 scheme —— 其余（`data:` / `file:` …）
/// 一律归 `.notRelative`（拒绝），不是「顺手也支持一下」。
public enum MediaReferenceClassifier {
    /// 认定为**外链**的 scheme 白名单（大小写不敏感）。
    public static let externalSchemes: Set<String> = ["http", "https"]

    /// 引用 ⇒ 形态。
    public static func classify(_ reference: String) -> MediaReferenceForm {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .notRelative }
        // 绝对路径（`/…`）先挡掉：它没有 scheme，但也不是包内相对路径。
        if trimmed.hasPrefix("/") { return .notRelative }
        if let scheme = scheme(of: trimmed) {
            if externalSchemes.contains(scheme), let url = URL(string: trimmed) {
                return .externalLink(url)
            }
            return .notRelative        // data: / file: / 其它 scheme
        }
        // 无 scheme 但残留 base64 载荷（`iVBORw0KGgo=;base64,…` 这类）—— 同 R-02 口径，拒绝。
        if trimmed.contains(";base64,") { return .notRelative }
        return .relativePath(trimmed)
    }

    /// 取 URL scheme（`:` 之前的 `[A-Za-z][A-Za-z0-9+.-]*`），返回**小写**；无 ⇒ `nil`。
    ///
    /// 与 R-02 `ReportRenderer.hasScheme` 同口径（`/` 出现即判无 scheme，避免把 `a/b:c` 当 scheme）。
    static func scheme(of reference: String) -> String? {
        guard let first = reference.first, first.isLetter else { return nil }
        var name = ""
        for character in reference {
            if character == ":" { return name.lowercased() }
            if character == "/" { return nil }
            if character.isLetter || character.isNumber
                || character == "+" || character == "-" || character == "." {
                name.append(character)
            } else {
                return nil
            }
        }
        return nil
    }
}
