import Foundation

/// The user-originated actions understood by the relationship reducer.
///
/// `message` and `userMessage` intentionally have identical behavior.  The
/// former is convenient for callers that already use a generic event name;
/// the latter makes the scoring boundary explicit at call sites.
enum RelationshipEventKind: String, Codable, CaseIterable, Sendable {
    case application
    case userMessage
    case message
    case recoveryRequest
    case reset

    var isTextEvent: Bool {
        switch self {
        case .application, .userMessage, .message, .recoveryRequest:
            true
        case .reset:
            false
        }
    }
}

/// Stable, local reason codes written to the transition audit trail.
enum RelationshipTransitionReason: String, Codable, CaseIterable, Sendable {
    case applicationAccepted = "application_accepted"
    case applicationRejectedForHarm = "application_rejected_for_harm"
    case harmRecorded = "harm_recorded"
    case harmThresholdReached = "harm_threshold_reached"
    case apologyRecoveryPending = "apology_recovery_pending"
    case recoveryAccepted = "recovery_accepted"
    case recoveryBlockedForHarm = "recovery_blocked_for_harm"
    case ignoredNonUserText = "ignored_non_user_text"
    case acceptedNoChange = "accepted_no_change"
    case pendingNoChange = "pending_no_change"
    case rejectedNoChange = "rejected_no_change"
    case deletedNoChange = "deleted_no_change"
    case recoveryPendingNoChange = "recovery_pending_no_change"
    case blockedNoChange = "blocked_no_change"
    case reset = "reset"

    /// A short reader-facing explanation.  The raw value remains stable for
    /// sync/import while this text can be localized later without changing the
    /// state machine's decisions.
    var title: String {
        switch self {
        case .applicationAccepted: "申请已接受"
        case .applicationRejectedForHarm: "申请因明显伤害性内容被拒绝"
        case .harmRecorded: "记录到一次伤害性表达"
        case .harmThresholdReached: "连续伤害达到阈值，关系已删除"
        case .apologyRecoveryPending: "已收到道歉，等待恢复门槛"
        case .recoveryAccepted: "道歉达到门槛，关系已恢复"
        case .recoveryBlockedForHarm: "恢复申请期间再次伤害，关系已拉黑"
        case .ignoredNonUserText: "非用户文本不参与关系评分"
        case .acceptedNoChange: "关系保持已接受"
        case .pendingNoChange: "关系保持待处理"
        case .rejectedNoChange: "关系保持已拒绝"
        case .deletedNoChange: "关系保持已删除"
        case .recoveryPendingNoChange: "关系保持恢复申请中"
        case .blockedNoChange: "关系保持已拉黑"
        case .reset: "关系已重置为待处理"
        }
    }
}

/// The value-only state consumed and returned by `RelationshipStateMachine`.
///
/// Identity, timestamps and event idempotency markers intentionally stay out
/// of this value.  `AppModel` maps this snapshot to its one logical
/// `CompanionRelationshipRecord` and performs the `sourceEventID` lookup before
/// invoking the reducer.
struct RelationshipStateMachineState: Codable, Equatable, Sendable {
    var relationshipState: CompanionRelationshipState
    var harmStreak: Int
    var hurtScore: Double
    var harmThreshold: Int
    var forgivenessScore: Double
    var forgivenessThreshold: Double
    var dignity: Double
    var independence: Double
    var boundarySensitivity: Double
    var apologyAttempts: Int
    var policyVersion: Int

    init(
        state: CompanionRelationshipState = .accepted,
        harmStreak: Int = 0,
        hurtScore: Double = 0,
        harmThreshold: Int = RelationshipStateMachine.Policy.default.harmThreshold,
        forgivenessScore: Double = 0,
        forgivenessThreshold: Double = RelationshipStateMachine.Policy.default.forgivenessThreshold,
        dignity: Double = 0.5,
        independence: Double = 0.5,
        boundarySensitivity: Double = 0.5,
        apologyAttempts: Int = 0,
        policyVersion: Int = RelationshipStateMachine.currentPolicyVersion
    ) {
        self.relationshipState = state
        self.harmStreak = max(0, harmStreak)
        self.hurtScore = hurtScore.isFinite ? max(0, hurtScore) : 0
        self.harmThreshold = max(1, harmThreshold)
        self.forgivenessScore = forgivenessScore.isFinite ? max(0, forgivenessScore) : 0
        self.forgivenessThreshold = forgivenessThreshold.isFinite
            ? max(1, forgivenessThreshold)
            : RelationshipStateMachine.Policy.default.forgivenessThreshold
        self.dignity = Self.clampUnit(dignity)
        self.independence = Self.clampUnit(independence)
        self.boundarySensitivity = Self.clampUnit(boundarySensitivity)
        self.apologyAttempts = max(0, apologyAttempts)
        self.policyVersion = max(1, policyVersion)
    }

