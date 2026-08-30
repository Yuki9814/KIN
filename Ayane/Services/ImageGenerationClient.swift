import Foundation
import ImageIO
import Darwin

enum ImageGenerationAPIStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case imagesAPI = "images_api"
    case openRouterImages = "openrouter_images"
    case chatCompletions = "chat_completions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imagesAPI:
            return "Images API"
        case .openRouterImages:
            return "OpenRouter Images API"
        case .chatCompletions:
            return "网关多模态 Chat（非 OpenAI 标准）"
        }
    }

    var detail: String {
        switch self {
        case .imagesAPI:
            return "调用 /images/generations，兼容 OpenAI、xAI 及同类接口"
        case .openRouterImages:
            return "调用 OpenRouter 当前专用 /images 接口"
        case .chatCompletions:
            return "调用供应商自定义 /chat/completions 并解析结构化图片输出；这不是 OpenAI 或 OpenRouter 当前标准生图协议"
        }
    }

    fileprivate var defaultResource: String {
        switch self {
        case .imagesAPI:
            return "images/generations"
        case .openRouterImages:
            return "images"
        case .chatCompletions:
            return "chat/completions"
        }
    }
}

struct ImageGenerationConfiguration: Equatable, Sendable {
    var baseURL: String
    var model: String
    var apiStyle: ImageGenerationAPIStyle

    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GeneratedImageResult: Equatable, Sendable {
    let data: Data
    let revisedPrompt: String?
}

enum ImageGenerationClientError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case missingModel
    case missingAPIKey
    case invalidResponse
    case invalidImageData
    case imageTooLarge
    case unsafeImageURL
    case unsupportedResponsesEndpoint
    case incompleteImagesEndpoint
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "图片 API 地址无效，请填写完整的 http 或 https 地址。"
        case .missingModel:
            return "请先填写图片模型 ID。"
        case .missingAPIKey:
            return "请先保存图片生成 API Key。"
        case .invalidResponse:
            return "图片 API 没有返回可识别的图片数据。"
        case .invalidImageData:
            return "图片 API 返回的内容不是有效图片。"
        case .imageTooLarge:
            return "生成图片超过 20 MB，未写入聊天记录。"
        case .unsafeImageURL:
            return "图片 API 返回了不安全或不受支持的图片地址。"
        case .unsupportedResponsesEndpoint:
            return "当前配置不支持 /responses 生图，请填写 API 根地址并选择 Images API。"
        case .incompleteImagesEndpoint:
            return "完整 Images API 地址必须以 /images/generations 结尾，不能只填 /images。"
        case .httpStatus(let code, let message):
            return message.isEmpty
                ? "图片 API 请求失败（HTTP \(code)）。"
                : "图片 API 请求失败（HTTP \(code)）：\(message)"
        }
    }
}

protocol ImageGenerationClientProtocol: Sendable {
    func generateImage(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async throws -> GeneratedImageResult
}

struct OpenAICompatibleImageGenerationClient: ImageGenerationClientProtocol {
    private let session: URLSession
    private let remoteImageURLValidator: @Sendable (URL) async -> Bool

    init(
        session: URLSession = .shared,
        remoteImageURLValidator: (@Sendable (URL) async -> Bool)? = nil
    ) {
        self.session = session
        self.remoteImageURLValidator = remoteImageURLValidator ?? { url in
            await Self.isSafeRemoteImageURL(url)
        }
    }

    func generateImage(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async throws -> GeneratedImageResult {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ImageGenerationClientError.missingModel }
        let credential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { throw ImageGenerationClientError.missingAPIKey }

        let endpoint = try Self.endpoint(for: configuration)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")

        switch configuration.apiStyle {
        case .imagesAPI:
            request.httpBody = try JSONEncoder().encode(
                ImagesGenerationRequest(
                    model: model,
                    prompt: prompt,
                    n: 1,
                    size: "1024x1024"
                )
            )
        case .openRouterImages:
            request.httpBody = try JSONEncoder().encode(
                OpenRouterImagesRequest(model: model, prompt: prompt)
            )
        case .chatCompletions:
            request.httpBody = try JSONEncoder().encode(
                ChatImageGenerationRequest(
                    model: model,
                    messages: [.init(role: "user", content: prompt)],
                    modalities: ["image", "text"],
                    n: 1,
                    stream: false
                )
            )
        }

        let (body, response) = try await session.data(for: request)
        try Self.validate(response: response, body: body)
        let candidate = try Self.imageCandidate(from: body)
        let imageData = try await resolve(candidate: candidate)
        try Self.validateImageData(imageData)
        return GeneratedImageResult(data: imageData, revisedPrompt: candidate.revisedPrompt)
    }

