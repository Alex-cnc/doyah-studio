import Foundation

// `IR-05` 周报包（跨化身交换面）的**领域模型 + 解析**（Retro macOS · M0 第 1 片）。
//
// 契约出处 = `Docs/需求规范书.md` §6.5 `IR-05`（本片相关的不变量 1 / 2 / 4 / 6 / 7）：
//   1. 一个周报 = 一个目录；目录名 = **期号**（`2026-W40` 或 `YYYYMMDD`），目录名即 `id`，全局唯一
//   2. 包内固定三件：`index.json`（元数据）· `report.md`（正文）· `assets/`（媒体目录，**可空**）
//   4. 元数据最小集：`id` / `title` / `published` / `summary` / `cover`(可选) / `media_count`
//   6. 正文字符集：UTF-8（**无 BOM**）；换行 LF
//   7. 只读语义：Retro **不写**这个包 —— 本文件只读盘，不产生任何写盘动作
//
// 本片**只做领域层**：扫描 + 解析 + 逐条诊断。视图层（卡片列表 / 富文本 / 媒体内联）是
// R-04 / R-03 的活，故这里**不 import 任何 GUI 框架**（领域层不依赖 GUI —— 概要设计 §8.1）。
//
// 硬口径「逐条报告且不崩」（`FR-R-12-04` ③ / `FR-R-13-08` ④）：坏包**不抛异常打断整轮扫描** ——
// 每个目录各自产出一个 `ReportPackage`（好）或一条 `ReportPackageIssue`（坏），整轮结果封装在
// `ReportScanResult`（见 `ReportPackageScanner.swift`）。

// MARK: - 元数据最小集（`IR-05` 不变量 4）

/// `index.json` 的元数据最小集，逐名对应契约不变量 4。
///
/// 键名以契约为准（`media_count` 走 `CodingKeys` 显式映射）——实现侧**不另起别名**，
/// 免得盘上一种、代码里一种。
public struct ReportPackageMetadata: Equatable {
    /// 期号；`IR-05` 不变量 1 规定**目录名即 `id`**。
    public let id: String
    public let title: String
    /// ISO 日期（契约原文 `published`(ISO 日期)）；本片按字符串原样保留，不擅自改格式。
    public let published: String
    public let summary: String
    /// 封面，可选；契约要求**相对路径**。
    public let cover: String?
    /// 媒体件数（图片 + 视频）。
    public let mediaCount: Int

    public init(
        id: String,
        title: String,
        published: String,
        summary: String,
        cover: String?,
        mediaCount: Int
    ) {
        self.id = id
        self.title = title
        self.published = published
        self.summary = summary
        self.cover = cover
        self.mediaCount = mediaCount
    }
}

// MARK: - 一期周报包

/// 一个已解析好的周报包。
///
/// `directoryName` 既是目录名也是**期号**（`IR-05` 不变量 1）；`directoryURL` 指向本机盘上的包目录。
/// 只读：本模型不携带任何「写回」入口。
public struct ReportPackage: Equatable {
    public let directoryName: String
    public let directoryURL: URL
    public let metadata: ReportPackageMetadata
    /// `report.md` 的正文（已按不变量 6 校验为 UTF-8 无 BOM）。
    public let reportMarkdown: String

    public init(
        directoryName: String,
        directoryURL: URL,
        metadata: ReportPackageMetadata,
        reportMarkdown: String
    ) {
        self.directoryName = directoryName
        self.directoryURL = directoryURL
        self.metadata = metadata
        self.reportMarkdown = reportMarkdown
    }
}

// MARK: - 逐条诊断（坏包 ⇒ 一条 issue，不打断整轮）

/// 一个目录为什么**没成为**一期周报包。每条带目录名，便于「逐条报告」时点得出是哪一期。
public struct ReportPackageIssue: Equatable, CustomStringConvertible {
    public enum Kind: Equatable, Error {
        /// 目录里既没有 `index.json` 也没有 `report.md`（空目录）。
        case emptyDirectory
        /// 有 `report.md` 但没有 `index.json`。
        case missingIndexJSON
        /// 有 `index.json` 但没有 `report.md`。
        case missingReportMD
        /// 目录名不是期号形状（`2026-W40` / `YYYYMMDD`）。
        case invalidPeriodName
        /// 某个文件不是 UTF-8（或带 BOM）——`IR-05` 不变量 6。
        case invalidEncoding(file: String)
        /// `index.json` 是合法 UTF-8 但不是合法 JSON（或字段类型不符）。
        case invalidJSON(detail: String)
        /// `index.json` 缺必填字段（`IR-05` 不变量 4）。
        case missingMetadataField(field: String)
    }

