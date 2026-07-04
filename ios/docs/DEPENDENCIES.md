# Curio iOS — Dependencies

Swift Package Manager is the sole package manager (no CocoaPods, no Carthage).
Packages are declared in `ios/project.yml` (XcodeGen `packages:`) and linked
per-target under `dependencies:`. Regenerate the `.xcodeproj` with
`xcodegen generate` from `ios/`.

Deployment target: **iOS 26.0**. Swift language mode: **6** (strict concurrency `complete`).

---

## Swift Package Manager packages

### firebase-ios-sdk

| Field | Value |
| --- | --- |
| URL | `https://github.com/firebase/firebase-ios-sdk.git` |
| Version rule | **Up to Next Major** from `12.0.0` (`from: "12.0.0"`) |
| Min iOS supported | iOS 15+ (well below our 26.0 floor) |

**Products linked, by target**

| Product | Curio (app) | CurioIntents (App Intents ext) | CurioShareExtension |
| --- | :---: | :---: | :---: |
| `FirebaseCore` | ✅ | — | — |
| `FirebaseFirestore` | ✅ | ✅ | — |
| `FirebaseAuth` | ✅ | — | — |

Notes:
- `FirebaseFirestore` (SDK 11+) **already contains** the Codable support, plus the
  `@DocumentID` / `@ServerTimestamp` / `@ExplicitNull` property wrappers. **Do not**
  add or `import FirebaseFirestoreSwift` — that target was merged in and removed;
  `import FirebaseFirestore` is sufficient.
- `FirebaseCore` provides `FirebaseApp.configure()` (called once at app launch).
  Only the app target needs it; extensions reuse the configured app process state
  but should still call `FirebaseApp.configure()` defensively if they touch Firestore.
- `FirebaseAuth` backs the **anonymous-auth gate** that precedes every Firestore
  read/write in the sync manager (path-scoped per anonymous uid).
- The Share Extension does **no** Firestore work (tight memory/wall-clock budget); it
  only queues payloads into the App Group. All ingestion happens in the main app.

There are **no other SPM packages**. Every other Android library maps to a first-party
Apple framework already in the SDK (no package needed):

| Need | Framework (system, no SPM) |
| --- | --- |
| Persistence (Room) | SwiftData |
| Networking (Retrofit/OkHttp/Moshi) | Foundation `URLSession` + `Codable` |
| OAuth2 browser login | AuthenticationServices (`ASWebAuthenticationSession`) |
| PKCE / token crypto | CryptoKit + Security (Keychain) |
| OCR (ML Kit) | Vision (`RecognizeTextRequest`) |
| On-device embeddings | NaturalLanguage (`NLContextualEmbedding`) + CoreML |
| Background work (WorkManager) | BackgroundTasks (`BGTaskScheduler`) |
| App-agent exposure (AppFunctions) | App Intents |
| Share receive (ACTION_SEND) | App Extensions + App Groups + `NSItemProvider` |
| State (StateFlow/ViewModel) | Observation (`@Observable`) |
| UI (Compose/Material You) | SwiftUI + Liquid Glass (iOS 26) |
| Vector math | Accelerate (`vDSP`) |

---

## GoogleService-Info.plist setup

Firestore on Apple platforms is configured from a bundled `GoogleService-Info.plist`
(the runtime equivalent of Android's build-time `google-services.json`).

1. In the Firebase console, add an **iOS app** with bundle id **`com.curio.app`**.
2. Download **`GoogleService-Info.plist`**.
3. Place it at **`ios/Curio/GoogleService-Info.plist`** so it is picked up by the
   `Curio` target's `sources: [Curio]` glob and copied into the app bundle as a
   resource (verify it appears under *Copy Bundle Resources* after `xcodegen generate`).
4. It **must** be a resource of the **app** target. `FirebaseApp.configure()` reads it
   from `Bundle.main` at launch — call `configure()` **before** any
   `Firestore.firestore()` access. There is no API-key plist for the App Intents
   extension; it relies on the already-configured shared Firestore state (and calls
   `FirebaseApp.configure()` itself if it performs reads in its own process).
5. **Do not commit** the real `GoogleService-Info.plist` if it carries restricted keys;
   keep a templated/CI-injected copy. It contains the Firebase API key and project ids
   (not a secret per se, but treat per your security policy). Add it to `.gitignore`
   if your team injects it via CI.

Offline persistence is **on by default** for Firestore on Apple platforms; tune via
`FirestoreSettings` (cacheSettings) **before** the first `Firestore.firestore()` call
if needed.

---

## Secrets / build configuration (not SPM)

The following are injected via `Info.plist` / `.xcconfig` and read by
`CurioConfig` — they are **not** packages:

- `X_CLIENT_ID` (OAuth client id; `CLIENT_ID` fallback)
- `X_REDIRECT_URI` (`curio-oauth://callback`)
- `HF_TOKEN` (HuggingFace, for gated EmbeddingGemma download)
- `XAI_API_KEY` (optional build-time default; runtime value preferred from Keychain)

OAuth tokens and the runtime xAI key live only in the **Keychain** (shared via the
`keychain-access-groups` entitlement), never in `Info.plist`.
