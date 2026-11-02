package com.music.spotui.data.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateCheckerTest {
    @Test fun stableNoticesReachOlderVersionsAndBetaCanMoveToStable() {
        fun entry(tag:String, beta:Boolean=false,draft:Boolean=false)=org.json.JSONObject()
            .put("tag_name",tag).put("html_url","https://github.com/hinokame07/Celestify/releases/tag/$tag")
            .put("prerelease",beta).put("draft",draft)
        val entries=listOf(entry("v3.0.0",draft=true),entry("v2.4.4-beta.1",true),entry("v2.4.3"))
        val stable=UpdateChecker.selectRelease(entries,false)!!.version
        assertEquals("2.4.3",stable)
        for(old in listOf("2.2.0","2.3.0","2.3.1","2.4.0","2.4.1","2.4.2","2.4.3-beta.1"))
            assertTrue(UpdateChecker.isNewer(stable,old))
        assertEquals("2.4.4-beta.1",UpdateChecker.selectRelease(entries,true)?.version)
        assertEquals("2.4.3",UpdateChecker.selectRelease(listOf(entry("v2.4.3-beta.2",true),entry("v2.4.3")),true)?.version)
    }
    @Test fun comparesNumericallyNotAsText() {
        assertTrue(UpdateChecker.isNewer("1.10.0", "1.9.2"))
        assertTrue(UpdateChecker.isNewer("0.9.1", "0.9.0"))
        assertTrue(UpdateChecker.isNewer("1.0", "0.9.9"))
    }
    @Test fun sameOrOlderIsNotAnUpdate() {
        assertFalse(UpdateChecker.isNewer("0.9.0", "0.9.0"))
        assertFalse(UpdateChecker.isNewer("0.9", "0.9.0"))
        assertFalse(UpdateChecker.isNewer("0.8.9", "0.9.0"))
        assertFalse(UpdateChecker.isNewer("0.9.0-beta", "0.9.0"))
        assertTrue(UpdateChecker.isNewer("2.0.0", "2.0.0-beta.3"))
        assertTrue(UpdateChecker.isNewer("2.0.0-beta.2", "2.0.0-beta.1"))
        assertFalse(UpdateChecker.isNewer("2.0.0-beta.1", "2.0.0-beta.1"))
        assertTrue(UpdateChecker.isNewer("2.0.1-beta.1", "2.0.0"))
    }
    @Test fun ordersBetasAndReleases() {
        assertTrue(UpdateChecker.isNewer("2.0.2-beta.7", "2.0.2-beta.6"))
        assertFalse(UpdateChecker.isNewer("2.0.2-beta.6", "2.0.2-beta.7"))
        assertTrue(UpdateChecker.isNewer("2.0.2-beta.10", "2.0.2-beta.9"))
        assertTrue(UpdateChecker.isNewer("2.0.2", "2.0.2-beta.7"))
        assertFalse(UpdateChecker.isNewer("2.0.2-beta.7", "2.0.2"))
        assertTrue(UpdateChecker.isNewer("2.0.3-beta.1", "2.0.2"))
        assertTrue(UpdateChecker.isNewer("2.1.0-beta.1", "2.0.9"))
        assertTrue(UpdateChecker.isNewer("2.0.2-beta.1", "2.0.1-beta.9"))
    }
    @Test fun notesKeepTheChangelogSectionAsPlainLines() {
        val body = "- **Local Files**: a folder\n  - nested [link](https://x.y)\n\n**Full Changelog**: https://github.com/a/b/compare/v1...v2"
        assertEquals("• Local Files: a folder\n  • nested link", UpdateChecker.cleanNotes(body))
    }
    @Test fun findsTheReleaseApk() {
        val release = org.json.JSONObject("""{"assets":[
            {"name":"checksums.txt","browser_download_url":"https://x/c.txt"},
            {"name":"Celestify-2.0.0-beta.4.apk","browser_download_url":"https://x/myspoti.apk"}]}""")
        assertEquals("https://x/myspoti.apk", UpdateChecker.apkAsset(release))
        assertEquals("", UpdateChecker.apkAsset(org.json.JSONObject("{}")))
    }
}
