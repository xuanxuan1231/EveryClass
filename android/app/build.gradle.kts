import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Jetpack Glance 桌面小组件的 @Composable 需要 Compose 编译器插件。
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun keystoreProperty(name: String): String? =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val hasReleaseSigning =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        keystoreProperty(it) != null
    }

android {
    namespace = "top.helloswx.everyclass"
    // Android 16 (API 36) 起支持 Live Updates（Notification.ProgressStyle /
    // FLAG_PROMOTED_ONGOING），低版本自动回退到普通常驻通知。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "top.helloswx.everyclass"
        // 通知渠道需要 API 26。
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = file(keystoreProperty("storeFile")!!)
                storePassword = keystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
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

flutter {
    source = "../.."
}

dependencies {
    // Android 16 Live Updates（提升为实时更新）所需的较新 androidx.core：
    // NotificationCompat.ProgressStyle、setRequestPromotedOngoing、setShortCriticalText。
    implementation("androidx.core:core-ktx:1.18.0")
    // 桌面服务卡片（今日课表 / 实时活动小组件）——Jetpack Glance。
    implementation("androidx.glance:glance-appwidget:1.1.1")
}
