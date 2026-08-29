package app.kin.shared.attachments

import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.platform.AttachmentStore
import app.kin.shared.platform.PlatformServices

class AttachmentService(
    private val store: AttachmentStore = PlatformServices.attachmentStore(),
) {
    suspend fun add(fileName: String, mimeType: String, bytes: ByteArray): AttachmentMetadata =
        store.put(fileName, mimeType, bytes)

    suspend fun load(metadata: AttachmentMetadata): ByteArray = store.read(metadata)

    suspend fun remove(metadata: AttachmentMetadata) = store.delete(metadata)

    suspend fun privatePath(metadata: AttachmentMetadata): String = store.pathFor(metadata)
}
