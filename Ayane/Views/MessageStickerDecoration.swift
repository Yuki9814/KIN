import Foundation
import SwiftUI

/// Presentation metadata for an explicit sticker payload.
///
/// Stickers are message payloads, not an inference made from message text.
/// Keeping the lookup here gives the chat row and accessibility label one
/// deterministic source of truth while preserving the legacy type name used
/// by older previews/tests.
struct MessageStickerDecoration: Equatable {
    let assetName: String
    let accessibilityLabel: String

    static func definition(for stickerID: String?) -> Self? {
        guard let stickerID,
              let definition = StickerCatalog.sticker(stickerID: stickerID) else {
            return nil
        }
        return Self(
            assetName: definition.resourceName,
            accessibilityLabel: definition.alternativeText
        )
    }

    /// Compatibility entry point for callers that used the old decoration
    /// API. It intentionally ignores message text and returns a decoration
    /// only when an explicit sticker identifier is supplied.
    static func decide(
        eventID: UUID?,
        role: EventRole,
        state: EventDeliveryState,
        content: String,
        stickerID: String? = nil
    ) -> Self? {
        guard role == .assistant || role == .user,
              state == .complete else {
            return nil
        }
        return definition(for: stickerID)
    }
}

/// Every catalog item has a real 1x/2x/3x transparent raster resource. The
/// fallback remains defensive for an invalid future catalog entry, but none of
/// the shipped 24 stickers should render as a generic system icon.
enum StickerVisualAssets {
    static let bundledAssetNames = Set(StickerCatalog.all.map(\.resourceName))

    static func fallbackSystemImage(for stickerID: String) -> String {
        let symbols = [
            "hand.thumbsup",
            "face.smiling",
            "face.smiling.inverse",
            "hands.clap",
            "checkmark.seal",
            "questionmark.circle",
            "exclamationmark.circle",
            "lightbulb",
            "checkmark.circle",
            "bolt.heart",
            "hand.raised",
            "minus.circle",
            "eye.slash",
            "party.popper",
            "ellipsis",
            "hand.wave"
        ]
        let value = stickerID.unicodeScalars.reduce(into: 0) { result, scalar in
            result = (result &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return symbols[value % symbols.count]
    }
}

/// Shared sticker renderer used by both the picker and conversation rows.
/// It prefers the real bundled image and has a stable symbol fallback for
/// catalog entries whose optional art has not shipped in this build.
struct StickerAssetView: View {
    let definition: StickerDefinition
    var size: CGFloat = 64

    var body: some View {
        Group {
            if StickerVisualAssets.bundledAssetNames.contains(definition.resourceName) {
                Image(definition.resourceName)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: StickerVisualAssets.fallbackSystemImage(for: definition.stickerID))
                    .font(.system(size: size * 0.46, weight: .regular))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
