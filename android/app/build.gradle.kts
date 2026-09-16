import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigning = mapOf(
    "storeFile" to providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull,
    "storePassword" to providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull,
    "keyAlias" to providers.environmentVariable("ANDROID_KEY_ALIAS").orNull,
    "keyPassword" to providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull,
)
val hasReleaseSigning = releaseSigning.values.all { !it.isNullOrBlank() }
val requestedReleaseBuild = gradle.startParameter.taskNames.any {
    it.substringAfterLast(':') in setOf("assembleRelease", "bundleRelease")
}

// Without signing variables a release build is left unsigned, which is what
// F-Droid and other reproducible-build pipelines expect: they sign the APK
// themselves. The GitHub release workflow sets RESCRIPTO_REQUIRE_SIGNING so a
// missing secret fails the build instead of publishing an unsigned APK.
val requireSigning = providers.environmentVariable("RESCRIPTO_REQUIRE_SIGNING").orNull == "true"
if (requestedReleaseBuild && requireSigning && !hasReleaseSigning) {
    throw GradleException(
        "Release signing requires ANDROID_KEYSTORE_PATH, " +
            "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD.",
    )
}

android {
    namespace = "com.rescripto.rescripto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // Native inference backends must be real files in
            // applicationInfo.nativeLibraryDir.  Android can dlopen a library
            // directly from base.apk, but llama.cpp's runtime backend loader
            // needs stable filesystem paths on API 24+ devices.
            useLegacyPackaging = true
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    defaultConfig {
        applicationId = "com.rescripto.rescripto"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The complete native LLM and Whisper stack is currently verified
        // only for 64-bit ARM. AGP refuses ndk abiFilters alongside ABI
        // splits, so a --split-per-abi build relies on its --target-platform
        // (and the packaging excludes above) instead.
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseSigning.getValue("storeFile")!!)
                storePassword = releaseSigning.getValue("storePassword")
                keyAlias = releaseSigning.getValue("keyAlias")
                keyPassword = releaseSigning.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    // AGP otherwise embeds a dependency list encrypted with a Google Play
    // key. Nobody else can read it, and F-Droid rejects APKs that carry it.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

// `flutter build apk --split-per-abi` gives each ABI its own APK, so each one
// needs its own version code: versionCode * 10 + the ABI's number. F-Droid's
// build recipe relies on this scheme. Builds that aren't split keep the plain
// versionCode.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
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
