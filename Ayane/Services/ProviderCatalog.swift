import CryptoKit
import Foundation

/// Providers that expose an OpenAI-compatible chat-completions surface.
///
/// The catalog only supplies connection defaults. Every address stays editable
/// because regional, workspace and private-gateway URLs can differ. Model IDs
/// are discovered from the provider instead of being frozen into the app.
enum ProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case deepSeek = "deepseek"
    case qwen = "qwen"
    case siliconFlow = "siliconflow"
    case moonshot = "moonshot"
    case openAI = "openai"
    case gemini = "gemini"
    case xAI = "xai"
    case groq = "groq"
    case mistral = "mistral"
    case openRouter = "openrouter"
    case together = "together"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .qwen: "阿里云百炼 / 通义千问"
        case .siliconFlow: "硅基流动"
        case .moonshot: "Kimi / Moonshot"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .xAI: "xAI"
        case .groq: "Groq"
        case .mistral: "Mistral"
        case .openRouter: "OpenRouter"
        case .together: "Together AI"
        case .custom: "自定义 OpenAI 兼容接口"
        }
    }

    var regionTitle: String {
        switch self {
        case .deepSeek, .qwen, .siliconFlow, .moonshot: "中国服务"
        case .openAI, .gemini, .xAI, .groq, .together: "美国服务"
        case .mistral: "欧洲服务"
        case .openRouter: "国际聚合服务"
        case .custom: "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .siliconFlow: "https://api.siliconflow.cn/v1"
        case .moonshot: "https://api.moonshot.cn/v1"
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .xAI: "https://api.x.ai/v1"
        case .groq: "https://api.groq.com/openai/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .together: "https://api.together.ai/v1"
        case .custom: ""
        }
    }

    var initialModel: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        default: ""
        }
    }

    static func resolve(_ rawValue: String) -> ProviderPreset {
        ProviderPreset(rawValue: rawValue) ?? .custom
    }

    static func matching(baseURL: String) -> ProviderPreset? {
        guard let host = URLComponents(
            string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host?.lowercased() else {
            return nil
        }
        return allCases.first { preset in
            guard preset != .custom,
                  let presetHost = URLComponents(string: preset.defaultBaseURL)?.host?.lowercased() else {
                return false
            }
            if preset == .qwen {
                return host == presetHost
                    || host == "dashscope-intl.aliyuncs.com"
                    || host == "cn-hongkong.dashscope.aliyuncs.com"
                    || host == "dashscope-us.aliyuncs.com"
                    || host.hasSuffix(".maas.aliyuncs.com")
            }
            return host == presetHost
        }
    }

    /// Keychain identity for this connection. Presets receive one independent
    /// key each. Custom endpoints are additionally scoped to their normalized
    /// address, so editing the host can never reuse a credential silently.
    func credentialID(for enteredBaseURL: String) -> String {
        guard self == .custom else { return id }
        let trimmed = enteredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if var components = URLComponents(string: trimmed), components.host != nil {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            components.fragment = nil
            while components.path.count > 1, components.path.hasSuffix("/") {
                components.path.removeLast()
            }
            normalized = components.string ?? trimmed
        } else {
            normalized = trimmed
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return "custom-\(suffix)"
    }

    func modelListURL(for enteredBaseURL: String) throws -> URL {
        let trimmed = enteredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else {
            throw AIClientError.invalidBaseURL
        }

        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        if self == .deepSeek, host == "api.deepseek.com" {
            components.path = "/models"
            components.query = nil
            guard let url = components.url else { throw AIClientError.invalidBaseURL }
            return url
        }

        if self == .qwen,
           host == "dashscope.aliyuncs.com" || host == "dashscope-us.aliyuncs.com" {
            throw ProviderModelDiscoveryError.qwenWorkspaceAddressRequired
        }

        if self == .qwen,
           host == "dashscope-intl.aliyuncs.com"
                || host == "cn-hongkong.dashscope.aliyuncs.com"
                || host.hasSuffix(".maas.aliyuncs.com") {
            if let range = components.path.range(of: "/compatible-mode/v1") {
                components.path.replaceSubrange(range, with: "/api/v1")
            } else if components.path.isEmpty {
                components.path = "/api/v1"
            }
            components.path += "/models"
            components.queryItems = [
                URLQueryItem(name: "capabilities", value: "TG"),
                URLQueryItem(name: "page_no", value: "1"),
                URLQueryItem(name: "page_size", value: "100")
            ]
            guard let url = components.url else { throw AIClientError.invalidBaseURL }
            return url
        }

        var url = try OpenAICompatibleClient.endpoint(baseURL: trimmed, resource: "models")
        if self == .siliconFlow,
           var filtered = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            filtered.queryItems = [
                URLQueryItem(name: "type", value: "text"),
                URLQueryItem(name: "sub_type", value: "chat")
            ]
            if let filteredURL = filtered.url {
                url = filteredURL
            }
        }
        if self == .openRouter,
           var filtered = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // OpenRouter publishes parameter support for each model. Limit
            // discovery to text models that accept the two optional controls
            // this client sends so the picker does not offer predictably
            // incompatible choices.
            filtered.queryItems = [
                URLQueryItem(name: "output_modalities", value: "text"),
                URLQueryItem(name: "supported_parameters", value: "temperature,max_tokens")
            ]
            if let filteredURL = filtered.url {
                url = filteredURL
            }
        }
        return url
    }
}

