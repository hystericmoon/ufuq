package app.ufuq.desktop.update

import java.util.Properties

/** Version and update key baked in by Gradle (`ufuq-build.properties`, generated from the repo-root VERSION). */
data class BuildInfo(val version: String, val updatePublicKey: String) {
    companion object {
        /** Full version for display and comparison, e.g. "0.2.0-beta.1"; "0.0.0" if the file is missing. */
        val current: BuildInfo by lazy {
            val p = Properties()
            runCatching { BuildInfo::class.java.getResourceAsStream("/ufuq-build.properties")?.use { p.load(it) } }
            BuildInfo(p.getProperty("version")?.trim().orEmpty().ifEmpty { "0.0.0" }, p.getProperty("updatePublicKey")?.trim().orEmpty())
        }
    }
}
