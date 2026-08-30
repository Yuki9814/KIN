import Foundation
import SwiftData
#if DEBUG
import CoreData
#endif

struct PersistenceBootstrap {
    let container: ModelContainer
    let cloudRequested: Bool
    let usingCloud: Bool
    let configurationName: String
    let storageURL: URL
    let warning: String?

    func appendingWarning(_ additional: String?) -> PersistenceBootstrap {
        let combined = [warning, additional]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return PersistenceBootstrap(
            container: container,
            cloudRequested: cloudRequested,
            usingCloud: usingCloud,
            configurationName: configurationName,
            storageURL: storageURL,
            warning: combined.isEmpty ? nil : combined
        )
    }
}

enum PersistenceController {
    // v17 adds the optional MomentInteractionRecord.deletedAt column. Keep
    // this independent from the wire export version: a local SwiftData store
    // must receive a pre-migration backup even when older export readers can
    // safely ignore the new optional field.
    private static let currentSchemaVersion = 17
    private static let migrationBackupVersionKey = "persistence.localMigrationBackupVersion"

    static let schema = Schema([
        CompanionProfileRecord.self,
        CompanionMomentTaskRecord.self,
        UserProfileRecord.self,
        MomentPostRecord.self,
        MomentInteractionRecord.self,
        MomentAIInteractionTaskRecord.self,
        ConversationReadStateRecord.self,
        MomentReadStateRecord.self,
        CompanionRelationshipRecord.self,
        CompanionRelationshipTransitionRecord.self,
        FriendApplicationRecord.self,
        ConversationRecord.self,
        ConversationEvent.self,
        WorldProfileRecord.self,
        GroupConversationRecord.self,
        GroupParticipantRecord.self,
        ChatTurnPresentationRecord.self,
        ProactiveMessageTaskRecord.self,
        MemoryAssertionRecord.self,
        MemoryEvidenceRecord.self,
        MemorySummaryRecord.self,
        MemoryTombstoneRecord.self
    ])

    static func makeContainer(
        inMemory: Bool = false,
        preferCloud: Bool? = nil
    ) -> PersistenceBootstrap {
        let requested = preferCloud
            ?? UserDefaults.standard.bool(forKey: SettingsKeys.cloudSyncEnabled)

        if requested && !inMemory {
            let cloudConfiguration = cloudConfiguration()
            do {
                let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
                return PersistenceBootstrap(
                    container: container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: cloudConfiguration.name,
                    storageURL: cloudConfiguration.url,
                    warning: nil
                )
            } catch {
                let fallback = makeLocalBootstrap(inMemory: false, cloudRequested: true)
                return PersistenceBootstrap(
                    container: fallback.container,
                    cloudRequested: true,
                    usingCloud: false,
                    configurationName: fallback.configurationName,
                    storageURL: fallback.storageURL,
                    warning: fallback.warning
                ).appendingWarning(
                    "iCloud 容器不可用，已安全回退到本机存储。请检查签名、iCloud capability 与 Apple 账户。"
                )
            }
        }

        return makeLocalBootstrap(inMemory: inMemory, cloudRequested: requested)
    }

#if DEBUG
    /// The schema initializer is deliberately absent from Release builds.
    /// It only runs when a developer supplies both explicit launch arguments.
    static let cloudKitSchemaInitializationArgument = "-AyaneInitializeCloudKitSchema"
    static let cloudKitContainerIdentifierArgument = "-AyaneCloudKitContainerIdentifier"

