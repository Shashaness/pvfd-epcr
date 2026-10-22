# PVFD ePCR — Milestone 1 audit

Date: October 22, 2026 (America/Phoenix). Scope: current `pvfd_epcr/lib/main.dart` entry point, persistence, Android source and merged debug manifest, pinned export/sharing plugins, source and repository-preparation checks. All test records are synthetic. No Git initialization, commit, publication, device installation, or patient-record deletion was performed. No HIPAA or NEMSIS compliance claim is made.

## Initial findings and confirmed defects

- PMH was serialized to `clinical.pmh`, loaded from `incident.pmh`, and filtered against current options. Opening a record also scheduled a save. Together these could erase history.
- Autosave wrote directly to the committed JSON. There was no replacement transaction, write ordering, error boundary, lifecycle flushing, or durable record binding across asynchronous directory lookup.
- IDs used seconds only. Two creations could address the same destination.
- Loading/listing assumed object/list types. One malformed JSON file could fail the entire listing. Dropdown and GCS values were not constrained to supported display values.
- Rebuilding the record from the form discarded unknown fields and unsupported values.
- The only existing test was an unrelated Flutter counter template and did not test this application.

## Implementation

### PMH and compatibility

`readPmh` selects valid string-array `clinical.pmh` first (including an intentionally empty array), otherwise uses legacy `incident.pmh`. Missing, null, wrong-type, and mixed arrays cannot crash loading. Known options and the existing None interaction remain unchanged. Unknown strings survive unrelated edits and are retained in storage even when a user changes visible PMH selections. Historical legacy fields remain present.

The form retains the original JSON and a deep baseline of its supported projection. Saving applies only edited fields recursively. This preserves unknown top-level/nested fields, unsupported dropdown values, malformed vitals/GCS values on unrelated edits, and other future fields. Explicitly editing a malformed field or section can replace that value with the current supported representation. Historical filenames and identifiers are retained; the original listed file path is used for subsequent saves. Listing/opening does not rewrite a file. Invalid root JSON is never replaced by a blank report.

### Safe persistence

`EpcrStorageService` serializes a complete snapshot before touching the destination, writes a unique sibling `.epcr-tmp-<random-id>` file asynchronously with flush enabled, and renames the completed file over the destination. It never deletes the destination first. Failures propagate. Failed temporary writes/replacements are cleaned up when possible. No dependencies were added.

Writes are chained by absolute destination path across service instances within the app isolate. Failed writes do not poison the queue. Serialization occurs at request time, so later mutation cannot alter a queued snapshot. The form binds its file future and deep snapshot before asynchronous operations. A revision tracks subsequent edits; completion of an older snapshot cannot mark newer edits saved. Failed saves retain dirty state, show a generic error, and prevent New/Open from discarding pending edits. Manual Save reports success only after completion.

The 750 ms debounce is unchanged. New/Open flush edits before switching. Inactive/background/detached transitions and disposal start best-effort flushing; flushing repeats if edits arrive during a write. Android does not promise time for asynchronous shutdown work. Force-stop, power loss, or termination during the debounce can lose edits that have not committed; committed JSON is protected by replacement. No synchronous file writes were introduced.

Android replacement was verified at source/API level: Dart's Linux/Android `File::Rename` uses `renameat`; same-filesystem POSIX rename replaces the destination atomically. See [Dart implementation](https://raw.githubusercontent.com/dart-lang/sdk/main/runtime/bin/file_linux.cc) and [POSIX rename semantics](https://man7.org/linux/man-pages/man3/rename.3p.html). Host overwrite and failure tests pass. Physical Samsung filesystem/interruption testing was unavailable. Temporary files are in the same directory to avoid cross-filesystem moves. Windows/other unverified platforms fail safely before attempting replacement; they retain the last committed copy and report unsupported operation. POSIX platforms are the supported persistence path. Directory metadata is not fsynced, so this is not a guarantee against every sudden power/hardware failure. Multiple independent processes/isolates editing the same existing record are outside the current single-form architecture and have no conflict resolution.

### Creation and recovery

New IDs use local `YYYYMMDDHHMMSS-` followed by 32 uppercase hex characters from `Random.secure` (128 random bits). The 47-character ID is filename/XML safe and retains the interpretable local creation time. An exclusive `.reserve` file coordinates creation, checks whether the JSON destination already exists, and retries collisions up to 20 times. Existing records are never treated as new creations or renamed. Reservation failures ultimately return a generic creation error.

