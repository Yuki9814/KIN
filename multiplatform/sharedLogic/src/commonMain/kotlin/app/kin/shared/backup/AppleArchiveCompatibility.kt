package app.kin.shared.backup

import app.kin.shared.crypto.Base64Codec
import app.kin.shared.crypto.toLowerHex
import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.AttachmentRef
import app.kin.shared.model.ChatAuthor
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.ProviderEndpointSanitizer
import app.kin.shared.model.RelationshipStage
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role
import app.kin.shared.platform.PlatformServices
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlin.math.roundToInt

/**
 * One-way compatibility reader for Apple's sanitized AyaneDataExport v4-v18 JSON.
 *
 * Apple stores a richer SwiftData graph (evidence, summaries, moments, world
 * profiles and scheduler records) than the first KMP release. This adapter
 * imports only the shared core graph: profiles, relationships, messages,
 * memory assertions, tombstoned memories and embedded event attachments. It
 * intentionally ignores unsupported Apple-only collections rather than
 * pretending that they are represented by KMP models. The v17
 * `moment_interactions.deleted_at` field therefore remains an Apple-side
 * sticky tombstone: it is not converted into a live KMP record, and the
 * adapter cannot resurrect it during import. Schema v18's optional
 * `relationships.manual_affinity_score` field is also ignored: KMP has no
 * manual-affinity slot, so this one-way adapter uses only `affinity_score`
 * (or the legacy tier) and does not claim to preserve the override.
 */
