package app.kin.shared.model

import kotlinx.serialization.Serializable
import kotlin.math.roundToInt
import kotlin.random.Random

/** Stable identifiers and product boundaries shared with the Apple legacy store. */
object KinBuiltIns {
    const val ayaneRoleId: String = "8D5DFB45-198D-4B74-B1F1-4C9C7A8248A1"
    const val ayaneDisplayName: String = "绫音"
    const val archiveFormat: String = "KINPortableArchiveV1"
    const val schemaVersion: Int = 1
    const val defaultProviderEndpoint: String = "https://api.openai.com/v1/chat/completions"

    /**
     * Role IDs are opaque except for the one stable built-in identity. Keep
     * custom IDs intact, while making whitespace/case variants of Ayane
     * resolve to the one canonical value at every storage/wire boundary.
     */
    fun canonicalRoleId(value: String): String = value.trim().let { trimmed ->
        if (trimmed.equals(ayaneRoleId, ignoreCase = true)) ayaneRoleId else trimmed
    }

    fun isAyaneRoleId(value: String): Boolean = canonicalRoleId(value) == ayaneRoleId
}

/**
 * Provider endpoints are display settings in a portable archive, never a
 * credential transport. Only an HTTPS authority and path survive export;
 * userinfo, query, fragment and malformed/unsafe URL components fall back to
 * the neutral default endpoint.
 */
object ProviderEndpointSanitizer {
    fun sanitize(endpoint: String): String {
        val candidate = endpoint.trim()
        if (candidate.isEmpty() || candidate.any { it.isISOControl() }) return fallback()

        val schemeSeparator = candidate.indexOf("://")
        if (schemeSeparator <= 0 || !candidate.substring(0, schemeSeparator).equals("https", ignoreCase = true)) {
            return fallback()
        }

        val authorityAndPathStart = schemeSeparator + 3
        val firstQuery = candidate.indexOf('?', authorityAndPathStart)
        val firstFragment = candidate.indexOf('#', authorityAndPathStart)
        val suffixStart = listOf(firstQuery, firstFragment)
            .filter { it >= 0 }
            .minOrNull() ?: candidate.length
        val authorityAndPath = candidate.substring(authorityAndPathStart, suffixStart)
        val pathStart = authorityAndPath.indexOf('/')
        val rawAuthority = if (pathStart >= 0) authorityAndPath.substring(0, pathStart) else authorityAndPath
        val path = if (pathStart >= 0) authorityAndPath.substring(pathStart) else ""

        // A backslash can be interpreted as a path separator by URL clients;
        // reject it instead of allowing an alternate authority to be hidden.
        if (rawAuthority.isEmpty() || rawAuthority.any { it.isWhitespace() || it == '\\' || it == '?' || it == '#' }) {
            return fallback()
        }

        // Everything before the last @ is URL userinfo. It is intentionally
        // discarded, including passwords and percent-encoded credential text.
        val hostAndPort = rawAuthority.substringAfterLast('@')
        if (hostAndPort.isEmpty() || hostAndPort.contains('@')) return fallback()

        val authority = parseAuthority(hostAndPort) ?: return fallback()
        if (path.any { it.isWhitespace() || it.isISOControl() || it == '\\' || it == '?' || it == '#' }) return fallback()
        return "https://${authority.host}${authority.port?.let { ":$it" }.orEmpty()}$path"
    }

    private fun fallback(): String = KinBuiltIns.defaultProviderEndpoint

    private data class ParsedAuthority(val host: String, val port: Int?)

    private fun parseAuthority(value: String): ParsedAuthority? {
        if (value.startsWith('[')) {
            val closingBracket = value.indexOf(']')
            if (closingBracket <= 1) return null
            val host = value.substring(1, closingBracket)
            val suffix = value.substring(closingBracket + 1)
            if (host.any { it.isWhitespace() || it.isISOControl() || it == '[' || it == ']' || it == '%' }) return null
            val port = when {
                suffix.isEmpty() -> null
                suffix.startsWith(':') -> parsePort(suffix.substring(1))
                else -> return null
            }
            return ParsedAuthority("[$host]", port)
        }

        // Unbracketed IPv6 and ambiguous colon-containing authorities are not
        // safe to reconstruct; callers can retry with a neutral default.
        if (value.count { it == ':' } > 1) return null
        val colon = value.indexOf(':')
        val host = if (colon >= 0) value.substring(0, colon) else value
        if (host.isEmpty() || host.any { it.isWhitespace() || it.isISOControl() || it in "/?#@\\%[]" }) return null
        val port = if (colon >= 0) parsePort(value.substring(colon + 1)) else null
        return ParsedAuthority(host, port)
    }

    private fun parsePort(value: String): Int? = value
        .takeIf { it.isNotEmpty() && it.all(Char::isDigit) }
        ?.toIntOrNull()
        ?.takeIf { it in 1..65_535 }
}

object Identifiers {
    fun newId(prefix: String): String = "$prefix-${Random.nextLong().toULong().toString(16)}-${Random.nextLong().toULong().toString(16)}"
}

