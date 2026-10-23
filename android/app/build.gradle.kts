plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Both choices keep the internal application ID. Production never reads these
// resources, and a build without an explicit choice retains the original icon.
// Flutter exposes --dart-define values as base64-encoded Gradle dart-defines.
val iconDefines = providers.gradleProperty("dart-defines").orNull
    .orEmpty().split(",").mapNotNull { encoded ->
        runCatching { String(java.util.Base64.getDecoder().decode(encoded), Charsets.UTF_8) }
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
require(smartfitIconVariant in setOf("", "A", "B")) {
    "smartfitIconVariant / SMARTFIT_ICON_VARIANT must be A or B (or omitted)."
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
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
