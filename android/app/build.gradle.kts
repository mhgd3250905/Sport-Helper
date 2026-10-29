import java.util.Base64
import java.net.URI
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// All review choices keep the internal application ID. Production never reads
// these candidate source sets. The local default A2 is awaiting visual approval.
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

// A release/internal artifact must have an explicit video origin. Decode only
// this public setting; never include the other dart-defines in diagnostics.
val mediaPrimaryDefines = providers.gradleProperty("dart-defines").orNull
    .orEmpty().split(",").mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }
            .getOrNull()
    }.filter { it.startsWith("SMARTFIT_MEDIA_PRIMARY_URL=") }
    .map { it.substringAfter("=").trim() }.distinct()

gradle.taskGraph.whenReady {
    val protectedBuild = allTasks.any {
        it.project == project &&
            (it.name.contains("release", ignoreCase = true) ||
                it.name.contains("internal", ignoreCase = true))
    }
    if (protectedBuild) {
        require(mediaPrimaryDefines.size == 1 && mediaPrimaryDefines.single().isNotEmpty()) {
            "SMARTFIT_MEDIA_PRIMARY_URL is required for release/internal builds."
        }
        val mediaOrigin = runCatching { URI(mediaPrimaryDefines.single()) }.getOrNull()
        require(mediaOrigin != null && mediaOrigin.scheme == "https" &&
            !mediaOrigin.host.isNullOrEmpty() && mediaOrigin.userInfo == null &&
            mediaOrigin.rawQuery == null && mediaOrigin.rawFragment == null &&
            mediaOrigin.path.endsWith("/") && mediaOrigin.normalize() == mediaOrigin) {
            "SMARTFIT_MEDIA_PRIMARY_URL must be a public HTTPS directory without credentials or query."
        }
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Keep the ELF bytes/alignment; Android extracts these compressed
            // libraries at install time rather than mapping them from the APK.
            useLegacyPackaging = true
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

// Check the actual APK, including transitive Flutter package assets. Source
// directory checks alone cannot prevent a dependency from bundling a video.
tasks.configureEach {
    if (name.startsWith("assemble") &&
        (name.contains("Release") || name.contains("Internal"))) {
        doLast {
            fileTree(layout.buildDirectory.dir("outputs/apk")) {
                include("**/*.apk")
            }.files.forEach { apk ->
                ZipFile(apk).use { archive ->
                    val entries = archive.entries().asSequence().toList()
                    require(entries.none { it.name.endsWith(".mp4", ignoreCase = true) }) {
                        "Slim asset gate: APK must not contain bundled MP4 files."
                    }
                    val manifest = archive.getEntry("assets/flutter_assets/AssetManifest.bin")
                    require(manifest != null) { "Slim asset gate: missing Flutter AssetManifest.bin." }
                    val assetNames = archive.getInputStream(manifest).use { stream ->
                        String(stream.readBytes(), Charsets.ISO_8859_1)
                    }
                    require(!assetNames.contains(".mp4", ignoreCase = true)) {
                        "Slim asset gate: AssetManifest must not reference MP4 files."
                    }
                }
            }
        }
    }
}
