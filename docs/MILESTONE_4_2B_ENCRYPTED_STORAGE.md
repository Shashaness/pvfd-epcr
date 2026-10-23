# Milestone 4.2B — encrypted-only local persistence (review build)

## Scope and deployment boundary

This implementation intentionally abandons plaintext ePCR compatibility. Finalization is on `feature/m4-2b-encrypted-storage`, based on `b1602e197299d0a7fea5d81a82691a8c4d06e1c4`. Controlled synthetic qualification passed on development-only Samsung SM-X210 (`R95Y804S2PV`) according to the operator report dated October 22, 2026; see [qualification evidence and limitations](MILESTONE_4_2B_SAMSUNG_QUALIFICATION.md). Normal-editor installation/acceptance requires separate explicit approval. No AWS integration, plaintext migration or production deployment is authorized.

The district states both tablets contain development data only. This is not automatic permission to reset them. The operational private recovery key is never accessed. Original unrelated Share UI and operational encryption-only instrumentation modifications are preserved byte-for-byte.

The default `LocalEpcrRepository` in this source now uses protected persistence. The next installation of this source would change save behavior; do not install it until the design and device-validation plan are approved. Existing installed binaries remain unchanged. Existing plaintext files are never opened as records, migrated, encrypted in place, or silently ignored.

## Inspected lifecycle and integration

Previously, `LocalEpcrRepository` passed a lossless JSON map to `EpcrStorageService`, which serialized it to `pcr_<report-id>.json` via a flushed sibling temporary file and atomic rename. A 750 ms timer/controller lifecycle flush managed revisions and awaited storage. The old application had no delete operation; this phase supplies repository/storage delete semantics without adding a UI action.

Now the controller's timing, dirty-revision logic, exclusive create future, stable medical IDs, unknown-field merges and in-memory editing remain unchanged. The repository still returns its own committed creation snapshot, without a read-after-write race or deriving medical IDs from filenames. It binds the controller to an opaque `record.epcr` handle. An explicit repository delete publishes a protected tombstone. PDF/NEMSIS XML generation, printing, native sharing, validation and form behavior are unchanged. Export/print/share derivatives remain plaintext by their existing design; encrypted JSON persistence does not secure recipients or export caches.

Startup recovery inspection surfaces a fixed diagnostic when legacy plaintext is detected. Listing any root `.json` file blocks ordinary storage operations (the previous implementation treated root JSON as possible records), without reading its contents. Direct loading of a `.json` path is rejected. No empty-database fallback is used for corrupt/unreadable committed encrypted data. Unknown/unrelated JSON requires operator classification; the reset must not broaden its deletion rules to clear that diagnostic.

## Physical layout and formats

Default root is `getApplicationDocumentsDirectory()`, Android's app-private Flutter data directory. All local ciphertext, portable backups and pending metadata stay beneath it. No public/external/OneDrive directory is used for persistence.

```text
<private documents>/protected_epcr_v1/
  .lock
  keys.json                          # version + opaque active Keystore alias ID only
  <32 lowercase random hex>/         # independent storage ID; not a report identifier
    record.epcr                      # fixed nonclinical handle marker
    committed.marker                 # fixed marker for acknowledged/visible history
    rev_<16 decimal digits>/
      local.enc                      # existing PVFDECRY AES-256-GCM envelope
      recovery.pvfdbak                # existing PVFDBAK1 portable encrypted bytes
      pending.json                   # nonclinical metadata; schema below
      .uploaded                      # optional future-upload acknowledgment marker
    .stage_<32 random hex>/          # uncommitted generation, never promoted on read
```

`keys.json` contains only `version:1` and `active:local_<32 random hex>`, not key bytes. The Android Keystore and its existing nonce DB remain separate from documents. `record.epcr` contains `PVFDSTORE1`; `committed.marker` contains `PVFDCOMMITTED1`. These are not patient data or keys. The latter allows a record whose committed generations disappeared to fail explicitly, rather than be mistaken for an interrupted new record. A crash after publication but before this marker can leave a readable complete generation that was never acknowledged; retries reconcile it.

`pending.json` has exactly five fields: `version`, `revision`, `operation` (`save` or `delete`), `recoveryKeyId`, and `recoverySha256`. It contains no JSON payload, report ID, patient name, address, narrative or timestamp from a record. Filename/storage ID, revision numbers and operation state are nonclinical. SHA-256 covers ciphertext, not plaintext. Public recovery key ID is pinned to `23c0301fc9fbf5898b1354484203b928c197ed95d843411fa6e3f3acc1dd88dd` for default writes.

