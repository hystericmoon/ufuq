import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.compose.multiplatform)
}

// Windows desktop app (plan W1/W2). Compose Multiplatform Desktop on top of the pure-Kotlin :core.
// Bytecode targets Java 17; the app and jpackage run on JDK 21 (CI uses Temurin 21).
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

tasks.withType<JavaCompile>().configureEach { options.release.set(17) }

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        allWarningsAsErrors.set(true)
    }
}

// adhan2 0.0.5 (prayer times in :core) is binary-incompatible with kotlinx-datetime 0.6+, but
// Compose Material3 pulls 0.7.1 in. Without this pin every prayer time fails with NoSuchMethodError.
// Material3 only uses datetime in its date pickers, which this app does not use.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlinx" && requested.name.startsWith("kotlinx-datetime")) useVersion("0.5.0")
    }
}

dependencies {
    implementation(project(":core"))
    implementation(compose.desktop.currentOs)
    implementation(libs.compose.mp.foundation)
    implementation(libs.compose.mp.material3)
    implementation(libs.kotlinx.coroutines.swing)
    implementation(libs.jna)
    implementation(libs.jna.platform)
    implementation(libs.jnativehook)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.compose.mp.ui.test)
}

val screenshotDir = layout.buildDirectory.dir("screenshots")

tasks.test {
    // Headless on CI: the screenshot tests render with Skia on the CPU.
    systemProperty("java.awt.headless", "true")
    systemProperty("ufuq.screenshotDir", screenshotDir.get().asFile.absolutePath)
    outputs.dir(screenshotDir)
}

compose.desktop {
    application {
        mainClass = "app.ufuq.desktop.MainKt"

        // jpackage builds the MSI on a Windows runner (WiX 3 is preinstalled on windows-latest).
        nativeDistributions {
            targetFormats(TargetFormat.Msi)
            packageName = "Ufuq"
            packageVersion = "0.1.0"
            description = "Prayer times and AI usage in a floating island"
            vendor = "Ufuq"
            modules("java.instrument", "java.management", "java.naming", "java.net.http", "java.prefs", "java.sql", "jdk.unsupported")
            windows {
                // Never change this: it is how an MSI upgrade finds the installed version.
                upgradeUuid = "5b0d2f7e-3c1a-4e8b-9a64-7f21c3d8e0a5"
                menu = true
                menuGroup = "Ufuq"
                shortcut = true
                dirChooser = true
                perUserInstall = true
            }
        }
    }
}
