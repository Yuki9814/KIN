package app.kin.shared.platform

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher
import io.ktor.client.HttpClient
import io.ktor.client.engine.android.Android
import io.ktor.client.request.header
import io.ktor.client.request.preparePost
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.utils.io.readUTF8Line
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.Identifiers

actual object PlatformServices {
    private var appContext: Context? = null
    private var picker: AndroidFilePicker? = null

    actual fun initialize(context: Any?) {
        val supplied = context as? Context
            ?: throw IllegalArgumentException("Android PlatformServices requires a Context")
        appContext = supplied.applicationContext
        picker = AndroidFilePicker(appContext!!)
    }

    private fun context(): Context = appContext ?: error("Call PlatformServices.initialize(context) first")

    actual fun crypto(): ArchiveCryptoProvider = AndroidCryptoProvider
    actual fun secretStore(): SecretStore = AndroidKeystoreSecretStore(context())
    actual fun sqliteDatabase(name: String): SqliteDriver = AndroidSqliteDriver(context(), name)
    actual fun settingsStore(): SettingsStore = AndroidSettingsStore(context())
    actual fun attachmentStore(): AttachmentStore = AndroidAttachmentStore(context())
    actual fun filePicker(): PlatformFilePicker = picker ?: AndroidFilePicker(context())
    actual fun sseTransport(): SseTransport = AndroidSseTransport

    /** ActivityResult launchers must be registered during Activity creation, not on a click. */
    fun bindFilePickerLaunchers(
        openDocument: ActivityResultLauncher<Array<String>>,
        createDocument: ActivityResultLauncher<String>,
    ) {
        (picker ?: AndroidFilePicker(context()).also { picker = it }).bind(openDocument, createDocument)
    }

    fun completePickedFile(uri: Uri?) {
        (picker ?: return).completePick(uri)
    }

    fun completeSavedFile(uri: Uri?) {
        (picker ?: return).completeSave(uri)
    }
}

private object AndroidCryptoProvider : ArchiveCryptoProvider {
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
        cipher.init(mode, javax.crypto.spec.SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        return cipher.doFinal(input)
    }
}

private class AndroidKeystoreSecretStore(private val context: Context) : SecretStore {
    private val preferences: SharedPreferences = context.getSharedPreferences("kin-secret-store", Context.MODE_PRIVATE)
    private val keyStore: KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    override suspend fun read(name: String): ByteArray? {
        val encoded = preferences.getString(preferenceKey(name), null) ?: return null
        val packed = Base64.decode(encoded, Base64.NO_WRAP)
        require(packed.size > 12) { "Corrupt Keystore value" }
        val nonce = packed.copyOfRange(0, 12)
        val ciphertext = packed.copyOfRange(12, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(name), GCMParameterSpec(128, nonce))
        return cipher.doFinal(ciphertext)
    }

    override suspend fun write(name: String, value: ByteArray) {
        val nonce = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(name), GCMParameterSpec(128, nonce))
        val ciphertext = cipher.doFinal(value)
        check(preferences.edit().putString(preferenceKey(name), Base64.encodeToString(nonce + ciphertext, Base64.NO_WRAP)).commit()) {
            "Unable to persist Keystore value"
        }
    }

    override suspend fun delete(name: String) {
        preferences.edit().remove(preferenceKey(name)).commit()
        val alias = alias(name)
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }

    private fun key(name: String): SecretKey {
        val alias = alias(name)
        if (!keyStore.containsAlias(alias)) {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(
                KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            generator.generateKey()
        }
        return keyStore.getKey(alias, null) as SecretKey
    }

    private fun sanitizedName(name: String): String = name.replace(Regex("[^A-Za-z0-9_.-]"), "_").take(80).ifBlank { "secret" }
    private fun preferenceKey(name: String): String = "value.${sanitizedName(name)}"
    private fun alias(name: String): String = "kin.${sanitizedName(name)}"
}

private class AndroidSqliteDriver(context: Context, name: String) : SqliteDriver {
    private val helper = object : SQLiteOpenHelper(context, name, null, 1) {
        override fun onCreate(db: SQLiteDatabase) = Unit
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    }
    private val database: SQLiteDatabase = helper.writableDatabase

    override fun execute(sql: String, args: List<Any?>) {
        database.execSQL(sql, args.toTypedArray())
    }

    override fun query(sql: String, args: List<Any?>): List<Map<String, Any?>> {
        val cursor = database.rawQuery(sql, args.map { it?.toString() }.toTypedArray())
        cursor.use {
            val result = ArrayList<Map<String, Any?>>(cursor.count)
            while (cursor.moveToNext()) {
                val row = LinkedHashMap<String, Any?>(cursor.columnCount)
                for (index in 0 until cursor.columnCount) {
                    row[cursor.getColumnName(index)] = when (cursor.getType(index)) {
                        Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                        Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                        Cursor.FIELD_TYPE_BLOB -> cursor.getBlob(index)
                        Cursor.FIELD_TYPE_STRING -> cursor.getString(index)
                        else -> null
                    }
                }
                result += row
            }
            return result
        }
    }

    override fun <T> transaction(block: () -> T): T {
        database.beginTransaction()
        return try {
            block().also { database.setTransactionSuccessful() }
        } finally {
            database.endTransaction()
        }
    }

    override fun close() {
        helper.close()
    }
}

private class AndroidSettingsStore(context: Context) : SettingsStore {
    private val prefs = context.getSharedPreferences("kin-settings", Context.MODE_PRIVATE)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }

    override suspend fun load(): AppSettings = prefs.getString("settings", null)?.let { json.decodeFromString<AppSettings>(it) } ?: AppSettings()

    override suspend fun save(settings: AppSettings) {
        check(prefs.edit().putString("settings", json.encodeToString(settings)).commit()) { "Unable to persist settings" }
    }
}

