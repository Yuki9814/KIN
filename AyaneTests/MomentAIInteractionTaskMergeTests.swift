import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MomentAIInteractionTaskMergeTests: XCTestCase {
    func testMergeNormalizesRoleAndRepeatedPayloadDoesNotDuplicateTask() throws {
        let roleID = RoleScope.legacyRoleID
        let task = makeTask(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            roleID: roleID,
            idempotencyKey: "moment-task-repeat",
            state: .pending,
            revision: 1,
            updatedAt: date(101)
        )
        var payload = try makePayload(task: task, roleID: roleID)
        // Simulate a legacy/in-process DTO whose optional role was not filled
        // until the merge boundary.
        payload.momentAIInteractionTasks[0].roleID = nil

        let destination = makeContext()
        let first = try DataMergeService.merge(payload, into: destination)
        let second = try DataMergeService.merge(payload, into: destination)

        XCTAssertEqual(
            first.momentAIInteractionTasks,
            DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0)
        )
        XCTAssertEqual(
            second.momentAIInteractionTasks,
            DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1)
        )
        let records = try destination.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.roleID, roleID)
        XCTAssertEqual(records.first?.idempotencyKey, "moment-task-repeat")
        XCTAssertEqual(first.totalInserted, 5)
        XCTAssertEqual(second.totalUnchanged, 5)
    }

    func testSameIdempotencyKeyUpdatesExistingPhysicalRowAndTerminalWinsOverNewerPending() throws {
        let roleID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let key = "moment-task-terminal"
        let initialID = UUID(uuidString: "20000000-0000-0000-0000-000000000011")!
        let initial = makeTask(
            id: initialID,
            roleID: roleID,
            idempotencyKey: key,
            state: .pending,
            revision: 1,
            updatedAt: date(101)
        )
        let destination = makeContext()
        _ = try DataMergeService.merge(
            try makePayload(task: initial, roleID: roleID),
            into: destination
        )

        let succeeded = makeTask(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000012")!,
            roleID: roleID,
            idempotencyKey: key,
            state: .succeeded,
            generatedText: "已经完成",
            revision: 2,
            updatedAt: date(102)
        )
        let update = try DataMergeService.merge(
            try makePayload(task: succeeded, roleID: roleID),
            into: destination
        )
        XCTAssertEqual(
            update.momentAIInteractionTasks,
            DataMergeEntityReport(inserted: 0, updated: 1, unchanged: 0)
        )

        // A non-terminal retry with a higher revision must not reopen the
        // completed operation.
        let staleRetry = makeTask(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000013")!,
            roleID: roleID,
            idempotencyKey: key,
            state: .pending,
            generatedText: "不应覆盖",
            revision: 99,
            updatedAt: date(999)
        )
        let unchanged = try DataMergeService.merge(
            try makePayload(task: staleRetry, roleID: roleID),
            into: destination
        )
        XCTAssertEqual(
            unchanged.momentAIInteractionTasks,
            DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1)
        )

        let records = try destination.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.id, initialID)
        XCTAssertEqual(record.state, .succeeded)
        XCTAssertEqual(record.generatedText, "已经完成")
        XCTAssertEqual(record.revision, 2)
    }

    func testDuplicateSourceIdempotencyKeyIsRejectedBeforeAnyTaskInsert() throws {
        let roleID = RoleScope.legacyRoleID
        let task = makeTask(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            roleID: roleID,
            idempotencyKey: "moment-task-duplicate",
            state: .pending,
            revision: 1,
            updatedAt: date(101)
        )
        var payload = try makePayload(task: task, roleID: roleID)
        var duplicate = task
        duplicate.id = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        payload.momentAIInteractionTasks.append(duplicate)

        let destination = makeContext()
        XCTAssertThrowsError(try DataMergeService.merge(payload, into: destination)) { error in
            XCTAssertEqual(
                error as? DataMergeError,
                .duplicateSourceIDs(entity: .momentAIInteractionTask)
            )
        }
        XCTAssertEqual(
            try destination.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>()).count,
            0
        )
    }

    private func makeContext() -> ModelContext {
        ModelContext(
            PersistenceController.makeContainer(inMemory: true, preferCloud: false).container
        )
    }

    private func makePayload(
        task: AyaneMomentAIInteractionTaskExport,
        roleID: UUID
    ) throws -> AyaneDataExport {
        let context = makeContext()
        let createdAt = date(100)
        let profile = CompanionProfileRecord(
            id: roleID,
            name: "测试角色",
            userName: "你",
            prompt: "保持坦诚",
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 1,
            deviceID: "merge-test"
        )
        let conversation = ConversationRecord(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            title: "朋友圈任务测试会话",
            createdAt: createdAt,
            roleID: roleID
        )
        let post = MomentPostRecord(
            id: task.postID,
            authorKind: .user,
            body: "今天的风很轻。",
            publishedAt: createdAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 1,
            deviceID: "merge-test"
        )
        let record = MomentAIInteractionTaskRecord(
            id: task.id,
            kindRaw: task.kindRaw,
            postID: task.postID,
            targetInteractionID: task.targetInteractionID,
            parentInteractionID: task.parentInteractionID,
            rootInteractionID: task.rootInteractionID,
            roleID: task.roleID,
            stateRaw: task.stateRaw,
            attemptCount: task.attemptCount,
            nextAttemptAt: task.nextAttemptAt,
            lastError: task.lastError,
            idempotencyKey: task.idempotencyKey,
            timezoneIdentifier: task.timezoneIdentifier,
            inputText: task.inputText,
            generatedText: task.generatedText,
            generatedLike: task.generatedLike,
            resultInteractionID: task.resultInteractionID,
            leaseOwner: task.leaseOwner,
            leaseExpiresAt: task.leaseExpiresAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            revision: task.revision,
            deviceID: task.deviceID
        )
        context.insert(profile)
        context.insert(conversation)
        context.insert(post)
        context.insert(record)
        try context.save()

        let suiteName = "AyaneTests.MomentAIInteractionTaskMerge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try DataExportService.makePayload(
            context: context,
            defaults: defaults,
            now: date(200)
        )
    }

    private func makeTask(
        id: UUID,
        roleID: UUID,
        idempotencyKey: String,
        state: MomentAIInteractionTaskState,
        generatedText: String = "",
        revision: Int,
        updatedAt: Date
    ) -> AyaneMomentAIInteractionTaskExport {
        AyaneMomentAIInteractionTaskExport(
            id: id,
            kind: .reactionComment,
            postID: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            roleID: roleID,
            state: state,
            nextAttemptAt: updatedAt,
            idempotencyKey: idempotencyKey,
            timezoneIdentifier: "Asia/Shanghai",
            inputText: "今天的风很轻。",
            generatedText: generatedText,
            createdAt: date(100),
            updatedAt: updatedAt,
            revision: revision,
            deviceID: "merge-test"
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}
