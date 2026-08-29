import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class StoreConflictIsolationTests: XCTestCase {
    func testEventConflictIsQuarantinedAndBlocksSendUntilResolved() async throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let defaults = try makeDefaults()
        configure(defaults)
        let client = CountingAIClient()
        let rawIndex = LocalConversationSearchIndex(inMemory: true)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: rawIndex,
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000c001")!
        let context = ModelContext(bootstrap.container)
        let first = makeEvent(id: eventID, content: "冲突正文一")
        let second = makeEvent(id: eventID, content: "冲突正文二")
        context.insert(first)
        context.insert(second)
        try context.save()
        await rawIndex.upsert(.init(id: eventID, role: "user", body: "冲突正文一"))

        appModel.refreshFromStore()

        XCTAssertEqual(appModel.integrityConflict, .eventConflict(eventID))
        XCTAssertTrue(appModel.hasIntegrityConflict)
        XCTAssertTrue(appModel.conflictedEventIDs.contains(eventID))
        XCTAssertFalse(appModel.messages.contains { $0.id == eventID })
        XCTAssertEqual(appModel.pendingMemoryCount, 0)

        appModel.send("不应发送")
        XCTAssertEqual(client.chatRequests, 0)
        XCTAssertEqual(client.extractionRequests, 0)

        try await waitUntil {
            await rawIndex.search("冲突正文一").isEmpty
        }

        let duplicateRecords = try context.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertEqual(duplicateRecords.filter { $0.id == eventID }.count, 2)
        context.delete(duplicateRecords.first { $0.content == "冲突正文二" }!)
        try context.save()

        appModel.refreshFromStore()

        XCTAssertNil(appModel.integrityConflict)
        XCTAssertFalse(appModel.hasIntegrityConflict)
        XCTAssertTrue(appModel.messages.contains { $0.id == eventID })
        XCTAssertEqual(appModel.pendingMemoryCount, 1)

        appModel.send("恢复后发送")
        try await waitUntil { client.chatRequests == 1 && !appModel.isGenerating }
    }

    func testSenderRoleConflictIsNotCollapsed() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID(uuidString: "00000000-0000-0000-0000-00000000c002")!
        let firstRoleID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondRoleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let first = makeEvent(id: eventID, content: "相同正文", senderRoleID: firstRoleID)
        let second = makeEvent(id: eventID, content: "相同正文", senderRoleID: secondRoleID)
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertThrowsError(try StoreDuplicateReconciler.reconcile(context: context)) { error in
            XCTAssertEqual(error as? StoreDuplicateReconcileError, .eventConflict(eventID))
        }
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationEvent>()).filter { $0.id == eventID }.count,
            2
        )
    }

    func testNonEventEntityCountChangesTriggerReconcile() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let defaults = try makeDefaults()
        configure(defaults)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: CountingAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let context = ModelContext(bootstrap.container)

        let memoryID = UUID(uuidString: "00000000-0000-0000-0000-00000000c101")!
        let memoryA = makeMemory(id: memoryID)
        let memoryB = makeMemory(id: memoryID)
        let evidenceID = UUID(uuidString: "00000000-0000-0000-0000-00000000c102")!
        let evidenceA = makeEvidence(id: evidenceID, memoryID: memoryID)
        let evidenceB = makeEvidence(id: evidenceID, memoryID: memoryID)
        let summaryID = UUID(uuidString: "00000000-0000-0000-0000-00000000c103")!
        let summaryA = makeSummary(id: summaryID)
        let summaryB = makeSummary(id: summaryID)
        let tombstoneID = UUID(uuidString: "00000000-0000-0000-0000-00000000c104")!
        let tombstoneA = makeTombstone(id: tombstoneID, memoryID: memoryID)
        let tombstoneB = makeTombstone(id: tombstoneID, memoryID: memoryID)

        for record in [memoryA, memoryB] { context.insert(record) }
        for record in [evidenceA, evidenceB] { context.insert(record) }
        for record in [summaryA, summaryB] { context.insert(record) }
        for record in [tombstoneA, tombstoneB] { context.insert(record) }
        try context.save()

        appModel.refreshFromStore(force: false)

        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).filter { $0.id == memoryID }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).filter { $0.id == evidenceID }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemorySummaryRecord>()).filter { $0.id == summaryID }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).filter { $0.id == tombstoneID }.count, 1)
        XCTAssertNil(appModel.integrityConflict)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "StoreConflictIsolationTests.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private func configure(_ defaults: UserDefaults) {
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
    }

    private func makeEvent(
        id: UUID,
        content: String,
        senderRoleID: UUID? = nil
    ) -> ConversationEvent {
        ConversationEvent(
            id: id,
            conversationID: AppModel.defaultConversationID,
            deviceID: "fixture-device",
            deviceSequence: 1,
            logicalTimestamp: "fixture-device-1",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            senderRoleID: senderRoleID
        )
    }

    private func makeMemory(id: UUID) -> MemoryAssertionRecord {
        MemoryAssertionRecord(
            id: id,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.8,
            importance: 0.5,
            sensitive: false,
            sourceRank: 1,
            extractorID: "fixture",
            deviceID: "fixture-device"
        )
    }

    private func makeEvidence(id: UUID, memoryID: UUID) -> MemoryEvidenceRecord {
        MemoryEvidenceRecord(
            id: id,
            memoryID: memoryID,
            eventID: UUID(uuidString: "00000000-0000-0000-0000-00000000c105")!,
            startUTF16: 0,
            endUTF16: 1,
            relation: .supports,
            quoteHash: "quote",
            confidence: 0.8
        )
    }

    private func makeSummary(id: UUID) -> MemorySummaryRecord {
        let summary = MemorySummaryRecord(
            conversationID: AppModel.defaultConversationID,
            scope: "session",
            content: "摘要",
            firstEventID: nil,
            lastEventID: nil,
            coveredEventCount: 0,
            extractorID: "fixture"
        )
        summary.id = id
        return summary
    }

    private func makeTombstone(id: UUID, memoryID: UUID) -> MemoryTombstoneRecord {
        let tombstone = MemoryTombstoneRecord(
            entityID: memoryID,
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            deviceID: "fixture-device",
            reason: "fixture"
        )
        tombstone.id = id
        return tombstone
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for AppModel state")
        throw WaitError.timedOut
    }

    private enum WaitError: Error {
        case timedOut
    }
}

private final class CountingAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedChatRequests = 0
    private var storedExtractionRequests = 0

    var chatRequests: Int { lock.withLock { storedChatRequests } }
    var extractionRequests: Int { lock.withLock { storedExtractionRequests } }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("fixture reply")
            continuation.finish()
        }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        lock.withLock {
            if messages.contains(where: { $0.content.contains("只做证据抽取") }) {
                storedExtractionRequests += 1
            } else {
                storedChatRequests += 1
            }
        }
        return "fixture reply"
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        throw AIClientError.missingEmbeddingModel
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}
