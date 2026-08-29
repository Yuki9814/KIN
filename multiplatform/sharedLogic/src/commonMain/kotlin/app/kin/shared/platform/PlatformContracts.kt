package app.kin.shared.platform

import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role

/** A secret is never represented by AppSettings or a portable archive. */
interface SecretStore {
    suspend fun read(name: String): ByteArray?
    suspend fun write(name: String, value: ByteArray)
    suspend fun delete(name: String)
}

interface ArchiveCryptoProvider {
    fun randomBytes(length: Int): ByteArray
    fun derivePbkdf2Sha256(password: ByteArray, salt: ByteArray, iterations: Int, keyBits: Int): ByteArray
    fun aesGcmEncrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray, aad: ByteArray): ByteArray
    fun aesGcmDecrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray, aad: ByteArray): ByteArray
    fun sha256(bytes: ByteArray): ByteArray
}

interface SqliteDriver : AutoCloseable {
    fun execute(sql: String, args: List<Any?> = emptyList())
    fun query(sql: String, args: List<Any?> = emptyList()): List<Map<String, Any?>>
    fun <T> transaction(block: () -> T): T
    override fun close()
}

interface SettingsStore {
    suspend fun load(): AppSettings
    suspend fun save(settings: AppSettings)
}

data class PickedFile(
    val fileName: String,
    val mimeType: String,
    val bytes: ByteArray,
)

interface PlatformFilePicker {
    suspend fun pickFile(allowedMimeTypes: List<String> = emptyList()): PickedFile?
    suspend fun saveFile(suggestedName: String, bytes: ByteArray): Boolean
}

interface AttachmentStore {
    suspend fun put(fileName: String, mimeType: String, bytes: ByteArray): AttachmentMetadata
    suspend fun read(metadata: AttachmentMetadata): ByteArray
    suspend fun delete(metadata: AttachmentMetadata)
    suspend fun pathFor(metadata: AttachmentMetadata): String
}

interface SseTransport {
    suspend fun stream(
        endpoint: String,
        bearerToken: String,
        jsonBody: String,
        onLine: suspend (String) -> Unit,
    )
}

/** Platform adapters are explicit; unsupported hosts throw instead of storing secrets in plaintext. */
expect object PlatformServices {
    fun initialize(context: Any? = null)
    fun crypto(): ArchiveCryptoProvider
    fun secretStore(): SecretStore
    fun sqliteDatabase(name: String = "kin.sqlite"): SqliteDriver
    fun settingsStore(): SettingsStore
    fun attachmentStore(): AttachmentStore
    fun filePicker(): PlatformFilePicker
    fun sseTransport(): SseTransport
}

data class PortableDataSnapshot(
    val roles: List<Role>,
    val relationships: List<RelationshipState>,
    val events: List<ChatEvent>,
    val memories: List<MemoryRecord>,
    val settings: AppSettings,
    val attachments: List<AttachmentMetadata>,
    val attachmentBytes: Map<String, ByteArray> = emptyMap(),
)
