package com.example.data.remote

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// Preferences extension delegate
val Context.tokenDataStore: DataStore<Preferences> by preferencesDataStore(name = "curio_tokens")

/**
 * Persists and retrieves OAuth credentials using Keystore-backed AES-GCM encryption
 * over Jetpack Preferences DataStore.
 */
class TokenStore(private val context: Context) {

    companion object {
        private const val TAG = "TokenStore"
        private const val KEY_ALIAS = "CurioTokenStoreKey"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"

        private val KEY_ACCESS_TOKEN_SURFACE = stringPreferencesKey("access_token_surface")
        private val KEY_REFRESH_TOKEN_SURFACE = stringPreferencesKey("refresh_token_surface")
        private val KEY_USER_ID = stringPreferencesKey("user_id")
        private val KEY_USERNAME = stringPreferencesKey("user_username")
        private val KEY_NAME = stringPreferencesKey("user_name")
        private val KEY_HF_TOKEN = stringPreferencesKey("hf_token_surface")
        private val KEY_XAI_KEY = stringPreferencesKey("xai_key_surface")
    }

    init {
        getOrCreateSecretKey()
    }

    /**
     * Observable mapping of current logged in X userId
     */
    val userIdFlow: Flow<String?> = context.tokenDataStore.data.map { preferences ->
        preferences[KEY_USER_ID]
    }

    /**
     * Observable X handle (without the leading @) of the current logged in account.
     */
    val usernameFlow: Flow<String?> = context.tokenDataStore.data.map { preferences ->
        preferences[KEY_USERNAME]
    }

    /**
     * Observable X display name of the current logged in account.
     */
    val nameFlow: Flow<String?> = context.tokenDataStore.data.map { preferences ->
        preferences[KEY_NAME]
    }

    /** Returns the currently logged-in X userId, or null if not signed in. */
    suspend fun getUserId(): String? =
        context.tokenDataStore.data.first()[KEY_USER_ID]

    /**
     * Checks if we have cached credentials.
     */
    suspend fun hasTokens(): Boolean {
        val prefs = context.tokenDataStore.data.first()
        return !prefs[KEY_ACCESS_TOKEN_SURFACE].isNullOrEmpty()
    }

    /**
     * Resolves plain-text decrypted Access Token
     */
    suspend fun getAccessToken(): String? {
        val encryptedBase64 = context.tokenDataStore.data.first()[KEY_ACCESS_TOKEN_SURFACE] ?: return null
        return decrypt(encryptedBase64)
    }

    /**
     * Resolves plain-text decrypted Refresh Token
     */
    suspend fun getRefreshToken(): String? {
        val encryptedBase64 = context.tokenDataStore.data.first()[KEY_REFRESH_TOKEN_SURFACE] ?: return null
        return decrypt(encryptedBase64)
    }

    /**
     * Saves credentials safely using crypto envelopes.
     */
    suspend fun saveTokens(
        accessToken: String,
        refreshToken: String?,
        userId: String,
        username: String? = null,
        name: String? = null
    ) {
        val encryptedAccess = encrypt(accessToken)
        val encryptedRefresh = refreshToken?.let { encrypt(it) } ?: ""

        context.tokenDataStore.edit { preferences ->
            preferences[KEY_ACCESS_TOKEN_SURFACE] = encryptedAccess
            preferences[KEY_REFRESH_TOKEN_SURFACE] = encryptedRefresh
            preferences[KEY_USER_ID] = userId
            if (username != null) preferences[KEY_USERNAME] = username else preferences.remove(KEY_USERNAME)
            if (name != null) preferences[KEY_NAME] = name else preferences.remove(KEY_NAME)
        }
    }

    /**
     * Resolves the plain-text decrypted Hugging Face token used to fetch gated model weights, or
     * null if none was saved. Independent of the X session — intentionally not removed by [clear].
     */
    suspend fun getHuggingFaceToken(): String? {
        val encryptedBase64 = context.tokenDataStore.data.first()[KEY_HF_TOKEN] ?: return null
        return decrypt(encryptedBase64)
    }

    /** Persists the Hugging Face token under Keystore-backed AES-GCM encryption. */
    suspend fun saveHuggingFaceToken(token: String) {
        val encrypted = encrypt(token)
        context.tokenDataStore.edit { preferences ->
            preferences[KEY_HF_TOKEN] = encrypted
        }
    }

