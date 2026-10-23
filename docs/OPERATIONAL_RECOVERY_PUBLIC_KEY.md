# Operational recovery public-key provisioning

The public PEM supplied by the district was validated as a single canonical SubjectPublicKeyInfo RSA-3072 public key with exponent 65537. Only that public file was accessed. Its canonical DER bytes are embedded in `lib/services/recovery/operational_recovery_key.dart`; no private key was opened, read, copied or otherwise accessed.

Configured ID (SHA-256 of canonical DER SubjectPublicKeyInfo):

`23c0301fc9fbf5898b1354484203b928c197ed95d843411fa6e3f3acc1dd88dd`

`loadOperationalRecoveryKey(service)` is explicit and passive: it passes the pinned public bytes/ID to the existing Milestone 4.2A loader, whose Android implementation validates RSA parameters, canonical DER and fingerprint. At initial provisioning, no application startup, repository, autosave, export or backup code called it. Milestone 4.2B composes it into protected writes; controlled synthetic qualification passed on one development-only Samsung tablet according to the operator report. Normal-editor acceptance and production deployment remain separate gates. No migration, automatic cloud backup or AWS configuration is activated; see [encrypted-storage review gates](MILESTONE_4_2B_ENCRYPTED_STORAGE.md). The expected fingerprint is pinned in source; it is not recomputed from an untrusted downloaded key as a substitute for authenticity. Future rotation requires an explicit reviewed configuration update.

The existing development public fixture and synthetic tests remain unchanged under `test/`. Production configuration does not import test fixtures or provide a fallback. Tests hash the actual configured public DER and compare it with the independently pinned ID, exercise the existing loader/channel contract and confirm a provisioning error propagates without trying a test key. Native RSA validation is performed by the existing Android loader; host tests mock that channel and do not claim a new device run.

Private recovery keys/passphrases, credentials and PHI are not configuration inputs and must never be bundled or committed. See the Milestone 4.2A document for private-key custody and independent recovery procedures. This public-key installation does not establish private-key custody or test access to the private key.

The pre-existing Share UI and native encryption-only test-runner diffs are preserved separately and excluded from the focused public-key provisioning commit. No push, tag or release is authorized.

Validation: `flutter analyze` passed with no issues; all 125 Flutter tests passed (123 existing plus two provisioning tests); `flutter build apk --debug` passed. Candidate source audit passed with 200 reviewed files and zero heuristic findings. Existing PDF Unicode and share_plus/Kotlin migration warnings remain nonfatal. Initial public-key provisioning did not install an application or perform private-key recovery; the subsequent synthetic validation is recorded below.

## Verified operational recovery test

The authorized Samsung tablet encrypted a synthetic-only ePCR with the production Android recovery-encryption service and the operational public key identified above. The resulting portable `PVFDBAK1` envelope had the expected key ID; the original fixture and encrypted artifact remained outside the source repository. This encryption-only test did not depend on local Android Keystore record keys or access existing ePCRs.

The operator subsequently reported independent macOS recovery using `tools/pvfd_recover.py` and the district-held private key:

- Byte-for-byte comparison: `cmp` exit code `0`.
- Original SHA-256: `bc3d8bbc0de5eec1c65542ff05bdab2c7819efd3bd43f58092657c381fc3ad40`.
- Recovered SHA-256: `bc3d8bbc0de5eec1c65542ff05bdab2c7819efd3bd43f58092657c381fc3ad40`.

Recovery and comparison are operator-verified results; the coding assistant did not access the private key, perform that decryption, or inspect the recovered file. No synthetic JSON, backup object, recovered plaintext, private-key material or passphrase is included in this commit. Production encryption, migration, automatic backups and AWS synchronization remain inactive.
