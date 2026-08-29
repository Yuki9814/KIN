package app.kin.desktop

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import app.kin.shared.platform.PlatformServices
import app.kin.ui.KinApp

fun main() {
    PlatformServices.initialize()
    application {
        Window(onCloseRequest = ::exitApplication, title = "KIN · 有灵") {
            KinApp()
        }
    }
}
