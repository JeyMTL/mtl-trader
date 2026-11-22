import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from `android/key.properties`, which is git-ignored
// along with the keystore itself. Keeping it out of the build file means the
// passwords are never in the repository, and a contributor without the file can
// still build: the release build falls back to the debug key and says so.
//
// Create the file with:
//   storePassword=…
//   keyPassword=…
//   keyAlias=upload
//   storeFile=../upload-keystore.jks
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
if (!hasReleaseKeystore) {
    logger.lifecycle(
        "Release will be signed with the debug key: android/key.properties is missing. " +
            "A Play upload needs a real keystore (see mobile_flutter/README.md)."
    )
}

android {
    // The application id is permanent after the first Play upload, so it is the
    // product's own name rather than the Flutter template's folder-derived one.
    // It also matches the OAuth redirect scheme in AndroidManifest.xml.
    namespace = "com.mtltrader.app"
    // Pinned rather than taken from Flutter: flutter_local_notifications 23
    // pulls androidx.core 1.19, which is compiled against API 37, and the AAR
    // metadata check refuses to build this module against 36. The root build
    // file forces the same value on every plugin module; keep them in step.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications schedules with java.time, which needs the
        // desugared library to reach phones below Android 8.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.mtltrader.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            // A debug-signed bundle is rejected by Play and can never be updated
            // under the same key, so this prefers the real keystore when it is
            // present and only falls back for local `flutter run --release`.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
