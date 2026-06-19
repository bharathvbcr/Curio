# Changelog

All notable changes to the **Curio** bookmark assistant will be documented in this file.

## [Phase 0] — Scaffold & Theme System (Completed)
- **Aesthetic Definition**: Integrated the heavy high-contrast **Bold Typography** design guidelines combined with a frosted **Liquid-Glass** material skin.
- **Grids & Layouts**: Placed the core container structure using `GlassScaffold` paired with top/bottom bars and a shape-morphing `LiquidGlassFab`.
- **Adaptive Sizing**: Added three dynamic performance-conscious styling levels: `Full`, `Blur`, and `Solid` to support low-RAM devices gracefully.
- **Color System**: Aligned system palettes directly with deep high-contrast Material You configurations.

## [Phase 1] — Authentication (OAuth 2.0 PKCE) (Completed)
- **PKCE Flow Generator**: Configured high-entropy cryptographic verifiers and secure S256 code challenge generation.
- **Crypto-Secured Token Store**: Integrated `AES/GCM/NoPadding` encryption using Android's `KeyStore` provider to encrypt credentials inside Preferences DataStore.
- **Deep Link Callback Routing**: Implemented singleTask custom scheme `curio-oauth://callback` routing handled cleanly inside `MainActivity`.
- **Manual Dependency Injection**: Set up `AppContainer` pattern to enable constructor injection without KSP compile delays.
- **Session Control UI**: Created a Material 3 High-Fidelity Login display with real-time feedback and dynamic session checks.

## [Phase 2] — Local Caching & Sync Orchestration (Completed)
- **Room SQLite Layer**: Set up reactive `AppDatabase`, compiled with KSP compiler, exposing high-performance `Flow<List<Bookmark>>`.
- **Remote Integration**: Configured Retrofit mapping of X v2 Bookmark lists with cursors, custom pagination, and local persistence.
- **Defensive Error Handling**: Captured X v2 core API Rate Limits (`429`), parsed Epoch Reset intervals, and mapped lockout timers directly to client-facing count-downs.

## [Phase 3] — OCR & AI Curation Engine (Completed)
- **On-Device local ML Kit OCR**: Implemented full Latin-based Google ML Kit Text Recognition inside `OcrAnalyzer`, allowing users to parse text overlays directly from screenshot image documents.
- **Smart Dual-Mode AI Analyzer**: Developed dual-mode AI processing coordinating a local keyword classifier for offline use and cloud `xAI Grok` REST endpoints (`grok-3-mini` for analysis, `grok-3` for chat) inside `XAiAnalyzer`.
- **Curation Dashboard**: Built dynamic category tag cards, auto-scroll flow chips, curation action widgets, and database purge controls inside `BookmarkApp`.

## [Phase 4] — Search & Multi-Filter Queries (Completed)
- **High-Fidelity Text Querying**: Built reactive search filters scanning both raw bookmark text, local OCR text extractions, and curated AI summary cards.
- **Dynamic Category Sliding Rail**: Integrated a custom horizontal-scroll category selection bar with color-coded active states.
- **Dismissible Filter States**: Implemented an active criteria chip banner highlighting current queries, categories, or selected tags with instant "Clear All" feedback.

## [Phase 5] — Interactive Insights & Unified Data Filtering (Completed)
- **Global Metric Hero Cards**: Built high-contrast frosted stats panels mapping total records, AI-curated bookmarks, and OCR screenshot syncs.
- **Proportional Share Bars**: Generated colorful category distribution bar-charts reflecting actual SQLite frequencies.
- **Interactive Topic Tag Cloud**: Programmed an active FlowRow of tag chips in both Insights and Bookmark cards; tapping any topic tag instantly executes a direct query filter across the feed.