Startup counts interrupted temporary/reservation files and warns without exposing paths or identifiers. Neither valid nor invalid orphan content is automatically promoted or deleted. Orphans never appear in the JSON listing. For recovery: stop writes to the affected tablet, make a protected copy of the directory, inspect copies of the committed JSON and orphan JSON for complete object structure, matching identity and clinical content, then have an authorized operator restore a separately reviewed copy. Preserve the originals. A valid-looking orphan is not evidence that it should supersede a committed report. Stale reservation files cause a new ID retry, not overwriting.

### Loading and error reporting

Each file is decoded independently. Invalid JSON/nonobject roots/read errors produce an aggregate generic notification while valid reports remain available. Originals remain in place. The list uses safe map projections; the form handles missing sections, malformed arrays, unsupported dropdowns and out-of-range GCS without assertions. Raw exception messages are excluded from list, save and export UI error boundaries. No patient values or raw stack traces were added to logs.

## Android storage and security audit

### Verified local storage

The installed `path_provider_android` 2.3.1 implementation calls `Context.getDir('flutter', MODE_PRIVATE)` for application documents and `cacheDir` for temporary storage. For the configured application ID, the ordinary primary-user paths are:

- Records: `/data/user/0/com.pvfd3.pvfd_epcr/app_flutter/pcr_<id>.json` (the `/data/data/...` alias may also apply; Android user/profile changes the prefix).
- Persistent exports: the same `app_flutter/Exports/PVFD_ePCR_<id>.pdf` or `.xml` directory.
- Sharing source exports: `/data/user/0/com.pvfd3.pvfd_epcr/cache/Exports/`.
- Sharing plugin copies: `cache/share_plus/`. Printing provider scope: `cache/share/`.

JSON, exports and interrupted files have no application-layer encryption. App-private storage normally prevents access by unrelated sandboxed apps and media indexing, but does not protect against root, privileged tooling, compromised devices, or the app's own access. Device filesystem encryption/lock policies were not inspected. App-specific files are removed on ordinary uninstall/clear-data; receiving-app copies, backups and print jobs can outlive uninstall. See [Android app-specific storage](https://developer.android.com/training/data-storage/app-specific).

