import Foundation
import SwiftData

struct MemoryLibraryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: MemoryKind
    let subject: String
    let predicate: String
    let value: String
    let state: MemoryState
    let confidence: Double
    let updatedAt: Date
    let isPinned: Bool
    let userVerified: Bool
}

struct MemoryLibrarySortKey: Equatable, Hashable, Sendable {
    let updatedAt: Date
    let id: UUID
}

struct MemoryLibraryCursor: Equatable, Hashable, Sendable {
    let after: MemoryLibrarySortKey
    let snapshotUpperBound: MemoryLibrarySortKey
    let filterFingerprint: String
    let storeRevision: Int
    /// Application UUIDs that have already been returned to the caller. A
    /// CloudKit merge can leave two physical rows for one application UUID;
    /// carrying only the returned IDs lets the next page skip the duplicate
    /// without skipping the over-fetched rows that were not shown yet.
    let seenApplicationIDs: Set<UUID>
    /// The global legacy tombstone cutoff belongs to the same read snapshot as
    /// the keyset upper bound. Keeping it in the cursor prevents a marker that
    /// arrives between page requests from changing the remainder of a page
    /// session when the caller has not advanced its store revision yet.
    let snapshotLegacyTombstoneCutoff: Date?
    /// Distinguishes a captured snapshot with no legacy cutoff from an older
    /// caller-created cursor that predates this field. Without this bit, a
    /// tombstone inserted between pages could change a previously empty
    /// cutoff into a live one and drift the remainder of the session.
    let snapshotLegacyTombstoneCutoffCaptured: Bool

    init(
        after: MemoryLibrarySortKey,
        snapshotUpperBound: MemoryLibrarySortKey,
        filterFingerprint: String,
        storeRevision: Int,
        seenApplicationIDs: Set<UUID> = [],
        snapshotLegacyTombstoneCutoff: Date? = nil,
        snapshotLegacyTombstoneCutoffCaptured: Bool = false
    ) {
        self.after = after
        self.snapshotUpperBound = snapshotUpperBound
        self.filterFingerprint = filterFingerprint
        self.storeRevision = storeRevision
        self.seenApplicationIDs = seenApplicationIDs
        self.snapshotLegacyTombstoneCutoff = snapshotLegacyTombstoneCutoff
        self.snapshotLegacyTombstoneCutoffCaptured = snapshotLegacyTombstoneCutoffCaptured
    }
}

struct MemoryLibraryPage: Equatable, Sendable {
    let items: [MemoryLibraryItem]
    let nextCursor: MemoryLibraryCursor?
    let hasMore: Bool
    /// Number of source models fetched while filling this page. Tests use this
    /// to ensure the first screen stays bounded as the durable library grows.
    let sourceRecordsScanned: Int
}

enum MemoryLibraryError: LocalizedError, Equatable {
    case staleCursor
    case unavailable

    var errorDescription: String? {
        switch self {
        case .staleCursor:
            return "记忆列表已更新，正在重新载入。"
        case .unavailable:
            return "这条记忆已在另一台设备更新或遗忘，请刷新后再试。"
        }
    }
}

/// Bounded, keyset-paged reads for the human-facing memory library.
///
/// The chat prompt and the durable source of truth remain separate concerns:
/// this type never deletes or rewrites records, and it never carries SwiftData
/// model objects into SwiftUI state. A page is converted immediately into
/// immutable value snapshots; mutations re-fetch the latest object by UUID.
@MainActor
enum MemoryLibrary {
    static let defaultPageSize = 80
    private static let maximumPageSize = 200
    private static let maximumPhysicalCopiesPerSortKey = 256

    static func filterFingerprint(
        query: String,
        state: MemoryState?,
        roleID: UUID? = nil
    ) -> String {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let resolvedRoleID = RoleScope.resolve(roleID)
        return "role=\(resolvedRoleID.uuidString.lowercased())|state=\(state?.rawValue ?? "all")|query=\(normalizedQuery)"
    }

