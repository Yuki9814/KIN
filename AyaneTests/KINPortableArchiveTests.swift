import Foundation
import SwiftData
import XCTest
@testable import Ayane

final class KINPortableArchiveTests: XCTestCase {
    func testEnvelopeUsesRequiredKDFAndAEADParameters() {
        XCTAssertEqual(KINPortableArchiveV1.formatIdentifier, "KINPortableArchiveV1")
        XCTAssertEqual(KINPortableArchiveV1.pbkdf2Algorithm, "PBKDF2-HMAC-SHA256")
        XCTAssertEqual(KINPortableArchiveV1.pbkdf2Iterations, 600_000)
        XCTAssertEqual(KINPortableArchiveV1.saltLength, 16)
        XCTAssertEqual(KINPortableArchiveV1.nonceLength, 12)
        XCTAssertEqual(KINPortableArchiveV1.keyLength, 32)
    }

    func testRoundTripAndWrongPasswordFailure() throws {
        let plaintext = Data("portable KIN payload".utf8)
        let archive = try KINPortableArchiveV1.encrypt(plaintext, password: "correct password")

        XCTAssertEqual(
            try KINPortableArchiveV1.decrypt(archive, password: "correct password"),
            plaintext
        )
        XCTAssertThrowsError(
            try KINPortableArchiveV1.decrypt(archive, password: "wrong password")
        ) { error in
            XCTAssertEqual(error as? KINPortableArchiveError, .authenticationFailed)
        }
    }

    func testFixedSwiftKotlinGoldenVectorMatches() throws {
        let plaintext = Data("{\"hello\":\"KIN\"}".utf8)
        let salt = Data((0..<16).map(UInt8.init))
        let nonce = Data((16..<28).map(UInt8.init))
        let expected = try XCTUnwrap(
            Data(base64Encoded: "S0lOUG9ydGFibGVBcmNoaXZlVjEBAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaG0i3iR5WDNxglMfNULeEsmcndsNG9rX+3h8SeFy00dY=")
        )

        let archive = try KINPortableArchiveV1.encrypt(
            plaintext,
            password: "test-password",
            salt: salt,
            nonce: nonce
        )

        XCTAssertEqual(archive, expected)
        XCTAssertEqual(
            try KINPortableArchiveV1.decrypt(expected, password: "test-password"),
            plaintext
        )
    }

    func testTamperAndEmptyPasswordFailWithoutPlaintext() throws {
        let archive = try KINPortableArchiveV1.encrypt(
            Data("private body".utf8),
            password: "password"
        )
        var tampered = archive
        tampered[tampered.index(before: tampered.endIndex)] ^= 1
        XCTAssertThrowsError(
            try KINPortableArchiveV1.decrypt(tampered, password: "password")
        )
        XCTAssertThrowsError(
            try KINPortableArchiveV1.encrypt(Data(), password: "")
        ) { error in
            XCTAssertEqual(error as? KINPortableArchiveError, .emptyPassword)
        }
    }

    func testPortableRedactionExcludesCredentialsDeviceAndDerivedIndexes() throws {
        let input: [String: Any] = [
            "schema_version": 16,
            "device_id": "private-device",
            "events": [[
                "device_id": "private-device",
                "device_sequence": 9,
                "logical_timestamp": "9-private-device-9"
            ]],
            "settings": [
                "provider": ["api_key": "private-api-key", "base_url": "https://private.example"],
                "oauth_token": "private-oauth-token"
            ],
            "memories": [[
                "embedding_base64": "private-derived-index",
                "embedding_model_id": "private-model"
            ]]
        ]
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let redacted = try KINPortableArchiveV1.sanitizeForPortableArchive(inputData)
        let text = String(decoding: redacted, as: UTF8.self)

        XCTAssertFalse(text.contains("private-device"))
        XCTAssertFalse(text.contains("private-api-key"))
        XCTAssertFalse(text.contains("private-oauth-token"))
        XCTAssertFalse(text.contains("private-derived-index"))
        XCTAssertFalse(text.contains("private-model"))
        XCTAssertTrue(text.contains("cloud_sync_enabled"))
    }

    @MainActor
    func testEncryptedStoreRoundTripIsAtomicAndRepeatable() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let roleID = UUID()
        let conversationID = UUID()
        let eventID = UUID()
        sourceContext.insert(CompanionProfileRecord(
            id: roleID,
            name: "便携角色",
            userName: "主人",
            prompt: "保持自然交流。",
            revision: 1,
            deviceID: "source-device"
        ))
        sourceContext.insert(ConversationRecord(
            id: conversationID,
            title: "便携会话",
            roleID: roleID
        ))
        sourceContext.insert(ConversationEvent(
            id: eventID,
            conversationID: conversationID,
            deviceID: "source-device",
            deviceSequence: 1,
            logicalTimestamp: "1-source-device-1",
            role: .user,
            content: "只在加密载荷里出现",
            contentHash: ContentHasher.sha256("只在加密载荷里出现"),
            roleID: roleID
        ))
        try sourceContext.save()

