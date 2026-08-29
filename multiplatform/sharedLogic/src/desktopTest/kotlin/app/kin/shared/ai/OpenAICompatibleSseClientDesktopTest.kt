package app.kin.shared.ai

import app.kin.shared.model.ChatEventKind
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.platform.SseTransport
import app.kin.shared.platform.PlatformServices
import app.kin.shared.storage.KinRepository
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class OpenAICompatibleSseClientDesktopTest {
    @Test
    fun mockSseDeltasArePersistedAndCompleted() = runBlocking {
        val repository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val transport = FakeSseTransport()
        val client = OpenAICompatibleSseClient(repository, transport)
        val deltas = mutableListOf<String>()

        val result = client.send(
            roleId = KinBuiltIns.ayaneRoleId,
            conversationId = "mock-conversation",
            prompt = listOf(
                ProviderMessageInput("system", "You are a fixture assistant."),
                ProviderMessageInput("user", "hello"),
            ),
            endpoint = "https://mock.invalid/v1/chat/completions",
            model = "fixture-model",
            apiKey = "fixture-api-key",
            nowMillis = { 100L },
            onDelta = { deltas += it },
        )

        assertEquals(ChatEventStatus.SENT, result.status)
        assertEquals("你好", result.text)
        assertEquals(listOf("你", "好"), deltas)
        assertEquals(
            listOf(
                ChatEventKind.MESSAGE,
                ChatEventKind.REQUEST_STARTED,
                ChatEventKind.DELTA,
                ChatEventKind.DELTA,
                ChatEventKind.COMPLETED,
            ),
            repository.events("mock-conversation").map { it.kind },
        )
        assertTrue(transport.requestBody.contains("\"stream\":true"))
        assertTrue(!transport.requestBody.contains("fixture-api-key"))
        repository.close()
    }

    @Test
    fun providerFailureIsRetainedForRetry() = runBlocking {
        val repository = KinRepository(PlatformServices.sqliteDatabase(":memory:"))
        val transport = FakeSseTransport(failAfterFirstDelta = true)
        val client = OpenAICompatibleSseClient(repository, transport)
        val failed = client.send(
            roleId = KinBuiltIns.ayaneRoleId,
            conversationId = "retry-conversation",
            prompt = listOf(ProviderMessageInput("user", "hello")),
            endpoint = "https://mock.invalid/v1/chat/completions",
            model = "fixture-model",
            apiKey = "fixture-api-key",
            nowMillis = { 100L },
        )

        assertEquals(ChatEventStatus.FAILED, failed.status)
        assertEquals("你", failed.text)
        assertEquals(
            listOf(
                ChatEventKind.MESSAGE,
                ChatEventKind.REQUEST_STARTED,
                ChatEventKind.DELTA,
                ChatEventKind.FAILED,
            ),
            repository.events("retry-conversation").map { it.kind },
        )

        transport.failAfterFirstDelta = false
        val retried = client.retry(
            failedAssistantEventId = failed.assistantEventId,
            roleId = KinBuiltIns.ayaneRoleId,
            conversationId = "retry-conversation",
            prompt = listOf(ProviderMessageInput("user", "hello")),
            endpoint = "https://mock.invalid/v1/chat/completions",
            model = "fixture-model",
            apiKey = "fixture-api-key",
            nowMillis = { 200L },
        )
        assertEquals(ChatEventStatus.SENT, retried.status)
        assertEquals("你好", retried.text)
        assertEquals(1, repository.events("retry-conversation").count { it.kind == ChatEventKind.COMPLETED })
        assertEquals(1, repository.events("retry-conversation").count { it.kind == ChatEventKind.RETRY_REQUESTED })
        repository.close()
    }
}

private class FakeSseTransport(
    var failAfterFirstDelta: Boolean = false,
) : SseTransport {
    var requestBody: String = ""
        private set

    override suspend fun stream(
        endpoint: String,
        bearerToken: String,
        jsonBody: String,
        onLine: suspend (String) -> Unit,
    ) {
        requestBody = jsonBody
        onLine("""data: {"choices":[{"delta":{"content":"你"}}]}""")
        if (failAfterFirstDelta) error("fixture provider failure")
        onLine("""data: {"choices":[{"delta":{"content":"好"}}]}""")
        onLine("data: [DONE]")
    }
}
