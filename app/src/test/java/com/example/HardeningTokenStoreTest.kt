package com.example

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.core.app.ApplicationProvider
import com.example.data.remote.TokenStore
import com.example.data.remote.tokenDataStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Adversarial-input tests for [TokenStore] crypto envelopes: a corrupted or hostile blob must
 * degrade to a null credential, never crash the process. The huge-IV case reproduces the one
 * genuinely crashing path (Int overflow at 4 + ivSize → ~2GB allocation → OutOfMemoryError,
 * uncatchable by catch(Exception)); the others pin down graceful degradation.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class HardeningTokenStoreTest {

    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val store = TokenStore(context)

    /** Builds a fake envelope: [4-byte big-endian length][payload bytes], Base64-encoded. */
    private fun blob(ivLen: Long, payload: Int): String {
        val buf = java.io.ByteArrayOutputStream()
        buf.write(((ivLen shr 24).toInt() and 0xFF))
        buf.write(((ivLen shr 16).toInt() and 0xFF))
        buf.write(((ivLen shr 8).toInt() and 0xFF))
        buf.write((ivLen.toInt() and 0xFF))
        buf.write(ByteArray(payload))
        return android.util.Base64.encodeToString(buf.toByteArray(), android.util.Base64.DEFAULT)
    }

    /** Persists a crafted envelope under the access-token key, then reads via [TokenStore.getAccessToken]. */
    private suspend fun decryptViaAccessSlot(envelopeBase64: String): String? {
        context.tokenDataStore.edit {
            it[stringPreferencesKey("access_token_surface")] = envelopeBase64
        }
        return store.getAccessToken()
    }

    @Test
    fun `roundtrip encrypt-decrypt survives`() = runBlocking {
        store.saveHuggingFaceToken("secret-token-value")
        assertEquals("secret-token-value", store.getHuggingFaceToken())
    }

    @Test
    fun `negative iv length returns null`() = runBlocking {
        // First header byte >= 0x80 makes the signed Int length negative. (Pre-fix this was
        // caught by catch(Exception) — guarded here so it can never regress to a crash.)
        assertNull(decryptViaAccessSlot(blob(0x80000000L, 32)))
    }

    @Test
    fun `huge iv length returns null not OOM`() = runBlocking {
        // 0x7FFFFFFF sits in the only band that crashes the old code: 4 + ivSize overflows
        // to a negative Int, so the old size check passes, then ByteArray(~2^31) attempts a
        // ~2GB allocation whose OutOfMemoryError the catch(Exception) guard cannot catch.
        assertNull(decryptViaAccessSlot(blob(0x7FFFFFFFL, 64)))
    }

    @Test
    fun `oversized but non-overflowing iv length returns null`() = runBlocking {
        assertNull(decryptViaAccessSlot(blob(4096L, 128)))
    }

    @Test
    fun `truncated envelope returns null`() = runBlocking {
        assertNull(decryptViaAccessSlot("QUJD")) // "ABC" — below the 4-byte header
    }

    @Test
    fun `non-base64 garbage returns null`() = runBlocking {
        assertNull(decryptViaAccessSlot("!!!!not-base64!!!!"))
    }
}
