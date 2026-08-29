import XCTest
@testable import Ayane

final class StickerPickerViewTests: XCTestCase {
    func testPickerCategoriesCoverRecentGenericAndRoleSurfaces() {
        XCTAssertEqual(
            StickerPickerCategory.allCases.map(\.title),
            ["最近", "通用", "绫音"]
        )
    }

    func testRecentSurfaceFallsBackToCatalogItemsAndPreservesOrder() {
        let fallback = StickerPickerCatalog.stickers(
            for: .recent,
            recentStickerIDs: []
        )
        XCTAssertEqual(fallback, Array(StickerCatalog.generic.prefix(8)))

        let ids = [
            StickerCatalog.ayaneExclusive[1].stickerID,
            StickerCatalog.generic[2].stickerID,
            "missing.sticker"
        ]
        let recent = StickerPickerCatalog.stickers(
            for: .recent,
            recentStickerIDs: ids
        )
        XCTAssertEqual(
            recent.map(\.stickerID),
            [StickerCatalog.ayaneExclusive[1].stickerID, StickerCatalog.generic[2].stickerID]
        )
    }

    func testTextDoesNotProduceImplicitStickerDecoration() {
        XCTAssertNil(
            MessageStickerDecoration.decide(
                eventID: UUID(),
                role: .assistant,
                state: .complete,
                content: "别怕，我会陪你。"
            )
        )
    }

    func testExplicitStickerIDResolvesDeterministically() {
        let item = StickerCatalog.ayaneExclusive[0]
        let decoration = MessageStickerDecoration.decide(
            eventID: UUID(),
            role: .assistant,
            state: .complete,
            content: "普通文本",
            stickerID: item.stickerID
        )

        XCTAssertEqual(decoration?.assetName, item.resourceName)
        XCTAssertEqual(decoration?.accessibilityLabel, item.alternativeText)
    }
}
