package app.kin.shared.memory

import app.kin.shared.model.ChatAuthor
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role
import app.kin.shared.model.promptLabel

data class PromptMessage(val role: String, val content: String)

/**
 * Builds a provider-neutral prompt from one role's history and memories only.
 * Cross-role data is filtered before formatting, not merely hidden in the UI.
 */
class PromptAssembler {
    fun assemble(
        role: Role,
        relationship: RelationshipState,
        events: List<ChatEvent>,
        memories: List<MemoryRecord>,
        maxHistory: Int = 40,
        maxMemories: Int = 30,
    ): List<PromptMessage> {
        // A completed assistant response is the canonical durable response;
        // DELTA events remain append-only audit data and are not duplicated in
        // the provider prompt.
        val roleEvents = events.filter {
            it.roleId == role.id &&
                it.kind in setOf(ChatEventKind.MESSAGE, ChatEventKind.COMPLETED) &&
                it.body.isNotBlank()
        }
        val roleMemories = memories.filter { it.roleId == role.id && !it.isTombstoned }
        val system = buildString {
            append(role.systemPrompt.trim())
            append("\n关系阶段：")
            append(relationship.stage.promptLabel())
            append("（好感度 ")
            append(relationship.affinity)
            append("/100）")
            if (roleMemories.isNotEmpty()) {
                append("\n仅可使用以下属于本角色的长期记忆：")
                roleMemories.takeLast(maxMemories).forEach { append("\n- ").append(it.text.trim()) }
            }
        }
        val messages = ArrayList<PromptMessage>(maxHistory + 1)
        messages += PromptMessage("system", system)
        roleEvents.takeLast(maxHistory).forEach { event ->
            val author = when (event.author) {
                ChatAuthor.USER -> "user"
                ChatAuthor.ROLE -> "assistant"
                ChatAuthor.SYSTEM -> "system"
            }
            messages += PromptMessage(author, event.body)
        }
        return messages
    }
}
