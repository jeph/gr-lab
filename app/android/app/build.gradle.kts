import com.android.build.api.dsl.ApplicationExtension
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

configure<ApplicationExtension> {
    namespace = "io.jeph.grlab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.jeph.grlab"
        // Android 12: Nearby-devices Bluetooth permissions without location,
        // WifiNetworkSpecifier, and MediaStore inserts without storage access.
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // `dev` installs beside `prod` (own application ID and name) and logs
    // camera traffic by default; `prod` is the release users get.
    buildFeatures {
        resValues = true
    }
    flavorDimensions += "variant"
    productFlavors {
        create("dev") {
            dimension = "variant"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "GR Lab Dev")
        }
        create("prod") {
            dimension = "variant"
            resValue("string", "app_name", "GR Lab")
        }
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
        // Kotlin warnings fail the build (AGENTS.md, "Checks").
        allWarningsAsErrors = true
    }
}

flutter {
    source = "../.."
}

// Every build first runs the workspace's static checks (format, analyzer,
// camera layer boundary) and stops when one fails (AGENTS.md, "Checks").
val flutterSdk: String =
    Properties()
        .apply { rootProject.file("local.properties").inputStream().use { load(it) } }
        .getProperty("flutter.sdk")
val workspaceChecks =
    tasks.register<Exec>("workspaceChecks") {
        val workspace = rootProject.file("../..")
        workingDir = workspace
        commandLine(workspace.resolve("tool/check.sh").path, "--static")
        environment("FLUTTER_ROOT", flutterSdk)
    }
tasks.named("preBuild") { dependsOn(workspaceChecks) }