Both existing encrypted envelopes are unchanged: 16 MiB byte payload bound, AES-256-GCM, 96-bit nonce, 128-bit tag. Portable backup uses fresh per-backup AES key wrapped with RSA-3072 OAEP-SHA256/MGF1-SHA256. The clinical JSON is serialized once and the same bytes feed local and recovery encryption. Storage generates no plaintext JSON file or plaintext temporary file. A delete uses encrypted `{"deleted":true}` and authenticated `operation:delete`; the opaque storage identity, not a clinical ID, identifies its queue entry.

Local external AAD context is UTF-8 `PVFD/local-store/v1/<opaque-storage-id>/` followed by canonical JSON for the five metadata fields in the order above. The existing local envelope additionally authenticates its own header and domain. This binds local data to identity, revision, operation, recovery fingerprint and exact portable backup bytes. Altering queue metadata, swapping backup artifacts, or changing a save to delete fails before exposing a medical map. Legacy clinical JSON schema is not expanded with storage metadata. Read errors use fixed codes; medical parse failures are sanitized rather than forwarding JSON-bearing format exceptions.

Reads validate exact metadata fields/types and bounds, generation-name/revision match, the portable envelope's key ID/length limits, backup SHA-256, and authenticated local decryption before JSON deserialization. An older recovery-public-key fingerprint remains readable when local authentication succeeds; explicitly selecting a new write fingerprint must not invalidate prior local records. The optional injected write fingerprint exists for explicit configuration/rotation and test keys, not automatic fallback. Default production configuration never selects a test key.

## Crash-consistent protected save

1. Snapshot/serialize the requested medical map before queueing so later edits cannot change it.
2. Serialize operations for the document root across service instances. Hold an advisory exclusive POSIX file lock for the entire transaction, including key rotation and queue changes; the application's normal operation is one UI isolate. Multiple independent Dart writer isolates in the same process are not supported by the isolate-local queue and require a separately reviewed shared coordinator; advisory file locks primarily guard cooperating processes.
3. Reject root legacy JSON. For updates, authenticate the current committed revision first; missing/corrupt keys/data cannot be silently overwritten. Choose the next monotonic storage revision.
4. Generate the portable backup fully in memory. Select/provision/rotate a local key under the same lock, then generate local authenticated ciphertext bound to its metadata and backup hash. If either cryptographic operation fails, no new record payload is written.
5. Create an opaque staging directory. Write/flush `local.enc`, `recovery.pvfdbak` and nonclinical `pending.json`. There is no independently committed queue file that could race its data.
6. Fsync the staging directory through the Android `Os` bridge. Rename that entire directory to its revision name in the same record directory; this is the visibility/commit boundary. Readers ignore `.stage_*` directories.
7. Flush the committed-history marker, fsync the record directory, store base and documents parent. Only after all these complete does the save future succeed and the controller clear its captured dirty revision.
8. Coalesce superseded generations only after durable publication. Remove only recognized members; unknown members are retained for manual review. Cleanup failure is not treated as loss of the newly durable revision.

The directory bridge validates app-private paths, opens with no-follow protection, verifies the descriptor is a directory and calls `Os.fsync`. Native/app-private directories are mode 0700. File writes use Dart's flushed byte writes. There is no delete-destination or cross-filesystem-copy fallback. Unsupported/unavailable native durability fails closed. A native filesystem failure is not permission to write plaintext.

Crash before rename leaves the prior complete generation and possibly a staging orphan; no promotion is attempted. An interrupted first creation without a committed generation is not listed as a live record and is reported as an orphan. A committed-history marker without a generation is an explicit storage error. Corrupt latest generations block reads rather than silently returning an old revision. Rename followed by fsync failure is an **ambiguous commit**: the caller sees failure and keeps dirty edits, while a complete newer revision may already be visible. Both generations are retained until a later successful save. A retry with the controller's matching `appRecordId`/`epcrNumber` binds the same record instead of allocating a duplicate; unrelated ID collisions still retry allocation. Full valid-directory deletion/rollback by an attacker is not prevented.

Deleting publishes and durably stages a new authenticated tombstone plus its portable recovery artifact and pending entry. Lists exclude tombstones; reads/updates of deleted records fail. Repeated deletion is idempotent. Physical garbage collection retains the tombstone and newest queue state. This is logical deletion, not a forensic secure-erasure claim, retention policy or authority to delete operational data.

## Durable queue and future synchronization

