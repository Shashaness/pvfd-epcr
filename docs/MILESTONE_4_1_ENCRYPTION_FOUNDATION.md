# Milestone 4.1 — inactive encryption foundation

Date: October 22, 2026. Branch: `feature/m4-1-encryption-foundation`.

## Scope and architecture review

This is infrastructure and synthetic testing only. **Existing records remain plaintext JSON. No migration or repository integration is active.** Android app-private storage alone is not application-layer encryption. This milestone does not make the application HIPAA-compliant or authorize production deployment.

Reviewed Milestones 1–3 and the current layered implementation. `LocalEpcrRepository` delegates JSON reads/listing and ordered atomic sibling-temp writes/exclusive ID reservations to `data/storage/EpcrStorageService`. `EpcrController` owns editing, lossless unknown-field merges, revision tracking and the 750 ms autosave timer; the lifecycle service flushes it. None of these components, their JSON schema, IDs, medical models or files was changed. PDF/NEMSIS generators, printing, native sharing, exports, record management and application composition are unchanged by this milestone.

`lib/services/encryption/` adds byte-only `RecordEncryptionService`, `EncryptionKeyManager`, `AesGcmProvider`, a versioned envelope codec, safe typed errors and an Android adapter. There is deliberately no import of these services from the repository, controller, application startup or UI. Native channel registration is passive: no DB/key/file is created merely by registering it or launching the editor. Future integration must serialize before encrypting, then feed bytes into atomic persistence; decrypt/authenticate before JSON decoding. It must retain the current lossless schema and ordering guarantees.

The earlier Share cleanup was already uncommitted at the start of this milestone. Its file is preserved byte-for-byte and excluded from this milestone's local commit. Normal working-tree builds/tests include that prior cleanup; the committed source is also validated separately before committing. No new UI behavior is introduced here.

## Threat model and exclusions

When explicitly called, the foundation protects payload confidentiality and authenticity from an attacker who obtains encrypted record files without usable Keystore access. Metadata and external context are authenticated; corruption, modified bytes and wrong keys cannot return unauthenticated plaintext. Neither the service nor the native implementation logs inputs, keys, payloads, nonces, raw provider exceptions or patient identifiers.

It does not protect existing plaintext records, PDF/XML exports, receiving-app copies, printer jobs, screen capture, memory of an unlocked app, compromised/rooted OS or app process, privileged debugging, malware able to invoke the app's keys, deletion/denial of service, replay of a complete valid envelope, filesystem/VM rollback, physical fault attacks, or an attacker who can alter the app and its nonce ledger. There is no biometric/access gate, key attestation, secure backup, retention policy, audit trail or compliance certification. Debug signing/debuggability remain development limitations. Payload sizes and opaque key identifiers are visible; identifiers must never contain patient information. Dart/JVM garbage-collected memory cannot provide a guarantee of plaintext zeroization.

## Design choice and cryptographic parameters

Selected **A: direct AES with a non-exportable Android Keystore key**. Keystore generates a random 256-bit AES key; key bytes never enter Dart, a platform-channel message or an application key file. AES/GCM/NoPadding uses a provider-generated 96-bit nonce and a 128-bit tag. `setRandomizedEncryptionRequired(true)` is mandatory; the production encrypt API cannot accept a supplied nonce. Decryption exposes plaintext only after successful authenticated `doFinal`.

Approach B (random DEK wrapped by a Keystore key) can support future recovery/portable wrapping schemes, but requires handling the unwrapped DEK in application memory, another persistent format, and recovery/wrapping lifecycle decisions. It brings no current recoverability benefit without a separately authorized recovery design. Direct Keystore encryption has fewer exposed key surfaces for this Android-only, device-bound phase. Changing to wrapped keys would require a new explicit envelope algorithm/version and migration plan, not an implicit fallback.

