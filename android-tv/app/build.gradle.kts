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
        versionCode = 4
        versionName = "0.1.3"
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
    implementation("org.java-websocket:Java-WebSocket:1.6.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("io.github.webrtc-sdk:android:150.7871.01")
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.media3:media3-exoplayer:1.9.4")
    implementation("androidx.media3:media3-exoplayer-hls:1.9.4")
    implementation("androidx.media3:media3-exoplayer-dash:1.9.4")
    implementation("androidx.media3:media3-ui:1.9.4")
}
