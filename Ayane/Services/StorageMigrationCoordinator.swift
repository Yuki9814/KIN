import Foundation
import SwiftData

enum AyaneStorageKind: String, Codable, Equatable, Sendable {
    case local
    case cloud

    init(usesCloud: Bool) {
        self = usesCloud ? .cloud : .local
    }

    var usesCloud: Bool { self == .cloud }

    var title: String {
        switch self {
        case .local: "仅本机"
        case .cloud: "iCloud 私有数据库"
        }
    }
}

struct PendingStorageMigration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let source: AyaneStorageKind
    let target: AyaneStorageKind
    let requestedAt: Date

    init(
        id: UUID = UUID(),
        source: AyaneStorageKind,
        target: AyaneStorageKind,
        requestedAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.source = source
        self.target = target
        self.requestedAt = requestedAt
    }
}

enum StorageMigrationJournalError: LocalizedError, Equatable {
    case unreadableJournal
    case unsupportedJournal(Int)
    case sameSourceAndTarget

    var errorDescription: String? {
        switch self {
        case .unreadableJournal:
            "存储切换记录损坏；当前数据库未被改动。"
        case .unsupportedJournal(let version):
            "存储切换记录版本 \(version) 与当前应用不兼容。"
        case .sameSourceAndTarget:
            "源存储和目标存储相同，无需迁移。"
        }
    }
}

enum StorageMigrationJournal {
    static let defaultsKey = "persistence.pendingStoreMigration"

    static func load(defaults: UserDefaults = .standard) throws -> PendingStorageMigration? {
        // `data(forKey:)` returns nil for a value of the wrong type. Treating
        // that as an absent journal would let the automatic fallback path
        // overwrite a damaged record. Inspect the raw object first so every
        // non-Data value is conservatively considered unreadable.
        guard let raw = defaults.object(forKey: defaultsKey) else { return nil }
        guard let data = raw as? Data else {
            throw StorageMigrationJournalError.unreadableJournal
        }
        let decoder = PropertyListDecoder()
        let migration: PendingStorageMigration
        do {
            migration = try decoder.decode(PendingStorageMigration.self, from: data)
        } catch {
            throw StorageMigrationJournalError.unreadableJournal
        }
        guard migration.version == PendingStorageMigration.currentVersion else {
            throw StorageMigrationJournalError.unsupportedJournal(migration.version)
        }
        guard migration.source != migration.target else {
            throw StorageMigrationJournalError.sameSourceAndTarget
        }
        return migration
    }

