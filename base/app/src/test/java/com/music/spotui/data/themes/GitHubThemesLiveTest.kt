package com.music.spotui.data.themes

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in contract check against the public upstream repository, not a hermetic unit test. */
class GitHubThemesLiveTest {
    @Test fun discoverAndConvertOfficialTheme() = runBlocking {
        assumeTrue(System.getenv("CELESTIFY_LIVE_THEMES_TEST") == "1")
        val candidates = GitHubThemes.discover("https://github.com/spicetify/spicetify-themes")
        assertTrue(candidates.isNotEmpty())
        val preview = GitHubThemes.preview(candidates.first { it.path == "Default" })
        assertTrue(preview.converted.schemes.isNotEmpty())
        assertEquals(ThemeCompatibility.PARTIAL, preview.converted.compatibility)
    }
}
