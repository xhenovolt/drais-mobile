plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.drais"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.drais"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Name the artefact after what it actually is.
//
// The default `app-debug.apk` / `app-release.apk` says nothing: two builds a
// week apart are the same filename, so the one sitting in someone's Downloads
// folder is unidentifiable and a bug report against it cannot be placed. These
// come out as `drais-1.7.1-debug.apk`, which answers "which build is this?"
// before the phone is even unlocked.
//
// AGP 9 removed the old `applicationVariants` API, so this uses the current
// variant API. `VariantOutputImpl` is where `outputFileName` still lives.
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            val impl = output as? com.android.build.api.variant.impl.VariantOutputImpl
            // versionName is a Provider and may be unset for a variant; fall
            // back rather than stamping "null" into a filename.
            val version = impl?.versionName?.orNull ?: "unversioned"
            impl?.outputFileName?.set("drais-$version-${variant.buildType}.apk")
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