The committed generation itself is the pending-upload record; startup has no separate transaction/queue reconstruction window. `pendingUploads` authenticates the bundle and returns opaque ID, revision, operation, ciphertext hash and app-private portable-file path. It omits medical fields. Restart lists the newest unacknowledged generation for each record, including tombstones. Rapid saves remain ordered; obsolete pending generations coalesce to the newest durable revision after successful publication. Every successfully acknowledged revision had its complete protected bundle, even if it is later superseded.

`readPendingUpload` checks that a descriptor still matches the newest authenticated revision and hash under the lock, then returns a byte snapshot; stale descriptors return null. Future uploaders must use this method rather than treating an old path as a permanent lease. They must use immutable object keys `<opaque-id>/<revision>.pvfdbak`, never let stale uploads overwrite a shared mutable "latest" object, and separately design any server-side head pointer with conditional monotonic updates. No network uploader exists here.

`acknowledgeUpload` compares the current revision/hash and refuses stale acknowledgments. A valid acknowledgment is flushed and directory-synced; new saves create a fresh pending generation regardless of an earlier acknowledgment. There are no timers, AWS calls, credentials, background upload scheduling or automatic backup transmission. An eventual S3 implementation must preserve these version rules, authenticate requests, keep objects encrypted-only and provide separate authorization/retention semantics. An old immutable remote object may exist after a newer one; selecting the newest valid revision is part of future synchronization design.

## Key and nonce lifecycle

The existing native nonce ledger's 65,536-use hard cap remains mandatory. Native `keyUsage` exposes only a validated use count for an existing key; lookup/count does not create or replace keys. Each protected write checks use count and rotates at **60,000**, leaving 5,536 uses of headroom. There is no cap bypass or deliberate nonce reset.

The first protected write to an empty store explicitly provisions a fresh random opaque alias and flushes/atomically replaces `keys.json`; there is no key creation at application startup or during decryption. A new key is created and looked up before switching the durable pointer. Old aliases/nonce history are retained indefinitely, and each local envelope carries its own key ID, so old records remain decryptable across rotation. No operational key is rotated or deleted on the test tablets during this work.

Missing/invalidated active keys and missing/corrupt active index with existing record handles fail closed. They do not trigger regeneration. A missing index does not prevent an otherwise valid old envelope from being read using its own key ID, but it blocks new writes until recovery is explicitly reviewed. Failed new-key generation leaves the old active pointer and all data intact. Interrupted pointer publication may leave a new unused alias or an already selected fresh key; no old key is deleted and no data save is acknowledged on that failure. An exhausted key is rotated explicitly on the next policy-controlled write after count inspection; underlying provider failures still propagate without plaintext fallback.

All normal writers share the root lock. External direct users of the low-level cipher could consume additional nonces after a count check; the native hard cap still fails closed, and the next retry rechecks usage. Automatic retirement/re-encryption of old keys, key custody/recovery policy, full-device rollback resistance and operational performance/usage monitoring remain review work. Portable backups remain independently recoverable with the district private key; this phase never accesses it.

## Development-only reset — guarded procedure

The reset API is deliberately absent from startup, upgrades and normal UI controls. It is blocked unless `kDebugMode` and an explicitly armed `PVFD_ALLOW_DEVELOPMENT_RESET=true` development build (or explicit test injection) are in effect. Release/profile builds cannot execute it. The operator must attest that the selected tablet holds **development data only**; code cannot classify whether a clinical payload represents a real person. Never install an armed debug-reset build on a production-data device.

`prepareDevelopmentReset(documents)` creates a plan, file hashes and a confirmation token. It recognizes only the old `pcr_<safe-id>.json` naming family (including known `.reserve`/`.epcr-tmp-*` variants), exact protected store markers, generation/stage directories and their known members, and abandoned key-index temporaries. It refuses symlink/unknown members inside record directories. Unrelated root files and active `keys.json` are preserved. The Keystore and native nonce DB are outside the reset's scope.

`executeDevelopmentReset(plan, confirmation: ...)` requires the exact phrase `DELETE CONFIRMED DEVELOPMENT DATA ONLY <plan token>`. It rebuilds the plan, checks additions and file hashes under the transaction lock, then deletes only planned known members/directories. Changed plans or unknown members abort before deletion. Unknown root JSON is deliberately not deleted, so an unresolved root-JSON diagnostic can remain. Deletion interrupted by power/process loss can be partial; re-plan rather than assuming an all-or-nothing wipe. Keys/identity are never reset.

