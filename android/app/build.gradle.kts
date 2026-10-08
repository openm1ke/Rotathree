import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeyFile = rootProject.file("key.properties")
if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { releaseKeys.load(it) }
fun releaseValue(name: String, env: String): String? =
    releaseKeys.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable(env).orNull?.takeIf { it.isNotBlank() }
val releaseStore = releaseValue("storeFile", "ROTATHREE_KEYSTORE")
val releaseStorePassword = releaseValue("storePassword", "ROTATHREE_STORE_PASSWORD")
val releaseAlias = releaseValue("keyAlias", "ROTATHREE_KEY_ALIAS")
val releasePassword = releaseValue("keyPassword", "ROTATHREE_KEY_PASSWORD")
val releaseId = providers.gradleProperty("rotathreeApplicationId")
    .orElse(providers.environmentVariable("ROTATHREE_APPLICATION_ID")).orNull
val releaseReady = listOf(releaseStore, releaseStorePassword, releaseAlias, releasePassword)
    .all { !it.isNullOrBlank() }

// Debug installs keep their existing ID and data. Publishing requires an
// explicit ID and the owner's release key; never substitute the debug key.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.endsWith("Release") }) {
        check(releaseReady) { "Configure android/key.properties or ROTATHREE_* signing variables before building a release." }
        check(!releaseId.isNullOrBlank() && !releaseId.startsWith("com.example.")) {
            "Set ROTATHREE_APPLICATION_ID (or -ProtathreeApplicationId) to your publishing application ID."
        }
    }
}

android {
    namespace = "com.example.rotathree"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = releaseId ?: "com.example.rotathree"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseReady) create("release") {
            storeFile = rootProject.file(releaseStore!!)
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releasePassword
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseReady) signingConfigs.getByName("release") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
