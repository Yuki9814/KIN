import Foundation

enum AffinityEventKind: String, Codable, CaseIterable, Sendable {
    case neutralMessage = "neutral_message"
    case appreciation
    case explicitAffection = "explicit_affection"
    case care
    case boundaryRespect = "boundary_respect"
    case apology
    case sharedMilestone = "shared_milestone"
    case conflict
    case rejection
    case boundaryViolation = "boundary_violation"
    case repeatedSpam = "repeated_spam"
}

struct AffinityDimensions: Codable, Equatable, Sendable {
    var warmth: Double
    var trust: Double
    var familiarity: Double
    var security: Double

    init(
        warmth: Double = 0,
        trust: Double = 0,
        familiarity: Double = 0,
        security: Double = 0
    ) {
        self.warmth = Self.score(warmth)
        self.trust = Self.score(trust)
        self.familiarity = Self.score(familiarity)
        self.security = Self.score(security)
    }

    static func seeded(fromLegacyScore score: Double) -> AffinityDimensions {
        let value = Self.score(score)
        return AffinityDimensions(
            warmth: value,
            trust: value,
            familiarity: value,
            security: value
        )
    }

    var overall: Double {
        Self.score(
            warmth * 0.35
                + trust * 0.30
                + familiarity * 0.20
                + security * 0.15
        )
    }

    fileprivate func applying(_ delta: AffinityDimensionDelta) -> AffinityDimensions {
        AffinityDimensions(
            warmth: warmth + delta.warmth,
            trust: trust + delta.trust,
            familiarity: familiarity + delta.familiarity,
            security: security + delta.security
        )
    }

    private static func score(_ value: Double) -> Double {
        guard value.isFinite else { return value.sign == .minus ? 0 : 100 }
        return min(100, max(0, value))
    }
}

struct AffinityDimensionDelta: Codable, Equatable, Sendable {
    var warmth: Double
    var trust: Double
    var familiarity: Double
    var security: Double

    static let zero = AffinityDimensionDelta(
        warmth: 0,
        trust: 0,
        familiarity: 0,
        security: 0
    )

    fileprivate func scaled(by value: Double) -> AffinityDimensionDelta {
        AffinityDimensionDelta(
            warmth: warmth * value,
            trust: trust * value,
            familiarity: familiarity * value,
            security: security * value
        )
    }
}

struct AffinityEvent: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let kind: AffinityEventKind
    let occurredAt: Date
    let fingerprint: String
    /// Allows trusted product events to scale a base rule without letting an
    /// arbitrary message directly choose its own score delta.
    let magnitude: Double

    init(
        idempotencyKey: String,
        kind: AffinityEventKind,
        occurredAt: Date = Date(),
        fingerprint: String? = nil,
        magnitude: Double = 1
    ) {
        self.idempotencyKey = idempotencyKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.occurredAt = occurredAt
        self.fingerprint = (fingerprint ?? kind.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.magnitude = magnitude.isFinite ? min(2, max(0, magnitude)) : 1
    }
}

struct AffinityLedgerState: Codable, Equatable, Sendable {
    var dimensions: AffinityDimensions
    var dayKey: String
    var positiveGainToday: Double
    var repetitions: [String: Int]
    var appliedEventKeys: [String]

    init(
        dimensions: AffinityDimensions = AffinityDimensions(),
        dayKey: String = "",
        positiveGainToday: Double = 0,
        repetitions: [String: Int] = [:],
        appliedEventKeys: [String] = []
    ) {
        self.dimensions = dimensions
        self.dayKey = dayKey
        self.positiveGainToday = max(0, positiveGainToday)
        self.repetitions = repetitions.mapValues { max(0, $0) }
        self.appliedEventKeys = Array(appliedEventKeys.suffix(500))
    }
}

struct AffinityProgressionChange: Equatable, Sendable {
    let eventKind: AffinityEventKind
    let previousDimensions: AffinityDimensions
    let nextDimensions: AffinityDimensions
    let dimensionDelta: AffinityDimensionDelta
    let legacyScoreDelta: Double
    let repetitionMultiplier: Double
    let wasDuplicate: Bool
    let reachedDailyPositiveCap: Bool
    let reason: String
}

struct AffinityProgressionResult: Equatable, Sendable {
    let state: AffinityLedgerState
    let change: AffinityProgressionChange
}

