# PVFD ePCR

PVFD ePCR is an offline-first Flutter electronic patient care reporting project developed for Pleasant Valley Fire District in Young, Arizona. The planned initial version is **0.1.0-alpha**. It is an experimental development project, not a certified production EMS records system.

The intended source repository is `Shashaness/pvfd-epcr`. Public publication and an initial release are pending maintainer approval. No public release date has been assigned.

## Current capabilities

- Create, list, open and edit locally stored ePCRs, with debounced autosave and ordered atomic JSON replacement.
- Work offline for clinical editing, local storage and document generation.
- Capture incident and patient information, responders, PMH, allergies, medications, GCS, assessments, vitals and clinical narrative.
- Record Forest Land status, GPS coordinates, additional contacts and Completed By information.
- Generate PDF reports and hand them to native printing.
- Generate NEMSIS-oriented XML and share PDF/XML through Android's native share sheet.
- Launch an external Google Maps address lookup when requested. Maps and recipient applications may need connectivity and control their own data handling.

## Architecture

The Flutter app remains in `pvfd_epcr/`. The repository root holds project documentation and licensing.

The application separates lossless domain records, repository/storage transactions, an editing/autosave controller, presentation screens/widgets, document generation and platform integrations. Existing JSON paths and unknown fields are retained during editing. See [Milestone 2 architecture](docs/MILESTONE_2_ARCHITECTURE.md) and the historical [Milestone 1 audit](docs/MILESTONE_1_AUDIT.md).

## Development environment

Tested locally with Flutter **3.47.7** and Dart **3.13.5**. Android SDK Platform **36** and Build Tools **36.1.0** are installed in the reviewed environment. These identify the tested/available toolchain, not universal minimum versions. The current project declares Dart `^3.12.2`; Flutter's Android defaults currently select compile/target API 36 and minimum API 24. See [build instructions](docs/BUILDING.md) for Gradle, Java and NDK details.

Android tablets are the primary target. Other platform directories are Flutter scaffolds and are not covered by equivalent acceptance testing. Persistence safely rejects unverified non-POSIX platforms; web operation is not supported by the current dart:io-based implementation.

## Getting started

Install the tested Flutter toolchain and Android SDK, accept required SDK licenses, and configure a dedicated synthetic-data test device or emulator. Run Flutter commands from the app directory:

```bash
cd pvfd_epcr
flutter pub get
flutter analyze
flutter test
flutter run -t lib/main.dart -d <test-device-id>
```

`flutter run` installs/updates an application. Do not run it against an operational tablet without an approved update plan. Use only the supported `lib/main.dart` entry point. Historical alternate entry points and the unlicensed-for-redistribution district logo are retained only in the original local workspace and excluded from publication.

## Building

```bash
cd pvfd_epcr
flutter build apk --debug
```

Output: `pvfd_epcr/build/app/outputs/flutter-apk/app-debug.apk`, relative to the repository root. APKs and build caches are excluded from source control.

Release signing is not finalized: the current release build configuration uses the debug signing configuration. Do not treat a release-mode build as an approved production distribution. Application ID and signing identity have not been changed for this source preparation. See [BUILDING.md](docs/BUILDING.md) before installing any build; uninstalling can delete app-private reports.

## Testing

The 53 existing automated tests cover lossless/legacy JSON, PMH, atomic storage, failure recovery, save ordering, unique creation, controller/lifecycle behavior, UI interactions, document structure and integration arguments. All test fixtures were reviewed as synthetic; none is a template for submitting real patient information.

PDF drawing streams and XML output are compared with synthetic pre-refactor fixtures. Host tests do not establish Android sharing/printing behavior or clinical correctness for every report. Maintainer-reported Samsung acceptance includes creating a synthetic report and exporting PDF/XML to OneDrive; this is not a security or standards certification. The Milestone 3 audit records the validation actually performed during publication preparation.

## Security and privacy

This application handles potentially sensitive medical information. Milestone 4.2B uses encrypted-only local persistence with app-private encrypted recovery staging. The operator reports successful synthetic qualification on one development-only Samsung tablet; normal-editor acceptance and production deployment remain separate review gates. PDF/XML exports are not application-layer encrypted. See [encrypted storage design and deployment gates](docs/MILESTONE_4_2B_ENCRYPTED_STORAGE.md). Authentication, authorization, audit trails, secure backup and retention require further work. Private storage and Android backup exclusions are useful safeguards, but do not establish compliance or a complete security design.

Do not deploy this development version for actual patient information without an appropriate security and operational review. Never upload patient records, exports, credentials, device logs containing clinical data, or identifying screenshots to a repository, issue or pull request. See [SECURITY.md](SECURITY.md) for disclosure guidance and the preferred GitHub private reporting channel and its required prepublication enablement.

## NEMSIS status

The application generates NEMSIS-oriented XML targeting version 3.5.1. It has not passed complete official NEMSIS 3.5.1 XSD/Schematron validation. Agency placeholders, identifier/UUID limitations and incomplete mappings remain documented. No NEMSIS or HIPAA compliance claim is made.

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md) and the [publication audit](docs/MILESTONE_3_PUBLICATION_AUDIT.md).

Original project code is offered under the [MIT license](LICENSE), copyright 2026 Shawn Bakhtiar. Third-party dependencies and Flutter-derived template materials retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). MIT licensing does not grant rights to district names, official insignia or third-party trademarks. The district logo is not part of the publication inventory.

## Disclaimer

This is experimental development software provided under the license's warranty disclaimer. It is not a certified production EMS records system, a clinical decision-support certification, or a substitute for agency-approved clinical, security and record-management procedures.