private class AndroidAttachmentStore(private val context: Context) : AttachmentStore {
    private val root: File = File(context.filesDir, "kin-attachments").apply { mkdirs() }

    override suspend fun put(fileName: String, mimeType: String, bytes: ByteArray): AttachmentMetadata {
        val hash = AndroidCryptoProvider.sha256(bytes).toHex()
        val destination = File(root, "$hash.bin")
        val hasValidExisting = destination.exists() && runCatching {
            destination.readBytes().contentEquals(bytes)
        }.getOrDefault(false)
        if (!hasValidExisting) {
            val temporary = File(root, ".$hash.tmp-${Thread.currentThread().id}")
            FileOutputStream(temporary).use { it.write(bytes); it.fd.sync() }
            try {
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: Exception) {
                Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
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
        val bytes = File(root, "${metadata.sha256.lowercase()}.bin").readBytes()
        check(bytes.size.toLong() == metadata.byteSize && AndroidCryptoProvider.sha256(bytes).toHex().equals(metadata.sha256, true)) {
            "Attachment integrity check failed"
        }
        return bytes
    }

    override suspend fun delete(metadata: AttachmentMetadata) {
        // Several metadata records may reference the same content hash; only
        // remove the private blob when this record is explicitly deleted.
        File(root, "${metadata.sha256.lowercase()}.bin").delete()
    }

    override suspend fun pathFor(metadata: AttachmentMetadata): String = File(root, "${metadata.sha256.lowercase()}.bin").absolutePath
}

private class AndroidFilePicker(private val context: Context) : PlatformFilePicker {
    private var openDocument: ActivityResultLauncher<Array<String>>? = null
    private var createDocument: ActivityResultLauncher<String>? = null
    private var pickContinuation: CancellableContinuation<PickedFile?>? = null
    private var saveContinuation: CancellableContinuation<Boolean>? = null
    private var pendingSaveBytes: ByteArray? = null

    fun bind(
        openDocument: ActivityResultLauncher<Array<String>>,
        createDocument: ActivityResultLauncher<String>,
    ) {
        this.openDocument = openDocument
        this.createDocument = createDocument
    }

    override suspend fun pickFile(allowedMimeTypes: List<String>): PickedFile? = suspendCancellableCoroutine { continuation ->
        check(pickContinuation == null) { "Another Android file pick is already in progress" }
        val launcher = openDocument ?: error("Android ActivityResult picker is not bound")
        pickContinuation = continuation
        continuation.invokeOnCancellation {
            if (pickContinuation === continuation) pickContinuation = null
        }
        try {
            launcher.launch(allowedMimeTypes.filter { it.isNotBlank() }.ifEmpty { listOf("*/*") }.toTypedArray())
        } catch (failure: Throwable) {
            if (pickContinuation === continuation) pickContinuation = null
            continuation.resumeWith(Result.failure(failure))
        }
    }

    override suspend fun saveFile(suggestedName: String, bytes: ByteArray): Boolean = suspendCancellableCoroutine { continuation ->
        check(saveContinuation == null) { "Another Android file save is already in progress" }
        val launcher = createDocument ?: error("Android ActivityResult picker is not bound")
        saveContinuation = continuation
        pendingSaveBytes = bytes.copyOf()
        continuation.invokeOnCancellation {
            if (saveContinuation === continuation) {
                saveContinuation = null
                pendingSaveBytes = null
            }
        }
        try {
            launcher.launch(suggestedName.substringAfterLast('/').substringAfterLast('\\').ifBlank { "KIN-export" })
        } catch (failure: Throwable) {
            if (saveContinuation === continuation) {
                saveContinuation = null
                pendingSaveBytes = null
            }
            continuation.resumeWith(Result.failure(failure))
        }
    }

    fun completePick(uri: Uri?) {
        val continuation = pickContinuation ?: return
        pickContinuation = null
        val picked = try {
            uri?.let(::readPickedFile)
        } catch (failure: Throwable) {
            continuation.resumeWith(Result.failure(failure))
            return
        }
        continuation.resume(picked)
    }

    fun completeSave(uri: Uri?) {
        val continuation = saveContinuation ?: return
        val bytes = pendingSaveBytes
        saveContinuation = null
        pendingSaveBytes = null
        if (uri == null || bytes == null) {
            continuation.resume(false)
            return
        }
        try {
            context.contentResolver.openOutputStream(uri)?.use { it.write(bytes); it.flush() }
                ?: error("Unable to open Android destination")
            continuation.resume(true)
        } catch (failure: Throwable) {
            continuation.resumeWith(Result.failure(failure))
        }
    }

    private fun readPickedFile(uri: Uri): PickedFile {
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            ?.ifBlank { null }
            ?: uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { null }
            ?: "attachment"
        val mimeType = resolver.getType(uri).orEmpty().ifBlank { "application/octet-stream" }
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("Unable to read selected Android file")
        return PickedFile(name, mimeType, bytes)
    }
}

private object AndroidSseTransport : SseTransport {
    private val client = HttpClient(Android) {
        expectSuccess = true
    }

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

private fun ByteArray.toHex(): String {
    val digits = "0123456789abcdef"
    return buildString(size * 2) {
        for (byte in this@toHex) {
            val value = byte.toInt() and 0xff
            append(digits[value ushr 4]); append(digits[value and 0x0f])
        }
    }
}
