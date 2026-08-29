import Foundation

/// Splits assistant copy into short, readable display bubbles without
/// changing the event that backs the conversation or memory pipeline.
///
/// The segmenter is deliberately value-only: a caller supplies text and gets
/// a deterministic array of strings back. `String.Character` boundaries keep
/// emoji, skin-tone modifiers, and combining marks intact.
struct MessageBubbleSegmenter {
    /// A useful conversational target, rather than a strict minimum.
    static let recommendedTargetLength = 42
    /// Display bubbles never exceed this many extended grapheme clusters.
    static let hardMaximumLength = 72

    // Short aliases make the sizing contract easy to discover at call sites.
    static let targetLength = recommendedTargetLength
    static let hardLimit = hardMaximumLength

    /// Returns display segments for `text`.
    ///
    /// Assistant text is split at every sentence or paragraph boundary first,
    /// then at a nearby whitespace boundary, and finally at a grapheme
    /// boundary. Natural boundaries are intentionally strict: a second or
    /// third sentence is never folded into the previous bubble just to hit a
    /// target length. User text remains one segment so a user's event is never
    /// visually rewritten into multiple messages by default. Empty and
    /// whitespace-only assistant input produces no empty bubble.
    static func segments(
        for text: String,
        role: EventRole = .assistant,
        targetLength: Int = MessageBubbleSegmenter.recommendedTargetLength,
        hardLimit: Int = MessageBubbleSegmenter.hardMaximumLength
    ) -> [String] {
        guard !text.isEmpty else { return [] }

        // The hard limit is a presentation concern for assistant output. Keep
        // the original user value exactly as one display unit by default.
        guard role == .assistant else {
            // A whitespace-only user draft is not a meaningful bubble either;
            // otherwise preserve the user's complete value as one unit.
            guard text.contains(where: { !$0.isWhitespace }) else { return [] }
            return [text]
        }

        let characters = Array(text)
        guard let firstContent = characters.firstIndex(where: { !$0.isWhitespace }),
              let lastContent = characters.lastIndex(where: { !$0.isWhitespace }) else {
            return []
        }

        // Outer whitespace is a layout boundary, not a meaningful bubble.
        // Internal whitespace remains in the returned strings, including the
        // whitespace between a word and a hard/soft split.
        let source = Array(characters[firstContent...lastContent])
        let maximum = max(1, hardLimit)
        let target = min(max(1, targetLength), maximum)

        var result: [String] = []
        result.reserveCapacity(max(1, (source.count + target - 1) / target))

        var start = 0
        while start < source.count {
            // Keep an inter-segment whitespace run attached to the following
            // content when the preceding hard limit ended inside that run.
            // This preserves lossless joining without ever emitting a
            // whitespace-only bubble.
            guard let contentStart = source[start...].firstIndex(where: { !$0.isWhitespace }) else {
                break
            }

            let limit = min(source.count, start + maximum)
            let cut: Int
            if let naturalBoundary = firstNaturalBoundary(
                in: source,
                from: contentStart
            ), naturalBoundary <= limit {
                cut = naturalBoundary
            } else if limit > contentStart {
                cut = chooseHardCut(
                    in: source,
                    from: start,
                    contentStart: contentStart,
                    targetLength: target,
                    limit: limit
                )
            } else {
                // A pathological run of leading whitespace is allowed to sit
                // next to the first content character rather than becoming a
                // separate bubble.
                cut = min(source.count, contentStart + 1)
            }

            guard cut > start else {
                // This is only defensive; all candidate functions return a
                // grapheme-safe position after `start`.
                start += 1
                continue
            }

            let segment = String(source[start..<cut])
            if !segment.isEmpty {
                result.append(segment)
            }
            start = cut
        }

        return result
    }

    /// Singular spelling for callers that prefer `segment(...)`.
    static func segment(
        _ text: String,
        role: EventRole = .assistant,
        targetLength: Int = MessageBubbleSegmenter.recommendedTargetLength,
        hardLimit: Int = MessageBubbleSegmenter.hardMaximumLength
    ) -> [String] {
        segments(
            for: text,
            role: role,
            targetLength: targetLength,
            hardLimit: hardLimit
        )
    }