        let sourceSuite = "KINPortableArchiveTests.source.\(UUID().uuidString)"
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceSuite))
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        SettingsStore.registerDefaults(defaults: sourceDefaults)
        let archive = try KINPortableArchiveV1.makeArchive(
            context: sourceContext,
            defaults: sourceDefaults,
            password: "portable-password",
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("只在加密载荷里出现"))

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationSuite = "KINPortableArchiveTests.destination.\(UUID().uuidString)"
        let destinationDefaults = try XCTUnwrap(UserDefaults(suiteName: destinationSuite))
        defer { destinationDefaults.removePersistentDomain(forName: destinationSuite) }
        SettingsStore.registerDefaults(defaults: destinationDefaults)

        XCTAssertThrowsError(try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "wrong-password",
            context: destinationContext,
            defaults: destinationDefaults
        ))
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<ConversationEvent>()), 0)

        let first = try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "portable-password",
            context: destinationContext,
            defaults: destinationDefaults
        )
        XCTAssertEqual(first.profiles, 1)
        XCTAssertEqual(first.conversations, 1)
        XCTAssertEqual(first.events, 1)
        XCTAssertEqual(
            try XCTUnwrap(destinationContext.fetch(FetchDescriptor<ConversationEvent>()).first).content,
            "只在加密载荷里出现"
        )

        // A user may select the same archive twice. The second validated
        // replace must converge on the same logical records, not duplicate
        // them or partially append another copy.
        let second = try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "portable-password",
            context: destinationContext,
            defaults: destinationDefaults
        )
        XCTAssertEqual(second, first)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<CompanionProfileRecord>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<ConversationRecord>()), 1)
        XCTAssertEqual(try destinationContext.fetchCount(FetchDescriptor<ConversationEvent>()), 1)
    }

    @MainActor
    func testKotlinPayloadRestoresIntoAppleStoreAndConverges() throws {
        let roleID = "role-kmp-custom-1"
        let payload: [String: Any] = [
            "format": "KINPortableArchiveV1",
            "schemaVersion": 1,
            "exportId": "kmp-export-1",
            "roles": [[
                "id": roleID,
                "displayName": "跨端角色",
                "systemPrompt": "保持清晰、自然的交流。",
                "isBuiltIn": false,
                "createdAtMillis": 1_700_000_000_000,
                "isArchived": false
            ]],
            "relationships": [[
                "roleId": roleID,
                "stage": "FRIEND",
                "affinity": 48,
                "updatedAtMillis": 1_700_000_001_000
            ]],
            "chatEvents": [[
                "id": "event-kmp-1",
                "roleId": roleID,
                "conversationId": "conversation-kmp-1",
                "author": "USER",
                "kind": "MESSAGE",
                "status": "SENT",
                "body": "来自 Kotlin 的消息",
                "createdAtMillis": 1_700_000_002_000,
                "sequence": 1,
                "attachmentRefs": []
            ]],
            "memories": [
                [
                    "id": "memory-kmp-active",
                    "roleId": roleID,
                    "text": "喜欢跨端备份",
                    "confidence": 0.9,
                    "createdAtMillis": 1_700_000_003_000,
                    "updatedAtMillis": 1_700_000_003_000,
                    "isTombstoned": false
                ],
                [
                    "id": "memory-kmp-deleted",
                    "roleId": roleID,
                    "text": "已经删除的旧记忆",
                    "confidence": 1.0,
                    "createdAtMillis": 1_700_000_004_000,
                    "updatedAtMillis": 1_700_000_005_000,
                    "isTombstoned": true
                ]
            ],
            "settings": [
                "theme": "SYSTEM",
                "endpoint": "https://api.openai.com/v1/chat/completions",
                "model": "gpt-4o-mini",
                "sendOnEnter": true
            ],
            "attachments": []
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let archive = try KINPortableArchiveV1.encrypt(payloadData, password: "跨端密码")

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        let suite = "KINPortableArchiveTests.kmp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStore.registerDefaults(defaults: defaults)

        let first = try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "跨端密码",
            context: context,
            defaults: defaults
        )
        XCTAssertEqual(first.profiles, 2)
        XCTAssertEqual(first.relationships, 2)
        XCTAssertEqual(first.conversations, 1)
        XCTAssertEqual(first.events, 1)
        XCTAssertEqual(first.memories, 2)
        XCTAssertEqual(first.tombstones, 1)
        XCTAssertEqual(first.exportedAt, Date(timeIntervalSince1970: 1_700_000_005))
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<CompanionProfileRecord>()).map(\.name)),
            Set(["绫音", "跨端角色"])
        )
        XCTAssertEqual(
            try XCTUnwrap(context.fetch(FetchDescriptor<ConversationEvent>()).first).content,
            "来自 Kotlin 的消息"
        )

        let second = try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "跨端密码",
            context: context,
            defaults: defaults
        )
        XCTAssertEqual(second, first)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionProfileRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEvent>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryTombstoneRecord>()), 1)
    }

    @MainActor
    func testKotlinPayloadWithMissingAttachmentFailsBeforeMutation() throws {
        let payload: [String: Any] = [
            "format": "KINPortableArchiveV1",
            "schemaVersion": 1,
            "exportId": "kmp-export-missing-attachment",
            "roles": [],
            "relationships": [],
            "chatEvents": [[
                "id": "event-missing-attachment",
                "roleId": RoleScope.legacyRoleID.uuidString,
                "conversationId": "conversation-missing-attachment",
                "author": "USER",
                "kind": "MESSAGE",
                "status": "SENT",
                "body": "附件必须完整",
                "createdAtMillis": 1_700_000_000_000,
                "sequence": 1,
                "attachmentRefs": [[
                    "id": "missing-file",
                    "sha256": String(repeating: "0", count: 64)
                ]]
            ]],
            "memories": [],
            "settings": [
                "theme": "SYSTEM",
                "endpoint": "https://api.openai.com/v1/chat/completions",
                "model": "gpt-4o-mini",
                "sendOnEnter": true
            ],
            "attachments": []
        ]
        let archive = try KINPortableArchiveV1.encrypt(
            JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            password: "password"
        )
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        let suite = "KINPortableArchiveTests.kmp-missing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStore.registerDefaults(defaults: defaults)

        XCTAssertThrowsError(try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "password",
            context: context,
            defaults: defaults
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()), 0)
    }
}