Backup was previously enabled by the platform default. Main manifest now disables backup and full backup and provides Android 12+ exclusions for cloud and device transfer across all regular data domains. Cleartext HTTP is explicitly disabled. Existing Android backup copies are not revoked/deleted by these settings. OEM/device-policy behavior still needs testing; see [Android backup behavior](https://developer.android.com/identity/data/autobackup). Removing automatic backup also leaves device loss/uninstall without an approved recovery path; a reviewed protected backup design is required.

### Manifests, signing and components

Reviewed main/debug/profile source manifests and the newly merged debug manifest. Main source requests no broad storage or location permissions. Debug/profile add INTERNET for development; no application telemetry or direct network client was found. Google Maps passes the address to an external HTTPS maps URL by explicit user action and therefore discloses it to the selected maps/browser service. Clinical editing, JSON saving and export generation remain offline.

Launcher activity is exported as required for launch. URL-launcher WebView activity, startup provider, printing/share providers and share callback receiver are not exported. Share and printing FileProviders enable URI grants, with cache-only path scopes rather than document-root grants. AndroidX ProfileInstallReceiver is exported but guarded by the platform DUMP permission. Debug APK is debuggable, as expected; it must not be used as a production security build. Release Gradle configuration still uses debug signing. Changing the signing identity now could prevent updates to existing tablets, so this requires a reviewed signing and rollout plan. The application ID and package remain unchanged. A fresh release APK/signature was not built or device-verified.

### Logging and exports

No routine `print`, `debugPrint` or application logging of patient fields was found in active Dart code. Generated plugin-registration code logs plugin-initialization exceptions; this is not a patient record logging path. Backup entry-point Dart files remain in `lib/` but are not imported by `main.dart`; they retain old defects and must not be selected as production targets.

PDF layout and NEMSIS generator structure were retained. Export deserialization now uses defensive projections for malformed maps/lists. Export filenames percent-encode legacy identifiers to prevent a saved identifier from introducing path separators. PDF/XML export and print/share UI callbacks have generic failure reporting. Export writing itself is not a transactional archive: failure can leave a partial export, while the JSON record stays protected. Persistent exports are intentional user-requested documents and are not automatically deleted.

Sharing remains functional. The pinned `share_plus` 10.1.4 native source clears its share cache when preparing a later share, copies the exported file there, and grants both read/write access to candidate resolved recipient packages. Its FileProvider only exposes `share_plus/`, not the record directory. Source files in `cache/Exports` are not automatically cleaned by this application. Files may persist after a share/cancel until cache cleanup/uninstall; immediate deletion is unsafe because chooser completion does not prove that a recipient has finished reading. A reviewed expiration/grant-revocation design or plugin update is needed. Android printing/spoolers and recipient apps control additional copies; the application cannot revoke copies already received. Nothing writes directly to public Downloads or external storage. User-selected recipients can copy documents into public/cloud locations. The printing plugin also has its own cache and platform-managed print lifecycle.

### Secrets and public repository preparation

Searched source/configuration for API key/token/password/private-key/secret patterns and inventoried record JSON, PDF/XML, keystore/certificate/environment file candidates without printing secret values. No credential or patient-record artifacts were identified in the inspected source tree. This is a heuristic inspection, not certification that no PHI/secrets exist in arbitrary binaries, generated artifacts, past history, or attached device storage. No device patient data was read.

Files requiring exclusion/review before publication: `android/local.properties` (machine paths), `.idea/workspace.xml` and root `.idea/` (local IDE state), generated `ios/Flutter/ephemeral/flutter_native_integration.env` and `macos/Flutter/ephemeral/flutter_native_integration.env` (local environment), `.dart_tool/`, `build/`, and any future signing credentials. Existing platform ignore rules cover many generated paths. Application `.gitignore` now also excludes record JSON, orphan/reservation files, Exports directories, common keystore/private-key formats, key.properties and dotenv files. Do not rely on ignore rules as a secret scanner. The district logo asset was inventoried; no sample patient documents were found. No credentials are included in this audit.

## NEMSIS identifier review

The current generator uses the UI incident number (defaulted from the new record ID) for `eRecord.01`, embeds the ePCR number in deterministic UUID seeds, and uses XML builder text escaping. The new ID has 47 characters; NEMSIS 3.5.1 `eRecord.01` permits a string of 3–50 characters, so the default new identifier fits. See the [official 3.5.1 dictionary, page 24](https://www.nemsis.org/media/nemsis_v3/release-3.5.1/DataDictionary/PDFHTML/EMSDEMSTATE/NEMSISDataDictionary.pdf). Full schema/Schematron compliance was not validated.

Pre-existing issues remain: manually changing incident number can change `eRecord.01` independently of report identity; `_stableUuid` reduces the ID seed to a 32-bit hash, weakening UUID collision resistance even though record filenames are now protected. Agency identifiers remain placeholders and several elements need a dedicated standards mapping review (for example software metadata and service codes). These are documented rather than rewriting the generator in this milestone.

## Files modified or created

| File | Purpose |
| --- | --- |
| `pvfd_epcr/lib/main.dart` | Integrate ordered atomic storage, retained-field editing, PMH fix, safe loading/listing, lifecycle/record-switch flush, secure IDs, generic errors and safe export filename components. Formatting follows Dart formatter. |
| `pvfd_epcr/lib/services/epcr_storage_service.dart` | Small persistence component, ID generation, conservative orphan detection, safe record projections and differential merge. |
| `pvfd_epcr/android/app/src/main/AndroidManifest.xml` | Disable backup and cleartext traffic; connect extraction exclusions. |
| `pvfd_epcr/android/app/src/main/res/xml/data_extraction_rules.xml` | Cloud and device-transfer data exclusions on modern Android. |
| `pvfd_epcr/.gitignore` | Exclude sensitive records/exports/signing material. |
| `pvfd_epcr/test/widget_test.dart` | Replace unrelated counter template with real synthetic form regressions. |
| `pvfd_epcr/test/storage_test.dart` | Persistence, failure, concurrency, creation collision, compatibility, malformed JSON and merge tests. |
| `docs/MILESTONE_1_AUDIT.md` | This audit, limitations and validation results. |

Flutter commands also refresh ignored local build/cache/plugin artifacts. No dependency was intentionally added or upgraded; existing lockfile constraints were used.

## Tests and results

Environment: Flutter 3.47.7 stable, Dart 3.13.5; host macOS. Required commands are run from `pvfd_epcr` (final results recorded below).

- `flutter pub get`: PASS; resolved existing dependencies. Tool reports newer versions outside current constraints; no blanket upgrade performed.
- `flutter analyze`: PASS, no issues found (final run).
- `flutter test`: PASS, all 25 tests (12 storage tests and 13 form/widget cases). PDF generation emits the existing Helvetica/Helvetica-Bold Unicode-support warnings; generation succeeds. Unicode text rendering was not validated.
- `flutter build apk --debug`: PASS; APK at `pvfd_epcr/build/app/outputs/flutter-apk/app-debug.apk`. The build warns that share_plus uses the Kotlin Gradle Plugin and needs a future compatibility update.
- `adb devices -l`: no connected devices. Physical tablet installation, force-stop/power-loss, print dialogs, Android sharing, external Maps launch and Samsung backup/transfer testing NOT RUN. No existing device records were touched.

Tests exercise PMH empty/multiple/None/unknown/legacy/preference/malformed cases, form save-load-save, unknown-field retention, no write on open/list, safe malformed dropdown/GCS/vitals display, creation/reset, background flush, dirty-state failure/retry, rapid overlapping snapshots, switching during an active save, successful overwrite, serialization/write/pre-rename/rename failures, queue recovery, ID collisions/restart simulation, malformed JSON isolation, orphan retention, PDF byte generation and XML generation with synthetic responders/allergies/medications/GCS/forest/GPS data. Print/share/Maps code paths were inspected; host generation tests cannot validate Android integrations or visual PDF equivalence.

## Remaining issues and next steps

No unresolved Critical issue was verified within the inspected scope. Severity is based on technical impact, not a legal compliance assessment.

| Severity | Finding and status | Impact / recommended action |
| --- | --- | --- |
| High | Verified: no app-level encryption, authentication/role controls or audit trail. Device encryption/MDM status unverified. | Lost/unlocked or compromised tablets can expose patient information. Review device management, access policy, encryption key management/recovery and authorized access before production expansion. Do not add ad hoc encryption. |
| High | Verified: release build uses debug signing. | Unsuitable production key custody/update controls. Inventory installed signing identities and plan a compatible managed release-signing rollout before distribution. |
| High | Verified: no approved secure backup/retention/recovery system; automatic backup now excluded. | Device loss, uninstall or hardware failure can permanently lose records. Define protected backup, recovery drills, retention and authorized deletion before wider deployment. |
| High | Verified: share plugin grants read/write URI access to candidate recipients and retains copies; source exports persist. | Sensitive copies can be read/retained beyond the intended handoff. Review plugin replacement/update or narrowed read-only native sharing with recipient/expiry policy and device regression tests. |
| High | Verified: NEMSIS UUID seeds have only 32-bit hash space, agency placeholders and incomplete mappings remain. | Local JSON IDs are protected, but exported UUIDs may collide and XML may be rejected/misinterpreted. Review stable standards-compliant UUIDs, identity semantics and full national/Arizona XSD/Schematron validation in a dedicated change. |
| Medium | Verified limitation: debounce/shutdown/power-failure window; no directory fsync or multi-process conflict handling. | Latest uncommitted edits can be lost, and hardware-level durability is not guaranteed. Run controlled interruption tests on synthetic records on target Samsung hardware; evaluate durable journaling if operational requirements demand it. |
| Medium | Verified: interrupted files, cached and persistent exports lack retention rules; partial exports possible on failure. | Residual PHI/storage growth. Define reviewed cleanup/archive policy, then implement retention and transactional exports without racing share recipients. |
| Medium | Unverified: device-level backup exclusion, encryption, exact filesystem durability, printing/sharing/Maps behavior. | Host checks cannot establish tablet behavior. Perform the synthetic device checklist before rollout. |
| Low | Verified: existing PDF Helvetica Unicode-support warnings, old alternate Dart entry points, generated/local files and future Kotlin Gradle Plugin incompatibility warning for share_plus. | Wrong build target or careless publication could reintroduce defects/expose local configuration. Select main.dart explicitly, review publication contents, check non-ASCII PDF text with synthetic data, and plan a tested dependency/toolchain update. |

Ready for scoped Milestone 2 architectural refactoring after review and a synthetic physical-tablet acceptance pass. Not ready for unreviewed production rollout or public GitHub release: complete signing, sensitive-file review and device validation first. No publication was performed.
