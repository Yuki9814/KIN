import Foundation

/// Bundled fallbacks for the one shipped companion. A user-imported
/// `avatarImageData` always wins; user-created roles never consult this map.
enum BuiltInCompanionAvatarCatalog {
    static let assetNameByDisplayName: [String: String] = [
        "绫音": "AyaneAvatar"
    ]

    static func assetName(for displayName: String) -> String? {
        assetNameByDisplayName[
            displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
    }
}
