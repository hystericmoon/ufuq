import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.roborazzi)
}

// Same as Adwam (muslimdaily/app/build.gradle.kts): compile/target SDK 37, minSdk 26.
val robolectricRepoUrl: String? = providers.gradleProperty("ufuq.robolectricRepoUrl").orNull

// One version for every platform: the repo-root VERSION (docs/release-android.md).
val appVersion: String = rootProject.file("../VERSION").readText().trim()
val appVersionCode: Int = appVersion.split('.').map { it.toIntOrNull() ?: error("VERSION '$appVersion' is not numeric dotted") }
    .also { require(it.size == 3) { "VERSION '$appVersion' must be MAJOR.MINOR.PATCH" } }
    .let { (major, minor, patch) -> major * 1_000_000 + minor * 1_000 + patch }

// Release signing (release-android.yml decodes UFUQ_KEYSTORE_BASE64 to the file in UFUQ_KEYSTORE_FILE).
// Without it a local release build is signed with the shared debug key, and Gradle says so.
val releaseKeystore: File? = System.getenv("UFUQ_KEYSTORE_FILE")?.takeIf { it.isNotBlank() }?.let(::file)?.takeIf { it.isFile }
if (releaseKeystore == null && gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
    logger.warn("WARNING: UFUQ_KEYSTORE_FILE is not set; the release APK is signed with the DEBUG key and cannot update a published install.")
}
// GitHub repository whose releases the in-app updater reads.
val updateRepo = "hystericmoon/ufuq"

android {
    namespace = "app.ufuq.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.ufuq.android"
        minSdk = 26
        targetSdk = 37
        versionCode = appVersionCode
        versionName = appVersion
        buildConfigField("String", "UPDATE_REPO", "\"$updateRepo\"")
    }

    signingConfigs {
        // Shared debug key (not secret), like Adwam, so CI builds install over local builds.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("UFUQ_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("UFUQ_KEY_ALIAS")
                keyPassword = System.getenv("UFUQ_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            // Debug builds (app.ufuq.android.debug, debug key) can't install the release APK over themselves.
            buildConfigField("boolean", "SELF_UPDATE", "false")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("boolean", "SELF_UPDATE", "true")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all { test ->
                test.systemProperty("robolectric.pixelCopyRenderMode", "hardware")
                test.jvmArgs(
                    "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
                    "--add-exports=java.base/jdk.internal.access=ALL-UNNAMED",
                    "--add-opens=java.base/java.io=ALL-UNNAMED",
                )
                test.maxHeapSize = "3g"
                robolectricRepoUrl?.let { test.systemProperty("robolectric.dependency.repo.url", it) }
            }
        }
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.text)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.animation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.coroutines.android)
    // Pairing QR scan: CameraX frames decoded by ZXing core (pure Java, no ML Kit / Play services).
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.zxing.core)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(libs.robolectric)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
}

roborazzi {
    // Recorded on Linux locally for preview; CI's runner is the reference (fonts differ slightly).
    outputDir.set(layout.projectDirectory.dir("src/test/screenshots"))
}
