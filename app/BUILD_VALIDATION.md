# Reproducible Flutter baseline

Use Flutter **3.47.7** with Dart **3.13.5**, as pinned in `.fvmrc`. The Android project keeps Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 and Java 17. Do not bypass Flutter's Android dependency validation.

Flutter 3.50 requires newer Android build tooling and also pins a different `flutter_test` dependency graph. Mixing that SDK's lockfile with this Android project is not a verified build baseline. The lockfile adjustment for 3.47.7 changes only test_api 0.7.14 to 0.7.12 and removes its unused transitive listen 1.0.1. Direct application dependencies are unchanged.

## Local checks

With FVM installed, run these from `app/`:

```sh
fvm install
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
```

Alternatively select the exact SDK on PATH and use `flutter` instead of `fvm flutter`. Do not run pub get with another SDK and commit its lockfile without reviewing the dependency changes.

Some integration and real-font tests need explicit fixtures. A skipped fixture gate is not a pass. Read the corresponding test's environment variables, provide the original source/font/offline data, then run it again. A local source review, mock notification test, or successful compilation does not prove actual device accessibility, native alarm delivery, audio playback, or behavior after reboot/process death.

## Android compile boundary

Compile with Java 17 and the project's configured Android SDK. For example, from `app/android/`:

```sh
./gradlew :app:compileDebugKotlin :app:compileDebugJavaWithJavac
```

A low-memory machine may exhaust the Java heap when Jetifier reads Flutter's native-engine-only JARs. A narrowly scoped command-line ignorelist was validated for these exact Flutter 3.47.7 engine artifacts at engine revision `deb287481e3ce9468f3434937ced4240a70539ca`:

- `armeabi_v7a_debug-1.0.0-deb287481e3ce9468f3434937ced4240a70539ca.jar`
- `arm64_v8a_debug-1.0.0-deb287481e3ce9468f3434937ced4240a70539ca.jar`
- `x86_64_debug-1.0.0-deb287481e3ce9468f3434937ced4240a70539ca.jar`

Each inspected JAR contains only `.so` files and no Java/Kotlin classes. This exception is not configured globally in the repository. If needed, pass `-Pandroid.jetifier.ignorelist=` with only those exact filenames, comma-separated, and keep Jetifier enabled for the embedding and plugins. Reinspect artifact contents when the SDK/engine changes. Do not use a blanket Jetifier disable or Flutter's skip-build-dependency-validation flag.

Compilation does not package, sign, install or release an APK. Those checks and physical-device acceptance remain separate. This document does not authorize changing signing keys, uninstalling an existing app, triggering paid CI, or publishing a release. The existing workflow remains manual-only.
