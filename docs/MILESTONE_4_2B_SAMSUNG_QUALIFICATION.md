# Milestone 4.2B — Samsung qualification record

Date: October 22, 2026. Controlled synthetic hardware qualification completed according to the operator report; normal-editor validation remains pending explicit installation approval.

## Completed qualification — operator-reported evidence

The operator confirms development-only Samsung SM-X210, ADB serial `R95Y804S2PV`, contains no operational patient data, and reports PASS for encrypted create/read/update, autosave, restart with persistent backup queue, offline operation, bounded simulated ENOSPC, ciphertext-tamper detection, and controlled pre-publication process termination followed by restart verification. The final **Verify restart returned PASS**. These results are supplied by the operator; this finalization does not independently capture or reconstruct the original device test logs, exact execution timestamps, reset counts, or reset authorization. No new reset is authorized.

This qualifies the exercised synthetic path on this device. It does not establish actual hardware power-loss durability, real full-filesystem ENOSPC behavior, exhaustive native filesystem failure handling, compliance or operational deployment readiness. Normal editor/autosave/reopen acceptance remains a separate step after explicit approval of the normal APK installation. No second tablet is included.

The following preparation record is historical. Its missing-package observation describes the earlier preparation session; current package/signing state must be independently rechecked before installation. Build hashes below identify the original prepared artifacts; any rebuilt candidate needs fresh evidence.


## Historical preparation blocker

Explicitly targeted ADB serial `R95Y804S2PV` is authorized (`device`) and reports model `SM-X210`. Operator confirmation of the physical tablet is still required. Active Android user is `0`. Read-only `pm path com.pvfd3.pvfd_epcr` returns no package path and `dumpsys package` reports that package cannot be found. Therefore the installed version and signing certificate cannot be verified, and existing app-private storage cannot be inventoried. **Affected file/directory counts are unknown, not zero. No reset plan token has been issued.** Resolve this discrepancy before any installation or data-changing step. Historical device results do not establish current compatibility. Do not inspect or operate on a second tablet.

No tablet writes, application launch, install, uninstall, data clearing, reset, signing change, record read, network upload, private-key access, commit or push was performed for this preparation.

## Prepared targets and exact builds

Run from `pvfd_epcr/`. Preserve each APK before the next build overwrites it:

```sh
flutter build apk --debug -t lib/qualification_main.dart --dart-define=PVFD_HARDWARE_QUALIFICATION=true --dart-define=PVFD_ALLOW_DEVELOPMENT_RESET=true
cp build/app/outputs/flutter-apk/app-debug.apk /private/tmp/pvfd-m42b-qualification/armed-reset.apk
flutter build apk --debug -t lib/qualification_main.dart --dart-define=PVFD_HARDWARE_QUALIFICATION=true --dart-define=PVFD_ALLOW_DEVELOPMENT_RESET=false
cp build/app/outputs/flutter-apk/app-debug.apk /private/tmp/pvfd-m42b-qualification/unarmed-qualification.apk
flutter build apk --debug -t lib/main.dart --dart-define=PVFD_ALLOW_DEVELOPMENT_RESET=false
cp build/app/outputs/flutter-apk/app-debug.apk /private/tmp/pvfd-m42b-qualification/unarmed-normal.apk
```

The destination directory must already exist. Build output and certificate evidence are retained locally in `/private/tmp/pvfd-m42b-qualification/`. The normal target is the last build. Both qualification flags default false; release/profile cannot use the reset API. Normal `main.dart` does not import the harness. The harness performs no storage operation at startup. Its serial text box is an operator attestation, not an automatic device-identity check.

Before a separately approved installation, recheck the exact serial, active user, package path, installed version and public signing certificate. Compare with candidate APK using `aapt dump badging` and `apksigner verify --print-certs`; an absent package, different certificate, version downgrade or unexpected package stops the procedure. Do not use Flutter's install/uninstall fallback. Any future approved update must use direct `adb -s R95Y804S2PV install -r -t <approved-apk>` only after these checks. This command is **not authorized for execution by this preparation**. Current absent-package state prevents certifying an in-place update.

## Reset harness and plan

Only the explicitly armed qualification target exposes reset controls. Before even previewing a plan, obtain approval to install/run that target and confirm all affected data is expendable development data. Preview invokes the existing production reset planner; taking its lock may create `protected_epcr_v1/` and `.lock`, so preview is not a strictly read-only tablet action.

The preview displays exact relative file paths, file count, directory paths and directory count, without reading clinical content into the UI. It covers recognized root `pcr_*.json` development files and their recognized reservation/interrupted-write siblings, plus known protected record generation/staging members and abandoned key-index temporary files. It preserves `keys.json`, `.lock`, Android Keystore aliases, nonce ledger and unrelated files. Unknown protected members or symlinks stop planning. Filename recognition cannot determine whether a record is synthetic: the operator must attest that it is development data. Legacy JSON contents are not displayed.

