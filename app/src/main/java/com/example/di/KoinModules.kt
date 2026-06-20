package com.example.di

import com.example.data.XAiAnalyzer
import com.example.data.ai.TextGeneratorSelector
import com.example.data.embedding.EmbeddingProvider
import com.example.data.ocr.OcrAnalyzer
import com.example.data.source.SourceResolver
import com.example.domain.repo.AuthRepository
import com.example.domain.repo.BookmarkRepository
import com.example.domain.usecase.LoginUseCase
import com.example.ui.BookmarkViewModel
import com.example.ui.screens.auth.AuthViewModel
import org.koin.androidx.viewmodel.dsl.viewModel
import org.koin.dsl.module

/**
 * Koin DI graph. The object construction lives in [AppContainer] (single composition root); this
 * module exposes that graph to Koin so ViewModels and dependencies are resolved by the framework
 * (`by viewModel()` / `get()`) instead of hand-rolled factories. Repositories are bound to their
 * interfaces so call sites depend on abstractions, not implementations.
 */
fun appModule(container: AppContainer) = module {
    single<BookmarkRepository> { container.bookmarkRepository }
    single<AuthRepository> { container.authRepository }
    single { container.loginUseCase }
    single { container.ocrAnalyzer }
    single { container.aiAnalyzer }
    single { container.grokImageService }
    single<EmbeddingProvider> { container.embeddingProvider }
    single { container.embeddingModelManager }
    single { container.sourceResolver }
    single { container.textGenerator }
    single { container.tokenStore }

    viewModel {
        BookmarkViewModel(
            get<BookmarkRepository>(),
            get<OcrAnalyzer>(),
            get<XAiAnalyzer>(),
            get<EmbeddingProvider>(),
            get<SourceResolver>(),
            get<TextGeneratorSelector>(),
            get<com.example.data.GrokImageService>(),
            get<com.example.data.embedding.EmbeddingModelManager>(),
            get<com.example.data.remote.TokenStore>()
        )
    }
    viewModel { AuthViewModel(get<LoginUseCase>(), get<AuthRepository>()) }
}
