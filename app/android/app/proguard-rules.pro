# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Just Audio & Audio Session
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# SQLite
-keep class com.tekartik.sqflite.** { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Play Core & Split Install warnings from Flutter engine
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# General Proguard optimizations safety
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
-dontwarn androidx.**
-keepattributes *Annotation*
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
