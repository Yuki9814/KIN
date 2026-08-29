import CoreData
import Foundation
import SwiftData

/// Persistent marker for the period after a cloud-to-local migration's first
/// snapshot. The migration journal itself is deliberately retained as well:
/// older builds and recovery code can still see the original direction, while
/// this marker carries the fact that delayed CloudKit imports must be drained.
struct CloudSourceDrainState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let migrationID: UUID
    let source: AyaneStorageKind
    let destination: AyaneStorageKind
    let startedAt: Date

    init(
        id: UUID = UUID(),
        migrationID: UUID,
        source: AyaneStorageKind = .cloud,
        destination: AyaneStorageKind = .local,
        startedAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.migrationID = migrationID
        self.source = source
        self.destination = destination
        self.startedAt = startedAt
    }
}

enum CloudSourceDrainJournalError: LocalizedError, Equatable {
    case unreadableJournal
    case unsupportedJournal(Int)
    case invalidDirection
    case migrationMismatch
    case missingMigration

    var errorDescription: String? {
        switch self {
        case .unreadableJournal:
            return "CloudKit 延迟补收记录损坏；补收未执行，原记录已保留。"
        case .unsupportedJournal(let version):
            return "CloudKit 延迟补收记录版本 \(version) 与当前应用不兼容。"
        case .invalidDirection:
            return "CloudKit 延迟补收记录的源和目标方向无效。"
        case .migrationMismatch:
            return "CloudKit 延迟补收记录与当前存储切换记录不一致；未覆盖原记录。"
        case .missingMigration:
            return "找不到 cloud→local 存储切换记录；延迟补收未启动。"
        }
    }
}

/// Owns the separate persistent marker used by CloudSourceDrainSession.
/// Every write path is compare-before-write so a malformed or unrelated value
/// is never silently repaired by replacing it.
enum CloudSourceDrainJournal {
    static let defaultsKey = "persistence.pendingCloudSourceDrain"

    static func load(defaults: UserDefaults = .standard) throws -> CloudSourceDrainState? {
        guard let raw = defaults.object(forKey: defaultsKey) else { return nil }
        guard let data = raw as? Data else {
            throw CloudSourceDrainJournalError.unreadableJournal
        }

        let state: CloudSourceDrainState
        do {
            state = try PropertyListDecoder().decode(CloudSourceDrainState.self, from: data)
        } catch {
            throw CloudSourceDrainJournalError.unreadableJournal
        }
        guard state.version == CloudSourceDrainState.currentVersion else {
            throw CloudSourceDrainJournalError.unsupportedJournal(state.version)
        }
        guard state.source == .cloud, state.destination == .local else {
            throw CloudSourceDrainJournalError.invalidDirection
        }
        return state
    }

