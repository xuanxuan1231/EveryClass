plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.everyclass"
    // Android 16 (API 36) 起支持 Live Updates（Notification.ProgressStyle /
    // FLAG_PROMOTED_ONGOING），低版本自动回退到普通常驻通知。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.everyclass"
        // 通知渠道需要 API 26。
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // Android 16 Live Updates（提升为实时更新）所需的较新 androidx.core：
    // NotificationCompat.ProgressStyle、setRequestPromotedOngoing、setShortCriticalText。
    implementation("androidx.core:core-ktx:1.18.0")
}
