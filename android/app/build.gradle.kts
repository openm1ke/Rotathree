import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun signingProperties(name: String) = Properties().apply {
    val file = rootProject.file(name)
    if (file.exists()) file.inputStream().use { load(it) }
}
val storeKeys = mapOf("play" to signingProperties("key.properties"), "rustore" to signingProperties("key-rustore.properties"))
val signingFields = mapOf("storeFile" to "KEYSTORE", "storePassword" to "STORE_PASSWORD", "keyAlias" to "KEY_ALIAS", "keyPassword" to "KEY_PASSWORD")
fun releaseValue(store: String, field: String): String? =
    storeKeys.getValue(store).getProperty(field)?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable("ROTATHREE_${store.uppercase()}_${signingFields.getValue(field)}").orNull?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable("ROTATHREE_${signingFields.getValue(field)}").orNull?.takeIf { it.isNotBlank() }
val releaseReady = storeKeys.keys.associateWith { store -> signingFields.keys.all { !releaseValue(store, it).isNullOrBlank() } }
val releaseId = providers.gradleProperty("rotathreeApplicationId")
    .orElse(providers.environmentVariable("ROTATHREE_APPLICATION_ID")).getOrElse("ru.izpz.rotathree")
// Only an explicit local-update build may retain the old test application ID.
val localRelease = providers.gradleProperty("rotathreeLocalRelease").map { it == "true" }.getOrElse(false)

gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { it.project == project && it.name.endsWith("Release") }
    if (releaseTasks.isNotEmpty()) {
        for (store in storeKeys.keys) {
            if (releaseTasks.any { it.name.contains("${store}Release", ignoreCase = true) }) {
                check(releaseReady.getValue(store)) { "Configure signing for $store: android/key${if (store == "play") "" else "-rustore"}.properties or ROTATHREE_${store.uppercase()}_* variables." }
            }
        }
        check(localRelease || !releaseId.startsWith("com.example.")) { "A store release requires the publishing application ID." }
    }
}

android {
    namespace = "ru.izpz.rotathree"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = releaseId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        for (store in storeKeys.keys) {
            if (releaseReady.getValue(store)) create("${store}Release") {
                storeFile = rootProject.file(releaseValue(store, "storeFile")!!)
                storePassword = releaseValue(store, "storePassword")
                keyAlias = releaseValue(store, "keyAlias")
                keyPassword = releaseValue(store, "keyPassword")
            }
        }
    }

    flavorDimensions += "store"
    productFlavors {
        create("play") {
            dimension = "store"
            if (releaseReady.getValue("play")) signingConfig = signingConfigs.getByName("playRelease")
        }
        create("rustore") {
            dimension = "store"
            applicationIdSuffix = ".rustore"
            if (releaseReady.getValue("rustore")) signingConfig = signingConfigs.getByName("rustoreRelease")
        }
    }
    buildTypes {
        debug { applicationIdSuffix = ".debug" }
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

// Flutter writes AOT libraries during its compile task. AGP's cached JNI
// merges can retain an older libapp.so even after that file has changed.
tasks.configureEach {
    if (name.startsWith("merge") &&
        (name.endsWith("JniLibFolders") || name.endsWith("NativeLibs"))) {
        outputs.upToDateWhen { false }
    }
}
