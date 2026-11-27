package app.ufuq.core

import java.time.Instant

val T0: Instant = Instant.ofEpochSecond(1_800_000_000)

/** `t0 + 7.9` in the Swift tests. */
operator fun Instant.plus(seconds: Double): Instant = plusMillis(Math.round(seconds * 1000))
operator fun Instant.plus(seconds: Int): Instant = plusSeconds(seconds.toLong())
operator fun Instant.minus(seconds: Int): Instant = minusSeconds(seconds.toLong())
