package app.kin.shared.backup

import app.kin.shared.model.RelationshipStage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppleArchiveCompatibilityTest {
    @Test
    fun appleV17MomentTombstoneIsAcceptedWithoutResurrection() {
        val payload = ArchivePayloadCodec.decodePortableOrApple(appleV17Fixture())

        assertTrue(payload.exportId.startsWith("apple-v17-"))
        assertEquals("core message", payload.chatEvents.single().body)
        assertEquals(1, payload.roles.size)
        assertFalse(payload.chatEvents.any { it.body.contains("deleted interaction") })
        assertEquals(emptyList(), payload.memories)
    }

    @Test
    fun appleV18ManualAffinityIsAcceptedAndSafelyIgnored() {
        val payload = ArchivePayloadCodec.decodePortableOrApple(appleV18Fixture())

        assertTrue(payload.exportId.startsWith("apple-v18-"))
        assertEquals(75, payload.relationships.single().affinity)
        assertEquals(RelationshipStage.CLOSE, payload.relationships.single().stage)
        assertFalse(ArchivePayloadCodec.encode(payload).decodeToString().contains("manual_affinity_score"))
    }

    @Test
    fun unsupportedFutureAppleSchemaFailsClosed() {
        val future = appleV18Fixture().decodeToString()
            .replace("\"schema_version\": 18", "\"schema_version\": 19")

        assertFailsWith<IllegalArgumentException> {
            AppleArchiveCompatibility.decode(future.encodeToByteArray())
        }
    }

    private fun appleV18Fixture(): ByteArray = appleV17Fixture().decodeToString()
        .replace("\"schema_version\": 17", "\"schema_version\": 18")
        .replace(
            "\"relationships\": [],",
            "\"relationships\": [{\"role_id\": \"11111111-1111-4111-8111-111111111111\", " +
                "\"state_raw\": \"accepted\", \"affinity_score\": 75.0, " +
                "\"manual_affinity_score\": 42.0}],",
        )
        .encodeToByteArray()

    private fun appleV17Fixture(): ByteArray = """
        {
          "schema_version": 17,
          "exported_at": "2026-08-30T00:00:00Z",
          "profiles": [
            {
              "id": "11111111-1111-4111-8111-111111111111",
              "role_id": "11111111-1111-4111-8111-111111111111",
              "name": "测试角色",
              "prompt": "保持清醒。"
            }
          ],
          "relationships": [],
          "events": [
            {
              "id": "22222222-2222-4222-8222-222222222222",
              "role_id": "11111111-1111-4111-8111-111111111111",
              "conversation_id": "33333333-3333-4333-8333-333333333333",
              "role": "user",
              "content": "core message",
              "occurred_at": "2026-08-30T00:00:01Z"
            }
          ],
          "memories": [],
          "tombstones": [],
          "moment_posts": [
            {
              "id": "44444444-4444-4444-8444-444444444444",
              "body": "moment post"
            }
          ],
          "moment_interactions": [
            {
              "id": "55555555-5555-4555-8555-555555555555",
              "post_id": "44444444-4444-4444-8444-444444444444",
              "kind": "comment",
              "actor_kind": "user",
              "body": "deleted interaction",
              "created_at": "2026-08-30T00:00:02Z",
              "updated_at": "2026-08-30T00:00:03Z",
              "deleted_at": "2026-08-30T00:00:04Z"
            }
          ],
          "settings": {
            "provider": {
              "base_url": "",
              "model": ""
            }
          }
        }
    """.trimIndent().encodeToByteArray()
}
