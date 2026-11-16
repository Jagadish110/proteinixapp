import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the repo in android/key.properties.
//
// Absent on a machine that only builds debug, which must keep working — so a
// missing file is not an error here. `signingConfigs` below falls back to the
// debug key when this is empty, and the release build then *says* so rather
// than producing an artifact that looks shippable and isn't.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// The Flutter app's .env, read here only for ADMOB_APP_ID, which has to end
// up in the manifest and so cannot be read at runtime like the other keys.
// A missing file or key is not an error: the build falls back to Google's
// public sample AdMob app id, which can only ever serve test ads.
val dotEnv = Properties().apply {
    val file = rootProject.file("../.env")
    if (file.exists()) file.inputStream().use { load(it) }
}
val admobAppId: String = dotEnv.getProperty("ADMOB_APP_ID")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?: "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.proteinix"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.proteinix"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        manifestPlaceholders["admobAppId"] = admobAppId
    }
    compileOptions { isCoreLibraryDesugaringEnabled = true; sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    signingConfigs {
        // Only declared when the credentials are actually present. Registering
        // it with null paths makes Gradle fail at configuration time on any
        // machine that has no key, including a fresh clone.
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key when it exists, the debug key otherwise.
            //
            // The fallback is deliberate — `flutter build apk` has to keep
            // working for anyone without the key — but a debug-signed release
            // is not shippable: Play rejects that certificate outright, and an
            // app once published under one key can never be updated under
            // another. The warning is there so that never happens by accident.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug").also {
                    logger.warn(
                        "\n*** RELEASE BUILD IS DEBUG-SIGNED ***\n" +
                            "android/key.properties is missing, so this artifact " +
                            "cannot be uploaded to Play and must not be " +
                            "distributed.\n"
                    )
                }
            // R8 was on by default with no proguard-rules.pro, silently stripping
            // the generic-type signatures flutter_local_notifications' Gson
            // persistence layer needs at runtime — that's what threw "Missing
            // type parameter" on every scheduled notification. No proguard
            // config exists to fix narrowly, and this app isn't size-constrained
            // enough to be worth the risk of a second bad interaction elsewhere.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.health.connect:connect-client:1.1.0-rc01")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.guava:guava:32.1.3-android")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")

    // ML Kit pose-detection and the explicit CameraX artifacts were here only
    // for the pushup challenge. Food scanning goes through the Flutter camera
    // plugin, which brings its own CameraX.
}
