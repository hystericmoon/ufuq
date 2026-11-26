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

// Version and update key (plan W3). The repo-root VERSION is shared by every platform.
val appVersion: String = rootProject.file("../VERSION").readText().trim()

// MSI needs MAJOR.MINOR.BUILD, all numeric: drop any pre-release suffix and pad to three parts.
val msiVersion: String = appVersion.substringBefore('-').substringBefore('+').split('.')
    .let { parts -> (parts + listOf("0", "0", "0")).take(3) }
    .also { parts -> require(parts.all { it.toIntOrNull() != null }) { "VERSION '$appVersion' is not numeric dotted" } }
    .joinToString(".")

// Base64 raw 32-byte Ed25519 public key. Absent means updates are off (development builds).
val updatePublicKey: String = (providers.gradleProperty("UFUQ_UPDATE_PUBLIC_KEY").orNull
    ?: providers.environmentVariable("UFUQ_UPDATE_PUBLIC_KEY").orNull).orEmpty().trim()

val generatedBuildInfo = layout.buildDirectory.dir("generated/buildinfo")
abstract class GenerateBuildInfo : DefaultTask() {
    @get:Input abstract val version: Property<String>
    @get:Input abstract val publicKey: Property<String>
    @get:OutputDirectory abstract val outDir: DirectoryProperty

    @TaskAction fun write() {
        val dir = outDir.get().asFile
        dir.mkdirs()
        File(dir, "ufuq-build.properties").writeText("version=${version.get()}\nupdatePublicKey=${publicKey.get()}\n")
    }
}

val generateBuildInfo by tasks.registering(GenerateBuildInfo::class) {
    version.set(appVersion)
    publicKey.set(updatePublicKey)
    outDir.set(generatedBuildInfo)
}
sourceSets.main { resources.srcDir(generateBuildInfo) }

compose.desktop {
    application {
        mainClass = "app.ufuq.desktop.MainKt"

        // jpackage builds the MSI on a Windows runner (WiX 3 is preinstalled on windows-latest).
        nativeDistributions {
            targetFormats(TargetFormat.Msi)
            packageName = "Ufuq"
            packageVersion = msiVersion
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
