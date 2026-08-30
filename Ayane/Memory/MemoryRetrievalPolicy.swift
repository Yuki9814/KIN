import Foundation

enum ConversationMemoryIntent: String, Codable, CaseIterable, Sendable {
    case identity
    case preference
    case relationship
    case timeline
    case task
    case casual
}

struct MemoryRetrievalPlan: Equatable, Sendable {
    let intent: ConversationMemoryIntent
    let queryVariants: [String]
    let options: MemorySearchOptions
    let allowsSensitiveMemory: Bool
    let explanation: String
}

/// Intent-aware policy layered over the deterministic hybrid MemoryEngine.
/// It keeps extraction and storage unchanged, but adjusts retrieval budgets,
/// recency and query expansion so durable profile facts do not lose to recent
/// small talk and short anaphoric turns can still recover their subject.
struct MemoryRetrievalPolicy: Sendable {
    let engine: MemoryEngine

    init(engine: MemoryEngine = .shared) {
        self.engine = engine
    }

    func plan(
        for message: String,
        recentUserMessages: [String] = [],
        queryEmbedding: [Float]? = nil,
        isGroupChat: Bool = false,
        now: Date = Date()
    ) -> MemoryRetrievalPlan {
        let intent = classify(message)
        let settings = settings(for: intent)
        let variants = queryVariants(
            message: message,
            recentUserMessages: recentUserMessages,
            intent: intent
        )
        return MemoryRetrievalPlan(
            intent: intent,
            queryVariants: variants,
            options: MemorySearchOptions(
                maxResults: settings.maxResults,
                tokenBudget: settings.tokenBudget,
                now: now,
                queryEmbedding: queryEmbedding,
                includeExpired: false,
                minimumScore: settings.minimumScore,
                duplicateJaccardThreshold: 0.84,
                diversityStrength: settings.diversityStrength,
                recencyHalfLifeDays: settings.recencyHalfLifeDays,
                allowHighValueFallback: settings.allowHighValueFallback
            ),
            allowsSensitiveMemory: !isGroupChat,
            explanation: settings.explanation
        )
    }

    func retrieve(
        for message: String,
        recentUserMessages: [String] = [],
        from memories: [MemorySnapshot],
        queryEmbedding: [Float]? = nil,
        isGroupChat: Bool = false,
        now: Date = Date()
    ) -> [MemorySearchResult] {
        let plan = plan(
            for: message,
            recentUserMessages: recentUserMessages,
            queryEmbedding: queryEmbedding,
            isGroupChat: isGroupChat,
            now: now
        )
        let eligible = plan.allowsSensitiveMemory
            ? memories
            : memories.filter { !$0.isSensitive }
        guard !eligible.isEmpty else { return [] }

        struct Fused {
            var best: MemorySearchResult
            var score: Double
            var bestRank: Int
        }
        var fused: [String: Fused] = [:]
        for (variantIndex, query) in plan.queryVariants.enumerated() {
            var options = plan.options
            options.maxResults = min(max(plan.options.maxResults * 2, 8), 24)
            options.tokenBudget = nil
            options.queryEmbedding = variantIndex == 0 ? queryEmbedding : nil
            let results = engine.search(query, in: eligible, options: options)
            for (rank, result) in results.enumerated() {
                let reciprocalRank = 1.0 / Double(60 + rank + 1)
                let variantWeight = variantIndex == 0 ? 1.0 : max(0.55, 0.82 - Double(variantIndex) * 0.08)
                let contribution = variantWeight
                    * (reciprocalRank + Double(result.score) * 0.18)
                if var current = fused[result.id] {
                    current.score += contribution
                    current.bestRank = min(current.bestRank, rank)
                    if result.score > current.best.score {
                        current.best = result
                    }
                    fused[result.id] = current
                } else {
                    fused[result.id] = Fused(
                        best: result,
                        score: contribution,
                        bestRank: rank
                    )
                }
            }
        }

        guard let maximumFusion = fused.values.map(\.score).max(), maximumFusion > 0 else {
            return []
        }
        let ranked = fused.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.best.memory.isPinned != rhs.best.memory.isPinned {
                return lhs.best.memory.isPinned
            }
            if lhs.best.score != rhs.best.score { return lhs.best.score > rhs.best.score }
            if lhs.bestRank != rhs.bestRank { return lhs.bestRank < rhs.bestRank }
            return lhs.best.id < rhs.best.id
        }

