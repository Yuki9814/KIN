package app.kin.shared.settings

import app.kin.shared.model.AppSettings
import app.kin.shared.platform.PlatformServices
import app.kin.shared.platform.SecretStore
import app.kin.shared.platform.SettingsStore

class SettingsService(
    private val settingsStore: SettingsStore = PlatformServices.settingsStore(),
    private val secretStore: SecretStore = PlatformServices.secretStore(),
) {
    suspend fun load(): AppSettings = settingsStore.load()

    suspend fun save(settings: AppSettings) = settingsStore.save(settings)

    suspend fun readApiKey(): String? = secretStore.read(API_KEY_SECRET)?.decodeToString()

    suspend fun saveApiKey(apiKey: String) {
        require(apiKey.isNotBlank()) { "API key must not be blank" }
        secretStore.write(API_KEY_SECRET, apiKey.encodeToByteArray())
    }

    suspend fun clearApiKey() = secretStore.delete(API_KEY_SECRET)

    private companion object {
        const val API_KEY_SECRET = "openai-compatible-api-key"
    }
}
