package com.example

import android.app.Application
import androidx.appfunctions.service.AppFunctionConfiguration
import com.example.appfunctions.CurioFunctions
import com.example.di.AppContainer
import com.example.di.appModule
import org.koin.android.ext.koin.androidContext
import kotlinx.coroutines.launch
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin

class CurioApplication : Application(), AppFunctionConfiguration.Provider {

    lateinit var appContainer: AppContainer
        private set

    private val curioFunctions: CurioFunctions by lazy {
        CurioFunctions(
            bookmarkRepository = appContainer.bookmarkRepository,
            tokenStore = appContainer.tokenStore,
            chronosFlowBridge = appContainer.chronosFlowBridge,
        )
    }

    override val appFunctionConfiguration: AppFunctionConfiguration
        get() = AppFunctionConfiguration.Builder()
            .addEnclosingClassFactory(CurioFunctions::class.java) { curioFunctions }
            .build()

    override fun onCreate() {
        super.onCreate()
        appContainer = AppContainer(this)
        // Wire the Koin DI graph from the single composition root. Guarded so repeated
        // Application instantiation (e.g. across Robolectric test classes) can't double-start.
        if (GlobalContext.getOrNull() == null) {
            startKoin {
                androidContext(this@CurioApplication)
                modules(appModule(appContainer))
            }
        }

        // Register the charging-gated, on-device embedding backfill (no-op until the model is
        // downloaded and the user keeps it enabled). Guarded: WorkManager isn't initialized in unit
        // tests (the androidx.startup provider doesn't run), and a background-scheduling hiccup must
        // never take down app startup.
        runCatching { com.example.background.EmbeddingIndexScheduler.ensureScheduled(this) }
            .onFailure { android.util.Log.w("CurioApplication", "Embedding index scheduling skipped: ${it.message}") }

        // Register the periodic stale-link sweep (replaces the old foreground BookmarkSweeperService).
        // Same guard rationale as above: never let a background-scheduling hiccup take down startup.
        runCatching { com.example.background.BookmarkSweeperScheduler.ensureScheduled(this) }
            .onFailure { android.util.Log.w("CurioApplication", "Bookmark sweeper scheduling skipped: ${it.message}") }

        // Load any user-supplied xAI key (encrypted on disk) into the process-wide resolver, so the
        // app uses the user's own key instead of a build-time key baked into the APK.
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            runCatching {
                var storedKey = appContainer.tokenStore.getXaiKey()
                // Debug-only convenience for personal test builds: when no key has ever been saved,
                // seed the encrypted store once from .env (BuildConfig.XAI_API_KEY). Release builds
                // stay strictly BYOK — no key ships in the APK.
                if (storedKey.isNullOrBlank() && BuildConfig.DEBUG) {
                    val buildKey = BuildConfig.XAI_API_KEY
                    if (buildKey.startsWith("xai-")) {
                        appContainer.tokenStore.saveXaiKey(buildKey)
                        storedKey = buildKey
                        android.util.Log.i("CurioApplication", "Seeded xAI key from .env (debug build)")
                    }
                }
                com.example.data.XaiKeyStore.setRuntimeKey(storedKey)
            }.onFailure { android.util.Log.w("CurioApplication", "xAI key load skipped: ${it.message}") }
        }
    }
}
