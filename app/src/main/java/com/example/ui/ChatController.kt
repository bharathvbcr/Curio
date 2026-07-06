package com.example.ui

import android.util.Log
import com.example.data.XAiAnalyzer
import com.example.data.ai.ChatPromptBuilder
import com.example.data.embedding.EmbeddingProvider
import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toFloatArray
import com.example.data.semantic.OnDeviceSemanticLayer
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Owns the Research Assistant chat: message list, loading state, selected grounding sources, and
 * the RAG retrieval + Live Search send path. Extracted from [BookmarkViewModel] to shrink the god
 * class; the VM facades to it (its public chat API is unchanged, so the UI is untouched). This
 * chat state is independent of the feed's filtering flows, so the extraction doesn't touch the
 * central reactive `combine` graph.
 *
 * The [semanticLayer] is a fully on-device accelerator: it can serve a cached answer for a
 * semantically-equivalent past query (skipping xAI), compress retrieved RAG context, and route
 * reasoning effort by query complexity. It is single-user and local, so there is no cross-user
 * exposure. Caching is skipped whenever Live Search is on, since those answers are time-sensitive.
 *
 * [rawBookmarks] / [currentUserId] are suppliers reading the VM's live state, so the controller
 * stays a thin collaborator rather than duplicating ownership of the library.
 */
