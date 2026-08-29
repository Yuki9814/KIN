import CommonCrypto
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum KINPortableArchiveError: LocalizedError, Equatable {
    case emptyPassword
    case invalidArchive
    case unsupportedVersion(Int)
    case incompatibleParameters
    case authenticationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            "便携备份密码不能为空。"
        case .invalidArchive:
            "这不是可读取的 KIN 便携备份。"
        case .unsupportedVersion(let version):
            "便携备份版本 \(version) 与当前应用不兼容。"
        case .incompatibleParameters:
            "便携备份的加密参数不受支持。"
        case .authenticationFailed:
            "便携备份密码错误或文件已被篡改。"
        case .exportFailed:
            "便携备份内容无法生成。"
        }
    }
}

/// Password-protected, portable account archive. The encrypted payload is a
/// sanitized KIN JSON export; the binary header contains no user records in
/// plaintext and is authenticated as AES-GCM additional data.  The exact wire
/// layout is shared with the Kotlin implementation:
/// `magic || version || salt[16] || nonce[12] || ciphertext || tag[16]`.
struct KINPortableArchiveV1: Equatable, Sendable {
    static let formatIdentifier = "KINPortableArchiveV1"
    static let currentVersion = 1
    static let pbkdf2Algorithm = "PBKDF2-HMAC-SHA256"
    static let pbkdf2Iterations = 600_000
    static let saltLength = 16
    static let nonceLength = 12
    static let keyLength = 32
    static let tagLength = 16
    static let fileExtension = "kinbackup"
    private static let magic = Data(formatIdentifier.utf8)
    private static let headerLength = magic.count + 1 + saltLength + nonceLength

