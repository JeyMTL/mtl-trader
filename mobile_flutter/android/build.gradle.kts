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

// Plugin modules such as file_picker still pin an old compileSdk (34), which fails
// the AAR metadata check against AndroidX libraries that need 36 or later.
// Compile every Android module against the same SDK the app itself uses; this
// block wins over the value in app/build.gradle.kts, so the two must agree.
// It is 37 because flutter_local_notifications 23 pulls androidx.core 1.19,
// which is built against API 37.
// This has to be registered before the evaluationDependsOn block below, which
// evaluates :app straight away.
val pluginCompileSdk = 37
subprojects {
    val forceCompileSdk = {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            try {
                androidExtension.withGroovyBuilder { setProperty("compileSdk", pluginCompileSdk) }
            } catch (_: Exception) {
                androidExtension.withGroovyBuilder {
                    invokeMethod("compileSdkVersion", pluginCompileSdk)
                }
            }
        }
    }
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