    public let directoryName: String
    public let kind: Kind

    public init(directoryName: String, kind: Kind) {
        self.directoryName = directoryName
        self.kind = kind
    }

    /// 人读的一行报告（供日志 / 回单直接印）。
    public var description: String {
        switch kind {
        case .emptyDirectory:
            return "\(directoryName)：空目录（既无 index.json 也无 report.md）"
        case .missingIndexJSON:
            return "\(directoryName)：缺 index.json"
        case .missingReportMD:
            return "\(directoryName)：缺 report.md"
        case .invalidPeriodName:
            return "\(directoryName)：目录名非期号形状（应形如 2026-W40 或 YYYYMMDD）"
        case .invalidEncoding(let file):
            return "\(directoryName)：\(file) 非 UTF-8（或带 BOM）"
        case .invalidJSON(let detail):
            return "\(directoryName)：index.json 解析失败（\(detail)）"
        case .missingMetadataField(let field):
            return "\(directoryName)：index.json 缺必填字段 \(field)"
        }
    }
}

// MARK: - 期号形状（`IR-05` 不变量 1）

/// 期号形态校验。契约认两种：ISO 周 `YYYY-Www`、`YYYYMMDD`。
public enum ReportPeriod {
    /// `true` ⇔ 目录名是合法期号形态。
    public static func isValid(_ name: String) -> Bool {
        validISOWeek(name) || validDate(name)
    }

    /// ISO 周：`\d{4}-W\d{2}`，周号 01–53。
    private static func validISOWeek(_ name: String) -> Bool {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let year = parts[0]
        guard year.count == 4, year.allSatisfy(isDigit) else { return false }
        let week = parts[1]
        guard week.count == 3, week.first == "W" else { return false }
        let digits = week.dropFirst()
        guard digits.count == 2, digits.allSatisfy(isDigit), let number = Int(digits) else { return false }
        return (1...53).contains(number)
    }

    /// 日期：`YYYYMMDD`，月 01–12、日 01–31。
    private static func validDate(_ name: String) -> Bool {
        guard name.count == 8, name.allSatisfy(isDigit) else { return false }
        let yearEnd = name.index(name.startIndex, offsetBy: 4)
        let monthEnd = name.index(yearEnd, offsetBy: 2)
        guard let month = Int(name[yearEnd..<monthEnd]), let day = Int(name[monthEnd...]) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}

// MARK: - 解析（`index.json` → 元数据；非法输入 ⇒ 结构化 issue，不抛）

/// `index.json` 与文本文件的解析入口。全部返回 `Result` / `Optional`，**不抛异常** ——
/// 坏包要能被逐条报告，而不是打断整轮扫描。
public enum ReportPackageParser {
    /// 按 `IR-05` 不变量 6 解码：必须是 UTF-8 且**无 BOM**。不合规 ⇒ `nil`。
    public static func decodeUTF8Text(_ data: Data) -> String? {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= bom.count, Array(data.prefix(bom.count)) == bom { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 解析 `index.json`。字段缺失 ⇒ `.missingMetadataField`；JSON 语法 / 类型错 ⇒ `.invalidJSON`。
    public static func decodeIndexJSON(_ data: Data) -> Result<ReportPackageMetadata, ReportPackageIssue.Kind> {
        do {
            let raw = try JSONDecoder().decode(IndexJSON.self, from: data)
            return .success(raw.metadata)
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, _):
                return .failure(.missingMetadataField(field: key.stringValue))
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                return .failure(.invalidJSON(detail: "字段 \(path(of: context)) 类型不符"))
            case .dataCorrupted(let context):
                return .failure(.invalidJSON(detail: context.debugDescription))
            @unknown default:
                return .failure(.invalidJSON(detail: "未知解码错误"))
            }
        } catch {
            return .failure(.invalidJSON(detail: error.localizedDescription))
        }
    }

    private static func path(of context: DecodingError.Context) -> String {
        context.codingPath.map { $0.stringValue }.joined(separator: ".")
    }

    /// 盘上 `index.json` 的映像（键名与契约不变量 4 逐名对应）。
    private struct IndexJSON: Decodable {
        let id: String
        let title: String
        let published: String
        let summary: String
        let cover: String?
        let mediaCount: Int

        enum CodingKeys: String, CodingKey {
            case id, title, published, summary, cover
            case mediaCount = "media_count"
        }

        var metadata: ReportPackageMetadata {
            ReportPackageMetadata(
                id: id,
                title: title,
                published: published,
                summary: summary,
                cover: cover,
                mediaCount: mediaCount
            )
        }
    }
}
