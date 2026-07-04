package com.example.ui

import com.example.data.XAiAnalyzer
import com.example.data.ai.ChatPromptBuilder
import com.example.data.embedding.EmbeddingProvider
import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toFloatArray
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
 * [rawBookmarks] / [currentUserId] are suppliers reading the VM's live state, so the controller
 * stays a thin collaborator rather than duplicating ownership of the library.
 */
internal class ChatController(
    private val scope: CoroutineScope,
    private val aiAnalyzer: XAiAnalyzer,
    private val embeddingService: EmbeddingProvider,
    private val repository: BookmarkRepository,
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
                val contextItems = if (useLibrary) {
                    if (uid != null) retrieveRagContext(textInput, uid) else rawBookmarks().take(15)
                } else emptyList()

                // Prompt + system-instruction + Live Search params are built in the data layer
                // (ChatPromptBuilder). ChatSource is a UI concept; map it to data-layer primitives.
                val liveApiTypes = sources.mapNotNull { it.apiType }
                val liveLabels = sources.filter { it != ChatSource.LIBRARY }.joinToString("/") { it.label }
                val parts = ChatPromptBuilder.build(
                    userQuery = textInput,
                    contextItems = contextItems,
                    useLibrary = useLibrary,
                    liveSourceApiTypes = liveApiTypes,
                    liveLabels = liveLabels
                )

                val aiResponse = aiAnalyzer.generateChatResponse(parts.contextPrompt, parts.systemInstruction, parts.searchParameters)
                // Surface retrieved library items as citations too (Live Search citations only cover web/x/news).
                val libraryCitations = if (useLibrary) contextItems.mapNotNull { citationUrl(it) } else emptyList()
                _chatMessages.value = _chatMessages.value + ChatMessage(
                    id = java.util.UUID.randomUUID().toString(),
                    sender = ChatSender.AI,
                    text = aiResponse.text,
                    citations = (aiResponse.citations + libraryCitations).distinct(),
                    groundedIn = sources.toList()
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

    /** Canonical URL for a retrieved library item, used to cite library-grounded chat replies. */
    private fun citationUrl(b: Bookmark): String? = when (b.sourceType) {
        SourceType.ARXIV -> "https://arxiv.org/abs/${b.sourceId}"
        SourceType.GITHUB -> "https://github.com/${b.sourceId}"
        SourceType.HUGGING_FACE -> "https://huggingface.co/${b.sourceId}"
        SourceType.DOI -> "https://doi.org/${b.sourceId}"
        else -> b.url
    }

    private suspend fun retrieveRagContext(query: String, userId: String): List<Bookmark> {
        return try {
            val queryEmbedding = embeddingService.embedQuery(query) ?: return rawBookmarks().take(15)
            val allEmbeddings = repository.getBookmarksWithEmbeddings(userId)
                .map { (id, bytes) -> id to bytes.toFloatArray() }
            if (allEmbeddings.isEmpty()) return rawBookmarks().take(15)
            val topIds = VectorSearch.topK(queryEmbedding, allEmbeddings, k = 15).toSet()
            val bookmarkMap = rawBookmarks().associateBy { it.id }
            topIds.mapNotNull { bookmarkMap[it] }
        } catch (e: Exception) {
            rawBookmarks().take(15)
        }
    }
}
