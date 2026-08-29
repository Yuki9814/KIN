import Foundation

/// A durable, value-type representation of one item in Ayane's long-term memory.
///
/// The engine deliberately keeps this model independent from persistence. A store can
/// map its own record into this snapshot and keep the original `sourceID` when a result
/// is handed back to the caller.
public struct MemorySnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let sourceID: String
    public let createdAt: Date
    public let updatedAt: Date?
    public let importance: Float
    public let confidence: Float
    public let isPinned: Bool
    public let isSensitive: Bool
    public let expiresAt: Date?
    public let embedding: [Float]?

    public var sourceId: String { sourceID }
    public var content: String { text }
    public var body: String { text }
    public var lastModifiedAt: Date { updatedAt ?? createdAt }

    public init(
        id: String,
        text: String,
        sourceID: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        importance: Float = 0.5,
        confidence: Float = 1.0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.text = text
        self.sourceID = sourceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importance = importance
        self.confidence = confidence
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.embedding = embedding
    }

    /// Convenience spelling for callers whose persistence model calls the text field
    /// `content` rather than `text`.
    public init(
        id: String,
        content: String,
        sourceID: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        importance: Float = 0.5,
        confidence: Float = 1.0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        embedding: [Float]? = nil
    ) {
        self.init(
            id: id,
            text: content,
            sourceID: sourceID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            importance: importance,
            confidence: confidence,
            isPinned: isPinned,
            isSensitive: isSensitive,
            expiresAt: expiresAt,
            embedding: embedding
        )
    }

    /// Convenience spelling for codebases that use the Foundation-style `sourceId`.
    public init(
        id: String,
        text: String,
        sourceId: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        importance: Float = 0.5,
        confidence: Float = 1.0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        embedding: [Float]? = nil
    ) {
        self.init(
            id: id,
            text: text,
            sourceID: sourceId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            importance: importance,
            confidence: confidence,
            isPinned: isPinned,
            isSensitive: isSensitive,
            expiresAt: expiresAt,
            embedding: embedding
        )
    }

    /// Creates a snapshot from a persisted little-endian Float32 embedding.
    public init(
        id: String,
        text: String,
        sourceID: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        importance: Float = 0.5,
        confidence: Float = 1.0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        embeddingData: Data?
    ) {
        self.init(
            id: id,
            text: text,
            sourceID: sourceID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            importance: importance,
            confidence: confidence,
            isPinned: isPinned,
            isSensitive: isSensitive,
            expiresAt: expiresAt,
            embedding: embeddingData.flatMap(MemoryEmbeddingCodec.decode)
        )
    }

    public var embeddingData: Data? {
        embedding.map(MemoryEmbeddingCodec.encode)
    }
}

/// Options controlling one deterministic memory search.
public struct MemorySearchOptions: Sendable, Equatable {
    public var maxResults: Int
    /// The sum of the selected memory token counts can never exceed this value.
    /// `nil` means no token limit.
    public var tokenBudget: Int?
    public var now: Date
    public var queryEmbedding: [Float]?
    public var includeExpired: Bool
    public var minimumScore: Float
    public var duplicateJaccardThreshold: Float
    /// 0 disables source diversity. Larger values prefer a source not already used.
    public var diversityStrength: Float
    public var recencyHalfLifeDays: Double
    /// Allows a bounded, preselected set of high-value records to remain
    /// eligible when no embedding exists and the question paraphrases them.
    public var allowHighValueFallback: Bool

    public init(
        maxResults: Int = 8,
        tokenBudget: Int? = 256,
        now: Date = Date(),
        queryEmbedding: [Float]? = nil,
        includeExpired: Bool = false,
        minimumScore: Float = 0.10,
        duplicateJaccardThreshold: Float = 0.86,
        diversityStrength: Float = 0.18,
        recencyHalfLifeDays: Double = 30.0,
        allowHighValueFallback: Bool = false
    ) {
        self.maxResults = maxResults
        self.tokenBudget = tokenBudget
        self.now = now
        self.queryEmbedding = queryEmbedding
        self.includeExpired = includeExpired
        self.minimumScore = minimumScore
        self.duplicateJaccardThreshold = duplicateJaccardThreshold
        self.diversityStrength = diversityStrength
        self.recencyHalfLifeDays = recencyHalfLifeDays
        self.allowHighValueFallback = allowHighValueFallback
    }
}

