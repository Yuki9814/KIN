import Foundation

/// Presents a completed assistant turn as a small sequence of bubbles.
///
/// The service owns timing and presentation segmentation only. It does not
/// mutate a conversation event, call an API, or decide what the assistant may
/// say. Cancellation returns the segments that were already displayed.
struct ChatTurnPresentationService {
    struct DisplayedSegment: Equatable, Sendable {
        let index: Int
        let text: String
    }

    struct Result: Equatable, Sendable {
        let displayedSegments: [String]
        let cancelled: Bool

        var segments: [String] { displayedSegments }
        var isCancelled: Bool { cancelled }
    }

    struct Configuration: Equatable, Sendable {
        /// Whether the first assistant bubble waits for the humanized delay.
        /// The value is also used as the mode switch for continuation pacing:
        /// when it is false, continuations use the fixed 1.2 second cadence.
        var firstDelayEnabled: Bool
        var firstDelayRange: ClosedRange<TimeInterval>

        /// Kept for source compatibility with the first presentation queue
        /// implementation. Continuation pacing is now derived from the text
        /// length, so this range is intentionally not consulted by `present`.
        var segmentDelayRange: ClosedRange<TimeInterval>

        /// Kept for source compatibility with callers that construct a
        /// configuration for a single persisted unit. Ordinary conversation
        /// text is never merged by this service anymore.
        var maximumOrdinarySegments: Int

        /// Kept for source compatibility with persisted queue callers. Long
        /// ordinary text follows the same strict sentence/paragraph rules as
        /// every other ordinary message; only code and structured lists stay
        /// as one display unit.
        var longTextCharacterThreshold: Int

        init(
            firstDelayEnabled: Bool = true,
            firstDelayRange: ClosedRange<TimeInterval> = 3...5,
            segmentDelayRange: ClosedRange<TimeInterval> = 1.5...4,
            maximumOrdinarySegments: Int = 4,
            longTextCharacterThreshold: Int = 280
        ) {
            self.firstDelayEnabled = firstDelayEnabled
            self.firstDelayRange = Self.normalized(firstDelayRange)
            self.segmentDelayRange = Self.normalized(segmentDelayRange)
            self.maximumOrdinarySegments = max(1, maximumOrdinarySegments)
            self.longTextCharacterThreshold = max(1, longTextCharacterThreshold)
        }

        private static func normalized(
            _ range: ClosedRange<TimeInterval>
        ) -> ClosedRange<TimeInterval> {
            let lower = max(0, min(range.lowerBound, range.upperBound))
            let upper = max(lower, range.upperBound)
            return lower...upper
        }
    }

    /// The sleeper receives seconds so tests can capture exact delays without
    /// waiting in real time. The default uses the platform task clock.
    typealias Sleeper = (TimeInterval) async throws -> Void
    typealias RandomUnit = () -> Double
    /// Presentation callbacks mutate AppModel and its SwiftData context. Keep
    /// every callback on the main actor even when an async sleep resumes the
    /// presenter on a generic executor.
    typealias SegmentHandler = @MainActor (DisplayedSegment) -> Void

    /// The fixed cadence used when the humanized rhythm switch is disabled.
    static let fixedContinuationDelay: TimeInterval = 1.2

    /// Returns the cadence before displaying a continuation bubble. The
    /// length is measured in Swift `Character`s so a user-perceived emoji or
    /// composed glyph counts as one character rather than several scalars.
    static func continuationDelay(
        for text: String,
        humanized: Bool = true
    ) -> TimeInterval {
        guard humanized else { return fixedContinuationDelay }
        let visibleText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposed = 1.5 + Double(visibleText.count) * 0.05
        return min(4, max(1.5, proposed))
    }

    /// Short alias for tests and callers that describe this value as a
    /// segment delay rather than a continuation delay.
    static func delay(
        for text: String,
        humanized: Bool = true
    ) -> TimeInterval {
        continuationDelay(for: text, humanized: humanized)
    }

    let configuration: Configuration
    private let sleeper: Sleeper
    private let randomUnit: RandomUnit

    init(
        configuration: Configuration = Configuration(),
        sleeper: @escaping Sleeper = ChatTurnPresentationService.defaultSleeper,
        randomUnit: @escaping RandomUnit = { Double.random(in: 0...1) }
    ) {
        self.configuration = configuration
        self.sleeper = sleeper
        self.randomUnit = randomUnit
    }