## [Phase 6] — Portability, Copy, Share, & Export (Completed)
- **High-Fidelity Backup & Schema Export**: Designed full JSON backup exports, creating a secure, serialized backup array of all bookmark, OCR, and AI metadata.
- **Quick-Curation Clipboard Copies**: Programmed an elegant copy icon on every bookmark card header to format and save curated AI details to the clipboard.
- **Native Context Sharing**: Integrated system-level android share dialog handlers to dispatch curated bookmark data and backup JSON files cleanly across other applications.

## [Phase 7] — Wiring Audit, Stabilization & Robolectric Unit Testing (Completed)
- **Stable Software Cryptographic Fallback**: Added a software-backed AES-GCM encryption fallback to token secure storage (`TokenStore`) for environments where the hardware `AndroidKeyStore` provider is absent (specifically during Robolectric JVM unit and screenshot tests).
- **Quality-of-Life Test Assertions**: Integrated a robust cryptographic roundtrip test suite in `ExampleRobolectricTest` to verify secure local session persistence.

## [Branding] — Adaptive App Icon & In-App Logo (Completed)
- **X-Theme Brand Mark**: Replaced the placeholder Android-robot launcher icon with a custom Curio mark — a bookmark ribbon with a knocked-out AI "spark" — rendered in the monochrome **X aesthetic** (flat near-black field, pure-white glyph) to echo the app's X-bookmark source.
- **Adaptive Iconography**: Authored vector `ic_launcher_background`, `ic_launcher_foreground`, and a dedicated `ic_launcher_monochrome` drawable, wired through the `mipmap-anydpi-v26` adaptive-icon configs with the mark held inside the 66dp safe zone so no launcher mask clips it.
- **Material You Themed Icons**: Added the proper `<monochrome>` silhouette so Android 13+ launchers re-tint the icon to the user's wallpaper palette — the previous config incorrectly pointed `monochrome` at the full-color foreground.
- **Legacy Raster Fallbacks**: Generated lossless `ic_launcher`/`ic_launcher_round` WebP bitmaps across `mdpi…xxxhdpi` for the API 24–25 devices that predate adaptive icons (`minSdk = 24`), plus a 512px Play Store listing icon.
- **Theme-Aware Compose Logo**: Introduced `CurioLogo` / `CurioLogoMark` components redrawing the identical 108-viewport mark on a Compose `Canvas`, tinting through `MaterialTheme.colorScheme` (light/dark + dynamic color); swapped the placeholder lock glyph in the OAuth login hero for the live brand mark.
- **Reproducible Asset Pipeline**: Added `tools/gen_logo_previews.py` and `tools/gen_launcher_rasters.py` so every icon density and the store asset regenerate from a single source geometry.



## [Compliance] — Checklist Verification Fixes

Brought the build into line with the master feature checklist's critical constraints and gaps.

### Critical constraints
- **minSdk 24 → 31**: dynamic color + RenderEffect glass both require API 31.
- **Foreground-only enrichment**: removed the background cloud-AI loop from `BookmarkSweeperService` (it summarized/classified via the xAI cloud on every bookmark with no user present). Enrichment now runs only from the foreground; the service keeps offline stale-link cleanup.
- **Accurate privacy disclosure**: the login screen no longer claims "on-device analysis guarantees total privacy". It now states OCR + token crypto are on-device while AI summaries/tags/chat use the xAI cloud, and only post text is sent on sync/analyze.
- **429 exponential backoff**: rate-limited pages now retry with exponential backoff honouring `x-rate-limit-reset`, surfacing `RateLimitException` only when the wait exceeds a 30s ceiling.

### Data layer
- **`includes`-join mapper**: bookmarks fetch + join `author_id → includes.users` (author name/handle), prefer `note_tweet.text` for long posts, expand `entities.urls.expanded_url`, and capture media `alt_text`. Added `user.fields`/`author_id` to the request; `max_results` default is now 100. Room bumped to v6 (`authorName`/`authorUsername`/`imageAltText`).
- **Named DAO queries**: `observeAll`, `search` (text/ocr/summary/title), `byCategory`, `categories`, `unenriched`.

