<div align="center">

<img src="app/src/main/ic_launcher-playstore.png" width="120" alt="Curio app icon" />

# Curio

**On-device AI bookmark assistant** — OCR, automatic category sorting and summaries powered by
xAI Grok, wrapped in a liquid-glass Material You theme.

</div>

---

Curio turns a messy pile of saved links and screenshots into a searchable, self-organizing
library. It reads your screenshots with **on-device OCR**, classifies and summarizes items with a
**dual-mode AI engine** (offline keyword classifier + xAI Grok in the cloud), and lets you
**chat** with your collection — all behind an adaptive, frosted **liquid-glass** interface.

## Features

- 📥 **Import & sync** — pull in your X (Twitter) bookmarks over the v2 API using a secure
  **OAuth 2.0 PKCE** flow, with cursor-based pagination and graceful `429` rate-limit handling
  (epoch reset parsed into a client-side countdown).
- 🔎 **On-device OCR** — Google ML Kit Latin text recognition extracts text from screenshots so
  image bookmarks become fully searchable.
- 🤖 **Dual-mode AI curation** — an offline keyword classifier for fast/local use plus xAI Grok
  in the cloud (`grok-3-mini` for analysis, `grok-3` for chat) for summaries and categorization.
- 💬 **Chat with your library** — ask questions about everything you've saved and get concise,
  grounded answers.
- 🗂️ **Self-organizing categories** — auto-tagged categories with a color-coded sliding rail and
  an interactive topic **tag cloud**; tap any tag to filter the feed instantly.
- 🔍 **Unified search** — a single query scans raw bookmark text, OCR extractions, and AI summaries.
- 📊 **Insights** — frosted hero metric cards, proportional category distribution bars, and tag
  analytics computed from your actual local data.
- 📦 **Portable** — full JSON backup/export of all bookmark, OCR, and AI metadata, plus one-tap
  clipboard copy of any curated card.
- 🎨 **Liquid-glass Material You** — dynamic color theming with three performance tiers
  (`Full` / `Blur` / `Solid`) so it degrades gracefully on low-RAM devices.

## Screenshots

<div align="center">
<img src="playstore/01_library_feed.png" width="240" alt="Library feed" />
<img src="playstore/02_ai_chat.png" width="240" alt="AI chat" />
</div>

## Architecture

Curio follows **Clean Architecture** with strict unidirectional data flow:

```
com.example.bookmarks
├── data/      # Retrofit (OAuth 2.0 PKCE) · Room database · repository implementations
├── domain/    # Pure-Kotlin models, repository interfaces, and use cases (no Android deps)
└── ui/        # Jetpack Compose — theme, reusable components, and screen-level state holders
```

Highlights:

- **Crypto-secured token store** — credentials are encrypted with `AES/GCM/NoPadding` keyed by the
  Android `KeyStore` and persisted in Preferences DataStore.
- **Reactive local cache** — Room exposes `Flow<List<Bookmark>>`; the UI renders immutable
  `UiState` objects.
- **Typed errors** — API, rate-limit, and auth failures compile into explicit sealed hierarchies.
- **Background work** — embedding indexing and bookmark sweeping run via WorkManager.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full guideline and [`CHANGELOG.md`](CHANGELOG.md)
for the phase-by-phase build history.

## Tech stack

Kotlin · Jetpack Compose (Material 3 / Material You) · Navigation Compose · Room · Koin DI ·
Retrofit · Coil · DataStore · WorkManager · Google ML Kit (OCR) · xAI Grok API · OAuth 2.0 PKCE

## Run locally

**Prerequisites:** JDK 17+ and the Android SDK (with `ANDROID_HOME`, or a `local.properties`
containing `sdk.dir`). minSdk per the app module.

1. Create a `.env` file in the project root and set your xAI key (see [`.env.example`](.env.example)):
   ```
   XAI_API_KEY=your_key_here
   ```
   Get a key at [console.x.ai](https://console.x.ai). The offline classifier and OCR work without it.
2. Build and run from the command line:
   ```bash
   ./gradlew :app:assembleDebug     # build the debug APK
   ./gradlew :app:installDebug      # build and install on a connected device/emulator
   ./gradlew :app:testDebugUnitTest # run the unit tests
   ```

> The release build references a signing config; for a plain debug run that line can be removed
> from `app/build.gradle.kts` if your environment has no release keystore configured.
