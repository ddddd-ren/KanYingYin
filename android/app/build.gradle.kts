plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath =
    providers.environmentVariable("KANYINGYIN_ANDROID_KEYSTORE").orNull
val releaseStorePassword =
    providers.environmentVariable("KANYINGYIN_ANDROID_STORE_PASSWORD").orNull
val releaseKeyAlias =
    providers.environmentVariable("KANYINGYIN_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword =
    providers.environmentVariable("KANYINGYIN_ANDROID_KEY_PASSWORD").orNull
val releaseSigningReady = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseRequested && !releaseSigningReady) {
    throw GradleException("Android Release 缺少 KANYINGYIN_ANDROID_* 签名环境变量")
}

val androidVersionName = "2.1.101"
val androidVersionCode = 20101

android {
    namespace = "com.kanyingyin.player"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kanyingyin.player"
        minSdk = 24
        targetSdk = 36
        versionCode = androidVersionCode
        versionName = androidVersionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
