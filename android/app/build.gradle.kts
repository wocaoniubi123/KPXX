import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ★ 2026-11-08（用户要求「配置安卓版」· 独立站点式最小改动）
//   发布签名：从 `android/key.properties` 读（**该文件被 `android/.gitignore` 忽略，绝不入库**）。
//   · **本地没有**该文件 ⇒ 自动回落 debug 签名 ⇒ 照样能跑 `flutter run/build`
//     （⚠️ debug 签名的包**签名每次都不同**，只能自测，不能覆盖升级另一个 build）
//   · **CI 有** ⇒ 用 Secrets 还原出稳定的 release 签名 ⇒ 以后能直接覆盖升级 ✅
//   · keystore 实体放在 `cert/`（`.gitignore` 已整目录忽略），由 key.properties 指过去
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    // ★ 用户拍板：包名 `ysc.tool6041.sign`（与 iOS 的 CFBundleIdentifier 完全一致）
    //   ⚠️ `namespace` 必须与 `MainActivity.kt` 的 package 一致
    //      （文件已放在 `kotlin/ysc/tool6041/sign/`），否则清单里的 `.MainActivity` 解析不到 ⇒ 启动即崩
    namespace = "ysc.tool6041.sign"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ysc.tool6041.sign"
        // ★ 用户拍板：**minSdk 24 = Android 7.0**
        //   依据（本机实测）：Flutter 3.47.6 默认 `minSdkVersion = 24`（FlutterExtension.kt:26），
        //   且解析出的插件里最高的也是 24（video_player_android 2.12.2 / webview_flutter_android 4.14.1 /
        //   shared_preferences_android 2.5.1 / image_picker_android 0.8.13+25 /
        //   flutter_plugin_android_lifecycle 2.0.35）⇒ 24 是硬地板，写死避免日后被默认值漂移带走
        //   （`media_kit_libs_android_video 1.3.8` 只要求 16，不会把门槛顶高 ✅）
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // 版本号跟 iOS 同步：来自 `kAppVersion`（CI 会先把 pubspec 的 version 改成它）
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                // ⚠️ 用 `rootProject.file(...)` 而不是 `file(...)`：
                //   `file()` 是相对**本模块**（`android/app/`）解析的 ⇒ 写 `../cert/...` 会指到 `android/cert/` ✗
                //   `rootProject` = `android/` ⇒ 写 `../cert/android-keystore.p12` 正好指到仓库根的 `cert/` ✅
                //   CI 上把 p12 放到 `android/keystore.p12`，properties 里写 `keystore.p12` 即可 ✅
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                // 本 keystore 是 **PKCS12**（openssl 生成）；不写这行 AGP 也能按扩展名猜，但写死更稳
                storeType = keystoreProperties.getProperty("storeType") ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 没有 key.properties（本机）⇒ 回落 debug 签名，保证可编译
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
