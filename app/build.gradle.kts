import java.util.Properties

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.compose)
  alias(libs.plugins.google.devtools.ksp)
  alias(libs.plugins.roborazzi)
  alias(libs.plugins.secrets)
}

android {
  namespace = "com.example"
  // compileSdk 37: required by androidx.appfunctions:appfunctions (AppFunctions). Compile-against
  // only — targetSdk (36) and minSdk (31) are unchanged, so runtime behavior/device support is the same.
  compileSdk { version = release(37) }

  defaultConfig {
    applicationId = "com.Curio.VBCR"
    // minSdk 31: dynamic color (Material You) and RenderEffect-based glass both require API 31.
    minSdk = 31
    targetSdk = 36
    // Play requires a strictly-increasing versionCode per upload. Override from CI/release
    // tooling via -PcurioVersionCode / -PcurioVersionName (or gradle.properties) without
    // editing this file; the defaults are the initial 1.0 release.
    versionCode = (project.findProperty("curioVersionCode") as String?)?.toInt() ?: 1
    versionName = (project.findProperty("curioVersionName") as String?) ?: "1.0"

    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

    // Load secrets dynamically for oauth and other features
    val localProperties = Properties()
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { stream ->
            localProperties.load(stream)
        }
    }
    val envProperties = Properties()
    val envFile = rootProject.file(".env")
    if (envFile.exists()) envFile.inputStream().use { envProperties.load(it) }

    // Treat blank and ROTATE_ME/placeholder values as unset — a cleared .env must fall through
    // to the default, not bake the literal placeholder into the OAuth client_id (X rejects the
    // authorize request with "you weren't given access to the app").
    fun secretOrNull(v: String?) =
        v?.takeIf { it.isNotBlank() && !it.startsWith("ROTATE") && !it.startsWith("MY_") }
    val xClientId = secretOrNull(localProperties.getProperty("X_CLIENT_ID"))
        ?: secretOrNull(envProperties.getProperty("CLIENT_ID"))
        ?: "S2l6bVJubWFrTmh1emUxYW45dmM6MTpjaQ"
    val xRedirectUri = localProperties.getProperty("X_REDIRECT_URI") ?: "curio-oauth://callback"

    buildConfigField("String", "X_CLIENT_ID", "\"$xClientId\"")
    buildConfigField("String", "X_REDIRECT_URI", "\"$xRedirectUri\"")
    // BYOK: the Hugging Face token (for the Gemma-license-gated EmbeddingGemma weights) and the
    // xAI API key are NOT baked into BuildConfig — users supply them at runtime in Settings and
    // they're stored encrypted on-device via TokenStore.
  }

  signingConfigs {
    create("release") {
      val keystorePath = System.getenv("KEYSTORE_PATH")
      // build-15: Warn loudly when KEYSTORE_PATH is absent so a misconfigured CI pipeline
      // never silently ships a release APK signed with debug/fallback credentials.
      if (keystorePath == null && gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
          logger.warn("WARNING: KEYSTORE_PATH not set — release build will use fallback path or fail at signing")
      }
      storeFile = file(keystorePath ?: "${rootDir}/my-upload-key.jks")
      storePassword = System.getenv("STORE_PASSWORD")
      keyAlias = "upload"
      keyPassword = System.getenv("KEY_PASSWORD")
    }
    create("debugConfig") {
      storeFile = file("${rootDir}/debug.keystore")
      storePassword = "android"
      keyAlias = "androiddebugkey"
      keyPassword = "android"
    }
  }

  buildTypes {
    release {
      isCrunchPngs = false
      // R8 code shrinking/obfuscation + resource shrinking. Keep rules live in
      // proguard-rules.pro. MUST be validated with a release build + end-to-end smoke
      // test (auth/fetch/AI/RAG/export) before shipping — this is the one change that
      // can only be confirmed by actually running R8.
      isMinifyEnabled = true
      isShrinkResources = true
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
      signingConfig = signingConfigs.getByName("release")
    }
    debug {
      signingConfig = signingConfigs.getByName("debugConfig")
    }
  }
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
  }
  buildFeatures {
    compose = true
    buildConfig = true
  }
  testOptions { unitTests { isIncludeAndroidResources = true } }
  lint {
    abortOnError = false
    checkReleaseBuilds = true
  }
}

// Align the Kotlin JVM target with Java 21 (compileOptions above). 21 is the floor for
// Robolectric's Android SDK 36 sandbox — on 17 every Robolectric test fails to even start.
kotlin {
  jvmToolchain(21)
}

// Configure the Secrets Gradle Plugin to use .env and .env.example files
// to match the convention used in Web projects.
secrets {
  propertiesFileName = ".env"
  defaultPropertiesFileName = ".env.example"
}

dependencies {
  implementation(platform(libs.androidx.compose.bom))
  implementation(platform(libs.firebase.bom))
  implementation(libs.androidx.activity.compose)
  implementation(libs.androidx.compose.material.icons.core)
  implementation(libs.androidx.compose.material.icons.extended)
  implementation(libs.androidx.compose.material3)
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.graphics)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.datastore.preferences)
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.lifecycle.viewmodel.compose)
  implementation(libs.androidx.navigation.compose)
  implementation(libs.androidx.room.ktx)
  implementation(libs.androidx.room.runtime)
  implementation(libs.coil.compose)
  implementation(libs.converter.moshi)
  implementation(libs.firebase.firestore)
  implementation(libs.firebase.auth)
  implementation(libs.haze)
  implementation(libs.koin.android)
  implementation(libs.koin.androidx.compose)
  implementation(libs.androidx.work.runtime.ktx)
  implementation(libs.localagents.rag)
  implementation(libs.kotlinx.coroutines.android)
  implementation(libs.kotlinx.coroutines.core)
  debugImplementation(libs.logging.interceptor)
  implementation(libs.moshi.kotlin)
  implementation(libs.okhttp)
  implementation(libs.retrofit)
  testImplementation(libs.androidx.compose.ui.test.junit4)
  testImplementation(libs.androidx.core)
  testImplementation(libs.androidx.junit)
  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation(libs.robolectric)
  testImplementation(libs.mockwebserver)
  testImplementation(libs.androidx.room.testing)
  // retrofit, converter.moshi, room.runtime, room.ktx are already on the compile classpath
  // (implementation above) and therefore visible to unit tests — no testImplementation duplicates needed.
  testImplementation(libs.roborazzi)
  testImplementation(libs.roborazzi.compose)
  testImplementation(libs.roborazzi.junit.rule)
  androidTestImplementation(platform(libs.androidx.compose.bom))
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  androidTestImplementation(libs.androidx.espresso.core)
  androidTestImplementation(libs.androidx.junit)
  androidTestImplementation(libs.androidx.runner)
  debugImplementation(libs.androidx.compose.ui.test.manifest)
  debugImplementation(libs.androidx.compose.ui.tooling)
  "ksp"(libs.androidx.room.compiler)
  "ksp"(libs.moshi.kotlin.codegen)
  "ksp"(libs.androidx.appfunctions.compiler)
  implementation(libs.androidx.appfunctions)
  implementation(libs.androidx.appfunctions.service)
  implementation(libs.play.services.mlkit.text.recognition)
}

ksp {
  arg("appfunctions:aggregateAppFunctions", "true")
  arg("room.schemaLocation", "$projectDir/schemas")
}