The following reset procedure requires separate explicit approval for each target. This finalization authorizes no reset and no operation on a second tablet:

1. Record the tablet's authorized ADB serial and confirm with its owner that it is one of the two development-only tablets. Do not target another device, auto-select from a list, or inspect real records to make this determination.
2. Review retention of any needed synthetic work and the exact filename rules. Obtain separate permission to install/execute the reset. Compare installed/candidate package, signing certificate and version; stop on any conflict. Never uninstall, clear-data, downgrade or change signing.
3. Build an explicitly armed debug version with `--dart-define=PVFD_ALLOW_DEVELOPMENT_RESET=true`. An operator/developer must invoke the guarded API in a reviewed debug session (no normal UI reset button is shipped). Example calls, **not executed here**:

   ```dart
   final storage = EpcrStorageService();
   final documents = await getApplicationDocumentsDirectory();
   final plan = await storage.prepareDevelopmentReset(documents);
   // Review the recognized file count and token privately; verify development-only target.
   await storage.executeDevelopmentReset(
     plan,
     confirmation: 'DELETE CONFIRMED DEVELOPMENT DATA ONLY ${plan.confirmationToken}',
   );
   ```

4. Confirm known development records/queue artifacts are gone, unrelated files and `keys.json` remain, and Keystore keys/nonce history were not deleted. Do not remove an unknown file to bypass a block. Repeat independently for the other authorized tablet.
5. Use the normal unarmed review build for subsequent approved testing. Qualify a fresh synthetic create/read/update/restart/offline cycle and independent recovery before production activation. No reset or new installation is performed in this milestone.

## Tests, coverage and limits

The storage tests now exercise encrypted create/read/update/delete, snapshots/ordering across instances, no plaintext payload in any local/staging member, JSON-free queue metadata, interrupted replacement/staging/encryption, directory-sync failure, ambiguous post-rename failure and idempotent retry, restart/persistent queue, stale ack/descriptor rejection, ciphertext/backup/metadata tampering, missing/invalidated keys, absent key index, pre-limit/exhausted rotation, failed rotation, explicit legacy rejection, orphan retention/no promotion, committed-generation loss, guarded reset/unknown-file/changed-plan safety, and operation with HTTP clients forbidden.

Existing plaintext-storage compatibility assertions were intentionally replaced; supporting plaintext now would violate the project decision. UI/controller/repository tests use explicitly injected synthetic cryptography rather than a production software fallback. They continue to cover unknown clinical fields, PMH, lifecycle/autosave, switches, failures, IDs and PDF/XML. Widget startup orphan inspection is separately stubbed to avoid scheduling real filesystem IO in Flutter's fake timer zone; actual orphan behavior is exercised by storage tests. Production has no test keys/default or deterministic random source.

`tools/tests/protected_storage_interop.py` generates a synthetic memory-only RSA private key, executes the **compiled production Kotlin `RecoveryEncryption` class** through a small Java entry point on the host JDK, stages its actual `PVFDBAK1` bytes through the real Dart storage transaction/queue, then independently decrypts that newest queue artifact with Python and compares exact bytes after simulated loss of the test local keys. It adds no cryptographic algorithm implementation. This is a host-JVM/JCA test, not a new physical Android run. Prior Milestone 4.2A/operational Android-to-Python verification remains historical evidence for the unchanged portable format. The real operational private key is never used by these tests.

After a debug build, repeat host interoperability with the installed JDK home and Kotlin stdlib JAR:

```sh
python3 tools/tests/protected_storage_interop.py \
  --java-home /path/to/jdk \
  --kotlin-stdlib /path/to/kotlin-stdlib.jar
```

Host storage tests inject directory-sync outcomes; they do not prove device filesystem/power-cut durability or cross-process lock behavior on every Android version. The operator reports successful synthetic writes, restart/queue retention, simulated low-space rejection, tamper rejection and controlled process termination on the selected Samsung tablet. These results do not prove hardware power-loss durability, real full-volume behavior or exhaustive filesystem failure handling; these remain operational qualification limitations. Normal-editor acceptance is still pending explicit installation approval. No HIPAA-compliance, secure backup/retention or production-safety claim is made.

## Validation results

