package app.ufuq.android.media

/** The media session the island shows: one player's now-playing state, free of Android types. */
data class MediaState(
    val title: String,
    val artist: String? = null,
    /** 0 for a live stream or when the player does not say. */
    val durationMs: Long = 0,
    /** Position at [updatedAtElapsedMs] (SystemClock.elapsedRealtime). */
    val positionMs: Long = 0,
    val updatedAtElapsedMs: Long = 0,
    val speed: Float = 1f,
    val playing: Boolean = false,
    /** The player accepts seek requests. */
    val canSeek: Boolean = true,
    val packageName: String? = null,
) {
    /** The position now: the reported one, advanced by the time since while playing. */
    fun positionAt(elapsedNowMs: Long): Long {
        val advanced = if (playing) positionMs + ((elapsedNowMs - updatedAtElapsedMs).coerceAtLeast(0) * speed).toLong() else positionMs
        return if (durationMs > 0) advanced.coerceIn(0, durationMs) else advanced.coerceAtLeast(0)
    }

    /** 0..1 of the track played; 0 when the length is unknown. */
    fun fractionAt(elapsedNowMs: Long): Float =
        if (durationMs <= 0) 0f else (positionAt(elapsedNowMs).toFloat() / durationMs).coerceIn(0f, 1f)

    /** The seek bar works only when the player allows it and the length is known. */
    val seekable: Boolean get() = canSeek && durationMs > 0
}

object MediaFormat {
    /** "1:24", "0:05", "1:02:03". */
    fun clock(ms: Long): String {
        val total = (ms.coerceAtLeast(0)) / 1000
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    /** "1 minute 24 seconds", for TalkBack. */
    fun spoken(ms: Long): String {
        val total = (ms.coerceAtLeast(0)) / 1000
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        val parts = mutableListOf<String>()
        if (h > 0) parts += "$h ${if (h == 1L) "hour" else "hours"}"
        if (m > 0) parts += "$m ${if (m == 1L) "minute" else "minutes"}"
        if (s > 0 || parts.isEmpty()) parts += "$s ${if (s == 1L) "second" else "seconds"}"
        return parts.joinToString(" ")
    }

    /** The wing text: a note and the title cut to [max] characters. */
    fun wing(title: String, max: Int = 14): String {
        val t = title.trim()
        return "♪ " + if (t.length > max) t.take(max - 1).trimEnd() + "…" else t
    }
}
