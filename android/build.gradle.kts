// ═══════════════════════════════════════════════════════════════════════════════════════
// ★ 2026-11-08（Android 第 4 次修复）：**这段必须放在文件最前面**
//
//   🛢️ 第 3 次失败原文（run 42481232340）：
//     `Build file '.../android/build.gradle.kts' line: 47`
//     `Cannot run Project.afterEvaluate(Action) when the project is already evaluated.`
//     全量日志里 **一条 `[kpxx]` 都没有** ⇒ 反射代码一次都没执行，配置阶段就炸了。
//   🛢️ 根因：本文件原来的**第 19 行 `project.evaluationDependsOn(":app")`**
//     —— 它在**根脚本配置期间就强制评估 `:app`**，而 Flutter 的 Gradle 插件会顺带把
//     各 plugin 子工程一起拉进配置 ⇒ 等脚本走到文件末尾那段 `subprojects{ afterEvaluate{} }` 时，
//     子工程**已经评估完了** ⇒ 再注册 afterEvaluate 直接抛异常 ☠
//   ✅ 修法：把这段**挪到文件最顶部**（此时还没任何子工程被评估 ⇒ 注册必然成功）。
//     注册成功后，回调仍在**插件自己 `compileSdkVersion 31` 之后**执行 ⇒ 我们的 36 生效 ✅
//   ✅ 另加 `state.executed` 兜底：万一将来又有人把 `evaluationDependsOn` 放到前面，
//     这里会**打印出是哪个模块被跳过**，而不是整场构建炸掉。
//
//   要解决的问题（第 2 次失败原文，run 42480382666）：
//     `:media_kit_video:checkReleaseAarMetadata` → 22 issues，全因
//     `:media_kit_video is currently compiled against android-31`，依赖要求 33/34/36。
//   本机 pub 缓存实读：写死 31 的插件有三个 ——
//     `media_kit_video-1.2.5` / `volume_controller-2.0.8` / `screen_brightness_android-0.1.0+2`
//   ⇒ 一次全抬到 36（36 ≥ 33/34/36 全部要求）。
//
//   ⚠️ 为什么不改插件源码：在 `~/.pub-cache` 里，改了不入库、CI 上仍是原版 ⇒ 无效
//   ⚠️ 为什么不升 media_kit_video：会牵动 iOS 播放链路（用户口径：不动 iOS）
//   ✅ 为什么用反射：不依赖 AGP 类型在根脚本可见（本机无 Android SDK，没法验证那个前提）；
//      `compileSdkVersion(int)` 一定存在 —— 那三个插件自己的 build.gradle 就在调它。
// ═══════════════════════════════════════════════════════════════════════════════════════
subprojects {
    if (state.executed) {
        logger.lifecycle("[kpxx] ${name}: ⚠️ 已评估，afterEvaluate 注册不了（compileSdk 可能仍是 31）")
    } else {
        afterEvaluate {
            val androidExt = extensions.findByName("android") ?: return@afterEvaluate
            var done = false
            for (m in listOf("compileSdkVersion", "compileSdk")) {
                if (done) break
                // ⚠️ `Int::class.javaPrimitiveType` 是 `Class<Int>?`（可空），getMethod 的可变参数要求非空
                val prim = Int::class.javaPrimitiveType!!
                done = runCatching {
                    androidExt.javaClass.getMethod(m, prim).invoke(androidExt, 36)
                }.isSuccess
                if (done) logger.lifecycle("[kpxx] ${name}: 用 $m(36) 覆盖 compileSdk 成功")
            }
            if (!done) {
                logger.lifecycle("[kpxx] ${name}: ⚠️ compileSdk 覆盖失败（找不到 compileSdkVersion/compileSdk(int)）")
            }
        }
    }
}

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

// ⚠️ 2026-11-08：原来这里还有一段 `subprojects { afterEvaluate { ...通compileSdk... } }`，
//   **已整块挪到文件最顶部**（原因见顶部那段注释：此处执行时子工程早已被
//   `evaluationDependsOn(":app")` 评估完，注册 afterEvaluate 会抛
//   `Cannot run Project.afterEvaluate(Action) when the project is already evaluated`）。
//   两份不能共存 —— 这里注册会立刻复现那个异常 ☠ 故删除。

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
