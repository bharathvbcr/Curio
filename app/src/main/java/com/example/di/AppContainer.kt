package com.example.di

import android.content.Context
import com.example.BuildConfig
import com.example.data.embedding.EmbeddingService
import com.example.data.remote.ArxivClient
import com.example.data.remote.GithubApi
import com.example.data.remote.HuggingFaceApi
import com.example.data.remote.TokenStore
import com.example.data.remote.XAuthApi
import com.example.data.remote.XAiApi
import com.example.data.repo.AuthRepositoryImpl
import com.example.data.source.SourceResolver
import com.example.domain.repo.AuthRepository
import com.example.domain.usecase.LoginUseCase
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.util.concurrent.TimeUnit

class AppContainer(private val context: Context) {

    val tokenStore: TokenStore by lazy {
        TokenStore(context.applicationContext)
    }

    private val moshi: Moshi by lazy {
        Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
    }

    // Separate debug logging interceptors — headers only (never body) to avoid leaking OAuth
    // tokens and the xAI Bearer key to logcat. Authorization header is always redacted.
    // Two distinct instances are required: OkHttp interceptors are stateful (they hold the
    // redacted-headers set) and sharing one instance across two clients risks concurrent
    // mutation if either client's builder modifies it after construction.
    private val mainLoggingInterceptor: HttpLoggingInterceptor by lazy {
        HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.HEADERS
                    else HttpLoggingInterceptor.Level.NONE
            redactHeader("Authorization")
        }
    }
    private val metadataLoggingInterceptor: HttpLoggingInterceptor by lazy {
        HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.HEADERS
                    else HttpLoggingInterceptor.Level.NONE
            redactHeader("Authorization")
        }
    }

    // Primary client used by xAI (long-running LLM calls) and X / Twitter APIs.
    // xAI streaming responses can take well over a minute, so 120 s read timeout.
    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder().apply {
            if (BuildConfig.DEBUG) addInterceptor(mainLoggingInterceptor)
        }
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    // Lightweight client for metadata APIs (ArXiv, Crossref, HuggingFace) that return small
    // JSON payloads quickly. Shorter timeouts surface network issues faster.
    private val metadataClient: OkHttpClient by lazy {
        OkHttpClient.Builder().apply {
            if (BuildConfig.DEBUG) addInterceptor(metadataLoggingInterceptor)
        }
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()
    }

    private val retrofit: Retrofit by lazy {
        Retrofit.Builder().baseUrl("https://api.twitter.com/")
            .client(okHttpClient).addConverterFactory(MoshiConverterFactory.create(moshi)).build()
    }

    private val xAiRetrofit: Retrofit by lazy {
        Retrofit.Builder().baseUrl("https://api.x.ai/")
            .client(okHttpClient).addConverterFactory(MoshiConverterFactory.create(moshi)).build()
    }

    private val githubRetrofit: Retrofit by lazy {
        Retrofit.Builder().baseUrl("https://api.github.com/")
            .client(okHttpClient).addConverterFactory(MoshiConverterFactory.create(moshi)).build()
    }

    private val huggingFaceRetrofit: Retrofit by lazy {
        Retrofit.Builder().baseUrl("https://huggingface.co/api/")
            .client(metadataClient).addConverterFactory(MoshiConverterFactory.create(moshi)).build()
    }

    private val xAuthApi: XAuthApi by lazy { retrofit.create(XAuthApi::class.java) }

    val authRepository: AuthRepository by lazy { AuthRepositoryImpl(xAuthApi, tokenStore) }
    val loginUseCase: LoginUseCase by lazy { LoginUseCase(authRepository) }

    val xAiApi: XAiApi by lazy { xAiRetrofit.create(XAiApi::class.java) }

    val ocrAnalyzer: com.example.data.ocr.OcrAnalyzer by lazy { com.example.data.ocr.OcrAnalyzer() }

    val aiAnalyzer: com.example.data.XAiAnalyzer by lazy {
        com.example.data.XAiAnalyzer(xAiApi)
    }

    val grokImageService: com.example.data.GrokImageService by lazy {
        com.example.data.GrokImageService(xAiApi)
    }

    // On-device-vs-cloud generation: device-gated selector is what gets injected.
    private val genAiAvailability: com.example.data.ai.GenAiAvailability by lazy {
        com.example.data.ai.GenAiAvailability(context.applicationContext)
    }
    private val cloudTextGenerator: com.example.data.ai.CloudTextGenerator by lazy {
        com.example.data.ai.CloudTextGenerator(aiAnalyzer)
    }
    private val localTextGenerator: com.example.data.ai.LocalKeywordTextGenerator by lazy {
        com.example.data.ai.LocalKeywordTextGenerator(aiAnalyzer)
    }
    private val nanoTextGenerator: com.example.data.ai.NanoTextGenerator by lazy {
        com.example.data.ai.NanoTextGenerator(genAiAvailability, localTextGenerator)
    }
    val textGenerator: com.example.data.ai.TextGeneratorSelector by lazy {
        com.example.data.ai.TextGeneratorSelector(
            nanoTextGenerator, cloudTextGenerator, localTextGenerator, genAiAvailability
        )
    }

    val embeddingService: EmbeddingService by lazy { EmbeddingService(xAiApi) }

    // On-device EmbeddingGemma (gated) with cloud fallback — the selector is what gets injected.
    val embeddingModelManager: com.example.data.embedding.EmbeddingModelManager by lazy {
        com.example.data.embedding.EmbeddingModelManager(context.applicationContext, tokenStore)
    }
    private val embeddingAvailability: com.example.data.embedding.EmbeddingAvailability by lazy {
        com.example.data.embedding.EmbeddingAvailability(embeddingModelManager)
    }
    // Exposed directly so the charging-gated index worker can embed on-device ONLY (no cloud fallback).
    val onDeviceEmbeddingProvider: com.example.data.embedding.OnDeviceEmbeddingProvider by lazy {
        com.example.data.embedding.OnDeviceEmbeddingProvider(embeddingAvailability, embeddingModelManager)
    }
    val embeddingProvider: com.example.data.embedding.EmbeddingProvider by lazy {
        com.example.data.embedding.EmbeddingProviderSelector(onDeviceEmbeddingProvider, embeddingService)
    }

    val arxivClient: ArxivClient by lazy { ArxivClient(metadataClient) }

    val crossrefClient: com.example.data.remote.CrossrefClient by lazy {
        com.example.data.remote.CrossrefClient(metadataClient)
    }

    private val githubApi: GithubApi by lazy { githubRetrofit.create(GithubApi::class.java) }

    private val huggingFaceApi: HuggingFaceApi by lazy {
        huggingFaceRetrofit.create(HuggingFaceApi::class.java)
    }

    val sourceResolver: SourceResolver by lazy {
        SourceResolver(arxivClient, githubApi, huggingFaceApi, crossrefClient)
    }

    val database: com.example.data.local.AppDatabase by lazy {
        com.example.data.local.AppDatabase.getDatabase(context.applicationContext)
    }

    val firebaseSyncManager: com.example.data.remote.FirebaseSyncManager by lazy {
        com.example.data.remote.FirebaseSyncManager(context.applicationContext)
    }

    private val xBookmarksApi: com.example.data.remote.XBookmarksApi by lazy {
        retrofit.create(com.example.data.remote.XBookmarksApi::class.java)
    }

    val bookmarkRepository: com.example.domain.repo.BookmarkRepository by lazy {
        com.example.data.repo.BookmarkRepositoryImpl(
            xBookmarksApi, database.bookmarkDao(), database.spaceDao(), tokenStore, firebaseSyncManager, xAuthApi
        )
    }

    /**
     * Release resources held by long-lived components. Call from Application.onTerminate() or
     * a lifecycle owner's onDestroy() to cancel the repository's background mirror scope.
     */
    fun close() {
        (bookmarkRepository as? com.example.data.repo.BookmarkRepositoryImpl)?.close()
    }
}
