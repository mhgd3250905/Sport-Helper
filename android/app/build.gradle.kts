import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// All review choices keep the internal application ID. Production never reads
// these candidate source sets. A2 is the approved production default.
// Flutter exposes --dart-define values as base64-encoded Gradle dart-defines.
val iconDefines = providers.gradleProperty("dart-defines").orNull
    .orEmpty().split(",").mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }
            .getOrNull()
    }.filter { it.startsWith("SMARTFIT_ICON_VARIANT=") }
    .map { it.substringAfter("=").uppercase() }.distinct()
require(iconDefines.size <= 1) { "Only one SMARTFIT_ICON_VARIANT may be supplied." }
val propertyIconVariant = providers.gradleProperty("smartfitIconVariant").orNull?.uppercase()
val definedIconVariant = iconDefines.singleOrNull()
require(propertyIconVariant == null || definedIconVariant == null ||
    propertyIconVariant == definedIconVariant) {
    "smartfitIconVariant and SMARTFIT_ICON_VARIANT disagree; supply one choice or matching values."
}
val smartfitIconVariant = propertyIconVariant ?: definedIconVariant.orEmpty()
require(smartfitIconVariant in setOf("", "A", "B", "A2")) {
    "smartfitIconVariant / SMARTFIT_ICON_VARIANT must be A, B, or A2 (or omitted)."
}

// Upload keys and passwords stay outside the repository. Release artifacts
// must never silently fall back to the Android debug certificate.
val signingPropertiesPath = providers.environmentVariable("SMARTFIT_SIGNING_PROPERTIES").orNull
val uploadProperties = Properties()
if (!signingPropertiesPath.isNullOrBlank()) {
    val signingFile = file(signingPropertiesPath).canonicalFile
    require(signingFile.isFile) { "The external upload-signing properties file is missing." }
    require(!signingFile.toPath().startsWith(rootProject.projectDir.parentFile.canonicalFile.toPath())) {
        "Upload-signing properties must be outside the App repository."
    }
    signingFile.inputStream().use { uploadProperties.load(it) }
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !uploadProperties.getProperty(it).isNullOrBlank() }) {
        "The external upload-signing properties file is incomplete."
    }
}

gradle.taskGraph.whenReady {
    val buildsReleaseArtifact = allTasks.any {
        it.project == project &&
            it.name.matches(Regex("(?i)(assemble|bundle|package|validateSigning).*Release.*"))
    }
    require(!buildsReleaseArtifact || !signingPropertiesPath.isNullOrBlank()) {
        "Release artifacts require SMARTFIT_SIGNING_PROPERTIES; debug-key fallback is disabled."
    }
}

android {
    namespace = "com.ugk.smartfit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent Google Play identity; do not change after the first upload.
        applicationId = "com.ugk.smartfit"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("production") {
            dimension = "distribution"
        }
        create("internal") {
            dimension = "distribution"
            applicationIdSuffix = ".internal"
        }
    }

    if (smartfitIconVariant.isNotEmpty()) {
        sourceSets.getByName("internal").res.srcDir(
            "src/internal/iconVariants/$smartfitIconVariant/res"
        )
    }

    signingConfigs {
        if (!signingPropertiesPath.isNullOrBlank()) {
            create("upload") {
                storeFile = file(uploadProperties.getProperty("storeFile"))
                storePassword = uploadProperties.getProperty("storePassword")
                keyAlias = uploadProperties.getProperty("keyAlias")
                keyPassword = uploadProperties.getProperty("keyPassword")
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingPropertiesPath.isNullOrBlank()) null
                else signingConfigs.getByName("upload")
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
