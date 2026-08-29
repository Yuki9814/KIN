package app.kin.shared.relationship

import app.kin.shared.model.RelationshipAction
import app.kin.shared.model.RelationshipStage
import app.kin.shared.model.RelationshipState
import kotlin.test.Test
import kotlin.test.assertEquals

class RelationshipStateMachineTest {
    @Test
    fun affinityTransitionsAreBoundedAndDeterministic() {
        val machine = RelationshipStateMachine()
        var state = RelationshipState("role-a")
        repeat(20) { state = machine.reduce(state, RelationshipAction.POSITIVE_INTERACTION, it.toLong()) }
        assertEquals(100, state.affinity)
        assertEquals(RelationshipStage.PARTNER, state.stage)
        state = machine.reduce(state, RelationshipAction.ARCHIVE, 99)
        assertEquals(RelationshipStage.ARCHIVED, state.stage)
        state = machine.reduce(state, RelationshipAction.RESTORE, 100)
        assertEquals(RelationshipStage.STRANGER, state.stage)
    }
}
