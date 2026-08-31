import CryptoKit
import Foundation
import SwiftData

/// A snapshot of the persona values that were genuinely persisted by an
/// earlier UserDefaults-backed build.  Registered defaults are deliberately
/// excluded from this type so a fresh CloudKit device cannot mistake fallback
/// values for an explicit user edit.
struct CompanionProfileLegacyDefaults: Equatable, Sendable {
    let configuration: PersonaConfiguration
    let persistedKeys: Set<String>

    var hasPersistedValues: Bool {
        !persistedKeys.isEmpty
    }
}

enum CompanionProfileError: LocalizedError, Equatable {
    case emptyName
    case emptyUserName
    case emptyPrompt
    case nameTooLong(Int)
    case userNameTooLong(Int)
    case promptTooLong(Int)
    case invalidBirthday
    case profileNotFound(UUID)
    case duplicateProfile(UUID)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "角色名不能为空。"
        case .emptyUserName:
            return "用户称呼不能为空。"
        case .emptyPrompt:
            return "人格提示不能为空。"
        case .nameTooLong(let limit):
            return "角色名不能超过 " + String(limit) + " 个字符。"
        case .userNameTooLong(let limit):
            return "用户称呼不能超过 " + String(limit) + " 个字符。"
        case .promptTooLong(let limit):
            return "人格提示不能超过 " + String(limit) + " 个字符。"
        case .invalidBirthday:
            return "生日必须同时包含月和日，并且是有效日期。"
        case .profileNotFound(let roleID):
            return "找不到角色 \(roleID.uuidString)。"
        case .duplicateProfile(let roleID):
            return "角色 \(roleID.uuidString) 已存在。"
        case .saveFailed(let message):
            return "角色设置保存失败：" + message
        }
    }
}

/// The single model-layer API for reading and writing the companion persona.
///
/// UserDefaults remains a legacy migration source and an in-memory fallback
/// only.  Once a CompanionProfileRecord exists, it is always preferred, even
/// when old defaults still contain values from the prototype.
@MainActor
final class CompanionProfileService {
    /// Compatibility alias retained for the original single-role callers.
    static let singletonID = RoleScope.legacyRoleID
    static let legacyRoleID = RoleScope.legacyRoleID

    /// These limits keep an accidental or imported prompt from becoming an
    /// unbounded request prefix while leaving ample room for a detailed
    /// companion specification.
    nonisolated static let nameMaximumLength = 80
    nonisolated static let userNameMaximumLength = 80
    nonisolated static let promptMaximumLength = 32_000

    /// Aliases make the validation boundary easy for UI and import callers to
    /// discover without duplicating constants.
    nonisolated static let maxNameLength = nameMaximumLength
    nonisolated static let maxUserNameLength = userNameMaximumLength
    nonisolated static let maxPromptLength = promptMaximumLength

    static let legacyMigrationKey = SettingsKeys.personaStorageMigrationVersion
    static let legacyMigrationVersion = SettingsStore.personaStorageMigrationVersion

    static let stableDeviceIDKey = "device.stableID"

    let context: ModelContext
    let defaults: UserDefaults
    let deviceID: String

    /// `legacyPersistentDomainName` is optional in production because the
    /// standard defaults domain is discovered from the app bundle.  Tests may
    /// provide a suite name explicitly; this also makes the source of truth
    /// check independent of private UserDefaults implementation details.
    private let legacyPersistentDomainName: String?

    init(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        deviceID: String? = nil,
        legacyPersistentDomainName: String? = nil
    ) {
        self.context = context
        self.defaults = defaults
        self.deviceID = Self.normalizedDeviceID(deviceID) ?? Self.loadDeviceID(defaults: defaults)
        self.legacyPersistentDomainName = legacyPersistentDomainName
    }

    /// The fixed fallback used when the store has no profile record.  This is
    /// intentionally a pure value operation: it never creates a CloudKit row.
    var fallbackConfiguration: PersonaConfiguration {
        SettingsStore.fallbackPersonaConfiguration
    }

    static var defaultConfiguration: PersonaConfiguration {
        SettingsStore.fallbackPersonaConfiguration
    }

    /// Returns the deterministic canonical profile, or nil when this store has
    /// no profile records. Duplicate physical rows are reduced by the same
    /// ordering used by merge/reconciliation callers. Omitting roleID retains
    /// the original single-role behavior and reads the legacy companion.
    func canonicalProfile(roleID: UUID? = nil) throws -> CompanionProfileRecord? {
        let records = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        return Self.canonicalProfile(from: records, roleID: roleID)
    }

