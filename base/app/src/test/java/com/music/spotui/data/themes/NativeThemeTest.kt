package com.music.spotui.data.themes

import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder

class NativeThemeTest {
    @get:Rule val temporary = TemporaryFolder()
    private val ini = "[Midnight]\nmain=050507\nsidebar=12151D\ncard=1A1E28\ntext=F7F9FF\nsubtext=A8B2C3\nbutton=B9DEFF"
    private fun installed() = InstalledTheme("owner/repo/theme", "Theme", "Author", "owner/repo", "theme", "a".repeat(40), "Midnight", SpicetifyParser.parse(ini, null).schemes.getValue("Midnight"), ThemeCompatibility.PARTIAL)
    @Test fun colorFormats() {
        assertEquals(0xffaabbcc.toInt(), SpicetifyParser.color("#abc"))
        assertEquals(0xffaabbcc.toInt(), SpicetifyParser.color("AABBCC"))
        assertEquals(0xffaabbcc.toInt(), SpicetifyParser.color("170,187,204"))
        assertEquals(0xffaabbcc.toInt(), SpicetifyParser.color("rgb(170,187,204)"))
        assertNull(SpicetifyParser.color("256,0,0"))
        assertNull(SpicetifyParser.color("\${HOME}"))
    }
    @Test fun multipleSchemesAndComments() {
        val parsed = SpicetifyParser.parse("; note\n$ini\n[Gold]\nmain=080706\nbutton=E9D5A8 ; comment", null)
        assertEquals(setOf("Midnight", "Gold"), parsed.schemes.keys)
        assertEquals(ThemeCompatibility.PARTIAL, parsed.compatibility)
    }
    @Test fun lightSchemesStayDarkAndReadable() {
        val c = SpicetifyParser.parse("[Light]\nmain=ffffff\nsidebar=eeeeee\ncard=ffffff\ntext=000000\nsubtext=111111\nbutton=222222", null).schemes.getValue("Light")
        listOf(c.background, c.surface, c.elevated).forEach { bg ->
            assertTrue(SpicetifyParser.luminance(bg) <= .035)
            listOf(c.text, c.secondary, c.accent).forEach { assertTrue(SpicetifyParser.contrast(it, bg) >= 4.5) }
        }
    }
    @Test fun unsupportedCssCannotClaimFullCompatibility() {
        val parsed = SpicetifyParser.parse(ini, "body { display:none; background:url(https://evil.test/x); } @import 'bad';")
        assertEquals(ThemeCompatibility.PARTIAL, parsed.compatibility)
        assertEquals(SpicetifyParser.parse(ini, null).schemes, parsed.schemes)
    }
    @Test fun cssVariablesOnly() {
        assertEquals(ThemeCompatibility.PARTIAL, SpicetifyParser.parse(null, ":root { --spice-main:#050507; --spice-button: #B9DEFF; }").compatibility)
        assertEquals(ThemeCompatibility.UNSUPPORTED, SpicetifyParser.parse(null, "body { color:red; }").compatibility)
    }
    @Test fun explicitNativeManifest() {
        val native = """{"schema":1,"colors":{"background":"050507","surface":"12151D","elevated":"1A1E28","text":"F7F9FF","secondary":"A8B2C3","accent":"B9DEFF"}}"""
        assertEquals(ThemeCompatibility.FULL, SpicetifyParser.parse(null, null, native).compatibility)
        assertEquals(ThemeCompatibility.PARTIAL, SpicetifyParser.parse(null, "body{}", native).compatibility)
        assertThrows(Exception::class.java) { SpicetifyParser.parse(null, null, native.replace("\"schema\":1", "\"schema\":2")) }
    }
    @Test fun malformedAndArchiveInputRejected() {
        assertThrows(Exception::class.java) { SpicetifyParser.parse(null, null, "{broken") }
        assertThrows(IllegalArgumentException::class.java) { SpicetifyParser.parse("PK\u0003\u0004../../evil", null) }
        assertThrows(IllegalArgumentException::class.java) { SpicetifyParser.parse("x".repeat(SpicetifyParser.MAX_TEXT + 1), null) }
    }
    @Test fun repositoryAndPathValidation() {
        assertEquals("spicetify/spicetify-themes", GitHubThemes.repository("https://github.com/spicetify/spicetify-themes.git"))
        for (bad in listOf("https://evil.test/a/b", "https://github.com/user/repo/tree/main", "https://github.com/a/b?x=1", "https://github.com/a/..")) assertThrows(Exception::class.java) { GitHubThemes.repository(bad) }
        for (bad in listOf("../theme", "/absolute", "a/../../x", "a\\b", "C:/x")) assertFalse(GitHubThemes.validPath(bad))
    }
    @Test fun persistenceAndUpdatePreviewRemainIsolated() {
        val storage = ThemeStorage(temporary.newFolder())
        val old = installed()
        val update = old.copy(revision = "b".repeat(40))
        storage.write(ThemeSnapshot(listOf(update), old.id, old))
        val restored = storage.read()
        assertEquals(update, restored.installed.single())
        assertEquals(old, restored.active)
    }
    @Test fun failedInstallPreservesRegistry() {
        val storage = ThemeStorage(temporary.newFolder())
        val original = ThemeSnapshot(listOf(installed()), installed().id)
        storage.write(original)
        assertThrows(IllegalArgumentException::class.java) { storage.write(ThemeSnapshot(List(101) { installed() })) }
        assertEquals(original, storage.read())
    }
    @Test fun stagingWriteFailurePreservesAppliedTheme() {
        val directory = temporary.newFolder()
        val storage = ThemeStorage(directory)
        val original = ThemeSnapshot(listOf(installed()), installed().id, installed())
        storage.write(original)
        java.io.File(directory, "themes.tmp").mkdir()
        assertThrows(java.io.IOException::class.java) { storage.write(ThemeSnapshot()) }
        assertEquals(original, storage.read())
    }
}