        var selected: [MemorySearchResult] = []
        var usedTokens = 0
        var normalizedTexts = Set<String>()
        let budget = plan.options.tokenBudget ?? Int.max
        for candidate in ranked {
            guard selected.count < plan.options.maxResults else { break }
            let normalized = MemoryTokenizer.normalizedText(candidate.best.text)
            guard normalizedTexts.insert(normalized).inserted,
                  usedTokens + candidate.best.tokenCount <= budget else {
                continue
            }
            let fusedScore = Float(min(1, candidate.score / maximumFusion))
            let result = MemorySearchResult(
                memory: candidate.best.memory,
                score: min(1, candidate.best.score * 0.72 + fusedScore * 0.28),
                lexicalScore: candidate.best.lexicalScore,
                vectorScore: candidate.best.vectorScore,
                cosineSimilarity: candidate.best.cosineSimilarity,
                importanceScore: candidate.best.importanceScore,
                confidenceScore: candidate.best.confidenceScore,
                recencyScore: candidate.best.recencyScore,
                tokenCount: candidate.best.tokenCount,
                matchedTokens: candidate.best.matchedTokens
            )
            selected.append(result)
            usedTokens += result.tokenCount
        }
        return selected
    }

    func classify(_ message: String) -> ConversationMemoryIntent {
        let value = normalize(message)
        if containsAny(value, [
            "你记得我", "关于我", "我的资料", "我是谁", "我的名字", "我的工作",
            "my profile", "about me", "who am i"
        ]) {
            return .identity
        }
        if containsAny(value, [
            "我喜欢", "我不喜欢", "我的偏好", "最喜欢", "最爱", "最讨厌", "爱吃", "不爱吃",
            "my favorite", "i like", "i dislike", "my preference"
        ]) {
            return .preference
        }
        if containsAny(value, [
            "还记得", "之前我们", "我们以前", "第一次", "上次聊", "答应过",
            "remember when", "last time", "between us", "our relationship"
        ]) {
            return .relationship
        }
        if containsAny(value, [
            "什么时候", "哪一天", "哪天", "多久以前", "时间线", "后来发生",
            "when did", "what date", "timeline", "how long ago"
        ]) {
            return .timeline
        }
        if containsAny(value, [
            "帮我", "怎么做", "方案", "代码", "项目", "步骤", "优化", "分析",
            "help me", "how do i", "plan", "code", "project", "optimize"
        ]) {
            return .task
        }
        return .casual
    }

    private struct Settings {
        let maxResults: Int
        let tokenBudget: Int
        let minimumScore: Float
        let diversityStrength: Float
        let recencyHalfLifeDays: Double
        let allowHighValueFallback: Bool
        let explanation: String
    }

    private func settings(for intent: ConversationMemoryIntent) -> Settings {
        switch intent {
        case .identity:
            Settings(
                maxResults: 9,
                tokenBudget: 360,
                minimumScore: 0.07,
                diversityStrength: 0.16,
                recencyHalfLifeDays: 365,
                allowHighValueFallback: true,
                explanation: "身份问题优先稳定、明确且高价值的个人资料。"
            )
        case .preference:
            Settings(
                maxResults: 8,
                tokenBudget: 320,
                minimumScore: 0.07,
                diversityStrength: 0.18,
                recencyHalfLifeDays: 365,
                allowHighValueFallback: true,
                explanation: "偏好问题扩大时间窗口，并保留高置信长期事实。"
            )
        case .relationship:
            Settings(
                maxResults: 10,
                tokenBudget: 440,
                minimumScore: 0.06,
                diversityStrength: 0.20,
                recencyHalfLifeDays: 540,
                allowHighValueFallback: true,
                explanation: "关系回忆同时检索承诺、共同经历和长期连续性。"
            )
        case .timeline:
            Settings(
                maxResults: 9,
                tokenBudget: 380,
                minimumScore: 0.07,
                diversityStrength: 0.16,
                recencyHalfLifeDays: 720,
                allowHighValueFallback: true,
                explanation: "时间线问题降低近期偏置，防止旧事件被新消息淹没。"
            )
        case .task:
            Settings(
                maxResults: 6,
                tokenBudget: 240,
                minimumScore: 0.10,
                diversityStrength: 0.22,
                recencyHalfLifeDays: 60,
                allowHighValueFallback: false,
                explanation: "任务请求只召回少量直接相关约束，避免历史信息干扰执行。"
            )
        case .casual:
            Settings(
                maxResults: 4,
                tokenBudget: 160,
                minimumScore: 0.12,
                diversityStrength: 0.20,
                recencyHalfLifeDays: 45,
                allowHighValueFallback: false,
                explanation: "闲聊采用小预算，只带入高相关记忆。"
            )
        }
    }

    private func queryVariants(
        message: String,
        recentUserMessages: [String],
        intent: ConversationMemoryIntent
    ) -> [String] {
        let primary = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else { return [] }
        var values = [primary]
        let compact = normalize(primary)
        let needsContext = MemoryTokenizer.tokenCount(of: primary) <= 6
            || containsAny(compact, ["这个", "那个", "它", "她", "他", "之前的", "刚才的"])
        if needsContext {
            let context = recentUserMessages
                .suffix(2)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !context.isEmpty {
                values.append(context + "\n" + primary)
            }
        }

        if intent == .identity || intent == .preference || intent == .relationship {
            let stripped = stripRecallScaffolding(primary)
            if stripped != primary, !stripped.isEmpty {
                values.append(stripped)
            }
        }
        var seen = Set<String>()
        return values.filter { value in
            let key = normalize(value)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private func stripRecallScaffolding(_ value: String) -> String {
        var result = value
        let markers = [
            "你还记得", "你记得", "还记得", "能不能告诉我", "请告诉我",
            "do you remember", "can you tell me", "please tell me"
        ]
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func containsAny(_ value: String, _ markers: [String]) -> Bool {
        markers.contains(where: value.contains)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
