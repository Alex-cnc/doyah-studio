import Foundation

/// 一个可注入模型的工具声明（`FR-AI-16` 的 `tools` 字段。
///
/// **唯一出处是工具注册表**（`FR-AI-19`）：这里只负责**搬运**，不做登记、不按工具名分支
/// （工具名的字面量只许出现在注册表定义处 —— 那条源树判据由 `FR-AI-19` 管）。
public struct LLMTool: Equatable, Sendable {

    public var name: String
    public var description: String
    /// 参数的 JSON Schema（**原样透传**给模型，本侧不改写、不裁剪）。
    public var parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }

    /// 发给模型的形状：`{"type":"function","function":{...}}`（OpenAI 兼容）。
    ///
    /// schema 解析不出来时**如实抛**，不静默降级成空参数（那会让模型以为这个工具没有参数）。
    func payload() throws -> [String: Any] {
        guard let data = parametersJSON.data(using: .utf8),
              let parameters = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.malformedResponse("工具 \(name) 的参数 schema 不是 JSON 对象。")
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ],
        ]
    }
}

/// `tool_choice` 的允许取值（`FR-AI-16` 验收要点 ①：取值必须在允许集合内）。
public enum LLMToolChoice: Equatable, Sendable {

    /// `auto` —— 由模型决定调不调。
    case automatic
    /// `none` —— 本轮一个工具都不调。
    case none
    /// `required` —— 必须调一个工具。
    case required
    /// 指名某个工具。
    case function(String)

    /// 字符串形态的允许集合（指名工具不在其列，它是 `{"type":"function",...}` 形态）。
    public static let allowedStringValues = ["auto", "none", "required"]

    /// 只接受集合内的字符串；其余一律拒绝（**不猜、不降级**）。
    public init?(rawValue: String) {
        switch rawValue {
        case "auto": self = .automatic
        case "none": self = .none
        case "required": self = .required
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .automatic: return "auto"
        case .none: return "none"
        case .required: return "required"
        case .function(let name): return name
        }
    }

    /// 发给模型的形状：前三档是字符串，指名工具是对象。
    var payload: Any {
        switch self {
        case .function(let name):
            return ["type": "function", "function": ["name": name]]
        default:
            return rawValue
        }
    }
}
