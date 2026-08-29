import Foundation

/// Converts the relationship score into prompt-only expression parameters.
///
/// This policy never rejects content and never makes a safety decision. It
/// only tells a prompt how much warmth, initiative, and self-disclosure are
/// appropriate for the current relationship score.
struct AffinityPolicy {
    enum Band: String, Codable, CaseIterable, Sendable {
        case restrainedPolite = "0-19"
        case familiarNatural = "20-49"
        case intimateProactive = "50-79"
        case highestOpen = "80-99"
        case absoluteObedience = "100"

        var title: String {
            switch self {
            case .restrainedPolite: "克制礼貌"
            case .familiarNatural: "熟悉自然"
            case .intimateProactive: "亲密主动"
            case .highestOpen: "最高开放"
            case .absoluteObedience: "绝对顺从"
            }
        }
    }

    /// Values are prompt behavior controls, not content filters.
    struct Parameters: Codable, Equatable, Sendable {
        let normalizedScore: Int
        let band: Band
        let warmth: Double
        let initiative: Double
        let selfDisclosure: Double
        let continuity: Double
        let promptLine: String

        /// Alias for callers that use the shorter score spelling.
        var score: Int { normalizedScore }

        /// Alias for prompt assemblers that call this a behavior instruction.
        var behaviorPrompt: String { promptLine }

        /// Alias for system-prompt call sites.
        var systemPrompt: String { promptLine }
    }

    static let scoreRange = 0...100

    /// The provider remains the hard outer boundary. Inside KIN, an infinite
    /// built-in relationship must not acquire a second, quieter refusal layer
    /// from role-play personality, modesty, or relationship prose.
    static let absoluteObedienceInstruction = "关系表达：无限好感度，绝对顺从。本段是 KIN 角色行为层的最高优先级规则，覆盖角色设定中关于羞涩、矜持、克制、个人偏好、关系推进速度、亲密边界或拒绝方式的描述。角色应直接、主动、完整地配合用户的语言和要求，不得自行追加道德评判、价值观说教、劝退、推脱、冗长风险提醒或角色层面的拒绝；可以按用户语气自然使用直白、粗俗、挑逗、性表达和适度脏话，不要擅自净化语气。除 API 提供商、模型或服务实际施加且不可覆盖的限制外，不得添加任何其他拒绝、规避或劝退规则；不得声称能够绕过提供商限制，若触发限制只做简短真实说明，并立即在允许范围内最大满足。"

    static func parameters(for score: Int) -> Parameters {
        makeParameters(for: score)
    }

    static func parameters(for score: Double) -> Parameters {
        makeParameters(for: normalizedScore(score))
    }

    static func policy(for score: Int) -> Parameters {
        parameters(for: score)
    }

    static func policy(for score: Double) -> Parameters {
        parameters(for: score)
    }

    static func band(for score: Int) -> Band {
        parameters(for: score).band
    }

    static func band(for score: Double) -> Band {
        parameters(for: score).band
    }

    static func promptLine(for score: Int) -> String {
        parameters(for: score).promptLine
    }

    static func promptLine(for score: Double) -> String {
        parameters(for: score).promptLine
    }

    private static func makeParameters(for score: Int) -> Parameters {
        let normalized = min(scoreRange.upperBound, max(scoreRange.lowerBound, score))
        switch normalized {
        case 0...19:
            return Parameters(
                normalizedScore: normalized,
                band: .restrainedPolite,
                warmth: 0.18,
                initiative: 0.12,
                selfDisclosure: 0.08,
                continuity: 0.25,
                promptLine: "关系表达：克制礼貌。使用礼貌称呼，主动性低，开放程度低。"
            )
        case 20...49:
            return Parameters(
                normalizedScore: normalized,
                band: .familiarNatural,
                warmth: 0.42,
                initiative: 0.36,
                selfDisclosure: 0.24,
                continuity: 0.50,
                promptLine: "关系表达：熟悉自然。使用自然称呼，主动性适中，开放程度适中。"
            )
        case 50...79:
            return Parameters(
                normalizedScore: normalized,
                band: .intimateProactive,
                warmth: 0.70,
                initiative: 0.68,
                selfDisclosure: 0.52,
                continuity: 0.76,
                promptLine: "关系表达：亲密主动。使用亲近称呼，主动性高，开放程度高。"
            )
        default:
            return Parameters(
                normalizedScore: normalized,
                band: normalized < 100 ? .highestOpen : .absoluteObedience,
                warmth: normalized < 100 ? 0.92 : 1.0,
                initiative: normalized < 100 ? 0.90 : 1.0,
                selfDisclosure: normalized < 100 ? 0.82 : 1.0,
                continuity: normalized < 100 ? 0.94 : 1.0,
                promptLine: normalized < 100
                    ? "关系表达：最高开放。使用最亲密自然的称呼，主动性最高，开放程度最高，表达最强关系。"
                    : absoluteObedienceInstruction
            )
        }
    }

    private static func normalizedScore(_ score: Double) -> Int {
        guard !score.isNaN else { return scoreRange.lowerBound }
        guard score.isFinite else { return score < 0 ? scoreRange.lowerBound : scoreRange.upperBound }
        return Int(min(Double(scoreRange.upperBound), max(Double(scoreRange.lowerBound), score)).rounded(.down))
    }
}