### AI architecture
- **Device-gated generation behind an interface**: new `TextGenerator` interface with `CloudTextGenerator` (xAI), `LocalKeywordTextGenerator` (offline), and `NanoTextGenerator` (on-device, gated by `GenAiAvailability`/`FeatureStatus` + EN/JA/KO language gate + ~3k-word cap). `TextGeneratorSelector` is what gets injected and falls back to cloud whenever Nano is unavailable. Never assumes Nano is present.

### UI
- **Lifecycle-aware state**: `collectAsState` → `collectAsStateWithLifecycle` across all screens.
- **Type-safe navigation**: replaced stringly-typed routes with a `CurioDestination` enum and exhaustive `when` switching.
- **Haze glass**: `GlassScaffold` now drives blur from a single hoisted `HazeState` (`hazeSource` on content, `hazeEffect` on bars); skipped on the `Solid` tier. Compose BOM bumped to 2024.12.01.

### Testing
- Real coverage added: in-memory Room DAO test, `TextGeneratorSelector` + language-gating test (selector picks cloud when Nano unavailable), MockWebServer repository paging + 429 test, and a Compose login smoke test. Fixed the pre-existing `FakeBookmarkRepository` that no longer implemented the Phase 12 interface (unit tests didn't compile).

### Dependency injection
- **Koin wired** (the checklist's "Hilt DI **(or Koin)**"): `startKoin` in `CurioApplication` with an `appModule` exposing the graph from the single `AppContainer` composition root; repositories bound to their interfaces; `MainActivity` resolves ViewModels via Koin `by viewModel()`. Koin (pure-runtime, no annotation processor/plugin) was chosen over Hilt to avoid the unproven Hilt × AGP 9.1.1 toolchain risk while still satisfying the framework-DI requirement.

### Embeddings
- **Device-gated EmbeddingGemma behind an interface**: new `EmbeddingProvider` interface with `EmbeddingService` as the cloud impl, `OnDeviceEmbeddingProvider` (gated by `EmbeddingAvailability` — detects the on-device EmbeddingGemma/MediaPipe runtime), and `EmbeddingProviderSelector` that prefers on-device when present and falls back to cloud. The selector is injected (via Koin) into the ViewModel. The ~200MB EmbeddingGemma model itself is not bundled, but the availability gate + fallback + interface are final so the on-device model drops in without further wiring.

## [Bugfix] — Bookmark Sync Pagination & Hang
- **Fetch all bookmarks, not just 10**: `syncBookmarks` issued a single X API request capped at `max_results=10`. It now paginates through `meta.next_token` (100 per page, up to 10 pages per sync) and persists each page as it arrives, so a full library is retrieved instead of only the first 10 entries. The "NEXT PAGE" action still resumes from the saved cursor for libraries beyond the per-sync cap.
- **Stop the endless "Synchronizing…" spinner**: The sync ran Firebase pull → X API → Firebase push sequentially, and the Firestore calls (built on mock credentials) used an unbounded `awaitTask()` that could hang forever — blocking the X fetch entirely and pinning the UI on `Loading`. Firebase pull/push are now bounded by a 15s timeout (`withTimeoutOrNull`), so a stalled Firestore call no longer blocks the X sync or wedges the loading state.
- **Auto-refresh expired X access tokens**: X OAuth access tokens expire after ~2 hours. The `XAuthApi.refreshToken` endpoint and `TokenStore.getRefreshToken()` existed but were never called, so once the token expired the bookmarks API returned 401, was swallowed as a generic error, and sync reported "Synchronized successfully" while silently fetching nothing. `syncBookmarks` now catches a 401 mid-pagination, exchanges the stored refresh token for a new access token (persisting the rotated refresh token), and retries — using the same `client_id` resolution as login so the refresh is accepted. Genuine re-login is only required when the refresh token itself has expired.
