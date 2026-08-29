package app.kin.shared.ai

import app.kin.shared.model.ChatAuthor
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.Identifiers
import app.kin.shared.platform.SseTransport
import app.kin.shared.storage.KinRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class ChatCompletionRequest(
    val model: String,
    val messages: List<ProviderMessage>,
    val stream: Boolean = true,
)

@Serializable
private data class ProviderMessage(val role: String, val content: String)

@Serializable
private data class SseChunk(val choices: List<SseChoice> = emptyList())

@Serializable
private data class SseChoice(val delta: SseDelta = SseDelta(), val finishReason: String? = null)

@Serializable
private data class SseDelta(val content: String? = null)

data class ChatSendResult(
    val requestEventId: String,
    val assistantEventId: String,
    val text: String,
    val status: ChatEventStatus,
    val errorMessage: String? = null,
)

/** OpenAI-compatible streaming client with durable lifecycle events. */
class OpenAICompatibleSseClient(
    private val repository: KinRepository,
    private val transport: SseTransport,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    suspend fun send(
        roleId: String,
        conversationId: String,
        prompt: List<ProviderMessageInput>,
        endpoint: String,
        model: String,
        apiKey: String,
        nowMillis: () -> Long,
        onDelta: suspend (String) -> Unit = {},
    ): ChatSendResult {
        require(apiKey.isNotBlank()) { "API key is required" }
        require(endpoint.startsWith("https://")) { "Provider endpoint must use HTTPS" }
        val userBody = prompt.lastOrNull { it.role == "user" }?.content.orEmpty()
        val requestEvent = repository.appendEvent(
            ChatEvent(
                id = Identifiers.newId("request"),
                roleId = roleId,
                conversationId = conversationId,
                author = ChatAuthor.USER,
                kind = ChatEventKind.MESSAGE,
                status = ChatEventStatus.SENT,
                body = userBody,
                createdAtMillis = nowMillis(),
            ),
        )
        val assistantEvent = repository.appendEvent(
            ChatEvent(
                id = Identifiers.newId("assistant"),
                roleId = roleId,
                conversationId = conversationId,
                author = ChatAuthor.ROLE,
                kind = ChatEventKind.REQUEST_STARTED,
                status = ChatEventStatus.PENDING,
                parentEventId = requestEvent.id,
                createdAtMillis = nowMillis(),
            ),
        )
        val body = json.encodeToString(
            ChatCompletionRequest(
                model = model,
                messages = prompt.map { ProviderMessage(it.role, it.content) },
            ),
        )
        val text = StringBuilder()
        return try {
            transport.stream(endpoint, apiKey, body) { line ->
                currentCoroutineContext().ensureActive()
                val data = line.removePrefix("data:").trim()
                if (data.isEmpty() || data == "[DONE]") return@stream
                val chunk = json.decodeFromString<SseChunk>(data)
                val delta = chunk.choices.firstOrNull()?.delta?.content.orEmpty()
                if (delta.isNotEmpty()) {
                    text.append(delta)
                    repository.appendEvent(
                        ChatEvent(
                            id = Identifiers.newId("delta"),
                            roleId = roleId,
                            conversationId = conversationId,
                            author = ChatAuthor.ROLE,
                            kind = ChatEventKind.DELTA,
                            status = ChatEventStatus.PERSISTED,
                            body = delta,
                            parentEventId = assistantEvent.id,
                            createdAtMillis = nowMillis(),
                        ),
                    )
                    onDelta(delta)
                }
            }
            val finalText = text.toString()
            repository.appendEvent(
                ChatEvent(
                    id = Identifiers.newId("complete"),
                    roleId = roleId,
                    conversationId = conversationId,
                    author = ChatAuthor.ROLE,
                    kind = ChatEventKind.COMPLETED,
                    status = ChatEventStatus.SENT,
                    body = finalText,
                    parentEventId = assistantEvent.id,
                    createdAtMillis = nowMillis(),
                ),
            )
            ChatSendResult(requestEvent.id, assistantEvent.id, finalText, ChatEventStatus.SENT)
        } catch (cancelled: CancellationException) {
            repository.appendEvent(
                lifecycleEvent(roleId, conversationId, assistantEvent.id, ChatEventKind.CANCELLED, ChatEventStatus.CANCELLED, text.toString(), nowMillis()),
            )
            throw cancelled
        } catch (failure: Throwable) {
            repository.appendEvent(
                lifecycleEvent(
                    roleId,
                    conversationId,
                    assistantEvent.id,
                    ChatEventKind.FAILED,
                    ChatEventStatus.FAILED,
                    text.toString(),
                    nowMillis(),
                    failure::class.simpleName ?: "provider_error",
                    failure.message ?: "Provider request failed",
                ),
            )
            ChatSendResult(requestEvent.id, assistantEvent.id, text.toString(), ChatEventStatus.FAILED, failure.message)
        }
    }

    suspend fun retry(
        failedAssistantEventId: String,
        roleId: String,
        conversationId: String,
        prompt: List<ProviderMessageInput>,
        endpoint: String,
        model: String,
        apiKey: String,
        nowMillis: () -> Long,
        onDelta: suspend (String) -> Unit = {},
    ): ChatSendResult {
        repository.appendEvent(
            lifecycleEvent(
                roleId,
                conversationId,
                failedAssistantEventId,
                ChatEventKind.RETRY_REQUESTED,
                ChatEventStatus.PENDING,
                "",
                nowMillis(),
            ),
        )
        return send(roleId, conversationId, prompt, endpoint, model, apiKey, nowMillis, onDelta)
    }

    private fun lifecycleEvent(
        roleId: String,
        conversationId: String,
        parentEventId: String,
        kind: ChatEventKind,
        status: ChatEventStatus,
        body: String,
        createdAtMillis: Long,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) = ChatEvent(
        id = Identifiers.newId(kind.name.lowercase()),
        roleId = roleId,
        conversationId = conversationId,
        author = ChatAuthor.ROLE,
        kind = kind,
        status = status,
        body = body,
        parentEventId = parentEventId,
        createdAtMillis = createdAtMillis,
        errorCode = errorCode,
        errorMessage = errorMessage,
    )
}

data class ProviderMessageInput(val role: String, val content: String)
