package app.kin.shared.backup

import app.kin.shared.crypto.Base64Codec
import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.ProviderEndpointSanitizer
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role
import app.kin.shared.platform.PlatformServices
import app.kin.shared.platform.PortableDataSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

@Serializable
data class PortableAttachmentV1(
    val metadata: AttachmentMetadata,
    /** Hex is intentionally used for deterministic cross-language JSON. */
    val contentHex: String? = null,
)

/** API credentials, OAuth tokens, device IDs and derived indexes have no fields here by design. */
@Serializable
data class KINPortableArchivePayloadV1(
    val format: String = KinBuiltIns.archiveFormat,
    val schemaVersion: Int = KinBuiltIns.schemaVersion,
    val exportId: String,
    val roles: List<Role>,
    val relationships: List<RelationshipState>,
    val chatEvents: List<ChatEvent>,
    val memories: List<MemoryRecord>,
    val settings: AppSettings,
    val attachments: List<PortableAttachmentV1> = emptyList(),
)

/** Normalize the identity and privacy-sensitive settings at every archive boundary. */
internal fun KINPortableArchivePayloadV1.canonicalizeForBoundary(): KINPortableArchivePayloadV1 = copy(
    roles = roles.map { role ->
        role.copy(id = KinBuiltIns.canonicalRoleId(role.id))
    },
    relationships = relationships.map { relationship ->
        relationship.copy(roleId = KinBuiltIns.canonicalRoleId(relationship.roleId))
    },
    chatEvents = chatEvents.map { event ->
        event.copy(roleId = KinBuiltIns.canonicalRoleId(event.roleId))
    },
    memories = memories.map { memory ->
        memory.copy(roleId = KinBuiltIns.canonicalRoleId(memory.roleId))
    },
    settings = settings.copy(
        endpoint = ProviderEndpointSanitizer.sanitize(settings.endpoint),
    ),
)

object ArchivePayloadCodec {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
        prettyPrint = false
    }

    fun encode(payload: KINPortableArchivePayloadV1): ByteArray {
        val canonical = payload.canonicalizeForBoundary()
        require(canonical.format == KinBuiltIns.archiveFormat) { "Unsupported archive format" }
        require(canonical.schemaVersion == KinBuiltIns.schemaVersion) { "Unsupported archive schema" }
        require(canonical.exportId.isNotBlank()) { "Archive export ID is missing" }
        validateRoleBoundary(canonical)
        return json.encodeToString(canonical).encodeToByteArray()
    }

    fun decode(bytes: ByteArray): KINPortableArchivePayloadV1 {
        val payload = json.decodeFromString<KINPortableArchivePayloadV1>(bytes.decodeToString())
            .canonicalizeForBoundary()
        require(payload.format == KinBuiltIns.archiveFormat) { "Unsupported archive format" }
        require(payload.schemaVersion == KinBuiltIns.schemaVersion) { "Unsupported archive schema" }
        require(payload.exportId.isNotBlank()) { "Archive export ID is missing" }
        validateRoleBoundary(payload)
        return payload
    }

    /**
     * Reads the KMP payload and sanitized Apple AyaneDataExport v4-v18
     * payload. Apple-only records are intentionally converted/ignored by the
     * explicit compatibility adapter; KMP export remains the canonical v1
     * wire schema and is not claimed to be a byte-for-byte Apple export.
     */
    fun decodePortableOrApple(bytes: ByteArray): KINPortableArchivePayloadV1 = try {
        decode(bytes)
    } catch (_: Throwable) {
        AppleArchiveCompatibility.decode(bytes).canonicalizeForBoundary()
    }

    fun fromSnapshot(snapshot: PortableDataSnapshot, exportId: String): KINPortableArchivePayloadV1 {
        val attachmentById = snapshot.attachmentBytes
        return KINPortableArchivePayloadV1(
            exportId = exportId,
            roles = snapshot.roles.filterNot { it.isBuiltIn || KinBuiltIns.isAyaneRoleId(it.id) },
            relationships = snapshot.relationships.filterNot { KinBuiltIns.isAyaneRoleId(it.roleId) },
            chatEvents = snapshot.events,
            memories = snapshot.memories,
            settings = snapshot.settings,
            attachments = snapshot.attachments.map { metadata ->
                PortableAttachmentV1(
                    metadata = metadata,
                    contentHex = attachmentById[metadata.id]?.toLowerHex(),
                )
            },
        ).canonicalizeForBoundary()
    }

    private fun validateRoleBoundary(payload: KINPortableArchivePayloadV1) {
        require(payload.roles.map { it.id }.toSet().size == payload.roles.size) {
            "Archive contains duplicate role IDs"
        }
        require(payload.roles.none { KinBuiltIns.isAyaneRoleId(it.id) && !it.isBuiltIn }) {
            "The built-in Ayane role cannot be shadowed"
        }
    }
}