    /// Creates a marker only when the key is absent. An existing marker must
    /// belong to the same migration; otherwise the caller gets an error and
    /// the original bytes remain untouched.
    @discardableResult
    static func beginIfAbsent(
        migrationID: UUID,
        startedAt: Date,
        defaults: UserDefaults = .standard
    ) throws -> CloudSourceDrainState {
        if let existing = try load(defaults: defaults) {
            guard existing.migrationID == migrationID else {
                throw CloudSourceDrainJournalError.migrationMismatch
            }
            return existing
        }
        guard defaults.object(forKey: defaultsKey) == nil else {
            // `load` normally catches this, but retain the invariant if a
            // concurrent writer populated the key between calls.
            throw CloudSourceDrainJournalError.unreadableJournal
        }

        let state = CloudSourceDrainState(
            migrationID: migrationID,
            startedAt: startedAt
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        defaults.set(try encoder.encode(state), forKey: defaultsKey)
        return state
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

enum CloudSourceDrainStatus: Equatable, Sendable {
    case idle
    case starting
    case draining
    case waiting
    case failed(String)
    case cancelled
    case stopped
}

struct CloudSourceDrainSnapshot: Equatable, Sendable {
    let status: CloudSourceDrainStatus
    let attempts: Int
    let successfulDrains: Int
    let lastRunAt: Date?
    let lastSuccessfulRunAt: Date?
    let lastReport: DataMergeReport?
    let lastError: String?
    let sourceContainerRetained: Bool
}

struct CloudSourceDrainResult: Equatable, Sendable {
    let status: CloudSourceDrainStatus
    let report: DataMergeReport?
    let message: String
}

/// Keeps a cloud source ModelContainer alive while a local destination is the
/// active store, repeatedly merging newly imported CloudKit records. The
/// session never assumes that the first snapshot is complete and never clears
/// either journal on its own.
@MainActor
final class CloudSourceDrainSession {
    typealias ContainerFactory = StorageMigrationCoordinator.ContainerFactory
    typealias SnapshotHandler = @MainActor (CloudSourceDrainSnapshot) -> Void
    typealias MergeHandler = @MainActor (DataMergeReport) -> Void
    typealias ErrorHandler = @MainActor (String) -> Void
    typealias IntegrityConflictHandler = @MainActor (StoreDuplicateReconcileError) -> Void

    private let destination: PersistenceBootstrap
    private let defaults: UserDefaults
    private let sourceFactory: ContainerFactory
    private let pollInterval: TimeInterval?

    /// The bootstrap is retained for the entire session. A new read context is
    /// created for each drain so delayed imports already committed by
    /// CoreData/CloudKit are visible without rebuilding the container.
    private var sourceBootstrap: PersistenceBootstrap?
    private var initialDrainTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var remoteDrainTask: Task<Void, Never>?
    private var remoteStoreChangeObserver: NSObjectProtocol?
    private var hasStarted = false
    private var didConfirmStop = false
    private var lifecycleGeneration: UInt64 = 0
    private var isDrainInProgress = false
    private var attempts = 0
    private var successfulDrains = 0
    private var lastRunAt: Date?
    private var lastSuccessfulRunAt: Date?
    private var lastReport: DataMergeReport?
    private var lastError: String?

    private(set) var status: CloudSourceDrainStatus = .idle {
        didSet { notifyUpdate() }
    }

    /// Called for every status transition and completed/failed run.
    var onUpdate: SnapshotHandler?

    /// Called after the destination save and independent validation succeed.
    var onMerge: MergeHandler?

    /// Called when a run fails. The journal remains available for retry.
    var onError: ErrorHandler?

    /// Preserves the typed duplicate conflict so AppModel can quarantine the
    /// affected IDs and stop chat/memory work instead of receiving only text.
    var onIntegrityConflict: IntegrityConflictHandler?

    init(
        destination: PersistenceBootstrap,
        defaults: UserDefaults = .standard,
        sourceFactory: @escaping ContainerFactory = PersistenceController.makeExactContainer,
        pollInterval: TimeInterval? = 30
    ) {
        self.destination = destination
        self.defaults = defaults
        self.sourceFactory = sourceFactory
        self.pollInterval = pollInterval
    }

    deinit {
        initialDrainTask?.cancel()
        pollingTask?.cancel()
        remoteDrainTask?.cancel()
        if let remoteStoreChangeObserver {
            NotificationCenter.default.removeObserver(remoteStoreChangeObserver)
        }
    }

    var snapshot: CloudSourceDrainSnapshot {
        CloudSourceDrainSnapshot(
            status: status,
            attempts: attempts,
            successfulDrains: successfulDrains,
            lastRunAt: lastRunAt,
            lastSuccessfulRunAt: lastSuccessfulRunAt,
            lastReport: lastReport,
            lastError: lastError,
            sourceContainerRetained: sourceBootstrap != nil
        )
    }

    var isRunning: Bool {
        switch status {
        case .starting, .draining, .waiting:
            return !didConfirmStop
        case .idle, .failed, .cancelled, .stopped:
            return false
        }
    }

    /// Starts notifications, low-frequency polling, and one deferred first
    /// drain. Deferring one executor turn lets app initialization and the first
    /// frame finish before any CloudKit container open or merge work begins.
    /// A failed first attempt still leaves polling installed for recovery.
    func start() {
        guard !hasStarted, !didConfirmStop else { return }
        hasStarted = true
        status = .starting
        guard !didConfirmStop, status != .cancelled else { return }
        installRemoteStoreChangeObserverIfNeeded()
        startPollingIfNeeded()
        guard !didConfirmStop, status != .cancelled else { return }
        guard attempts == 0 else { return }
        initialDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.initialDrainTask = nil }
            await Task.yield()
            guard !Task.isCancelled,
                  !self.didConfirmStop,
                  self.status != .cancelled,
                  self.attempts == 0 else { return }
            _ = self.drainNow()
        }
    }

    /// Cancels active work and observers without changing either persistent
    /// record. The session can therefore be resumed by a later app launch.
    func cancel() {
        guard !didConfirmStop else { return }
        guard status != .cancelled else {
            sourceBootstrap = nil
            return
        }
        lifecycleGeneration &+= 1
        initialDrainTask?.cancel()
        initialDrainTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        remoteDrainTask?.cancel()
        remoteDrainTask = nil
        if let remoteStoreChangeObserver {
            NotificationCenter.default.removeObserver(remoteStoreChangeObserver)
            self.remoteStoreChangeObserver = nil
        }
        sourceBootstrap = nil
        status = .cancelled
    }

    /// Explicit user-confirmed stop. Only this operation clears the
    /// cloud-to-local migration and drain markers; automatic drains and
    /// cancellation preserve them for crash-safe retry.
    func confirmStopAfterUserConfirmation() {
        guard !didConfirmStop else { return }
        cancel()
        didConfirmStop = true
        StorageMigrationJournal.clear(defaults: defaults)
        CloudSourceDrainJournal.clear(defaults: defaults)
        status = .stopped
    }

    /// Short alias for UI/controller code that already has an explicit
    /// confirmation gate around the call.
    func stopAfterUserConfirmation() {
        confirmStopAfterUserConfirmation()
    }

    /// Performs one idempotent source snapshot merge. This synchronous API is
    /// intentionally easy to exercise from startup and deterministic tests;
    /// the low-frequency scheduler calls the same method.
    @discardableResult
    func drainNow(now: Date = Date()) -> CloudSourceDrainResult {
        guard !didConfirmStop else {
            return CloudSourceDrainResult(
                status: .stopped,
                report: nil,
                message: "CloudKit 延迟补收已按用户确认停止。"
            )
        }
        if status == .cancelled {
            return CloudSourceDrainResult(
                status: .cancelled,
                report: nil,
                message: "CloudKit 延迟补收已取消；补收记录仍保留。"
            )
        }
        guard !isDrainInProgress else {
            return CloudSourceDrainResult(
                status: status,
                report: nil,
                message: "已有一次 CloudKit 延迟补收正在执行，未启动重入任务。"
            )
        }

        isDrainInProgress = true
        defer { isDrainInProgress = false }
        let runGeneration = lifecycleGeneration

        attempts += 1
        lastRunAt = now
        lastError = nil
        status = .draining
        guard isRunCurrent(runGeneration) else {
            return interruptedResult()
        }

        do {
            guard !destination.usingCloud else {
                throw CloudSourceDrainJournalError.invalidDirection
            }
            try ensureDrainMarker()
            let source = try sourceContainer()
            guard source.usingCloud else {
                throw StorageMigrationJournalError.unreadableJournal
            }

            let sourceContext = ModelContext(source.container)
            // Build a canonical payload from records fetched before any staged
            // deletion. The source is never saved or refetched while dirty.
            let payload = try StoreDuplicateReconciler.makeCanonicalPayload(
                context: sourceContext,
                defaults: defaults,
                now: now
            )
            guard isRunCurrent(runGeneration) else {
                return interruptedResult()
            }

            let destinationContext = ModelContext(destination.container)
            // Destination deduplication is staged and committed by the one
            // DataMergeService save together with new/updated source records.
            _ = try StoreDuplicateReconciler.stage(context: destinationContext)
            let report = try DataMergeService.merge(
                payload,
                into: destinationContext
            )

            let merged = try DataExportService.makePayload(
                context: destinationContext,
                defaults: defaults,
                now: now
            )
            try DataImportService.validate(merged)
            guard isRunCurrent(runGeneration) else {
                return interruptedResult()
            }

            successfulDrains += 1
            lastSuccessfulRunAt = now
            lastReport = report
            status = .waiting
            let message = "已完成第 \(successfulDrains) 次 CloudKit 延迟补收：新增 \(report.totalInserted) 条，更新 \(report.totalUpdated) 条；补收记录继续保留。"
            guard isRunCurrent(runGeneration), status == .waiting else {
                return interruptedResult()
            }
            onMerge?(report)
            guard isRunCurrent(runGeneration), status == .waiting else {
                return interruptedResult()
            }
            return CloudSourceDrainResult(
                status: .waiting,
                report: report,
                message: message
            )
        } catch let error as StoreDuplicateReconcileError {
            guard isRunCurrent(runGeneration) else {
                return interruptedResult()
            }
            onIntegrityConflict?(error)
            guard isRunCurrent(runGeneration) else {
                return interruptedResult()
            }
            let message = error.localizedDescription
            lastError = message
            status = .failed(message)
            guard isRunCurrent(runGeneration), status == .failed(message) else {
                return interruptedResult()
            }
            onError?(message)
            guard isRunCurrent(runGeneration), status == .failed(message) else {
                return interruptedResult()
            }
            return CloudSourceDrainResult(
                status: .failed(message),
                report: nil,
                message: message
            )
        } catch {
            guard isRunCurrent(runGeneration) else {
                return interruptedResult()
            }
            let message = error.localizedDescription
            lastError = message
            status = .failed(message)
            guard isRunCurrent(runGeneration), status == .failed(message) else {
                return interruptedResult()
            }
            onError?(message)
            guard isRunCurrent(runGeneration), status == .failed(message) else {
                return interruptedResult()
            }
            return CloudSourceDrainResult(
                status: .failed(message),
                report: nil,
                message: message
            )
        }
    }

    private func ensureDrainMarker() throws {
        guard let migration = try StorageMigrationJournal.load(defaults: defaults),
              migration.source == .cloud,
              migration.target == .local else {
            throw CloudSourceDrainJournalError.missingMigration
        }

        if let state = try CloudSourceDrainJournal.load(defaults: defaults) {
            guard state.source == .cloud,
                  state.destination == .local else {
                throw CloudSourceDrainJournalError.invalidDirection
            }
            guard state.migrationID == migration.id else {
                throw CloudSourceDrainJournalError.migrationMismatch
            }
            return
        }

        _ = try CloudSourceDrainJournal.beginIfAbsent(
            migrationID: migration.id,
            startedAt: migration.requestedAt,
            defaults: defaults
        )
    }

    private func sourceContainer() throws -> PersistenceBootstrap {
        if let sourceBootstrap {
            return sourceBootstrap
        }
        let source = try sourceFactory(true)
        guard source.usingCloud else {
            throw StorageMigrationJournalError.unreadableJournal
        }
        sourceBootstrap = source
        return source
    }

    private func installRemoteStoreChangeObserverIfNeeded() {
        guard remoteStoreChangeObserver == nil else { return }
        remoteStoreChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRemoteDrain()
            }
        }
    }

    private func scheduleRemoteDrain() {
        guard !didConfirmStop, status != .cancelled else { return }
        remoteDrainTask?.cancel()
        remoteDrainTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            _ = self.drainNow()
            self.remoteDrainTask = nil
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil,
              let pollInterval,
              pollInterval.isFinite,
              pollInterval > 0 else { return }

        // Seven days is already far beyond the product's 30-second default and
        // keeps arbitrary finite configuration values inside UInt64 safely.
        let safeInterval = min(max(pollInterval, 0.001), 7 * 24 * 60 * 60)
        let nanoseconds = UInt64(safeInterval * 1_000_000_000)
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, !self.didConfirmStop else {
                    return
                }
                _ = self.drainNow()
            }
        }
    }

    private func notifyUpdate() {
        onUpdate?(snapshot)
    }

    private func isRunCurrent(_ generation: UInt64) -> Bool {
        generation == lifecycleGeneration
            && !didConfirmStop
            && status != .cancelled
            && status != .stopped
    }

    private func interruptedResult() -> CloudSourceDrainResult {
        let finalStatus: CloudSourceDrainStatus = didConfirmStop || status == .stopped
            ? .stopped
            : .cancelled
        let message = finalStatus == .stopped
            ? "CloudKit 延迟补收已按用户确认停止，本次任务未继续写入。"
            : "CloudKit 延迟补收已取消，本次任务未继续写入；补收记录仍保留。"
        return CloudSourceDrainResult(status: finalStatus, report: nil, message: message)
    }
}
