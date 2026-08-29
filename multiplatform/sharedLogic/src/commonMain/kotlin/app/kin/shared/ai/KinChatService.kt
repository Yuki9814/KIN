package app.kin.shared.ai

import app.kin.shared.memory.PromptAssembler
import app.kin.shared.model.ChatEvent
import app.kin.shared.model.MemoryRecord
import app.kin.shared.platform.PlatformServices
import app.kin.shared.settings.SettingsService
import app.kin.shared.storage.KinRepository

/** Application-level path that connects role-isolated prompt assembly to the durable SSE client. */
class KinChatService(
    private val repository: KinRepository,
    private val settings: SettingsService = SettingsService(),
    private val promptAssembler: PromptAssembler = PromptAssembler(),
    private val client: OpenAICompatibleSseClient = OpenAICompatibleSseClient(
        repository,
        PlatformServices.sseTransport(),
    ),
) {
    suspend fun send(
        roleId: String,
        conversationId: String,
        userText: String,
        nowMillis: () -> Long,
        onDelta: suspend (String) -> Unit = {},
    ): ChatSendResult {
        require(userText.isNotBlank()) { "Message must not be blank" }
        val role = repository.role(roleId) ?: error("Unknown role: $roleId")
        val prompt = promptAssembler.assemble(
            role = role,
            relationship = repository.relationship(roleId),
            events = repository.events(conversationId, roleId),
            memories = repository.memories(roleId),
        ).map { ProviderMessageInput(it.role, it.content) }
        val appSettings = settings.load()
        val apiKey = settings.readApiKey() ?: error("No API key is stored in SecretStore")
        return client.send(
            roleId = roleId,
            conversationId = conversationId,
            prompt = prompt + ProviderMessageInput("user", userText),
            endpoint = appSettings.endpoint,
            model = appSettings.model,
            apiKey = apiKey,
            nowMillis = nowMillis,
            onDelta = onDelta,
        )
    }

    suspend fun retry(
        failedAssistantEventId: String,
        roleId: String,
        conversationId: String,
        userText: String,
        nowMillis: () -> Long,
        onDelta: suspend (String) -> Unit = {},
    ): ChatSendResult {
        val role = repository.role(roleId) ?: error("Unknown role: $roleId")
        val prompt = promptAssembler.assemble(
            role,
            repository.relationship(roleId),
            repository.events(conversationId, roleId),
            repository.memories(roleId),
        ).map { ProviderMessageInput(it.role, it.content) }
        val appSettings = settings.load()
        val apiKey = settings.readApiKey() ?: error("No API key is stored in SecretStore")
        return client.retry(
            failedAssistantEventId,
            roleId,
            conversationId,
            prompt + ProviderMessageInput("user", userText),
            appSettings.endpoint,
            appSettings.model,
            apiKey,
            nowMillis,
            onDelta,
        )
    }
}
