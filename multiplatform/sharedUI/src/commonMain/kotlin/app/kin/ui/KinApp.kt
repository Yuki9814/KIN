package app.kin.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.kin.shared.ai.KinChatService
import app.kin.shared.attachments.AttachmentService
import app.kin.shared.backup.KinBackupService
import app.kin.shared.model.ChatEventStatus
import app.kin.shared.model.KinBuiltIns
import app.kin.shared.model.MemoryRecord
import app.kin.shared.platform.PlatformServices
import app.kin.shared.storage.KinRepository
import kotlinx.coroutines.launch

private enum class KinPage(val title: String) {
    MESSAGES("消息"),
    CONTACTS("通讯录"),
    MEMORIES("记忆"),
    ATTACHMENTS("附件"),
    SETTINGS("设置"),
    BACKUP("备份"),
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun KinApp(repositoryFactory: () -> KinRepository = { KinRepository() }) {
    val repository = remember(repositoryFactory) { repositoryFactory() }
    var page by remember { mutableStateOf(KinPage.MESSAGES) }
    var selectedRoleId by remember { mutableStateOf(KinBuiltIns.ayaneRoleId) }
    var revision by remember { mutableStateOf(0) }
    val refresh = { revision += 1 }

    MaterialTheme {
        Scaffold(
            topBar = { TopAppBar(title = { Text("KIN · 有灵") }) },
            bottomBar = {
                NavigationBar {
                    KinPage.entries.forEach { item ->
                        NavigationBarItem(
                            selected = page == item,
                            onClick = { page = item },
                            icon = {},
                            label = { Text(item.title) },
                        )
                    }
                }
            },
        ) { padding ->
            Surface(Modifier.fillMaxSize().padding(padding)) {
                // Reading revision keeps all pages grounded in persisted SQLite state.
                revision
                when (page) {
                    KinPage.MESSAGES -> MessagesPage(repository, selectedRoleId, refresh)
                    KinPage.CONTACTS -> ContactsPage(repository, selectedRoleId, { selectedRoleId = it; page = KinPage.MESSAGES; refresh() }, refresh)
                    KinPage.MEMORIES -> MemoriesPage(repository, selectedRoleId, refresh)
                    KinPage.ATTACHMENTS -> AttachmentsPage(repository, refresh)
                    KinPage.SETTINGS -> SettingsPage(repository, refresh)
                    KinPage.BACKUP -> BackupPage(repository, refresh)
                }
            }
        }
    }
}

@Composable
private fun MessagesPage(repository: KinRepository, roleId: String, refresh: () -> Unit) {
    val role = repository.role(roleId) ?: repository.role(KinBuiltIns.ayaneRoleId) ?: return
    val events = repository.events(conversationId = "default-$roleId", roleId = role.id)
    val scope = rememberCoroutineScope()
    var draft by remember(role.id) { mutableStateOf("") }
    var sending by remember(role.id) { mutableStateOf(false) }
    var message by remember(role.id) { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text(role.displayName, style = MaterialTheme.typography.headlineSmall)
        Text("append-only 事件流 · ${events.size} 条", style = MaterialTheme.typography.labelMedium)
        Spacer(Modifier.height(12.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(events, key = { it.id }) { event ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(event.author.name.lowercase(), style = MaterialTheme.typography.labelSmall)
                        Text(event.body.ifBlank { event.kind.name }, style = MaterialTheme.typography.bodyLarge)
                        if (event.status == ChatEventStatus.FAILED) Text("失败：${event.errorMessage.orEmpty()}", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                draft,
                { draft = it },
                Modifier.weight(1f),
                enabled = !sending,
                placeholder = { Text("写给${role.displayName}…") },
            )
            Button(
                enabled = !sending,
                onClick = {
                    val userText = draft.trim()
                    if (userText.isNotBlank()) {
                        draft = ""
                        sending = true
                        message = ""
                        scope.launch {
                            try {
                                val result = KinChatService(repository).send(
                                    roleId = role.id,
                                    conversationId = "default-${role.id}",
                                    userText = userText,
                                    nowMillis = ::currentTimeMillis,
                                    onDelta = { refresh() },
                                )
                                if (result.status == ChatEventStatus.FAILED) {
                                    message = result.errorMessage ?: "AI 回复失败，失败事件已保留。"
                                }
                                refresh()
                            } catch (failure: Throwable) {
                                message = failure.message ?: "AI 回复不可用；请检查安全存储与设置。"
                                refresh()
                            } finally {
                                sending = false
                            }
                        }
                    }
                },
            ) { Text(if (sending) "发送中" else "发送") }
        }
        Text(
            message.ifBlank { "AI 回复通过 sharedLogic 的 OpenAI-compatible SSE 客户端接入；失败与取消事件会保留。" },
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ContactsPage(repository: KinRepository, selectedRoleId: String, select: (String) -> Unit, refresh: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var prompt by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text("角色", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(repository.roles(), key = { it.id }) { role ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(Modifier.weight(1f)) {
                            Text(role.displayName)
                            Text(if (role.isBuiltIn) "内置稳定角色" else "自建角色", style = MaterialTheme.typography.labelSmall)
                        }
                        TextButton(onClick = { select(role.id) }) { Text(if (selectedRoleId == role.id) "当前" else "聊天") }
                        if (!role.isBuiltIn) TextButton(onClick = { repository.archiveRole(role.id, currentTimeMillis()); refresh() }) { Text("归档") }
                    }
                }
            }
        }
        HorizontalDivider()
        Spacer(Modifier.height(8.dp))
        Text("新建角色", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("名称") })
        OutlinedTextField(prompt, { prompt = it }, Modifier.fillMaxWidth(), label = { Text("系统提示词") })
        Button(onClick = {
            if (name.isNotBlank() && prompt.isNotBlank()) {
                repository.createRole(name, prompt, currentTimeMillis())
                name = ""; prompt = ""; refresh()
            }
        }) { Text("创建") }
    }
}

@Composable
private fun MemoriesPage(repository: KinRepository, roleId: String, refresh: () -> Unit) {
    val role = repository.role(roleId) ?: return
    var text by remember(roleId) { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text("${role.displayName} 的长期记忆", style = MaterialTheme.typography.headlineSmall)
        Text("记忆按 roleId 隔离，组装 prompt 时不会跨角色读取。", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(repository.memories(roleId), key = { it.id }) { memory ->
                Card(Modifier.fillMaxWidth()) { Text(memory.text, Modifier.padding(12.dp)) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(text, { text = it }, Modifier.weight(1f), label = { Text("添加记忆") })
            Button(onClick = {
                if (text.isNotBlank()) {
                    repository.addMemory(MemoryRecord(roleId = roleId, text = text.trim(), createdAtMillis = currentTimeMillis()))
                    text = ""; refresh()
                }
            }) { Text("保存") }
        }
    }
}

@Composable
private fun AttachmentsPage(repository: KinRepository, refresh: () -> Unit) {
    val scope = rememberCoroutineScope()
    val service = remember { AttachmentService() }
    var message by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text("附件", style = MaterialTheme.typography.headlineSmall)
        Text("私有文件存储 + SHA-256 完整性校验", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(repository.attachments(), key = { it.id }) { attachment ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(attachment.fileName)
                        Text("${attachment.byteSize} bytes · ${attachment.sha256}", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
        Button(onClick = {
            scope.launch {
                try {
                    val picked = PlatformServices.filePicker().pickFile()
                    if (picked != null) {
                        val metadata = service.add(picked.fileName, picked.mimeType, picked.bytes)
                        repository.saveAttachmentMetadata(metadata)
                        message = "已保存 ${metadata.fileName}"
                        refresh()
                    }
                } catch (failure: Throwable) {
                    message = failure.message ?: "文件选择不可用"
                }
            }
        }) { Text("选择并保存附件") }
        if (message.isNotBlank()) Text(message, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun SettingsPage(repository: KinRepository, refresh: () -> Unit) {
    val scope = rememberCoroutineScope()
    var settings by remember { mutableStateOf(repository.settings()) }
    var apiKeyState by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("设置", style = MaterialTheme.typography.headlineSmall)
        OutlinedTextField(settings.endpoint, { settings = settings.copy(endpoint = it) }, Modifier.fillMaxWidth(), label = { Text("OpenAI-compatible Endpoint") })
        OutlinedTextField(settings.model, { settings = settings.copy(model = it) }, Modifier.fillMaxWidth(), label = { Text("Model") })
        OutlinedTextField(apiKeyState, { apiKeyState = it }, Modifier.fillMaxWidth(), label = { Text("API Key（仅写入系统安全存储）") }, visualTransformation = PasswordVisualTransformation())
        Button(onClick = { repository.saveSettings(settings); refresh() }) { Text("保存设置") }
        Button(onClick = {
            scope.launch {
                try {
                    require(apiKeyState.isNotBlank()) { "API key 不能为空" }
                    PlatformServices.secretStore().write("openai-compatible-api-key", apiKeyState.encodeToByteArray())
                    apiKeyState = ""
                    message = "API key 已写入系统安全存储"
                } catch (failure: Throwable) {
                    message = failure.message ?: "安全存储不可用"
                }
            }
        }) { Text("保存 API Key") }
        if (message.isNotBlank()) Text(message, style = MaterialTheme.typography.bodySmall)
        Text("API key 通过 SecretStore 保存：Android Keystore；Windows DPAPI。未提供明文回退。", style = MaterialTheme.typography.bodySmall)
        HorizontalDivider()
        Text("朋友圈、群聊、主动任务、OAuth：首版明确不实现。", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun BackupPage(repository: KinRepository, refresh: () -> Unit) {
    val scope = rememberCoroutineScope()
    val service = remember { KinBackupService(repository, AttachmentService()) }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("加密备份", style = MaterialTheme.typography.headlineSmall)
        Text("KINPortableArchiveV1 · PBKDF2-HMAC-SHA256 600000 · AES-GCM", style = MaterialTheme.typography.bodySmall)
        OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("备份密码") }, visualTransformation = PasswordVisualTransformation())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                scope.launch {
                    runCatching {
                        val result = service.export(password, currentTimeMillis())
                        PlatformServices.filePicker().saveFile(result.fileName, result.bytes)
                    }.onSuccess { message = "备份导出完成" }.onFailure { message = it.message ?: "导出失败" }
                }
            }) { Text("导出") }
            Button(onClick = {
                scope.launch {
                    try {
                        val picked = PlatformServices.filePicker().pickFile()
                        if (picked == null) {
                            message = "未选择文件"
                        } else {
                            val result = service.importArchive(picked.bytes, password, currentTimeMillis())
                            message = "已导入 ${result.recordsImported} 条记录"
                            refresh()
                        }
                    } catch (failure: Throwable) {
                        message = failure.message ?: "导入失败"
                    }
                }
            }) { Text("导入") }
        }
        Text(message, style = MaterialTheme.typography.bodySmall)
        Text("错误密码、篡改、重复导入会在写入前失败；导入使用 SQLite 事务并清理本次附件。", style = MaterialTheme.typography.bodySmall)
    }
}

internal expect fun currentTimeMillis(): Long
