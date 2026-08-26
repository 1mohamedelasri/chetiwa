import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("com.google.android.libraries.mapsplatform.secrets-gradle-plugin")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadKeyPropertiesFile = rootProject.file("key.properties")
val uploadKeyProperties = Properties().apply {
    if (uploadKeyPropertiesFile.exists()) {
        uploadKeyPropertiesFile.inputStream().use(::load)
    }
}

android {
    namespace = "com.ezplatforms.chetiwa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ezplatforms.chetiwa"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // google_maps_flutter 2.18 requires Android 7.0 (API 24).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = providers.gradleProperty("admobAppId")
            .orNull ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (uploadKeyPropertiesFile.exists()) {
            create("release") {
                keyAlias = uploadKeyProperties.getProperty("keyAlias")
                keyPassword = uploadKeyProperties.getProperty("keyPassword")
                storeFile = file(uploadKeyProperties.getProperty("storeFile"))
                storePassword = uploadKeyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Never ship a build signed with Flutter's shared debug key.
            if (uploadKeyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

secrets {
    // local.properties is ignored and also contains Flutter's SDK path.
    propertiesFileName = "local.properties"
    defaultPropertiesFileName = "local.defaults.properties"
    ignoreList.add("flutter.sdk")
    ignoreList.add("sdk.dir")
}
