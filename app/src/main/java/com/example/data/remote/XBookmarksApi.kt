package com.example.data.remote

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path
import retrofit2.http.Query

@JsonClass(generateAdapter = true)
data class TweetAttachmentsDto(
    @Json(name = "media_keys") val mediaKeys: List<String>? = null
)

/** Long-form tweet body (>280 chars). Prefer this over `text` when present. */
@JsonClass(generateAdapter = true)
data class NoteTweetDto(
    @Json(name = "text") val text: String? = null
)

/** A single expanded URL entity (t.co → real link). */
@JsonClass(generateAdapter = true)
data class UrlEntityDto(
    @Json(name = "url") val url: String? = null,
    @Json(name = "expanded_url") val expandedUrl: String? = null,
    @Json(name = "display_url") val displayUrl: String? = null
)

@JsonClass(generateAdapter = true)
data class TweetEntitiesDto(
    @Json(name = "urls") val urls: List<UrlEntityDto>? = null
)

@JsonClass(generateAdapter = true)
data class BookmarkDto(
    @Json(name = "id") val id: String,
    @Json(name = "text") val text: String,
    @Json(name = "created_at") val createdAt: String? = null,
    @Json(name = "author_id") val authorId: String? = null,
    @Json(name = "note_tweet") val noteTweet: NoteTweetDto? = null,
    @Json(name = "entities") val entities: TweetEntitiesDto? = null,
    @Json(name = "attachments") val attachments: TweetAttachmentsDto? = null
)

@JsonClass(generateAdapter = true)
data class MediaDto(
    @Json(name = "media_key") val mediaKey: String,
    @Json(name = "type") val type: String? = null,
    @Json(name = "url") val url: String? = null,
    @Json(name = "preview_image_url") val previewImageUrl: String? = null,
    @Json(name = "alt_text") val altText: String? = null
)

/** Expanded author from `includes.users`, joined by author_id. */
@JsonClass(generateAdapter = true)
data class UserDto(
    @Json(name = "id") val id: String,
    @Json(name = "name") val name: String? = null,
    @Json(name = "username") val username: String? = null
)

@JsonClass(generateAdapter = true)
data class BookmarksIncludesDto(
    @Json(name = "media") val media: List<MediaDto>? = null,
    @Json(name = "users") val users: List<UserDto>? = null
)

@JsonClass(generateAdapter = true)
data class BookmarksMetaDto(
    @Json(name = "next_token") val nextToken: String? = null
)

@JsonClass(generateAdapter = true)
data class BookmarksResponse(
    @Json(name = "data") val data: List<BookmarkDto>? = null,
    @Json(name = "includes") val includes: BookmarksIncludesDto? = null,
    @Json(name = "meta") val meta: BookmarksMetaDto? = null
)

interface XBookmarksApi {
    @GET("2/users/{userId}/bookmarks")
    suspend fun getBookmarks(
        @Header("Authorization") authHeader: String,
        @Path("userId") userId: String,
        @Query("max_results") maxResults: Int = 100,
        @Query("pagination_token") paginationToken: String? = null,
        @Query("tweet.fields") tweetFields: String = "created_at,attachments,author_id,note_tweet,entities",
        @Query("expansions") expansions: String = "attachments.media_keys,author_id",
        @Query("media.fields") mediaFields: String = "url,preview_image_url,type,alt_text",
        @Query("user.fields") userFields: String = "name,username"
    ): BookmarksResponse
}
