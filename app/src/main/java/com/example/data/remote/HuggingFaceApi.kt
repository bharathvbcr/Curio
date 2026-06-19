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
    @Json(name = "downloads") val downloads: Int = 0,
    @Json(name = "likes") val likes: Int = 0,
    @Json(name = "pipeline_tag") val pipelineTag: String? = null,
    @Json(name = "tags") val tags: List<String> = emptyList(),
    @Json(name = "description") val description: String? = null
)

@JsonClass(generateAdapter = true)
data class HfDatasetResponse(
    @Json(name = "id") val id: String? = null,
    @Json(name = "author") val author: String? = null,
    @Json(name = "downloads") val downloads: Int = 0,
    @Json(name = "likes") val likes: Int = 0,
    @Json(name = "tags") val tags: List<String> = emptyList(),
    @Json(name = "description") val description: String? = null
)

interface HuggingFaceApi {
    @GET("models/{id}")
    suspend fun getModel(@Path("id", encoded = true) id: String): HfModelResponse

    @GET("datasets/{id}")
    suspend fun getDataset(@Path("id", encoded = true) id: String): HfDatasetResponse
}
