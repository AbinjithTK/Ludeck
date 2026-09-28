import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play upload key. android/key.properties (gitignored) points at a keystore
// kept OUTSIDE the repo; docs/RELEASE-SIGNING.md has the one-time setup.
//   storeFile=C:/Users/<you>/keys/ludeck-upload.jks
//   storePassword=...   keyAlias=upload   keyPassword=...
// Without it, release APKs for the emulator still build on the debug key, but
// an app bundle (the only thing Play accepts) refuses to build: a
// debug-signed bundle is rejected on upload, and finding that out at the
// Play Console is later than finding it out here.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasUploadKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }

gradle.taskGraph.whenReady {
    // Exactly the app-bundle task. A prefix match also caught AGP's internal
    // bundle*Release tasks that assembleRelease runs, and blocked emulator APKs.
    val bundling = allTasks.any { it.path == ":app:bundleRelease" }
    if (bundling && !hasUploadKey) {
        throw GradleException(
            "Release app bundle needs the Play upload key: create android/key.properties " +
                "(see docs/RELEASE-SIGNING.md). Refusing to build a debug-signed bundle."
        )
    }
}

android {
    namespace = "com.ludeck.ludeck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ludeck.ludeck"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                // Emulator release APKs only; bundleRelease refuses (above).
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
