package app.kin.shared.memory

import app.kin.shared.model.ChatAuthor
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PromptAssemblerTest {
    @Test
    fun onlySelectedRoleHistoryAndMemoryEnterPrompt() {
        val role = Role("role-a", "A", "system-a")
        val events = listOf(
            ChatEvent("a", "role-a", "conversation", ChatAuthor.USER, ChatEventKind.MESSAGE, ChatEventStatus.SENT, "belongs to A", 1),
            ChatEvent("b", "role-b", "conversation", ChatAuthor.USER, ChatEventKind.MESSAGE, ChatEventStatus.SENT, "secret from B", 2),
        )
        val memories = listOf(
            MemoryRecord("ma", "role-a", "memory A", createdAtMillis = 1),
            MemoryRecord("mb", "role-b", "memory B", createdAtMillis = 1),
        )
        val prompt = PromptAssembler().assemble(role, RelationshipState("role-a"), events, memories)
            .joinToString("\n") { it.content }
        assertTrue("belongs to A" in prompt)
        assertTrue("memory A" in prompt)
        assertFalse("secret from B" in prompt)
        assertFalse("memory B" in prompt)
    }
}
