package com.example

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.data.embedding.EmbeddingBackend
import com.example.data.embedding.EmbeddingPreference
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class EmbeddingPreferenceTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("curio_embedding_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
    }

    @Test
    fun `defaults to AUTO when unset`() {
        assertEquals(EmbeddingBackend.AUTO, EmbeddingPreference.get(context))
    }

    @Test
    fun `persists backend choice`() {
        EmbeddingPreference.set(context, EmbeddingBackend.ON_DEVICE)
        assertEquals(EmbeddingBackend.ON_DEVICE, EmbeddingPreference.get(context))
        EmbeddingPreference.set(context, EmbeddingBackend.XAI)
        assertEquals(EmbeddingBackend.XAI, EmbeddingPreference.get(context))
    }

    @Test
    fun `unknown stored value falls back to AUTO`() {
        context.getSharedPreferences("curio_embedding_prefs", Context.MODE_PRIVATE)
            .edit().putString("embedding_backend", "NOT_A_BACKEND").commit()
        assertEquals(EmbeddingBackend.AUTO, EmbeddingPreference.get(context))
    }
}
