import Foundation
import XCTest
@testable import Ayane

final class InteractionCorePreferencesAdapterTests: XCTestCase {
    func testGroupPreferencesResolveTypedPlannerValues() {
        let manual = GroupInteractionPreferences(
            strategyRaw: "manual",
            promptAssemblyModeRaw: "joinCharacterCards"
        )
        XCTAssertEqual(manual.turnStrategy, .manual)
        XCTAssertEqual(manual.promptAssemblyMode, .joinCharacterCards)

        let invalid = GroupInteractionPreferences(
            strategyRaw: "future-mode",
            promptAssemblyModeRaw: "future-prompt-mode"
        )
        XCTAssertEqual(invalid.turnStrategy, .natural)
        XCTAssertEqual(invalid.promptAssemblyMode, .swapActiveCharacter)
    }

    func testImagePreferencesResolveBatchExecutorOptions() {
        let preferences = ImageInteractionPreferences(
            imageCount: 3,
            aspectRatioRaw: "tallPortrait",
            qualityRaw: "high",
            styleRaw: "animeCG",
            preserveCharacterIdentity: false,
            negativePrompt: "重复人物",
            maximumRetries: 1
        )
        let options = preferences.batchOptions

        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.aspectRatio, .tallPortrait)
        XCTAssertEqual(options.quality, .high)
        XCTAssertEqual(options.style, .animeCG)
        XCTAssertFalse(options.preserveCharacterIdentity)
        XCTAssertEqual(options.negativePrompt, "重复人物")
        XCTAssertEqual(options.maximumRetries, 1)
    }
}
