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
// super_keyboard (from super_editor) still builds against Android 34; its dependencies need 36.
subprojects {
    if (name == "super_keyboard") {
        val raise = { extensions.configure<com.android.build.gradle.LibraryExtension>("android") { compileSdk = 36 } }
        if (state.executed) raise() else afterEvaluate { raise() }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
