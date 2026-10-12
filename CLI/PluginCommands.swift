import Foundation
import DoyahCore

/// `plugins` 子命令：把「宿主认识哪些插件、哪些被降级、挂点归谁」暴露给**脚本**（概设 §8 判据 ①）。
///
/// **为什么要有它**：装配这件事今天只在界面里"看起来对"，
/// 而"插件不在 ⇒ 功能消失且不报错"是一条**可机械判定**的性质 ——
/// 没有脚本出口，它就退化成"我们相信它是这样"。
///
/// 用法：
///   DoyahCLI plugins dump [--dir <插件根目录>] [--json]
///
/// 退出码：0 = 至少一个插件激活且零降级；1 = 有降级项（**不是错误**，是"如实报"）；
/// 2 = 用法错；3 = 目录不存在。
extension DoyahCLI {
    static func runPluginsCommand(arguments: [String]) -> Int32 {
        func value(of flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        guard let action = arguments.first, action == "dump" else {
            FileHandle.standardError.write(Data("用法：plugins dump [--dir <插件根目录>] [--json]\n".utf8))
            return 2
        }

        let directory: URL
        if let text = value(of: "--dir") {
            directory = URL(fileURLWithPath: text, isDirectory: true)
        } else if let resolved = PluginManifestLoader.defaultPluginsDirectory() {
            directory = resolved
        } else {
            FileHandle.standardError.write(Data("找不到插件根目录：请给 --dir，或设 DOYAH_PLUGINS_DIR，或把 Plugins/ 放进 app 包\n".utf8))
            return 3
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            FileHandle.standardError.write(Data("插件根目录不存在：\(directory.path)\n".utf8))
            return 3
        }

        let registry = PluginRegistry.load(pluginsDirectory: directory)

        if arguments.contains("--json") {
            let payload: [String: Any] = [
                "directory": directory.path,
                "active": registry.active.map(\.id),
                "degraded": registry.degraded.map { ["id": $0.id, "reason": $0.reason] }
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return registry.degraded.isEmpty && !registry.active.isEmpty ? 0 : 1
        }

        print("plugins dir: \(directory.path)")
        for manifest in registry.active {
            let capabilities = manifest.capabilities.isEmpty ? "（无）" : manifest.capabilities.joined(separator: ",")
            let contributions = manifest.contributions
                .map { contribution -> String in
                    if let order = contribution.order {
                        return "\(contribution.point.rawValue)#\(order)"
                    }
                    return contribution.point.rawValue
                }
                .joined(separator: ",")
            print(
                "id=\(manifest.id) | displayName=\(manifest.displayName) | version=\(manifest.version)"
                    + " | entryTarget=\(manifest.entryTarget)"
                    + " | apiVersion=\(manifest.apiVersion) | storage=\(manifest.storage.rawValue)"
                    + " | capabilities=\(capabilities) | contributions=\(contributions)"
            )
        }
        for item in registry.degraded {
            print("degraded: id=\(item.id) | reason=\(item.reason)")
        }
        print("diagnostic: \(registry.diagnosticLine())")
        print("readings: active \(registry.active.count) / degraded \(registry.degraded.count)")
        // 挂点读数（契约 §3.52④ 的机械出口）：缺位插件会让自己的活动栏项整体消失。
        let mounts = PluginMounts.live(registry: registry, pluginsDirectory: directory)
        print("mounts: \(mounts.unmountedSummary)")

        // **空目录也返回 1**：没有插件的宿主是"功能整体消失"的合法形态，但脚本不该把它当"装配成功"。
        return registry.degraded.isEmpty && !registry.active.isEmpty ? 0 : 1
    }
}
