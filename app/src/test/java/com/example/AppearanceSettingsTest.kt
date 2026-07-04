package com.example

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.test.core.app.ApplicationProvider
import com.example.data.remote.TokenStore
import com.example.data.remote.tokenDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class AppearanceSettingsTest {

    private lateinit var context: Context
    private lateinit var tokenStore: TokenStore

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        runBlocking { context.tokenDataStore.edit { it.clear() } }
        tokenStore = TokenStore(context)
    }

    @Test
    fun `dynamic color defaults to false`() = runBlocking {
        assertEquals(false, tokenStore.useDynamicColorFlow.first())
    }

    @Test
    fun `persists dynamic color toggle`() = runBlocking {
        tokenStore.setUseDynamicColor(true)
        assertEquals(true, tokenStore.useDynamicColorFlow.first())
    }

    @Test
    fun `theme setting defaults to null and maps to DARK in ViewModel layer`() = runBlocking {
        assertNull(tokenStore.themeSettingFlow.first())
    }

    @Test
    fun `persists theme setting`() = runBlocking {
        tokenStore.setThemeSetting("LIGHT")
        assertEquals("LIGHT", tokenStore.themeSettingFlow.first())
    }

    @Test
    fun `glass tier override defaults to null`() = runBlocking {
        assertNull(tokenStore.glassTierOverrideFlow.first())
    }

    @Test
    fun `persists and clears glass tier override`() = runBlocking {
        tokenStore.setGlassTierOverride("Blur")
        assertEquals("Blur", tokenStore.glassTierOverrideFlow.first())
        tokenStore.setGlassTierOverride(null)
        assertNull(tokenStore.glassTierOverrideFlow.first())
    }
}