    @discardableResult
    static func stage(
        source: AyaneStorageKind,
        target: AyaneStorageKind,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> PendingStorageMigration {
        guard source != target else {
            throw StorageMigrationJournalError.sameSourceAndTarget
        }
        let migration = PendingStorageMigration(
            source: source,
            target: target,
            requestedAt: now
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(migration)
        defaults.set(data, forKey: defaultsKey)
        return migration
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Stages the recovery migration created by a CloudKit open failure.
    ///
    /// This method is deliberately compare-before-write. A valid pending
    /// migration, a drain marker, or even a malformed value all block the
    /// automatic path; only an actually absent key may be populated here.
    @discardableResult
    static func stageLocalToCloudIfAbsent(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> PendingStorageMigration? {
        guard defaults.object(forKey: defaultsKey) == nil else { return nil }
        return try stage(
            source: .local,
            target: .cloud,
            defaults: defaults,
            now: now
        )
    }
}

struct StorageMigrationStartupResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case none
        case completed
        /// The first cloud-to-local merge succeeded, but the cloud source is
        /// intentionally retained for delayed-import draining.
        case draining
        case deferred
        case invalidJournal
    }

    let state: State
    let message: String?

    static let none = StorageMigrationStartupResult(state: .none, message: nil)
}

@MainActor
enum StorageMigrationCoordinator {
    typealias ContainerFactory = @MainActor (Bool) throws -> PersistenceBootstrap

    /// Records a retryable local-to-cloud migration when the requested CloudKit
    /// container fell back to a local store. Existing and malformed journal
    /// values are never replaced by this automatic recovery path.
    static func ensureFallbackJournalIfNeeded(
        destination: PersistenceBootstrap,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> StorageMigrationStartupResult {
        guard destination.cloudRequested, !destination.usingCloud else {
            return .none
        }

        // Protect an independent drain marker before looking at the migration
        // key. A stale-but-valid marker means this local store is already the
        // destination of a cloud drain; it must not be replaced with a new
        // local→cloud intent. A malformed marker is likewise left untouched.
        do {
            if try CloudSourceDrainJournal.load(defaults: defaults) != nil {
                return StorageMigrationStartupResult(
                    state: .deferred,
                    message: "检测到仍在进行的 CloudKit 延迟补收记录；未覆盖，当前继续使用本机存储。"
                )
            }
        } catch {
            return StorageMigrationStartupResult(
                state: .invalidJournal,
                message: error.localizedDescription
            )
        }

        // Diagnose an existing migration value before attempting the
        // compare-before-write fallback stage. This keeps valid, unsupported,
        // and malformed bytes intact.
        do {
            if let existing = try StorageMigrationJournal.load(defaults: defaults) {
                return StorageMigrationStartupResult(
                    state: .deferred,
                    message: "iCloud 容器不可用；已有 \(existing.source.title)→\(existing.target.title) 切换记录，未覆盖，当前继续使用本机存储。"
                )
            }
        } catch {
            return StorageMigrationStartupResult(
                state: .invalidJournal,
                message: error.localizedDescription
            )
        }

        do {
            guard try StorageMigrationJournal.stageLocalToCloudIfAbsent(
                defaults: defaults,
                now: now
            ) != nil else {
                // The key was populated between the read above and this final
                // compare-before-write. Do not attempt a second write.
                return StorageMigrationStartupResult(
                    state: .deferred,
                    message: "iCloud 容器不可用；存储切换记录未被覆盖，当前继续使用本机存储。"
                )
            }
            return StorageMigrationStartupResult(
                state: .deferred,
                message: "iCloud 容器不可用，已为本机回退自动保留 local→cloud 补偿记录；当前继续使用本机存储，本次及之后的本机写入会在云端可用时合并。"
            )
        } catch {
            // Encoding failure is exceptionally unlikely, but if it occurs no
            // setting is changed and the caller receives an explicit warning.
            return StorageMigrationStartupResult(
                state: .deferred,
                message: "iCloud 容器不可用，无法写入本机回退补偿记录：\(error.localizedDescription)"
            )
        }
    }

    /// Alias with the terminology used by callers that treat the bootstrap as
    /// the active destination. Keeping the small wrapper makes the recovery
    /// entry point easy to discover without duplicating write logic.
    static func stageFallbackJournalIfNeeded(
        destination: PersistenceBootstrap,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> StorageMigrationStartupResult {
        ensureFallbackJournalIfNeeded(
            destination: destination,
            defaults: defaults,
            now: now
        )
    }

    /// Resumes a previously confirmed switch before AppModel starts writing.
    /// The source store remains intact. local→cloud clears its retry journal
    /// only after the destination save and validation succeed; cloud→local
    /// deliberately retains both migration and drain records for delayed
    /// CloudKit imports.
    static func resumeIfNeeded(
        destination: PersistenceBootstrap,
        defaults: UserDefaults = .standard,
        sourceFactory: ContainerFactory = PersistenceController.makeExactContainer
    ) -> StorageMigrationStartupResult {
        let migration: PendingStorageMigration
        do {
            guard let loaded = try StorageMigrationJournal.load(defaults: defaults) else {
                return .none
            }
            migration = loaded
        } catch {
            return StorageMigrationStartupResult(
                state: .invalidJournal,
                message: error.localizedDescription
            )
        }

        guard destination.usingCloud == migration.target.usesCloud else {
            let detail = migration.target == .cloud
                ? "iCloud 容器尚不可用"
                : "目标本机数据库尚未打开"
            return StorageMigrationStartupResult(
                state: .deferred,
                message: "\(detail)，跨存储合并尚未执行；源数据库与切换记录均已保留，下次启动会重试。"
            )
        }

        do {
            let source = try sourceFactory(migration.source.usesCloud)
            guard source.usingCloud == migration.source.usesCloud else {
                return StorageMigrationStartupResult(
                    state: .deferred,
                    message: "无法打开原 \(migration.source.title)；目标数据库未写入，切换记录已保留。"
                )
            }

            let sourceContext = ModelContext(source.container)
            let destinationContext = ModelContext(destination.container)

            // Canonicalize and export from an already-held source snapshot.
            // The helper never saves and always rolls staged changes back, so
            // migration cannot rewrite the source store or refetch after a
            // pending deletion.
            let payload = try StoreDuplicateReconciler.makeCanonicalPayload(
                context: sourceContext,
                defaults: defaults
            )

            // Destination duplicate collapse and the additive merge now share
            // DataMergeService's single atomic save. If planning or saving
            // fails, its rollback also restores this staged reconciliation.
            _ = try StoreDuplicateReconciler.stage(context: destinationContext)
            let report = try DataMergeService.merge(
                payload,
                into: destinationContext
            )

            // Re-exporting and validating the destination is an independent
            // post-save integrity gate before the retry journal is removed.
            let merged = try DataExportService.makePayload(
                context: destinationContext,
                defaults: defaults
            )
            try DataImportService.validate(merged)

            if migration.target == .local, migration.source == .cloud {
                // CloudKit imports are eventually consistent. Keeping both the
                // migration journal and a dedicated drain marker means a late
                // source event can be imported after this first successful
                // snapshot. The local database is the actual active target,
                // but the switch is not reported as fully finished yet.
                do {
                    try CloudSourceDrainJournal.beginIfAbsent(
                        migrationID: migration.id,
                        startedAt: migration.requestedAt,
                        defaults: defaults
                    )
                } catch {
                    return StorageMigrationStartupResult(
                        state: .deferred,
                        message: "首次 cloud→local 合并已写入目标，但无法保留延迟补收记录：\(error.localizedDescription)；切换记录仍保留，尚未宣称完成。"
                    )
                }

                defaults.set(false, forKey: SettingsKeys.cloudSyncEnabled)
                return StorageMigrationStartupResult(
                    state: .draining,
                    message: "已把原 iCloud 私有数据库非破坏性合并到本机：新增 \(report.totalInserted) 条，更新 \(report.totalUpdated) 条；本机已作为当前目标，CloudKit 源与切换记录继续保留，后台会持续补收延迟导入，需确认停止后才结束。"
                )
            }

            // local→cloud has no delayed source to drain. It is safe to clear
            // the retry journal only after the destination save and validation
            // above both succeed.
            StorageMigrationJournal.clear(defaults: defaults)
            CloudSourceDrainJournal.clear(defaults: defaults)
            defaults.set(migration.target.usesCloud, forKey: SettingsKeys.cloudSyncEnabled)
            return StorageMigrationStartupResult(
                state: .completed,
                message: "已把原 \(migration.source.title) 非破坏性合并到 \(migration.target.title)：新增 \(report.totalInserted) 条，更新 \(report.totalUpdated) 条；源数据库仍完整保留。"
            )
        } catch {
            return StorageMigrationStartupResult(
                state: .deferred,
                message: "跨存储合并未完成：\(error.localizedDescription) 源数据库和切换记录均已保留，下次启动会重试。"
            )
        }
    }
}
