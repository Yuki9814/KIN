package app.kin.shared.platform

import com.sun.jna.platform.win32.Crypt32Util
import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.Identifiers
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.request.header
import io.ktor.client.request.preparePost
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.utils.io.readUTF8Line
import java.awt.EventQueue
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.security.SecureRandom
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.sql.Types
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import javax.swing.JFileChooser
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

actual object PlatformServices {
    private var initialized = false

    actual fun initialize(context: Any?) {
        initialized = true
    }

    actual fun crypto(): ArchiveCryptoProvider = DesktopCryptoProvider

    actual fun secretStore(): SecretStore {
        check(isWindows()) { "Windows DPAPI SecretStore is unavailable on this host; refusing plaintext fallback" }
        return WindowsDpapiSecretStore()
    }

    actual fun sqliteDatabase(name: String): SqliteDriver = JdbcSqliteDriver(name)
    actual fun settingsStore(): SettingsStore = DesktopSettingsStore()
    actual fun attachmentStore(): AttachmentStore = DesktopAttachmentStore()
    actual fun filePicker(): PlatformFilePicker = SwingFilePicker()
    actual fun sseTransport(): SseTransport = DesktopSseTransport

    private fun isWindows(): Boolean = System.getProperty("os.name").contains("Windows", ignoreCase = true)
}

private object DesktopCryptoProvider : ArchiveCryptoProvider {
    override fun randomBytes(length: Int): ByteArray = ByteArray(length).also(SecureRandom()::nextBytes)

    override fun derivePbkdf2Sha256(password: ByteArray, salt: ByteArray, iterations: Int, keyBits: Int): ByteArray {
        val spec = PBEKeySpec(password.decodeToString().toCharArray(), salt, iterations, keyBits)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    override fun aesGcmEncrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray, aad: ByteArray): ByteArray =
        aesGcm(Cipher.ENCRYPT_MODE, key, nonce, plaintext, aad)

    override fun aesGcmDecrypt(key: ByteArray, nonce: ByteArray, ciphertext: ByteArray, aad: ByteArray): ByteArray =
        aesGcm(Cipher.DECRYPT_MODE, key, nonce, ciphertext, aad)

    override fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

    private fun aesGcm(mode: Int, key: ByteArray, nonce: ByteArray, input: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        return cipher.doFinal(input)
    }
}

/** Windows-only DPAPI storage. There is intentionally no non-Windows file fallback. */
private class WindowsDpapiSecretStore : SecretStore {
    private val root: Path = Path.of(
        System.getenv("APPDATA")?.takeIf { it.isNotBlank() } ?: System.getProperty("user.home"),
        "KIN",
        "secrets",
    ).also { Files.createDirectories(it) }

    override suspend fun read(name: String): ByteArray? {
        val file = file(name)
        if (!Files.exists(file)) return null
        return Crypt32Util.cryptUnprotectData(Files.readAllBytes(file))
    }

    override suspend fun write(name: String, value: ByteArray) {
        val destination = file(name)
        val temporary = destination.resolveSibling(".${destination.fileName}.tmp-${Thread.currentThread().id}")
        Files.write(temporary, Crypt32Util.cryptProtectData(value))
        try {
            Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: Exception) {
            Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    override suspend fun delete(name: String) {
        Files.deleteIfExists(file(name))
    }

    private fun file(name: String): Path {
        val safe = name.replace(Regex("[^A-Za-z0-9_.-]"), "_").take(80).ifBlank { "secret" }
        return root.resolve("$safe.dpapi")
    }
}

private class JdbcSqliteDriver(name: String) : SqliteDriver {
    private val connection: Connection

    init {
        Class.forName("org.sqlite.JDBC")
        val base = System.getenv("LOCALAPPDATA")?.takeIf { it.isNotBlank() }
            ?: System.getenv("APPDATA")?.takeIf { it.isNotBlank() }
            ?: System.getProperty("user.home")
        val root = Path.of(base, "KIN").also { Files.createDirectories(it) }
        connection = if (name == ":memory:") {
            DriverManager.getConnection("jdbc:sqlite::memory:")
        } else {
            DriverManager.getConnection("jdbc:sqlite:${root.resolve(name).normalize()}")
        }
        connection.autoCommit = true
    }

    override fun execute(sql: String, args: List<Any?>) {
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            statement.execute()
        }
    }

    override fun query(sql: String, args: List<Any?>): List<Map<String, Any?>> {
        connection.prepareStatement(sql).use { statement ->
            bind(statement, args)
            statement.executeQuery().use { result ->
                val metadata = result.metaData
                val rows = ArrayList<Map<String, Any?>>()
                while (result.next()) {
                    val row = LinkedHashMap<String, Any?>(metadata.columnCount)
                    for (index in 1..metadata.columnCount) {
                        row[metadata.getColumnLabel(index)] = result.getObject(index)
                    }
                    rows += row
                }
                return rows
            }
        }
    }

    override fun <T> transaction(block: () -> T): T {
        val previous = connection.autoCommit
        connection.autoCommit = false
        return try {
            block().also { connection.commit() }
        } catch (failure: Throwable) {
            runCatching { connection.rollback() }
            throw failure
        } finally {
            connection.autoCommit = previous
        }
    }

    override fun close() {
        connection.close()
    }

    private fun bind(statement: java.sql.PreparedStatement, args: List<Any?>) {
        args.forEachIndexed { index, value ->
            when (value) {
                null -> statement.setNull(index + 1, Types.NULL)
                is ByteArray -> statement.setBytes(index + 1, value)
                is Int -> statement.setInt(index + 1, value)
                is Long -> statement.setLong(index + 1, value)
                is Double -> statement.setDouble(index + 1, value)
                else -> statement.setString(index + 1, value.toString())
            }
        }
    }
}

private class DesktopSettingsStore : SettingsStore {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }
    private val file: Path = dataRoot().resolve("settings.json").also { Files.createDirectories(it.parent) }