object AppleArchiveCompatibility {
    private const val minAppleSchema = 4
    private const val maxAppleSchema = 18
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        explicitNulls = false
    }

    fun decode(bytes: ByteArray): KINPortableArchivePayloadV1 {
        val root = json.parseToJsonElement(bytes.decodeToString()).jsonObject
        val appleSchema = root.requiredInt("schema_version")
        require(appleSchema in minAppleSchema..maxAppleSchema) {
            "Unsupported Apple AyaneDataExport schema: $appleSchema"
        }
        val fallbackMillis = root.string("exported_at")?.toAppleEpochMillis() ?: 0L
        val profileObjects = root.objectArray("profiles").ifEmpty {
            root.obj("persona")?.let(::listOf).orEmpty()
        }
        val roles = profileObjects.mapNotNull { profile ->
            val roleId = profile.id("role_id") ?: profile.id("id") ?: return@mapNotNull null
            val normalizedRoleId = normalizeId(roleId)
            if (isAyane(normalizedRoleId)) {
                null
            } else {
                Role(
                    id = normalizedRoleId,
                    displayName = profile.string("name")?.trim().orEmpty().ifBlank { "Imported role" },
                    systemPrompt = profile.string("prompt")?.trim().orEmpty().ifBlank { "保持真诚、温柔、清醒。" },
                    avatarKey = null,
                    isBuiltIn = false,
                    createdAtMillis = profile.string("created_at")?.toAppleEpochMillis() ?: fallbackMillis,
                    isArchived = profile.bool("archived") == true,
                )
            }
        }
        require(roles.map { it.id }.toSet().size == roles.size) { "Apple archive contains duplicate profiles" }
        val knownRoleIds = roles.mapTo(mutableSetOf()) { it.id }
        knownRoleIds += KinBuiltIns.ayaneRoleId

        val relationships = root.objectArray("relationships").map { relationship ->
            val roleId = relationship.requiredRoleId(knownRoleIds)
            val stateRaw = listOfNotNull(
                relationship.string("state_raw"),
                relationship.string("contact_membership_raw"),
            ).joinToString(" ").lowercase()
            val archived = stateRaw.contains("archiv") || stateRaw.contains("retir") ||
                relationship.string("retired_at") != null || stateRaw.contains("removed")
            // Schema v18 adds manual_affinity_score, but RelationshipState has
            // no field for it. Keep the automatic score/tier only; importing
            // the override here would falsely imply that an Apple round-trip
            // can preserve it.
            val affinity = (relationship.double("affinity_score")
                ?: relationship.int("affinity_tier")?.times(20.0)
                ?: 0.0).roundToInt().coerceIn(0, 100)
            RelationshipState(
                roleId = roleId,
                stage = if (archived) RelationshipStage.ARCHIVED else stageForAffinity(affinity),
                affinity = affinity,
                updatedAtMillis = relationship.string("updated_at")?.toAppleEpochMillis() ?: fallbackMillis,
            )
        }
        require(relationships.map { it.roleId }.toSet().size == relationships.size) {
            "Apple archive contains duplicate relationships"
        }

        val attachments = LinkedHashMap<String, PortableAttachmentV1>()
        val events = root.objectArray("events").mapIndexed { index, event ->
            val eventId = normalizeId(event.id("id") ?: "apple-event-$index")
            val roleId = event.roleId(knownRoleIds)
            val createdAtMillis = event.string("occurred_at")?.toAppleEpochMillis() ?: fallbackMillis
            val refs = buildList {
                event.embeddedAttachment(
                    eventId = eventId,
                    dataKey = "image_data",
                    fileName = event.string("file_name") ?: "$eventId-image",
                    mimeType = imageMime(event.string("file_type_identifier")),
                    createdAtMillis = createdAtMillis,
                    attachments = attachments,
                )?.let(::add)
                event.embeddedAttachment(
                    eventId = eventId,
                    dataKey = "file_data",
                    fileName = event.string("file_name") ?: "$eventId-file",
                    mimeType = fileMime(event.string("file_type_identifier")),
                    createdAtMillis = createdAtMillis,
                    attachments = attachments,
                )?.let(::add)
            }
            ChatEvent(
                id = eventId,
                roleId = roleId,
                conversationId = normalizeId(event.id("conversation_id") ?: "apple-conversation"),
                author = eventAuthor(event.string("role_raw") ?: event.string("role")),
                kind = ChatEventKind.MESSAGE,
                status = deliveryStatus(event.string("delivery_state_raw") ?: event.string("delivery_state")),
                body = event.string("content").orEmpty(),
                createdAtMillis = createdAtMillis,
                parentEventId = event.id("parent_event_id")?.let(::normalizeId),
                attachmentRefs = refs,
                errorCode = null,
                errorMessage = null,
            )
        }
        require(events.map { it.id }.toSet().size == events.size) { "Apple archive contains duplicate events" }

        val memoriesById = LinkedHashMap<String, MemoryRecord>()
        root.objectArray("memories").forEachIndexed { index, memory ->
            val id = normalizeId(memory.id("id") ?: "apple-memory-$index")
            require(memoriesById[id] == null) { "Apple archive contains duplicate memories" }
            val roleId = memory.roleId(knownRoleIds)
            val text = memoryText(memory)
            val state = listOfNotNull(memory.string("state_raw"), memory.string("state"))
                .joinToString(" ").lowercase()
            memoriesById[id] = MemoryRecord(
                id = id,
                roleId = roleId,
                text = text,
                confidence = (memory.double("confidence") ?: 1.0).toFloat().coerceIn(0f, 1f),
                createdAtMillis = memory.string("created_at")?.toAppleEpochMillis() ?: fallbackMillis,
                updatedAtMillis = memory.string("updated_at")?.toAppleEpochMillis()
                    ?: memory.string("created_at")?.toAppleEpochMillis()
                    ?: fallbackMillis,
                isTombstoned = state.contains("deleted") || state.contains("tombstone") ||
                    state.contains("retracted") || state.contains("superseded"),
            )
        }
        root.objectArray("tombstones").forEachIndexed { index, tombstone ->
            if (tombstone.string("entity_type")?.lowercase() != "memory") return@forEachIndexed
            val id = normalizeId(tombstone.id("entity_id") ?: "apple-tombstone-$index")
            val existing = memoriesById[id]
            if (existing != null) {
                memoriesById[id] = existing.copy(isTombstoned = true)
            } else {
                memoriesById[id] = MemoryRecord(
                    id = id,
                    roleId = tombstone.roleId(knownRoleIds),
                    text = "[已删除] ${tombstone.string("canonical_key") ?: tombstone.string("reason").orEmpty()}".trim(),
                    confidence = 0f,
                    createdAtMillis = tombstone.string("deleted_at")?.toAppleEpochMillis() ?: fallbackMillis,
                    updatedAtMillis = tombstone.string("deleted_at")?.toAppleEpochMillis() ?: fallbackMillis,
                    isTombstoned = true,
                )
            }
        }

        val settingsObject = root.obj("settings")?.obj("provider")
        val settings = AppSettings(
            // Apple sanitization intentionally blanks provider values. Keep
            // destination defaults when the source does not carry a usable
            // endpoint/model; never import credentials or OAuth state.
            endpoint = settingsObject?.string("base_url")?.let(ProviderEndpointSanitizer::sanitize)
                ?: AppSettings().endpoint,
            model = settingsObject?.string("model")?.takeIf { it.isNotBlank() } ?: AppSettings().model,
        )
        val payload = KINPortableArchivePayloadV1(
            exportId = "apple-v$appleSchema-${PlatformServices.crypto().sha256(bytes).toLowerHex()}",
            roles = roles,
            relationships = relationships,
            chatEvents = events,
            memories = memoriesById.values.toList(),
            settings = settings,
            attachments = attachments.values.toList(),
        )
        validateReferences(payload, knownRoleIds)
        return payload
    }

    private fun validateReferences(payload: KINPortableArchivePayloadV1, knownRoleIds: Set<String>) {
        require(payload.chatEvents.all { it.roleId in knownRoleIds }) { "Apple event references an unknown profile" }
        require(payload.memories.all { it.roleId in knownRoleIds }) { "Apple memory references an unknown profile" }
        require(payload.relationships.all { it.roleId in knownRoleIds }) { "Apple relationship references an unknown profile" }
    }

    private fun stageForAffinity(affinity: Int): RelationshipStage = when {
        affinity >= 90 -> RelationshipStage.PARTNER
        affinity >= 70 -> RelationshipStage.CLOSE
        affinity >= 40 -> RelationshipStage.FRIEND
        affinity >= 15 -> RelationshipStage.ACQUAINTANCE
        else -> RelationshipStage.STRANGER
    }

    private fun eventAuthor(role: String?): ChatAuthor = when (role?.lowercase()) {
        "assistant", "role", "companion", "ai" -> ChatAuthor.ROLE
        "system" -> ChatAuthor.SYSTEM
        else -> ChatAuthor.USER
    }

    private fun deliveryStatus(state: String?): ChatEventStatus = when (state?.lowercase()) {
        "pending", "streaming", "sending" -> ChatEventStatus.PENDING
        "failed", "error" -> ChatEventStatus.FAILED
        "cancelled", "canceled" -> ChatEventStatus.CANCELLED
        else -> ChatEventStatus.SENT
    }

    private fun memoryText(memory: JsonObject): String {
        val subject = memory.string("subject").orEmpty().trim()
        val predicate = memory.string("predicate").orEmpty().trim()
        val value = memory.string("value").orEmpty().trim()
        return listOf(subject, predicate, value).filter { it.isNotBlank() }.joinToString(" ")
            .ifBlank { memory.string("canonical_key").orEmpty().ifBlank { "Imported memory" } }
    }

    private fun JsonObject.embeddedAttachment(
        eventId: String,
        dataKey: String,
        fileName: String,
        mimeType: String,
        createdAtMillis: Long,
        attachments: MutableMap<String, PortableAttachmentV1>,
    ): AttachmentRef? {
        val encoded = string(dataKey)?.takeIf { it.isNotBlank() } ?: return null
        val bytes = Base64Codec.decode(encoded)
        if (bytes.isEmpty()) return null
        val hash = PlatformServices.crypto().sha256(bytes).toLowerHex()
        val id = "apple-attachment-$eventId-${dataKey.removeSuffix("_data")}"
        attachments.putIfAbsent(
            id,
            PortableAttachmentV1(
                metadata = AttachmentMetadata(
                    id = id,
                    fileName = fileName.substringAfterLast('/').substringAfterLast('\\').ifBlank { id },
                    mimeType = mimeType,
                    byteSize = bytes.size.toLong(),
                    sha256 = hash,
                    createdAtMillis = createdAtMillis,
                ),
                contentHex = bytes.toLowerHex(),
            ),
        )
        return AttachmentRef(id, hash)
    }

    private fun imageMime(identifier: String?): String = when {
        identifier.orEmpty().contains("png", ignoreCase = true) -> "image/png"
        identifier.orEmpty().contains("gif", ignoreCase = true) -> "image/gif"
        identifier.orEmpty().contains("webp", ignoreCase = true) -> "image/webp"
        else -> "image/jpeg"
    }

    private fun fileMime(identifier: String?): String = when {
        identifier.orEmpty().contains("pdf", ignoreCase = true) -> "application/pdf"
        identifier.orEmpty().contains("json", ignoreCase = true) -> "application/json"
        identifier.orEmpty().contains("text", ignoreCase = true) -> "text/plain"
        else -> "application/octet-stream"
    }

    private fun JsonObject.roleId(knownRoleIds: Set<String>): String {
        val raw = id("role_id") ?: id("sender_role_id")
        if (raw == null) return KinBuiltIns.ayaneRoleId
        val normalized = normalizeId(raw)
        require(normalized in knownRoleIds) { "Apple record references an unknown profile: $raw" }
        return normalized
    }

    private fun JsonObject.requiredRoleId(knownRoleIds: Set<String>): String {
        val raw = id("role_id") ?: error("Apple record is missing role_id")
        val normalized = normalizeId(raw)
        require(normalized in knownRoleIds) { "Apple record references an unknown profile: $raw" }
        return normalized
    }

    private fun normalizeId(value: String): String = KinBuiltIns.canonicalRoleId(value).let {
        if (isAyane(it)) KinBuiltIns.ayaneRoleId else it.lowercase()
    }

    private fun isAyane(value: String): Boolean = KinBuiltIns.isAyaneRoleId(value)

    private fun JsonObject.id(key: String): String? = string(key)?.takeIf { it.isNotBlank() }
    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
    private fun JsonObject.double(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.obj(key: String): JsonObject? = (this[key] as? JsonObject)
    private fun JsonObject.objectArray(key: String): List<JsonObject> =
        (this[key] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    private fun JsonObject.requiredInt(key: String): Int = int(key) ?: error("Apple archive is missing $key")
}

private val appleDatePattern = Regex(
    """^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$""",
)

private fun String.toAppleEpochMillis(): Long {
    val match = appleDatePattern.matchEntire(trim()) ?: return toLongOrNull() ?: 0L
    val year = match.groupValues[1].toInt()
    val month = match.groupValues[2].toInt()
    val day = match.groupValues[3].toInt()
    val hour = match.groupValues[4].toInt()
    val minute = match.groupValues[5].toInt()
    val second = match.groupValues[6].toInt()
    val fraction = match.groupValues[7].padEnd(3, '0').take(3).toLongOrNull() ?: 0L
    val offset = match.groupValues[8]
    val offsetMinutes = when {
        offset.isBlank() || offset == "Z" -> 0
        else -> {
            val sign = if (offset[0] == '-') -1 else 1
            val digits = offset.substring(1).replace(":", "")
            sign * (digits.substring(0, 2).toInt() * 60 + digits.substring(2, 4).toInt())
        }
    }
    val days = daysFromCivil(year, month, day)
    return (days * 86_400L + hour * 3_600L + minute * 60L + second) * 1_000L + fraction - offsetMinutes * 60_000L
}

/** Days since 1970-01-01, valid for the Gregorian dates used by ISO-8601. */
private fun daysFromCivil(yearValue: Int, month: Int, day: Int): Long {
    var year = yearValue.toLong()
    year -= if (month <= 2) 1 else 0
    val era = year / 400L
    val yearOfEra = year - era * 400L
    val monthValue = month.toLong()
    val dayOfYear = (153L * (monthValue + if (month > 2) -3 else 9) + 2) / 5 + day - 1
    val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}
