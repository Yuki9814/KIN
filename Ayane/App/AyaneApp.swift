import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
import UserNotifications

extension Notification.Name {
    static let kinProactiveNotificationRouteRequested = Notification.Name(
        "kin.proactive-notification.route-requested"
    )
}

@MainActor
final class KINNotificationRouter {
    static let shared = KINNotificationRouter()

    private(set) var pendingRoute: ProactiveNotificationRoute?

    var hasPendingRoute: Bool { pendingRoute != nil }

    func receive(userInfo: [AnyHashable: Any]) {
        guard let route = ProactiveNotificationRoute(userInfo: userInfo) else { return }
        pendingRoute = route
        NotificationCenter.default.post(
            name: .kinProactiveNotificationRouteRequested,
            object: nil
        )
    }

    func consume() -> ProactiveNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}

final class KINNotificationAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            KINNotificationRouter.shared.receive(
                userInfo: response.notification.request.content.userInfo
            )
        }
    }
}

#if DEBUG
@MainActor
private enum LocalNotificationQAFixture {
    static let delayArgument = "-KINNotificationQADelaySeconds"
    private static let lastIdentifierKey = "debug.notificationQA.lastIdentifier"

    static func runIfRequested(on appModel: AppModel) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: delayArgument),
              arguments.indices.contains(flagIndex + 1),
              let requestedDelay = TimeInterval(arguments[flagIndex + 1]) else {
            await reportPreviousDeliveryIfNeeded()
            return
        }

        let delay = max(5, requestedDelay)
        let route = ProactiveNotificationRoute(
            taskID: UUID(),
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            stage: .test
        )
        let didSchedule = await ProactiveNotificationService.shared.schedule(
            route: route,
            title: appModel.persona.name,
            body: "测试通知：即使 KIN 被划掉，我也还能来找你。",
            at: Date().addingTimeInterval(delay)
        )
        if didSchedule {
            UserDefaults.standard.set(route.requestIdentifier, forKey: lastIdentifierKey)
        }
        print(
            "[KIN][NotificationQA] scheduled=\(didSchedule) "
                + "identifier=\(route.requestIdentifier) delay=\(Int(delay))"
        )
    }

    static func reportPreviousDeliveryIfNeeded() async {
        guard let identifier = UserDefaults.standard.string(forKey: lastIdentifierKey) else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: Set(requests.map { $0.identifier })
                )
            }
        }
        let delivered = await ProactiveNotificationService.shared
            .deliveredNotificationIdentifiers()
        print(
            "[KIN][NotificationQA] delivered=\(delivered.contains(identifier)) "
                + "pending=\(pending.contains(identifier)) "
                + "authorization=\(settings.authorizationStatus.rawValue) "
                + "alert=\(settings.alertSetting.rawValue) "
                + "notificationCenter=\(settings.notificationCenterSetting.rawValue) "
                + "lockScreen=\(settings.lockScreenSetting.rawValue) "
                + "scheduledDelivery=\(settings.scheduledDeliverySetting.rawValue) "
                + "identifier=\(identifier)"
        )
    }
}
#endif
#endif

@main
@MainActor
struct AyaneApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(KINNotificationAppDelegate.self)
    private var notificationAppDelegate
    #endif

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
                    .task {
                        await LocalNotificationQAFixture.runIfRequested(on: appModel)
                    }
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
