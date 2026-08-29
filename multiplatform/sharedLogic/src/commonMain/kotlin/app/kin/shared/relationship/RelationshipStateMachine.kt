package app.kin.shared.relationship

import app.kin.shared.model.RelationshipAction
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.next

class RelationshipStateMachine {
    fun reduce(current: RelationshipState, action: RelationshipAction, nowMillis: Long): RelationshipState =
        current.next(action, nowMillis)
}
