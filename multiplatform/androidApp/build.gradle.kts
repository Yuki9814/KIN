plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

fun releaseSecret(propertyName: String, environmentName: String): String? =
    providers.gradleProperty(propertyName).orNull
        ?: providers.environmentVariable(environmentName).orNull

val releaseStoreFile = releaseSecret("kinReleaseStoreFile", "KIN_RELEASE_STORE_FILE")
val releaseStorePassword = releaseSecret("kinReleaseStorePassword", "KIN_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = releaseSecret("kinReleaseKeyAlias", "KIN_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseSecret("kinReleaseKeyPassword", "KIN_RELEASE_KEY_PASSWORD")
val releaseStoreType = releaseSecret("kinReleaseStoreType", "KIN_RELEASE_STORE_TYPE")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { !it.isNullOrBlank() }
val kinReleaseUnsigned = providers.gradleProperty("kinReleaseUnsigned").orNull
    ?.trim()
    ?.equals("true", ignoreCase = true) == true
val useReleaseSigning = hasReleaseSigning && !kinReleaseUnsigned

if (!hasReleaseSigning && !kinReleaseUnsigned) {
    logger.lifecycle("KIN release signing is not configured; release packaging will be blocked instead of producing a falsely signed APK")
} else if (kinReleaseUnsigned) {
    logger.lifecycle("KIN unsigned release explicitly requested; no Android signing configuration will be attached")
}

android {
    namespace = "app.kin.android"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "app.kin.android"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 4
        versionName = project.version.toString()
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // An explicit unsigned release always wins, even if a signing
            // secret happens to be present in the environment. In the
            // unsigned path this remains null; AGP must never inherit debug.
            signingConfig = if (useReleaseSigning) {
                signingConfigs.create("release") {
                    storeFile = file(requireNotNull(releaseStoreFile))
                    storeType = releaseStoreType ?: if (releaseStoreFile!!.lowercase().let { it.endsWith(".p12") || it.endsWith(".pfx") }) {
                        "PKCS12"
                    } else {
                        null
                    }
                    storePassword = requireNotNull(releaseStorePassword)
                    keyAlias = requireNotNull(releaseKeyAlias)
                    keyPassword = requireNotNull(releaseKeyPassword)
                }
            } else {
                null
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.configureEach {
    if (name in setOf("assembleRelease", "packageRelease", "bundleRelease")) {
        doFirst {
            check(hasReleaseSigning || kinReleaseUnsigned) {
                "Release signing is required unless kinReleaseUnsigned=true is explicitly set. Set kinReleaseStoreFile/kinReleaseStorePassword/kinReleaseKeyAlias/kinReleaseKeyPassword Gradle properties or KIN_RELEASE_* environment variables."
            }
        }
    }
}

dependencies {
    implementation(project(":sharedUI"))
    implementation(project(":sharedLogic"))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
}