Execution needs a separate authorization checkbox and the exact typed phrase, including the newly generated plan digest:

```text
DELETE CONFIRMED DEVELOPMENT DATA ONLY <confirmationToken>
```

The phrase is displayed but not prefilled. The planner binds paths/hashes; execution rebuilds/revalidates the plan under the lock and refuses changes. The harness does not invoke execution on preview, startup or install. No live plan/count can be supplied while the expected package is absent. Do not substitute an invented digest or execute a reset during this preparation. Do not manually delete records to bypass an error.

## Isolated synthetic qualification

After separate approval and compatibility verification, use **unarmed-qualification.apk**. Enter the confirmed serial, attest that the target is development-only, and separately authorize the synthetic namespace. All test records use a marker-guarded app-private `files/pvfd_qualification_v1/documents/` namespace rather than normal `app_flutter/` documents. Unexpected pre-existing namespace contents stop the harness. Production repository, encryption, pinned operational public key, native Keystore and native durability bridge are reused; only failure hooks are synthetic. No operational recovery private key is needed. New synthetic local-encryption aliases/nonce entries are created only when these tests are explicitly run; existing aliases/records are not removed. No cleanup/reset runs automatically.

Run in this order and require each displayed PASS before continuing:

| Case/action | Expected result | Failure criterion |
| --- | --- | --- |
| Basic create/read/update, then repeat | Fictitious TEST ONLY record with Unicode and fixed timestamp authenticates; sequence increases | Any storage/authentication error, duplicate basic record, missing update |
| Autosave | 750 ms controller autosave plus awaited flush persists synthetic fields | Missing record, dirty/error state or timeout |
| Restart/queue | After completed save, force-stop/relaunch harness and Verify restart | Missing/authentication-failed record, empty pending queue |
| Offline | Operator disables network on target; repeat Basic and Verify restart over USB ADB | Network dependency or attempted upload; no uploader is configured |
| Bounded ENOSPC | Injected errno 28 before recovery staging; previous revision/hash/queue remain intact | Success reported for failed write, changed prior bundle, missing record |
| Tamper | Flip one tag bit only in isolated synthetic ciphertext; load rejects; finally restore original encrypted bytes and sync | Unauthenticated read succeeds, restoration fails, any normal-record access |
| Pre-publication termination, last | Complete stage is paused before rename; force-stop; restart Verify sees previous revision/hash and retained orphan | Incomplete stage promoted, previous bundle changed/lost, missing orphan |

The offline step is operator controlled; do not change device networking during preparation. Queue checks prove local pending-bundle persistence, not AWS delivery. Synthetic fixtures contain invented identifiers, TEST ONLY names, fixed `2026-10-22` incident time and Unicode. Status text reports counts/sequences/errors, not clinical fields.

For the controlled termination case select Pause before publication and wait for `READY_TO_TERMINATE`. Only after confirming this foreground synthetic session, the operator may separately authorize:

```sh
adb -s R95Y804S2PV shell am force-stop com.pvfd3.pvfd_epcr
adb -s R95Y804S2PV shell am start -n com.pvfd3.pvfd_epcr/.MainActivity
```

Then re-attest the target and select Verify restart. These commands must not interrupt a normal editor with unsaved work. Run this case last: its checkpoint intentionally remains for inspection and later normal updates would invalidate the comparison. Cancel instead releases the pause as a rejected write and removes only this run's synthetic checkpoint; no records are deleted. Force-stop tests process death, **not hardware power loss**. No physical power interruption is proposed.

The bounded low-space test serializes at most 16 KiB of synthetic payload and injects `FileSystemException`/errno 28 at the staging hook; it writes no filler files and cannot consume all Android storage. This tests rejection/retention behavior, not actual kernel ENOSPC, SQLite exhaustion, directory-fsync failure or an OEM filesystem under full-volume pressure. Genuine capacity qualification needs a separately reviewed bounded emulator/test filesystem; do not fill `/data` on either tablet.

## Metadata-only inspection

From repository root, after the missing-package blocker is resolved:

```sh
python3 tools/pvfd_qualification_inspect.py --serial R95Y804S2PV --adb "$HOME/Library/Android/sdk/platform-tools/adb"
```

The tool is read-only and pinned to that serial/package/user. It lists recognized relative filenames, SHA-256 hashes, envelope header fields and strictly validated five-field queue metadata. It does not decrypt, export full ciphertext or read legacy JSON payloads, keys, clinical contents or recovery private keys. It limits traversal/output, rejects symlinks and reports unknown paths by count only. It covers normal documents and the isolated synthetic documents namespace. Its provisional normal-storage reset candidate list is not the hash-bound executable reset plan. Missing roots are reported as absent, not certified empty. Never replace it with `cat` of record JSON, a full app-directory pull or unrestricted logcat.