    /// Returns the display plan without waiting.
    func segments(for text: String, role: EventRole = .assistant) -> [String] {
        let visible = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty else { return [] }
        guard role == .assistant else { return [visible] }

        // Code and structured lists remain one event-shaped display unit.
        // Their internal formatting is more valuable than a conversational
        // bubble cadence. Ordinary text, including long-form copy, must keep
        // every natural sentence/paragraph boundary visible.
        if isCode(visible) || isStructuredList(visible) {
            return [visible]
        }

        return MessageBubbleSegmenter.segments(
            for: visible,
            role: .assistant
        )
    }

    /// Displays the completed turn, preserving already displayed segments on
    /// cancellation. The same switch controls both the initial humanized
    /// pause and continuation cadence.
    func present(
        text: String,
        role: EventRole = .assistant,
        firstDelayEnabled: Bool? = nil
    ) async -> [String] {
        await present(
            text: text,
            role: role,
            firstDelayEnabled: firstDelayEnabled,
            onSegment: { _ in }
        ).displayedSegments
    }

    /// Presents the turn and reports each segment immediately after it is
    /// displayed. The result remains useful when cancellation interrupts a
    /// delay: it contains the visible prefix and an explicit cancellation bit.
    func present(
        text: String,
        role: EventRole = .assistant,
        firstDelayEnabled: Bool? = nil,
        onSegment: @escaping SegmentHandler
    ) async -> Result {
        let plan = segments(for: text, role: role)
        guard !plan.isEmpty else {
            return Result(displayedSegments: [], cancelled: Task.isCancelled)
        }

        var displayed: [String] = []
        let humanized = firstDelayEnabled ?? configuration.firstDelayEnabled
        if humanized {
            switch await wait(for: sample(configuration.firstDelayRange)) {
            case .completed:
                break
            case .cancelled:
                return Result(displayedSegments: displayed, cancelled: true)
            case .failed:
                return Result(displayedSegments: displayed, cancelled: false)
            }
        }

        for (index, segment) in plan.enumerated() {
            guard !Task.isCancelled else {
                return Result(displayedSegments: displayed, cancelled: true)
            }
            if index > 0 {
                let delay = Self.continuationDelay(
                    for: segment,
                    humanized: humanized
                )
                switch await wait(for: delay) {
                case .completed:
                    break
                case .cancelled:
                    return Result(displayedSegments: displayed, cancelled: true)
                case .failed:
                    return Result(displayedSegments: displayed, cancelled: false)
                }
            }
            guard !Task.isCancelled else {
                return Result(displayedSegments: displayed, cancelled: true)
            }
            displayed.append(segment)
            await onSegment(DisplayedSegment(index: index, text: segment))
        }
        return Result(displayedSegments: displayed, cancelled: Task.isCancelled)
    }

    /// Alias for callers that name the operation after the displayed result.
    func displaySegments(
        for text: String,
        role: EventRole = .assistant,
        firstDelayEnabled: Bool? = nil
    ) async -> [String] {
        await present(
            text: text,
            role: role,
            firstDelayEnabled: firstDelayEnabled
        )
    }

    private enum WaitResult {
        case completed
        case cancelled
        case failed
    }

    private func wait(for seconds: TimeInterval) async -> WaitResult {
        guard !Task.isCancelled else { return .cancelled }
        do {
            try await sleeper(seconds)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        return Task.isCancelled ? .cancelled : .completed
    }

    private func sample(_ range: ClosedRange<TimeInterval>) -> TimeInterval {
        let rawUnit = randomUnit()
        let unit = rawUnit.isFinite ? min(1, max(0, rawUnit)) : 0.5
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    private func isCode(_ text: String) -> Bool {
        if text.contains("```") { return true }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return false }
        let codeSignals = lines.reduce(into: 0) { count, line in
            let value = String(line).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("import ")
                || value.hasPrefix("#include")
                || value.hasPrefix("func ")
                || value.hasPrefix("class ")
                || value.hasPrefix("struct ")
                || value.hasPrefix("let ")
                || value.hasPrefix("var ")
                || value.hasPrefix("return ")
                || value.contains("=>")
                || value.hasSuffix("{")
                || value.hasSuffix("};") {
                count += 1
            }
        }
        return codeSignals >= 2
    }

    private func isStructuredList(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return false }
        let listLines = lines.filter { line in
            let value = String(line).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("- ")
                || value.hasPrefix("* ")
                || value.hasPrefix("• ")
                || value.hasPrefix("· ")
                || value.hasPrefix("— ")
                || value.hasPrefix("、") {
                return true
            }
            guard let first = value.first else { return false }
            if first.isNumber {
                return value.dropFirst().first == "."
                    || value.dropFirst().first == ")"
                    || value.dropFirst().first == "、"
            }
            return false
        }
        return listLines.count >= 2 && listLines.count * 2 >= lines.count
    }

    private static func defaultSleeper(_ seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
