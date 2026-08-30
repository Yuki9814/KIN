import Foundation

@MainActor
extension AppModel {
    func groupInteractionPreferences(
        conversationID: UUID
    ) -> GroupInteractionPreferences {
        InteractionCorePreferencesStore.groupPreferences(
            conversationID: conversationID
        )
    }

    func saveGroupInteractionPreferences(
        _ preferences: GroupInteractionPreferences,
        conversationID: UUID
    ) throws {
        try InteractionCorePreferencesStore.saveGroupPreferences(
            preferences,
            conversationID: conversationID
        )
    }

    func resetGroupInteractionPreferences(
        conversationID: UUID
    ) {
        InteractionCorePreferencesStore.clearGroupPreferences(
            conversationID: conversationID
        )
    }

    func imageInteractionPreferences(
        connectionID: UUID?
    ) -> ImageInteractionPreferences {
        InteractionCorePreferencesStore.imagePreferences(
            connectionID: connectionID
        )
    }

    func saveImageInteractionPreferences(
        _ preferences: ImageInteractionPreferences,
        connectionID: UUID?
    ) throws {
        try InteractionCorePreferencesStore.saveImagePreferences(
            preferences,
            connectionID: connectionID
        )
    }

    func resetImageInteractionPreferences(
        connectionID: UUID?
    ) {
        InteractionCorePreferencesStore.clearImagePreferences(
            connectionID: connectionID
        )
    }
}