| Check | Result |
| --- | --- |
| `flutter pub get` | PASS; only the existing crypto 3.0.7 package is promoted to direct; package versions unchanged. |
| `flutter analyze` | PASS; no issues. |
| `flutter test` | PASS; 137 tests, including updated encrypted-only persistence regressions and the unchanged crypto/document/controller suites. |
| `flutter build apk --debug` | PASS; built locally only, not installed. |
| Explicit protected-storage interoperability | PASS; one additional configured Flutter transaction/queue test, production Kotlin/JCA encryption on the host JVM, independent Python exact-byte recovery after simulated loss of synthetic local keys. |
| Python recovery unit suite | PASS; all 19 tests. |
| Python static syntax | PASS: `python3 -m compileall -q tools`. |
| Candidate publication/security audit | PASS; 206 reviewed source filenames, zero heuristic findings, exact candidate/inventory match; no keys, PHI or runtime artifacts added. |
| Preserved prior changes | PASS; UI and operational test-runner files match their pre-task hashes byte-for-byte. |
| Git controls | HEAD remains the provisioning commit; no stage, commit, push or tag. |
| Android/device qualification | Operator-reported PASS on one development-only Samsung SM-X210; final Verify restart PASS. No independently captured original device test logs. See qualification record. |

The ordinary Flutter run intentionally does not execute the separately configured JVM/Python interoperability test until its explicit synthetic harness supplies public-test-key/JDK paths. Its dedicated invocation passed. Existing PDF Unicode and share_plus/Kotlin migration warnings remain nonfatal. Host test durability adapters simulate filesystem failure points; they do not claim physical power-cut validation. No separate Python static type checker is claimed. No tablet reset, new application install/launch, tablet-key rotation, operational private-key access, migration or AWS synchronization is performed.

## Files and dependencies

- `lib/data/storage/epcr_storage_service.dart`: encrypted revision transactions, authenticated queue and guarded reset.
- `lib/data/storage/protected_storage_crypto.dart`: native directory durability and explicit key policy/recovery composition.
- `lib/data/repositories/epcr_repository.dart`: opaque handles, creation identity and delete API.
- `lib/application/controllers/epcr_controller.dart`: clear legacy-storage diagnostic only; autosave algorithm unchanged.
- `lib/services/encryption/android_keystore_provider.dart`, Android `KeystoreEncryption.kt`: safe native use-count lookup.
- Android `MainActivity.kt`: narrow directory-fsync channel and use-count dispatch.
- `pubspec.yaml`/lockfile: `crypto` 3.0.7 promoted from existing transitive to direct for SHA-256 ciphertext binding; no package version change. Existing direct license notice is added.
- `test/storage_test.dart`, `test/repository_test.dart`, `test/widget_test.dart`, `test/support/memory_repository.dart`: adapt obsolete plaintext assertions and preserve functional regression coverage.
- `test/support/protected_storage.dart`: synthetic test crypto/durability only.
- `test/protected_storage_interop_test.dart`, `tools/tests/NativeRecoveryEncrypt.java`, `tools/tests/protected_storage_interop.py`: committed-queue/native/Python interoperability, explicitly invoked with test configuration.
- Root README/security/notices, the operational public-key integration note, `.gitignore`, publication audit allowlist and inventory: current behavior, operational-data exclusion and exact reviewed test tools.
- This design/test/reset document. Historical milestone audits and public-key configuration remain unchanged.

The two earlier dirty UI/instrumentation files are not part of the changes above and remain preserved. Finalization stages and commits only the reviewed 4.2B files on its dedicated branch; the two unrelated changes remain uncommitted.

## References

- [Android Os.fsync and directory descriptors](https://developer.android.com/reference/android/system/Os#fsync(java.io.FileDescriptor)).
- [path_provider documents directory](https://pub.dev/documentation/path_provider/latest/path_provider/getApplicationDocumentsDirectory.html).
- Existing Milestone 4.1, 4.2A and operational public-key documents define cryptographic formats and custody limitations; their historical results are not rewritten.

## Finalization record — October 22, 2026

The validation table above preserves the original implementation-stage host results (137 Flutter tests, 19 Python tests, 206 candidate files and no device test at that time). The qualification harness adds a default-disabled widget test and metadata-inspection tests. Current finalization reruns analysis, Flutter/Python tests, a normal debug build and the exact staged-source audit. Operator-reported device results are distinct from independently captured local validation logs. Normal app installation is approval-gated; AWS, production use and actual hardware power-cut/full-filesystem qualification are not authorized or established.

Finalization validation of the exact staged source: clean analysis, all 138 Flutter tests, all 21 Python tests and normal Android debug build PASS; staged 213-file publication inventory/security audit PASS with zero heuristic findings. Qualification result attribution and remaining deployment limits are recorded in the Samsung qualification document.
