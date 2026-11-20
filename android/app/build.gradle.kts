import java.util.Properties
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signing = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyFile.inputStream().use { signing.load(it) }
val firebase = file("google-services.json").takeIf { it.isFile }?.let { JsonSlurper().parse(it) as Map<*, *> }

android {
    namespace = "id.myra.myra_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }
    defaultConfig {
        applicationId = "id.myra.myra_mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (firebase != null) {
            val info = firebase["project_info"] as Map<*, *>
            val clients = firebase["client"] as List<*>
            val client = clients.filterIsInstance<Map<*, *>>().first {
                val clientInfo = it["client_info"] as Map<*, *>
                (clientInfo["android_client_info"] as Map<*, *>)["package_name"] == applicationId
            }
            resValue("string", "google_app_id", (client["client_info"] as Map<*, *>)["mobilesdk_app_id"].toString())
            resValue("string", "gcm_defaultSenderId", info["project_number"].toString())
            resValue("string", "project_id", info["project_id"].toString())
            resValue("string", "google_api_key", ((client["api_key"] as List<*>).first() as Map<*, *>)["current_key"].toString())
        }
    }
    signingConfigs {
        if (keyFile.exists()) create("owner") {
            storeFile = file(signing.getProperty("storeFile"))
            storePassword = signing.getProperty("storePassword")
            keyAlias = signing.getProperty("keyAlias")
            keyPassword = signing.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keyFile.exists()) "owner" else "debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}
dependencies { implementation("com.google.firebase:firebase-messaging:24.1.2") }
flutter { source = "../.." }
