import Foundation

extension GroupResponseCoordinator {
    /// Preserves the original array-shaped call site used by AppModel and older
    /// tests while the V2 planner keeps set semantics internally. Explicit role
    /// IDs come from the UI's resolved mention tokens, so they take precedence
    /// over ambiguous display-name parsing (for example two members named 绫音).
    func responseOrder(
        members: [Member],
        message: String,
        explicitlyMentionedRoleIDs: [UUID]
    ) -> [UUID] {
        let knownRoleIDs = Set(members.map(\.roleID))
        let explicit = Set(explicitlyMentionedRoleIDs).intersection(knownRoleIDs)
        if !explicit.isEmpty {
            return responseOrder(
                members: members,
                mentionedRoleIDs: explicit
            )
        }
        return responseOrder(
            members: members,
            message: message,
            explicitlyMentionedRoleIDs: Set<UUID>()
        )
    }
}