Current invocation stopped safely because the package is absent, before private file inspection. Filenames/header inspection supplements authentication tests; it is not a forensic proof that every OS storage surface lacks plaintext.

## Filesystem durability and limits

The Android bridge accepts only canonical directories inside the application's data directory. It applies owner-only permissions, opens without following the final symlink, verifies a directory with `fstat`, calls `Os.fsync`, then closes. Public SDK availability requires the `fstat` check instead of `O_DIRECTORY`. Unsupported/failed directory sync fails the write rather than acknowledging durability. Generation files are flushed, staging directory synced, directory atomically renamed on the same filesystem, then record/base/documents directories synced. Post-rename sync failure is an ambiguous commit; the previous generation is retained and failure reported. Stages are not promoted during recovery. Unknown files are preserved/fail closed.

Advisory locking assumes the supported single writer isolate; uncontrolled external writes and hardware/storage firmware behavior are outside that guarantee. The operator-reported protected-write PASS exercises the native directory-sync path, but no independent syscall trace or device durability log was captured here. No claim of power-cut durability or real low-space hardware qualification is made. Reset can partially complete on storage failure and is development-only, not secure erasure or a migration strategy.

## Local validation

See the preparation result reported with this document for build/certificate hashes. Flutter analysis/tests, Python tests and source-candidate audit are run locally; passing them does not remove the device/package blocker. All unrelated work remains uncommitted and preserved. No armed build is installed and no operator reset authorization has been supplied.

## Candidate APK evidence

All three builds succeeded. Each is `com.pvfd3.pvfd_epcr`, version `0.1.0-alpha`, version code `1`, compile SDK `36`. Public debug signing certificate SHA-256 is `5209f9ce37da3dd356671d75d35f2a90e7ddba496e806cf1fca1062ac2f5ef67` for all variants; installed certificate comparison remains blocked.

| Variant | APK SHA-256 |
| --- | --- |
| `armed-reset.apk` | `5a10c7241a12da7b955087b4c090dcfb0257b7b126a120e9c7f8fcae73621b53` |
| `unarmed-qualification.apk` | `84cf92c4ae967b87d033b787dd3d88f272345cf52c7441f138e76df3b560cfd4` |
| `unarmed-normal.apk` | `dc10f7b24f2c8d3ee1b67bfced8e5b887bc82b405ae08b44bde3f911e922aaaf` |

These artifacts are outside source control. No installation was attempted.

Local results: `flutter analyze` PASS; `flutter test` PASS, all 138 tests; all three Android debug builds PASS; `python3 -m unittest discover -s tools/tests -p 'test_*.py'` PASS, 21 tests; source-candidate audit PASS, 213 files and zero heuristic findings; `git diff --check` PASS. Existing nonfatal PDF Helvetica Unicode and Android dependency build warnings remain. The default-disabled harness widget test and reset-preview metadata tests pass. No hardware cases were executed. Pre-existing Share UI and native recovery-test modifications were verified byte-for-byte unchanged. Git HEAD remains `b1602e197299d0a7fea5d81a82691a8c4d06e1c4`; index is empty of staged changes.

## Finalization validation boundary

Finalization targets `feature/m4-2b-encrypted-storage` from `b1602e197299d0a7fea5d81a82691a8c4d06e1c4`. The Share UI and operational native test-runner changes are excluded. Exact staged-source validation and security-audit results are recorded below when complete. Normal application installation requires a fresh explicit operator approval after live package/version/public signing-certificate comparison. No reset, AWS integration, second-tablet operation, merge, tag or release is included.

Finalization exact-index export results: `flutter pub get`, `flutter analyze`, all **138 Flutter tests**, all **21 Python tests**, and the Android normal debug build PASS. The build explicitly sets both `PVFD_ALLOW_DEVELOPMENT_RESET=false` and `PVFD_HARDWARE_QUALIFICATION=false`. The 213-file staged inventory/security audit passes with zero heuristic findings; no runtime artifacts or private credentials are staged. The two unrelated modifications remain excluded. Local validation logs are independently captured under `/private/tmp/pvfd-m42b-final-check-*.log`; original hardware qualification results remain operator-reported.

The final normal APK is rebuilt from the exact staged application source, excluding the unrelated Share UI change, and copied to `/private/tmp/pvfd-m42b-qualification/unarmed-normal.apk`. Its SHA-256 is `fb5c8de602a2ce69e80e03e56a302b24411bf26176192fedbdb3a736e34a38fb`. This supersedes the earlier normal APK hash in the historical table. The normal entry point has no qualification imports, qualification library/entry URIs or pause UI label in its packaged kernel. Repository failure-injection callback parameters remain available for automated tests but are unset in normal application composition; no injected test behavior is active. Reset is disabled. No normal-app installation has been performed during finalization.
