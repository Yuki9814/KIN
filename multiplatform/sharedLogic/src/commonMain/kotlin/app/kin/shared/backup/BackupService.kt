package app.kin.shared.backup

import app.kin.shared.attachments.AttachmentService
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.Identifiers
import app.kin.shared.storage.KinRepository
import kotlinx.coroutines.CancellationException

class BackupImportException(message: String, cause: Throwable? = null) : IllegalStateException(message, cause)

data class BackupExportResult(val bytes: ByteArray, val fileName: String)
data class BackupImportResult(val recordsImported: Int, val exportId: String)

/** Password-protected portable data flow. Credentials never enter the snapshot. */
class KinBackupService(
    private val repository: KinRepository,
    private val attachments: AttachmentService,
) {
    suspend fun export(password: String, nowMillis: Long): BackupExportResult {
        require(password.isNotEmpty()) { "Backup password must not be empty" }
        val snapshot = repository.snapshot(
            attachmentBytes = repository.attachments().associate { metadata -> metadata.id to attachments.load(metadata) },
        )
        val exportId = "export-${nowMillis.toString(16)}-${Identifiers.newId("id").substringAfter('-')}"
        val payload = ArchivePayloadCodec.fromSnapshot(snapshot, exportId)
        val bytes = ArchiveCrypto.encryptPayload(payload, password)
        return BackupExportResult(bytes, "KIN-${KinBuiltIns.archiveFormat}-$nowMillis.kinbackup")
    }

    suspend fun importArchive(bytes: ByteArray, password: String, nowMillis: Long): BackupImportResult {
        val payload = try {
            ArchiveCrypto.decryptPayload(bytes, password)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Throwable) {
            throw BackupImportException("Backup decryption or validation failed", failure)
        }
        repository.validateImport(payload)
        val newlyWritten = mutableListOf<AttachmentMetadata>()
        try {
            // Files are written before the SQLite transaction. If the transaction
            // rejects the archive, every file created in this attempt is removed.
            payload.attachments.forEach { attachment ->
                val hex = attachment.contentHex ?: throw BackupImportException("Attachment bytes are missing")
                val data = hex.decodeHex()
                require(data.size.toLong() == attachment.metadata.byteSize) { "Attachment size mismatch" }
                // Attachment blobs are content-addressed and may already belong to
                // another metadata record. Keep pre-existing blobs intact if the
                // later database transaction rejects this archive.
                var wasPresent = false
                try {
                    attachments.load(attachment.metadata)
                    wasPresent = true
                } catch (_: Throwable) {
                    // A missing/corrupt blob is replaced by the content-addressed
                    // store and is therefore owned by this import attempt.
                }
                val imported = attachments.add(
                    attachment.metadata.fileName,
                    attachment.metadata.mimeType,
                    data,
                )
                require(imported.sha256.equals(attachment.metadata.sha256, ignoreCase = true)) {
                    "Attachment hash mismatch"
                }
                if (!wasPresent) newlyWritten += imported
            }
            val count = repository.importPayload(payload, nowMillis)
            return BackupImportResult(count, payload.exportId)
        } catch (cancelled: CancellationException) {
            newlyWritten.forEach { runCatching { attachments.remove(it) } }
            throw cancelled
        } catch (failure: Throwable) {
            newlyWritten.forEach { runCatching { attachments.remove(it) } }
            throw if (failure is BackupImportException) failure else BackupImportException("Backup import rolled back", failure)
        }
    }
}

private fun String.decodeHex(): ByteArray {
    require(length % 2 == 0) { "Invalid hex length" }
    return ByteArray(length / 2) { index ->
        val high = digit(this[index * 2])
        val low = digit(this[index * 2 + 1])
        ((high shl 4) or low).toByte()
    }
}

private fun digit(char: Char): Int = when (char) {
    in '0'..'9' -> char - '0'
    in 'a'..'f' -> char - 'a' + 10
    in 'A'..'F' -> char - 'A' + 10
    else -> error("Invalid hex character")
}
