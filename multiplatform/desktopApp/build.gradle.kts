plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.jetbrains.compose)
}

val kinVersion = project.version.toString()

// jpackage rejects a native package version whose first component is zero.
// Keep Gradle/application metadata at kinVersion while mapping only that
// platform-specific installer field to a valid positive release version.
val nativePackageVersion = if (kinVersion.substringBefore('.').toIntOrNull() == 0) {
    "1.0.0"
} else {
    kinVersion
}

kotlin {
    // CI and local release builds use the pinned JDK 21 toolchain; bytecode
    // remains JVM 17-compatible in shared modules for Windows 10 support.
    jvmToolchain(21)
}

dependencies {
    implementation(project(":sharedUI"))
    implementation(project(":sharedLogic"))
    implementation(compose.desktop.currentOs)
}

compose.desktop {
    application {
        mainClass = "app.kin.desktop.MainKt"
        nativeDistributions {
            targetFormats(
                org.jetbrains.compose.desktop.application.dsl.TargetFormat.Exe,
                org.jetbrains.compose.desktop.application.dsl.TargetFormat.Msi,
            )
            packageName = "KIN"
            // jpackage requires a positive first component. Product version
            // remains kinVersion in Gradle/Android metadata; Windows
            // installers use the normalized native package version.
            packageVersion = nativePackageVersion
            // WiX 3 emits a code-page error when installer metadata contains
            // characters outside Windows-1252 on an English build host.
            description = "KIN companion app $kinVersion"
            vendor = "KIN"
            windows {
                menuGroup = "KIN"
                upgradeUuid = "7d1f3f28-7d4e-4d25-a4a8-5d9b28a7c0e1"
                shortcut = true
            }
        }
    }
}
