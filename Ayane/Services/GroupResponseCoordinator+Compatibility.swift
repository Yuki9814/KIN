import Foundation

extension GroupResponseCoordinator {
    /// Preserves the original array-shaped call site used by AppModel and older
    /// tests while the V2 planner keeps set semantics internally.
    func responseOrder(
        members: [Member],
        message: String,
        explicitlyMentionedRoleIDs: [UUID]
    ) -> [UUID] {
        responseOrder(
            members: members,
            message: message,
            explicitlyMentionedRoleIDs: Set(explicitlyMentionedRoleIDs)
        )
    }
}
