package app.ufuq.core.update

/**
 * Dotted versions with an optional pre-release suffix, ordered like SemVer:
 * 0.6.0-beta.1 < 0.6.0-beta.2 < 0.6.0 < 0.6.1.
 */
object Versions {
    fun parse(raw: String): List<Int>? {
        val core = raw.trim().removePrefix("v").removePrefix("V").substringBefore('-').substringBefore('+')
        if (core.isEmpty()) return null
        return core.split('.').map { it.toIntOrNull() ?: return null }
    }

    /** "beta.2" becomes ["beta", "2"]; empty for a final release. */
    private fun preRelease(raw: String): List<String> =
        raw.trim().substringBefore('+').substringAfter('-', "").split('.').filter { it.isNotEmpty() }

    fun isPreRelease(raw: String): Boolean = preRelease(raw).isNotEmpty()

    /** Drops a leading "v" and any pre-release or build suffix: "v1.2.3-beta.1" becomes "1.2.3". */
    fun numericCore(raw: String): String = raw.trim().removePrefix("v").removePrefix("V").substringBefore('-').substringBefore('+')

    /** True when [candidate] is strictly newer than [current]. An unparseable candidate is never newer. */
    fun isNewer(candidate: String, current: String): Boolean {
        val a = parse(candidate) ?: return false
        val b = parse(current) ?: return true
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        val pa = preRelease(candidate)
        val pb = preRelease(current)
        if (pa.isEmpty() || pb.isEmpty()) return pa.isEmpty() && pb.isNotEmpty()
        for (i in 0 until maxOf(pa.size, pb.size)) {
            val x = pa.getOrNull(i) ?: return false
            val y = pb.getOrNull(i) ?: return true
            if (x == y) continue
            val nx = x.toIntOrNull()
            val ny = y.toIntOrNull()
            return when {
                nx != null && ny != null -> nx > ny
                nx != null -> false
                ny != null -> true
                else -> x > y
            }
        }
        return false
    }
}
