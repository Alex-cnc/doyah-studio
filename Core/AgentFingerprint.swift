import Foundation

/// 指纹（`FR-AI-20` ③⑤：审批按**次** —— 工具名 + 参数）。
///
/// FNV-1a 64：纯函数、不引随机源 ⇒ 判据可以逐项对拍。**唯一一处实现**（注册表与工具共用）。
public enum AgentFingerprint {
    public static func hash(_ material: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(material.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
