package app.kin.shared.backup

import app.kin.shared.attachments.AttachmentService
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.platform.AttachmentStore
import app.kin.shared.platform.PlatformServices
import app.kin.shared.storage.DuplicateImportException
import app.kin.shared.storage.KinRepository
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.runBlocking

class BackupServiceDesktopTest {
    @Test
    fun encryptedImportAndDuplicateRejectionKeepAttachment() = runBlocking {
        val sourceRepository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val sourceStore = InMemoryAttachmentStore()
        val sourceAttachments = AttachmentService(sourceStore)
        val sourceRole = sourceRepository.createRole("测试角色", "保持清醒", 1L)
        val sourceMetadata = sourceAttachments.add("note.txt", "text/plain", "private".encodeToByteArray())
        sourceRepository.saveAttachmentMetadata(sourceMetadata)
        val archive = KinBackupService(sourceRepository, sourceAttachments).export("password", 2L)

        val targetRepository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val targetStore = InMemoryAttachmentStore()
        val targetService = KinBackupService(targetRepository, AttachmentService(targetStore))
        val imported = targetService.importArchive(archive.bytes, "password", 3L)

        assertEquals(2, imported.recordsImported)
        assertEquals(sourceRole.id, targetRepository.roles().single { !it.isBuiltIn }.id)
        assertEquals("private", targetStore.read(sourceMetadata).decodeToString())
        assertFailsWith<DuplicateImportException> {
            targetService.importArchive(archive.bytes, "password", 4L)
        }
        assertEquals("private", targetStore.read(sourceMetadata).decodeToString())
        sourceRepository.close()
        targetRepository.close()
    }
}

private class InMemoryAttachmentStore : AttachmentStore {
    private val blobs = mutableMapOf<String, ByteArray>()

    override suspend fun put(fileName: String, mimeType: String, bytes: ByteArray): AttachmentMetadata {
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).toHex()
        blobs.putIfAbsent(hash, bytes.copyOf())
        return AttachmentMetadata(
            fileName = fileName,
            mimeType = mimeType,
            byteSize = bytes.size.toLong(),
            sha256 = hash,
            createdAtMillis = 1L,
        )
    }

    override suspend fun read(metadata: AttachmentMetadata): ByteArray = blobs[metadata.sha256]
        ?.copyOf()
        ?: error("missing attachment")

    override suspend fun delete(metadata: AttachmentMetadata) {
        blobs.remove(metadata.sha256)
    }

    override suspend fun pathFor(metadata: AttachmentMetadata): String = "memory://${metadata.sha256}"
}

private fun ByteArray.toHex(): String {
    val digits = "0123456789abcdef"
    return buildString(size * 2) {
        for (byte in this@toHex) {
            val value = byte.toInt() and 0xff
            append(digits[value ushr 4])
            append(digits[value and 0x0f])
        }
    }
}
