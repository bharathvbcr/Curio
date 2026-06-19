package com.example.data.remote

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.Path

@JsonClass(generateAdapter = true)
data class GithubOwner(
    @Json(name = "login") val login: String
)

@JsonClass(generateAdapter = true)
data class GithubRepoResponse(
    @Json(name = "full_name") val fullName: String,
    @Json(name = "description") val description: String? = null,
    @Json(name = "stargazers_count") val stars: Int = 0,
    @Json(name = "language") val language: String? = null,
    @Json(name = "topics") val topics: List<String> = emptyList(),
    @Json(name = "pushed_at") val pushedAt: String? = null,
    @Json(name = "owner") val owner: GithubOwner
)

interface GithubApi {
    @GET("repos/{owner}/{repo}")
    @Headers("Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28")
    suspend fun getRepo(
        @Path("owner") owner: String,
        @Path("repo") repo: String
    ): GithubRepoResponse
}