object ArchiveCrypto {
    const val iterations: Int = 600_000
    const val saltLength: Int = 16
    const val nonceLength: Int = 12
    private const val keyBits: Int = 256
    private val magic = KinBuiltIns.archiveFormat.encodeToByteArray()

    fun encrypt(payload: ByteArray, password: String): ByteArray = encrypt(
        payload = payload,
        password = password,
        salt = PlatformServices.crypto().randomBytes(saltLength),
        nonce = PlatformServices.crypto().randomBytes(nonceLength),
    )

    fun encrypt(payload: ByteArray, password: String, salt: ByteArray, nonce: ByteArray): ByteArray {
        require(password.isNotEmpty()) { "Backup password must not be empty" }
        require(salt.size == saltLength) { "Salt must be 16 bytes" }
        require(nonce.size == nonceLength) { "Nonce must be 12 bytes" }
        val header = header(salt, nonce)
        val key = PlatformServices.crypto().derivePbkdf2Sha256(password.encodeToByteArray(), salt, iterations, keyBits)
        val ciphertext = PlatformServices.crypto().aesGcmEncrypt(key, nonce, payload, header)
        return header + ciphertext
    }

    fun decrypt(archive: ByteArray, password: String): ByteArray {
        require(password.isNotEmpty()) { "Backup password must not be empty" }
        require(archive.size >= magic.size + 1 + saltLength + nonceLength + 16) { "Archive is truncated" }
        require(archive.copyOfRange(0, magic.size).contentEquals(magic)) { "Unsupported archive magic" }
        val versionOffset = magic.size
        require(archive[versionOffset].toInt() == 1) { "Unsupported archive version" }
        val saltStart = versionOffset + 1
        val salt = archive.copyOfRange(saltStart, saltStart + saltLength)
        val nonceStart = saltStart + saltLength
        val nonce = archive.copyOfRange(nonceStart, nonceStart + nonceLength)
        val header = archive.copyOfRange(0, nonceStart + nonceLength)
        val ciphertext = archive.copyOfRange(header.size, archive.size)
        val key = PlatformServices.crypto().derivePbkdf2Sha256(password.encodeToByteArray(), salt, iterations, keyBits)
        return PlatformServices.crypto().aesGcmDecrypt(key, nonce, ciphertext, header)
    }

    fun encryptPayload(payload: KINPortableArchivePayloadV1, password: String): ByteArray =
        encrypt(ArchivePayloadCodec.encode(payload), password)

    fun decryptPayload(archive: ByteArray, password: String): KINPortableArchivePayloadV1 =
        ArchivePayloadCodec.decodePortableOrApple(decrypt(archive, password))

    fun encodeForFixture(bytes: ByteArray): String = Base64Codec.encode(bytes)

    private fun header(salt: ByteArray, nonce: ByteArray): ByteArray =
        magic + byteArrayOf(1) + salt + nonce
}

private fun ByteArray.toLowerHex(): String {
    val digits = "0123456789abcdef"
    return buildString(size * 2) {
        for (byte in this@toLowerHex) {
            val value = byte.toInt() and 0xff
            append(digits[value ushr 4])
            append(digits[value and 0x0f])
        }
    }
}
