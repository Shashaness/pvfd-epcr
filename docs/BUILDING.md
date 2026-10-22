# Building PVFD ePCR

## Scope and toolchain

Android tablets are the primary target. Commands below assume the repository retains its Flutter application in `pvfd_epcr/`; run all Flutter/Dart commands from that directory. The supported entry point is `lib/main.dart`.

The reviewed environment uses Flutter 3.47.7 stable and Dart 3.13.5. The project declares Dart `^3.12.2`; these tested versions are not a newly asserted universal minimum. Android SDK Platform 36 is required by the current Flutter compileSdk default. Build Tools 36.1.0 are installed/available locally; SDK components may select another compatible installed Build Tools revision. Flutter currently selects minimum API 24, target API 36 and NDK 28.2.13676358. The Gradle wrapper properties request Gradle 9.1.0; use a compatible JDK (Java/Kotlin source target is 17). Let `flutter doctor -v` identify the Java runtime actually selected on your machine rather than changing project signing/package settings.

Install Flutter, Android SDK command-line/platform tools, the required platform/build tools/NDK and Java runtime. Configure SDK paths locally with Flutter/Android tooling; never commit `android/local.properties`. Accept the SDK licenses through the appropriate local tooling. Package downloads, Gradle distribution/dependencies and uncached SDK components require connectivity during development. This does not change the application's offline clinical editing/storage/generation behavior.

```bash
flutter --version
flutter doctor -v
cd pvfd_epcr
flutter pub get
```

Keep `pubspec.lock` in source control for this application. Do not perform a blanket dependency upgrade while reproducing the baseline. Generated Gradle wrapper scripts/JAR, plugin registrants and platform ephemeral files are excluded by the platform/root ignore rules; Flutter tooling recreates the needed files during setup/build. They are not undocumented signing inputs.

## Test devices and running

Use a dedicated device/emulator with invented records. For a physical Android test device, enable Developer options and USB debugging, connect USB and approve the debugging authorization on that device. Disable debugging when no longer needed under agency/device policy.

```bash
adb devices -l
cd pvfd_epcr
flutter devices
# This installs or updates the app; choose a dedicated synthetic-data device.
flutter run -t lib/main.dart -d <test-device-id>
```

Do not run install/update commands against an operational tablet without explicit authorization and a reviewed data-preservation/update plan. ADB authorization is not approval to read or change patient data. Never copy operational records into test fixtures or public bug reports.

## Analysis and automated tests

```bash
cd pvfd_epcr
flutter analyze
flutter test
```

The baseline has 53 tests covering lossless JSON, repository/storage failures and ordering, controller/disposal behavior, UI interactions and synthetic PDF/XML fixtures. See [Milestone 2 architecture](MILESTONE_2_ARCHITECTURE.md) for details. To format a contribution, run `dart format` on the specific changed Dart files; avoid reformatting historical/local-only entry points.

## Build a debug APK

```bash
cd pvfd_epcr
flutter build apk --debug
```

Output from the app directory: `build/app/outputs/flutter-apk/app-debug.apk`.

Output from the repository root: `pvfd_epcr/build/app/outputs/flutter-apk/app-debug.apk`.

Debug builds are debuggable and are not approved production distributions. Current package identity remains `com.pvfd3.pvfd_epcr`. No signing key is distributed with the source; Android tooling uses the developer machine's debug keystore for debug builds. Different machines can therefore produce APKs with incompatible debug signing certificates even from identical source.

## Installing on a dedicated test device

Only after confirming that the selected device is authorized for synthetic-data testing:

```bash
# Run from the repository root; replace the placeholder with the test-device ID.
adb -s <test-device-id> install -r pvfd_epcr/build/app/outputs/flutter-apk/app-debug.apk
```

`-r` requests an update retaining app data when package/signature/version compatibility allows it. It is not a backup or a guarantee against data loss. Verify the installed and new certificate identities and review compatibility before an approved update. Do not use downgrade flags, clear-data commands, or uninstall/reinstall as a workaround for an install error on an operational device.

**Uninstalling the application or clearing its storage can permanently delete app-private ePCR records and exports.** A signing mismatch is a reason to stop and plan a compatible update, not to delete the installation. Device loss or failure also requires a separately reviewed protected backup/recovery design; the project does not supply one.

## Versioning and release signing

`pubspec.yaml` uses `version: 0.1.0-alpha+1`: `0.1.0-alpha` is the prerelease name and `1` is the Android build/version code. Android Gradle reads both through Flutter. The reviewed Flutter Android build accepts this prerelease name; iOS/macOS tooling may sanitize nonnumeric build names, and those builds are not validated here. Future distributed Android updates must use an appropriate monotonically increasing build code and compatible signing identity.

The current release build configuration still uses debug signing. This milestone does not modify that identity, application ID or package configuration, create a keystore, publish an APK or create a release/tag. A managed signing and tablet-rollout plan is required before production distribution. See [security policy](../SECURITY.md), the historical [Milestone 1 audit](MILESTONE_1_AUDIT.md) and current [publication audit](MILESTONE_3_PUBLICATION_AUDIT.md).

## Reproducing the publication candidate

The audited source inventory is recorded in PUBLICATION_INVENTORY.txt and checked against the reviewed Git index. The publication audit explains validation from a temporary directory containing only candidate source, tests, platform templates and documentation—without ignored local properties, build caches, branding or patient data. A source-only reproduction can still use the developer's documented external Flutter/Android SDK, package cache and Gradle cache. No destructive cleanup of the working project is required.

The public iOS project omits the original developer-specific Apple team setting. Its original local configuration is preserved in ignored `pvfd_epcr/ios/Runner.xcodeproj/project.pbxproj.local`; iOS developers must configure their own authorized team locally. Android signing is unchanged. Other platform scaffolds have not received equivalent build or device acceptance. Current persistence uses dart:io and rejects unverified non-POSIX replacement platforms; do not interpret the presence of web/Windows directories as support certification.