    /**
     * Resolves the user-supplied xAI API key (encrypted), or null if none was saved. Independent
     * of the X session — intentionally not removed by [clear].
     */
    suspend fun getXaiKey(): String? {
        val encryptedBase64 = context.tokenDataStore.data.first()[KEY_XAI_KEY] ?: return null
        return decrypt(encryptedBase64)
    }

    /** Persists (or clears, with a blank value) the xAI API key under AES-GCM encryption. */
    suspend fun saveXaiKey(key: String) {
        context.tokenDataStore.edit { preferences ->
            if (key.isBlank()) preferences.remove(KEY_XAI_KEY)
            else preferences[KEY_XAI_KEY] = encrypt(key)
        }
    }

    /**
     * Purges all locally cached session elements completely.
     */
    suspend fun clear() {
        context.tokenDataStore.edit { preferences ->
            preferences.remove(KEY_ACCESS_TOKEN_SURFACE)
            preferences.remove(KEY_REFRESH_TOKEN_SURFACE)
            preferences.remove(KEY_USER_ID)
            preferences.remove(KEY_USERNAME)
            preferences.remove(KEY_NAME)
        }
    }

    // --- CRYPTO LOGIC ---

    /**
     * Synchronous credential purge used by the KeyStore failure path in release builds.
     * Runs on whatever thread calls [getOrCreateSecretKey], which is fine — DataStore
     * write operations are serialized internally.
     */
    private fun clearAll() {
        kotlinx.coroutines.runBlocking { clear() }
    }

    private var softwareFallbackKey: SecretKey? = null

    private fun getOrCreateSecretKey(): SecretKey {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
            keyStore.getKey(KEY_ALIAS, null)?.let { return it as SecretKey }

            val keyGenerator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEY_STORE
            )

            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()

            keyGenerator.init(spec)
            return keyGenerator.generateKey()
        } catch (e: Exception) {
            // Software fallback only in debug builds (JVM unit / screenshot tests where
            // AndroidKeyStore provider is absent). In release builds we clear credentials and
            // surface an exception so the caller can handle the failure explicitly.
            if (BuildConfig.DEBUG) {
                return softwareFallbackKey ?: synchronized(this) {
                    softwareFallbackKey ?: SecretKeySpec(
                        ByteArray(16) { 0x55.toByte() }, // 128-bit stable fallback test key
                        "AES"
                    ).also { softwareFallbackKey = it }
                }
            } else {
                clearAll()
                throw SecurityException("AndroidKeyStore unavailable; credentials cleared", e)
            }
        }
    }

    private fun encrypt(plainText: String): String {
        val key = getOrCreateSecretKey()
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, key)
        }
        val cipherText = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv

        // Combine IV and CipherText: [IV_Length (4 bytes)][IV][CipherText]
        val combined = ByteArray(4 + iv.size + cipherText.size)
        combined[0] = (iv.size shr 24).toByte()
        combined[1] = (iv.size shr 16).toByte()
        combined[2] = (iv.size shr 8).toByte()
        combined[3] = iv.size.toByte()

        System.arraycopy(iv, 0, combined, 4, iv.size)
        System.arraycopy(cipherText, 0, combined, 4 + iv.size, cipherText.size)

        return Base64.encodeToString(combined, Base64.DEFAULT)
    }

    private fun decrypt(encryptedBase64: String): String? {
        return try {
            val combined = Base64.decode(encryptedBase64, Base64.DEFAULT)
            if (combined.size < 4) return null

            val ivSize = ((combined[0].toInt() and 0xFF) shl 24) or
                    ((combined[1].toInt() and 0xFF) shl 16) or
                    ((combined[2].toInt() and 0xFF) shl 8) or
                    (combined[3].toInt() and 0xFF)

            if (combined.size < 4 + ivSize) return null

            val iv = ByteArray(ivSize)
            System.arraycopy(combined, 4, iv, 0, ivSize)

            val cipherTextSize = combined.size - 4 - ivSize
            val cipherText = ByteArray(cipherTextSize)
            System.arraycopy(combined, 4 + ivSize, cipherText, 0, cipherTextSize)

            val key = getOrCreateSecretKey()
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            }
            val decryptedBytes = cipher.doFinal(cipherText)
            String(decryptedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.w(TAG, "Decryption/KeyStore error", e)
            null
        }
    }
}