/// Event-ledger relationship progression. It replaces unconditional per-message
/// farming with idempotency, diminishing returns, daily caps and independent
/// trust/warmth/familiarity/security dimensions.
enum AffinityProgressionPolicy {
    static let dailyPositiveCap = 6.0
    static let maximumAppliedEventKeys = 500
    static let maximumRepetitionKeys = 64

    static func event(
        forMessage text: String,
        sourceEventID: UUID,
        occurredAt: Date = Date()
    ) -> AffinityEvent {
        let classification = classifyMessage(text)
        return AffinityEvent(
            idempotencyKey: "message:\(sourceEventID.uuidString.lowercased())",
            kind: classification.kind,
            occurredAt: occurredAt,
            fingerprint: classification.fingerprint
        )
    }

    static func classifyMessage(_ text: String) -> (
        kind: AffinityEventKind,
        fingerprint: String
    ) {
        let value = normalize(text)
        guard !value.isEmpty else { return (.neutralMessage, "empty") }

        let relationalNegative = [
            "我不喜欢你", "我讨厌你", "别再这样", "不要再联系", "离我远点",
            "不想理你", "你让我失望", "i hate you", "leave me alone"
        ]
        if relationalNegative.contains(where: value.contains) {
            return (.rejection, "relational_rejection")
        }
        let apologies = ["对不起", "抱歉", "是我不对", "我错了", "sorry", "my fault"]
        if apologies.contains(where: value.contains) {
            return (.apology, "apology")
        }
        let care = [
            "注意休息", "别太累", "好好吃饭", "照顾好自己", "我担心你",
            "辛苦了", "take care", "rest well"
        ]
        if care.contains(where: value.contains) {
            return (.care, "care")
        }
        let strongAffection = [
            "我爱你", "最喜欢你", "离不开你", "想一直陪着你",
            "i love you", "love you so much"
        ]
        if strongAffection.contains(where: value.contains) {
            return (.explicitAffection, "explicit_affection")
        }
        let appreciation = [
            "谢谢你", "你真好", "喜欢你", "很懂我", "有你真好",
            "thank you", "appreciate you", "like you"
        ]
        if appreciation.contains(where: value.contains) {
            return (.appreciation, "appreciation")
        }
        return (.neutralMessage, "neutral")
    }

    static func applying(
        _ event: AffinityEvent,
        to inputState: AffinityLedgerState,
        timeZone: TimeZone = .current
    ) -> AffinityProgressionResult {
        var state = normalizedForDay(inputState, date: event.occurredAt, timeZone: timeZone)
        let previous = state.dimensions
        let eventKey = event.idempotencyKey
        if !eventKey.isEmpty, state.appliedEventKeys.contains(eventKey) {
            return AffinityProgressionResult(
                state: state,
                change: AffinityProgressionChange(
                    eventKind: event.kind,
                    previousDimensions: previous,
                    nextDimensions: previous,
                    dimensionDelta: .zero,
                    legacyScoreDelta: 0,
                    repetitionMultiplier: 0,
                    wasDuplicate: true,
                    reachedDailyPositiveCap: state.positiveGainToday >= dailyPositiveCap,
                    reason: "同一关系事件已经处理过，本次不重复计分。"
                )
            )
        }

        let base = baseDelta(for: event.kind).scaled(by: event.magnitude)
        let isPositive = weightedMagnitude(base) > 0
        let fingerprint = event.fingerprint.isEmpty ? event.kind.rawValue : event.fingerprint
        let repeatCount = state.repetitions[fingerprint, default: 0]
        let repetitionMultiplier: Double
        if isPositive {
            repetitionMultiplier = max(0.15, pow(0.55, Double(repeatCount)))
        } else {
            repetitionMultiplier = 1
        }

        let saturationMultiplier = isPositive
            ? max(0.20, 1 - previous.overall / 120)
            : 1
        var applied = base.scaled(by: repetitionMultiplier * saturationMultiplier)
        var hitCap = false
        if isPositive {
            let remaining = max(0, dailyPositiveCap - state.positiveGainToday)
            let projected = max(0, weightedMagnitude(applied))
            if projected > remaining {
                let capMultiplier = projected > 0 ? remaining / projected : 0
                applied = applied.scaled(by: capMultiplier)
                hitCap = true
            }
        }

        let next = previous.applying(applied)
        let legacyDelta = next.overall - previous.overall
        if legacyDelta > 0 {
            state.positiveGainToday += legacyDelta
        }
        state.dimensions = next
        state.repetitions[fingerprint] = repeatCount + 1
        trimRepetitions(&state.repetitions)
        if !eventKey.isEmpty {
            state.appliedEventKeys.append(eventKey)
            if state.appliedEventKeys.count > maximumAppliedEventKeys {
                state.appliedEventKeys.removeFirst(
                    state.appliedEventKeys.count - maximumAppliedEventKeys
                )
            }
        }

        return AffinityProgressionResult(
            state: state,
            change: AffinityProgressionChange(
                eventKind: event.kind,
                previousDimensions: previous,
                nextDimensions: next,
                dimensionDelta: applied,
                legacyScoreDelta: legacyDelta,
                repetitionMultiplier: repetitionMultiplier,
                wasDuplicate: false,
                reachedDailyPositiveCap: hitCap || state.positiveGainToday >= dailyPositiveCap,
                reason: reason(
                    for: event.kind,
                    appliedDelta: legacyDelta,
                    repeated: repeatCount > 0,
                    capped: hitCap
                )
            )
        )
    }