    static func fetchPage(
        context: ModelContext,
        query: String,
        state: MemoryState?,
        roleID: UUID? = nil,
        after cursor: MemoryLibraryCursor?,
        storeRevision: Int,
        limit requestedLimit: Int = 80
    ) throws -> MemoryLibraryPage {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let limit = min(max(1, requestedLimit), maximumPageSize)
        let resolvedRoleID = RoleScope.resolve(roleID)
        let fingerprint = filterFingerprint(query: query, state: state, roleID: resolvedRoleID)
        if let cursor {
            guard cursor.filterFingerprint == fingerprint,
                  cursor.storeRevision == storeRevision else {
                throw MemoryLibraryError.staleCursor
            }
        }

        let visibleTarget = limit + 1
        let chunkLimit = min(max(visibleTarget + 16, 32), maximumPageSize + 1)
        var scanCursor = cursor?.after
        var upperBound = cursor?.snapshotUpperBound
        let legacyTombstoneCutoff: Date?
        if let cursor, cursor.snapshotLegacyTombstoneCutoffCaptured {
            legacyTombstoneCutoff = cursor.snapshotLegacyTombstoneCutoff
        } else {
            legacyTombstoneCutoff = try legacyGlobalTombstoneCutoff(
                roleID: resolvedRoleID,
                context: context
            )
        }
        var visible: [MemoryLibraryItem] = []
        var seenApplicationIDs = cursor?.seenApplicationIDs ?? []
        var sourceRecordsScanned = 0
        var sourceExhausted = false

        while visible.count < visibleTarget, !sourceExhausted {
            var descriptor = makeDescriptor(
                query: query,
                state: state,
                roleID: resolvedRoleID,
                after: scanCursor,
                upperBound: upperBound,
                legacyTombstoneCutoff: legacyTombstoneCutoff
            )
            descriptor.fetchLimit = chunkLimit
            descriptor.propertiesToFetch = libraryRecordProperties

            let fetchedRecords = try context.fetch(descriptor)
            guard !fetchedRecords.isEmpty else {
                sourceExhausted = true
                break
            }
            var records = fetchedRecords
            sourceRecordsScanned += fetchedRecords.count

            // A page boundary can split physical CloudKit copies which share
            // the exact same application UUID and timestamp. Complete only
            // that one boundary group, then choose a deterministic logical
            // winner before advancing the keyset cursor. This keeps ordinary
            // pages bounded while preventing a matching copy from being
            // skipped solely because an equal-key copy happened to be fetched
            // first.
            if fetchedRecords.count == chunkLimit,
               let boundary = fetchedRecords.last {
                let boundaryCopies = try physicalCopies(
                    matching: sortKey(boundary),
                    roleID: resolvedRoleID,
                    legacyTombstoneCutoff: legacyTombstoneCutoff,
                    context: context
                )
                sourceRecordsScanned += boundaryCopies.count
                records.removeAll { sortKey($0) == sortKey(boundary) }
                // Complete the physical boundary before applying the logical
                // state filter. Forgotten copies must remain visible to the
                // duplicate-integrity check even when the requested page is
                // filtered to another state.
                records.append(contentsOf: boundaryCopies.filter {
                    matchesRequestedState($0, state: state)
                })
            }
            records = deterministicLogicalRecords(records)
            if upperBound == nil, let first = records.first {
                upperBound = sortKey(first)
            }

            // A CloudKit merge may materialize active and forgotten rows under
            // one application UUID. Resolve every logical UUID represented by
            // this bounded chunk before evaluating its visibility. This is
            // deliberately after the boundary group has been completed, but
            // before state/tombstone/search filtering can hide a forgotten
            // physical copy. The extra equality reads are bounded by the
            // current chunk and are integrity checks, not unbounded scans.
            var blockedApplicationIDs = Set<UUID>()
            var inspectedApplicationIDs = Set<UUID>()
            for record in records {
                guard inspectedApplicationIDs.insert(record.id).inserted else {
                    continue
                }
                let copies = try physicalCopies(
                    forApplicationID: record.id,
                    roleID: resolvedRoleID,
                    legacyTombstoneCutoff: legacyTombstoneCutoff,
                    context: context
                )
                if copies.contains(where: { $0.state == .forgotten }) {
                    blockedApplicationIDs.insert(record.id)
                }
            }

            // The snapshot cutoff has already been pushed into the source
            // predicate. Do not re-read the current global legacy marker here:
            // a marker arriving between pages must not rewrite this cursor's
            // previously captured snapshot.
            let tombstones = try relevantTombstones(
                for: records,
                context: context,
                includeLegacyGlobal: false
            )
            for record in records {
                // The first row for an application UUID is its deterministic
                // newest logical winner. Consume that UUID even when its text
                // does not match; an older physical copy must not make stale
                // content searchable again.
                guard !seenApplicationIDs.contains(record.id) else { continue }
                if blockedApplicationIDs.contains(record.id)
                    || record.state == .forgotten
                    || MemoryRepository.isSuppressedByTombstone(
                        record,
                        tombstones: tombstones
                    ) {
                    seenApplicationIDs.insert(record.id)
                    continue
                }
                seenApplicationIDs.insert(record.id)
                guard matchesSearch(record, query: query) else { continue }
                visible.append(item(record))
                if visible.count == visibleTarget { break }
            }

            guard let last = records.last else {
                sourceExhausted = true
                break
            }
            scanCursor = sortKey(last)
            sourceExhausted = fetchedRecords.count < chunkLimit
        }

        let pageItems = Array(visible.prefix(limit))
        let hasMore = visible.count > limit || !sourceExhausted
        let nextCursor: MemoryLibraryCursor?
        if hasMore, let last = pageItems.last, let upperBound {
            // Keep IDs that were returned or rejected by a state/tombstone
            // barrier. The one over-fetched visible item is intentionally
            // removed: it has not been returned yet and must be eligible on
            // the next page. Query-mismatching rows were never inserted into
            // this set, so a matching duplicate physical row can still be
            // discovered later.
            let overFetchedIDs = Set(visible.dropFirst(limit).map(\.id))
            nextCursor = MemoryLibraryCursor(
                after: MemoryLibrarySortKey(updatedAt: last.updatedAt, id: last.id),
                snapshotUpperBound: upperBound,
                filterFingerprint: fingerprint,
                storeRevision: storeRevision,
                seenApplicationIDs: seenApplicationIDs.subtracting(overFetchedIDs),
                snapshotLegacyTombstoneCutoff: legacyTombstoneCutoff,
                snapshotLegacyTombstoneCutoffCaptured: true
            )
        } else {
            nextCursor = nil
        }

        return MemoryLibraryPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: hasMore,
            sourceRecordsScanned: sourceRecordsScanned
        )
    }

    private static func matchesSearch(
        _ record: MemoryAssertionRecord,
        query: String
    ) -> Bool {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return true }
        return record.value.localizedStandardContains(searchText)
            || record.predicate.localizedStandardContains(searchText)
            || record.subject.localizedStandardContains(searchText)
            || record.canonicalKey.localizedStandardContains(searchText)
            || record.kindRaw.localizedStandardContains(searchText)
            || (MemoryKind(rawValue: record.kindRaw)?.title.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private static var libraryRecordProperties: [PartialKeyPath<MemoryAssertionRecord>] {
        [
            \MemoryAssertionRecord.id,
            \MemoryAssertionRecord.roleID,
            \MemoryAssertionRecord.kindRaw,
            \MemoryAssertionRecord.subject,
            \MemoryAssertionRecord.predicate,
            \MemoryAssertionRecord.value,
            \MemoryAssertionRecord.canonicalKey,
            \MemoryAssertionRecord.stateRaw,
            \MemoryAssertionRecord.confidence,
            \MemoryAssertionRecord.sourceRank,
            \MemoryAssertionRecord.createdAt,
            \MemoryAssertionRecord.updatedAt,
            \MemoryAssertionRecord.isPinned,
            \MemoryAssertionRecord.userVerified
        ]
    }

    private static func physicalCopies(
        matching key: MemoryLibrarySortKey,
        roleID: UUID,
        legacyTombstoneCutoff: Date?,
        context: ModelContext
    ) throws -> [MemoryAssertionRecord] {
        let boundaryDate = key.updatedAt
        let boundaryID = key.id
        let cutoffDate = legacyTombstoneCutoff ?? .distantPast
        let hasLegacyCutoff = legacyTombstoneCutoff != nil
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        var descriptor = FetchDescriptor<MemoryAssertionRecord>(
            predicate: #Predicate {
                $0.updatedAt == boundaryDate
                    && $0.id == boundaryID
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
                    && (!hasLegacyCutoff || $0.createdAt > cutoffDate)
            }
        )
        descriptor.fetchLimit = maximumPhysicalCopiesPerSortKey + 1
        descriptor.propertiesToFetch = libraryRecordProperties
        let copies = try context.fetch(descriptor)
        guard copies.count <= maximumPhysicalCopiesPerSortKey else {
            // A pathological duplicate group is an integrity condition, not a
            // reason to expose an arbitrary physical copy.
            throw MemoryLibraryError.unavailable
        }
        return copies
    }

    /// Fetches the complete physical duplicate group for one application UUID.
    /// Unlike the ordinary page predicate this intentionally includes forgotten
    /// rows, because an active/forgotten pair is an integrity conflict that
    /// must not be resolved by whichever row happened to be fetched first.
    private static func physicalCopies(
        forApplicationID applicationID: UUID,
        roleID: UUID,
        legacyTombstoneCutoff: Date?,
        context: ModelContext
    ) throws -> [MemoryAssertionRecord] {
        let cutoffDate = legacyTombstoneCutoff ?? .distantPast
        let hasLegacyCutoff = legacyTombstoneCutoff != nil
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        var descriptor = FetchDescriptor<MemoryAssertionRecord>(
            predicate: #Predicate {
                $0.id == applicationID
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
                    && (!hasLegacyCutoff || $0.createdAt > cutoffDate)
            },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.stateRaw),
                SortDescriptor(\.canonicalKey),
                SortDescriptor(\.value)
            ]
        )
        descriptor.fetchLimit = maximumPhysicalCopiesPerSortKey + 1
        descriptor.propertiesToFetch = libraryRecordProperties
        let copies = try context.fetch(descriptor)
        guard copies.count <= maximumPhysicalCopiesPerSortKey else {
            // A pathological duplicate group is an integrity condition, not a
            // reason to expose an arbitrary physical copy.
            throw MemoryLibraryError.unavailable
        }
        return copies
    }

    private static func matchesRequestedState(
        _ record: MemoryAssertionRecord,
        state: MemoryState?
    ) -> Bool {
        guard let state else { return true }
        // The library never exposes forgotten rows. Keep the historical
        // behavior for an explicit forgotten filter while still fetching the
        // rows needed to detect a conflicting physical copy.
        guard state != .forgotten else { return false }
        return record.state == state
    }

    private static func deterministicLogicalRecords(
        _ records: [MemoryAssertionRecord]
    ) -> [MemoryAssertionRecord] {
        var order: [MemoryLibrarySortKey] = []
        var winners: [MemoryLibrarySortKey: MemoryAssertionRecord] = [:]
        for record in records {
            let key = sortKey(record)
            if winners[key] == nil {
                order.append(key)
            }
            if libraryRecordPreferred(record, over: winners[key]) {
                winners[key] = record
            }
        }
        return order.compactMap { winners[$0] }
    }

    private static func libraryRecordPreferred(
        _ candidate: MemoryAssertionRecord,
        over current: MemoryAssertionRecord?
    ) -> Bool {
        guard let current else { return true }
        if candidate.userVerified != current.userVerified {
            return candidate.userVerified
        }
        if candidate.sourceRank != current.sourceRank {
            return candidate.sourceRank > current.sourceRank
        }
        return libraryRecordStableKey(candidate) > libraryRecordStableKey(current)
    }

    private static func libraryRecordStableKey(_ record: MemoryAssertionRecord) -> String {
        [
            record.kindRaw,
            record.subject,
            record.predicate,
            record.value,
            record.canonicalKey,
            record.stateRaw,
            String(record.confidence.bitPattern, radix: 16),
            String(record.sourceRank),
            String(record.createdAt.timeIntervalSince1970.bitPattern, radix: 16),
            record.isPinned ? "1" : "0",
            record.userVerified ? "1" : "0"
        ].joined(separator: "\u{1f}")
    }

    /// Re-resolves the current physical object before every user mutation.
    /// This prevents a stale SwiftUI row from reviving a CloudKit tombstone or
    /// overwriting a newer cross-device value.
    static func fetchLatestVisibleRecord(
        id: UUID,
        roleID: UUID? = nil,
        context: ModelContext
    ) throws -> MemoryAssertionRecord {
        let resolvedRoleID = RoleScope.resolve(roleID)
        let legacyTombstoneCutoff = try legacyGlobalTombstoneCutoff(
            roleID: resolvedRoleID,
            context: context
        )
        let records = try physicalCopies(
            forApplicationID: id,
            roleID: resolvedRoleID,
            legacyTombstoneCutoff: legacyTombstoneCutoff,
            context: context
        )

        // A forgotten physical copy is an integrity conflict, even when a
        // newer active copy also exists. Returning the active row would make
        // a delayed/partial CloudKit merge capable of reviving forgotten
        // content, so this path is fail-closed.
        guard !records.contains(where: { $0.state == .forgotten }) else {
            throw MemoryLibraryError.unavailable
        }

        let tombstones = try relevantTombstones(for: records, context: context)
        let logicalRecords = deterministicLogicalRecords(records)
        guard let record = logicalRecords.first(where: {
            $0.state != .forgotten
                && !MemoryRepository.isSuppressedByTombstone($0, tombstones: tombstones)
        }) else {
            throw MemoryLibraryError.unavailable
        }
        return record
    }

    private static func makeDescriptor(
        query: String,
        state: MemoryState?,
        roleID: UUID,
        after: MemoryLibrarySortKey?,
        upperBound: MemoryLibrarySortKey?,
        legacyTombstoneCutoff: Date?
    ) -> FetchDescriptor<MemoryAssertionRecord> {
        // Search text is applied to the bounded source chunk in Swift. This
        // keeps the persisted predicate small enough for the iOS 17/macOS 14
        // translator while retaining title-aware matching (which cannot be
        // represented by a collection `contains` predicate).
        _ = query

        let afterDate = after?.updatedAt ?? .distantFuture
        let afterID = after?.id
            ?? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let upperDate = upperBound?.updatedAt ?? .distantFuture
        let upperID = upperBound?.id
            ?? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let hasUpperBound = upperBound != nil
        let cutoffDate = legacyTombstoneCutoff ?? .distantPast
        let hasLegacyCutoff = legacyTombstoneCutoff != nil
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID

        // Predicate translation on the app's minimum SwiftData runtimes is
        // reliable for scalar equality and boolean combinations, but not for
        // a captured collection's `contains`. Keep an explicit state filter
        // as one scalar equality; with no filter, include forgotten rows so
        // the caller can complete the physical UUID group before hiding them.
        let hasRequestedState = state != nil
        let requestedStateRaw = state?.rawValue ?? ""
        let requestedStateIsForgotten = state == .forgotten

        let sortBy = [
            SortDescriptor(\MemoryAssertionRecord.updatedAt, order: .reverse),
            SortDescriptor(\MemoryAssertionRecord.id, order: .reverse)
        ]
        return FetchDescriptor<MemoryAssertionRecord>(
            predicate: #Predicate {
                (!requestedStateIsForgotten
                    && (!hasRequestedState || $0.stateRaw == requestedStateRaw))
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
                    && ($0.updatedAt < afterDate
                        || ($0.updatedAt == afterDate && $0.id < afterID))
                    && (!hasUpperBound
                        || $0.updatedAt < upperDate
                        || ($0.updatedAt == upperDate
                            && ($0.id < upperID || $0.id == upperID)))
                    && (!hasLegacyCutoff || $0.createdAt > cutoffDate)
            },
            sortBy: sortBy
        )
    }

    /// Fetch only tombstones that can affect this bounded source batch. New
    /// records persist normalized canonical keys; raw/trimmed/case variants
    /// keep imported legacy keys on the safe side without loading all markers.
    static func relevantTombstones(
        for records: [MemoryAssertionRecord],
        context: ModelContext,
        includeLegacyGlobal: Bool = true
    ) throws -> [MemoryTombstoneRecord] {
        guard !records.isEmpty else { return [] }
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let entityType = "memory"
        // A malformed or delayed CloudKit duplicate group can contain the same
        // tombstone UUID with different entity/key identities, at either equal
        // or different deletion times. Each identity is independent suppression
        // evidence: choosing only the newest physical UUID copy could make an
        // older key visible again. Collapse timestamps only within one complete
        // identity and retain every distinct identity fail-closed.
        var newestByIdentity: [TombstoneSuppressionIdentity: MemoryTombstoneRecord] = [:]
        // Keep each predicate to scalar equality. In particular, do not use a
        // captured `ids.contains`/`keys.contains`: older iOS 17/macOS 14
        // SwiftData stores either reject that predicate or fall back to an
        // unbounded scan.
        let roleIDs = Set(records.map(\.resolvedRoleID))
            .sorted { $0.uuidString < $1.uuidString }
        for roleID in roleIDs {
            let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
            let scopedRecords = records.filter { $0.resolvedRoleID == roleID }
            let ids = Set(scopedRecords.map(\.id))
            let keys = Set(scopedRecords.flatMap { canonicalKeyVariants($0.canonicalKey) })
            for id in ids {
                var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                    predicate: #Predicate {
                        $0.entityType == entityType
                            && $0.entityID == id
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                    },
                    sortBy: [
                        SortDescriptor(\.deletedAt, order: .reverse),
                        SortDescriptor(\.id, order: .reverse)
                    ]
                )
                descriptor.fetchLimit = 1
                descriptor.propertiesToFetch = tombstoneProperties
                for tombstone in try context.fetch(descriptor) {
                    keepNewestSuppression(tombstone, in: &newestByIdentity)
                }
            }
            for key in keys {
                var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                    predicate: #Predicate {
                        $0.entityType == entityType
                            && $0.canonicalKey == key
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                    },
                    sortBy: [
                        SortDescriptor(\.deletedAt, order: .reverse),
                        SortDescriptor(\.id, order: .reverse)
                    ]
                )
                descriptor.fetchLimit = 1
                descriptor.propertiesToFetch = tombstoneProperties
                for tombstone in try context.fetch(descriptor) {
                    keepNewestSuppression(tombstone, in: &newestByIdentity)
                }
            }
        }

        // Legacy markers did not always persist a canonical key. One newest
        // global cutoff safely prevents a different UUID from reviving older
        // structured facts, while a later explicit restatement remains valid.
        if includeLegacyGlobal {
            for roleID in roleIDs {
                for legacy in try fetchLegacyGlobalTombstones(
                    roleID: roleID,
                    context: context
                ) {
                    keepNewestSuppression(legacy, in: &newestByIdentity)
                }
            }
        }
        return newestByIdentity.values
            .sorted {
                if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
                if $0.deletedAt != $1.deletedAt { return $0.deletedAt > $1.deletedAt }
                if $0.canonicalKey != $1.canonicalKey {
                    return $0.canonicalKey < $1.canonicalKey
                }
                return $0.entityID.uuidString < $1.entityID.uuidString
            }
    }

    /// Every legacy row is durably normalized before this query. Therefore an
    /// exact empty-key lookup is complete even for old mixed Unicode/tab/newline
    /// spellings, and the hot read never approximates correctness with a recent
    /// fixed-size slice of the tombstone table.
    private static func fetchLegacyGlobalTombstones(
        roleID: UUID,
        context: ModelContext
    ) throws -> [MemoryTombstoneRecord] {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let entityType = "memory"
        let emptyKey = ""
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && $0.canonicalKey == emptyKey
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
            },
            sortBy: [
                SortDescriptor(\.deletedAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = tombstoneProperties
        return try context.fetch(descriptor)
    }

    private static func legacyGlobalTombstoneCutoff(
        roleID: UUID,
        context: ModelContext
    ) throws -> Date? {
        try fetchLegacyGlobalTombstones(roleID: roleID, context: context)
            .map(\.deletedAt)
            .max()
    }

    private static var tombstoneProperties: [PartialKeyPath<MemoryTombstoneRecord>] {
        [
            \MemoryTombstoneRecord.id,
            \MemoryTombstoneRecord.roleID,
            \MemoryTombstoneRecord.entityID,
            \MemoryTombstoneRecord.entityType,
            \MemoryTombstoneRecord.canonicalKey,
            \MemoryTombstoneRecord.canonicalKeyNormalizationVersion,
            \MemoryTombstoneRecord.deletedAt
        ]
    }

    private struct TombstoneSuppressionIdentity: Hashable {
        let id: UUID
        let roleID: UUID
        let entityID: UUID
        let entityType: String
        let canonicalKey: String

        init(_ tombstone: MemoryTombstoneRecord) {
            id = tombstone.id
            roleID = tombstone.resolvedRoleID
            entityID = tombstone.entityID
            entityType = tombstone.entityType
            canonicalKey = MemoryTombstoneRecord.normalizedCanonicalKey(
                tombstone.canonicalKey
            )
        }
    }

    private static func keepNewestSuppression(
        _ tombstone: MemoryTombstoneRecord,
        in newestByIdentity: inout [TombstoneSuppressionIdentity: MemoryTombstoneRecord]
    ) {
        let identity = TombstoneSuppressionIdentity(tombstone)
        guard let current = newestByIdentity[identity] else {
            newestByIdentity[identity] = tombstone
            return
        }
        if tombstone.deletedAt > current.deletedAt {
            newestByIdentity[identity] = tombstone
        }
    }

    private static func canonicalKeyVariants(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = MemoryTombstoneRecord.normalizedCanonicalKey(value)
        return [value, trimmed, normalized, normalized.lowercased(), normalized.uppercased()]
            .filter { !$0.isEmpty }
    }

    private static func sortKey(_ record: MemoryAssertionRecord) -> MemoryLibrarySortKey {
        MemoryLibrarySortKey(updatedAt: record.updatedAt, id: record.id)
    }

    private static func item(_ record: MemoryAssertionRecord) -> MemoryLibraryItem {
        MemoryLibraryItem(
            id: record.id,
            kind: record.kind,
            subject: record.subject,
            predicate: record.predicate,
            value: record.value,
            state: record.state,
            confidence: record.confidence,
            updatedAt: record.updatedAt,
            isPinned: record.isPinned,
            userVerified: record.userVerified
        )
    }
}
