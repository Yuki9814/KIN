package app.kin.shared.backup

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFails
import kotlin.test.assertTrue

class ArchiveCryptoGoldenVectorTest {
    @Test
    fun fixedCrossLanguageVectorMatches() {
        val plaintext = "{\"hello\":\"KIN\"}".encodeToByteArray()
        val salt = ByteArray(16) { it.toByte() }
        val nonce = ByteArray(12) { (it + 16).toByte() }
        val expected = "S0lOUG9ydGFibGVBcmNoaXZlVjEBAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaG0i3iR5WDNxglMfNULeEsmcndsNG9rX+3h8SeFy00dY="

        val archive = ArchiveCrypto.encrypt(plaintext, "test-password", salt, nonce)

        assertTrue(ArchiveCrypto.encodeForFixture(archive) == expected)
        assertContentEquals(plaintext, ArchiveCrypto.decrypt(archive, "test-password"))
    }

    @Test
    fun wrongPasswordAndTamperingFail() {
        val archive = ArchiveCrypto.encrypt("payload".encodeToByteArray(), "correct-password", ByteArray(16) { 3 }, ByteArray(12) { 7 })
        assertFails { ArchiveCrypto.decrypt(archive, "wrong-password") }
        val tampered = archive.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }
        assertFails { ArchiveCrypto.decrypt(tampered, "correct-password") }
    }
}
