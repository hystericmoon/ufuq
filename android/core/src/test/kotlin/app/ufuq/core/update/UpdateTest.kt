package app.ufuq.core.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UpdateTest {
    private val hash = "a".repeat(64)

    private fun release(tag: String, pre: Boolean = false, draft: Boolean = false, assets: Boolean = true, sig: Boolean = true, digest: String = "\"sha256:$hash\"") = """
        {"tag_name":"$tag","body":" notes ","draft":$draft,"prerelease":$pre,"assets":[
        ${if (assets) """{"name":"Ufuq-${tag.removePrefix("v")}.msi","browser_download_url":"https://github.com/x/y/releases/download/$tag/Ufuq-${tag.removePrefix("v")}.msi","size":123,"digest":$digest}""" else """{"name":"other.zip","browser_download_url":"https://e/o.zip"}"""}
        ${if (assets && sig) """,{"name":"Ufuq-${tag.removePrefix("v")}.msi.sig","browser_download_url":"https://github.com/x/y/releases/download/$tag/Ufuq-${tag.removePrefix("v")}.msi.sig","size":88}""" else ""}
        ]}"""

    private val name = { v: String -> "Ufuq-$v.msi" }

    @Test fun versionOrdering() {
        assertTrue(Versions.isNewer("0.2.0", "0.1.0"))
        assertTrue(Versions.isNewer("v0.10.0", "0.9.9"))
        assertFalse(Versions.isNewer("0.1.0", "0.1.0"))
        assertFalse(Versions.isNewer("0.1.0", "0.2.0"))
        assertTrue(Versions.isNewer("1.0.0", "1.0.0-beta.3"))
        assertFalse(Versions.isNewer("1.0.0-beta.3", "1.0.0"))
        assertTrue(Versions.isNewer("1.0.0-beta.10", "1.0.0-beta.2"))
        assertFalse(Versions.isNewer("garbage", "1.0.0"))
        assertTrue(Versions.isNewer("1.0", "0.9.9"))
        assertEquals("1.2.3", Versions.numericCore("v1.2.3-beta.1+7"))
    }

    @Test fun parsesLatest() {
        val info = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0")))
        assertEquals("0.2.0", info.version)
        assertEquals("notes", info.notes)
        assertEquals(hash, info.assets.first().sha256)
        val u = assertNotNull(GitHubReleases.pick(listOf(info), "0.1.0", false, name))
        assertEquals("Ufuq-0.2.0.msi.sig", u.signature.name)
        assertEquals(123, u.installer.size)
    }

    @Test fun missingDigestIsNull() {
        val info = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0", digest = "null")))
        assertNull(info.assets.first().sha256)
        val bad = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0", digest = "\"sha256:xyz\"")))
        assertNull(bad.assets.first().sha256)
    }

    @Test fun missingAssetsAreSkipped() {
        val noMsi = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0", assets = false)))
        assertNull(GitHubReleases.pick(listOf(noMsi), "0.1.0", false, name))
        val noSig = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0", sig = false)))
        assertNull(GitHubReleases.pick(listOf(noSig), "0.1.0", false, name))
    }

    @Test fun listPicksNewestAndHonoursBeta() {
        val json = "[" + listOf(release("v0.3.0-beta.1", pre = true), release("v0.2.0"), release("v0.4.0", draft = true), release("v0.1.0")).joinToString(",") + "]"
        val all = assertNotNull(GitHubReleases.parseList(json))
        assertEquals(3, all.size) // draft dropped
        assertEquals("0.3.0-beta.1", GitHubReleases.pick(all, "0.1.0", true, name)?.version)
        assertEquals("0.2.0", GitHubReleases.pick(all, "0.1.0", false, name)?.version)
        assertNull(GitHubReleases.pick(all, "0.3.0", false, name))
    }

    @Test fun malformedAndUnsafeInput() {
        assertNull(GitHubReleases.parseLatest("not json"))
        assertNull(GitHubReleases.parseList("{}"))
        assertNull(GitHubReleases.parseLatest(release("v..\\evil")))
        val http = assertNotNull(GitHubReleases.parseLatest(release("v0.2.0").replace("https://github.com", "http://github.com")))
        assertTrue(http.assets.isEmpty())
    }
}
