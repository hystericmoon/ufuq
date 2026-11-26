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

    @Test fun pickAssetNeedsNoSignature() {
        val apk = { v: String -> "ufuq-$v.apk" }
        fun apkRelease(tag: String, pre: Boolean = false, withApk: Boolean = true) = """
            {"tag_name":"$tag","body":"n","prerelease":$pre,"assets":[
            ${if (withApk) """{"name":"ufuq-${tag.removePrefix("v")}.apk","browser_download_url":"https://github.com/x/y/releases/download/$tag/ufuq-${tag.removePrefix("v")}.apk","size":9,"digest":"sha256:$hash"}""" else """{"name":"Ufuq-${tag.removePrefix("v")}.dmg","browser_download_url":"https://github.com/x/y/a.dmg","size":1}"""}
            ]}"""
        val list = assertNotNull(GitHubReleases.parseList("[" + listOf(apkRelease("v0.4.0", withApk = false), apkRelease("v0.3.0-beta.1", pre = true), apkRelease("v0.2.0"), apkRelease("v0.1.0")).joinToString(",") + "]"))
        // 0.4.0 has no APK yet (Mac files uploaded first): skipped, not half-offered.
        val stable = assertNotNull(GitHubReleases.pickAsset(list, "0.1.0", includePreReleases = false, assetName = apk))
        assertEquals("0.2.0", stable.version)
        assertEquals("ufuq-0.2.0.apk", stable.asset.name)
        assertEquals(hash, stable.asset.sha256)
        assertEquals("0.3.0-beta.1", GitHubReleases.pickAsset(list, "0.1.0", includePreReleases = true, assetName = apk)?.version)
        assertNull(GitHubReleases.pickAsset(list, "0.3.0", includePreReleases = true, assetName = apk))
        // The Windows picker still requires its .sig, so an APK-only release is not offered there.
        assertNull(GitHubReleases.pick(list, "0.1.0", includePreReleases = true, installerName = apk))
    }
}
