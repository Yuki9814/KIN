# KIN portable archive contract

This document is the cross-language contract for version 1. The KMP
implementation is the canonical writer. It does not claim that its JSON
payload is an Apple AyaneDataExport document.

## Outer wire format

The bytes are laid out in this order:

    ASCII("KINPortableArchiveV1") || 0x01 || salt[16] || nonce[12] || AES-GCM(ciphertext || tag[16])

AES-GCM uses a 256-bit key derived with PBKDF2-HMAC-SHA256, 600000
iterations. The complete prefix through nonce is the AAD. Salt and nonce are
random for normal exports; tests may provide fixed values. Wrong passwords,
changed headers, changed ciphertext, truncation and unsupported versions must
fail before any data is written.

## Canonical payload

After decryption, the UTF-8 JSON object has exactly these top-level fields:

    format: "KINPortableArchiveV1"
    schemaVersion: 1
    exportId: non-empty string
    roles: Role[]
    relationships: RelationshipState[]
    chatEvents: ChatEvent[]
    memories: MemoryRecord[]
    settings: AppSettings
    attachments: PortableAttachmentV1[]

All IDs are opaque strings. The built-in role ID is always
8D5DFB45-198D-4B74-B1F1-4C9C7A8248A1; an archive may not replace it. API
keys, OAuth tokens, device IDs, embeddings or derived indexes are not fields
in this payload. Attachment bytes are optional only for metadata-only
inspection, and are represented as lowercase contentHex when included; the
SHA-256 and byte size must match at import.

chatEvents is append-only. MESSAGE, REQUEST_STARTED, DELTA, COMPLETED,
FAILED, CANCELLED and RETRY_REQUESTED are lifecycle records, not mutable
message updates. A Swift bridge may collapse DELTA and REQUEST_STARTED rows
when presenting/importing user-visible messages, but must retain COMPLETED,
FAILED and CANCELLED semantics. KMP itself keeps all rows.

## Apple compatibility mapping

ArchivePayloadCodec.decodePortableOrApple accepts sanitized Apple
AyaneDataExport schema versions 4 through 18 as a one-way input adapter:

- profiles (or legacy persona) become custom Role records; the stable Ayane
  profile is filtered because KMP provisions it locally.
- relationships uses affinity_score (or the legacy tier) and maps to the KMP
  stage thresholds. Schema v18 may additionally contain the optional
  `manual_affinity_score`; KMP's RelationshipState has no manual-affinity
  field, so the adapter safely ignores that value and does not claim to
  preserve it for an Apple round-trip.
- events become append-only MESSAGE records. role/role_raw, delivery state,
  parent event and ISO-8601 timestamps are retained.
- Base64 image_data and file_data become private hashed attachment
  metadata/content and event references.
- memories become role-scoped records; Apple memory tombstones mark or create
  tombstoned KMP records.
- Sanitized HTTPS provider URL/model values may be retained as display
  settings; credentials and OAuth state are never imported.
- Apple-only evidence, summaries, Moments, groups, proactive tasks, world
  profiles and account/device fields are ignored because KMP 0.1.5 has no
  corresponding model. In schema v17, `moment_interactions.deleted_at` is a
  sticky Apple-side tombstone; the safe-read adapter does not turn any Moments
  interaction (deleted or live) into a KMP chat event or memory, so an import
  cannot resurrect a deleted interaction. There is no KMP-side Moments DTO yet,
  so this boundary does not promise a Moments round-trip.

The reverse direction requires a Swift bridge that maps this canonical object
to an AyaneDataExport envelope and supplies empty Apple-only collections. It
is a schema conversion, not byte-for-byte or lossless round-trip
compatibility; in particular, the v18 manual affinity override is not
restored by a KMP import/export cycle. The reusable legacy/current fixtures are
sharedLogic/src/commonTest/resources/fixtures/apple_ayane_data_export_v16.json
and
sharedLogic/src/commonTest/resources/fixtures/apple_ayane_data_export_v17.json
and
sharedLogic/src/commonTest/resources/fixtures/kin_portable_payload_v1.json.
