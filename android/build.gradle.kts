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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// リリースビルド時の lint 検査（lintVital）を止める。
// JDK 17 で動く lint が一部プラグイン（image_picker_android）の Java ソースの解析中に落ちるため。
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital")) enabled = false
    }
}