/// One ranked result plus the diagnostics needed to explain why it was selected.
public struct MemorySearchResult: Hashable, Sendable {
    public let memory: MemorySnapshot
    public let score: Float
    /// Lexical coverage in the closed interval [0, 1].
    public let lexicalScore: Float
    /// Cosine similarity mapped from [-1, 1] into [0, 1]. It is zero when a vector
    /// could not be compared.
    public let vectorScore: Float
    /// The unmodified cosine value, when both vectors were present and compatible.
    public let cosineSimilarity: Float?
    public let importanceScore: Float
    public let confidenceScore: Float
    public let recencyScore: Float
    public let tokenCount: Int
    /// Query tokens that occurred in the selected memory, in query order.
    public let matchedTokens: [String]

    public var snapshot: MemorySnapshot { memory }
    public var id: String { memory.id }
    public var sourceID: String { memory.sourceID }
    public var sourceId: String { memory.sourceID }
    public var text: String { memory.text }
    public var relevanceScore: Float { score }

    public init(
        memory: MemorySnapshot,
        score: Float,
        lexicalScore: Float,
        vectorScore: Float,
        cosineSimilarity: Float? = nil,
        importanceScore: Float = 0,
        confidenceScore: Float = 0,
        recencyScore: Float = 0,
        tokenCount: Int,
        matchedTokens: [String] = []
    ) {
        self.memory = memory
        self.score = score
        self.lexicalScore = lexicalScore
        self.vectorScore = vectorScore
        self.cosineSimilarity = cosineSimilarity
        self.importanceScore = importanceScore
        self.confidenceScore = confidenceScore
        self.recencyScore = recencyScore
        self.tokenCount = tokenCount
        self.matchedTokens = matchedTokens
    }
}

/// Deterministic text tokenization used by the memory engine.
///
/// Latin words and numbers are lowercased and split on punctuation. CJK runs add
/// individual characters and overlapping bigrams, so a short Chinese query can match
/// both a single character and a meaningful two-character phrase without requiring
/// NaturalLanguage at runtime.
public enum MemoryTokenizer {
    public static func tokens(from text: String) -> [String] {
        var result: [String] = []
        var latinBuffer = ""
        var cjkRun: [String] = []

        func flushLatin() {
            guard !latinBuffer.isEmpty else { return }
            result.append(latinBuffer)
            latinBuffer.removeAll(keepingCapacity: true)
        }

        func flushCJK() {
            guard !cjkRun.isEmpty else { return }
            result.append(contentsOf: cjkRun)
            if cjkRun.count > 1 {
                for index in 0..<(cjkRun.count - 1) {
                    result.append(cjkRun[index] + cjkRun[index + 1])
                }
            }
            cjkRun.removeAll(keepingCapacity: true)
        }

        for scalar in text.lowercased().unicodeScalars {
            if isCJK(scalar) {
                flushLatin()
                cjkRun.append(String(scalar))
            } else if isWordScalar(scalar) {
                flushCJK()
                latinBuffer.append(contentsOf: String(scalar))
            } else {
                flushLatin()
                flushCJK()
            }
        }

        flushLatin()
        flushCJK()
        return result
    }

    public static func tokenCount(of text: String) -> Int {
        tokens(from: text).count
    }

    /// A punctuation-insensitive key used only for duplicate detection.
    public static func normalizedText(_ text: String) -> String {
        tokens(from: text).joined(separator: " ")
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        let character = Character(String(scalar))
        return character.isLetter || character.isNumber
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, // Hangul Jamo
             0x3040...0x30FF, // Hiragana and Katakana
             0x3100...0x312F, // Bopomofo
             0x3130...0x318F, // Hangul compatibility jamo
             0x31A0...0x31BF, // Bopomofo extended
             0x31F0...0x31FF, // Katakana phonetic extensions
             0x3400...0x4DBF, // CJK Extension A
             0x4E00...0x9FFF, // Unified ideographs
             0xA960...0xA97F, // Hangul Jamo Extended A
             0xAC00...0xD7FF, // Hangul syllables and Jamo Extended B
             0xF900...0xFAFF, // Compatibility ideographs
             0xFF66...0xFF9D, // Halfwidth Katakana
             0x20000...0x2FA1F: // Supplementary ideographs
            return true
        default:
            return false
        }
    }
}

