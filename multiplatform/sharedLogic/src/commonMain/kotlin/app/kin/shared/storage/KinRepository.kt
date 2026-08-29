package app.kin.shared.storage

import app.kin.shared.backup.KINPortableArchivePayloadV1
import app.kin.shared.backup.canonicalizeForBoundary
import app.kin.shared.model.AppSettings
import app.kin.shared.model.AttachmentMetadata
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.MemoryRecord
import app.kin.shared.model.RelationshipState
import app.kin.shared.model.Role
import app.kin.shared.model.Identifiers
import app.kin.shared.model.ayaneRole
import app.kin.shared.platform.PlatformServices
import app.kin.shared.platform.PortableDataSnapshot
import app.kin.shared.platform.SqliteDriver
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

class DuplicateImportException(message: String) : IllegalStateException(message)
class RepositoryValidationException(message: String) : IllegalArgumentException(message)

/**
 * SQLite-backed append-only domain repository. Every mutable-looking state is
 * represented by a new row/event or a transactionally replaced snapshot; chat
 * events themselves are never updated or deleted.
 */
class KinRepository(
    private val driver: SqliteDriver = PlatformServices.sqliteDatabase(),
) : AutoCloseable {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
    }

    init {
        driver.execute("PRAGMA foreign_keys = ON")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_roles (id TEXT PRIMARY KEY, json TEXT NOT NULL)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_relationships (role_id TEXT PRIMARY KEY, json TEXT NOT NULL)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_chat_events (id TEXT PRIMARY KEY, role_id TEXT NOT NULL, conversation_id TEXT NOT NULL, sequence INTEGER NOT NULL, json TEXT NOT NULL)")
        driver.execute("CREATE INDEX IF NOT EXISTS kin_chat_events_conversation_sequence ON kin_chat_events(conversation_id, sequence)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_memories (id TEXT PRIMARY KEY, role_id TEXT NOT NULL, json TEXT NOT NULL)")
        driver.execute("CREATE INDEX IF NOT EXISTS kin_memories_role ON kin_memories(role_id)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_attachments (id TEXT PRIMARY KEY, sha256 TEXT NOT NULL, json TEXT NOT NULL)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_settings (id INTEGER PRIMARY KEY CHECK(id = 1), json TEXT NOT NULL)")
        driver.execute("CREATE TABLE IF NOT EXISTS kin_import_receipts (export_id TEXT PRIMARY KEY, imported_at INTEGER NOT NULL)")
        if (driver.query("SELECT id, json FROM kin_roles").none { row ->
                KinBuiltIns.isAyaneRoleId(row.string("id")) ||
                    runCatching { KinBuiltIns.isAyaneRoleId(json.decodeFromString<Role>(row.string("json")).id) }
                        .getOrDefault(false)
            }) {
            putRole(ayaneRole())
        }
    }

    fun roles(includeArchived: Boolean = true): List<Role> = driver.query(
        "SELECT id, json FROM kin_roles ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, id",
        listOf(KinBuiltIns.ayaneRoleId),
    ).map { canonicalStoredRole(it) }
        .distinctBy { it.id }
        .filter { includeArchived || !it.isArchived }

    fun role(roleId: String): Role? {
        val canonicalId = KinBuiltIns.canonicalRoleId(roleId)
        return driver.query("SELECT id, json FROM kin_roles WHERE id = ?", listOf(canonicalId))
            .firstOrNull()
            ?.let(::canonicalStoredRole)
            ?: driver.query("SELECT id, json FROM kin_roles").firstOrNull {
                KinBuiltIns.canonicalRoleId(it.string("id")) == canonicalId ||
                    runCatching {
                        KinBuiltIns.canonicalRoleId(json.decodeFromString<Role>(it.string("json")).id) == canonicalId
                    }.getOrDefault(false)
            }?.let(::canonicalStoredRole)
    }

    fun createRole(displayName: String, systemPrompt: String, nowMillis: Long, avatarKey: String? = null): Role {
        require(displayName.isNotBlank()) { "Role name must not be blank" }
        val role = Role(
            id = Identifiers.newId("role"),
            displayName = displayName.trim(),
            systemPrompt = systemPrompt.trim(),
            avatarKey = avatarKey,
            createdAtMillis = nowMillis,
        )
        putRole(role)
        return role
    }

    fun archiveRole(roleId: String, nowMillis: Long) {
        val canonicalRoleId = KinBuiltIns.canonicalRoleId(roleId)
        require(!KinBuiltIns.isAyaneRoleId(canonicalRoleId)) { "The built-in Ayane role cannot be archived" }
        val current = role(canonicalRoleId) ?: throw RepositoryValidationException("Unknown role: $roleId")
        putRole(current.copy(isArchived = true))
        val relationship = relationship(canonicalRoleId)
        saveRelationship(relationship.copy(stage = app.kin.shared.model.RelationshipStage.ARCHIVED, updatedAtMillis = nowMillis))
    }

    fun relationship(roleId: String): RelationshipState {
        val canonicalRoleId = KinBuiltIns.canonicalRoleId(roleId)
        return driver.query("SELECT role_id, json FROM kin_relationships WHERE role_id = ?", listOf(canonicalRoleId))
            .firstOrNull()
            ?.let { json.decodeFromString<RelationshipState>(it.string("json")).copy(roleId = canonicalRoleId) }
            ?: driver.query("SELECT role_id, json FROM kin_relationships").firstOrNull {
                KinBuiltIns.canonicalRoleId(it.string("role_id")) == canonicalRoleId
            }?.let { json.decodeFromString<RelationshipState>(it.string("json")).copy(roleId = canonicalRoleId) }
            ?: RelationshipState(roleId = canonicalRoleId)
    }

    fun saveRelationship(state: RelationshipState) {
        val canonical = state.copy(roleId = KinBuiltIns.canonicalRoleId(state.roleId))
        require(role(canonical.roleId) != null) { "Unknown role: ${state.roleId}" }
        driver.execute(
            "INSERT INTO kin_relationships(role_id, json) VALUES(?, ?) ON CONFLICT(role_id) DO UPDATE SET json = excluded.json",
            listOf(canonical.roleId, json.encodeToString(canonical)),
        )
    }

    fun appendEvent(event: ChatEvent): ChatEvent {
        val canonical = event.copy(roleId = KinBuiltIns.canonicalRoleId(event.roleId))
        require(role(canonical.roleId) != null) { "Unknown role: ${event.roleId}" }
        val nextSequence = driver.query(
            "SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence FROM kin_chat_events WHERE conversation_id = ?",
            listOf(canonical.conversationId),
        ).firstOrNull()?.long("next_sequence") ?: 1L
        // Sequence is assigned at the append boundary. Imported/caller-provided
        // sequence values must not create collisions or reorder an existing
        // conversation.
        val persisted = canonical.copy(sequence = nextSequence)
        driver.execute(
            "INSERT INTO kin_chat_events(id, role_id, conversation_id, sequence, json) VALUES(?, ?, ?, ?, ?)",
            listOf(
                persisted.id,
                persisted.roleId,
                persisted.conversationId,
                persisted.sequence,
                json.encodeToString(persisted),
            ),
        )
        return persisted
    }

    fun events(conversationId: String, roleId: String? = null): List<ChatEvent> {
        val canonicalRoleId = roleId?.let(KinBuiltIns::canonicalRoleId)
        return driver.query(
            "SELECT json FROM kin_chat_events WHERE conversation_id = ? ORDER BY sequence",
            listOf(conversationId),
        ).map { json.decodeFromString<ChatEvent>(it.string("json")).canonicalRole() }
            .filter { canonicalRoleId == null || it.roleId == canonicalRoleId }
    }

    fun allEvents(): List<ChatEvent> = driver.query(
        "SELECT json FROM kin_chat_events ORDER BY conversation_id, sequence",
    ).map { json.decodeFromString<ChatEvent>(it.string("json")).canonicalRole() }

    fun addMemory(memory: MemoryRecord): MemoryRecord {
        val canonical = memory.copy(roleId = KinBuiltIns.canonicalRoleId(memory.roleId))
        require(role(canonical.roleId) != null) { "Unknown role: ${memory.roleId}" }
        driver.execute(
            "INSERT INTO kin_memories(id, role_id, json) VALUES(?, ?, ?)",
            listOf(canonical.id, canonical.roleId, json.encodeToString(canonical)),
        )
        return canonical
    }

    fun memories(roleId: String, includeTombstoned: Boolean = false): List<MemoryRecord> {
        val canonicalRoleId = KinBuiltIns.canonicalRoleId(roleId)
        return driver.query("SELECT json FROM kin_memories ORDER BY id")
            .map { json.decodeFromString<MemoryRecord>(it.string("json")).canonicalRole() }
            .filter { it.roleId == canonicalRoleId }
            .filter { includeTombstoned || !it.isTombstoned }
    }

    fun saveAttachmentMetadata(metadata: AttachmentMetadata) {
        require(metadata.byteSize >= 0) { "Attachment size cannot be negative" }
        driver.execute(
            "INSERT INTO kin_attachments(id, sha256, json) VALUES(?, ?, ?) ON CONFLICT(id) DO UPDATE SET sha256 = excluded.sha256, json = excluded.json",
            listOf(metadata.id, metadata.sha256, json.encodeToString(metadata)),
        )
    }

    fun attachments(): List<AttachmentMetadata> = driver.query(
        "SELECT json FROM kin_attachments ORDER BY id",
    ).map { json.decodeFromString<AttachmentMetadata>(it.string("json")) }

    fun settings(): AppSettings = driver.query("SELECT json FROM kin_settings WHERE id = 1")
        .firstOrNull()?.let { json.decodeFromString<AppSettings>(it.string("json")) } ?: AppSettings()

    fun saveSettings(settings: AppSettings) {
        driver.execute(
            "INSERT INTO kin_settings(id, json) VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json",
            listOf(json.encodeToString(settings)),
        )
    }

    fun snapshot(attachmentBytes: Map<String, ByteArray> = emptyMap()): PortableDataSnapshot = PortableDataSnapshot(
        roles = roles(),
        relationships = roles().map { relationship(it.id) },
        events = allEvents(),
        memories = roles().flatMap { memories(it.id, includeTombstoned = true) },
        settings = settings(),
        attachments = attachments(),
        attachmentBytes = attachmentBytes,
    )

    /** Validate all import constraints before touching the database. */
    fun validateImport(payload: KINPortableArchivePayloadV1) {
        validateCanonicalImport(payload.canonicalizeForBoundary())
    }

    private fun validateCanonicalImport(payload: KINPortableArchivePayloadV1) {
        require(payload.format == KinBuiltIns.archiveFormat) { "Unsupported archive format" }
        require(payload.schemaVersion == KinBuiltIns.schemaVersion) { "Unsupported archive schema" }
        if (driver.query("SELECT export_id FROM kin_import_receipts WHERE export_id = ?", listOf(payload.exportId)).isNotEmpty()) {
            throw DuplicateImportException("Archive ${payload.exportId} was already imported")
        }
        val existingRoleIds = roles().map { it.id }.toSet()
        val importedRoleIds = payload.roles.map { it.id }.toSet()
        require(importedRoleIds.size == payload.roles.size) { "Duplicate role IDs in archive" }
        require(payload.roles.none { KinBuiltIns.isAyaneRoleId(it.id) }) { "Archive cannot replace built-in Ayane" }
        require(payload.relationships.all { it.roleId in existingRoleIds || it.roleId in importedRoleIds }) {
            "Relationship references an unknown role"
        }
        require(payload.chatEvents.all { it.roleId in existingRoleIds || it.roleId in importedRoleIds }) {
            "Chat event references an unknown role"
        }
        require(payload.memories.all { it.roleId in existingRoleIds || it.roleId in importedRoleIds }) {
            "Memory references an unknown role"
        }
        require(payload.roles.none { role(it.id) != null }) { "Archive contains an existing role" }
        require(payload.chatEvents.none { event(it.id) != null }) { "Archive contains an existing chat event" }
        require(payload.memories.none { memory(it.id) != null }) { "Archive contains an existing memory" }
        require(payload.attachments.none { attachment(it.metadata.id) != null }) { "Archive contains an existing attachment" }
    }

    /** Import is one SQLite transaction; any validation or insert failure rolls it back. */
    fun importPayload(payload: KINPortableArchivePayloadV1, importedAtMillis: Long): Int {
        val canonical = payload.canonicalizeForBoundary()
        validateCanonicalImport(canonical)
        return driver.transaction {
            canonical.roles.forEach(::putRole)
            canonical.relationships.forEach(::saveRelationship)
            canonical.chatEvents.forEach(::appendEvent)
            canonical.memories.forEach(::addMemory)
            canonical.attachments.forEach { saveAttachmentMetadata(it.metadata) }
            saveSettings(canonical.settings)
            driver.execute(
                "INSERT INTO kin_import_receipts(export_id, imported_at) VALUES(?, ?)",
                listOf(canonical.exportId, importedAtMillis),
            )
            canonical.roles.size + canonical.chatEvents.size + canonical.memories.size + canonical.attachments.size
        }
    }

    private fun putRole(role: Role) {
        val canonical = KinBuiltIns.canonicalRoleId(role.id)
        require(!KinBuiltIns.isAyaneRoleId(canonical) || role.isBuiltIn) {
            "The built-in Ayane role cannot be shadowed"
        }
        val persisted = if (KinBuiltIns.isAyaneRoleId(canonical)) {
            ayaneRole()
        } else {
            role.copy(id = canonical)
        }
        driver.execute(
            "INSERT INTO kin_roles(id, json) VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json",
            listOf(persisted.id, json.encodeToString(persisted)),
        )
    }

    private fun canonicalStoredRole(row: Map<String, Any?>): Role {
        val role = json.decodeFromString<Role>(row.string("json"))
        val storedId = row.string("id")
        val canonicalId = when {
            KinBuiltIns.isAyaneRoleId(storedId) || KinBuiltIns.isAyaneRoleId(role.id) -> KinBuiltIns.ayaneRoleId
            storedId.isNotBlank() -> KinBuiltIns.canonicalRoleId(storedId)
            else -> KinBuiltIns.canonicalRoleId(role.id)
        }
        return if (KinBuiltIns.isAyaneRoleId(canonicalId)) ayaneRole() else role.copy(id = canonicalId)
    }

    private fun ChatEvent.canonicalRole(): ChatEvent = copy(roleId = KinBuiltIns.canonicalRoleId(roleId))
    private fun MemoryRecord.canonicalRole(): MemoryRecord = copy(roleId = KinBuiltIns.canonicalRoleId(roleId))

    private fun event(id: String): ChatEvent? = driver.query("SELECT json FROM kin_chat_events WHERE id = ?", listOf(id))
        .firstOrNull()?.let { json.decodeFromString<ChatEvent>(it.string("json")) }

    private fun memory(id: String): MemoryRecord? = driver.query("SELECT json FROM kin_memories WHERE id = ?", listOf(id))
        .firstOrNull()?.let { json.decodeFromString<MemoryRecord>(it.string("json")) }

    private fun attachment(id: String): AttachmentMetadata? = driver.query("SELECT json FROM kin_attachments WHERE id = ?", listOf(id))
        .firstOrNull()?.let { json.decodeFromString<AttachmentMetadata>(it.string("json")) }

    override fun close() {
        driver.close()
    }
}

private fun Map<String, Any?>.string(key: String): String = this[key]?.toString() ?: error("Missing SQLite column $key")
private fun Map<String, Any?>.long(key: String): Long = when (val value = this[key]) {
    is Number -> value.toLong()
    else -> value?.toString()?.toLongOrNull() ?: 0L
}
