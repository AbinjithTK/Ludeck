// Versions pinned deliberately. compileSdk 35 with AGP 8.7.3 is a combination
// that works with the Gradle 8.14 distribution already cached on this machine.
// SDK platform android-36 is installed too, but moving to it requires AGP 8.9+,
// which is a change to make on purpose rather than by accident.
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    id("com.google.devtools.ksp") version "2.0.21-1.0.28" apply false
}
