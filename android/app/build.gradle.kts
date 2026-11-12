import com.google.gms.googleservices.GoogleServicesTask
import groovy.json.JsonSlurper
import org.gradle.api.tasks.StopExecutionException
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
// Configure each TEST task, including those reached through assembleDebug.
// The Google Services plugin otherwise falls back to the legacy root JSON.
val testApplicationId = "com.example.flutter_application_1.fr21test"
val appBuildDirectory = layout.buildDirectory
val legacyFirebaseConfig = file("google-services.json")
tasks.withType<GoogleServicesTask>().configureEach {
    if (!name.startsWith("processFr21test")) return@configureEach

    doFirst {
        // The plugin assigns the task inputs after registering the task.
        val googleServicesTask = this as GoogleServicesTask
        val config = googleServicesTask.googleServicesJsonFiles.firstOrNull { it.isFile }
        val matchesTestClient = config != null && config != legacyFirebaseConfig &&
            runCatching {
                val json = JsonSlurper().parse(config) as Map<*, *>
                val project = json["project_info"] as Map<*, *>
                val clients = json["client"] as List<*>
                project["project_id"] == "tez-rider-fe12b" && clients.any { client ->
                    val info = (client as? Map<*, *>)?.get("client_info") as? Map<*, *>
                    val android = info?.get("android_client_info") as? Map<*, *>
                    android?.get("package_name") == testApplicationId
                }
            }.getOrDefault(false)
        if (matchesTestClient) return@doFirst

        // Remove resources from an earlier push-enabled build when the file changes.
        val output = googleServicesTask.outputDirectory.get().asFile.canonicalFile
        val buildRoot = appBuildDirectory.get().asFile.canonicalFile
        check(output != buildRoot && output.toPath().startsWith(buildRoot.toPath()))
        check(output.deleteRecursively()) { "Could not clear generated TEST Firebase resources." }
        check(output.mkdirs() || output.isDirectory)
        logger.lifecycle("TezRider TEST: Firebase push disabled. Add the matching TEST google-services.json to enable it.")
        throw StopExecutionException()
    }
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
            manifestPlaceholders["appLabel"] = "TezRider"
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
