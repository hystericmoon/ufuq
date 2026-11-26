package app.ufuq.core.update

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** One file attached to a GitHub release. [sha256] is the hex digest GitHub reports, when it does. */
data class ReleaseAsset(val name: String, val url: String, val size: Long, val sha256: String?)

data class ReleaseInfo(
    val version: String,
    val notes: String,
    val prerelease: Boolean,
    val assets: List<ReleaseAsset>,
)

/** A newer release that has the installer and its detached signature. */
data class AvailableUpdate(
    val version: String,
    val notes: String,
    val installer: ReleaseAsset,
    val signature: ReleaseAsset,
)

@Serializable
private data class ReleaseJson(
    @SerialName("tag_name") val tag: String = "",
    val body: String? = null,
    val draft: Boolean = false,
    val prerelease: Boolean = false,
    val assets: List<AssetJson> = emptyList(),
)

@Serializable
private data class AssetJson(
    val name: String = "",
    @SerialName("browser_download_url") val url: String = "",
    val size: Long = 0,
    val digest: String? = null,
)

object GitHubReleases {
    private val format = Json { ignoreUnknownKeys = true }

    /** Versions end up in file names, so only these characters are accepted. */
    private val SAFE_VERSION = Regex("^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$")

    /** The `/releases/latest` response; null when it is not a release. */
    fun parseLatest(json: String): ReleaseInfo? =
        runCatching { format.decodeFromString<ReleaseJson>(json) }.getOrNull()?.let(::toInfo)

    /** The `/releases` list (pre-releases included); null when it is not a list. Drafts are dropped. */
    fun parseList(json: String): List<ReleaseInfo>? =
        runCatching { format.decodeFromString<List<ReleaseJson>>(json) }.getOrNull()?.mapNotNull(::toInfo)

    private fun toInfo(r: ReleaseJson): ReleaseInfo? {
        if (r.draft) return null
        val version = r.tag.trim().removePrefix("v").removePrefix("V")
        if (!SAFE_VERSION.matches(version) || Versions.parse(version) == null) return null
        val assets = r.assets.filter { it.name.isNotEmpty() && it.url.startsWith("https://") }.map {
            ReleaseAsset(it.name, it.url, it.size, it.digest?.takeIf { d -> d.startsWith("sha256:", ignoreCase = true) }?.substringAfter(':')?.lowercase()?.takeIf { h -> h.matches(Regex("[0-9a-f]{64}")) })
        }
        return ReleaseInfo(version, r.body.orEmpty().trim(), r.prerelease, assets)
    }

    /**
     * The newest release that is newer than [currentVersion] and carries `<installerName(version)>` and
     * `<installerName(version)>.sig`. A release missing either asset is skipped, never half-offered.
     * Pre-releases only count when [includePreReleases].
     */
    fun pick(
        releases: List<ReleaseInfo>,
        currentVersion: String,
        includePreReleases: Boolean,
        installerName: (String) -> String,
    ): AvailableUpdate? = releases
        .filter { includePreReleases || !it.prerelease }
        .filter { Versions.isNewer(it.version, currentVersion) }
        .mapNotNull { r ->
            val name = installerName(r.version)
            val installer = r.assets.firstOrNull { it.name == name } ?: return@mapNotNull null
            val sig = r.assets.firstOrNull { it.name == "$name.sig" } ?: return@mapNotNull null
            AvailableUpdate(r.version, r.notes, installer, sig)
        }
        .reduceOrNull { best, next -> if (Versions.isNewer(next.version, best.version)) next else best }
}
