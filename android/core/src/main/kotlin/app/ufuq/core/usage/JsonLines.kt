package app.ufuq.core.usage

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.time.OffsetDateTime
import kotlin.math.abs
import kotlin.math.floor
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

internal object JsonLines {
    private const val DEPTH_LIMIT = 128

    /**
     * Calls [body] once per non-blank line: the parsed object, or null if the line is not a JSON
     * object. A final line with no trailing newline that fails to parse is a write in progress and
     * is not reported at all.
     */
    fun forEachObject(data: ByteArray, body: (JsonObject?) -> Unit) {
        var start = 0
        if (data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()) start = 3
        val endsWithNewline = data.size > start && data[data.size - 1] == NL
        // Non-empty slices [from, to), split on '\n'.
        var from = start
        while (from < data.size) {
            var to = from
            while (to < data.size && data[to] != NL) to++
            val next = to + 1
            if (to > from) {
                val isLast = lastNonEmptySliceEnds(data, to)
                if (!isBlank(data, from, to)) {
                    val obj = if (exceedsDepth(data, from, to)) null else parseObject(data, from, to)
                    if (!(obj == null && !endsWithNewline && isLast)) body(obj)
                }
            }
            from = next
        }
    }

    /** True when no non-empty slice follows the one ending at [end]. */
    private fun lastNonEmptySliceEnds(data: ByteArray, end: Int): Boolean {
        for (i in end until data.size) if (data[i] != NL) return false
        return true
    }

    fun objects(data: ByteArray): List<JsonObject?> = buildList { forEachObject(data) { add(it) } }

    private const val NL: Byte = 0x0A

    private fun isBlank(data: ByteArray, from: Int, to: Int): Boolean {
        for (i in from until to) {
            val b = data[i].toInt()
            if (b != 0x20 && b != 0x0D && b != 0x09) return false
        }
        return true
    }

    private fun parseObject(data: ByteArray, from: Int, to: Int): JsonObject? {
        val text = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(data, from, to - from)).toString()
        } catch (e: CharacterCodingException) {
            return null
        }
        return try {
            Json.parseToJsonElement(text) as? JsonObject
        } catch (e: Exception) { // SerializationException, IllegalArgumentException
            null
        } catch (e: StackOverflowError) {
            null
        }
    }

    /** Real log lines nest a few levels; refuse pathological nesting before it reaches the parser. */
    private fun exceedsDepth(data: ByteArray, from: Int, to: Int, limit: Int = DEPTH_LIMIT): Boolean {
        var depth = 0
        var inString = false
        var escaped = false
        for (i in from until to) {
            val b = data[i].toInt()
            if (inString) {
                if (escaped) escaped = false else if (b == 0x5C) escaped = true else if (b == 0x22) inString = false
                continue
            }
            when (b) {
                0x22 -> inString = true
                0x5B, 0x7B -> {
                    depth++
                    if (depth > limit) return true
                }
                0x5D, 0x7D -> depth--
            }
        }
        return false
    }

    /** A JSON number or numeric string as a Double; null for anything else (objects, null, booleans). */
    fun double(value: JsonElement?): Double? {
        val p = value as? JsonPrimitive ?: return null
        if (p is JsonNull) return null
        if (!p.isString && (p.content == "true" || p.content == "false")) return null
        return p.content.trim().toDoubleOrNull()
    }

    fun int(value: JsonElement?): Long? =
        double(value)?.takeIf { it.isFinite() && abs(it) < 1e15 }?.toLong()

    fun string(value: JsonElement?): String? = (value as? JsonPrimitive)?.takeIf { it.isString }?.content

    fun obj(value: JsonElement?): JsonObject? = value as? JsonObject

    /** Epoch seconds, or milliseconds when the value is too large to be seconds. */
    fun epochDate(value: Double): Instant? {
        if (!value.isFinite() || value <= 0) return null
        val seconds = if (value >= 1e11) value / 1000 else value
        if (seconds >= 1e11) return null
        val whole = floor(seconds)
        return Instant.ofEpochSecond(whole.toLong(), ((seconds - whole) * 1e9).toLong())
    }

    /** ISO 8601 string (any offset) or epoch number. */
    fun date(value: JsonElement?): Instant? {
        val p = value as? JsonPrimitive ?: return null
        if (p is JsonNull) return null
        if (p.isString) return date(p.content)
        return when (p.content) {
            "true", "false" -> null
            else -> p.content.toDoubleOrNull()?.let { epochDate(it) }
        }
    }

    fun date(s: String): Instant? =
        try {
            OffsetDateTime.parse(s).toInstant()
        } catch (e: java.time.DateTimeException) {
            null
        }
}
