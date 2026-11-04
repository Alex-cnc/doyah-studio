import Foundation

// `IR-05` 周报包的**扫描**（Retro macOS · M0 第 1 片）。
//
// 契约出处 = `Docs/需求规范书.md` §6.5 `IR-05`「导入面」：
//   > Retro 扫一个**固定目录**的**直接子目录**，凡含 `index.json` 且 `report.md` 存在的即视为一个周报包；
//   > 缺件、编码错、媒体缺失逐条报告（`FR-R-12-04` 判据 ③）。
//
// 本片扫的是**盘上原生的包目录**（扫描根的直接子目录）；「导入 = 复制落本机」那一步（不变量 7）
// 与媒体件的内联 / 降级（`FR-R-13-09`）是后续片，本文件不涉及。
//
// 硬口径「逐条报告且不崩」：一个坏目录只产出一条 `ReportPackageIssue`，**不 throw、不 assert、
// 不中断**其余目录的解析（`FR-R-13-08` ④ 与 `FR-R-12-04` ③ 同口径）。

/// 一次扫描的全部结果：好包逐条、坏包逐条。
public struct ReportScanResult: Equatable {
    /// 解析成功的周报包（按 `published` 降序 —— 新期在前）。
    public let packages: [ReportPackage]
    /// 未成为包的目录，逐条（按目录名排序，便于对账）。
    public let issues: [ReportPackageIssue]

    public init(packages: [ReportPackage], issues: [ReportPackageIssue]) {
        self.packages = packages
        self.issues = issues
    }
}

/// 扫描根本身不可用（不存在 / 不是目录）—— 这是调用方的错，不是「某个包坏了」，故用错误表达。
public enum ReportPackageError: Error, Equatable, CustomStringConvertible {
    case rootMissing(String)

    public var description: String {
        switch self {
        case .rootMissing(let path):
            return "扫描根不存在或不是目录：\(path)"
        }
    }
}

public enum ReportPackageScanner {
    /// 扫描 `rootDirectory` 的**直接子目录**，逐个产出包或 issue。
    ///
    /// - 只认直接子目录；根下的普通文件忽略（不报错 —— 扫描根里放个 `README` 不该红）。
    /// - `assets/` 缺失**不算错**：契约不变量 2 明写「`assets/`（媒体目录，**可空**）」，
    ///   包是否成立只看 `index.json` + `report.md`。
    /// - 根不存在 / 非目录 ⇒ `ReportPackageError.rootMissing`。
    public static func scan(
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> ReportScanResult {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw ReportPackageError.rootMissing(rootDirectory.path)
        }

        let entries = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var packages: [ReportPackage] = []
        var issues: [ReportPackageIssue] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard isDirectoryEntry(entry, fileManager) else { continue }
            let name = entry.lastPathComponent
            switch validate(directory: entry, name: name, fileManager: fileManager) {
            case .package(let package):
                packages.append(package)
            case .issue(let kind):
                issues.append(ReportPackageIssue(directoryName: name, kind: kind))
            }
        }

        // 列表顺序：published 降序（ISO 日期字符串按字典序排即时间序），同日按目录名降序 —— 新期在前。
        packages.sort { lhs, rhs in
            if lhs.metadata.published != rhs.metadata.published {
                return lhs.metadata.published > rhs.metadata.published
            }
            return lhs.directoryName > rhs.directoryName
        }
        issues.sort { $0.directoryName < $1.directoryName }

        return ReportScanResult(packages: packages, issues: issues)
    }

    // MARK: - 单目录校验

    private enum Validation {
        case package(ReportPackage)
        case issue(ReportPackageIssue.Kind)
    }

    private static func validate(
        directory: URL,
        name: String,
        fileManager: FileManager
    ) -> Validation {
        let indexURL = directory.appendingPathComponent("index.json")
        let reportURL = directory.appendingPathComponent("report.md")
        let hasIndex = fileManager.fileExists(atPath: indexURL.path)
        let hasReport = fileManager.fileExists(atPath: reportURL.path)

        // 先按「缺件」分层报（与肉眼判断的顺序一致，回单好读）：
        if !hasIndex && !hasReport {
            let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            return .issue(contents.isEmpty ? .emptyDirectory : .missingIndexJSON)
        }
        if !hasIndex { return .issue(.missingIndexJSON) }
        if !hasReport { return .issue(.missingReportMD) }

        // 目录名 = 期号（不变量 1）：形状不对 ⇒ 这一期不成立。
        guard ReportPeriod.isValid(name) else { return .issue(.invalidPeriodName) }

        guard let indexData = try? Data(contentsOf: indexURL) else { return .issue(.missingIndexJSON) }
        guard let reportData = try? Data(contentsOf: reportURL) else { return .issue(.missingReportMD) }

        // 不变量 6：UTF-8（无 BOM）。两件正文都查。
        guard ReportPackageParser.decodeUTF8Text(indexData) != nil else {
            return .issue(.invalidEncoding(file: "index.json"))
        }
        guard let reportText = ReportPackageParser.decodeUTF8Text(reportData) else {
            return .issue(.invalidEncoding(file: "report.md"))
        }

        switch ReportPackageParser.decodeIndexJSON(indexData) {
        case .success(let metadata):
            let package = ReportPackage(
                directoryName: name,
                directoryURL: directory,
                metadata: metadata,
                reportMarkdown: reportText
            )
            return .package(package)
        case .failure(let kind):
            return .issue(kind)
        }
    }

    private static func isDirectoryEntry(_ url: URL, _ fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