internal class ChatController(
    private val scope: CoroutineScope,
    private val aiAnalyzer: XAiAnalyzer,
    private val embeddingService: EmbeddingProvider,
    private val repository: BookmarkRepository,
    private val semanticLayer: OnDeviceSemanticLayer,
    private val rawBookmarks: () -> List<Bookmark>,
    private val currentUserId: () -> String?
) {
    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages.asStateFlow()

    private val _isChatLoading = MutableStateFlow(false)
    val isChatLoading: StateFlow<Boolean> = _isChatLoading.asStateFlow()

    /** Grounding sources the user has toggled on. [ChatSource.LIBRARY] is on by default. */
    private val _chatSources = MutableStateFlow(setOf(ChatSource.LIBRARY))
    val chatSources: StateFlow<Set<ChatSource>> = _chatSources.asStateFlow()

    fun toggleSource(source: ChatSource) {
        _chatSources.value = _chatSources.value.toMutableSet().apply {
            if (!add(source)) remove(source)
        }.ifEmpty { setOf(ChatSource.LIBRARY) }
    }

    /** Resets the conversation back to the empty welcome state. */
    fun clear() {
        _chatMessages.value = emptyList()
        _isChatLoading.value = false
    }

    fun send(textInput: String, includeUserMessage: Boolean = true) {
        if (textInput.isBlank()) return
        val sources = _chatSources.value
        if (includeUserMessage) {
            val userMsg = ChatMessage(id = java.util.UUID.randomUUID().toString(), sender = ChatSender.USER, text = textInput)
            _chatMessages.value = _chatMessages.value + userMsg
        }
        _isChatLoading.value = true
        scope.launch {
            try {
                val uid = currentUserId()
                val useLibrary = ChatSource.LIBRARY in sources
                // ChatSource is a UI concept; map it to data-layer primitives for the prompt builder.
                val liveApiTypes = sources.mapNotNull { it.apiType }
                val liveLabels = sources.filter { it != ChatSource.LIBRARY }.joinToString("/") { it.label }

                val semanticEnabled = semanticLayer.isEnabled()
                // Only cache answers that don't depend on Live Search (those are time-sensitive).
                val cacheable = semanticEnabled && liveApiTypes.isEmpty()

                // Embed the query once and reuse the vector for retrieval, cache, and compression.
                val needEmbedding = semanticEnabled || (useLibrary && uid != null)
                val queryEmbedding = if (needEmbedding) embeddingService.embedQuery(textInput) else null

                val scored: List<Pair<Bookmark, FloatArray>> = if (useLibrary) {
                    if (uid != null) retrieveRagContextScored(queryEmbedding, uid)
                    else rawBookmarks().take(15).map { it to FloatArray(0) }
                } else emptyList()

                // 1. Semantic cache lookup — serve a past answer and skip xAI entirely.
                if (cacheable) {
                    val cached = semanticLayer.lookup(textInput, queryEmbedding, uid)
                    if (cached != null && cached.response.isNotBlank()) {
                        Log.d("SemanticLayer", "cache hit tier=${cached.modelTier} sim=${cached.similarity}")
                        val libraryCitations = if (useLibrary) scored.mapNotNull { citationUrl(it.first) } else emptyList()
                        _chatMessages.value = _chatMessages.value + ChatMessage(
                            id = java.util.UUID.randomUUID().toString(),
                            sender = ChatSender.AI,
                            text = cached.response,
                            citations = libraryCitations,
                            groundedIn = sources.toList(),
                            semanticCacheEntryId = cached.entryId,
                            semanticSimilarity = cached.similarity.takeIf { it > 0f },
                            semanticCacheHit = true,
                            semanticModelTier = cached.modelTier
                        )
                        return@launch
                    }
                }

                // 2. Compress retrieved context (MMR) before building the prompt.
                val contextItems = if (semanticEnabled) semanticLayer.compress(queryEmbedding, scored)
                else scored.map { it.first }
                val libraryCitations = if (useLibrary) contextItems.mapNotNull { citationUrl(it) } else emptyList()

                // 3. Route reasoning effort by query complexity.
                val route = if (semanticEnabled) semanticLayer.route(textInput) else null

                val parts = ChatPromptBuilder.build(
                    userQuery = textInput,
                    contextItems = contextItems,
                    useLibrary = useLibrary,
                    liveSourceApiTypes = liveApiTypes,
                    liveLabels = liveLabels
                )

                val aiResponse = aiAnalyzer.generateChatResponse(
                    prompt = parts.contextPrompt,
                    systemInstruction = parts.systemInstruction,
                    searchParameters = parts.searchParameters,
                    reasoningEffort = route?.reasoningEffort
                )

                // 4. Write-through store (cacheable answers only).
                val cacheEntryId = if (cacheable) {
                    semanticLayer.store(textInput, queryEmbedding, aiResponse.text, uid, route?.tier ?: "")
                } else null

                // Surface retrieved library items as citations too (Live Search citations only cover web/x/news).
                _chatMessages.value = _chatMessages.value + ChatMessage(
                    id = java.util.UUID.randomUUID().toString(),
                    sender = ChatSender.AI,
                    text = aiResponse.text,
                    citations = (aiResponse.citations + libraryCitations).distinct(),
                    groundedIn = sources.toList(),
                    semanticCacheEntryId = cacheEntryId,
                    semanticCacheHit = false,
                    semanticModelTier = route?.tier
                )
            } catch (e: Exception) {
                _chatMessages.value = _chatMessages.value + ChatMessage(
                    id = java.util.UUID.randomUUID().toString(),
                    sender = ChatSender.AI,
                    text = humanReadableError(e, ErrorContext.AI),
                    isError = true,
                    retryPrompt = textInput
                )
            } finally {
                _isChatLoading.value = false
            }
        }
    }

    /** Re-runs the failed prompt without duplicating the user's message bubble. */
    fun retryMessage(failedMessageId: String) {
        val messages = _chatMessages.value
        val failedIndex = messages.indexOfFirst { it.id == failedMessageId }
        if (failedIndex < 0) return
        val failed = messages[failedIndex]
        val prompt = failed.retryPrompt ?: return
        _chatMessages.value = messages.filterIndexed { index, _ -> index != failedIndex }
        send(prompt, includeUserMessage = false)
    }

    /**
     * Thumbs up/down on a cache-served assistant message. Thumbs-down evicts the offending cache
     * entry and nudges the hit threshold up so the bad match isn't repeated (handled on-device).
     */
    fun submitSemanticFeedback(messageId: String, accepted: Boolean) {
        scope.launch {
            val msg = _chatMessages.value.find { it.id == messageId } ?: return@launch
            val entryId = msg.semanticCacheEntryId ?: return@launch
            if (msg.semanticFeedbackAccepted != null) return@launch
            semanticLayer.feedback(entryId, accepted, msg.semanticSimilarity ?: 0f)
            _chatMessages.value = _chatMessages.value.map {
                if (it.id == messageId) it.copy(semanticFeedbackAccepted = accepted) else it
            }
        }
    }

    /** Canonical URL for a retrieved library item, used to cite library-grounded chat replies. */
    private fun citationUrl(b: Bookmark): String? = when (b.sourceType) {
        SourceType.ARXIV -> "https://arxiv.org/abs/${b.sourceId}"
        SourceType.GITHUB -> "https://github.com/${b.sourceId}"
        SourceType.HUGGING_FACE -> "https://huggingface.co/${b.sourceId}"
        SourceType.DOI -> "https://doi.org/${b.sourceId}"
        else -> b.url
    }

    /**
     * Retrieves the top-K library bookmarks for [queryEmbedding], paired with their embeddings so
     * the semantic compressor can MMR-rank them. Falls back to recent bookmarks (no embeddings)
     * when the query can't be embedded or nothing is indexed yet.
     */
    private suspend fun retrieveRagContextScored(
        queryEmbedding: FloatArray?,
        userId: String
    ): List<Pair<Bookmark, FloatArray>> {
        return try {
            if (queryEmbedding == null) return rawBookmarks().take(15).map { it to FloatArray(0) }
            val all = repository.getBookmarksWithEmbeddings(userId)
                .map { (id, bytes) -> id to bytes.toFloatArray() }
            if (all.isEmpty()) return rawBookmarks().take(15).map { it to FloatArray(0) }
            val embById = all.toMap()
            val topScored = VectorSearch.topKScored(queryEmbedding, all, k = 15)
            val bookmarkMap = rawBookmarks().associateBy { it.id }
            topScored.mapNotNull { (id, _) ->
                bookmarkMap[id]?.let { it to (embById[id] ?: FloatArray(0)) }
            }
        } catch (e: Exception) {
            rawBookmarks().take(15).map { it to FloatArray(0) }
        }
    }
}