/// Float32 embedding serialization and similarity helpers.
///
/// The wire format is intentionally small and explicit: each Float is encoded as its
/// IEEE-754 bit pattern in little-endian order. No platform alignment or native-endian
/// assumptions are involved, making persisted vectors portable between iOS and macOS.
public enum MemoryEmbeddingCodec {
    public static func encode(_ embedding: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(embedding.count * MemoryLayout<UInt32>.size)
        for value in embedding {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { rawBuffer in
                data.append(contentsOf: rawBuffer)
            }
        }
        return data
    }

    public static func decode(_ data: Data) -> [Float]? {
        let bytes = [UInt8](data)
        let stride = MemoryLayout<UInt32>.size
        guard bytes.count % stride == 0 else { return nil }

        var result: [Float] = []
        result.reserveCapacity(bytes.count / stride)
        var offset = 0
        while offset < bytes.count {
            let bits = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            result.append(Float(bitPattern: bits))
            offset += stride
        }
        return result
    }

    public static func encodeFloat32(_ embedding: [Float]) -> Data {
        encode(embedding)
    }

    public static func decodeFloat32(_ data: Data) -> [Float]? {
        decode(data)
    }

    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }

        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            guard left.isFinite, right.isFinite else { return nil }
            dot += left * right
            lhsNorm += left * left
            rhsNorm += right * right
        }

        guard lhsNorm > 0, rhsNorm > 0 else { return nil }
        let value = dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
        guard value.isFinite else { return nil }
        return Float(max(-1.0, min(1.0, value)))
    }

    public static func cosine(_ lhs: Data, _ rhs: Data) -> Float? {
        guard let left = decode(lhs), let right = decode(rhs) else { return nil }
        return cosine(left, right)
    }

    public static func cosine(_ lhs: Data?, _ rhs: Data?) -> Float? {
        guard let lhs, let rhs else { return nil }
        return cosine(lhs, rhs)
    }

    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        cosine(lhs, rhs)
    }

    public static func cosineSimilarity(_ lhs: Data, _ rhs: Data) -> Float? {
        cosine(lhs, rhs)
    }
}

