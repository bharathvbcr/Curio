package com.example.data.remote

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.Field
import retrofit2.http.FormUrlEncoded
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

@JsonClass(generateAdapter = true)
data class TokenResponse(
    @Json(name = "access_token") val accessToken: String,
    @Json(name = "refresh_token") val refreshToken: String?,
    @Json(name = "expires_in") val expiresIn: Int?,
    @Json(name = "scope") val scope: String?
)

@JsonClass(generateAdapter = true)
data class UserResponse(
    @Json(name = "data") val data: UserData
)

@JsonClass(generateAdapter = true)
data class UserData(
    @Json(name = "id") val id: String,
    @Json(name = "name") val name: String,
    @Json(name = "username") val username: String
)

/**
 * Retrofit interface representing Auth and identity management against official X API.
 */
interface XAuthApi {
    @FormUrlEncoded
    @POST("2/oauth2/token")
    suspend fun exchangeToken(
        @Field("grant_type") grantType: String,
        @Field("client_id") clientId: String,
        @Field("redirect_uri") redirectUri: String,
        @Field("code") code: String,
        @Field("code_verifier") codeVerifier: String
    ): TokenResponse

    @FormUrlEncoded
    @POST("2/oauth2/token")
    suspend fun refreshToken(
        @Field("grant_type") grantType: String,
        @Field("client_id") clientId: String,
        @Field("refresh_token") refreshToken: String
    ): TokenResponse

    @GET("2/users/me")
    suspend fun getUserMe(
        @Header("Authorization") authorization: String
    ): UserResponse
}