A small SQLite nonce ledger (`epcr_crypto_nonce_v1.db`) reserves every provider-generated nonce under the opaque key ID in a unique `(id, nonce)` row **before ciphertext can be returned**. Reservation uses a committed SQLite transaction; failure, an observed collision or a full ledger returns no ciphertext. Reserved-but-unused nonces after a failed operation are intentionally never reclaimed. Both process serialization and the DB uniqueness constraint apply. The conservative limit is 65,536 encryptions per key, then `keyExhausted`; decryption remains possible. Milestone 4.2 must plan usage/rotation before activation, particularly for frequent autosaves. The ledger contains only key IDs and nonces, never plaintext, AAD, medical IDs or keys. It may grow to a few MB per exhausted key.

This combines established platform randomness with durable collision rejection, rather than claiming that independent random draws can never collide. A key with missing nonce-ledger enrollment fails closed; it is not re-enrolled automatically. Restore/rollback of only part of ledger state cannot be made safe by this mechanism; whole-device rollback is an excluded threat. Backup/restore of the ledger or encrypted files is unsupported. There is no automatic DB recreation that enrolls an existing key, destructive upgrade, reset, deletion, reuse retry or usage-cap bypass API.

AAD is the exact ASCII domain `PVFD/ePCR/envelope/v1` followed by a zero byte, the full encoded header including key ID and ciphertext length, then a four-byte big-endian external-context length and the external-context bytes. Empty context is allowed; future integration must define stable record binding where needed. Wrong/missing context fails authentication. The nonce is the GCM IV, so modifying it also invalidates authentication. This is domain separation, not a change to medical JSON.

## Key lifecycle and platform boundary

Keys use the alias prefix `pvfd.epcr.aes.v1.` plus an opaque ASCII ID. `create(id)` is explicitly invoked and fails if either the Keystore alias or ledger enrollment exists. `lookup(id)`, encrypt and decrypt never create a key. No default key is chosen on app startup. Failed generation/enrollment can leave an orphaned unusable key; operators must investigate rather than silently replace it.

Future rotation means explicitly provisioning a different ID, validating it, switching a separately managed active-key pointer, and retaining older keys for authenticated reads until migration and recovery policy permit retirement. No active pointer, deletion, key retirement, rotation orchestration or re-encryption exists in this phase. A missing/invalidated key is a recovery incident, never permission to replace the key and overwrite records.

The narrow channel `com.pvfd3.pvfd_epcr/encryption` exposes only `createKey`, `lookupKey`, `encrypt`, `decrypt`. It runs on a Flutter background task queue; a native lock serializes operations and key provisioning. Native input dimensions and IDs are independently validated. Only safe error codes and generic text cross the channel. There is no network operation or runtime cryptography dependency beyond Android platform APIs.

The app's current minimum is Android API 24 (Android 7), compile/target SDK 36, Java/JVM 17. Android Keystore AES-GCM is available on supported Android versions, subject to actual provider/device capability. Other platforms fail with `platformUnavailable`; there is no software-key fallback there. No SDK, application ID, signing configuration, permissions, backup policy or biometric requirement was changed. Existing manifest backup/data-extraction exclusions remain in place.

StrongBox is requested when advertised on API 28+. Only `StrongBoxUnavailableException` allows a fresh-key fallback to the default Keystore provider, and only when no alias appeared. Other errors stop. Actual protection is obtained from `KeyInfo`, not inferred from model/feature flags: API 31+ reports StrongBox, trusted environment, software or unknown. Older devices report hardware-backed without asserting which hardware type, or software. Unknown remains unknown. A software-backed Android Keystore key remains non-exportable through this API, but has weaker isolation than verified hardware protection. Hardware-backed storage is not remote attestation or proof against a compromised OS.

## Envelope v1 specification

All integers are unsigned, big-endian. No compression, JSON interpretation or implicit format detection occurs. Entire payloads are bounded to 16 MiB; external context is separately bounded to 16 MiB. The codec requires exact length with no trailing bytes.

| Offset | Size | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `PVFDECRY` |
| 8 | 1 | Format version `1` |
| 9 | 1 | Algorithm `1`: AES-256-GCM / 96-bit IV / 128-bit tag |
| 10 | 2 | Key-ID byte length K, 1–64 |
| 12 | 4 | Ciphertext byte length N, 0–16,777,216 |
| 16 | K | ASCII key ID, `[A-Za-z0-9_-]` only |
| 16+K | 12 | Nonce |
| 28+K | N | Ciphertext (same size as plaintext) |
| 28+K+N | 16 | Authentication tag |