/// Stateless hybrid retrieval for short- and long-term conversation memories.
public struct MemoryEngine: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var lexicalWeight: Float
        public var vectorWeight: Float
        public var importanceWeight: Float
        public var confidenceWeight: Float
        public var recencyWeight: Float
        public var pinnedBoost: Float
        public var minimumCosineForRelevance: Float

        public init(
            lexicalWeight: Float = 0.44,
            vectorWeight: Float = 0.28,
            importanceWeight: Float = 0.10,
            confidenceWeight: Float = 0.08,
            recencyWeight: Float = 0.10,
            pinnedBoost: Float = 0.20,
            minimumCosineForRelevance: Float = 0.20
        ) {
            self.lexicalWeight = lexicalWeight
            self.vectorWeight = vectorWeight
            self.importanceWeight = importanceWeight
            self.confidenceWeight = confidenceWeight
            self.recencyWeight = recencyWeight
            self.pinnedBoost = pinnedBoost
            self.minimumCosineForRelevance = minimumCosineForRelevance
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public static let shared = MemoryEngine()

    public func search(
        _ query: String,
        in memories: [MemorySnapshot],
        options: MemorySearchOptions = MemorySearchOptions()
    ) -> [MemorySearchResult] {
        let queryTokens = MemoryTokenizer.tokens(from: query)
        let queryUnique = unique(queryTokens)
        let queryTokenSet = Set(queryUnique)
        let normalizedBudget = options.tokenBudget.map { max(0, $0) }
        let resultLimit = max(0, options.maxResults)
        guard resultLimit > 0 else { return [] }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(memories.count)

        for (index, memory) in memories.enumerated() {
            let expired = memory.expiresAt.map { $0 <= options.now } ?? false
            if expired && !options.includeExpired { continue }

            let memoryTokens = MemoryTokenizer.tokens(from: memory.text)
            let tokenCount = memoryTokens.count
            if let budget = normalizedBudget, tokenCount > budget { continue }

            let lexical = lexicalScore(queryUnique: queryUnique, queryTokenSet: queryTokenSet, memoryTokens: memoryTokens)
            let matchedTokens = queryUnique.filter { memoryTokens.contains($0) }
            let cosine = options.queryEmbedding.flatMap { queryVector in
                memory.embedding.flatMap { MemoryEmbeddingCodec.cosine(queryVector, $0) }
            }
            let vector = cosine.map(normalizedCosine) ?? 0

            // Without an embedding model, an explicit high-value memory may
            // use different wording from the current question (for example
            // "乌龙茶" versus "最爱的饮品"). Keep a narrow quality fallback
            // so these durable facts still reach the prompt; ordinary unrelated
            // records continue to require lexical/vector evidence.
            let highValueFallback = options.allowHighValueFallback
                && cosine == nil
                && !memory.isSensitive
                && (memory.isPinned
                    || (memory.confidence >= 0.90 && memory.importance >= 0.75))
            if memory.isSensitive,
               cosine == nil,
               lexical < 0.25 {
                continue
            }
            if !queryUnique.isEmpty,
               lexical <= 0,
               (cosine ?? -1) < configuration.minimumCosineForRelevance,
               !highValueFallback {
                continue
            }

            let importance = clamp01(memory.importance)
            let confidence = clamp01(memory.confidence)
            let recency = recencyScore(for: memory, now: options.now, halfLifeDays: options.recencyHalfLifeDays)

            var lexicalWeight = max(0, configuration.lexicalWeight)
            var vectorWeight = cosine == nil ? 0 : max(0, configuration.vectorWeight)
            let importanceWeight = max(0, configuration.importanceWeight)
            let confidenceWeight = max(0, configuration.confidenceWeight)
            let recencyWeight = max(0, configuration.recencyWeight)
            let totalWeight = lexicalWeight + vectorWeight + importanceWeight + confidenceWeight + recencyWeight
            if totalWeight <= 0 {
                lexicalWeight = 1
                vectorWeight = 0
            }
            let denominator = totalWeight > 0 ? totalWeight : 1
            var score = (lexicalWeight * lexical + vectorWeight * vector
                + importanceWeight * importance
                + confidenceWeight * confidence
                + recencyWeight * recency) / denominator

            if memory.isPinned {
                score += max(0, configuration.pinnedBoost)
            }
            if expired {
                score *= 0.25
            }
            score = min(1, score)

            guard score.isFinite, score >= max(0, options.minimumScore) || memory.isPinned else {
                continue
            }

            let result = MemorySearchResult(
                memory: memory,
                score: score,
                lexicalScore: lexical,
                vectorScore: vector,
                cosineSimilarity: cosine,
                importanceScore: importance,
                confidenceScore: confidence,
                recencyScore: recency,
                tokenCount: tokenCount,
                matchedTokens: matchedTokens
            )
            candidates.append(
                Candidate(
                    result: result,
                    normalizedText: MemoryTokenizer.normalizedText(memory.text),
                    tokenSet: Set(memoryTokens),
                    sourceKey: memory.sourceID.isEmpty ? "id:\(memory.id)" : memory.sourceID,
                    originalIndex: index
                )
            )
        }

        candidates.sort(by: stableOrdering)
        let uniqueCandidates = removeDuplicates(candidates, threshold: options.duplicateJaccardThreshold)
        let selected = selectWithBudgetAndDiversity(
            uniqueCandidates,
            maxResults: resultLimit,
            tokenBudget: normalizedBudget,
            diversityStrength: max(0, options.diversityStrength)
        )
        return selected.map(\.result)
    }

    public func search(
        query: String,
        memories: [MemorySnapshot],
        options: MemorySearchOptions = MemorySearchOptions()
    ) -> [MemorySearchResult] {
        search(query, in: memories, options: options)
    }

    public func retrieve(
        query: String,
        from memories: [MemorySnapshot],
        options: MemorySearchOptions = MemorySearchOptions()
    ) -> [MemorySearchResult] {
        search(query, in: memories, options: options)
    }

    private struct Candidate {
        let result: MemorySearchResult
        let normalizedText: String
        let tokenSet: Set<String>
        let sourceKey: String
        let originalIndex: Int
    }

    private func stableOrdering(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.result.score != rhs.result.score {
            return lhs.result.score > rhs.result.score
        }
        if lhs.result.memory.isPinned != rhs.result.memory.isPinned {
            return lhs.result.memory.isPinned
        }
        let leftDate = lhs.result.memory.updatedAt ?? lhs.result.memory.createdAt
        let rightDate = rhs.result.memory.updatedAt ?? rhs.result.memory.createdAt
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        if lhs.originalIndex != rhs.originalIndex {
            return lhs.originalIndex < rhs.originalIndex
        }
        return lhs.result.memory.id < rhs.result.memory.id
    }

    private func lexicalScore(
        queryUnique: [String],
        queryTokenSet: Set<String>,
        memoryTokens: [String]
    ) -> Float {
        guard !queryUnique.isEmpty, !memoryTokens.isEmpty else { return 0 }
        let memorySet = Set(memoryTokens)
        let overlap = queryTokenSet.reduce(into: 0) { partialResult, token in
            if memorySet.contains(token) { partialResult += 1 }
        }
        return Float(overlap) / Float(queryUnique.count)
    }

    private func recencyScore(for memory: MemorySnapshot, now: Date, halfLifeDays: Double) -> Float {
        let reference = max(memory.createdAt, memory.updatedAt ?? memory.createdAt)
        let age = max(0, now.timeIntervalSince(reference))
        let halfLife = max(0.001, halfLifeDays) * 86_400
        return Float(exp(-age / halfLife))
    }

    private func removeDuplicates(_ candidates: [Candidate], threshold: Float) -> [Candidate] {
        let jaccardThreshold = min(1, max(0.5, threshold))
        var result: [Candidate] = []
        result.reserveCapacity(candidates.count)

        for candidate in candidates {
            let isDuplicate = result.contains { existing in
                if candidate.normalizedText == existing.normalizedText {
                    return true
                }
                guard !candidate.tokenSet.isEmpty, !existing.tokenSet.isEmpty else { return false }
                let intersection = candidate.tokenSet.intersection(existing.tokenSet).count
                let union = candidate.tokenSet.union(existing.tokenSet).count
                guard union > 0 else { return false }
                return Float(intersection) / Float(union) >= jaccardThreshold
            }
            if !isDuplicate { result.append(candidate) }
        }
        return result
    }

    private func selectWithBudgetAndDiversity(
        _ candidates: [Candidate],
        maxResults: Int,
        tokenBudget: Int?,
        diversityStrength: Float
    ) -> [Candidate] {
        guard maxResults > 0 else { return [] }
        var remaining = candidates
        var selected: [Candidate] = []
        var usedTokens = 0
        var usedSources: Set<String> = []

        while selected.count < maxResults && !remaining.isEmpty {
            let eligible = remaining.indices.filter { index in
                guard let tokenBudget else { return true }
                return usedTokens + remaining[index].result.tokenCount <= tokenBudget
            }
            guard !eligible.isEmpty else { break }

            var bestIndex = eligible[0]
            var bestAdjustedScore = adjustedScore(
                for: remaining[bestIndex],
                usedSources: usedSources,
                diversityStrength: diversityStrength
            )

            for index in eligible.dropFirst() {
                let adjusted = adjustedScore(
                    for: remaining[index],
                    usedSources: usedSources,
                    diversityStrength: diversityStrength
                )
                if adjusted > bestAdjustedScore {
                    bestIndex = index
                    bestAdjustedScore = adjusted
                } else if adjusted == bestAdjustedScore,
                          stableOrdering(remaining[index], remaining[bestIndex]) {
                    bestIndex = index
                }
            }

            let chosen = remaining.remove(at: bestIndex)
            selected.append(chosen)
            usedTokens += chosen.result.tokenCount
            usedSources.insert(chosen.sourceKey)
        }
        return selected
    }

    private func adjustedScore(
        for candidate: Candidate,
        usedSources: Set<String>,
        diversityStrength: Float
    ) -> Float {
        candidate.result.score - (usedSources.contains(candidate.sourceKey) ? diversityStrength : 0)
    }

    private func unique(_ tokens: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(tokens.count)
        for token in tokens where seen.insert(token).inserted {
            result.append(token)
        }
        return result
    }

    private func normalizedCosine(_ value: Float) -> Float {
        clamp01((value + 1) * 0.5)
    }

    private func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
