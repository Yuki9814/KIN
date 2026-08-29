import SwiftData
import SwiftUI

@main
@MainActor
struct AyaneApp: App {
    @State private var appModel: AppModel
    private let container: ModelContainer
    /// Retained for the lifetime of the app so a local destination continues
    /// receiving delayed CloudKit imports after the first migration snapshot.
    private let cloudSourceDrainSession: CloudSourceDrainSession?

    init() {
#if DEBUG
        if SendCrashRegressionFixture.isRequested {
            let fixture = SendCrashRegressionFixture.make()
            self.container = fixture.bootstrap.container
            _appModel = State(initialValue: fixture.appModel)
            self.cloudSourceDrainSession = nil
            return
        }
#endif
        SettingsStore.registerDefaults()
        SettingsStore.migrateProviderSelectionIfNeeded()
        let providerKeychainWarning: String?
        do {
            try SettingsStore.migrateLegacyAPIKeyIfNeeded()
            providerKeychainWarning = nil
        } catch {
            providerKeychainWarning = "旧版 API Key 尚未迁移：\(error.localizedDescription)"
        }
        let subscriptionImportWarning =
            LocalSubscriptionCredentialImporter.importPendingIfAvailable()
#if DEBUG
        let schemaInitializationWarning = PersistenceController.initializeCloudKitSchemaIfRequested()
#else
        let schemaInitializationWarning: String? = nil
#endif
        let pendingMigration: PendingStorageMigration?
        let journalWarning: String?
        do {
            pendingMigration = try StorageMigrationJournal.load()
            journalWarning = nil
        } catch {
            pendingMigration = nil
            journalWarning = error.localizedDescription
        }

        let pendingDrain: CloudSourceDrainState?
        let drainJournalWarning: String?
        do {
            pendingDrain = try CloudSourceDrainJournal.load()
            drainJournalWarning = nil
        } catch {
            pendingDrain = nil
            drainJournalWarning = error.localizedDescription
        }

        let requestedCloud: Bool
        if let pendingMigration {
            requestedCloud = pendingMigration.target.usesCloud
        } else if pendingDrain != nil {
            requestedCloud = false
        } else {
            requestedCloud = UserDefaults.standard.bool(forKey: SettingsKeys.cloudSyncEnabled)
        }
        var bootstrap = PersistenceController.makeContainer(preferCloud: requestedCloud)
        bootstrap = bootstrap.appendingWarning(schemaInitializationWarning)
        bootstrap = bootstrap.appendingWarning(journalWarning)
        bootstrap = bootstrap.appendingWarning(drainJournalWarning)
        bootstrap = bootstrap.appendingWarning(providerKeychainWarning)
        bootstrap = bootstrap.appendingWarning(subscriptionImportWarning)

        // A CloudKit open failure can happen before the user ever confirms a
        // storage switch. Persist a recovery intent now, before AppModel can
        // write more local records. Existing or malformed journals are never
        // replaced by this automatic path.
        let fallback = StorageMigrationCoordinator.ensureFallbackJournalIfNeeded(
            destination: bootstrap
        )
        bootstrap = bootstrap.appendingWarning(fallback.message)

        if pendingMigration != nil {
            let migration = StorageMigrationCoordinator.resumeIfNeeded(
                destination: bootstrap
            )
            bootstrap = bootstrap.appendingWarning(migration.message)
        }

        #if DEBUG
        bootstrap = bootstrap.appendingWarning(
            VisualQAFixture.seedIfRequested(in: bootstrap.container)
        )
        #endif

        self.container = bootstrap.container
        let model = AppModel(bootstrap: bootstrap)
        _appModel = State(initialValue: model)

        // Keep the source container open whenever a cloud→local journal is
        // active. The session's callbacks are intentionally thin here; the
        // AppModel/Settings layer can additionally expose status and the
        // explicit user-confirmed stop action without changing persistence
        // ownership.
        // Reuse the values loaded (and warning-checked) at the beginning of
        // initialization. Re-reading here could turn a second decode failure
        // into a silent `false` and hide a retained recovery record.
        let migrationNeedsDrain = pendingMigration?.source == .cloud
            && pendingMigration?.target == .local
        let drainMarkerExists = pendingDrain != nil
        let shouldDrain = migrationNeedsDrain || drainMarkerExists

        if shouldDrain, !bootstrap.usingCloud {
            let session = CloudSourceDrainSession(destination: bootstrap)
            model.attachCloudSourceDrainSession(session)
            self.cloudSourceDrainSession = session
            session.start()
        } else {
            self.cloudSourceDrainSession = nil
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .tint(AppTheme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 946, height: 642)

        Settings {
            SettingsView()
                .environment(appModel)
                .modelContainer(container)
                .tint(AppTheme.accent)
        }
        #else
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                VisualQAFixture.scheduledTasksLaunchArgument
            ) {
                NavigationStack {
                    ScheduledTasksHomeView()
                }
                .environment(appModel)
                .modelContainer(container)
                .tint(AppTheme.accent)
            } else if ProcessInfo.processInfo.arguments.contains(
                VisualQAFixture.scheduledCalendarLaunchArgument
            ) {
                NavigationStack {
                    ScheduledTasksCalendarView()
                }
                .environment(appModel)
                .modelContainer(container)
                .tint(AppTheme.accent)
            } else if SendCrashRegressionFixture.isRequested {
                ChatView()
                    .environment(appModel)
                    .modelContainer(container)
                    .tint(AppTheme.accent)
                    .task {
                        await SendCrashRegressionFixture.run(on: appModel)
                    }
            } else if SubscriptionConnectionRegressionFixture.isRequested {
                Color.clear
                    .task {
                        await SubscriptionConnectionRegressionFixture.run()
                    }
            } else {
                RootView()
                    .environment(appModel)
                    .modelContainer(container)
                    .tint(AppTheme.accent)
            }
            #else
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .tint(AppTheme.accent)
            #endif
        }
        #endif
    }
}
