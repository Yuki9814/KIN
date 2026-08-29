import Foundation
import SwiftData

enum MemoryTombstoneNormalizationError: LocalizedError, Equatable {
    case incomplete

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return "旧版遗忘标记尚未完成安全规范化；长期记忆暂不读取，请稍后重试。"
        }
    }
}

/// Incrementally upgrades legacy tombstones without ever materializing the
/// whole table. The completion bit lives on every durable row, so a delayed
/// CloudKit import from an older build is detected even after a prior scan had
/// completed. Memory reads call this barrier before evaluating tombstones;
/// failure is fail-closed rather than allowing an old fact to reappear.
@MainActor
enum MemoryTombstoneNormalizer {
    static let batchSize = 128

    @discardableResult
    static func normalizePending(
        context: ModelContext
    ) throws -> Int {
        let currentVersion = MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        var normalizedCount = 0

        while true {
            var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.canonicalKeyNormalizationVersion != currentVersion
                },
                sortBy: [
                    SortDescriptor(\.deletedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            descriptor.fetchLimit = batchSize
            descriptor.propertiesToFetch = [
                \MemoryTombstoneRecord.id,
                \MemoryTombstoneRecord.canonicalKey,
                \MemoryTombstoneRecord.canonicalKeyNormalizationVersion,
                \MemoryTombstoneRecord.deletedAt
            ]
            let records = try context.fetch(descriptor)
            guard !records.isEmpty else { break }

            for record in records {
                record.canonicalKey = MemoryTombstoneRecord.normalizedCanonicalKey(
                    record.canonicalKey
                )
                record.canonicalKeyNormalizationVersion = currentVersion
            }
            normalizedCount += records.count
            // Persist every bounded page before asking SwiftData for the next
            // one. Besides keeping dirty state bounded, this prevents a store
            // implementation from returning the same database-backed legacy
            // rows repeatedly while their in-memory values are still unsaved.
            try context.save()
        }

        guard try !hasPending(context: context) else {
            throw MemoryTombstoneNormalizationError.incomplete
        }
        return normalizedCount
    }

    static func hasPending(context: ModelContext) throws -> Bool {
        let currentVersion = MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
            predicate: #Predicate {
                $0.canonicalKeyNormalizationVersion != currentVersion
            }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [
            \MemoryTombstoneRecord.id,
            \MemoryTombstoneRecord.canonicalKeyNormalizationVersion
        ]
        return try !context.fetch(descriptor).isEmpty
    }

    /// Hot reads and mutations never attempt a partial compatibility scan.
    /// AppModel owns the durable migration at startup/remote refresh; if an
    /// old CloudKit row races that pass, this barrier keeps memory fail-closed
    /// until the next normalization pass completes.
    static func requireComplete(context: ModelContext) throws {
        guard try !hasPending(context: context) else {
            throw MemoryTombstoneNormalizationError.incomplete
        }
    }
}
