package app.kin.shared.storage

import app.kin.shared.model.ChatAuthor
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.Role
import app.kin.shared.platform.PlatformServices
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class KinRepositoryDesktopTest {
    @Test
    fun builtInRoleIsStableAndChatEventsAreAppendOnly() {
        PlatformServices.initialize()
        val repository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val role = repository.createRole("测试角色", "只用于测试", 1)
        repository.appendEvent(ChatEvent(roleId = role.id, conversationId = "c", author = ChatAuthor.USER, kind = ChatEventKind.MESSAGE, status = ChatEventStatus.SENT, body = "hi", createdAtMillis = 2))
        repository.appendEvent(ChatEvent(roleId = role.id, conversationId = "c", author = ChatAuthor.ROLE, kind = ChatEventKind.COMPLETED, status = ChatEventStatus.SENT, body = "hello", createdAtMillis = 3))
        assertEquals(2, repository.events("c").size)
        assertEquals(KinBuiltIns.ayaneRoleId, repository.roles().first().id)
        repository.close()
    }

    @Test
    fun duplicateArchiveImportRollsBack() {
        PlatformServices.initialize()
        val repository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val role = Role("role-import", "Imported", "prompt", createdAtMillis = 1)
        val payload = app.kin.shared.backup.KINPortableArchivePayloadV1(
            exportId = "export-test",
            roles = listOf(role),
            relationships = emptyList(),
            chatEvents = listOf(ChatEvent("event-import", role.id, "c", ChatAuthor.USER, ChatEventKind.MESSAGE, ChatEventStatus.SENT, "body", 2)),
            memories = listOf(MemoryRecord("memory-import", role.id, "memory", createdAtMillis = 2)),
            settings = repository.settings(),
        )
        assertEquals(3, repository.importPayload(payload, 3))
        assertFailsWith<DuplicateImportException> { repository.importPayload(payload, 4) }
        assertEquals(1, repository.roles().count { it.id == role.id })
        assertEquals(1, repository.memories(role.id).size)
        repository.close()
    }
}
