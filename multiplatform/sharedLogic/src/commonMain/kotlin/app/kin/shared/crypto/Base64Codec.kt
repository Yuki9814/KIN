package app.kin.shared.crypto

/** Small dependency-free base64 codec used by the SSE client and archive fixtures. */
internal object Base64Codec {
    private const val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    fun encode(input: ByteArray): String {
        if (input.isEmpty()) return ""
        val out = StringBuilder((input.size + 2) / 3 * 4)
        var index = 0
        while (index < input.size) {
            val a = input[index++].toInt() and 0xff
            val hasB = index < input.size
            val b = if (hasB) input[index++].toInt() and 0xff else 0
            val hasC = index < input.size
            val c = if (hasC) input[index++].toInt() and 0xff else 0
            out.append(alphabet[a ushr 2])
            out.append(alphabet[((a and 0x03) shl 4) or (b ushr 4)])
            out.append(if (hasB) alphabet[((b and 0x0f) shl 2) or (c ushr 6)] else '=')
            out.append(if (hasC) alphabet[c and 0x3f] else '=')
        }
        return out.toString()
    }

    fun decode(input: String): ByteArray {
        val normalized = input.filterNot { it.isWhitespace() }
        require(normalized.length % 4 == 0) { "Invalid base64 length" }
        if (normalized.isEmpty()) return ByteArray(0)
        val out = ByteArray(normalized.length / 4 * 3 - when {
            normalized.endsWith("==") -> 2
            normalized.endsWith('=') -> 1
            else -> 0
        })
        var inIndex = 0
        var outIndex = 0
        fun value(c: Char): Int = when (c) {
            in alphabet -> alphabet.indexOf(c)
            '=' -> 0
            else -> error("Invalid base64 character")
        }
        while (inIndex < normalized.length) {
            val a = value(normalized[inIndex++])
            val b = value(normalized[inIndex++])
            val c = value(normalized[inIndex++])
            val d = value(normalized[inIndex++])
            if (outIndex < out.size) out[outIndex++] = ((a shl 2) or (b ushr 4)).toByte()
            if (outIndex < out.size) out[outIndex++] = (((b and 0x0f) shl 4) or (c ushr 2)).toByte()
            if (outIndex < out.size) out[outIndex++] = (((c and 0x03) shl 6) or d).toByte()
        }
        return out
    }
}

internal fun ByteArray.toLowerHex(): String {
    val digits = "0123456789abcdef"
    return buildString(size * 2) {
        for (byte in this@toLowerHex) {
            val value = byte.toInt() and 0xff
            append(digits[value ushr 4])
            append(digits[value and 0x0f])
        }
    }
}
