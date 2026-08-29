import Foundation
import XCTest
@testable import Ayane

final class MemoryEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLexicalRelevanceAndSourceIDArePreserved() {
        let memories = [
            MemorySnapshot(id: "blue", text: "My favorite color is blue.", sourceID: "chat-1", createdAt: now),
            MemorySnapshot(id: "tea", text: "I prefer green tea.", sourceID: "chat-2", createdAt: now)
        ]

        let results = MemoryEngine().search(
            "favorite color blue",
            in: memories,
            options: MemorySearchOptions(now: now)
        )

        XCTAssertEqual(results.first?.id, "blue")
        XCTAssertEqual(results.first?.sourceID, "chat-1")
        XCTAssertGreaterThan(results.first?.lexicalScore ?? 0, 0.9)
    }

    func testChineseCharactersAndBigramsTokenizeAndMatch() {
        let tokens = MemoryTokenizer.tokens(from: "我喜欢火锅")
        XCTAssertTrue(tokens.contains("火"))
        XCTAssertTrue(tokens.contains("锅"))
        XCTAssertTrue(tokens.contains("火锅"))

        let memory = MemorySnapshot(id: "cn", text: "今晚一起吃火锅", sourceID: "notes", createdAt: now)
        let result = MemoryEngine().search("火锅", in: [memory], options: MemorySearchOptions(now: now))
        XCTAssertEqual(result.first?.id, "cn")
        XCTAssertEqual(result.first?.matchedTokens, ["火", "锅", "火锅"])
    }

    func testJapaneseAndKoreanUseTheSameCharacterBigramSemanticsAsFTS() {
        let koreanTokens = MemoryTokenizer.tokens(from: "한국어를")
        let japaneseTokens = MemoryTokenizer.tokens(from: "日本語を")
        XCTAssertTrue(koreanTokens.contains("한국"))
        XCTAssertTrue(japaneseTokens.contains("日本"))

        let memories = [
            MemorySnapshot(id: "ko", text: "한국어를 공부합니다", createdAt: now),
            MemorySnapshot(id: "ja", text: "日本語を勉強しています", createdAt: now)
        ]
        XCTAssertEqual(
            MemoryEngine().search("한국어", in: memories, options: MemorySearchOptions(now: now)).first?.id,
            "ko"
        )
        XCTAssertEqual(
            MemoryEngine().search("日本語", in: memories, options: MemorySearchOptions(now: now)).first?.id,
            "ja"
        )
    }

    func testTokenBudgetIsStrictAndSkipsOversizedTopCandidate() {
        let memories = [
            MemorySnapshot(id: "long", text: "blue favorite color is a calm ocean shade", sourceID: "a", createdAt: now),
            MemorySnapshot(id: "short", text: "blue color", sourceID: "b", createdAt: now)
        ]

        let results = MemoryEngine().search(
            "blue color",
            in: memories,
            options: MemorySearchOptions(maxResults: 3, tokenBudget: 4, now: now)
        )

        XCTAssertFalse(results.contains { $0.id == "long" })
        XCTAssertLessThanOrEqual(results.reduce(0) { $0 + $1.tokenCount }, 4)
    }

    func testVectorSimilarityRanksSemanticMatch() {
        let memories = [
            MemorySnapshot(id: "near", text: "unrelated label", sourceID: "vector", createdAt: now, embedding: [1, 0]),
            MemorySnapshot(id: "far", text: "also unrelated", sourceID: "vector-2", createdAt: now, embedding: [0, 1])
        ]

        let results = MemoryEngine().search(
            "semantic query",
            in: memories,
            options: MemorySearchOptions(now: now, queryEmbedding: [1, 0])
        )

        XCTAssertEqual(results.first?.id, "near")
        XCTAssertEqual(results.first?.cosineSimilarity ?? 0, 1, accuracy: 0.0001)
    }

    func testExactAndNearDuplicatesAreCollapsed() {
        let memories = [
            MemorySnapshot(id: "first", text: "Remember my birthday is Friday", sourceID: "one", createdAt: now),
            MemorySnapshot(id: "duplicate", text: "remember my birthday is Friday", sourceID: "two", createdAt: now),
            MemorySnapshot(id: "near", text: "Remember my birthday is this Friday", sourceID: "three", createdAt: now)
        ]

        let results = MemoryEngine().search(
            "birthday Friday",
            in: memories,
            options: MemorySearchOptions(now: now, duplicateJaccardThreshold: 0.70)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "first")
    }

    func testPinnedMemoryReceivesBoost() {
        let memories = [
            MemorySnapshot(id: "ordinary", text: "blue", sourceID: "ordinary", createdAt: now, importance: 1),
            MemorySnapshot(id: "pinned", text: "blue", sourceID: "pinned", createdAt: now, importance: 0, isPinned: true)
        ]

        let results = MemoryEngine().search("blue", in: memories, options: MemorySearchOptions(now: now))
        XCTAssertEqual(results.first?.id, "pinned")
    }

    func testExpiredAndIrrelevantMemoriesAreExcluded() {
        let memories = [
            MemorySnapshot(id: "expired", text: "blue", sourceID: "expired", createdAt: now, expiresAt: now.addingTimeInterval(-1)),
            MemorySnapshot(id: "irrelevant", text: "green tea", sourceID: "irrelevant", createdAt: now),
            MemorySnapshot(id: "valid", text: "blue sky", sourceID: "valid", createdAt: now)
        ]

        let results = MemoryEngine().search("blue", in: memories, options: MemorySearchOptions(now: now))
        XCTAssertEqual(results.map(\.id), ["valid"])
    }

    func testHighValueExplicitMemoryIsAvailableWithoutEmbeddingOrWordOverlap() {
        let memory = MemorySnapshot(
            id: "favorite-drink",
            text: "用户明确偏好乌龙茶",
            createdAt: now,
            importance: 1,
            confidence: 1
        )
        let results = MemoryEngine().search(
            "我最爱的饮品是什么",
            in: [memory],
            options: MemorySearchOptions(
                now: now,
                queryEmbedding: nil,
                allowHighValueFallback: true
            )
        )
        XCTAssertEqual(results.first?.id, memory.id)
    }

    func testSensitiveMemoryNeverUsesUnrelatedHighValueFallback() {
        let memory = MemorySnapshot(
            id: "sensitive",
            text: "用户的敏感资料",
            createdAt: now,
            importance: 1,
            confidence: 1,
            isPinned: true,
            isSensitive: true
        )
        let results = MemoryEngine().search(
            "我最爱的饮品是什么",
            in: [memory],
            options: MemorySearchOptions(
                now: now,
                queryEmbedding: nil,
                allowHighValueFallback: true
            )
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testEmbeddingCodecRoundTripsAndRejectsMalformedData() {
        let original: [Float] = [1, -0.25, 0, .pi]
        let encoded = MemoryEmbeddingCodec.encode(original)
        let decoded = MemoryEmbeddingCodec.decode(encoded)

        XCTAssertEqual(decoded?.count, original.count)
        for (actual, expected) in zip(decoded ?? [], original) {
            XCTAssertEqual(actual, expected, accuracy: 0)
        }
        XCTAssertNil(MemoryEmbeddingCodec.decode(Data([1, 2, 3])))
        XCTAssertEqual(MemoryEmbeddingCodec.cosine(original, original) ?? 0, 1, accuracy: 0.0001)
    }

    func testStableTieBreakPreservesInputOrderAndIsRepeatable() {
        let memories = [
            MemorySnapshot(id: "z", text: "same", sourceID: "z", createdAt: now),
            MemorySnapshot(id: "a", text: "same", sourceID: "a", createdAt: now)
        ]
        let options = MemorySearchOptions(now: now, diversityStrength: 0)
        let first = MemoryEngine().search("same", in: memories, options: options)
        let second = MemoryEngine().search("same", in: memories, options: options)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.first?.id, "z")
    }

    func testDiversityPrefersAnotherSourceWhenScoresAreClose() {
        let memories = [
            MemorySnapshot(id: "a1", text: "blue sky", sourceID: "a", createdAt: now),
            MemorySnapshot(id: "a2", text: "blue ocean", sourceID: "a", createdAt: now),
            MemorySnapshot(id: "b1", text: "blue light", sourceID: "b", createdAt: now)
        ]

        let results = MemoryEngine().search(
            "blue",
            in: memories,
            options: MemorySearchOptions(maxResults: 2, now: now, diversityStrength: 0.20)
        )
        XCTAssertEqual(Set(results.map(\.sourceID)).count, 2)
    }
}
