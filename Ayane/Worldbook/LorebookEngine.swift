import Foundation

/// Deterministic, bounded lore activation inspired by established lorebook
/// workflows while preserving KIN's own prompt and evidence-memory boundaries.
enum LorebookEngine {
    struct CandidateKey: Hashable {
        let documentID: UUID
        let entryID: UUID
    }

    struct Candidate {
        let document: LorebookDocument
        let entry: LorebookEntry
        let reason: LorebookActivationReason
        let primaryMatches: [String]
        let secondaryMatches: [String]
        let recursionDepth: Int
        let tokenCount: Int

        var selection: LorebookActivationSelection {
            LorebookActivationSelection(
                documentID: document.id,
                documentName: document.name,
                entry: entry,
                reason: reason,
                matchedPrimaryKeys: primaryMatches,
                matchedSecondaryKeys: secondaryMatches,
                recursionDepth: recursionDepth,
                tokenCount: tokenCount
            )
        }
    }

    static func activate(
        documents: [LorebookDocument],
        context: LorebookActivationContext
    ) -> LorebookActivationResult {
        let documents = canonicalDocuments(documents).filter {
            applies($0, to: context)
        }
        guard !documents.isEmpty,
              context.tokenBudget > 0,
              context.maxEntries > 0 else {
            return LorebookActivationResult(
                selections: [],
                skippedForBudget: [],
                skippedForInclusionGroup: [],
                usedTokenCount: 0,
                tokenBudget: context.tokenBudget
            )
        }

        var candidatesByID: [CandidateKey: Candidate] = [:]
        var recursiveTextByDocument: [UUID: String] = [:]

        for document in documents {
            let scanText = scanText(for: document, context: context)
            for entry in canonicalEntries(document.entries) {
                guard let candidate = candidate(
                    document: document,
                    entry: entry,
                    text: scanText,
                    reason: entry.strategy == .constant ? .constant : .keyword,
                    recursionDepth: 0,
                    allowDelayedEntry: false,
                    context: context
                ) else { continue }
                candidatesByID[
                    CandidateKey(documentID: document.id, entryID: entry.id)
                ] = candidate
                if document.recursiveScanning, !entry.preventFurtherRecursion {
                    recursiveTextByDocument[document.id, default: ""] += "\n" + entry.content
                }
            }
        }

        let maximumSteps = documents.map { document in
            context.maxRecursionStepsOverride ?? document.maxRecursionSteps
        }.max() ?? 1
        if maximumSteps > 1 {
            for depth in 1..<maximumSteps {
                var addedAny = false
                for document in documents where document.recursiveScanning {
                    let recursiveText = recursiveTextByDocument[document.id] ?? ""
                    guard !recursiveText.isEmpty else { continue }
                    let documentMaximumSteps = context.maxRecursionStepsOverride
                        ?? document.maxRecursionSteps
                    guard depth < documentMaximumSteps else { continue }
                    for entry in canonicalEntries(document.entries) {
                        let key = CandidateKey(documentID: document.id, entryID: entry.id)
                        guard candidatesByID[key] == nil,
                              !entry.nonRecursable,
                              entry.recursionLevel <= depth,
                              let candidate = candidate(
                                document: document,
                                entry: entry,
                                text: recursiveText,
                                reason: .recursive,
                                recursionDepth: depth,
                                allowDelayedEntry: true,
                                context: context
                              ) else { continue }
                        candidatesByID[key] = candidate
                        addedAny = true
                        if !entry.preventFurtherRecursion {
                            recursiveTextByDocument[document.id, default: ""] += "\n" + entry.content
                        }
                    }
                }
                if !addedAny { break }
            }
        }

        let ranked = candidatesByID.values.sorted(by: candidateRanksBefore)
        let grouped = resolveInclusionGroups(ranked, seed: context.deterministicSeed)
        let selectedCandidates = grouped.accepted
        var skippedForBudget: [UUID] = []
        var selected: [Candidate] = []
        var usedGlobalTokens = 0
        var usedDocumentTokens: [UUID: Int] = [:]

        for candidate in selectedCandidates {
            guard selected.count < context.maxEntries else {
                skippedForBudget.append(candidate.entry.id)
                continue
            }
            let entryLimit = candidate.entry.tokenBudget ?? Int.max
            let documentLimit = candidate.document.tokenBudget
            let documentUsed = usedDocumentTokens[candidate.document.id, default: 0]
            guard candidate.tokenCount <= entryLimit,
                  usedGlobalTokens + candidate.tokenCount <= context.tokenBudget,
                  documentUsed + candidate.tokenCount <= documentLimit else {
                skippedForBudget.append(candidate.entry.id)
                continue
            }
            selected.append(candidate)
            usedGlobalTokens += candidate.tokenCount
            usedDocumentTokens[candidate.document.id] = documentUsed + candidate.tokenCount
        }

        let rendered = selected
            .map(\.selection)
            .sorted(by: selectionRendersBefore)
        return LorebookActivationResult(
            selections: rendered,
            skippedForBudget: skippedForBudget.sorted { $0.uuidString < $1.uuidString },
            skippedForInclusionGroup: grouped.skipped.sorted { $0.uuidString < $1.uuidString },
            usedTokenCount: usedGlobalTokens,
            tokenBudget: context.tokenBudget
        )
    }
}