enum ProviderModelDiscoveryError: LocalizedError, Equatable {
    case invalidResponse
    case noChatModels
    case qwenWorkspaceAddressRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "提供商返回了无法识别的模型列表。你仍可手动填写模型 ID。"
        case .noChatModels:
            "没有发现可用的聊天模型。请检查地址、密钥权限，或手动填写模型 ID。"
        case .qwenWorkspaceAddressRequired:
            "阿里云中国区兼容地址没有公开的通用模型列表。请改填工作空间的兼容地址，或直接手动填写模型 ID。"
        }
    }
}

struct ProviderModelCatalogClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listChatModels(
        provider: ProviderPreset,
        baseURL: String,
        apiKey: String
    ) async throws -> [String] {
        let url = try provider.modelListURL(for: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, body: data)
        let descriptors = try Self.decodeDescriptors(from: data)
        let modelIDs = descriptors
            .filter { $0.supportsChat(for: provider) }
            .map(\.id)
            .filter { !$0.isEmpty && Self.looksLikeChatModel($0, provider: provider) }
        let unique = Array(Set(modelIDs)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        guard !unique.isEmpty else {
            throw ProviderModelDiscoveryError.noChatModels
        }
        return unique
    }

    private static func decodeDescriptors(from data: Data) throws -> [ModelDescriptor] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ModelListEnvelope.self, from: data) {
            let values = envelope.data ?? envelope.models ?? envelope.output?.models ?? []
            if !values.isEmpty { return values }
        }
        if let array = try? decoder.decode([ModelDescriptor].self, from: data), !array.isEmpty {
            return array
        }
        throw ProviderModelDiscoveryError.invalidResponse
    }

    private static func looksLikeChatModel(_ id: String, provider: ProviderPreset) -> Bool {
        let lower = id.lowercased()
        var excludedFragments = [
            "embedding", "embed-", "rerank", "whisper", "transcri",
            "speech", "tts", "moderation", "image", "dall-e", "sora",
            "audio", "realtime"
        ]
        if provider == .openAI {
            excludedFragments += ["babbage", "davinci"]
        }
        if provider == .groq {
            excludedFragments += ["guard"]
        }
        return !excludedFragments.contains(where: lower.contains)
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProviderModelDiscoveryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var message = ""
            if let envelope = try? JSONDecoder().decode(ModelListAPIErrorEnvelope.self, from: body) {
                message = envelope.error.message
            } else if let raw = String(data: body, encoding: .utf8) {
                message = String(raw.prefix(500))
            }
            throw AIClientError.httpStatus(http.statusCode, message)
        }
    }
}

private struct ModelListEnvelope: Decodable {
    struct Output: Decodable {
        let models: [ModelDescriptor]?
    }

    let data: [ModelDescriptor]?
    let models: [ModelDescriptor]?
    let output: Output?
}

private struct ModelDescriptor: Decodable {
    struct Capabilities: Decodable {
        let completionChat: Bool?

        enum CodingKeys: String, CodingKey {
            case completionChat = "completion_chat"
        }
    }

    let id: String
    let capabilities: Capabilities?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, model, name, capabilities, type
        case modelID = "model_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .model)
            ?? container.decodeIfPresent(String.self, forKey: .modelID)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        // Some providers use an object (`completion_chat`), while Alibaba
        // returns an array such as ["TG"]. Only the former carries a negative
        // chat capability that needs to be enforced here.
        capabilities = try? container.decode(Capabilities.self, forKey: .capabilities)
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }

    func supportsChat(for provider: ProviderPreset) -> Bool {
        guard capabilities?.completionChat != false else { return false }
        if provider == .together, let type = type?.lowercased() {
            return ["chat", "language", "code"].contains(type)
        }
        return true
    }
}

private struct ModelListAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
