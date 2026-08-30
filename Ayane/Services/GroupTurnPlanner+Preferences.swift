import Foundation

struct PersistedGroupTurnPlan: Equatable, Sendable {
    let plan: GroupTurnPlan
    let promptAssemblyMode: GroupPromptAssemblyMode
    let allowsSensitiveMemory: Bool
}

extension GroupTurnPlanner {
    /// Plans a normal automatic group turn using the conversation-scoped user
    /// defaults. The existing value-only planner remains the source of truth;
    /// this adapter only removes hard-coded strategy and responder limits from
    /// future AppModel/UI call sites.
    func plan(
        members: [GroupTurnMember],
        message: String,
        conversationID: UUID,
        lastSpeakerRoleID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) -> PersistedGroupTurnPlan {
        let preferences = InteractionCorePreferencesStore.groupPreferences(
            conversationID: conversationID,
            defaults: defaults
        )
        let plan = plan(
            members: members,
            message: message,
            context: GroupTurnPlanningContext(
                strategy: preferences.turnStrategy,
                maxAutomaticResponders: preferences.maximumAutomaticResponders,
                lastSpeakerRoleID: lastSpeakerRoleID
            )
        )
        return PersistedGroupTurnPlan(
            plan: plan,
            promptAssemblyMode: preferences.promptAssemblyMode,
            allowsSensitiveMemory: preferences.allowSensitiveMemory
        )
    }
}
