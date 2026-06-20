package com.example.data.remote

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.GET
import retrofit2.http.Path

@JsonClass(generateAdapter = true)
data class HfModelResponse(
    @Json(name = "modelId") val modelId: String? = null,
    @Json(name = "id") val id: String? = null,
    @Json(name = "author") val author: String? = null,
    // Nullable: HF API omits these fields for gated/private models and on 404 responses.
    @Json(name = "downloads") val downloads: Int? = null,
    @Json(name = "likes") val likes: Int? = null,
    @Json(name = "lastModified") val lastModified: String? = null,
    @Json(name = "pipeline_tag") val pipelineTag: String? = null,
    @Json(name = "tags") val tags: List<String> = emptyList(),
    @Json(name = "description") val description: String? = null
)

@JsonClass(generateAdapter = true)
data class HfDatasetResponse(
    @Json(name = "id") val id: String? = null,
    @Json(name = "author") val author: String? = null,
    // Nullable: HF API omits these fields for gated/private datasets and on 404 responses.
    @Json(name = "downloads") val downloads: Int? = null,
    @Json(name = "likes") val likes: Int? = null,
    @Json(name = "lastModified") val lastModified: String? = null,
    @Json(name = "tags") val tags: List<String> = emptyList(),
    @Json(name = "description") val description: String? = null
)

interface HuggingFaceApi {
    // Nullable return: HF returns 404 for private/non-existent models; callers must null-check.
    @GET("models/{id}")
    suspend fun getModel(@Path("id", encoded = true) id: String): HfModelResponse?

    // Nullable return: HF returns 404 for private/non-existent datasets; callers must null-check.
    @GET("datasets/{id}")
    suspend fun getDataset(@Path("id", encoded = true) id: String): HfDatasetResponse?
}
