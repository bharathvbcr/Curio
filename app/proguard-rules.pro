# ─────────────────────────────────────────────────────────────────────────────
# Curio R8 / ProGuard rules.
#
# IMPORTANT: minify is now enabled. These keep rules cover the reflection-heavy
# libraries in this app (Moshi, Retrofit/OkHttp, Room, Koin, Firestore, ML Kit,
# AI-Edge localagents-rag). They MUST be validated with a real release build +
# end-to-end smoke test (auth → fetch → AI analysis → RAG search → export) before
# shipping, because this environment cannot compile/run R8.
# ─────────────────────────────────────────────────────────────────────────────

# Keep generic signatures, annotations and enclosing-method info (needed by Moshi,
# Retrofit and kotlin reflection to recover types after shrinking).
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# Preserve line numbers for readable crash reports, then hide the source file name.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile

# ── Kotlin ───────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }

# ── Moshi (codegen + kotlin-reflect adapter) ─────────────────────────────────
# Keep only the public API surface R8 cannot infer — narrows from the old blanket
# "-keep class com.squareup.moshi.** { *; }" that blocked all shrinking (build-16).
-keep class com.squareup.moshi.JsonAdapter { *; }
-keep class com.squareup.moshi.JsonReader { *; }
-keep class com.squareup.moshi.JsonWriter { *; }
-keep @com.squareup.moshi.JsonClass class * { *; }
-keepclassmembers class * { @com.squareup.moshi.FromJson *; @com.squareup.moshi.ToJson *; }
-dontwarn com.squareup.moshi.**
# Generated JsonAdapters.
-keep class **JsonAdapter { *; }
-keepnames @com.squareup.moshi.JsonClass class *
# Keep the fields of any @JsonClass model so reflective/codegen binding works.
-keepclassmembers @com.squareup.moshi.JsonClass class * { <fields>; <init>(...); }
# Keep @Json-annotated members and our DTOs (defensive — covers the reflect adapter).
-keepclassmembers class com.example.** {
    @com.squareup.moshi.Json <fields>;
}

# ── Retrofit + OkHttp ─────────────────────────────────────────────────────────
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keepclasseswithmembers,allowshrinking interface * { @retrofit2.http.* <methods>; }
-keep interface com.example.data.remote.** { @retrofit2.http.* <methods>; }
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.codehaus.mojo.animal_sniffer.*

# ── Room ─────────────────────────────────────────────────────────────────────
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep @androidx.room.Entity class * { *; }
-dontwarn androidx.room.paging.**

# ── Koin ─────────────────────────────────────────────────────────────────────
-keep class org.koin.** { *; }
-dontwarn org.koin.**

# ── Firebase Firestore ───────────────────────────────────────────────────────
# This app writes/reads Firestore via manual hashMapOf + getString (no reflective
# toObject POJO binding), so only the SDK keep rules from the AAR are needed.
-dontwarn com.google.firebase.messaging.**

# ── Google AI Edge localagents-rag + ML Kit ──────────────────────────────────
-keep class com.google.ai.edge.** { *; }
-dontwarn com.google.ai.edge.**
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# ── App models referenced reflectively by serialization ──────────────────────
-keep class com.example.domain.model.** { *; }
-keep class com.example.data.remote.**Dto { *; }

# ── AppFunctions ─────────────────────────────────────────────────────────────
# KSP-generated invokers call CurioFunctions by class reference from
# AppFunctionConfiguration; keep the class and all @AppFunction-annotated methods.
-keep class com.example.appfunctions.CurioFunctions { *; }
# Keep @AppFunctionSerializable models for schema-based serialisation.
-keep @androidx.appfunctions.AppFunctionSerializable class * { *; }
# KSP-generated aggregate inventory/invoker classes use $ names in internal package.
-keep class androidx.appfunctions.internal.$** { *; }
-keep class com.example.appfunctions.$** { *; }
-dontwarn androidx.appfunctions.**

# ── Room generated code ───────────────────────────────────────────────────────
-keep @androidx.room.Dao interface * { *; }
-keep class **_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
