import Foundation
import XCTest
@testable import Ayane

final class LorebookCharacterCardV2Tests: XCTestCase {
    func testLorebookActivatesKeywordAndRecursiveEntriesWithinScope() {
        let roleID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let recursiveID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        let document = LorebookDocument(
            name: "雾港",
            scope: .character,
            scanDepth: 2,
            tokenBudget: 500,
            recursiveScanning: true,
            maxRecursionSteps: 3,
            boundCharacterIDs: [roleID],
            entries: [
                LorebookEntry(
                    id: firstID,
                    name: "雾港入口",
                    content: "月轮塔负责记录潮汐。",
                    primaryKeys: ["雾港"]
                ),
                LorebookEntry(
                    id: recursiveID,
                    name: "潮汐规则",
                    content: "潮汐记录决定港口开放时刻。",
                    primaryKeys: ["潮汐"],
                    delayUntilRecursion: true,
                    recursionLevel: 1
                ),
            ]
        )
        let result = LorebookEngine.activate(
            documents: [document],
            context: LorebookActivationContext(
                messages: [
                    .init(
                        role: .user,
                        senderName: "用户",
                        content: "我们去雾港"
                    )
                ],
                activeCharacterID: roleID,
                tokenBudget: 500,
                deterministicSeed: "fixture"
            )
        )

        XCTAssertEqual(
            Set(result.selections.map { $0.entry.id }),
            Set([firstID, recursiveID])
        )
        XCTAssertEqual(
            result.selections.first(where: { $0.entry.id == recursiveID })?.reason,
            .recursive
        )
        XCTAssertFalse(result.overflowed)
    }

    func testLorebookScopeAndBudgetAreEnforced() {
        let roleID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let otherRoleID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let entry = LorebookEntry(
            content: "这是一段只属于绑定角色的设定。",
            strategy: .constant
        )
        let document = LorebookDocument(
            name: "角色限定",
            scope: .character,
            tokenBudget: 200,
            boundCharacterIDs: [roleID],
            entries: [entry]
        )
        let inactive = LorebookEngine.activate(
            documents: [document],
            context: LorebookActivationContext(
                messages: [.init(role: .user, content: "你好")],
                activeCharacterID: otherRoleID,
                tokenBudget: 200
            )
        )
        let activeButNoBudget = LorebookEngine.activate(
            documents: [document],
            context: LorebookActivationContext(
                messages: [.init(role: .user, content: "你好")],
                activeCharacterID: roleID,
                tokenBudget: 0
            )
        )

        XCTAssertTrue(inactive.selections.isEmpty)
        XCTAssertTrue(activeButNoBudget.selections.isEmpty)
    }

    func testCharacterCardV2RoundTripPreservesExtensionsAndPromptBoundaries() throws {
        let card = CharacterCardDocument(
            name: "绫音",
            description: "{{char}} 是来自雾港的向导。",
            personality: "清冷、克制，但会认真照顾 {{user}}。",
            scenario: "{{user}} 与 {{char}} 正在月轮塔下。",
            firstMessage: "欢迎回来，{{user}}。",
            exampleMessages: "<START>\n{{char}}: 夜里风凉。",
            creatorNotes: "这段只给创建者阅读，绝不能进入模型提示词。",
            systemPrompt: "保持 {{char}} 的身份。",
            postHistoryInstructions: "回答前核对当前场景。",
            alternateGreetings: ["你来了，{{user}}。"],
            characterBook: CharacterCardBook(
                name: "雾港规则",
                entries: [
                    CharacterCardBookEntry(
                        keys: ["月轮塔"],
                        content: "月轮塔记录潮汐。",
                        id: 7
                    )
                ]
            ),
            extensions: [
                "kin": .object([
                    "schema": .string("interaction-core-v2"),
                    "enabled": .bool(true),
                ])
            ]
        )

        let data = try card.encodedV2()
        let decoded = try CharacterCardDocument.decode(from: data)
        let plan = decoded.promptPlan(userName: "哥哥")
        let legacyPrompt = decoded.legacyCompatiblePersonaPrompt(userName: "哥哥")

        XCTAssertEqual(decoded.extensions, card.extensions)
        XCTAssertEqual(decoded.characterBook?.entries.first?.id, 7)
        XCTAssertTrue(plan.personaPrompt.contains("绫音"))
        XCTAssertTrue(plan.personaPrompt.contains("哥哥"))
        XCTAssertEqual(plan.firstMessages.first, "欢迎回来，哥哥。")
        XCTAssertEqual(plan.lorebook?.entries.count, 1)
        XCTAssertFalse(legacyPrompt.contains(card.creatorNotes))
    }

    func testCharacterCardV1ImportRemainsCompatible() throws {
        let json = """
        {
          "name": "旧版角色",
          "description": "角色描述",
          "personality": "沉稳",
          "scenario": "书房",
          "first_mes": "你好。",
          "mes_example": "<START>"
        }
        """
        let card = try CharacterCardDocument.decode(from: Data(json.utf8))

        XCTAssertEqual(card.name, "旧版角色")
        XCTAssertEqual(card.firstMessage, "你好。")
        XCTAssertEqual(card.spec, "chara_card_v2")
    }

    func testCharacterBookMapsSupportedPromptInsertionPositions() {
        let positions = [
            "before_char": LorebookInsertionPosition.beforeCharacter,
            "after_char": .afterCharacter,
            "before_example": .beforeExamples,
            "after_example": .afterExamples,
            "at_depth": .depthSystem,
            "depth_user": .depthUser,
            "depth_assistant": .depthAssistant,
        ]
        let book = CharacterCardBook(
            entries: positions.keys.sorted().map { position in
                CharacterCardBookEntry(
                    keys: [position],
                    content: position,
                    position: position
                )
            }
        )
        let entries = book.lorebook(fallbackName: "测试").entries

        for (rawValue, expected) in positions {
            XCTAssertEqual(
                entries.first(where: { $0.content == rawValue })?.insertionPosition,
                expected
            )
        }
    }

    func testLorebookMergeDeduplicatesExistingDocumentIDs() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let first = LorebookDocument(id: id, name: "旧名称")
        let duplicate = LorebookDocument(id: id, name: "新名称")

        let merged = try LorebookStore.merged(
            existing: [first, duplicate],
            imported: []
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "新名称")
    }

    func testPortableJSONValuePreservesLargeIntegerExactly() throws {
        let source = Data("9007199254740993".utf8)
        let value = try JSONDecoder().decode(PortableJSONValue.self, from: source)
        let encoded = try JSONEncoder().encode(value)

        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "9007199254740993")
    }

    func testCharacterCardRejectsOversizedInputBeforeDecoding() {
        let oversized = Data(
            repeating: 0x20,
            count: CharacterCardDocument.maximumImportBytes + 1
        )

        XCTAssertThrowsError(try CharacterCardDocument.decode(from: oversized)) { error in
            XCTAssertEqual(
                error as? CharacterCardImportError,
                .fileTooLarge(
                    maximumMegabytes: CharacterCardDocument.maximumImportMegabytes
                )
            )
        }
    }
}