    private static func baseDelta(for kind: AffinityEventKind) -> AffinityDimensionDelta {
        switch kind {
        case .neutralMessage:
            return .zero
        case .appreciation:
            return AffinityDimensionDelta(warmth: 1.4, trust: 0.6, familiarity: 0.5, security: 0.2)
        case .explicitAffection:
            return AffinityDimensionDelta(warmth: 2.8, trust: 0.8, familiarity: 0.9, security: 0.5)
        case .care:
            return AffinityDimensionDelta(warmth: 1.2, trust: 1.4, familiarity: 0.4, security: 1.0)
        case .boundaryRespect:
            return AffinityDimensionDelta(warmth: 0.5, trust: 2.0, familiarity: 0.4, security: 1.8)
        case .apology:
            return AffinityDimensionDelta(warmth: 0.4, trust: 1.2, familiarity: 0.2, security: 1.0)
        case .sharedMilestone:
            return AffinityDimensionDelta(warmth: 1.4, trust: 1.0, familiarity: 2.2, security: 0.8)
        case .conflict:
            return AffinityDimensionDelta(warmth: -1.5, trust: -1.0, familiarity: 0, security: -1.0)
        case .rejection:
            return AffinityDimensionDelta(warmth: -3.0, trust: -1.2, familiarity: 0, security: -2.0)
        case .boundaryViolation:
            return AffinityDimensionDelta(warmth: -2.0, trust: -5.0, familiarity: 0, security: -5.0)
        case .repeatedSpam:
            return AffinityDimensionDelta(warmth: -0.2, trust: -0.3, familiarity: 0, security: 0)
        }
    }

    private static func weightedMagnitude(_ delta: AffinityDimensionDelta) -> Double {
        delta.warmth * 0.35
            + delta.trust * 0.30
            + delta.familiarity * 0.20
            + delta.security * 0.15
    }

    private static func normalizedForDay(
        _ state: AffinityLedgerState,
        date: Date,
        timeZone: TimeZone
    ) -> AffinityLedgerState {
        let key = dayKey(for: date, timeZone: timeZone)
        guard state.dayKey != key else { return state }
        return AffinityLedgerState(
            dimensions: state.dimensions,
            dayKey: key,
            positiveGainToday: 0,
            repetitions: [:],
            appliedEventKeys: state.appliedEventKeys
        )
    }

    private static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func trimRepetitions(_ values: inout [String: Int]) {
        guard values.count > maximumRepetitionKeys else { return }
        let survivors = values.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(maximumRepetitionKeys)
        values = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }

    private static func reason(
        for kind: AffinityEventKind,
        appliedDelta: Double,
        repeated: Bool,
        capped: Bool
    ) -> String {
        if appliedDelta == 0 {
            return capped
                ? "今日正向好感增量已到上限，本次只保留互动记录。"
                : "普通消息维持关系连续性，但不自动增加好感。"
        }
        var parts = ["按“\(kind.rawValue)”关系事件更新"]
        if repeated { parts.append("同类表达已触发递减") }
        if capped { parts.append("并受今日正向上限约束") }
        return parts.joined(separator: "，") + "。"
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