    /// Returns the first natural boundary after `start`.
    ///
    /// The returned range stops at the natural boundary itself. Any following
    /// whitespace therefore remains attached to the next non-empty segment,
    /// keeping `segments.joined()` lossless while each completed sentence
    /// still ends with its punctuation when one is present.
    private static func firstNaturalBoundary(
        in characters: [Character],
        from start: Int
    ) -> Int? {
        guard start < characters.count else { return nil }

        var index = start
        while index < characters.count {
            let character = characters[index]

            if isSentenceTerminator(character),
               !isDecimalPoint(in: characters, at: index),
               isStandaloneFullStop(in: characters, at: index) {
                var end = index + 1

                // Keep ellipses and repeated terminal punctuation together.
                while end < characters.count,
                      isSentenceTerminator(characters[end]) {
                    end += 1
                }

                // Closing quotation/bracket characters belong to the sentence
                // that they close, not to the next bubble.
                while end < characters.count,
                      isClosingCharacter(characters[end]) {
                    end += 1
                }

                return end
            }

            if isLineBreak(character) {
                // Leave paragraph separators at the start of the following
                // segment so the preceding paragraph remains a clean unit.
                return index
            }

            index += 1
        }
        return nil
    }

    private static func chooseHardCut(
        in characters: [Character],
        from start: Int,
        contentStart: Int,
        targetLength: Int,
        limit: Int
    ) -> Int {
        let usable = whitespaceBoundaryEnds(
            in: characters,
            from: start,
            through: limit
        ).filter { $0 > contentStart && $0 <= limit }

        let targetEnd = min(start + targetLength, limit)
        if let firstAfterTarget = usable.first(where: { $0 >= targetEnd }) {
            return firstAfterTarget
        }
        if let lastBeforeTarget = usable.last {
            return lastBeforeTarget
        }

        // No punctuation or whitespace was available in range. Array slicing
        // still lands exactly on a Character boundary, so this is safe for
        // emoji and combining-character sequences as well.
        return limit
    }

    /// Finds word/whitespace boundaries for long text without punctuation.
    /// The returned positions are the starts of whitespace runs, so trailing
    /// separators stay with the following segment and never become a bubble
    /// on their own.
    private static func whitespaceBoundaryEnds(
        in characters: [Character],
        from start: Int,
        through limit: Int
    ) -> [Int] {
        guard start < limit else { return [] }

        var ends: [Int] = []
        var index = start
        while index < limit {
            guard characters[index].isWhitespace else {
                index += 1
                continue
            }

            let end = index
            var runEnd = index + 1
            while runEnd < characters.count,
                  runEnd < limit,
                  characters[runEnd].isWhitespace {
                runEnd += 1
            }
            if end <= limit { ends.append(end) }
            index = max(index + 1, runEnd)
        }
        return ends
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        switch character {
        case "。", "！", "？", "!", "?", ";", "；", "…", ".":
            return true
        default:
            return false
        }
    }

    private static func isClosingCharacter(_ character: Character) -> Bool {
        switch character {
        case "\"", "'", "”", "’", "》", "」", "』", "】", "）", ")", "]", "}", "〉", "〕":
            return true
        default:
            return false
        }
    }

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r"
    }

    private static func isDecimalPoint(
        in characters: [Character],
        at index: Int
    ) -> Bool {
        guard characters[index] == ".",
              index > 0,
              index + 1 < characters.count else {
            return false
        }
        return isASCIIDigit(characters[index - 1])
            && isASCIIDigit(characters[index + 1])
    }

    /// An ASCII full stop in a URL, identifier, or abbreviation is not a
    /// sentence boundary unless it closes a token or is followed by spacing,
    /// closing punctuation, or another terminal mark.
    private static func isStandaloneFullStop(
        in characters: [Character],
        at index: Int
    ) -> Bool {
        guard characters[index] == "." else { return true }
        guard index + 1 < characters.count else { return true }
        let next = characters[index + 1]
        return next.isWhitespace
            || next == "."
            || isClosingCharacter(next)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }
        return (48...57).contains(scalar.value)
    }
}