The authenticated header is bytes `[0,16+K)`. Parsing/unsupported-version checks occur before key lookup. Unsupported algorithms are never dispatched to a weaker cipher. Header changes to recognized parameters are authenticated; malformed or unsupported values are rejected earlier. Exact valid-envelope replay is not prevented by GCM; version/record freshness belongs to future repository policy.

## Failures and loss/backup implications

`EncryptionException` has a fixed safe code and no attached plaintext, key, identifier, envelope or original provider exception. Codes distinguish malformed/truncated envelope, unsupported version/algorithm, invalid key ID, size limit, missing/invalidated/unavailable/existing key, authentication failure, random/provider initialization failure, observed nonce reuse, exhausted key and unavailable platform. Unknown platform exceptions are sanitized to `cryptoFailure`; other unclassified native Keystore/provider/storage failures fail closed as `keyUnavailable`. Some devices may report permanent loss as unavailable rather than specifically invalidated; this never causes regeneration.

Uninstall, clear-data, device reset, Keystore loss/invalidation or transfer to a different device can make encrypted records permanently inaccessible. Signing/UID changes can also change access. Raw encrypted-file backup alone is not recoverability. The nonce ledger and non-exportable key must stay consistent; there is no supported restore/import/recovery workflow. Do not enable encrypted production storage until a reviewed recovery, backup and rotation policy exists. No biometric policy or user-authentication-bound key is configured yet.

## Automated and device validation

Validation results follow below. Tests use synthetic byte strings and published test vectors only. Raw keys/deterministic nonces exist only under `test/` and `src/androidTest/`, never in production encryption code. `cryptography` 2.9.0 (Apache-2.0) is a **dev dependency** for an independent host AES-GCM implementation; the lockfile adds only this package and no production dependency. Android tests use a small framework `Instrumentation` runner and platform APIs, with no additional test library dependency.

Host tests cover round trips (empty, Unicode, arbitrary binary and 1 MiB), nonce differences/collision rejection, ciphertext/tag/nonce/AAD/key-ID tampering, wrong/missing/invalidated keys, duplicate creation, simulated secure-random failure, every truncation boundary, malformed/unsupported/oversize envelopes, stable binary encoding, asynchronous input snapshots, safe platform errors, unavailable platform and malformed channel results. An IOOverrides trap verifies that the byte service/reference-provider operations make no filesystem calls. Native production code persists only nonce metadata; the native test persists only synthetic ciphertext and a process ID, never plaintext or key material. This is a source review and scoped test, not a claim to forensically prove absence of plaintext anywhere in OS memory or swap.

Two official NIST CAVP `gcmEncryptExtIV256.rsp` Count=0 vectors are checked independently in host and native tests: PTlen=0/AADlen=0 and PTlen=128/AADlen=128, both Keylen=256/IVlen=96/Taglen=128. Raw fixed test keys are public known-answer inputs, not deployed secrets. Matching expected ciphertext/tag tests interoperability; round trips alone would not establish it. These checks are not NIST/FIPS validation of this application.

The headless Android test has two explicit modes, using a fresh `m41_test_` identifier per run. `prepare` checks creation/retrieval, duplicate-create refusal, nonce differences, round trips, tampering, large/empty inputs, NIST vectors and durable nonce collision rejection. It writes only a synthetic ciphertext fixture. `verify` runs in a different process (asserted by PID), retrieves the existing key, decrypts that fixture, encrypts with a fresh nonce, checks wrong-key/missing-ledger failures and removes only this run's synthetic aliases, rows and fixture. It never starts Flutter/the editor or enumerates/opens ePCR records. Actual hardware invalidation and hardware RNG failure are not deliberately induced on the tablet; host fault injection verifies those error contracts.