    /// Resolves a required role profile and reports a typed missing-profile
    /// error rather than silently returning the legacy fallback.
    func profile(roleID: UUID?) throws -> CompanionProfileRecord {
        let resolvedRoleID = RoleScope.resolve(roleID)
        guard let profile = try canonicalProfile(roleID: resolvedRoleID) else {
            throw CompanionProfileError.profileNotFound(resolvedRoleID)
        }
        return profile
    }

    /// Pure helper for callers that already hold a fetched snapshot.
    static func canonicalProfile(
        from records: [CompanionProfileRecord]
    ) -> CompanionProfileRecord? {
        canonicalProfile(from: records, roleID: singletonID)
    }

    /// Pure role-scoped canonicalization. Duplicate physical rows for one
    /// role are reduced with the existing revision/time/device/content order.
    static func canonicalProfile(
        from records: [CompanionProfileRecord],
        roleID: UUID?
    ) -> CompanionProfileRecord? {
        let resolvedRoleID = RoleScope.resolve(roleID)
        return deterministicWinner(from: records.filter { $0.id == resolvedRoleID })
    }

    /// Reduces all physical profile rows into one deterministic winner per
    /// logical role. Results are returned in UUID order, independent of
    /// SwiftData fetch order.
    static func logicalProfiles(
        from records: [CompanionProfileRecord]
    ) -> [UUID: CompanionProfileRecord] {
        var winners: [UUID: CompanionProfileRecord] = [:]
        for candidate in records {
            if let current = winners[candidate.id] {
                if isPreferred(candidate, over: current) {
                    winners[candidate.id] = candidate
                }
            } else {
                winners[candidate.id] = candidate
            }
        }
        return winners
    }

    /// Array projection of `logicalProfiles`, suitable for deterministic UI
    /// lists and export callers.
    static func deterministicWinners(
        from records: [CompanionProfileRecord]
    ) -> [CompanionProfileRecord] {
        let profiles = logicalProfiles(from: records)
        return profiles
            .keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { profiles[$0] }
    }

    /// Reads all logical profiles, reducing physical duplicates before they
    /// are exposed to callers.
    func listProfiles() throws -> [CompanionProfileRecord] {
        let records = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        return Self.deterministicWinners(from: records)
    }

    /// Reads one role's persisted configuration. Missing non-legacy roles are
    /// errors; no arbitrary role is substituted with 绫音's profile. Omitting
    /// roleID retains the original fallback behavior.
    func configuration(roleID: UUID? = nil) throws -> PersonaConfiguration {
        guard roleID != nil else {
            guard let profile = try canonicalProfile() else {
                return fallbackConfiguration
            }
            return Self.configuration(from: profile, fallback: fallbackConfiguration)
        }
        let profile = try self.profile(roleID: roleID)
        // A selected role is already persisted data, so do not apply the
        // legacy fallback field-by-field here. That fallback is reserved for
        // the original no-argument API and must not make a malformed or
        // incomplete non-legacy role look like 绫音.
        return PersonaConfiguration(
            name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            userName: profile.userName.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            birthdayMonth: profile.birthdayMonth,
            birthdayDay: profile.birthdayDay,
            avatarImageData: profile.avatarImageData,
            chatBackgroundImageData: profile.chatBackgroundImageData
        )
    }

