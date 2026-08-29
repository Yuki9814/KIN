import Foundation
import XCTest
@testable import Ayane

final class MemoryCandidateAccumulatorTests: XCTestCase {
    func testSemanticTargetInOldestBatchSurvivesTenThousandBoundedScan() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var accumulator = MemoryCandidateAccumulator(
            query: "那件只有我们知道的约定",
            limit: 192,
            now: now,
            queryEmbedding: [1, 0, 0]
        )

        let total = 10_001
        let targetID = "semantic-oldest-target"
        for start in stride(from: 0, to: total, by: 128) {
            let end = min(start + 128, total)
            let batch = (start..<end).map { index in
                MemorySnapshot(
                    id: index == total - 1 ? targetID : "noise-\(index)",
                    text: index == total - 1 ? "我们约定下雨天一起听旧唱片" : "无关记录 \(index)",
                    createdAt: now.addingTimeInterval(Double(-index)),
                    updatedAt: now.addingTimeInterval(Double(-index)),
                    importance: index == total - 1 ? 0.9 : 0.3,
                    confidence: 1,
                    embedding: index == total - 1 ? [1, 0, 0] : [0, 1, 0]
                )
            }
            accumulator.consume(batch)
            XCTAssertLessThanOrEqual(accumulator.count, 192)
        }

        XCTAssertTrue(accumulator.snapshots.contains { $0.id == targetID })
    }

    func testLexicalFallbackKeepsOldMatchingMemoryWithoutEmbedding() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var accumulator = MemoryCandidateAccumulator(
            query: "乌龙茶",
            limit: 64,
            now: now,
            queryEmbedding: nil
        )
        accumulator.consume((0..<256).map { index in
            MemorySnapshot(
                id: "recent-\(index)",
                text: "无关事项 \(index)",
                createdAt: now,
                importance: 0.5,
                confidence: 1
            )
        })
        accumulator.consume([
            MemorySnapshot(
                id: "old-lexical-target",
                text: "绫音记得用户最喜欢乌龙茶",
                createdAt: now.addingTimeInterval(-100_000),
                importance: 0.8,
                confidence: 1
            )
        ])

        XCTAssertEqual(accumulator.snapshots.map(\.id), ["old-lexical-target"])
    }

    func testDuplicateApplicationIDKeepsNewestSnapshotAndOrderingIsStable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func run() -> [MemorySnapshot] {
            var accumulator = MemoryCandidateAccumulator(
                query: "旅行",
                limit: 8,
                now: now,
                queryEmbedding: nil
            )
            accumulator.consume([
                MemorySnapshot(
                    id: "same-id",
                    text: "旧的旅行计划",
                    createdAt: now.addingTimeInterval(-200),
                    updatedAt: now.addingTimeInterval(-100),
                    importance: 0.7
                ),
                MemorySnapshot(
                    id: "another-id",
                    text: "秋天旅行",
                    createdAt: now.addingTimeInterval(-50),
                    importance: 0.7
                )
            ])
            accumulator.consume([
                MemorySnapshot(
                    id: "same-id",
                    text: "新的旅行计划",
                    createdAt: now.addingTimeInterval(-200),
                    updatedAt: now,
                    importance: 0.7
                )
            ])
            return accumulator.snapshots
        }

        let first = run()
        let second = run()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first { $0.id == "same-id" }?.text, "新的旅行计划")
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    }
}