    /// Accepts either an API root (`https://host/v1`) or a complete image/chat
    /// endpoint. The standard image path is kept strict so a partially entered
    /// `/images` route cannot be saved as if it were usable.
    static func endpoint(for configuration: ImageGenerationConfiguration) throws -> URL {
        let trimmed = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            throw ImageGenerationClientError.invalidBaseURL
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/responses") {
            throw ImageGenerationClientError.unsupportedResponsesEndpoint
        }
        if configuration.apiStyle == .imagesAPI, path.hasSuffix("/images") {
            throw ImageGenerationClientError.incompleteImagesEndpoint
        }
        let targetSuffix = "/" + configuration.apiStyle.defaultResource
        if path.hasSuffix(targetSuffix) {
            components.path = path
            guard let url = components.url else {
                throw ImageGenerationClientError.invalidBaseURL
            }
            return url
        }

        for suffix in ["/images/generations", "/chat/completions", "/images"]
        where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        if path.isEmpty { path = "/v1" }
        components.path = path + targetSuffix
        guard let url = components.url else {
            throw ImageGenerationClientError.invalidBaseURL
        }
        return url
    }

    private func resolve(candidate: ImageCandidate) async throws -> Data {
        let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ImageGenerationClientError.invalidResponse }

        if value.lowercased().hasPrefix("data:image/") {
            guard let comma = value.firstIndex(of: ","),
                  value[..<comma].lowercased().contains(";base64") else {
                throw ImageGenerationClientError.invalidImageData
            }
            return try Self.decodeBase64(String(value[value.index(after: comma)...]))
        }

        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            guard await remoteImageURLValidator(url) else {
                throw ImageGenerationClientError.unsafeImageURL
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            // Never forward the provider credential to a returned CDN URL.
            // Redirects are deliberately disabled so a public CDN URL cannot
            // bounce the download to a loopback or private-network target.
            let (data, response) = try await session.data(
                for: request,
                delegate: ImageDownloadRedirectDelegate()
            )
            if let http = response as? HTTPURLResponse,
               (300..<400).contains(http.statusCode) {
                throw ImageGenerationClientError.unsafeImageURL
            }
            try Self.validate(response: response, body: data)
            return data
        }