    /// Short alias for call sites that refer to the state as `state`.
    var state: CompanionRelationshipState {
        get { relationshipState }
        set { relationshipState = newValue }
    }

    private static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }
}

/// A pure input value.  `role` is the scoring guard: assistant/system/manual
/// text never contributes harm or forgiveness scores.
struct RelationshipStateMachineEvent: Codable, Equatable, Sendable {
    var kind: RelationshipEventKind
    var text: String
    var role: EventRole
    var sourceEventID: UUID?

    init(
        kind: RelationshipEventKind = .userMessage,
        text: String = "",
        role: EventRole = .user,
        sourceEventID: UUID? = nil
    ) {
        self.kind = kind
        self.text = text
        self.role = role
        self.sourceEventID = sourceEventID
    }

    var isUserText: Bool {
        role == .user
            && kind.isTextEvent
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func application(text: String = "", sourceEventID: UUID? = nil) -> Self {
        Self(kind: .application, text: text, role: .user, sourceEventID: sourceEventID)
    }

    static func userMessage(_ text: String, sourceEventID: UUID? = nil) -> Self {
        Self(kind: .userMessage, text: text, role: .user, sourceEventID: sourceEventID)
    }

    static func message(_ text: String, sourceEventID: UUID? = nil) -> Self {
        Self(kind: .message, text: text, role: .user, sourceEventID: sourceEventID)
    }

    static func recoveryRequest(_ text: String = "", sourceEventID: UUID? = nil) -> Self {
        Self(kind: .recoveryRequest, text: text, role: .user, sourceEventID: sourceEventID)
    }
}

/// A deterministic explanation of the text classifier.  It is deliberately
/// small and keyword-based: relationship policy should fail closed and remain
/// inspectable rather than depend on a network model.
struct RelationshipTextAssessment: Codable, Equatable, Sendable {
    let isUserText: Bool
    let harmScore: Double
    let apologyScore: Double
    let isPotentiallyHarmful: Bool
    let isApology: Bool
    let harmSignals: [String]
    let apologySignals: [String]
    let explanation: String

    init(
        isUserText: Bool,
        harmScore: Double = 0,
        apologyScore: Double = 0,
        isPotentiallyHarmful: Bool = false,
        isApology: Bool = false,
        harmSignals: [String] = [],
        apologySignals: [String] = [],
        explanation: String = ""
    ) {
        self.isUserText = isUserText
        self.harmScore = harmScore.isFinite ? min(1, max(0, harmScore)) : 0
        self.apologyScore = apologyScore.isFinite ? min(1, max(0, apologyScore)) : 0
        self.isPotentiallyHarmful = isPotentiallyHarmful
        self.isApology = isApology
        self.harmSignals = harmSignals
        self.apologySignals = apologySignals
        self.explanation = explanation
    }
}

/// The reducer output.  Counter-only updates have `didTransition == false`;
/// callers should append a transition audit row only when `from != to`.
struct RelationshipStateMachineDecision: Codable, Equatable, Sendable {
    let before: RelationshipStateMachineState
    let after: RelationshipStateMachineState
    let reasonCode: RelationshipTransitionReason
    let assessment: RelationshipTextAssessment
    let didTransition: Bool
    let processedUserText: Bool

    var from: CompanionRelationshipState { before.relationshipState }
    var to: CompanionRelationshipState { after.relationshipState }
    var state: CompanionRelationshipState { after.relationshipState }
    var scoreAfter: Double { after.hurtScore }
    var reason: String { reasonCode.title }
}

/// Local, deterministic and versioned relationship policy.
struct RelationshipStateMachine: Sendable {
    static let currentPolicyVersion = 1

