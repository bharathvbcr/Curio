<div align="center">

<img src="app/src/main/ic_launcher-playstore.png" width="120" alt="Curio app icon" />

# Curio

**On-device AI bookmark assistant** — OCR, automatic category sorting and summaries powered by xAI Grok, wrapped in a liquid-glass Material You theme.

</div>

---

## Features

- 📚 **Smart library** — save links, notes and screenshots; Curio reads them with on-device OCR.
- 🤖 **AI chat & summaries** — ask questions about your saved items and get concise answers powered by xAI Grok.
- 🗂️ **Automatic categories** — items are sorted into categories for you.
- 🎨 **Material You / liquid-glass UI** — dynamic color theming that adapts to your wallpaper.

## Screenshots

<div align="center">
<img src="playstore/01_library_feed.png" width="240" alt="Library feed" />
<img src="playstore/02_ai_chat.png" width="240" alt="AI chat" />
</div>

## Run locally

**Prerequisites:** [Android Studio](https://developer.android.com/studio)

1. Open the project in Android Studio and let it sync.
2. Create a `.env` file in the project root and set your xAI key (see [`.env.example`](.env.example)):
   ```
   XAI_API_KEY=your_key_here
   ```
   Get a key at [console.x.ai](https://console.x.ai).
3. Run on an emulator or a physical device.

## Tech

Kotlin · Jetpack Compose · Material 3 (Material You) · on-device OCR · xAI Grok API