    /// Common alias for code that describes the reduction as a winner
    /// selection rather than canonicalization.
    static func deterministicWinner(
        from records: [CompanionProfileRecord]
    ) -> CompanionProfileRecord? {
        records.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return isPreferred(candidate, over: current) ? candidate : current
        }
    }

    static func winner(
        from records: [CompanionProfileRecord]
    ) -> CompanionProfileRecord? {
        deterministicWinner(from: records)
    }

    /// Deterministic order for one logical profile.  Revision is the primary
    /// logical clock; the remaining keys make equal revisions converge even
    /// when two devices wrote at the same wall-clock instant.
    static func isPreferred(
        _ lhs: CompanionProfileRecord,
        over rhs: CompanionProfileRecord
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision > rhs.revision
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID > rhs.deviceID
        }
        return canonicalContentFingerprint(lhs) > canonicalContentFingerprint(rhs)
    }

    static func canonicalContentFingerprint(_ record: CompanionProfileRecord) -> String {
        func dataHash(_ data: Data?) -> String {
            guard let data else { return "" }
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        let avatarHash = dataHash(record.avatarImageData)
        let backgroundHash = dataHash(record.chatBackgroundImageData)
        let content = [
            record.worldProfileID.uuidString.lowercased(),
            record.name,
            record.userName,
            record.prompt,
            record.birthdayMonth.map(String.init) ?? "",
            record.birthdayDay.map(String.init) ?? "",
            avatarHash,
            backgroundHash
        ]
            .joined(separator: "\u{001F}")
        return SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func configuration(
        from profile: CompanionProfileRecord,
        fallback fallbackConfiguration: PersonaConfiguration? = nil
    ) -> PersonaConfiguration {
        let fallback = fallbackConfiguration ?? Self.defaultConfiguration
        return PersonaConfiguration(
            name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback.name
                : profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            userName: profile.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback.userName
                : profile.userName.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallback.prompt
                : profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            birthdayMonth: profile.birthdayMonth,
            birthdayDay: profile.birthdayDay,
            avatarImageData: profile.avatarImageData,
            chatBackgroundImageData: profile.chatBackgroundImageData
        )
    }

    /// Finds only genuinely persisted legacy values.  `register(defaults:)`
    /// values live in the registration domain and are excluded even though
    /// ordinary `string(forKey:)` calls can see them.
    func legacyDefaults() -> CompanionProfileLegacyDefaults? {
        Self.legacyDefaults(
            from: defaults,
            persistentDomainName: legacyPersistentDomainName
        )
    }

    static func legacyDefaults(
        from defaults: UserDefaults,
        persistentDomainName: String? = nil
    ) -> CompanionProfileLegacyDefaults? {
        let fallback = SettingsStore.fallbackPersonaConfiguration
        var persistedKeys = Set<String>()

        func readString(_ key: String, fallback: String) -> String {
            guard let value = persistentLegacyValue(
                forKey: key,
                defaults: defaults,
                persistentDomainName: persistentDomainName
            ) else {
                return fallback
            }
            persistedKeys.insert(key)
            return value as? String ?? fallback
        }

        let configuration = PersonaConfiguration(
            name: readString(SettingsKeys.personaName, fallback: fallback.name),
            userName: readString(SettingsKeys.userName, fallback: fallback.userName),
            prompt: readString(SettingsKeys.personaPrompt, fallback: fallback.prompt)
        )

        guard !persistedKeys.isEmpty else { return nil }
        return CompanionProfileLegacyDefaults(
            configuration: configuration,
            persistedKeys: persistedKeys
        )
    }

    /// Idempotently migrates old custom defaults into the active store.  A
    /// pre-existing model record always wins and is never overwritten by
    /// defaults.  With only registered defaults this does nothing, preserving
    /// the no-record CloudKit startup behavior.
    @discardableResult
    func migrateLegacyIfNeeded(now: Date = Date()) throws -> CompanionProfileRecord? {
        if try canonicalProfile() != nil {
            markLegacyMigrationComplete()
            return nil
        }
        guard let legacy = legacyDefaults() else { return nil }

        let configuration = try Self.validatedConfiguration(legacy.configuration)
        let record = CompanionProfileRecord(
            id: Self.singletonID,
            name: configuration.name,
            userName: configuration.userName,
            prompt: configuration.prompt,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: deviceID
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw CompanionProfileError.saveFailed(error.localizedDescription)
        }
        markLegacyMigrationComplete()
        return record
    }

    /// Alias for startup code that calls the operation a backfill.
    @discardableResult
    func backfillLegacyIfNeeded(now: Date = Date()) throws -> CompanionProfileRecord? {
        try migrateLegacyIfNeeded(now: now)
    }

    /// Saves one complete persona snapshot with exactly one ModelContext save.
    /// Omitting roleID retains the original single-role behavior and writes
    /// the legacy profile; a supplied role ID is handled independently.
    @discardableResult
    func save(
        _ configuration: PersonaConfiguration,
        roleID: UUID? = nil,
        worldProfileID: UUID? = nil,
        now: Date = Date()
    ) throws -> CompanionProfileRecord {
        let normalized = try Self.validatedConfiguration(configuration)
        let resolvedRoleID = RoleScope.resolve(roleID)
        if let profile = try canonicalProfile(roleID: resolvedRoleID) {
            profile.worldProfileID = worldProfileID ?? profile.worldProfileID
            profile.name = normalized.name
            profile.userName = normalized.userName
            profile.prompt = normalized.prompt
            profile.birthdayMonth = normalized.birthdayMonth
            profile.birthdayDay = normalized.birthdayDay
            profile.avatarImageData = normalized.avatarImageData
            profile.chatBackgroundImageData = normalized.chatBackgroundImageData
            profile.updatedAt = now
            profile.revision = max(0, profile.revision) + 1
            profile.deviceID = deviceID
            return try saveContextReturning(profile)
        }

        let profile = CompanionProfileRecord(
            id: resolvedRoleID,
            worldProfileID: worldProfileID ?? WorldProfileRecord.realityID,
            name: normalized.name,
            userName: normalized.userName,
            prompt: normalized.prompt,
            birthdayMonth: normalized.birthdayMonth,
            birthdayDay: normalized.birthdayDay,
            avatarImageData: normalized.avatarImageData,
            chatBackgroundImageData: normalized.chatBackgroundImageData,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: deviceID
        )
        context.insert(profile)
        return try saveContextReturning(profile)
    }

    /// Creates a new logical profile. Unlike role-scoped `save`, creation is
    /// intentionally strict: an existing role (including a physical duplicate
    /// group) is reported as a duplicate instead of being silently overwritten.
    @discardableResult
    func create(
        _ configuration: PersonaConfiguration,
        roleID: UUID,
        worldProfileID: UUID = WorldProfileRecord.realityID,
        now: Date = Date()
    ) throws -> CompanionProfileRecord {
        let resolvedRoleID = RoleScope.resolve(roleID)
        let normalized = try Self.validatedConfiguration(configuration)
        guard try canonicalProfile(roleID: resolvedRoleID) == nil else {
            throw CompanionProfileError.duplicateProfile(resolvedRoleID)
        }

        let profile = CompanionProfileRecord(
            id: resolvedRoleID,
            worldProfileID: worldProfileID,
            name: normalized.name,
            userName: normalized.userName,
            prompt: normalized.prompt,
            birthdayMonth: normalized.birthdayMonth,
            birthdayDay: normalized.birthdayDay,
            avatarImageData: normalized.avatarImageData,
            chatBackgroundImageData: normalized.chatBackgroundImageData,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: deviceID
        )
        context.insert(profile)
        return try saveContextReturning(profile)
    }

    /// Updates an existing selected role. Keeping this operation strict makes
    /// a typo or stale role ID observable instead of turning it into a write to
    /// the legacy companion. Omitting roleID retains the original upsert API.
    @discardableResult
    func update(
        roleID: UUID? = nil,
        name: String,
        userName: String,
        prompt: String,
        worldProfileID: UUID? = nil,
        now: Date = Date()
    ) throws -> CompanionProfileRecord {
        let existing = try canonicalProfile(roleID: RoleScope.resolve(roleID))
        return try update(
            roleID: roleID,
            name: name,
            userName: userName,
            prompt: prompt,
            avatarImageData: existing?.avatarImageData,
            chatBackgroundImageData: existing?.chatBackgroundImageData,
            worldProfileID: worldProfileID,
            now: now
        )
    }

    @discardableResult
    func update(
        roleID: UUID? = nil,
        name: String,
        userName: String,
        prompt: String,
        avatarImageData: Data?,
        chatBackgroundImageData: Data?,
        worldProfileID: UUID? = nil,
        now: Date = Date()
    ) throws -> CompanionProfileRecord {
        let configuration = PersonaConfiguration(
            name: name,
            userName: userName,
            prompt: prompt,
            avatarImageData: avatarImageData,
            chatBackgroundImageData: chatBackgroundImageData
        )
        guard roleID != nil else {
            return try save(configuration, worldProfileID: worldProfileID, now: now)
        }
        let resolvedRoleID = RoleScope.resolve(roleID)
        let normalized = try Self.validatedConfiguration(configuration)
        guard let profile = try canonicalProfile(roleID: resolvedRoleID) else {
            throw CompanionProfileError.profileNotFound(resolvedRoleID)
        }
        profile.name = normalized.name
        profile.worldProfileID = worldProfileID ?? profile.worldProfileID
        profile.userName = normalized.userName
        profile.prompt = normalized.prompt
        profile.avatarImageData = normalized.avatarImageData
        profile.chatBackgroundImageData = normalized.chatBackgroundImageData
        profile.updatedAt = now
        profile.revision = max(0, profile.revision) + 1
        profile.deviceID = deviceID
        return try saveContextReturning(profile)
    }

    /// Resets the selected role to the fallback persona values. Omitting
    /// roleID retains the original single-role behavior and creates the legacy
    /// row when needed; an explicit non-legacy role must already exist.
    @discardableResult
    func reset(
        roleID: UUID? = nil,
        now: Date = Date()
    ) throws -> CompanionProfileRecord {
        let existing = try canonicalProfile(roleID: RoleScope.resolve(roleID))
        let resetConfiguration = PersonaConfiguration(
            name: fallbackConfiguration.name,
            userName: fallbackConfiguration.userName,
            prompt: fallbackConfiguration.prompt,
            avatarImageData: existing?.avatarImageData,
            chatBackgroundImageData: existing?.chatBackgroundImageData
        )
        guard roleID != nil else { return try save(resetConfiguration, now: now) }
        return try update(
            roleID: roleID,
            name: resetConfiguration.name,
            userName: resetConfiguration.userName,
            prompt: resetConfiguration.prompt,
            avatarImageData: resetConfiguration.avatarImageData,
            chatBackgroundImageData: resetConfiguration.chatBackgroundImageData,
            worldProfileID: existing?.worldProfileID,
            now: now
        )
    }

    static func validatedConfiguration(
        _ configuration: PersonaConfiguration
    ) throws -> PersonaConfiguration {
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = configuration.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { throw CompanionProfileError.emptyName }
        guard !userName.isEmpty else { throw CompanionProfileError.emptyUserName }
        guard !prompt.isEmpty else { throw CompanionProfileError.emptyPrompt }
        guard name.count <= nameMaximumLength else {
            throw CompanionProfileError.nameTooLong(nameMaximumLength)
        }
        guard userName.count <= userNameMaximumLength else {
            throw CompanionProfileError.userNameTooLong(userNameMaximumLength)
        }
        guard prompt.count <= promptMaximumLength else {
            throw CompanionProfileError.promptTooLong(promptMaximumLength)
        }

        let birthday: BirthdayMonthDay?
        switch (configuration.birthdayMonth, configuration.birthdayDay) {
        case (nil, nil):
            birthday = nil
        case let (month?, day?):
            guard let validated = BirthdayMonthDay(month: month, day: day) else {
                throw CompanionProfileError.invalidBirthday
            }
            birthday = validated
        default:
            throw CompanionProfileError.invalidBirthday
        }

        return PersonaConfiguration(
            name: name,
            userName: userName,
            prompt: prompt,
            birthdayMonth: birthday?.month,
            birthdayDay: birthday?.day,
            avatarImageData: configuration.avatarImageData,
            chatBackgroundImageData: configuration.chatBackgroundImageData
        )
    }

    private func saveContextReturning(
        _ profile: CompanionProfileRecord
    ) throws -> CompanionProfileRecord {
        do {
            try context.save()
            return profile
        } catch {
            context.rollback()
            throw CompanionProfileError.saveFailed(error.localizedDescription)
        }
    }

    private func markLegacyMigrationComplete() {
        defaults.set(Self.legacyMigrationVersion, forKey: Self.legacyMigrationKey)
    }

    private static func persistentLegacyValue(
        forKey key: String,
        defaults: UserDefaults,
        persistentDomainName: String?
    ) -> Any? {
        let knownDomainNames: [String]
        if let persistentDomainName {
            // An explicit domain is authoritative.  This is also the public
            // API that lets an injected test suite name its persisted store.
            knownDomainNames = persistentDomainName.isEmpty ? [] : [persistentDomainName]
        } else if defaults === UserDefaults.standard {
            // Only the standard defaults object should probe app domains. A
            // custom suite must not accidentally read another app's settings
            // from the process-wide defaults database.
            // The local signed build may override Bundle ID through the
            // ignored Local.xcconfig. Deriving the domain at runtime keeps
            // public source neutral while preserving that build's existing
            // persisted profile domain.
            knownDomainNames = [
                Bundle.main.bundleIdentifier
            ].compactMap { $0 }.filter { !$0.isEmpty }
        } else {
            knownDomainNames = []
        }

        for domainName in knownDomainNames {
            if let value = defaults.persistentDomain(forName: domainName)?[key] {
                return value
            }
        }

        // A custom UserDefaults suite does not expose its suite name through
        // the public Swift API.  Its dictionary representation still contains
        // its persisted values, while registered defaults are visible in the
        // registration volatile domain.  This fallback keeps test suites and
        // injected defaults usable without relying on private APIs.  When a
        // persisted value overrides a registration value, the effective value
        // differs and is therefore still considered a genuine legacy edit.
        guard let value = defaults.dictionaryRepresentation()[key] else {
            return nil
        }
        let registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        if let registeredValue = registration[key] {
            if let valueString = value as? String,
               let registeredString = registeredValue as? String,
               valueString == registeredString {
                return nil
            }
            if let valueObject = value as? NSObject,
               let registeredObject = registeredValue as? NSObject,
               valueObject.isEqual(registeredObject) {
                return nil
            }
        }
        return value
    }

    private static func normalizedDeviceID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func loadDeviceID(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: stableDeviceIDKey),
           let normalized = normalizedDeviceID(existing) {
            return normalized
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: stableDeviceIDKey)
        return created
    }
}