@Serializable
data class Role(
    val id: String,
    val displayName: String,
    val systemPrompt: String,
    val avatarKey: String? = null,
    val isBuiltIn: Boolean = false,
    val createdAtMillis: Long = 0L,
    val isArchived: Boolean = false,
)

fun ayaneRole(): Role = Role(
    id = KinBuiltIns.ayaneRoleId,
    displayName = KinBuiltIns.ayaneDisplayName,
    systemPrompt = "你是绫音。保持真诚、温柔、清醒，尊重用户的边界与选择。",
    avatarKey = "ayane",
    isBuiltIn = true,
)

@Serializable
enum class RelationshipStage {
    STRANGER,
    ACQUAINTANCE,
    FRIEND,
    CLOSE,
    PARTNER,
    ARCHIVED,
}

@Serializable
data class RelationshipState(
    val roleId: String,
    val stage: RelationshipStage = RelationshipStage.STRANGER,
    val affinity: Int = 0,
    val updatedAtMillis: Long = 0L,
) {
    init {
        require(affinity in 0..100) { "affinity must be between 0 and 100" }
    }
}

@Serializable
enum class RelationshipAction {
    POSITIVE_INTERACTION,
    NEGATIVE_INTERACTION,
    ARCHIVE,
    RESTORE,
}

@Serializable
enum class ChatAuthor {
    USER,
    ROLE,
    SYSTEM,
}

@Serializable
enum class ChatEventKind {
    MESSAGE,
    REQUEST_STARTED,
    DELTA,
    COMPLETED,
    FAILED,
    CANCELLED,
    RETRY_REQUESTED,
}

@Serializable
data class AttachmentRef(
    val id: String,
    val sha256: String,
)

@Serializable
data class ChatEvent(
    val id: String = Identifiers.newId("event"),
    val roleId: String,
    val conversationId: String,
    val author: ChatAuthor,
    val kind: ChatEventKind,
    val status: ChatEventStatus = ChatEventStatus.PERSISTED,
    val body: String = "",
    val createdAtMillis: Long,
    val sequence: Long = 0L,
    val parentEventId: String? = null,
    val attachmentRefs: List<AttachmentRef> = emptyList(),
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

@Serializable
enum class ChatEventStatus {
    PERSISTED,
    PENDING,
    SENT,
    FAILED,
    CANCELLED,
}

@Serializable
data class MemoryRecord(
    val id: String = Identifiers.newId("memory"),
    val roleId: String,
    val text: String,
    val confidence: Float = 1f,
    val createdAtMillis: Long,
    val updatedAtMillis: Long = createdAtMillis,
    val isTombstoned: Boolean = false,
)

@Serializable
data class AttachmentMetadata(
    val id: String = Identifiers.newId("attachment"),
    val fileName: String,
    val mimeType: String,
    val byteSize: Long,
    val sha256: String,
    val createdAtMillis: Long,
)

@Serializable
data class AppSettings(
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val endpoint: String = KinBuiltIns.defaultProviderEndpoint,
    val model: String = "gpt-4o-mini",
    val sendOnEnter: Boolean = true,
)

@Serializable
enum class ThemeMode {
    SYSTEM,
    LIGHT,
    DARK,
}

/** Credentials are deliberately not part of this model or any portable payload. */
data class ProviderCredentialRef(val secretName: String = "openai-compatible-api-key")

fun RelationshipState.next(action: RelationshipAction, nowMillis: Long): RelationshipState {
    if (action == RelationshipAction.ARCHIVE) {
        return copy(stage = RelationshipStage.ARCHIVED, updatedAtMillis = nowMillis)
    }
    if (action == RelationshipAction.RESTORE) {
        return copy(stage = stage.takeUnless { it == RelationshipStage.ARCHIVED } ?: RelationshipStage.STRANGER, updatedAtMillis = nowMillis)
    }
    val delta = if (action == RelationshipAction.POSITIVE_INTERACTION) 5 else -8
    val nextAffinity = (affinity + delta).coerceIn(0, 100)
    val nextStage = when {
        nextAffinity >= 90 -> RelationshipStage.PARTNER
        nextAffinity >= 70 -> RelationshipStage.CLOSE
        nextAffinity >= 40 -> RelationshipStage.FRIEND
        nextAffinity >= 15 -> RelationshipStage.ACQUAINTANCE
        else -> RelationshipStage.STRANGER
    }
    return copy(affinity = nextAffinity, stage = nextStage, updatedAtMillis = nowMillis)
}

fun RelationshipStage.promptLabel(): String = when (this) {
    RelationshipStage.STRANGER -> "初识"
    RelationshipStage.ACQUAINTANCE -> "熟悉"
    RelationshipStage.FRIEND -> "朋友"
    RelationshipStage.CLOSE -> "亲近"
    RelationshipStage.PARTNER -> "伴侣"
    RelationshipStage.ARCHIVED -> "已归档"
}

fun Float.normalizedConfidence(): Int = (coerceIn(0f, 1f) * 100f).roundToInt()
