package com.example

import android.app.Application
import com.example.di.AppContainer
import com.example.di.appModule
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.GlobalContext
import org.koin.core.context.startKoin

class CurioApplication : Application() {

    lateinit var appContainer: AppContainer
        private set

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
    }
}
