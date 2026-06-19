package com.example

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.data.AnalysisResult
import com.example.data.ai.CloudTextGenerator
import com.example.data.ai.GenAiAvailability
import com.example.data.ai.LanguageGate
import com.example.data.ai.TextGenerator
import com.example.data.ai.TextGeneratorSelector
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Stub generator that tags its result with a label so we can assert which backend ran. */
private class LabelGenerator(private val label: String) : TextGenerator {
    override val name = label
    override suspend fun analyze(text: String, ocrText: String?, sourceAbstract: String?, imageUrl: String?): AnalysisResult =
        AnalysisResult(summary = label, tags = emptyList(), category = "other", entities = null, usedLocalAnalysis = label == "LOCAL")
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TextGeneratorSelectorTest {

    private fun selector(): TextGeneratorSelector {
        // On the JVM/Robolectric there is no AICore, so GenAiAvailability reports UNAVAILABLE —
        // exactly the "Nano not present" case the selector must handle by routing to cloud.
        val availability = GenAiAvailability(ApplicationProvider.getApplicationContext<Context>())
        return TextGeneratorSelector(
            nano = LabelGenerator("NANO"),
            cloud = LabelGenerator("CLOUD"),
            local = LabelGenerator("LOCAL"),
            availability = availability
        )
    }

    @Test
    fun `selector picks cloud when nano unavailable`() = runTest {
        val result = selector().analyze("Some English research text", null, null, forceLocal = false)
        assertEquals("CLOUD", result.summary)
    }

    @Test
    fun `selector picks local when user forces offline`() = runTest {
        val result = selector().analyze("Some English research text", null, null, forceLocal = true)
        assertEquals("LOCAL", result.summary)
    }

    @Test
    fun `language gate detects EN JA KO and rejects others`() {
        assertEquals(LanguageGate.Lang.EN, LanguageGate.detect("Linear-time sequence modeling"))
        assertEquals(LanguageGate.Lang.JA, LanguageGate.detect("これはテストです"))
        assertEquals(LanguageGate.Lang.KO, LanguageGate.detect("이것은 테스트입니다"))
        assertEquals(LanguageGate.Lang.OTHER, LanguageGate.detect("Это тест на русском"))
    }

    @Test
    fun `language gate enforces word cap`() {
        val short = "word ".repeat(100)
        val long = "word ".repeat(4_000)
        assert(LanguageGate.withinCap(short))
        assert(!LanguageGate.withinCap(long))
    }
}
