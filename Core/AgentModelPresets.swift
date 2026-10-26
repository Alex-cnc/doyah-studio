import Foundation

/// **模型工具**（`FR-AGT-TOOL-MODEL-001/002` / 本端计划 P4-模型）：多档 + 端点/模型名可预填。
public enum AgentModelTier: String, Codable, Sendable, CaseIterable {
    /// 快：小任务、路由、摘要。
    case fast
    /// 均衡：默认。
    case balanced
    /// 深：长上下文、复杂推理。
    case deep
}

public struct AgentModelPreset: Equatable, Sendable, Codable {
    public var tier: AgentModelTier
    public var endpoint: String
    public var model: String
    /// 该档的上下文上限（token）—— 压缩预算从这里取，不另写死数字。
    public var contextLimit: Int

    public init(tier: AgentModelTier, endpoint: String, model: String, contextLimit: Int) {
        self.tier = tier
        self.endpoint = endpoint
        self.model = model
        self.contextLimit = contextLimit
    }
}

public enum AgentModelPresetError: Error, Equatable, Sendable {
    case missingEndpoint
    case missingModel
    case nonPositiveLimit
    case endpointNotHTTPS(String)
}

public struct AgentModelCatalog: Equatable, Sendable {
    public var presets: [AgentModelPreset]

    public static let standard = AgentModelCatalog(presets: [
        AgentModelPreset(tier: .fast, endpoint: "https://api.example.com/v1", model: "fast-mini", contextLimit: 64_000),
        AgentModelPreset(tier: .balanced, endpoint: "https://api.example.com/v1", model: "balanced", contextLimit: 262_144),
        AgentModelPreset(tier: .deep, endpoint: "https://api.example.com/v1", model: "deep-max", contextLimit: 1_000_000),
    ])

    public init(presets: [AgentModelPreset]) {
        self.presets = presets
    }

    public func preset(for tier: AgentModelTier) -> AgentModelPreset? {
        presets.first { $0.tier == tier }
    }

    /// 预填：换端点/模型名时**保留档位与上限**，只改这两项（界面「改连接」用）。
    public func prefilled(tier: AgentModelTier, endpoint: String?, model: String?) throws -> AgentModelPreset {
        guard var preset = preset(for: tier) else { throw AgentModelPresetError.missingModel }
        if let endpoint { preset.endpoint = endpoint.trimmingCharacters(in: .whitespaces) }
        if let model { preset.model = model.trimmingCharacters(in: .whitespaces) }
        _ = try Self.validate(preset)
        return preset
    }

    public static func validate(_ preset: AgentModelPreset) throws -> AgentModelPreset {
        guard !preset.endpoint.isEmpty else { throw AgentModelPresetError.missingEndpoint }
        guard preset.endpoint.hasPrefix("https://") else {
            throw AgentModelPresetError.endpointNotHTTPS(preset.endpoint)
        }
        guard !preset.model.isEmpty else { throw AgentModelPresetError.missingModel }
        guard preset.contextLimit > 0 else { throw AgentModelPresetError.nonPositiveLimit }
        return preset
    }
}