To repeat, first build debug and `:app:assembleDebugAndroidTest`, identify/authorize the device, and compare the candidate signing certificate and version with the installed app. Stop on any mismatch; never use uninstall, clear-data, downgrade or a signing workaround. Install with direct `adb install -r -t` (no automatic uninstall fallback), then run the separate test component `com.pvfd3.pvfd_epcr.test/com.pvfd3.pvfd_epcr.CryptoSelfTestInstrumentation` with `-e mode prepare -e keyId m41_test_<32 fresh lowercase hex digits>` and subsequently `-e mode verify` with that same ID. Require `PASS` and result code `-1` for each; shell exit status alone does not indicate an instrumentation pass. No logcat or app-record access is needed. An interrupted test may leave its synthetic fixture/key; do not delete other aliases or files to clean it up.

## Validation results

| Check | Result |
| --- | --- |
| `flutter pub get` | PASS; cryptography 2.9.0 is the sole added package, dev-only. |
| Working-tree `flutter analyze` | PASS; no issues. |
| Working-tree `flutter test` | PASS; 100 tests, including all 53 original tests and 47 new encryption/channel tests. |
| Working-tree `flutter build apk --debug` | PASS. |
| `:app:assembleDebugAndroidTest` | PASS; separate headless test APK builds. |
| Authorized Samsung SM-X210, Android 16/API 36 | PASS; in-place update after exact public signing-certificate and version match. No uninstall, clear-data, downgrade or signing change. |
| Native synthetic `prepare` | PASS; create/retrieve, duplicate-key rejection, round trips, tampering, distinct nonces, 1 MiB/empty payloads, both NIST vectors and durable nonce-collision rejection. |
| Native synthetic `verify` | PASS in a distinct process; retained key decrypts prior ciphertext, fresh nonce, wrong-key and missing-ledger errors; this run's synthetic aliases/rows/fixture removed. |
| Actual key protection | `KeyInfo.securityLevel` reports `trustedEnvironment`; hardware-backed TEE confirmed for this test key. StrongBox is not claimed. |
| Local source audit | PASS; 184 reviewed filenames, zero heuristic findings; manual review identifies no new PHI or deployed key/credential. Fixed raw key values are explicitly public NIST test vectors in test-only sources. |
| Exact staged-source export | PASS: fresh 184-file index export, `pub get`, clean analysis, all 100 tests and Android debug build, excluding the prior UI diff and all ignored artifacts. |

Device tests exercise the production native provider, not a Dart replacement, without launching the editor. Host tests exercise Dart envelope orchestration, an independent AES-GCM implementation, and mocked channel contracts. There is no claim of a live Flutter-channel/device end-to-end test or exhaustive testing on every Android version. Genuine hardware RNG failure/invalidation, ledger exhaustion and power-cut durability were not induced; future operational qualification remains necessary. The test APK remains installed as a development tool; no operational report file was accessed, altered, encrypted or migrated. No regular application launch/clinical acceptance test was performed during this milestone.

Existing nonfatal PDF Helvetica Unicode and share_plus Kotlin Gradle Plugin migration warnings remain. Direct Gradle instrumentation builds also report existing Kotlin/AGP compatibility/deprecation warnings; the clean source build reports obsolete dependency Java 8 source/target warnings. These are not resolved by the encryption foundation.

## Remaining work and release controls

Milestone 4.2 must design crash-safe plaintext/encrypted detection and migration, backups/recovery, active-key rotation, nonce-ledger operational limits, partial-failure behavior, record-bound AAD and atomic byte persistence, with rollback/data-loss tests before activating encryption. Milestone 4.3 must design access/biometric policy and its invalidation/recovery consequences. Milestone 4.4 must address the planned remaining security validation and release controls, including export/cache retention, backups, device policies, signing and operational acceptance. None is implied complete by the foundation.

Historical Milestone 1–3 audits remain unchanged. The current reviewed filename inventory is updated for the added foundation source/tests/document; the 174-file Milestone 3 count is historical. No existing baseline history is rewritten. This phase authorizes a local feature-branch commit only, with no push, tag, release or APK distribution.

## References

- [Android Keystore security, non-exportability and KeyInfo checks](https://developer.android.com/privacy-and-security/keystore).
- [Android randomized-encryption requirement](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setRandomizedEncryptionRequired(boolean)).
- [NIST CAVP block-cipher mode testing](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/cavp-testing-block-cipher-modes) and [official GCM vector ZIP](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/mac/gcmtestvectors.zip).
- [Test-only cryptography package](https://pub.dev/packages/cryptography).
