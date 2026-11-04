import Foundation
import Darwin
import DoyahRetroCore

// 命令入口（Retro macOS · M0 第 5 片 · 派单卡 `t_7530f3d6`）。
//
// 为什么要有它：前四片把**领域层**（`DoyahRetroCore`：扫包 / 解析 / 块模型 / 媒体策略）与
// **视图层**（`DoyahRetroUI`）都落了，但两者都只在单测里被驱动过 —— 一条命令、端到端跑一个
// **样例包**、把读数打成 JSON 的入口还没有。本文件就是那个入口：**扫一个根 ⇒ 逐期读数**。
//
// 契约出处（本片对应 `T-20261006-007` 验收 ①/② 与 `FR-R-13-08` / `FR-R-13-09` 的机械面）：
//   · `IR-05` §6.5「导入面」：扫**扫描根的直接子目录**，含 `index.json` + `report.md` 即为一期；
//   · `FR-R-13-09`：一条媒体引用 ⇒ `内联`（图片 / `mp4` 本地内联）/ `外链`（交系统默认处理）/
//     `占位`（白名单外格式）/ `缺失`（文件不在盘上）/ `越界`（`../`）/ `拒绝`（非相对形态）。
//
// 只做三件事，**不做第四件**：
//   ① 扫根（复用 R-01 `ReportPackageScanner`）—— 坏目录逐条 `issue`，**不崩**；
//   ② 逐期取媒体条目（复用 R-02 块模型：**独占一行的 `![alt](ref)` 即一条**）；
//   ③ 逐条判定（复用 R-03 `MediaResolve`）—— 打印一份**确定性 JSON 读数**到 stdout。
// 本层**不落盘、不碰包**（`IR-05` 不变量 7）：全程只读 + 写 stdout；本文件不 import 任何 GUI 框架。
//
// 用法（本仓根执行；二进制由 `swift build` 产出）：
//   .build/debug/DoyahRetroCLI <扫描根目录>
//   例：.build/debug/DoyahRetroCLI Plugins/Retro/Fixtures/sample
//
// 退出码：扫描成功 ⇒ **0**（哪怕有坏目录 —— 坏目录是「逐条报告」，不是失败）；
//         扫描根不存在 / 不是目录 ⇒ **1**（JSON 里带 `error`）；无参数 ⇒ **2**（用法打到 stderr）。

@main
struct DoyahRetroCLI {

    // MARK: - 一条媒体读数

    /// 一条媒体引用 ⇒ 读数（判定 + 去向 + 报告）。
    private struct MediaLine {
        /// `report.md` 里原样写的引用串。
        let reference: String
        /// 判定词（契约五类 + 拒绝）：`内联` / `外链` / `占位` / `缺失` / `越界` / `拒绝`。
        let judgement: String
        /// 去向的确定性描述（复用 `MediaResolution.description`）。
        let detail: String
        /// 该条产生的报告条目（内联 / 外链 ⇒ `nil`；占位四类 ⇒ **恰好一条**）。
        let report: String?
    }

    // MARK: - 入口

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let rootPath = arguments.first(where: { !$0.hasPrefix("--") }) else {
            FileHandle.standardError.write(Data("用法：DoyahRetroCLI <扫描根目录>\n".utf8))
            exit(2)
        }

        let root = URL(fileURLWithPath: rootPath).standardizedFileURL

        do {
            let result = try ReportPackageScanner.scan(rootDirectory: root)
            print(json(result: result, root: root.path))
            exit(0)
        } catch let error as ReportPackageError {
            print(jsonError(message: error.description, root: root.path))
            exit(1)
        } catch {
            print(jsonError(message: String(describing: error), root: root.path))
            exit(1)
        }
    }

    // MARK: - 判定（`MediaResolution` ⇒ 契约里的判定词）

    /// 把一条去向映射成判定词。**单调、穷尽**：`MediaResolution` 的每个 case 都有且只有一个词。
    private static func judgement(of resolution: MediaResolution) -> String {
        switch resolution {
        case .inlineImage, .inlineVideo:
            return "内联"
        case .externalLink:
            return "外链"
        case .placeholder(let reason, _):
            switch reason {
            case .fileMissing:
                return "缺失"
            case .pathOutOfPackage:
                return "越界"
            case .formatNotWhitelisted:
                return "占位"
            case .referenceNotRelative:
                return "拒绝"
            }
        }
    }

    /// 一条引用 ⇒ 读数。判定与报告**同源于一次** `MediaResolve`（不会两处各判一次而漂）。
    private static func mediaLine(for reference: String, packageDirectory: URL) -> MediaLine {
        let outcome = MediaResolve.resolve(reference: reference, packageDirectory: packageDirectory)
        return MediaLine(
            reference: reference,
            judgement: judgement(of: outcome.resolution),
            detail: outcome.resolution.description,
            report: outcome.issue?.description
        )
    }

    /// 取一期的全部媒体条目：块模型里**独占一行的 `![alt](ref)`** 即一条（行进混排的留在段落里）。
    private static func mediaEntries(of package: ReportPackage) -> [MediaLine] {
        let rendered = ReportRenderer.render(package: package)
        var lines: [MediaLine] = []
        for block in rendered.blocks {
            guard case .image(let image) = block else { continue }
            lines.append(mediaLine(for: image.reference, packageDirectory: package.directoryURL))
        }
        return lines
    }

    // MARK: - JSON（手写发射器：键序固定、中文不转义 ⇒ 逐字节可复算）

    private static func json(result: ReportScanResult, root: String) -> String {
        var lines: [String] = []
        lines.append("{")
        lines.append("  \"root\": \(quoted(root)),")
        lines.append("  \"packageCount\": \(result.packages.count),")
        lines.append("  \"issueCount\": \(result.issues.count),")
        lines.append("  \"packages\": [")

        for (index, package) in result.packages.enumerated() {
            let media = mediaEntries(of: package)
            lines.append("    {")
            lines.append("      \"period\": \(quoted(package.directoryName)),")
            lines.append("      \"title\": \(quoted(package.metadata.title)),")
            lines.append("      \"mediaCount\": \(package.metadata.mediaCount),")
            lines.append("      \"media\": [")
            for (mediaIndex, entry) in media.enumerated() {
                let report = entry.report.map { quoted($0) } ?? "null"
                lines.append("        {")
                lines.append("          \"reference\": \(quoted(entry.reference)),")
                lines.append("          \"judgement\": \(quoted(entry.judgement)),")
                lines.append("          \"detail\": \(quoted(entry.detail)),")
                lines.append("          \"report\": \(report)")
                lines.append("        }\(mediaIndex == media.count - 1 ? "" : ",")")
            }
            lines.append("      ]")
            lines.append("    }\(index == result.packages.count - 1 ? "" : ",")")
        }

        lines.append("  ],")
        lines.append("  \"issues\": [")
        for (index, issue) in result.issues.enumerated() {
            lines.append("    \(quoted(issue.description))\(index == result.issues.count - 1 ? "" : ",")")
        }
        lines.append("  ]")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func jsonError(message: String, root: String) -> String {
        var lines: [String] = []
        lines.append("{")
        lines.append("  \"root\": \(quoted(root)),")
        lines.append("  \"error\": \(quoted(message))")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// 最小 JSON 串转义：只挡 `"` / `\` / 控制字符；非 ASCII（中文）**原样保留** —— 读数要人读得懂。
    private static func quoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
