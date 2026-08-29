import Foundation
import SwiftUI

/// The small set of surfaces exposed by the WeChat-style sticker tray.
/// `recent` is local to the current chat screen; selecting an item moves it to
/// the front so returning to the tray feels like the native recent tab.
enum StickerPickerCategory: String, CaseIterable, Identifiable {
    case recent
    case generic
    case ayane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近"
        case .generic: "通用"
        case .ayane: "绫音"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .generic: "face.smiling"
        case .ayane: "person.crop.circle"
        }
    }

    var accessibilityLabel: String {
        "\(title)表情"
    }
}

enum StickerPickerCatalog {
    static func stickers(
        for category: StickerPickerCategory,
        recentStickerIDs: [String]
    ) -> [StickerDefinition] {
        switch category {
        case .recent:
            let recent = recentStickerIDs.compactMap(StickerCatalog.sticker(stickerID:))
            return recent.isEmpty ? Array(StickerCatalog.generic.prefix(8)) : recent
        case .generic:
            return StickerCatalog.generic
        case .ayane:
            return StickerCatalog.ayaneExclusive
        }
    }
}

enum StickerRecentStore {
    private static let key = "stickers.recentIDs"

    static func load(defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return stored.filter { StickerCatalog.item(for: $0) != nil }.reduce(into: []) {
            if !$0.contains($1) { $0.append($1) }
        }
    }

    @discardableResult
    static func remember(
        _ stickerID: String,
        defaults: UserDefaults = .standard
    ) -> [String] {
        guard StickerCatalog.item(for: stickerID) != nil else { return load(defaults: defaults) }
        var recent = load(defaults: defaults)
        recent.removeAll { $0 == stickerID }
        recent.insert(stickerID, at: 0)
        recent = Array(recent.prefix(12))
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: key)
        }
        return recent
    }
}

struct StickerPickerView: View {
    let onSelect: (StickerDefinition) -> Void

    @State private var selectedCategory: StickerPickerCategory = .recent
    @State private var recentStickerIDs: [String]

    init(
        recentStickerIDs: [String] = StickerRecentStore.load(),
        onSelect: @escaping (StickerDefinition) -> Void
    ) {
        self.onSelect = onSelect
        _recentStickerIDs = State(initialValue: recentStickerIDs)
    }

    var body: some View {
        #if os(macOS)
        pickerSurface(
            columnCount: 5,
            rowSpacing: 4,
            stickerSize: 56,
            height: 264
        )
        #else
        pickerSurface(
            columnCount: 4,
            rowSpacing: 6,
            stickerSize: 62,
            height: 270
        )
        #endif
    }

    @ViewBuilder
    private func pickerSurface(
        columnCount: Int,
        rowSpacing: CGFloat,
        stickerSize: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            categoryBar

            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 44), spacing: 4),
                        count: columnCount
                    ),
                    spacing: rowSpacing
                ) {
                    ForEach(displayedStickers) { sticker in
                        stickerButton(sticker, size: stickerSize)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppTheme.stickerPickerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        #if os(macOS)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 0.5)
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wechat.chat.sticker-panel")
    }

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(StickerPickerCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    categoryButtonLabel(for: category)
                        .foregroundStyle(
                            selectedCategory == category
                                ? AppTheme.iconPrimary
                                : AppTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            selectedCategory == category
                                ? selectedCategoryBackground
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.accessibilityLabel)
                .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                .accessibilityIdentifier("wechat.sticker.category.\(category.id)")
            }

            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: 0.5, height: 24)
                .padding(.horizontal, 5)

            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44, height: 44)
                .opacity(0.62)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("表情设置")
                .accessibilityValue("暂未开放")
                .accessibilityHint("表情设置功能暂未开放")
                .accessibilityIdentifier("wechat.sticker.settings")
                .disabled(true)
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(AppTheme.stickerPickerBackground)
    }

    @ViewBuilder
    private func categoryButtonLabel(for category: StickerPickerCategory) -> some View {
        #if os(macOS)
        Text(category.title)
            .font(.system(size: 12, weight: .medium))
        #else
        Image(systemName: category.systemImage)
            .font(.system(size: 21, weight: .regular))
        #endif
    }

    private var selectedCategoryBackground: Color {
        #if os(macOS)
        AppTheme.accent.opacity(0.14)
        #else
        AppTheme.divider
        #endif
    }

    private func stickerButton(_ sticker: StickerDefinition, size: CGFloat) -> some View {
        Button {
            remember(sticker)
            onSelect(sticker)
        } label: {
            StickerAssetView(definition: sticker, size: size)
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sticker.alternativeText)
        .accessibilityHint("轻点发送这张表情")
        .accessibilityIdentifier("wechat.sticker.\(sticker.stickerID)")
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppTheme.iconPrimary)
                .frame(width: 6, height: 6)
            Circle()
                .fill(AppTheme.secondaryText.opacity(0.55))
                .frame(width: 6, height: 6)

            Spacer(minLength: 12)

            Text("选择表情后发送")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: 28)
    }

    private var displayedStickers: [StickerDefinition] {
        StickerPickerCatalog.stickers(
            for: selectedCategory,
            recentStickerIDs: recentStickerIDs
        )
    }

    static func stickers(
        for category: StickerPickerCategory,
        recentStickerIDs: [String]
    ) -> [StickerDefinition] {
        StickerPickerCatalog.stickers(
            for: category,
            recentStickerIDs: recentStickerIDs
        )
    }

    private func remember(_ sticker: StickerDefinition) {
        recentStickerIDs = StickerRecentStore.remember(sticker.stickerID)
    }
}

#Preview("Sticker picker") {
    StickerPickerView { _ in }
        .preferredColorScheme(.dark)
}