    /// Encrypts arbitrary bytes using PBKDF2-HMAC-SHA256 and AES-256-GCM.
    /// This primitive is intentionally independent from SwiftData so callers
    /// can test the cryptographic contract without touching the local store.
    static func encrypt(_ payload: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw KINPortableArchiveError.emptyPassword }
        return try encrypt(
            payload,
            password: password,
            salt: randomData(count: saltLength),
            nonce: randomData(count: nonceLength)
        )
    }

    /// Deterministic entry point used only by the shared Swift/Kotlin golden
    /// vector. Production callers use the random-salt overload above.
    static func encrypt(
        _ payload: Data,
        password: String,
        salt: Data,
        nonce nonceData: Data
    ) throws -> Data {
        guard !password.isEmpty else { throw KINPortableArchiveError.emptyPassword }
        guard salt.count == saltLength, nonceData.count == nonceLength else {
            throw KINPortableArchiveError.incompatibleParameters
        }
        let key = try deriveKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        var header = magic
        header.append(UInt8(currentVersion))
        header.append(salt)
        header.append(nonceData)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(payload, using: key, nonce: nonce, authenticating: header)
        } catch {
            throw KINPortableArchiveError.exportFailed
        }
        var archive = header
        archive.append(sealed.ciphertext)
        archive.append(sealed.tag)
        return archive
    }

    static func encrypt(payload: Data, password: String) throws -> Data {
        try encrypt(payload, password: password)
    }

    static func makeArchive(payload: Data, password: String) throws -> Data {
        try encrypt(payload, password: password)
    }

    /// Decrypts and authenticates an archive. Every envelope parameter is
    /// checked before any plaintext is returned, so wrong passwords and GCM
    /// tampering fail without exposing a partial payload.
    static func decrypt(_ archive: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw KINPortableArchiveError.emptyPassword }
        guard archive.count >= headerLength + tagLength else {
            throw KINPortableArchiveError.invalidArchive
        }
        guard archive.prefix(magic.count) == magic else {
            throw KINPortableArchiveError.invalidArchive
        }
        let version = Int(archive[magic.count])
        guard version == currentVersion else {
            throw KINPortableArchiveError.unsupportedVersion(version)
        }
        let saltStart = magic.count + 1
        let nonceStart = saltStart + saltLength
        let payloadStart = nonceStart + nonceLength
        let tagStart = archive.count - tagLength
        guard tagStart >= payloadStart else { throw KINPortableArchiveError.invalidArchive }
        let salt = archive.subdata(in: saltStart..<nonceStart)
        let nonceData = archive.subdata(in: nonceStart..<payloadStart)
        let ciphertext = archive.subdata(in: payloadStart..<tagStart)
        let tag = archive.subdata(in: tagStart..<archive.count)
        let header = archive.prefix(headerLength)
        let key = try deriveKey(password: password, salt: salt)
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw KINPortableArchiveError.authenticationFailed
        }
    }

    static func decrypt(archive: Data, password: String) throws -> Data {
        try decrypt(archive, password: password)
    }

    static func openArchive(_ archive: Data, password: String) throws -> Data {
        try decrypt(archive, password: password)
    }

    /// Builds a `.kinbackup` from the existing JSON export while removing
    /// device identity, credentials, CloudKit journals and derived indexes.
    @MainActor
    static func makeArchive(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        password: String,
        now: Date = Date()
    ) throws -> Data {
        let json = try DataExportService.export(context: context, defaults: defaults, now: now)
        let portableJSON = try sanitizeJSON(json)
        return try encrypt(portableJSON, password: password)
    }

    @MainActor
    static func export(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        password: String,
        now: Date = Date()
    ) throws -> Data {
        try makeArchive(context: context, defaults: defaults, password: password, now: now)
    }

    /// Exposes the same redaction boundary to migration tests and audit tools
    /// without exposing the private implementation details of the envelope.
    static func sanitizeForPortableArchive(_ data: Data) throws -> Data {
        try sanitizeJSON(data)
    }

    /// Prepares a validated JSON payload for DataImportService. The archive
    /// never stores source device IDs; restore receives a fresh local
    /// provenance token only after decryption, and the destination's provider
    /// settings are retained instead of being imported from the archive.
    @MainActor
    static func prepareJSONForRestore(
        _ archive: Data,
        password: String,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> Data {
        let decrypted = try decrypt(archive, password: password)
        guard var root = try JSONSerialization.jsonObject(
            with: decrypted,
            options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            throw KINPortableArchiveError.invalidArchive
        }

        // Kotlin/Compose writes the compact cross-platform payload while the
        // Apple app writes its richer AyaneDataExport graph. Convert the KMP
        // core graph before passing it to the existing all-or-nothing import
        // validator. Apple-only collections stay empty for a KMP-originated
        // archive; an Apple-originated archive keeps them in full.
        if KMPPortableArchiveCompatibility.isPayload(root) {
            root = try KMPPortableArchiveCompatibility.applePayload(from: root)
        }

        let restoreDeviceID = "portable-restore-\(UUID().uuidString.lowercased())"
        injectRestoreMetadata(&root, deviceID: restoreDeviceID)

        // Keep provider/cloud preferences local to the destination. This is
        // also the reason a portable backup can safely cross accounts.
        let currentExport = try DataExportService.export(
            context: context,
            defaults: defaults,
            now: now
        )
        guard let currentObject = try JSONSerialization.jsonObject(
            with: currentExport,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
        let currentSettings = currentObject["settings"] else {
            throw KINPortableArchiveError.exportFailed
        }
        root["settings"] = currentSettings

        guard JSONSerialization.isValidJSONObject(root) else {
            throw KINPortableArchiveError.invalidArchive
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    @MainActor
    static func inspectArchive(
        _ archive: Data,
        password: String,
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> DataImportSummary {
        let prepared = try prepareJSONForRestore(
            archive,
            password: password,
            context: context,
            defaults: defaults
        )
        return try DataImportService.inspect(prepared)
    }

    @MainActor
    @discardableResult
    static func restoreArchive(
        _ archive: Data,
        password: String,
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> DataImportSummary {
        let prepared = try prepareJSONForRestore(
            archive,
            password: password,
            context: context,
            defaults: defaults
        )
        // Validation completes before replaceAll is allowed to mutate the
        // context. DataImportService itself repeats the check defensively.
        _ = try DataImportService.inspect(prepared)
        return try DataImportService.replaceAll(
            with: prepared,
            context: context,
            defaults: defaults
        )
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let outputLength = keyLength
        let passwordLength = passwordData.count
        let saltLength = salt.count
        var output = [UInt8](repeating: 0, count: outputLength)
        let status = output.withUnsafeMutableBytes { outputBuffer in
            passwordData.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordLength,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        saltLength,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(pbkdf2Iterations),
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw KINPortableArchiveError.incompatibleParameters
        }
        return SymmetricKey(data: Data(output))
    }

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return Data(bytes)
    }

    private static let prohibitedKeyFragments: [String] = [
        "apikey",
        "apitoken",
        "oauth",
        "accesstoken",
        "refreshtoken",
        "secret",
        "signature",
        "cloudkit",
        "journal",
        "derived",
        "embedding",
        "searchindex",
        "lease",
        "device",
        "logicaltimestamp"
    ]

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isProhibitedKey(_ key: String) -> Bool {
        let normalized = normalizedKey(key)
        return prohibitedKeyFragments.contains { normalized.contains($0) }
    }

    private static func sanitizedValue(_ value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, child) in dictionary where !isProhibitedKey(key) {
                if let sanitized = sanitizedValue(child) {
                    output[key] = sanitized
                }
            }
            return output
        }
        if let array = value as? [Any] {
            return array.compactMap(sanitizedValue)
        }
        return value
    }

    private static func sanitizeJSON(_ data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
        var sanitized = sanitizedValue(object) as? [String: Any] else {
            throw KINPortableArchiveError.exportFailed
        }

        // A portable archive must not carry an API endpoint/model selection or
        // a cloud-sync toggle. Restore keeps the destination's values.
        sanitized["settings"] = [
            "provider": [
                "provider_id": NSNull(),
                "base_url": "",
                "model": "",
                "embedding_model": "",
                "temperature": 0.8,
                "streams_responses": true
            ],
            "memory": [
                "auto_extract_memory": true,
                "token_budget": 2_400,
                "recent_message_limit": 24,
                "raw_history_recall_enabled": true,
                "raw_history_token_budget": 1_000
            ],
            "persistence": ["cloud_sync_enabled": false],
            "humanized_reply_delay_enabled": true,
            "proactive_messages_enabled": true,
            "proactive_quiet_start_hour": 23,
            "proactive_quiet_end_hour": 8,
            "worldview_auto_match_enabled": true
        ]
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            throw KINPortableArchiveError.exportFailed
        }
        return try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
    }

    private static let recordArrayKeys: [String] = [
        "profiles",
        "conversations",
        "events",
        "memories",
        "evidence",
        "summaries",
        "tombstones",
        "relationships",
        "friend_applications",
        "transitions",
        "moment_tasks",
        "moment_posts",
        "moment_interactions",
        "conversation_read_states",
        "moment_read_states",
        "moment_ai_interaction_tasks",
        "world_profiles",
        "group_conversations",
        "group_participants",
        "chat_turn_presentations",
        "proactive_message_tasks"
    ]

    private static func injectRestoreMetadata(
        _ root: inout [String: Any],
        deviceID: String
    ) {
        for key in recordArrayKeys {
            guard var records = root[key] as? [[String: Any]] else { continue }
            for index in records.indices {
                records[index]["device_id"] = deviceID
                if key == "events" {
                    let sequence = (records[index]["device_sequence"] as? Int) ?? index + 1
                    records[index]["device_sequence"] = max(0, sequence)
                    let timestamp = records[index]["logical_timestamp"] as? String
                    if timestamp?.isEmpty != false {
                        records[index]["logical_timestamp"] = "\(sequence)-\(deviceID)-\(index + 1)"
                    }
                }
            }
            root[key] = records
        }
        for key in ["persona", "user_profile"] {
            guard var record = root[key] as? [String: Any] else { continue }
            record["device_id"] = deviceID
            root[key] = record
        }
    }
}

/// Strict bridge for the canonical Kotlin `KINPortableArchivePayloadV1` JSON.
///
/// IDs created by the KMP client are strings rather than UUIDs. They are
/// mapped deterministically so importing the same archive twice converges on
/// the same Apple records. Unsupported streaming audit rows are ignored, but
/// user-visible messages, final replies, failures, memories, tombstones and a
/// single attachment per message are preserved. Any missing/corrupt attachment
/// or cross-role reference rejects the entire archive before SwiftData writes.
private enum KMPPortableArchiveCompatibility {
    private struct RoleProjection {
        let rawID: String
        let id: UUID
        let name: String
        let prompt: String
        let createdAtMillis: Int64
        let archived: Bool
    }

    private struct AttachmentProjection {
        let id: String
        let fileName: String
        let mimeType: String
        let sha256: String
        let bytes: Data
    }

    static func isPayload(_ root: [String: Any]) -> Bool {
        string(root["format"]) == KINPortableArchiveV1.formatIdentifier
            && integer(root["schemaVersion"]) != nil
    }

    static func applePayload(from root: [String: Any]) throws -> [String: Any] {
        guard string(root["format"]) == KINPortableArchiveV1.formatIdentifier,
              integer(root["schemaVersion"]) == 1,
              let exportID = string(root["exportId"])?.trimmed,
              !exportID.isEmpty else {
            throw KINPortableArchiveError.invalidArchive
        }

        let ayane = BuiltInCompanionCatalog.companions[0]
        let builtIn = RoleProjection(
            rawID: RoleScope.legacyRoleID.uuidString,
            id: RoleScope.legacyRoleID,
            name: ayane.name,
            prompt: ayane.prompt,
            createdAtMillis: 0,
            archived: false
        )
        var roles = [builtIn]
        var roleByKey = [canonicalID(builtIn.rawID): builtIn]

        for object in objectArray(root["roles"]) {
            guard let rawID = string(object["id"])?.trimmed, !rawID.isEmpty else {
                throw KINPortableArchiveError.invalidArchive
            }
            let key = canonicalID(rawID)
            let claimsBuiltIn = bool(object["isBuiltIn"]) ?? false
            if key == canonicalID(builtIn.rawID) {
                guard claimsBuiltIn else { throw KINPortableArchiveError.invalidArchive }
                continue
            }
            guard roleByKey[key] == nil,
                  !claimsBuiltIn,
                  let name = string(object["displayName"])?.trimmed,
                  !name.isEmpty,
                  let prompt = string(object["systemPrompt"])?.trimmed,
                  !prompt.isEmpty else {
                throw KINPortableArchiveError.invalidArchive
            }
            let role = RoleProjection(
                rawID: rawID,
                id: stableUUID(scope: "role", rawID: rawID),
                name: name,
                prompt: prompt,
                createdAtMillis: int64(object["createdAtMillis"]) ?? 0,
                archived: bool(object["isArchived"]) ?? false
            )
            roles.append(role)
            roleByKey[key] = role
        }

        let attachments = try attachmentMap(from: root)
        let rawEvents = objectArray(root["chatEvents"])
        try requireUnique(rawEvents.compactMap { string($0["id"])?.trimmed }, expected: rawEvents.count)
        let visibleEvents = try rawEvents.filter { object in
            guard let kind = string(object["kind"]) else {
                throw KINPortableArchiveError.invalidArchive
            }
            switch kind {
            case "MESSAGE", "COMPLETED", "FAILED", "CANCELLED": return true
            case "REQUEST_STARTED", "DELTA", "RETRY_REQUESTED": return false
            default: throw KINPortableArchiveError.invalidArchive
            }
        }

        var eventIDByRaw = [String: UUID]()
        for object in visibleEvents {
            guard let rawID = string(object["id"])?.trimmed, !rawID.isEmpty else {
                throw KINPortableArchiveError.invalidArchive
            }
            eventIDByRaw[canonicalID(rawID)] = stableUUID(scope: "event", rawID: rawID)
        }

        struct ConversationProjection {
            let id: UUID
            let rawID: String
            let role: RoleProjection
            var createdAtMillis: Int64
            var updatedAtMillis: Int64
        }
        var conversationsByKey = [String: ConversationProjection]()
        for event in visibleEvents {
            guard let rawConversationID = string(event["conversationId"])?.trimmed,
                  !rawConversationID.isEmpty,
                  let rawRoleID = string(event["roleId"])?.trimmed,
                  let role = roleByKey[canonicalID(rawRoleID)] else {
                throw KINPortableArchiveError.invalidArchive
            }
            let createdAt = int64(event["createdAtMillis"]) ?? 0
            let key = conversationKey(rawConversationID, roleID: role.rawID)
            if var existing = conversationsByKey[key] {
                existing.createdAtMillis = min(existing.createdAtMillis, createdAt)
                existing.updatedAtMillis = max(existing.updatedAtMillis, createdAt)
                conversationsByKey[key] = existing
            } else {
                conversationsByKey[key] = ConversationProjection(
                    id: stableUUID(scope: "conversation", rawID: key),
                    rawID: rawConversationID,
                    role: role,
                    createdAtMillis: createdAt,
                    updatedAtMillis: createdAt
                )
            }
        }
        if conversationsByKey.isEmpty {
            let key = conversationKey("default", roleID: builtIn.rawID)
            conversationsByKey[key] = ConversationProjection(
                id: ayane.conversationID,
                rawID: "default",
                role: builtIn,
                createdAtMillis: 0,
                updatedAtMillis: 0
            )
        }

        let profileObjects = roles.map(profileObject)
        let profilesByKey = Dictionary(uniqueKeysWithValues: roles.map { (canonicalID($0.rawID), $0) })
        let relationshipInput = objectArray(root["relationships"])
        try requireUnique(
            relationshipInput.compactMap { string($0["roleId"])?.trimmed }.map(canonicalID),
            expected: relationshipInput.count
        )
        let relationshipByRole = Dictionary(uniqueKeysWithValues: relationshipInput.compactMap { object -> (String, [String: Any])? in
            guard let rawID = string(object["roleId"])?.trimmed else { return nil }
            return (canonicalID(rawID), object)
        })
        for key in relationshipByRole.keys where profilesByKey[key] == nil {
            throw KINPortableArchiveError.invalidArchive
        }
        let relationshipObjects = try roles.map { role in
            try relationshipObject(role: role, source: relationshipByRole[canonicalID(role.rawID)])
        }

        let conversationObjects = conversationsByKey.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { conversation in
                [
                    "id": conversation.id.uuidString,
                    "role_id": conversation.role.id.uuidString,
                    "title": conversation.role.name,
                    "created_at": dateString(conversation.createdAtMillis),
                    "updated_at": dateString(max(conversation.createdAtMillis, conversation.updatedAtMillis)),
                    "archived": conversation.role.archived
                ] as [String: Any]
            }

        var eventObjects = [[String: Any]]()
        for (index, event) in visibleEvents.enumerated() {
            guard let rawID = string(event["id"])?.trimmed,
                  let eventID = eventIDByRaw[canonicalID(rawID)],
                  let rawConversationID = string(event["conversationId"])?.trimmed,
                  let rawRoleID = string(event["roleId"])?.trimmed,
                  let role = roleByKey[canonicalID(rawRoleID)],
                  let conversation = conversationsByKey[conversationKey(rawConversationID, roleID: role.rawID)],
                  let author = string(event["author"]),
                  let kind = string(event["kind"]),
                  let status = string(event["status"]) else {
                throw KINPortableArchiveError.invalidArchive
            }
            let roleRaw: String
            switch author {
            case "USER": roleRaw = EventRole.user.rawValue
            case "ROLE": roleRaw = EventRole.assistant.rawValue
            case "SYSTEM": roleRaw = EventRole.system.rawValue
            default: throw KINPortableArchiveError.invalidArchive
            }
            var content = string(event["body"]) ?? ""
            if content.isEmpty, kind == "FAILED" {
                content = string(event["errorMessage"])?.trimmed.nonEmpty ?? "请求失败"
            } else if content.isEmpty, kind == "CANCELLED" {
                content = "请求已停止"
            }
            let delivery: String
            if kind == "FAILED" || status == "FAILED" {
                delivery = EventDeliveryState.failed.rawValue
            } else if kind == "CANCELLED" || status == "CANCELLED" {
                delivery = EventDeliveryState.cancelled.rawValue
            } else if status == "PENDING" {
                delivery = EventDeliveryState.streaming.rawValue
            } else if status == "PERSISTED" || status == "SENT" {
                delivery = EventDeliveryState.complete.rawValue
            } else {
                throw KINPortableArchiveError.invalidArchive
            }

            var object: [String: Any] = [
                "id": eventID.uuidString,
                "role_id": role.id.uuidString,
                "conversation_id": conversation.id.uuidString,
                "device_id": "portable-bridge",
                "device_sequence": index + 1,
                "logical_timestamp": "\(index + 1)-portable-bridge-\(eventID.uuidString.lowercased())",
                "occurred_at": dateString(int64(event["createdAtMillis"]) ?? 0),
                "recorded_at": dateString(int64(event["createdAtMillis"]) ?? 0),
                "role": roleRaw,
                "role_raw": roleRaw,
                "content": content,
                "content_hash": ContentHasher.sha256(content),
                "payload_kind": MessagePayloadKind.text.rawValue,
                "payload_kind_raw": MessagePayloadKind.text.rawValue,
                "sticker_id": "",
                "file_name": "",
                "file_type_identifier": "",
                "delivery_state": delivery,
                "delivery_state_raw": delivery,
                "redacted": false,
                "memory_processing_version": 0
            ]
            if let parentRaw = string(event["parentEventId"])?.trimmed,
               let parentID = eventIDByRaw[canonicalID(parentRaw)] {
                object["parent_event_id"] = parentID.uuidString
            }
            try applyAttachment(
                references: objectArray(event["attachmentRefs"]),
                attachments: attachments,
                to: &object
            )
            eventObjects.append(object)
        }

        let rawMemories = objectArray(root["memories"])
        try requireUnique(rawMemories.compactMap { string($0["id"])?.trimmed }, expected: rawMemories.count)
        var memoryObjects = [[String: Any]]()
        var tombstoneObjects = [[String: Any]]()
        for memory in rawMemories {
            guard let rawID = string(memory["id"])?.trimmed,
                  !rawID.isEmpty,
                  let rawRoleID = string(memory["roleId"])?.trimmed,
                  let role = roleByKey[canonicalID(rawRoleID)],
                  let text = string(memory["text"])?.trimmed,
                  !text.isEmpty,
                  let confidence = double(memory["confidence"]),
                  (0...1).contains(confidence) else {
                throw KINPortableArchiveError.invalidArchive
            }
            let createdAt = int64(memory["createdAtMillis"]) ?? 0
            let updatedAt = int64(memory["updatedAtMillis"]) ?? createdAt
            guard updatedAt >= createdAt else { throw KINPortableArchiveError.invalidArchive }
            let memoryID = stableUUID(scope: "memory", rawID: rawID)
            let canonicalKey = "portable:\(ContentHasher.sha256(text))"
            let tombstoned = bool(memory["isTombstoned"]) ?? false
            memoryObjects.append([
                "id": memoryID.uuidString,
                "role_id": role.id.uuidString,
                "kind": MemoryKind.profile.rawValue,
                "kind_raw": MemoryKind.profile.rawValue,
                "subject": "便携记忆",
                "predicate": "内容",
                "value": text,
                "canonical_key": canonicalKey,
                "state": tombstoned ? MemoryState.forgotten.rawValue : MemoryState.active.rawValue,
                "state_raw": tombstoned ? MemoryState.forgotten.rawValue : MemoryState.active.rawValue,
                "confidence": confidence,
                "importance": 0.5,
                "sensitive": false,
                "source_rank": 0,
                "observed_at": dateString(createdAt),
                "extractor_id": "kin-portable-v1",
                "schema_version": 1,
                "created_at": dateString(createdAt),
                "updated_at": dateString(updatedAt),
                "is_pinned": false,
                "user_verified": false,
                "device_id": "portable-bridge"
            ])
            if tombstoned {
                tombstoneObjects.append([
                    "id": stableUUID(scope: "memory-tombstone", rawID: rawID).uuidString,
                    "role_id": role.id.uuidString,
                    "entity_id": memoryID.uuidString,
                    "entity_type": "memory",
                    "canonical_key": canonicalKey,
                    "source_event_ids": [],
                    "deleted_at": dateString(updatedAt),
                    "device_id": "portable-bridge",
                    "reason": "portable-import"
                ])
            }
        }

        let settings: [String: Any] = [
            "provider": [
                "provider_id": NSNull(),
                "base_url": "",
                "model": "",
                "embedding_model": "",
                "temperature": 0.8,
                "streams_responses": true
            ],
            "memory": [
                "auto_extract_memory": true,
                "token_budget": 2_400,
                "recent_message_limit": 24,
                "raw_history_recall_enabled": true,
                "raw_history_token_budget": 1_000
            ],
            "persistence": ["cloud_sync_enabled": false],
            "humanized_reply_delay_enabled": true,
            "proactive_messages_enabled": true,
            "proactive_quiet_start_hour": 23,
            "proactive_quiet_end_hour": 8,
            "worldview_auto_match_enabled": true
        ]
        let exportedAtMillis = deterministicExportedAtMillis(from: root)
        let emptyCollectionKeys = [
            "evidence", "summaries", "friend_applications", "transitions",
            "moment_tasks", "moment_posts", "moment_interactions",
            "conversation_read_states", "moment_read_states",
            "moment_ai_interaction_tasks", "group_conversations",
            "group_participants", "chat_turn_presentations",
            "proactive_message_tasks"
        ]
        var output: [String: Any] = [
            "schema_version": AyaneDataExport.currentSchemaVersion,
            // The KMP v1 payload has no separate export timestamp. Use its
            // newest durable record timestamp so importing the exact same
            // authenticated archive always yields the same summary.
            "exported_at": dateString(exportedAtMillis),
            "conversations": conversationObjects,
            "events": eventObjects,
            "memories": memoryObjects,
            "tombstones": tombstoneObjects,
            "profiles": profileObjects,
            "persona": profileObjects[0],
            "relationships": relationshipObjects,
            "settings": settings,
            // Retain a non-secret provenance hint only inside the authenticated
            // payload; no local device or account identifier is introduced.
            "portable_export_id": exportID
        ]
        for key in emptyCollectionKeys { output[key] = [] }
        guard JSONSerialization.isValidJSONObject(output) else {
            throw KINPortableArchiveError.invalidArchive
        }
        return output
    }

    private static func profileObject(_ role: RoleProjection) -> [String: Any] {
        [
            "id": role.id.uuidString,
            "role_id": role.id.uuidString,
            "world_profile_id": WorldProfileRecord.realityID.uuidString,
            "name": role.name,
            "user_name": UserIdentityPolicy.defaultAddress,
            "prompt": role.prompt,
            "created_at": dateString(role.createdAtMillis),
            "updated_at": dateString(role.createdAtMillis),
            "revision": 1,
            "device_id": "portable-bridge"
        ]
    }

    private static func relationshipObject(
        role: RoleProjection,
        source: [String: Any]?
    ) throws -> [String: Any] {
        let affinity = source.flatMap { integer($0["affinity"]) }
            ?? (role.id == RoleScope.legacyRoleID ? 100 : 0)
        guard (0...100).contains(affinity) else {
            throw KINPortableArchiveError.invalidArchive
        }
        let stage = source.flatMap { string($0["stage"]) } ?? "STRANGER"
        let validStages = ["STRANGER", "ACQUAINTANCE", "FRIEND", "CLOSE", "PARTNER", "ARCHIVED"]
        guard validStages.contains(stage) else { throw KINPortableArchiveError.invalidArchive }
        let archived = role.archived || stage == "ARCHIVED"
        let updatedAt = source.flatMap { int64($0["updatedAtMillis"]) } ?? role.createdAtMillis
        guard updatedAt >= role.createdAtMillis else {
            throw KINPortableArchiveError.invalidArchive
        }
        return [
            "id": stableUUID(scope: "relationship", rawID: role.rawID).uuidString,
            "role_id": role.id.uuidString,
            "state_raw": CompanionRelationshipState.accepted.rawValue,
            "harm_streak": 0,
            "hurt_score": 0.0,
            "harm_threshold": 3,
            "forgiveness_score": 0.0,
            "forgiveness_threshold": 2.0,
            "affinity_score": Double(affinity),
            "affinity_tier": min(3, affinity / 25),
            "affinity_policy_version": 1,
            "dignity": 0.5,
            "independence": 0.5,
            "boundary_sensitivity": 0.5,
            "apology_attempts": 0,
            "policy_version": 1,
            "created_at": dateString(role.createdAtMillis),
            "updated_at": dateString(updatedAt),
            "revision": 1,
            "device_id": "portable-bridge",
            "contact_membership_raw": archived
                ? ContactMembershipState.archivedByUser.rawValue
                : ContactMembershipState.active.rawValue,
            "contact_state_updated_at": dateString(updatedAt)
        ]
    }

    private static func attachmentMap(from root: [String: Any]) throws -> [String: AttachmentProjection] {
        let objects = objectArray(root["attachments"])
        var output = [String: AttachmentProjection]()
        for object in objects {
            guard let metadata = object["metadata"] as? [String: Any],
                  let rawID = string(metadata["id"])?.trimmed,
                  !rawID.isEmpty,
                  output[canonicalID(rawID)] == nil,
                  let fileName = string(metadata["fileName"])?.trimmed,
                  !fileName.isEmpty,
                  let mimeType = string(metadata["mimeType"])?.trimmed,
                  !mimeType.isEmpty,
                  let expectedHash = string(metadata["sha256"])?.lowercased(),
                  expectedHash.count == 64,
                  let contentHex = string(object["contentHex"]),
                  let bytes = dataFromHex(contentHex),
                  int64(metadata["byteSize"]) == Int64(bytes.count),
                  sha256(bytes).lowercased() == expectedHash else {
                throw KINPortableArchiveError.invalidArchive
            }
            output[canonicalID(rawID)] = AttachmentProjection(
                id: rawID,
                fileName: (fileName as NSString).lastPathComponent,
                mimeType: mimeType,
                sha256: expectedHash,
                bytes: bytes
            )
        }
        return output
    }

    private static func applyAttachment(
        references: [[String: Any]],
        attachments: [String: AttachmentProjection],
        to event: inout [String: Any]
    ) throws {
        guard references.count <= 1 else {
            // Apple v16 has one payload slot per message; silently dropping a
            // second file would violate the archive's all-or-nothing contract.
            throw KINPortableArchiveError.invalidArchive
        }
        guard let reference = references.first else { return }
        guard let rawID = string(reference["id"])?.trimmed,
              let expectedHash = string(reference["sha256"])?.lowercased(),
              let attachment = attachments[canonicalID(rawID)],
              attachment.sha256 == expectedHash else {
            throw KINPortableArchiveError.invalidArchive
        }
        if attachment.mimeType.lowercased().hasPrefix("image/") {
            event["payload_kind"] = MessagePayloadKind.image.rawValue
            event["payload_kind_raw"] = MessagePayloadKind.image.rawValue
            event["image_data"] = attachment.bytes.base64EncodedString()
        } else {
            event["payload_kind"] = MessagePayloadKind.file.rawValue
            event["payload_kind_raw"] = MessagePayloadKind.file.rawValue
            event["file_name"] = attachment.fileName
            event["file_type_identifier"] = attachment.mimeType
            event["file_data"] = attachment.bytes.base64EncodedString()
        }
    }

    private static func requireUnique(_ values: [String], expected: Int) throws {
        guard values.count == expected,
              Set(values.map(canonicalID)).count == values.count else {
            throw KINPortableArchiveError.invalidArchive
        }
    }

    private static func stableUUID(scope: String, rawID: String) -> UUID {
        if canonicalID(rawID) == canonicalID(RoleScope.legacyRoleID.uuidString) {
            return RoleScope.legacyRoleID
        }
        if let parsed = UUID(uuidString: rawID) { return parsed }
        var bytes = Array(SHA256.hash(data: Data("kin-portable-v1:\(scope):\(rawID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: value)!
    }

    private static func conversationKey(_ rawID: String, roleID: String) -> String {
        "\(canonicalID(roleID)):\(canonicalID(rawID))"
    }

    private static func canonicalID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func dateString(_ milliseconds: Int64) -> String {
        ISO8601DateFormatter().string(
            from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        )
    }

    private static func deterministicExportedAtMillis(from root: [String: Any]) -> Int64 {
        let fieldsByCollection: [(String, [String])] = [
            ("roles", ["createdAtMillis"]),
            ("relationships", ["updatedAtMillis"]),
            ("chatEvents", ["createdAtMillis"]),
            ("memories", ["createdAtMillis", "updatedAtMillis"])
        ]
        var timestamps = [Int64]()
        for (collection, fields) in fieldsByCollection {
            for object in objectArray(root[collection]) {
                for field in fields {
                    if let value = int64(object[field]) {
                        timestamps.append(value)
                    }
                }
            }
        }
        return timestamps.max() ?? 0
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func int64(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func objectArray(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func dataFromHex(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }
        var output = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            output.append(byte)
            index = next
        }
        return output
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension UTType {
    static var kinPortableBackup: UTType {
        UTType(exportedAs: "com.example.kin.portable-backup", conformingTo: .data)
    }
}

struct KINPortableArchiveDocument: FileDocument, Identifiable {
    static var readableContentTypes: [UTType] { [.kinPortableBackup] }

    let id = UUID()
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw KINPortableArchiveError.invalidArchive
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Small settings entry point for encrypted backups. The cryptographic and
/// import boundaries remain in `KINPortableArchiveV1`; this view only handles
/// password input and native file picking/exporting.
struct KINPortableArchiveSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var password = ""
    @State private var archiveDocument: KINPortableArchiveDocument?
    @State private var pendingArchive: Data?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("加密便携备份") {
                SecureField("备份密码", text: $password)
                    .textContentType(.password)
                Button("生成 .kinbackup", systemImage: "lock.doc") {
                    makeArchive()
                }
                .disabled(password.isEmpty || isWorking)
                Button("选择并检查 .kinbackup", systemImage: "folder") {
                    isImporting = true
                }
                .disabled(password.isEmpty || isWorking)
                if pendingArchive != nil {
                    Button("解密并恢复", role: .destructive) {
                        restoreArchive()
                    }
                    .disabled(password.isEmpty || isWorking)
                }
                Text("文件使用 PBKDF2-HMAC-SHA256（600000 次）与 AES-256-GCM 加密。API/OAuth、签名、CloudKit 日志、设备标识和向量索引不会进入便携备份；现有 JSON 导入仍可继续使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message {
                    Text(message)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("加密便携备份")
        .fileExporter(
            isPresented: $isExporting,
            document: archiveDocument,
            contentTypes: [.kinPortableBackup],
            defaultFilename: "kin-backup"
        ) { result in
            switch result {
            case .success:
                message = "加密便携备份已导出。"
            case .failure(let error):
                message = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.kinPortableBackup],
            allowsMultipleSelection: false
        ) { result in
            loadArchive(result)
        }
    }

    private func makeArchive() {
        isWorking = true
        defer { isWorking = false }
        do {
            archiveDocument = KINPortableArchiveDocument(
                data: try appModel.makePortableArchive(password: password)
            )
            isExporting = true
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func loadArchive(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = "读取失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let summary = try appModel.inspectPortableArchive(data, password: password)
                pendingArchive = data
                message = "校验通过：\(summary.totalIncludingSchemaV11) 条记录待恢复。"
            } catch {
                pendingArchive = nil
                message = "检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func restoreArchive() {
        guard let pendingArchive else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let summary = try await appModel.restorePortableArchive(
                    from: pendingArchive,
                    password: password
                )
                self.pendingArchive = nil
                self.message = "恢复完成：\(summary.totalIncludingSchemaV11) 条记录。"
            } catch {
                self.message = "恢复失败：\(error.localizedDescription)"
            }
        }
    }
}
