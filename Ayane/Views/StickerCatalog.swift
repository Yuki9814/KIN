import Foundation

enum StickerCategory: String, Codable, CaseIterable, Sendable {
    case genericReaction = "generic_reaction"
    case ayaneExclusive = "ayane_exclusive"

    var title: String {
        switch self {
        case .genericReaction: "通用反应"
        case .ayaneExclusive: "绫音专属"
        }
    }

    /// Short compatibility spelling for catalog filters.
    static var generic: Self { .genericReaction }
    static var ayane: Self { .ayaneExclusive }
}

/// One structured sticker record. No keyword matching or random selection is
/// part of this catalog; callers choose by `stickerID` and can render the
/// declared local resource deterministically.
struct StickerDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    let stickerID: String
    let resourceName: String
    let category: StickerCategory
    let alternativeText: String

    var id: String { stickerID }
    var altText: String { alternativeText }
}

typealias StickerCatalogItem = StickerDefinition

struct StickerCatalog {
    static let all: [StickerDefinition] = [
        StickerDefinition(stickerID: "generic.reaction.01", resourceName: "StickerGeneric01", category: .genericReaction, alternativeText: "通用反应：点头"),
        StickerDefinition(stickerID: "generic.reaction.02", resourceName: "StickerGeneric02", category: .genericReaction, alternativeText: "通用反应：微笑"),
        StickerDefinition(stickerID: "generic.reaction.03", resourceName: "StickerGeneric03", category: .genericReaction, alternativeText: "通用反应：大笑"),
        StickerDefinition(stickerID: "generic.reaction.04", resourceName: "StickerGeneric04", category: .genericReaction, alternativeText: "通用反应：鼓掌"),
        StickerDefinition(stickerID: "generic.reaction.05", resourceName: "StickerGeneric05", category: .genericReaction, alternativeText: "通用反应：赞同"),
        StickerDefinition(stickerID: "generic.reaction.06", resourceName: "StickerGeneric06", category: .genericReaction, alternativeText: "通用反应：疑问"),
        StickerDefinition(stickerID: "generic.reaction.07", resourceName: "StickerGeneric07", category: .genericReaction, alternativeText: "通用反应：惊讶"),
        StickerDefinition(stickerID: "generic.reaction.08", resourceName: "StickerGeneric08", category: .genericReaction, alternativeText: "通用反应：思考"),
        StickerDefinition(stickerID: "generic.reaction.09", resourceName: "StickerGeneric09", category: .genericReaction, alternativeText: "通用反应：收到"),
        StickerDefinition(stickerID: "generic.reaction.10", resourceName: "StickerGeneric10", category: .genericReaction, alternativeText: "通用反应：加油"),
        StickerDefinition(stickerID: "generic.reaction.11", resourceName: "StickerGeneric11", category: .genericReaction, alternativeText: "通用反应：抱歉"),
        StickerDefinition(stickerID: "generic.reaction.12", resourceName: "StickerGeneric12", category: .genericReaction, alternativeText: "通用反应：无奈"),
        StickerDefinition(stickerID: "generic.reaction.13", resourceName: "StickerGeneric13", category: .genericReaction, alternativeText: "通用反应：害羞"),
        StickerDefinition(stickerID: "generic.reaction.14", resourceName: "StickerGeneric14", category: .genericReaction, alternativeText: "通用反应：庆祝"),
        StickerDefinition(stickerID: "generic.reaction.15", resourceName: "StickerGeneric15", category: .genericReaction, alternativeText: "通用反应：沉默"),
        StickerDefinition(stickerID: "generic.reaction.16", resourceName: "StickerGeneric16", category: .genericReaction, alternativeText: "通用反应：再见"),
        StickerDefinition(stickerID: "ayane.exclusive.01", resourceName: "AyaneStickerHappy", category: .ayaneExclusive, alternativeText: "绫音专属：开心"),
        StickerDefinition(stickerID: "ayane.exclusive.02", resourceName: "AyaneStickerComfort", category: .ayaneExclusive, alternativeText: "绫音专属：安慰"),
        StickerDefinition(stickerID: "ayane.exclusive.03", resourceName: "AyaneStickerAngry", category: .ayaneExclusive, alternativeText: "绫音专属：生气"),
        StickerDefinition(stickerID: "ayane.exclusive.04", resourceName: "AyaneStickerShy", category: .ayaneExclusive, alternativeText: "绫音专属：害羞"),
        StickerDefinition(stickerID: "ayane.exclusive.05", resourceName: "AyaneStickerProud", category: .ayaneExclusive, alternativeText: "绫音专属：小小骄傲"),
        StickerDefinition(stickerID: "ayane.exclusive.06", resourceName: "AyaneStickerTea", category: .ayaneExclusive, alternativeText: "绫音专属：递茶"),
        StickerDefinition(stickerID: "ayane.exclusive.07", resourceName: "AyaneStickerPeek", category: .ayaneExclusive, alternativeText: "绫音专属：探头"),
        StickerDefinition(stickerID: "ayane.exclusive.08", resourceName: "AyaneStickerSleep", category: .ayaneExclusive, alternativeText: "绫音专属：晚安"),
    ]

    static var generic: [StickerDefinition] {
        all.filter { $0.category == .genericReaction }
    }

    static var ayaneExclusive: [StickerDefinition] {
        all.filter { $0.category == .ayaneExclusive }
    }

    static func sticker(stickerID: String) -> StickerDefinition? {
        all.first { $0.stickerID == stickerID }
    }

    static func item(for stickerID: String) -> StickerDefinition? {
        sticker(stickerID: stickerID)
    }
}
