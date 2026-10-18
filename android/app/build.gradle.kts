plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.watap.watap_mobile"

    // Niveles configurados explícitamente para que queden documentados:
    //   compileSdk 36 -> Android 16 (API 36), requerido por las dependencias
    //                   estables actuales (AndroidX / flutter_secure_storage).
    //   minSdk 24     -> Android 7.0 Nougat. Cubre dispositivos modernos y es
    //                   compatible con sqflite y flutter_secure_storage.
    //   targetSdk 36  -> comportamiento declarado frente al sistema actual.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.watap.watap_mobile"
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // NOTA: la firma con las claves de depuración es la configuración
            // predeterminada del andamiaje de Flutter. Sirve para instalar y
            // probar el APK Release, pero NO es apta para publicar en Google
            // Play. Consulta el README ("Firma de la versión Release") para
            // configurar un keystore propio mediante `key.properties`.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/DEPENDENCIES", "META-INF/LICENSE*")
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
