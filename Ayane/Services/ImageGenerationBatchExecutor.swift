import Foundation

struct GeneratedImageVariant: Identifiable, Equatable, Sendable {
    var id: Int { index }
    let index: Int
    let prompt: String
    let result: GeneratedImageResult
    let attempts: Int
}

struct ImageGenerationFailure: Identifiable, Equatable, Sendable {
    var id: Int { index }
    let index: Int
    let prompt: String
    let message: String
    let attempts: Int
}

struct ImageGenerationBatchResult: Equatable, Sendable {
    let images: [GeneratedImageVariant]
    let failures: [ImageGenerationFailure]

    var isComplete: Bool { failures.isEmpty }
    var isPartial: Bool { !images.isEmpty && !failures.isEmpty }
}

/// Provider-neutral batch execution. It keeps each current endpoint's proven
/// request format, but adds identity-aware prompt planning, bounded retries,
/// deterministic variations, partial-failure reporting and cancellation.
struct ImageGenerationBatchExecutor: Sendable {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    let client: any ImageGenerationClientProtocol
    private let sleeper: Sleeper

    init(
        client: any ImageGenerationClientProtocol,
        sleeper: @escaping Sleeper = { seconds in
            guard seconds > 0 else { return }
            let nanoseconds = UInt64(min(seconds, 60) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.client = client
        self.sleeper = sleeper
    }

    func generate(
        userPrompt: String,
        promptContext: ImagePromptContext = ImagePromptContext(),
        options: ImageGenerationBatchOptions = ImageGenerationBatchOptions(),
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async -> ImageGenerationBatchResult {
        var images: [GeneratedImageVariant] = []
        var failures: [ImageGenerationFailure] = []

        for index in 0..<options.count {
            if Task.isCancelled { break }
            let prompt = ImagePromptComposer.compose(
                userPrompt: userPrompt,
                context: promptContext,
                options: options,
                variationIndex: index
            )
            var attempt = 0
            while true {
                if Task.isCancelled { break }
                attempt += 1
                do {
                    let result = try await client.generateImage(
                        prompt: prompt,
                        configuration: configuration,
                        apiKey: apiKey
                    )
                    images.append(
                        GeneratedImageVariant(
                            index: index,
                            prompt: prompt,
                            result: result,
                            attempts: attempt
                        )
                    )
                    break
                } catch is CancellationError {
                    return ImageGenerationBatchResult(images: images, failures: failures)
                } catch {
                    let canRetry = attempt <= options.maximumRetries && isRetryable(error)
                    if canRetry {
                        let delay = options.initialRetryDelay * pow(2, Double(attempt - 1))
                        do {
                            try await sleeper(delay)
                            continue
                        } catch {
                            return ImageGenerationBatchResult(images: images, failures: failures)
                        }
                    }
                    failures.append(
                        ImageGenerationFailure(
                            index: index,
                            prompt: prompt,
                            message: error.localizedDescription,
                            attempts: attempt
                        )
                    )
                    break
                }
            }
            if index < options.count - 1, options.interRequestDelay > 0 {
                do {
                    try await sleeper(options.interRequestDelay)
                } catch {
                    break
                }
            }
        }
        return ImageGenerationBatchResult(images: images, failures: failures)
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let error = error as? ImageGenerationClientError,
           case .httpStatus(let code, _) = error {
            return code == 408 || code == 409 || code == 425 || code == 429
                || (500...599).contains(code)
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        return false
    }
}
