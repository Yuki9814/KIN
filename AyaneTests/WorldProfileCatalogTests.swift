import Foundation
import XCTest
@testable import Ayane

final class WorldProfileCatalogTests: XCTestCase {
    private let realityID = WorldProfileRecord.realityID
    private let fantasyID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let futureID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

    func testCanonicalWorldProfilesKeepsDistinctIDsAndMergesSameID() {
        let olderFantasy = AyaneWorldProfileExport(
            id: fantasyID,
            displayName: "魔法大陆",
            worldKind: "fantasy",
            timezoneIdentifier: "UTC",
            commonFacts: ["魔法学院"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            revision: 1,
            deviceID: "a"
        )
        let newerFantasy = AyaneWorldProfileExport(
            id: fantasyID,
            displayName: "魔法大陆（新）",
            worldKind: "fantasy",
            timezoneIdentifier: "UTC",
            commonFacts: ["魔法学院"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            revision: 2,
            deviceID: "b"
        )
        let reality = AyaneWorldProfileExport(
            id: realityID,
            displayName: "现实世界",
            worldKind: "reality"
        )

        let canonical = WorldProfileCatalog.canonicalWorldProfiles([
            olderFantasy,
            reality,
            newerFantasy
        ])

        XCTAssertEqual(canonical.count, 2)
        XCTAssertEqual(Set(canonical.map(\.id)), Set([realityID, fantasyID]))
        XCTAssertEqual(canonical.first(where: { $0.id == fantasyID })?.displayName, "魔法大陆（新）")
    }

    func testBestMatchUsesRoleNameAndPromptAgainstWorldText() {
        let reality = AyaneWorldProfileExport(
            id: realityID,
            displayName: "现实世界",
            worldKind: "reality",
            locationContext: "上海",
            commonFacts: ["日常生活"]
        )
        let fantasy = AyaneWorldProfileExport(
            id: fantasyID,
            displayName: "星辉魔法学院",
            worldKind: "fantasy",
            locationContext: "浮空城",
            commonFacts: ["古老传说"]
        )

        let match = WorldProfileCatalog.bestMatchID(
            roleName: "艾琳",
            prompt: "你是魔法学院的见习法师。",
            worlds: [reality, fantasy]
        )

        XCTAssertEqual(match, fantasyID)
    }

    func testBestMatchFallsBackToRealityThenStableFirstWorld() {
        let reality = AyaneWorldProfileExport(id: realityID, displayName: "现实世界")
        let other = AyaneWorldProfileExport(id: futureID, displayName: "远古星球")

        XCTAssertEqual(
            WorldProfileCatalog.bestMatchID(
                roleName: "陌生角色",
                prompt: "完全没有相关词语",
                worlds: [other, reality]
            ),
            realityID
        )

        XCTAssertEqual(
            WorldProfileCatalog.bestMatchID(
                roleName: "陌生角色",
                prompt: "完全没有相关词语",
                worlds: [other]
            ),
            futureID
        )
    }

    func testPersonaWorldBindingRoundTripAndLegacyDefault() throws {
        let roleID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        let profile = AyanePersonaExport(
            name: "艾琳",
            userName: "旅人",
            prompt: "魔法学院的见习法师",
            id: roleID,
            roleID: roleID,
            worldProfileID: fantasyID
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(AyanePersonaExport.self, from: data)
        XCTAssertEqual(decoded.worldProfileID, fantasyID)
        XCTAssertEqual(decoded.roleID, roleID)

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "world_profile_id")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyDecoded = try decoder.decode(AyanePersonaExport.self, from: legacyData)
        XCTAssertEqual(legacyDecoded.worldProfileID, WorldProfileRecord.realityID)
    }

    func testLegacySingularWorldBackupSynthesizesWorldCollection() throws {
        let conversationRecord = ConversationRecord(
            id: UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!,
            title: "旧会话",
            roleID: RoleScope.legacyRoleID
        )
        let roleID = RoleScope.legacyRoleID
        let persona = AyanePersonaExport(
            name: "绫音",
            userName: "你",
            prompt: "保留旧备份兼容性",
            id: roleID,
            roleID: roleID
        )
        let payload = AyaneDataExport(
            schemaVersion: 12,
            conversations: [AyaneConversationExport(conversationRecord)],
            events: [],
            memories: [],
            evidence: [],
            summaries: [],
            tombstones: [],
            persona: persona,
            settings: makeSettings(),
            worldProfile: AyaneWorldProfileExport(id: fantasyID, displayName: "魔法大陆"),
            worldProfiles: [
                AyaneWorldProfileExport(id: fantasyID, displayName: "魔法大陆")
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "world_profiles")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(AyaneDataExport.self, from: legacyData)
        XCTAssertEqual(decoded.worldProfiles.count, 1)
        XCTAssertEqual(decoded.worldProfiles.first?.id, fantasyID)
        XCTAssertEqual(decoded.worldProfile.id, fantasyID)
    }

    private func makeSettings() -> AyaneSettingsExport {
        AyaneSettingsExport(
            provider: AyaneProviderSettingsExport(
                baseURL: "https://example.com",
                model: "model",
                embeddingModel: "",
                temperature: 0.8,
                streamsResponses: true
            ),
            memory: AyaneMemorySettingsExport(
                autoExtractMemory: true,
                tokenBudget: 2_400,
                recentMessageLimit: 24,
                rawHistoryRecallEnabled: true,
                rawHistoryTokenBudget: 1_000
            ),
            persistence: AyanePersistenceSettingsExport(cloudSyncEnabled: false)
        )
    }
}
