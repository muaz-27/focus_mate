allprojects {
    repositories {
        google()
        mavenCentral()
    }
}



val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null && android.namespace == null) {
            val manifestFile = project.file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val manifestXml = manifestFile.readText()
                val packageRegex = Regex("""package=["']([^"']+)["']""")
                val matchResult = packageRegex.find(manifestXml)
                val packageName = matchResult?.groupValues?.get(1)
                if (packageName != null) {
                    android.namespace = packageName
                }
            } else if (project.name == "device_apps") {
                android.namespace = "fr.g123k.deviceapps"
            }
        }
        
        // Force compileSdkVersion to fix lStar error in plugins like device_apps
        if (android != null) {
            android.compileSdkVersion(36)
        }
    }
}






tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}