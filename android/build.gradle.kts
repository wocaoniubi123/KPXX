allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ★ 2026-11-08（修「首次/第二次 Android 云端构建」的第二个阻塞点）
//
//   🛢️ 报错原文（run 42480382666，步骤 #9 `Flutter build APK`）：
//     `Execution failed for task ':media_kit_video:checkReleaseAarMetadata'.`
//     `22 issues were found when checking AAR metadata:`
//     `1. Dependency ':wakelock_plus' requires ... compile against version 36 or later`
//     `   :media_kit_video is currently compiled against android-31.`
//     （22 条全同一个受害者 `:media_kit_video`，只是依赖项不同；要求最高到 36）
//
//   🛢️ 本机 pub 缓存实读：**有三个插件把自己的 compileSdk 写死在 31**
//       · `media_kit_video-1.2.5/android/build.gradle`      → `compileSdkVersion 31`
//       · `volume_controller-2.0.8/android/build.gradle`    → `compileSdkVersion 31`
//       · `screen_brightness_android-0.1.0+2/android/build.gradle` → `compileSdkVersion 31`
//       其余插件没写 → 走 AGP 默认（够新）；我们自己的 `:app` 是 `flutter.compileSdkVersion`(36) ✅
//     ⇒ 只抬 `media_kit_video` 的话，另外两个下一步照样会炸 ⇒ **一次全抬到 36** ✅
//
//   ⚠️ 为什么不改插件源码：它在 `~/.pub-cache` 里，改了不入库、CI 上仍取原版 ⇒ 无效 ☠
//   ⚠️ 为什么不用 `extensions.configure<com.android.build.api.dsl.LibraryExtension>`：
//       那要求 AGP 的类在**根构建脚本**里可见 —— 本机没有 Android SDK，我**没法验证**这个前提。
//   ✅ 改用**反射**调 `compileSdkVersion(int)`：不依赖任何 AGP 类型。
//      为什么断定这个方法一定存在 —— 那三个插件自己的 `build.gradle` 就在用 `compileSdkVersion 31`，
//      AGP 不可能把这个方法删掉（删了它们自己就编译不了）。
//      同时兼容性兜底：也试 AGP 新 DSL 的 `compileSdk(int)`。
//   ⚠️ 只在 `afterEvaluate` 里改 ⇒ 一定**晚于**插件自己的 `compileSdkVersion 31` ⇒ 我们的 36 生效 ✅
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        var done = false
        for (m in listOf("compileSdkVersion", "compileSdk")) {
            if (done) break
            // ⚠️ `Int::class.javaPrimitiveType` 的类型是 `Class<Int>?`（可空），而 getMethod 的
            //    可变参数要求非空 ⇒ 必须 `!!`，否则 Kotlin DSL 编译不过 ☠
            val prim = Int::class.javaPrimitiveType!!
            done = runCatching {
                androidExt.javaClass.getMethod(m, prim).invoke(androidExt, 36)
            }.isSuccess
            if (done) logger.lifecycle("[kpxx] ${project.name}: 用 $m(36) 覆盖 compileSdk 成功")
        }
        if (!done) {
            logger.lifecycle("[kpxx] ${project.name}: ⚠️ compileSdk 覆盖失败（找不到 compileSdkVersion/compileSdk(int)）")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
