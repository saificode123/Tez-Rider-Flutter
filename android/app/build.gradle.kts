import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") apply false
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Android TEST FCM uses only its own registered Firebase configuration.
// Until supplied, existing in-app TEST builds remain usable with push disabled.
val isFr21TestBuild = gradle.startParameter.taskNames.any { it.contains("Fr21test", ignoreCase = true) }
val includesProductionRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true) && !it.contains("Fr21test", ignoreCase = true)
}
val productionApplicationId = providers.gradleProperty("tezriderApplicationId")
    .orElse("com.example.flutter_application_1").get()
val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.exists()) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseProperties.getProperty(it).isNullOrBlank() }
if (includesProductionRelease) {
    require(!productionApplicationId.startsWith("com.example.")) {
        "Set the approved production ID with -PtezriderApplicationId before building production."
    }
    require(hasReleaseSigning && rootProject.file(releaseProperties.getProperty("storeFile")).isFile) {
        "Production release requires a valid private android/key.properties and upload keystore."
    }
}
if (!isFr21TestBuild || file("src/fr21test/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.flutter_application_1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_application_1"
        manifestPlaceholders["appLabel"] = "TezRider"

        // ✅ FIXED: local_auth requires minimum SDK 23
        // Do NOT use flutter.minSdkVersion — it defaults to 21
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
            applicationId = productionApplicationId
            signingConfig = signingConfigs.findByName("release")
        }
        create("fr21test") {
            dimension = "environment"
            applicationIdSuffix = ".fr21test"
            manifestPlaceholders["appLabel"] = "TezRider TEST"
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildTypes {
        release {
            // Each flavor supplies its signing key; production never falls back
            // to the TEST/debug key, including multi-flavor Gradle invocations.
            signingConfig = null
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