    @MainActor
    static func initializeCloudKitSchemaIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        fileManager: FileManager = .default
    ) -> String? {
        guard arguments.contains(cloudKitSchemaInitializationArgument) else {
            return nil
        }

        let flagIndexes = arguments.indices.filter {
            arguments[$0] == cloudKitContainerIdentifierArgument
        }
        guard flagIndexes.count == 1 else {
            return "开发 schema 初始化需要且只能提供一个 "
                + cloudKitContainerIdentifierArgument
                + " 参数。"
        }
        let flagIndex = flagIndexes[0]
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return "开发 schema 初始化缺少 CloudKit container identifier。"
        }

        let identifier = arguments[valueIndex]
        guard isValidCloudKitContainerIdentifier(identifier) else {
            return "开发 schema 初始化拒绝无效的 CloudKit container identifier。"
        }

        do {
            try initializeCloudKitSchema(
                containerIdentifier: identifier,
                fileManager: fileManager
            )
            print("[Ayane][DEBUG] CloudKit development schema initialization finished for \(identifier).")
            return nil
        } catch {
            return "开发 CloudKit schema 初始化失败：\(error.localizedDescription)"
        }
    }

    private static func isValidCloudKitContainerIdentifier(_ identifier: String) -> Bool {
        identifier.range(
            of: #"^iCloud\.[A-Za-z0-9][A-Za-z0-9.-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func initializeCloudKitSchema(
        containerIdentifier: String,
        fileManager: FileManager
    ) throws {
        guard let managedObjectModel = makeManagedObjectModel(for: schema) else {
            throw CloudKitSchemaInitializationError.managedObjectModelUnavailable
        }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Ayane-CloudKit-Schema-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let persistentContainer = NSPersistentCloudKitContainer(
            name: "AyaneCloudKitSchemaDevelopment",
            managedObjectModel: managedObjectModel
        )
        let modelConfiguration = ModelConfiguration(
            "AyaneCloudKitSchemaDevelopment",
            schema: schema,
            url: temporaryDirectory.appendingPathComponent("Schema.sqlite"),
            cloudKitDatabase: .private(containerIdentifier)
        )
        let storeDescription = NSPersistentStoreDescription(
            url: modelConfiguration.url
        )
        storeDescription.shouldAddStoreAsynchronously = false
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        persistentContainer.persistentStoreDescriptions = [storeDescription]

        var loadError: Error?
        persistentContainer.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        // This is the Core Data bridge documented by Apple for generating a
        // development schema. SwiftData.ModelContainer itself has no public
        // initializeCloudKitSchema API.
        try persistentContainer.initializeCloudKitSchema(options: [.printSchema])

        for store in persistentContainer.persistentStoreCoordinator.persistentStores {
            try persistentContainer.persistentStoreCoordinator.remove(store)
        }
    }

    private static func makeManagedObjectModel(for schema: Schema) -> NSManagedObjectModel? {
        if #available(macOS 26, iOS 26, *) {
            return NSManagedObjectModel.makeManagedObjectModel(for: schema)
        }
        return nil
    }

    private enum CloudKitSchemaInitializationError: LocalizedError {
        case managedObjectModelUnavailable

        var errorDescription: String? {
            switch self {
            case .managedObjectModelUnavailable:
                return "开发 schema 初始化需要 macOS 26 或 iOS 26；应用的正常运行仍支持 macOS 14 与 iOS 17。"
            }
        }
    }
#endif

    /// Opens exactly the requested backend and never redirects a cloud source
    /// to the local store. Migration uses this to avoid reading the wrong side.
    @MainActor
    static func makeExactContainer(_ usingCloud: Bool) throws -> PersistenceBootstrap {
        if usingCloud {
            let configuration = cloudConfiguration()
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return PersistenceBootstrap(
                container: container,
                cloudRequested: true,
                usingCloud: true,
                configurationName: configuration.name,
                storageURL: configuration.url,
                warning: nil
            )
        }

        let configuration = localConfiguration(inMemory: false)
        let backupWarning = createLocalMigrationBackupIfNeeded(storeURL: configuration.url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return PersistenceBootstrap(
            container: container,
            cloudRequested: false,
            usingCloud: false,
            configurationName: configuration.name,
            storageURL: configuration.url,
            warning: backupWarning
        )
    }

    private static func makeLocalBootstrap(
        inMemory: Bool,
        cloudRequested: Bool
    ) -> PersistenceBootstrap {
        let configuration = localConfiguration(inMemory: inMemory)
        let backupWarning = inMemory
            ? nil
            : createLocalMigrationBackupIfNeeded(storeURL: configuration.url)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建 KIN 数据库：\(error.localizedDescription)")
        }
        return PersistenceBootstrap(
            container: container,
            cloudRequested: cloudRequested,
            usingCloud: false,
            configurationName: configuration.name,
            storageURL: configuration.url,
            warning: backupWarning
        )
    }

    /// Before the first v17 open, retain a physical copy of the local SQLite
    /// store and its sidecars. This runs before SwiftData can migrate the file,
    /// is skipped for new installs and in-memory tests, and never overwrites an
    /// earlier backup.
    private static func createLocalMigrationBackupIfNeeded(
        storeURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> String? {
        guard defaults.integer(forKey: migrationBackupVersionKey) < currentSchemaVersion else {
            return nil
        }
        guard fileManager.fileExists(atPath: storeURL.path) else {
            defaults.set(currentSchemaVersion, forKey: migrationBackupVersionKey)
            return nil
        }

        let backupRoot = storeURL.deletingLastPathComponent()
            .appendingPathComponent("MigrationBackups", isDirectory: true)
        let backupDirectory = backupRoot.appendingPathComponent(
            "pre-v\(currentSchemaVersion)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
            let sourceURLs = [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-wal"),
                URL(fileURLWithPath: storeURL.path + "-shm")
            ]
            for source in sourceURLs where fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(
                    at: source,
                    to: backupDirectory.appendingPathComponent(source.lastPathComponent)
                )
            }
            defaults.set(currentSchemaVersion, forKey: migrationBackupVersionKey)
            return nil
        } catch {
            try? fileManager.removeItem(at: backupDirectory)
            return "v\(currentSchemaVersion) 数据迁移前的本地备份暂未完成，将在下次启动重试：\(error.localizedDescription)"
        }
    }

    private static func localConfiguration(inMemory: Bool) -> ModelConfiguration {
        let configuration = ModelConfiguration(
            "AyaneLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return configuration
    }

    private static func cloudConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "AyaneCloud",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
    }
}