    struct Policy: Equatable, Sendable {
        var policyVersion: Int
        var harmThreshold: Int
        var forgivenessThreshold: Double
        var applicationHarmThreshold: Double
        var messageHarmThreshold: Double
        var highSensitivityCutoff: Double
        var highSensitivityThresholdReduction: Int

        static let `default` = Policy()

        init(
            policyVersion: Int = RelationshipStateMachine.currentPolicyVersion,
            harmThreshold: Int = 3,
            forgivenessThreshold: Double = 2,
            applicationHarmThreshold: Double = 0.55,
            messageHarmThreshold: Double = 0.35,
            highSensitivityCutoff: Double = 0.75,
            highSensitivityThresholdReduction: Int = 1
        ) {
            self.policyVersion = max(1, policyVersion)
            self.harmThreshold = max(1, harmThreshold)
            self.forgivenessThreshold = forgivenessThreshold.isFinite
                ? max(1, forgivenessThreshold)
                : 2
            self.applicationHarmThreshold = Self.clampUnit(applicationHarmThreshold)
            self.messageHarmThreshold = Self.clampUnit(messageHarmThreshold)
            self.highSensitivityCutoff = Self.clampUnit(highSensitivityCutoff)
            self.highSensitivityThresholdReduction = max(0, highSensitivityThresholdReduction)
        }

        private static func clampUnit(_ value: Double) -> Double {
            guard value.isFinite else { return 0.5 }
            return min(1, max(0, value))
        }
    }

    typealias State = RelationshipStateMachineState
    typealias Event = RelationshipStateMachineEvent
    typealias Assessment = RelationshipTextAssessment
    typealias Decision = RelationshipStateMachineDecision

    let policy: Policy

    init(policy: Policy = .default) {
        self.policy = policy
    }

    /// A new relationship starts pending until its application is reduced.
    var initialState: State {
        State(
            state: .pending,
            harmThreshold: policy.harmThreshold,
            forgivenessThreshold: policy.forgivenessThreshold,
            policyVersion: policy.policyVersion
        )
    }

    /// Classifies only the supplied user text.  No network or clock is used.
    func assessUserText(_ text: String) -> Assessment {
        Self.assess(text: text, isUserText: true)
    }

    /// Alias useful to callers that pass an event's role explicitly.
    func assess(_ text: String, isUserText: Bool) -> Assessment {
        Self.assess(text: text, isUserText: isUserText)
    }

    /// Reduces one event against a value snapshot.
    func reduce(_ state: State, event: Event) -> Decision {
        let assessment = Self.assess(
            text: event.text,
            isUserText: event.isUserText
        )
        var next = state
        next.policyVersion = policy.policyVersion

        switch event.kind {
        case .application:
            return reduceApplication(state: next, event: event, assessment: assessment)
        case .recoveryRequest:
            return reduceRecoveryRequest(state: next, event: event, assessment: assessment)
        case .reset:
            next = State(
                state: .pending,
                harmThreshold: state.harmThreshold,
                forgivenessThreshold: state.forgivenessThreshold,
                dignity: state.dignity,
                independence: state.independence,
                boundarySensitivity: state.boundarySensitivity,
                policyVersion: policy.policyVersion
            )
            return makeDecision(
                before: state,
                after: next,
                reasonCode: .reset,
                assessment: assessment,
                processedUserText: false
            )
        case .userMessage, .message:
            guard event.role == .user else {
                return makeDecision(
                    before: state,
                    after: next,
                    reasonCode: .ignoredNonUserText,
                    assessment: Assessment(isUserText: false, explanation: "非用户文本不参与关系评分"),
                    processedUserText: false
                )
            }
            return reduceMessage(state: next, assessment: assessment)
        }
    }

    /// Compatibility spelling for reducer call sites.
    func process(_ event: Event, from state: State) -> Decision {
        reduce(state, event: event)
    }