        if value.contains("://") {
            throw ImageGenerationClientError.unsafeImageURL
        }
        return try Self.decodeBase64(value)
    }

    static func isSafeRemoteImageURL(_ url: URL) async -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHost.isEmpty else {
            return false
        }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"),
              !host.hasSuffix(".home.arpa") else {
            return false
        }
        return await Task.detached(priority: .utility) {
            Self.hostResolvesOnlyToPublicAddresses(host)
        }.value
    }

    private static func hostResolvesOnlyToPublicAddresses(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0,
              let first = result else {
            return false
        }
        defer { freeaddrinfo(first) }

        var foundAddress = false
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            let entry = current.pointee
            defer { cursor = entry.ai_next }
            guard let address = entry.ai_addr else { continue }
            switch Int32(entry.ai_family) {
            case AF_INET:
                let bytes = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    pointer -> [UInt8] in
                    let value = UInt32(bigEndian: pointer.pointee.sin_addr.s_addr)
                    return [
                        UInt8((value >> 24) & 0xff),
                        UInt8((value >> 16) & 0xff),
                        UInt8((value >> 8) & 0xff),
                        UInt8(value & 0xff)
                    ]
                }
                foundAddress = true
                guard isPublicIPv4(bytes) else { return false }
            case AF_INET6:
                var addressValue = address.withMemoryRebound(
                    to: sockaddr_in6.self,
                    capacity: 1
                ) { $0.pointee.sin6_addr }
                let bytes = withUnsafeBytes(of: &addressValue) { Array($0) }
                foundAddress = true
                guard isPublicIPv6(bytes) else { return false }
            default:
                continue
            }
        }
        return foundAddress
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]
        let third = bytes[2]
        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100, (64...127).contains(second) { return false }
        if first == 169, second == 254 { return false }
        if first == 172, (16...31).contains(second) { return false }
        if first == 192, second == 168 { return false }
        if first == 192, second == 0 { return false }
        if first == 192, second == 88, third == 99 { return false }
        if first == 198, second == 18 || second == 19 { return false }
        if first == 198, second == 51, third == 100 { return false }
        if first == 203, second == 0, third == 113 { return false }
        return true
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return false }
        if bytes[0] & 0xfe == 0xfc { return false }
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return false }
        if bytes[0] == 0xff { return false }
        if bytes[0...3] == [0x20, 0x01, 0x0d, 0xb8] { return false }

        let mappedPrefix = bytes.prefix(10).allSatisfy({ $0 == 0 })
            && bytes[10] == 0xff
            && bytes[11] == 0xff
        if mappedPrefix {
            return isPublicIPv4(Array(bytes.suffix(4)))
        }
        return bytes[0] & 0xe0 == 0x20
    }

    private static func imageCandidate(from body: Data) throws -> ImageCandidate {
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ImageGenerationClientError.invalidResponse
        }

        if let candidate = candidate(in: root["data"], revisedPrompt: root["revised_prompt"] as? String) {
            return candidate
        }
        if let candidate = candidate(in: root["images"], revisedPrompt: root["revised_prompt"] as? String) {
            return candidate
        }
        if let candidate = candidate(in: root, revisedPrompt: root["revised_prompt"] as? String) {
            return candidate
        }

        if let choices = root["choices"] as? [[String: Any]] {
            for choice in choices {
                guard let message = choice["message"] as? [String: Any] else { continue }
                if let candidate = candidate(in: message["images"], revisedPrompt: nil) {
                    return candidate
                }
                if let content = message["content"] as? [[String: Any]],
                   let candidate = candidate(in: content, revisedPrompt: nil) {
                    return candidate
                }
                if let content = message["content"] as? String,
                   let dataURL = firstDataURL(in: content) {
                    return ImageCandidate(value: dataURL, revisedPrompt: nil)
                }
            }
        }

        if let output = root["output"] as? [[String: Any]] {
            for item in output where (item["type"] as? String) == "image_generation_call" {
                if let result = item["result"] as? String, !result.isEmpty {
                    return ImageCandidate(
                        value: result,
                        revisedPrompt: item["revised_prompt"] as? String
                    )
                }
            }
        }
        throw ImageGenerationClientError.invalidResponse
    }

    private static func candidate(
        in value: Any?,
        revisedPrompt: String?
    ) -> ImageCandidate? {
        if let string = value as? String, !string.isEmpty {
            return ImageCandidate(value: string, revisedPrompt: revisedPrompt)
        }
        if let values = value as? [Any] {
            for item in values {
                if let candidate = candidate(in: item, revisedPrompt: revisedPrompt) {
                    return candidate
                }
            }
            return nil
        }
        guard let object = value as? [String: Any] else { return nil }
        let itemPrompt = object["revised_prompt"] as? String ?? revisedPrompt
        for key in ["b64_json", "base64", "data", "url", "public_url", "result"] {
            if let string = object[key] as? String, !string.isEmpty {
                return ImageCandidate(value: string, revisedPrompt: itemPrompt)
            }
        }
        for key in ["image_url", "inline_data", "inlineData", "file_output"] {
            if let candidate = candidate(in: object[key], revisedPrompt: itemPrompt) {
                return candidate
            }
        }
        return nil
    }

    private static func firstDataURL(in text: String) -> String? {
        guard let range = text.range(of: "data:image/", options: .caseInsensitive) else {
            return nil
        }
        let suffix = text[range.lowerBound...]
        let end = suffix.firstIndex { character in
            character.isWhitespace || character == ")" || character == "\"" || character == "'"
        } ?? suffix.endIndex
        let value = String(suffix[..<end])
        return value.contains(";base64,") ? value : nil
    }

    private static func decodeBase64(_ rawValue: String) throws -> Data {
        var normalized = rawValue
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        let maximumEncodedCount = ((SchemaV11DataSupport.maxImageDataBytes + 2) / 3) * 4 + 8
        guard normalized.count <= maximumEncodedCount,
              let data = Data(base64Encoded: normalized),
              !data.isEmpty else {
            throw normalized.count > maximumEncodedCount
                ? ImageGenerationClientError.imageTooLarge
                : ImageGenerationClientError.invalidImageData
        }
        return data
    }

    private static func validateImageData(_ data: Data) throws {
        guard !data.isEmpty else { throw ImageGenerationClientError.invalidImageData }
        guard data.count <= SchemaV11DataSupport.maxImageDataBytes else {
            throw ImageGenerationClientError.imageTooLarge
        }
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw ImageGenerationClientError.invalidImageData
        }
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ImageGenerationClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let value = error["message"] as? String {
                message = value
            } else {
                message = String((String(data: body, encoding: .utf8) ?? "").prefix(500))
            }
            throw ImageGenerationClientError.httpStatus(http.statusCode, message)
        }
        if http.expectedContentLength > Int64(SchemaV11DataSupport.maxImageDataBytes),
           http.mimeType?.lowercased().hasPrefix("image/") == true {
            throw ImageGenerationClientError.imageTooLarge
        }
    }
}

private final class ImageDownloadRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct ImageCandidate {
    let value: String
    let revisedPrompt: String?
}

private struct ImagesGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
}

private struct OpenRouterImagesRequest: Encodable {
    let model: String
    let prompt: String
}

private struct ChatImageGenerationRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let modalities: [String]
    let n: Int
    let stream: Bool
}
