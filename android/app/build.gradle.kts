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

val pubspecVersionLines =
    rootProject
        .file("../pubspec.yaml")
        .readLines(Charsets.UTF_8)
        .filter { it.startsWith("version:") }
if (pubspecVersionLines.size != 1) {
    throw GradleException("pubspec.yaml 必须包含唯一的 version 字段")
}
val pubspecVersionPattern =
    Regex("""^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$""")
val pubspecVersionMatch =
    pubspecVersionPattern.matchEntire(pubspecVersionLines.single())
        ?: throw GradleException("pubspec.yaml 的 version 格式无效")
val windowsVersionName = pubspecVersionMatch.groupValues[1]
val windowsVersionCode = pubspecVersionMatch.groupValues[2].toInt()
if (windowsVersionName != "1.0.10" || windowsVersionCode != 10010) {
    throw GradleException("pubspec.yaml 必须为 Windows 正式版 1.0.10+10010")
}
val androidVersionName = "1.0.6"
val androidVersionCode = 10006

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

    flavorDimensions += "device"
    productFlavors {
        create("mobile") {
            dimension = "device"
            applicationId = "com.kanyingyin.player"
        }
        create("tvTest") {
            dimension = "device"
            applicationId = "com.kanyingyin.player.tvtest"
        }
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
