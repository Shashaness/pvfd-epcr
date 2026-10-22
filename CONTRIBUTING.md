# Contributing

PVFD ePCR is an experimental offline-first EMS reporting application. The initial public repository and release are pending approval.

## Bugs and feature proposals

For ordinary bugs, provide a minimal reproducible example, expected/actual behavior, platform and toolchain versions. Reproduce with invented data. For features, describe the workflow and compatibility implications before proposing a large change. Once the repository is public, ordinary issues and pull requests may be used; security concerns must follow [SECURITY.md](SECURITY.md).

Never submit real patient records, exports, names, identifiers, addresses, operational contacts, credentials, signing material, or screenshots/logs containing sensitive information. Synthetic labels alone are not proof of safety: review the actual contents and strip device/machine-specific details. Public issues are not a patient-record upload channel.

## Development and style

Use the supported `pvfd_epcr/lib/main.dart` entry point. Keep changes focused and follow the existing layers and Dart/Flutter style. Domain models must remain lossless; do not replace unsupported stored values simply because the UI cannot display them. Preserve offline functionality and avoid new services/dependencies unless justified.

From the Flutter application directory:

```bash
cd pvfd_epcr
# List only the Dart files changed by your contribution.
dart format lib/path/to/changed_file.dart test/path/to/changed_test.dart
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

See [BUILDING.md](docs/BUILDING.md) for installation precautions and test devices. Do not install over an operational tablet or uninstall it to bypass a signing mismatch.

## Tests and pull requests

Add focused synthetic regression tests for behavior changes, especially persistence, save failures/order, PMH, lossless JSON handling, document output and widget/controller disposal. Existing tests must continue to pass. Do not weaken fixtures/assertions to accommodate an unintended output change.

Describe the problem, resulting behavior, compatibility and validation actually performed. Distinguish tests not run from successful tests. Call out any effects on stored JSON, clinical semantics, PDF layout, Android permissions/signing or dependency licensing. Do not log patient data while diagnosing failures.

Retain historical identifiers/filenames and unknown JSON fields. Do not destructively migrate or delete records. Preserve atomic replacement, ordered writes, dirty/revision tracking and original record binding.

Changes to NEMSIS mappings or identity semantics require an explicit description, tests and documentation of standards implications; no conformance claim should be made without validation. Review security/retention proposals before adding encryption, authentication, backup, cleanup or telemetry.

By contributing, you should have the right to submit your contribution under the project's applicable license. No mandatory contributor license agreement is introduced.