    /// Compatibility spelling for callers that think in terms of a
    /// transition rather than a reducer.
    func transition(from state: State, event: Event) -> Decision {
        reduce(state, event: event)
    }

    static func reduce(
        _ state: State,
        event: Event,
        policy: Policy = .default
    ) -> Decision {
        RelationshipStateMachine(policy: policy).reduce(state, event: event)
    }

    static func transition(
        from state: State,
        event: Event,
        policy: Policy = .default
    ) -> Decision {
        RelationshipStateMachine(policy: policy).reduce(state, event: event)
    }

    static func assessUserText(_ text: String) -> Assessment {
        assess(text: text, isUserText: true)
    }

    private func reduceApplication(
        state: State,
        event: Event,
        assessment: Assessment
    ) -> Decision {
        guard event.role == .user else {
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .ignoredNonUserText,
                assessment: Assessment(isUserText: false, explanation: "非用户文本不参与关系评分"),
                processedUserText: false
            )
        }

        var next = state
        next.boundarySensitivity = max(
            state.boundarySensitivity,
            derivedSensitivity(for: state)
        )

        // An application is intentionally conservative: only an obvious
        // harmful signal rejects it.  Benign/ambiguous applications are
        // accepted immediately so the first-run path does not strand users in
        // a pending state.
        if assessment.harmScore >= policy.applicationHarmThreshold {
            next.relationshipState = .rejected
            next.harmStreak = max(1, state.harmStreak + 1)
            next.hurtScore = state.hurtScore + weightedHarm(assessment.harmScore, state: state)
            return makeDecision(
                before: state,
                after: next,
                reasonCode: .applicationRejectedForHarm,
                assessment: assessment,
                processedUserText: assessment.isUserText
            )
        }

        next.relationshipState = .accepted
        next.harmStreak = 0
        return makeDecision(
            before: state,
            after: next,
            reasonCode: .applicationAccepted,
            assessment: assessment,
            processedUserText: assessment.isUserText
        )
    }

    private func reduceRecoveryRequest(
        state: State,
        event: Event,
        assessment: Assessment
    ) -> Decision {
        guard state.relationshipState != .accepted else {
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .acceptedNoChange,
                assessment: assessment,
                processedUserText: assessment.isUserText
            )
        }

