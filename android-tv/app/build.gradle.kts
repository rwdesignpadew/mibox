plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "pl.miboxscreen.tv"
    compileSdk = 35

    defaultConfig {
        applicationId = "pl.miboxscreen.tv"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        val signalingUrl = providers.gradleProperty("SIGNALING_URL")
            .orElse("ws://192.168.1.10:8080/signal")
            .get()
        buildConfigField("String", "SIGNALING_URL", "\"$signalingUrl\"")
    }

    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.github.webrtc-sdk:android:150.7871.01")
}
