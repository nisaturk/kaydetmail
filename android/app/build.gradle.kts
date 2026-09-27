import java.io.FileInputStream
import java.util.Properties


plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("com.google.firebase.firebase-perf")
}
val releaseSigningProperties = Properties()
val releaseSigningFile = rootProject.file("key.properties")
if (releaseSigningFile.exists()) {
    FileInputStream(releaseSigningFile).use(releaseSigningProperties::load)
}

fun releaseSigningValue(property: String, environment: String): String? =
    releaseSigningProperties.getProperty(property)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environment)?.takeIf { it.isNotBlank() }

val releaseStoreFile = releaseSigningValue("storeFile", "KAYDETMAIL_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "KAYDETMAIL_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "KAYDETMAIL_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "KAYDETMAIL_KEY_PASSWORD")
val hasReleaseSigning =
    listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
        .all { it != null }

android {
    namespace = "com.kaydetmail.app"
    // receive_sharing_intent requires 37; flutter's default is 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kaydetmail.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project == project &&
            it.name.contains("Release", ignoreCase = true) &&
            (it.name.startsWith("assemble") ||
                it.name.startsWith("bundle") ||
                it.name.startsWith("package"))
    }
    check(!buildsRelease || hasReleaseSigning) {
        "Release signing is not configured. Add android/key.properties or the KAYDETMAIL_KEYSTORE_* environment variables."
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // local_auth: LaunchTheme now extends Theme.AppCompat.DayNight so its
    // biometric dialog doesn't crash on Android 8 and below (see
    // res/values/styles.xml and the local_auth_android setup README).
    implementation("androidx.appcompat:appcompat:1.7.0")
}