    override suspend fun load(): AppSettings = if (Files.exists(file)) {
        json.decodeFromString(Files.readString(file))
    } else {
        AppSettings()
    }

    override suspend fun save(settings: AppSettings) {
        val temporary = file.resolveSibling(".settings.tmp-${Thread.currentThread().id}")
        Files.writeString(temporary, json.encodeToString(settings))
        Files.move(temporary, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }
}

private class DesktopAttachmentStore : AttachmentStore {
    private val root: Path = dataRoot().resolve("attachments").also { Files.createDirectories(it) }

    override suspend fun put(fileName: String, mimeType: String, bytes: ByteArray): AttachmentMetadata {
        val hash = DesktopCryptoProvider.sha256(bytes).toHex()
        val destination = root.resolve("$hash.bin")
        val hasValidExisting = Files.exists(destination) && runCatching {
            Files.readAllBytes(destination).contentEquals(bytes)
        }.getOrDefault(false)
        if (!hasValidExisting) {
            val temporary = root.resolve(".$hash.tmp-${Thread.currentThread().id}")
            Files.write(temporary, bytes)
            try {
                Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE)
            } catch (_: Exception) {
                Files.move(temporary, destination, StandardCopyOption.REPLACE_EXISTING)
            }
        }
        return AttachmentMetadata(
            id = Identifiers.newId("attachment"),
            fileName = fileName.substringAfterLast('/').substringAfterLast('\\').ifBlank { "attachment" },
            mimeType = mimeType.ifBlank { "application/octet-stream" },
            byteSize = bytes.size.toLong(),
            sha256 = hash,
            createdAtMillis = System.currentTimeMillis(),
        )
    }

    override suspend fun read(metadata: AttachmentMetadata): ByteArray {
        val bytes = Files.readAllBytes(root.resolve("${metadata.sha256.lowercase()}.bin"))
        check(bytes.size.toLong() == metadata.byteSize && DesktopCryptoProvider.sha256(bytes).toHex().equals(metadata.sha256, true)) {
            "Attachment integrity check failed"
        }
        return bytes
    }

    override suspend fun delete(metadata: AttachmentMetadata) {
        Files.deleteIfExists(root.resolve("${metadata.sha256.lowercase()}.bin"))
    }

    override suspend fun pathFor(metadata: AttachmentMetadata): String = root.resolve("${metadata.sha256.lowercase()}.bin").toString()
}

private class SwingFilePicker : PlatformFilePicker {
    override suspend fun pickFile(allowedMimeTypes: List<String>): PickedFile? {
        var result: PickedFile? = null
        onEventQueue {
            val chooser = JFileChooser()
            if (chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION) {
                val file = chooser.selectedFile
                result = PickedFile(file.name, "application/octet-stream", file.readBytes())
            }
        }
        return result
    }

    override suspend fun saveFile(suggestedName: String, bytes: ByteArray): Boolean {
        var saved = false
        onEventQueue {
            val chooser = JFileChooser().apply { selectedFile = File(suggestedName) }
            if (chooser.showSaveDialog(null) == JFileChooser.APPROVE_OPTION) {
                chooser.selectedFile.writeBytes(bytes)
                saved = true
            }
        }
        return saved
    }

    private fun onEventQueue(block: () -> Unit) {
        if (EventQueue.isDispatchThread()) block() else EventQueue.invokeAndWait(block)
    }
}

private object DesktopSseTransport : SseTransport {
    private val client = HttpClient(CIO) { expectSuccess = true }

    override suspend fun stream(endpoint: String, bearerToken: String, jsonBody: String, onLine: suspend (String) -> Unit) {
        client.preparePost(endpoint) {
            header(HttpHeaders.Authorization, "Bearer $bearerToken")
            contentType(ContentType.Application.Json)
            setBody(jsonBody)
        }.execute { response ->
            val channel = response.bodyAsChannel()
            while (!channel.isClosedForRead) {
                val line = channel.readUTF8Line() ?: break
                onLine(line)
            }
        }
    }
}

private fun dataRoot(): Path {
    val base = System.getenv("LOCALAPPDATA")?.takeIf { it.isNotBlank() }
        ?: System.getenv("APPDATA")?.takeIf { it.isNotBlank() }
        ?: System.getProperty("user.home")
    return Path.of(base, "KIN")
}

private fun isWindows(): Boolean = System.getProperty("os.name").contains("Windows", ignoreCase = true)

private fun ByteArray.toHex(): String {
    val digits = "0123456789abcdef"
    return buildString(size * 2) {
        for (byte in this@toHex) {
            val value = byte.toInt() and 0xff
            append(digits[value ushr 4]); append(digits[value and 0x0f])
        }
    }
}
