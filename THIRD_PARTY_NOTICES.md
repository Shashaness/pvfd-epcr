# Third-party notices and asset review

The root MIT license covers original PVFD ePCR contributions; it does not relicense third-party dependencies, Flutter-derived template code/artwork, fonts, trademarks or district insignia. This is a local source-publication review, not a comprehensive legal license opinion or audit of every transitive/native dependency in a future binary release.

## Flutter template material

The platform scaffolding and standard Flutter launcher/icon assets originate from the Flutter project. Keep the applicable Flutter BSD-3-Clause notice in [third_party/FLUTTER_LICENSE](third_party/FLUTTER_LICENSE). Existing source copyright/license headers remain in place. Twelve included images matched local SDK template files byte-for-byte; additional platform icons were reviewed as standard Flutter template/generated icon variants. No extra font files are bundled in the source tree. Flutter marks and third-party trademarks are not granted by the project's MIT license and should not imply endorsement.

## Direct packages reviewed locally

The following installed versions were resolved in the reviewed environment. Package license files were inspected from the local SDK/package cache; dependencies are downloaded by tooling rather than vendored into this source repository.

| Package | Reviewed version | Local license information |
| --- | --- | --- |
| Flutter SDK | 3.47.7 | BSD-3-Clause, SDK LICENSE |
| flutter_test | SDK | SDK license applies; no separate package LICENSE found locally |
| flutter_lints | 6.0.0 | BSD-3-Clause |
| crypto (Milestone 4.2B SHA-256; existing transitive package promoted to direct) | 3.0.7 | BSD-3-Clause |
| cryptography (Milestone 4.1 tests only) | 2.9.0 | Apache-2.0 |
| cupertino_icons | 1.0.9 | MIT |
| pdf | 3.12.0 | Apache-2.0 |
| printing | 5.14.3 | Apache-2.0 |
| xml | 6.6.1 | MIT |
| share_plus | 10.1.4 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| uuid | 4.5.3 | MIT |
| url_launcher | 6.3.2 | BSD-3-Clause |

Review resolved transitive packages, native components (including printing/PDF components), fonts and notices before binary distribution. Apache and BSD/MIT notices remain the upstream authors' terms; the project's MIT file is not their replacement. Package versions may differ in historical milestone documents, which record earlier observations.

## Offline recovery workstation dependency

Milestone 4.2A tools use Python `cryptography` 49.0.0, licensed `Apache-2.0 OR BSD-3-Clause` (installed package license metadata reviewed). This is separate from the Dart package named cryptography. It is downloaded into the authorized recovery environment, not bundled with Flutter/Android. Preserve upstream notices when redistributing any Python dependency/wheel environment; native/transitive binary obligations still require review.

## District branding exclusion

The original workspace contains an unused asset named `assets/images/pvfd_logo.jpg`. Inspection shows it is a PNG containing district insignia despite its filename extension. Ownership/redistribution permission has not been established. The entire root `assets/` directory is excluded from the initial publication inventory and remains intact locally. No active asset declaration or image reference requires this file for the current build, so excluding it does not change the application UI or document layout.

Do not distribute that asset without separate authorization or assume that MIT code licensing permits official insignia use. The project/district names in explanatory documentation are descriptive and do not imply district endorsement or trademark permission.

## Synthetic fixtures and historical source

Reviewed document fixtures use invented names/addresses/clinical text and nonworking placeholder contact numbers. Their ordinary-looking vital signs, coordinates, responder codes and timestamps are test inputs, not recovered patient records. No real patient identity was found in their reviewed contents.

The three historical alternate Dart entry points are retained locally and ignored rather than deleted or archived destructively. They contain outdated implementations and unsupported launch targets; only `pvfd_epcr/lib/main.dart` is part of the supported public source baseline. No credentials or hardcoded patient identities were identified in their inspected contents.
