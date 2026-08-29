package app.kin.shared.backup

import app.kin.shared.model.AppSettings
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.Role
import app.kin.shared.platform.PlatformServices
import app.kin.shared.storage.KinRepository
import app.kin.shared.model.RelationshipStage
import java.io.InputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ArchiveCompatibilityDesktopTest {
    @Test
    fun appleV16FixtureMapsOnlyTheSharedCore() {
        val payload = ArchivePayloadCodec.decodePortableOrApple(fixture("apple_ayane_data_export_v16.json"))

        assertEquals(listOf("11111111-1111-4111-8111-111111111111"), payload.roles.map { it.id })
        assertEquals(RelationshipStage.CLOSE, payload.relationships.single().stage)
        assertEquals(75, payload.relationships.single().affinity)
        assertEquals(listOf("hello", "hi"), payload.chatEvents.map { it.body })
        assertEquals("68656c6c6f", payload.attachments.single().contentHex)
        assertEquals("fixture.txt", payload.attachments.single().metadata.fileName)
        assertEquals("主人 喜欢 茶", payload.memories.single().text)
        assertTrue(payload.memories.single().isTombstoned)
        assertTrue(payload.settings.endpoint.startsWith("https://"))
        // evidence, moments and groups are Apple-only and have no KMP fields.
        assertTrue(payload.exportId.startsWith("apple-v16-"))
    }

    @Test
    fun encryptedAppleFixtureUsesTheSamePortableWireHeader() {
        val appleJson = fixture("apple_ayane_data_export_v16.json")
        val archive = ArchiveCrypto.encrypt(
            payload = appleJson,
            password = "fixture-password",
            salt = ByteArray(16) { it.toByte() },
            nonce = ByteArray(12) { (it + 16).toByte() },
        )

        val payload = ArchiveCrypto.decryptPayload(archive, "fixture-password")
        assertEquals(2, payload.chatEvents.size)
        assertEquals("11111111-1111-4111-8111-111111111111", payload.chatEvents.first().roleId)
    }

    @Test
    fun canonicalKmpPayloadFixtureIsStrictlyReadable() {
        val payload = ArchivePayloadCodec.decode(fixture("kin_portable_payload_v1.json"))

        assertEquals("fixture-kmp-v1", payload.exportId)
        assertEquals("fixture message", payload.chatEvents.single().body)
        assertEquals("fixture memory", payload.memories.single().text)
        assertEquals("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", payload.attachments.single().metadata.sha256)
    }

    @Test
    fun decryptedPortableArchiveDropsProviderCredentialsAndUrlDecorations() {
        val payload = KINPortableArchivePayloadV1(
            exportId = "endpoint-sanitization",
            roles = emptyList(),
            relationships = emptyList(),
            chatEvents = emptyList(),
            memories = emptyList(),
            settings = AppSettings(
                endpoint = "https://user:password@provider.example/path?token=top-secret#fragment",
            ),
        )

        val archive = ArchiveCrypto.encrypt(
            payload = ArchivePayloadCodec.encode(payload),
            password = "archive-password",
            salt = ByteArray(16) { it.toByte() },
            nonce = ByteArray(12) { (it + 16).toByte() },
        )
        val plaintext = ArchiveCrypto.decrypt(archive, "archive-password").decodeToString()
        val restored = ArchiveCrypto.decryptPayload(archive, "archive-password")

        assertEquals("https://provider.example/path", restored.settings.endpoint)
        assertFalse(plaintext.contains("user"))
        assertFalse(plaintext.contains("password"))
        assertFalse(plaintext.contains("token"))
        assertFalse(plaintext.contains("top-secret"))
        assertFalse(plaintext.contains("fragment"))
    }

    @Test
    fun trimmedLowercaseAyaneShadowIsRejectedAndRepositoryKeepsOneBuiltInRole() {
        val shadowId = " ${KinBuiltIns.ayaneRoleId.lowercase()} "
        val shadow = Role(
            id = shadowId,
            displayName = "伪造绫音",
            systemPrompt = "shadow",
            isBuiltIn = false,
        )
        val payload = KINPortableArchivePayloadV1(
            exportId = "shadow-role",
            roles = listOf(shadow),
            relationships = emptyList(),
            chatEvents = emptyList(),
            memories = emptyList(),
            settings = AppSettings(),
        )

        assertFailsWith<IllegalArgumentException> { ArchivePayloadCodec.encode(payload) }
        val raw = """
            {
              "format":"KINPortableArchiveV1",
              "schemaVersion":1,
              "exportId":"shadow-role-json",
              "roles":[{"id":"$shadowId","displayName":"伪造绫音","systemPrompt":"shadow","isBuiltIn":false}],
              "relationships":[],
              "chatEvents":[],
              "memories":[],
              "settings":{}
            }
        """.trimIndent()
        assertFailsWith<IllegalArgumentException> { ArchivePayloadCodec.decode(raw.encodeToByteArray()) }

        PlatformServices.initialize()
        val repository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        try {
            assertFailsWith<IllegalArgumentException> { repository.importPayload(payload, 1L) }
            val persisted = repository.appendEvent(
                ChatEvent(
                    roleId = shadowId,
                    conversationId = "ayane-boundary",
                    author = app.kin.shared.model.ChatAuthor.USER,
                    kind = ChatEventKind.MESSAGE,
                    status = ChatEventStatus.SENT,
                    body = "boundary",
                    createdAtMillis = 2L,
                ),
            )
            assertEquals(KinBuiltIns.ayaneRoleId, persisted.roleId)
            assertEquals(KinBuiltIns.ayaneRoleId, repository.events("ayane-boundary").single().roleId)
            assertEquals(1, repository.roles().count { KinBuiltIns.isAyaneRoleId(it.id) })
            assertTrue(repository.roles().single { KinBuiltIns.isAyaneRoleId(it.id) }.isBuiltIn)
        } finally {
            repository.close()
        }
    }

    private fun fixture(name: String): ByteArray =
        requireNotNull(javaClass.getResourceAsStream("/fixtures/$name")) {
            "Missing test fixture: $name"
        }.use(InputStream::readBytes)
}