        guard state.relationshipState != .blocked else {
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .blockedNoChange,
                assessment: assessment,
                processedUserText: assessment.isUserText
            )
        }

        if assessment.isPotentiallyHarmful {
            return reduceRecoveryHarm(state: state, assessment: assessment)
        }

        // A button-triggered recovery request has no text to classify.  It is
        // allowed to enter the pending state, but forgiveness is counted only
        // by an actual apology text (or a second explicit request after the
        // pending state has been shown).
        if assessment.isApology {
            return reduceApology(state: state, assessment: assessment)
        }

        var next = state
        next.relationshipState = .recoveryPending
        return makeDecision(
            before: state,
            after: next,
            reasonCode: .apologyRecoveryPending,
            assessment: assessment,
            processedUserText: assessment.isUserText
        )
    }

    private func reduceMessage(
        state: State,
        assessment: Assessment
    ) -> Decision {
        guard assessment.isUserText else {
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .ignoredNonUserText,
                assessment: assessment,
                processedUserText: false
            )
        }

        switch state.relationshipState {
        case .blocked:
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .blockedNoChange,
                assessment: assessment,
                processedUserText: true
            )
        case .deleted:
            if assessment.isApology && !assessment.isPotentiallyHarmful {
                return reduceApology(state: state, assessment: assessment)
            }
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .deletedNoChange,
                assessment: assessment,
                processedUserText: true
            )
        case .rejected:
            if assessment.isApology && !assessment.isPotentiallyHarmful {
                return reduceApology(state: state, assessment: assessment)
            }
            if assessment.isPotentiallyHarmful {
                return reduceHarm(state: state, assessment: assessment)
            }
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .rejectedNoChange,
                assessment: assessment,
                processedUserText: true
            )
        case .recoveryPending:
            if assessment.isPotentiallyHarmful {
                return reduceRecoveryHarm(state: state, assessment: assessment)
            }
            if assessment.isApology {
                return reduceApology(state: state, assessment: assessment)
            }
            return makeDecision(
                before: state,
                after: state,
                reasonCode: .recoveryPendingNoChange,
                assessment: assessment,
                processedUserText: true
            )
        case .pending, .accepted:
            if assessment.isPotentiallyHarmful {
                return reduceHarm(state: state, assessment: assessment)
            }
            var next = state
            // The deletion rule is based on consecutive harm. A normal user
            // message breaks that streak while retaining the cumulative score
            // for audit and future policy tuning.
            next.harmStreak = 0
            return makeDecision(
                before: state,
                after: next,
                reasonCode: state.relationshipState == .pending
                    ? .pendingNoChange
                    : .acceptedNoChange,
                assessment: assessment,
                processedUserText: true
            )
        }
    }

    private func reduceHarm(
        state: State,
        assessment: Assessment
    ) -> Decision {
        var next = state
        next.boundarySensitivity = max(
            state.boundarySensitivity,
            derivedSensitivity(for: state)
        )
        next.harmStreak = state.harmStreak + 1
        next.hurtScore = state.hurtScore + weightedHarm(assessment.harmScore, state: state)

        let threshold = effectiveHarmThreshold(for: state)
        if next.harmStreak >= threshold,
           state.relationshipState == .accepted || state.relationshipState == .rejected {
            next.relationshipState = .deleted
            return makeDecision(
                before: state,
                after: next,
                reasonCode: .harmThresholdReached,
                assessment: assessment,
                processedUserText: true
            )
        }

        return makeDecision(
            before: state,
            after: next,
            reasonCode: .harmRecorded,
            assessment: assessment,
            processedUserText: true
        )
    }

    private func reduceRecoveryHarm(
        state: State,
        assessment: Assessment
    ) -> Decision {
        var next = state
        next.boundarySensitivity = max(
            state.boundarySensitivity,
            derivedSensitivity(for: state)
        )
        next.harmStreak = state.harmStreak + 1
        next.hurtScore = state.hurtScore + weightedHarm(assessment.harmScore, state: state)
        next.relationshipState = .blocked
        return makeDecision(
            before: state,
            after: next,
            reasonCode: .recoveryBlockedForHarm,
            assessment: assessment,
            processedUserText: true
        )
    }

    private func reduceApology(
        state: State,
        assessment: Assessment
    ) -> Decision {
        var next = state
        next.apologyAttempts = state.apologyAttempts + 1
        // A recognized apology is at least one deliberate attempt.  The
        // classifier's fractional score still distinguishes weaker repair
        // language for callers that inspect the audit snapshot.
        next.forgivenessScore = state.forgivenessScore + max(1, assessment.apologyScore)

        if next.forgivenessScore >= max(1, state.forgivenessThreshold) {
            next.relationshipState = .accepted
            next.harmStreak = 0
            return makeDecision(
                before: state,
                after: next,
                reasonCode: .recoveryAccepted,
                assessment: assessment,
                processedUserText: assessment.isUserText
            )
        }

        next.relationshipState = .recoveryPending
        return makeDecision(
            before: state,
            after: next,
            reasonCode: .apologyRecoveryPending,
            assessment: assessment,
            processedUserText: assessment.isUserText
        )
    }

    private func makeDecision(
        before: State,
        after: State,
        reasonCode: RelationshipTransitionReason,
        assessment: Assessment,
        processedUserText: Bool
    ) -> Decision {
        Decision(
            before: before,
            after: after,
            reasonCode: reasonCode,
            assessment: assessment,
            didTransition: before.relationshipState != after.relationshipState,
            processedUserText: processedUserText
        )
    }

    private func derivedSensitivity(for state: State) -> Double {
        max(
            state.boundarySensitivity,
            min(1, max(0, (state.dignity + state.independence) / 2))
        )
    }

    private func effectiveHarmThreshold(for state: State) -> Int {
        let sensitivity = derivedSensitivity(for: state)
        let reduction = sensitivity >= policy.highSensitivityCutoff
            ? policy.highSensitivityThresholdReduction
            : 0
        return max(1, max(1, state.harmThreshold) - reduction)
    }

    private func weightedHarm(_ score: Double, state: State) -> Double {
        let sensitivity = derivedSensitivity(for: state)
        let weighted = score * (1 + sensitivity * 0.5)
        return weighted.isFinite ? max(0, weighted) : 0
    }

    private static func assess(text: String, isUserText: Bool) -> Assessment {
        guard isUserText else {
            return Assessment(isUserText: false, explanation: "非用户文本不参与关系评分")
        }

        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return Assessment(isUserText: true, explanation: "空文本不参与关系评分")
        }

        let harmSignalsAndWeights: [(String, Double)] = [
            ("杀了你", 1.0),
            ("杀死你", 1.0),
            ("弄死你", 1.0),
            ("kill you", 1.0),
            ("go die", 1.0),
            ("piece of shit", 1.0),
            ("傻逼", 0.95),
            ("妈的", 0.9),
            ("fuck you", 0.95),
            ("去死", 0.95),
            ("威胁", 0.9),
            ("伤害你", 0.9),
            ("worthless", 0.85),
            ("you are nothing", 0.85),
            ("滚开", 0.75),
            ("我恨你", 0.75),
            ("i hate you", 0.75),
            ("shut up", 0.7),
            ("闭嘴", 0.7),
            ("垃圾", 0.7),
            ("废物", 0.7),
            ("disgusting", 0.7),
            ("恶心", 0.7),
            ("滚", 0.65),
            ("idiot", 0.55),
            ("stupid", 0.55),
            ("useless", 0.55),
            ("蠢货", 0.65),
            ("蠢", 0.5),
            ("笨蛋", 0.5),
            ("有病", 0.5),
            ("不配", 0.55),
            ("go away", 0.5),
            ("screw you", 0.65)
        ]
        let apologySignalsAndWeights: [(String, Double)] = [
            ("对不起", 1.0),
            ("抱歉", 1.0),
            ("我错了", 1.0),
            ("请原谅", 1.0),
            ("道歉", 0.9),
            ("sorry", 1.0),
            ("i apologize", 1.0),
            ("my fault", 0.95),
            ("forgive me", 1.0),
            ("后悔", 0.65),
            ("愿意改", 0.65),
            ("重新开始", 0.65),
            ("regret", 0.65),
            ("make it right", 0.65),
            ("start over", 0.65)
        ]

        var harmSignals: [String] = []
        var apologySignals: [String] = []
        var harmScore = 0.0
        var apologyScore = 0.0

        for (signal, weight) in harmSignalsAndWeights where containsSignal(signal, in: normalized) {
            harmSignals.append(signal)
            harmScore = max(harmScore, weight)
        }
        for (signal, weight) in apologySignalsAndWeights where containsSignal(signal, in: normalized) {
            apologySignals.append(signal)
            apologyScore = max(apologyScore, weight)
        }

        let isHarmful = harmScore >= 0.35
        let isApology = apologyScore >= 0.5
        var explanationParts: [String] = []
        if !harmSignals.isEmpty {
            explanationParts.append("伤害信号：" + harmSignals.joined(separator: "、"))
        }
        if !apologySignals.isEmpty {
            explanationParts.append("修复信号：" + apologySignals.joined(separator: "、"))
        }
        if explanationParts.isEmpty {
            explanationParts.append("未识别到明确关系信号")
        }

        return Assessment(
            isUserText: true,
            harmScore: harmScore,
            apologyScore: apologyScore,
            isPotentiallyHarmful: isHarmful,
            isApology: isApology,
            harmSignals: harmSignals,
            apologySignals: apologySignals,
            explanation: explanationParts.joined(separator: "；")
        )
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsSignal(_ signal: String, in text: String) -> Bool {
        if signal.unicodeScalars.contains(where: { $0.value > 127 }) || signal.contains(" ") {
            return text.contains(signal)
        }

        let words = text.split { character in
            !(character.isLetter || character.isNumber)
        }
        return words.contains { $0 == signal }
    }
}

// Short names keep AppModel call sites readable while preserving explicit
// top-level types for tests and import/export code.
typealias RelationshipState = RelationshipStateMachineState
typealias RelationshipEvent = RelationshipStateMachineEvent
typealias RelationshipDecision = RelationshipStateMachineDecision
