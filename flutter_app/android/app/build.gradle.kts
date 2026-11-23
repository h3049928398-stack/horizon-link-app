import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val signingValues = listOf("HL_KEYSTORE", "HL_STORE_PASSWORD", "HL_KEY_ALIAS", "HL_KEY_PASSWORD")
    .associateWith { System.getenv(it).orEmpty() }
val releaseDefines = (project.findProperty("dart-defines") as String?).orEmpty().split(',')
    .filter { it.isNotBlank() }.associate {
        val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        decoded.substringBefore('=') to decoded.substringAfter('=', "")
    }
fun validateReleaseInputs() {
    check(signingValues.values.all { it.isNotBlank() }) {
        "Release signing is not configured. Set HL_KEYSTORE, HL_STORE_PASSWORD, HL_KEY_ALIAS, HL_KEY_PASSWORD privately; no debug fallback."
    }
    check(file(signingValues.getValue("HL_KEYSTORE")).isFile) { "Release keystore is missing." }
    for (name in listOf("WEEKLY_CONTENT_URL", "DEVELOPER_NAME", "CONTACT_EMAIL", "PRIVACY_POLICY_URL", "PRIVACY_EFFECTIVE_DATE", "APP_FILING_NUMBER")) {
        check(!releaseDefines[name].isNullOrBlank()) { "Missing release metadata: $name. Use scripts/build_android_release.ps1." }
    }
    for (name in listOf("WEEKLY_CONTENT_URL", "PRIVACY_POLICY_URL")) {
        val uri = URI(releaseDefines.getValue(name))
        check(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.fragment == null) { "Invalid HTTPS metadata: $name" }
    }
}
if (releaseRequested) validateReleaseInputs()
// Also protect aggregate Gradle tasks (e.g. assemble), not only Flutter's
// explicit assembleRelease/bundleRelease entry points.
gradle.taskGraph.whenReady {
    if (!releaseRequested && allTasks.any { it.project == project && it.name.contains("Release") }) {
        validateReleaseInputs()
    }
}

android {
    namespace = "com.horizonlink.horizon_link"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.horizonlink.horizon_link"
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

    signingConfigs {
        create("production") {
            if (signingValues.values.all { it.isNotBlank() }) {
                storeFile = file(signingValues.getValue("HL_KEYSTORE"))
                storePassword = signingValues.getValue("HL_STORE_PASSWORD")
                keyAlias = signingValues.getValue("HL_KEY_ALIAS")
                keyPassword = signingValues.getValue("HL_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("production")
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
