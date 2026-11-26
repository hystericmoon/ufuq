package app.ufuq.core.sync

import java.time.Instant

object SyncFixtures {
    fun text(name: String): String =
        checkNotNull(SyncFixtures::class.java.getResourceAsStream("/fixtures/sync/$name")) { "missing fixture $name" }
            .use { it.readBytes().toString(Charsets.UTF_8) }

    /** The instant of `generatedAt` in `snapshot.json`. */
    val GENERATED: Instant = Instant.parse("2026-11-28T09:00:00Z")

    val KEY: ByteArray = ByteArray(32) { it.toByte() }
}

fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }

fun unhex(text: String): ByteArray = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
