package app.kin.android

import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.kin.shared.platform.PlatformServices
import app.kin.ui.KinApp

class MainActivity : ComponentActivity() {
    private val openDocumentLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        PlatformServices.completePickedFile(uri)
    }

    private val createDocumentLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        PlatformServices.completeSavedFile(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PlatformServices.initialize(this)
        PlatformServices.bindFilePickerLaunchers(openDocumentLauncher, createDocumentLauncher)
        setContent { KinApp() }
    }
}
