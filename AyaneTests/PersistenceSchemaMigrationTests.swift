import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class PersistenceSchemaMigrationTests: XCTestCase {
    func testAddingCompanionProfileModelOpensLegacySixEntityStoreWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AyaneSchemaMigrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Legacy.store")

        let legacySchema = Schema([
            ConversationRecord.self,
            ConversationEvent.self,
            MemoryAssertionRecord.self,
            MemoryEvidenceRecord.self,
            MemorySummaryRecord.self,
            MemoryTombstoneRecord.self
        ])
        do {
            let legacyConfiguration = ModelConfiguration(
                "AyaneLegacy",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            let context = ModelContext(legacyContainer)
            let conversation = ConversationRecord(
                id: AppModel.defaultConversationID,
                title: "迁移前会话",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let content = "迁移前原始消息"
            context.insert(conversation)
            context.insert(ConversationEvent(
                conversationID: conversation.id,
                deviceID: "legacy-device",
                deviceSequence: 1,
                logicalTimestamp: "legacy-1",
                occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                role: .user,
                content: content,
                contentHash: ContentHasher.sha256(content)
            ))
            try context.save()
        }

        let currentConfiguration = ModelConfiguration(
            "AyaneLegacy",
            schema: PersistenceController.schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let migratedContainer = try ModelContainer(
            for: PersistenceController.schema,
            configurations: [currentConfiguration]
        )
        let migratedContext = ModelContext(migratedContainer)

        XCTAssertEqual(
            try migratedContext.fetch(FetchDescriptor<ConversationRecord>()).map(\.title),
            ["迁移前会话"]
        )
        XCTAssertEqual(
            try migratedContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.content),
            ["迁移前原始消息"]
        )
        XCTAssertEqual(
            try migratedContext.fetchCount(FetchDescriptor<CompanionProfileRecord>()),
            0,
            "Adding the CloudKit-safe profile entity must not synthesize a default row."
        )
    }
}
