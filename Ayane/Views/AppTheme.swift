import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum AppTheme {
    /// The public WeChat UI is the visual contract for the social shell.
    /// Product content remains Ayane-specific; these tokens intentionally keep
    /// the chrome, density and message hierarchy familiar.
    static let accent = Color(red: 7 / 255, green: 193 / 255, blue: 96 / 255)

    #if os(macOS)
    // macOS colors use an appearance provider so the same shell remains
    // legible when the user changes the system appearance at runtime. Keep
    // the light values close to WeChat's flat palette and use slightly lifted
    // dark surfaces instead of a second, hard-coded black UI.
    static let outgoingBubble = macAdaptiveColor(
        light: NSColor(calibratedRed: 157 / 255, green: 242 / 255, blue: 159 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 46 / 255, green: 194 / 255, blue: 93 / 255, alpha: 1)
    )
    static let incomingBubble = macAdaptiveColor(
        light: NSColor(calibratedRed: 238 / 255, green: 238 / 255, blue: 240 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 52 / 255, green: 53 / 255, blue: 56 / 255, alpha: 1)
    )
    static let chatBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 29 / 255, green: 30 / 255, blue: 32 / 255, alpha: 1)
    )
    static let rootBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 232 / 255, green: 232 / 255, blue: 234 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 23 / 255, green: 24 / 255, blue: 26 / 255, alpha: 1)
    )
    static let barBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 35 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1)
    )
    static let composerBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 37 / 255, green: 38 / 255, blue: 40 / 255, alpha: 1)
    )
    static let composerFieldBackground = macAdaptiveColor(
        light: NSColor(calibratedWhite: 1, alpha: 1),
        dark: NSColor(calibratedRed: 48 / 255, green: 49 / 255, blue: 52 / 255, alpha: 1)
    )
    static let stickerPickerBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 31 / 255, green: 32 / 255, blue: 34 / 255, alpha: 1)
    )
    static let rowBackground = macAdaptiveColor(
        light: NSColor(calibratedWhite: 1, alpha: 1),
        dark: NSColor(calibratedRed: 31 / 255, green: 32 / 255, blue: 34 / 255, alpha: 1)
    )
    static let searchBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 45 / 255, green: 46 / 255, blue: 49 / 255, alpha: 1)
    )
    static let secondarySurface = macAdaptiveColor(
        light: NSColor(calibratedRed: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 43 / 255, green: 44 / 255, blue: 47 / 255, alpha: 1)
    )
    static let divider = macAdaptiveColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.085),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )
    static let primaryText = Color(nsColor: .labelColor)
    static let messageText = Color(nsColor: .labelColor)
    static let messageTextOnOutgoing = macAdaptiveColor(
        light: NSColor(calibratedRed: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 15 / 255, green: 61 / 255, blue: 30 / 255, alpha: 1)
    )
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let inactiveTab = Color(nsColor: .secondaryLabelColor)
    static let iconPrimary = Color(nsColor: .labelColor)
    static let composerIcon = Color(nsColor: .labelColor)
    static let iconOnAccent = Color.white
    static let momentsAccent = macAdaptiveColor(
        light: NSColor(calibratedRed: 69 / 255, green: 107 / 255, blue: 155 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 168 / 255, green: 199 / 255, blue: 250 / 255, alpha: 1)
    )
    /// Shell-specific surfaces remain semantic tokens so Mac views do not
    /// grow their own fixed palette.
    static let railBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 232 / 255, green: 242 / 255, blue: 238 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 28 / 255, green: 30 / 255, blue: 32 / 255, alpha: 1)
    )
    static let sessionBackground = macAdaptiveColor(
        light: NSColor(calibratedRed: 240 / 255, green: 240 / 255, blue: 242 / 255, alpha: 1),
        dark: NSColor(calibratedRed: 36 / 255, green: 37 / 255, blue: 40 / 255, alpha: 1)
    )
    #elseif os(iOS)
    static let outgoingBubble = adaptiveColor(
        light: UIColor(red: 149 / 255, green: 236 / 255, blue: 105 / 255, alpha: 1),
        dark: UIColor(red: 89 / 255, green: 176 / 255, blue: 105 / 255, alpha: 1)
    )
    static let incomingBubble = adaptiveColor(
        light: .white,
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 44 / 255, alpha: 1)
    )
    static let chatBackground = adaptiveColor(
        light: UIColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1),
        dark: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
    )
    static let rootBackground = adaptiveColor(
        light: UIColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1),
        dark: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
    )
    static let barBackground = adaptiveColor(
        light: UIColor(red: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1),
        dark: UIColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1)
    )
    static let composerBackground = adaptiveColor(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 35 / 255, green: 35 / 255, blue: 35 / 255, alpha: 1)
    )
    static let composerFieldBackground = adaptiveColor(
        light: UIColor.white,
        dark: UIColor(red: 48 / 255, green: 48 / 255, blue: 48 / 255, alpha: 1)
    )
    static let stickerPickerBackground = adaptiveColor(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 29 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1)
    )
    static let rowBackground = adaptiveColor(light: .white, dark: UIColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1))
    static let searchBackground = adaptiveColor(
        light: UIColor(red: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1),
        dark: UIColor(red: 29 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1)
    )
    static let secondarySurface = adaptiveColor(
        light: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
        dark: UIColor(red: 37 / 255, green: 37 / 255, blue: 37 / 255, alpha: 1)
    )
    static let divider = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.085),
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    static let primaryText = Color(uiColor: .label)
    static let messageText = adaptiveColor(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        dark: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
    )
    static let messageTextOnOutgoing = adaptiveColor(
        light: UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
        dark: UIColor(red: 18 / 255, green: 63 / 255, blue: 32 / 255, alpha: 1)
    )
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let inactiveTab = Color(uiColor: .secondaryLabel)
    static let iconPrimary = Color(uiColor: .label)
    static let composerIcon = Color(uiColor: .label)
    static let iconOnAccent = Color.white
    /// Accent for author names and interaction summaries on the Moments feed.
    /// The dark variant is intentionally lighter so it remains readable on
    /// the dark row/surface tokens.
    static let momentsAccent = adaptiveColor(
        light: UIColor(red: 69 / 255, green: 107 / 255, blue: 155 / 255, alpha: 1),
        dark: UIColor(red: 168 / 255, green: 199 / 255, blue: 250 / 255, alpha: 1)
    )
    #else
    static let outgoingBubble = Color(red: 149 / 255, green: 236 / 255, blue: 105 / 255)
    static let incomingBubble = Color.white
    static let chatBackground = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    static let rootBackground = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    static let barBackground = Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    static let composerBackground = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let composerFieldBackground = Color.white
    static let stickerPickerBackground = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let rowBackground = Color.white
    static let searchBackground = Color.white
    static let secondarySurface = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let divider = Color.black.opacity(0.085)
    static let primaryText = Color.black.opacity(0.92)
    static let messageText = Color.black.opacity(0.92)
    static let messageTextOnOutgoing = Color.black.opacity(0.92)
    static let secondaryText = Color(red: 178 / 255, green: 178 / 255, blue: 178 / 255)
    static let tertiaryText = Color.black.opacity(0.5)
    static let inactiveTab = Color.black.opacity(0.78)
    static let iconPrimary = Color.black.opacity(0.88)
    static let composerIcon = Color.black.opacity(0.86)
    static let iconOnAccent = Color.white
    static let momentsAccent = Color(red: 69 / 255, green: 107 / 255, blue: 155 / 255)
    #endif

    // Compatibility aliases used by non-chat screens while the semantic
    // token names above remain the source of truth for chat UI.
    static let userBubble = outgoingBubble
    static let assistantBubble = incomingBubble

    /// Semantic red used for an active Moments like. Keeping this separate
    /// from the WeChat green action accent makes the selected state clear
    /// without hard-coding a color in the feed views.
    static let momentsLikeAccent = Color(red: 214 / 255, green: 55 / 255, blue: 55 / 255)

    #if os(iOS)
    static let subtleBorder = adaptiveColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    #elseif os(macOS)
    static let subtleBorder = macAdaptiveColor(
        light: NSColor(calibratedWhite: 0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1, alpha: 0.10)
    )
    #else
    static let subtleBorder = Color.black.opacity(0.08)
    #endif
    static let warmGlow = Color.clear

    static let contentMaxWidth: CGFloat = 820
    static let cornerRadius: CGFloat = 4
    static let pagePadding: CGFloat = 12

    #if os(iOS)
    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
    #elseif os(macOS)
    private static func macAdaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    #endif
}
