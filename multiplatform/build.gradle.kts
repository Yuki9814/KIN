plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.kotlin.multiplatform.library) apply false
    alias(libs.plugins.jetbrains.compose) apply false
}

val kinVersion = providers.gradleProperty("kinVersion")
    .map(String::trim)
    .map { it.ifBlank { "0.1.5" } }
    .orElse("0.1.5")
    .get()

allprojects {
    group = "app.kin"
    version = kinVersion

}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask<*>>().configureEach {
        compilerOptions {
            freeCompilerArgs.addAll("-Xexpect-actual-classes")
        }
    }
}

tasks.register("test") {
    group = "verification"
    description = "Runs the sharedLogic JVM test suite (including commonTest)."
    dependsOn(":sharedLogic:desktopTest")
}
