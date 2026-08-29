import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class CompanionProfileServiceTests: XCTestCase {
    private func makeContext() -> ModelContext {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        return ModelContext(bootstrap.container)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.example.kin.tests.persona." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func countRecords(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<CompanionProfileRecord>()).count
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testEmptyStoreUsesFallbackWithoutCreatingRecord() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = makeContext()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "fixture-device"
        )

        XCTAssertNil(try service.canonicalProfile())
        XCTAssertEqual(try service.configuration(), SettingsStore.fallbackPersonaConfiguration)
        XCTAssertNil(try service.migrateLegacyIfNeeded(now: date(1)))
        XCTAssertEqual(try countRecords(in: context), 0)
    }

    func testRegisteredDefaultsDoNotBackfill() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.register(defaults: [
            SettingsKeys.personaName: "注册角色",
            SettingsKeys.userName: "注册用户",
            SettingsKeys.personaPrompt: "注册提示"
        ])
        let context = makeContext()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "fixture-device"
        )

        XCTAssertNil(service.legacyDefaults())
        XCTAssertNil(try service.migrateLegacyIfNeeded(now: date(2)))
        XCTAssertEqual(try countRecords(in: context), 0)
        XCTAssertEqual(try service.configuration(), SettingsStore.fallbackPersonaConfiguration)
    }

    func testPersistedLegacyValuesBackfillOnceAndTrim() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("  新绫音  ", forKey: SettingsKeys.personaName)
        fixture.defaults.set("  小明  ", forKey: SettingsKeys.userName)
        fixture.defaults.set("  保持连续、坦诚。  ", forKey: SettingsKeys.personaPrompt)
        let context = makeContext()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "legacy-device",
            legacyPersistentDomainName: fixture.suiteName
        )

        let first = try XCTUnwrap(try service.migrateLegacyIfNeeded(now: date(10)))
        XCTAssertEqual(first.id, CompanionProfileService.singletonID)
        XCTAssertEqual(first.name, "新绫音")
        XCTAssertEqual(first.userName, "小明")
        XCTAssertEqual(first.prompt, "保持连续、坦诚。")
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.createdAt, date(10))
        XCTAssertEqual(first.updatedAt, date(10))
        XCTAssertEqual(first.deviceID, "legacy-device")
        XCTAssertEqual(
            fixture.defaults.integer(forKey: SettingsKeys.personaStorageMigrationVersion),
            SettingsStore.personaStorageMigrationVersion
        )

        XCTAssertNil(try service.migrateLegacyIfNeeded(now: date(20)))
        XCTAssertEqual(try countRecords(in: context), 1)
        XCTAssertEqual(try service.configuration().name, "新绫音")
    }

    func testExistingModelAlwaysWinsOverLegacyDefaults() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("旧角色", forKey: SettingsKeys.personaName)
        fixture.defaults.set("旧用户", forKey: SettingsKeys.userName)
        fixture.defaults.set("旧提示", forKey: SettingsKeys.personaPrompt)
        let context = makeContext()
        let existing = CompanionProfileRecord(
            name: "云端角色",
            userName: "云端用户",
            prompt: "云端提示",
            createdAt: date(30),
            updatedAt: date(31),
            revision: 7,
            deviceID: "cloud-device"
        )
        context.insert(existing)
        try context.save()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "legacy-device",
            legacyPersistentDomainName: fixture.suiteName
        )

        XCTAssertNil(try service.migrateLegacyIfNeeded(now: date(40)))
        let canonical = try XCTUnwrap(try service.canonicalProfile())
        XCTAssertEqual(canonical.name, "云端角色")
        XCTAssertEqual(canonical.userName, "云端用户")
        XCTAssertEqual(canonical.prompt, "云端提示")
        XCTAssertEqual(canonical.revision, 7)
        XCTAssertEqual(try countRecords(in: context), 1)
    }

    func testSaveUpdateResetValidateTrimAndAdvanceRevision() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = makeContext()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "save-device"
        )

        let first = try service.save(
            PersonaConfiguration(
                name: "  绫音X  ",
                userName: "  小明  ",
                prompt: "  保持坦诚  "
            ),
            now: date(50)
        )
        XCTAssertEqual(first.name, "绫音X")
        XCTAssertEqual(first.userName, "小明")
        XCTAssertEqual(first.prompt, "保持坦诚")
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.createdAt, date(50))
        XCTAssertEqual(first.updatedAt, date(50))
        XCTAssertEqual(first.deviceID, "save-device")

        let second = try service.update(
            name: "  绫音Y ",
            userName: " 小明Y ",
            prompt: " 新的人格 ",
            now: date(60)
        )
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(second.createdAt, date(50))
        XCTAssertEqual(second.updatedAt, date(60))
        XCTAssertEqual(second.name, "绫音Y")
        XCTAssertEqual(second.userName, "小明Y")
        XCTAssertEqual(second.prompt, "新的人格")

        XCTAssertThrowsError(
            try service.save(
                PersonaConfiguration(name: " ", userName: "有效", prompt: "有效"),
                now: date(70)
            )
        ) { error in
            XCTAssertEqual(error as? CompanionProfileError, .emptyName)
        }
        XCTAssertThrowsError(
            try service.save(
                PersonaConfiguration(
                    name: String(repeating: "名", count: CompanionProfileService.maxNameLength + 1),
                    userName: "有效",
                    prompt: "有效"
                ),
                now: date(70)
            )
        ) { error in
            XCTAssertEqual(
                error as? CompanionProfileError,
                .nameTooLong(CompanionProfileService.maxNameLength)
            )
        }
        XCTAssertThrowsError(
            try service.save(
                PersonaConfiguration(
                    name: "绫音",
                    userName: "有效",
                    prompt: "有效",
                    birthdayMonth: 2,
                    birthdayDay: 30
                ),
                now: date(70)
            )
        ) { error in
            XCTAssertEqual(error as? CompanionProfileError, .invalidBirthday)
        }
        XCTAssertThrowsError(
            try service.save(
                PersonaConfiguration(
                    name: "绫音",
                    userName: "有效",
                    prompt: "有效",
                    birthdayMonth: 2,
                    birthdayDay: nil
                ),
                now: date(70)
            )
        ) { error in
            XCTAssertEqual(error as? CompanionProfileError, .invalidBirthday)
        }

        let reset = try service.reset(now: date(80))
        XCTAssertEqual(reset.revision, 3)
        XCTAssertEqual(reset.name, SettingsStore.fallbackPersonaConfiguration.name)
        XCTAssertEqual(reset.userName, SettingsStore.fallbackPersonaConfiguration.userName)
        XCTAssertEqual(
            reset.prompt,
            SettingsStore.fallbackPersonaConfiguration.prompt.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    func testWinnerOrderAndContentFingerprintAreDeterministic() {
        let sameTime = date(100)
        let lowerRevision = CompanionProfileRecord(
            name: "低版本",
            userName: "用户",
            prompt: "提示",
            updatedAt: sameTime,
            revision: 1,
            deviceID: "z-device"
        )
        let higherRevision = CompanionProfileRecord(
            name: "高版本",
            userName: "用户",
            prompt: "提示",
            updatedAt: date(1),
            revision: 2,
            deviceID: "a-device"
        )
        XCTAssertIdentical(
            CompanionProfileService.winner(from: [lowerRevision, higherRevision]),
            higherRevision
        )

        let later = CompanionProfileRecord(
            name: "较晚",
            userName: "用户",
            prompt: "提示",
            updatedAt: date(101),
            revision: 2,
            deviceID: "a-device"
        )
        XCTAssertIdentical(
            CompanionProfileService.deterministicWinner(from: [higherRevision, later]),
            later
        )

        let deviceZ = CompanionProfileRecord(
            name: "设备Z",
            userName: "用户",
            prompt: "提示",
            updatedAt: sameTime,
            revision: 3,
            deviceID: "z-device"
        )
        let deviceA = CompanionProfileRecord(
            name: "设备A",
            userName: "用户",
            prompt: "提示",
            updatedAt: sameTime,
            revision: 3,
            deviceID: "a-device"
        )
        XCTAssertIdentical(
            CompanionProfileService.winner(from: [deviceA, deviceZ]),
            deviceZ
        )

        let contentA = CompanionProfileRecord(
            name: "内容A",
            userName: "用户",
            prompt: "提示",
            updatedAt: sameTime,
            revision: 4,
            deviceID: "same-device"
        )
        let contentB = CompanionProfileRecord(
            name: "内容B",
            userName: "用户",
            prompt: "提示",
            updatedAt: sameTime,
            revision: 4,
            deviceID: "same-device"
        )
        let expected = CompanionProfileService.canonicalContentFingerprint(contentA)
            > CompanionProfileService.canonicalContentFingerprint(contentB)
            ? contentA
            : contentB
        XCTAssertIdentical(
            CompanionProfileService.winner(from: [contentA, contentB]),
            expected
        )
        XCTAssertIdentical(
            CompanionProfileService.winner(from: [contentB, contentA]),
            expected
        )

        let unrelated = CompanionProfileRecord(
            id: UUID(),
            name: "不应被选中",
            userName: "用户",
            prompt: "提示",
            revision: 99,
            deviceID: "other-device"
        )
        XCTAssertNil(
            CompanionProfileService.canonicalProfile(from: [unrelated])
        )
    }

    func testTwoLogicalProfilesCoexistAndRoleUpdateIsIsolated() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = makeContext()
        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "multi-role-device"
        )
        let roleA = UUID()
        let roleB = UUID()

        let profileA = try service.create(
            PersonaConfiguration(name: "角色A", userName: "用户A", prompt: "提示A"),
            roleID: roleA,
            now: date(200)
        )
        let profileB = try service.create(
            PersonaConfiguration(name: "角色B", userName: "用户B", prompt: "提示B"),
            roleID: roleB,
            now: date(201)
        )
        XCTAssertEqual(profileA.id, roleA)
        XCTAssertEqual(profileB.id, roleB)
        XCTAssertEqual(profileA.roleID, roleA)
        XCTAssertEqual(
            try service.listProfiles().map(\.id).sorted { $0.uuidString < $1.uuidString },
            [roleA, roleB].sorted { $0.uuidString < $1.uuidString }
        )

        let updatedA = try service.update(
            roleID: roleA,
            name: "角色A2",
            userName: "用户A2",
            prompt: "提示A2",
            now: date(202)
        )
        XCTAssertEqual(updatedA.id, roleA)
        XCTAssertEqual(try service.profile(roleID: roleA).name, "角色A2")
        XCTAssertEqual(try service.profile(roleID: roleB).name, "角色B")
        XCTAssertEqual(try service.profile(roleID: roleB).userName, "用户B")
        let missingRoleID = UUID()
        XCTAssertThrowsError(try service.profile(roleID: missingRoleID)) { error in
            XCTAssertEqual(error as? CompanionProfileError, .profileNotFound(missingRoleID))
        }
    }

    func testPhysicalDuplicateForOneRoleUsesDeterministicWinner() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = makeContext()
        let roleID = UUID()
        let sameTime = date(300)
        let older = CompanionProfileRecord(
            id: roleID,
            name: "旧副本",
            userName: "用户",
            prompt: "提示",
            createdAt: date(299),
            updatedAt: sameTime,
            revision: 1,
            deviceID: "a-device"
        )
        let newer = CompanionProfileRecord(
            id: roleID,
            name: "新副本",
            userName: "用户",
            prompt: "提示",
            createdAt: date(299),
            updatedAt: sameTime,
            revision: 2,
            deviceID: "a-device"
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let service = CompanionProfileService(
            context: context,
            defaults: fixture.defaults,
            deviceID: "duplicate-reader"
        )
        let winner = try XCTUnwrap(try service.canonicalProfile(roleID: roleID))
        XCTAssertIdentical(winner, newer)
        XCTAssertEqual(try service.listProfiles().count, 1)
        XCTAssertEqual(try service.listProfiles().first?.id, roleID)
        XCTAssertThrowsError(
            try service.create(
                PersonaConfiguration(name: "再次创建", userName: "用户", prompt: "提示"),
                roleID: roleID
            )
        ) { error in
            XCTAssertEqual(error as? CompanionProfileError, .duplicateProfile(roleID))
        }
    }

    func testLegacyRoleScopeResolvesNilRoleIDs() {
        XCTAssertEqual(RoleScope.resolve(nil), RoleScope.legacyRoleID)
        let conversation = ConversationRecord()
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "device",
            deviceSequence: 1,
            logicalTimestamp: "1",
            role: .user,
            content: "旧记录",
            contentHash: "hash"
        )
        XCTAssertNil(conversation.roleID)
        XCTAssertNil(event.roleID)
        XCTAssertEqual(conversation.resolvedRoleID, RoleScope.legacyRoleID)
        XCTAssertEqual(event.resolvedRoleID, RoleScope.legacyRoleID)
    }
}
