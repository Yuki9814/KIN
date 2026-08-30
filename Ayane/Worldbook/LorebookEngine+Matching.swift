import Foundation

extension LorebookEngine {
    static func canonicalDocuments(
        _ documents: [LorebookDocument]
    ) -> [LorebookDocument] {
        var winners: [UUID: LorebookDocument] = [:]
        for document in documents where winners[document.id] == nil {
            winners[document.id] = document
        }
        return winners.values.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return scopeRank(lhs.scope) < scopeRank(rhs.scope)
            }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func canonicalEntries(_ entries: [LorebookEntry]) -> [LorebookEntry] {
        var seen = Set<UUID>()
        return entries
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.insertionOrder != rhs.insertionOrder {
                    return lhs.insertionOrder < rhs.insertionOrder
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func applies(
        _ document: LorebookDocument,
        to context: LorebookActivationContext
    ) -> Bool {
        switch document.scope {
        case .global:
            return true
        case .persona:
            guard let id = context.activePersonaID else { return false }
            return document.boundPersonaIDs.isEmpty || document.boundPersonaIDs.contains(id)
        case .character:
            guard let id = context.activeCharacterID else { return false }
            return document.boundCharacterIDs.isEmpty || document.boundCharacterIDs.contains(id)
        case .conversation:
            guard let id = context.activeConversationID else { return false }
            return document.boundConversationIDs.isEmpty || document.boundConversationIDs.contains(id)
        }
    }

    static func scopeRank(_ scope: LorebookScope) -> Int {
        switch scope {
        case .conversation: 0
        case .persona: 1
        case .character: 2
        case .global: 3
        }
    }

    static func scanText(
        for document: LorebookDocument,
        context: LorebookActivationContext
    ) -> String {
        let depth = context.scanDepthOverride ?? document.scanDepth
        guard depth > 0 else { return "" }
        return context.messages.suffix(depth).map { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if document.includeParticipantNames,
               let sender = message.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sender.isEmpty {
                return "\(sender): \(content)"
            }
            return content
        }.joined(separator: "\n")
    }

    static func candidate(
        document: LorebookDocument,
        entry: LorebookEntry,
        text: String,
        reason: LorebookActivationReason,
        recursionDepth: Int,
        allowDelayedEntry: Bool,
        context: LorebookActivationContext
    ) -> Candidate? {
        let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.enabled,
              !content.isEmpty,
              context.messages.count >= entry.delayMessages,
              characterFilterAllows(entry, characterID: context.activeCharacterID),
              allowDelayedEntry || !entry.delayUntilRecursion else {
            return nil
        }

        let primaryMatches: [String]
        let secondaryMatches: [String]
        if entry.strategy == .constant, reason != .recursive {
            primaryMatches = []
            secondaryMatches = []
        } else {
            primaryMatches = matchingKeys(
                entry.primaryKeys,
                in: text,
                caseSensitive: entry.caseSensitive,
                matchWholeWords: entry.matchWholeWords
            )
            guard !primaryMatches.isEmpty else { return nil }
            secondaryMatches = matchingKeys(
                entry.secondaryKeys,
                in: text,
                caseSensitive: entry.caseSensitive,
                matchWholeWords: entry.matchWholeWords
            )
            guard secondaryLogicAllows(
                entry.secondaryLogic,
                keys: entry.secondaryKeys,
                matches: secondaryMatches
            ) else { return nil }
        }

        guard probabilityAllows(
            entry: entry,
            documentID: document.id,
            context: context,
            recursionDepth: recursionDepth
        ) else { return nil }
        let tokenCount = max(1, MemoryTokenizer.tokenCount(of: content))
        return Candidate(
            document: document,
            entry: entry,
            reason: reason,
            primaryMatches: primaryMatches,
            secondaryMatches: secondaryMatches,
            recursionDepth: recursionDepth,
            tokenCount: tokenCount
        )
    }

    static func characterFilterAllows(
        _ entry: LorebookEntry,
        characterID: UUID?
    ) -> Bool {
        if let characterID, entry.excludedCharacterIDs.contains(characterID) {
            return false
        }
        guard !entry.requiredCharacterIDs.isEmpty else { return true }
        guard let characterID else { return false }
        return entry.requiredCharacterIDs.contains(characterID)
    }

    static func matchingKeys(
        _ keys: [String],
        in text: String,
        caseSensitive: Bool,
        matchWholeWords: Bool
    ) -> [String] {
        keys.filter { key in
            keyMatches(
                key,
                in: text,
                caseSensitive: caseSensitive,
                matchWholeWords: matchWholeWords
            )
        }
    }

    static func keyMatches(
        _ rawKey: String,
        in text: String,
        caseSensitive: Bool,
        matchWholeWords: Bool
    ) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !text.isEmpty else { return false }
        if let regex = parsedRegex(key, defaultCaseSensitive: caseSensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }

        let options: String.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        guard matchWholeWords, isASCIISingleWord(key) else {
            return text.range(of: key, options: options) != nil
        }
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        let regexOptions: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func parsedRegex(
        _ key: String,
        defaultCaseSensitive: Bool
    ) -> NSRegularExpression? {
        guard key.first == "/",
              let lastSlash = key.lastIndex(of: "/"),
              lastSlash > key.startIndex else {
            return nil
        }
        let patternStart = key.index(after: key.startIndex)
        let pattern = String(key[patternStart..<lastSlash])
        guard !pattern.isEmpty else { return nil }
        let flagsStart = key.index(after: lastSlash)
        let flags = String(key[flagsStart...])
        var options: NSRegularExpression.Options = []
        if flags.contains("i") || !defaultCaseSensitive { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    static func isASCIISingleWord(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
    }

    static func secondaryLogicAllows(
        _ logic: LorebookSecondaryLogic,
        keys: [String],
        matches: [String]
    ) -> Bool {
        guard !keys.isEmpty else { return true }
        switch logic {
        case .andAny: return !matches.isEmpty
        case .andAll: return matches.count == keys.count
        case .notAny: return matches.isEmpty
        case .notAll: return matches.count != keys.count
        }
    }

    static func probabilityAllows(
        entry: LorebookEntry,
        documentID: UUID,
        context: LorebookActivationContext,
        recursionDepth: Int
    ) -> Bool {
        if entry.probabilityPercent >= 100 { return true }
        if entry.probabilityPercent <= 0 { return false }
        let value = [
            context.deterministicSeed,
            documentID.uuidString,
            entry.id.uuidString,
            String(context.messages.count),
            String(recursionDepth)
        ].joined(separator: "|")
        return Int(stableHash(value) % 100) < entry.probabilityPercent
    }

    static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
