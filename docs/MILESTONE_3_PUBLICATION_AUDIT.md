# Milestone 3 — local publication-readiness audit

Date: October 22, 2026 (America/Phoenix). Intended repository: `https://github.com/Shashaness/pvfd-epcr`. Planned release: `v0.1.0-alpha` (not tagged or released).

## Scope and repository decision

The repository root is the workspace directory `PVFDePCR/`. It contains the Flutter application in `pvfd_epcr/`, milestone/build documentation in `docs/`, root project/licensing policies and a local-only audit tool. No application directory restructuring was needed. All Flutter commands run from `pvfd_epcr/`.

No `.git` directory existed in this tree or an enclosing repository at initial inspection. Git was initialized locally on branch `main`. There was therefore no pre-existing commit history to audit or rewrite. Initial commit status and final index verification are recorded below; this document is included in that commit. No remote or tag has been configured, no GitHub repository created, and no code/APK uploaded. External lookups were limited to official documentation and a read-only query of the intended owner's public GitHub account ID (contact/profile fields were neither printed nor stored); local source was not sent to any scanner or service.

## Findings classification

BLOCKER means the condition must be resolved before the relevant publication step. WARNING requires review or is an operational limitation. INFORMATIONAL records acceptable, documented exclusions and evidence. No known PHI/credential/unknown-rights asset remains in the reviewed source inventory.

| Class | Finding | Disposition |
| --- | --- | --- |
| BLOCKER — external source publication | GitHub Private Vulnerability Reporting cannot be enabled/verified because the intended repository does not yet exist. | The user selected this preferred channel and explicitly authorized the initial **local** commit while retaining this mandatory gate before uploading public source. After separate approval, create an empty repository, enable/verify the reporting route, then publish only the audited source. Nothing external was created during this milestone. |
| BLOCKER — external actions | No approval to create a GitHub repository, configure a remote, push, upload an APK or publish a release/tag. | Stop after the local report and request explicit publication approval. |
| INFORMATIONAL — excluded asset | District insignia redistribution rights are unverified. The root asset's extension does not match its PNG format. | `assets/` is ignored and absent from the candidate/index. The unused logo remains intact locally; no UI/PDF change or asset replacement was needed. Inclusion would require separate permission. |
| INFORMATIONAL — excluded historical code | Three inactive alternate Dart entry points contain outdated/insecure persistence or unrelated scaffold behavior. | Ignore the three exact paths non-destructively; preserve them locally. Only `lib/main.dart` is supported in the public baseline. No hardcoded patient identity or credential was found in their reviewed contents. |
| INFORMATIONAL — excluded local state | IDE/SDK/generated files contain local machine paths and environment/build information. | Root and existing platform ignore rules exclude them. No values are copied into this report. |
| INFORMATIONAL — sanitized iOS account setting | The iOS project selected a concrete Apple development team. | Original preserved as ignored `pvfd_epcr/ios/Runner.xcodeproj/project.pbxproj.local`; team-selection lines removed from the public project. Android package/signing settings are unchanged. |
| INFORMATIONAL — synthetic fixtures | Phone-shaped strings occur in three fixture/input files. | Reviewed invented names/addresses/clinical text and nonworking contact placeholders. Coordinates/vitals/timestamps are synthetic scenario inputs, not patient records. Both required JSON/XML document fixtures remain eligible. |
| INFORMATIONAL — false positives | Email-like strings in iOS asset catalogs are image scale filenames. | Reviewed as catalog filenames, not operational/personal contacts. |
| WARNING — license scope | Direct package licenses and template origins were reviewed locally; this is not a complete legal/transitive/native binary-license audit. | Preserve upstream notices. Review all native/transitive/font obligations before binary distribution. |
| WARNING — existing development risks | No application-layer encryption/access controls/audit trail, no approved secure backup/retention, debug release signing, sharing-grant/cache risks and incomplete NEMSIS conformance remain. | Disclosed in README/SECURITY/build docs and historical audits. Source publication is not production approval. No signing/package/security redesign was made. |
| INFORMATIONAL — commit identity privacy | Inherited Git configuration was not a GitHub no-reply address. | Verified the intended public GitHub login/account ID and derived its ID-based GitHub no-reply identity, following the documented format. Repository-local Git identity uses the requested author name and this non-personal address; global configuration is unchanged. It is not a security contact. |

## Sensitive-file inspection

Initial whole-tree inventory: **6,086 files**, approximately **3.19 GB**, including **5,892 generated files**. Local scanning decoded **3,276 UTF-8 text files**. **2,780 binary files** and **30 files over 16 MiB** were inventoried rather than represented as fully decoded content inspections. These opaque/large build artifacts are excluded from source publication; the audit does not certify their contents or any tablet/device/cloud data.

Read-only filename/content checks covered operational JSON/PDF/XML names, temporary/reservation files, backups/databases, keystore/private-key extensions, private-key headers, common credential/token shapes, credential assignments, machine paths, email/phone-like text, generated caches/logs and included binary assets. Matches were reported by category/file only, with matched values suppressed. No real report files, signing keystores, private keys or credential-shaped values were identified in the reviewed source candidates. No suspicious file was deleted automatically.

Machine-path findings were in ignored local properties, IDE state, generated environment/plugin files and build/cache outputs. The few database/archive matches were generated build caches/symbol artifacts, not identified patient databases. No patient screenshots, extra bundled fonts or unknown non-icon binaries are included in the candidate. Excluded generated binaries are not a guarantee that no sensitive information exists elsewhere in the original workspace.

The full contents of source fixtures, the shared synthetic input, alternate entry points and relevant text/configuration were reviewed locally. Existing names/agency descriptions in source are intentional project/district references, not patient identities. Android source package IDs and app-private path examples are intentional, public technical configuration. No personal machine path was found in the retained milestone documents. No real device records, OneDrive documents or operational installations were inspected or modified.

`tools/audit_publication.py` provides a repeatable local candidate/index check. It has no network operations, uses Git's actual exclusions/index blobs, suppresses matched values, applies an explicit publication path allowlist and flags unreviewed JSON/binaries/exports, private key/token shapes and personal machine paths. It supplements human review; it does not prove absence of all PHI or secrets. Do not blindly widen its allowlist to bypass a finding.

## Exclusions and publication inventory

Root `.gitignore` supplements preserved Flutter/platform rules. Exclusions include Flutter/Dart/Gradle/Pods/ephemeral build state, plugin registrants, local properties/environment, IDE configuration, signing/private keys, operational record naming/data/backup directories, persistent/cache export naming, autosave/reservation files, logs/dumps/APKs, root branding assets and the three historical entry points. An ignored `.local` file preserves the original iOS team configuration. The nested application ignore file retains its existing rules and now allows a reviewed `.env.example` placeholder. No actual environment file is included.

Git ignore probes verified that local properties, signing configuration, real environment names, root district branding, all historical targets, build APKs, operational JSON, interrupted writes, reservations and both export-directory capitalizations are excluded. The synthetic XML/PDF-stream JSON fixtures and application lockfile are eligible. There is no blanket JSON/XML/PDF ignore rule; unexpected PDF files are rejected by the publication audit allowlist because no PDF source artifact has been reviewed for this baseline. No `git add -f` was used.

The exact reviewed filename allowlist is [PUBLICATION_INVENTORY.txt](PUBLICATION_INVENTORY.txt). It includes:

- Root MIT license, README, contribution/security policies, changelog, third-party notices and ignore rules.
- Existing milestone audits/architecture, new build/publication documentation and exact source inventory.
- Active layered Dart source and all 53 tests, test helpers and two reviewed synthetic document fixtures.
- Flutter dependency manifest/lockfile/project metadata and existing platform scaffold/build configuration.
- Standard Flutter platform icons and separate upstream Flutter license notice.
- The read-only/local publication audit script.

Generated Gradle wrapper scripts/JAR and plugin registrants are excluded as in Flutter scaffolding; required Android outputs are recreated by Flutter. Public source does not include the developer's debug keystore. The clean source validation below verifies that ignored local/generated files are not needed as source inputs.

## Licensing and included assets

`LICENSE` contains the standard MIT license with `Copyright (c) 2026 Shawn Bakhtiar`. No third-party terms were mixed into it. [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) distinguishes original code from upstream materials and records direct-package licenses. `third_party/FLUTTER_LICENSE` retains the local Flutter BSD-3-Clause notice for template-derived source/icons.

All 36 included binary image files are platform launcher/icon assets. Twelve matched SDK template files byte-for-byte; representative other generated Flutter icon variants were visually reviewed. The district insignia is separate, unused and excluded. No bundled extra font files were found. MIT licensing grants no right to official insignia or trademarks, and project description is not a district-endorsement claim.

Local direct-package license files were available for Flutter, flutter_lints, cupertino_icons, pdf, printing, xml, share_plus, path_provider, uuid and url_launcher. The SDK flutter_test package has no separate local LICENSE; the SDK license is retained/referenced. Reviewed license categories were BSD-3-Clause, MIT and Apache-2.0; no incompatible direct-package term was identified by this limited inspection. Transitive/native dependencies and binary redistribution remain a separate review scope.

## Documentation and versioning

Created: root README.md, LICENSE, CONTRIBUTING.md, SECURITY.md, CHANGELOG.md, THIRD_PARTY_NOTICES.md, docs/BUILDING.md, this audit, docs/PUBLICATION_INVENTORY.txt and third_party/FLUTTER_LICENSE. The application README now points to root instructions. Historical Milestone 1 and 2 documents were not rewritten. The repeatable audit helper is in tools/. The iOS public project omits account-specific team selection while an ignored local copy preserves the original; this is the only platform-source sanitation change.

`pvfd_epcr/pubspec.yaml` is prepared as `0.1.0-alpha+1`. The existing Android Gradle configuration reads Flutter's version name/code. Flutter's installed Android version-name validation accepts the prerelease string, and the built APK metadata is verified below. Build code `1` is an initial development value, not permission to downgrade any installed application. No application ID, signing identity, package configuration, public tag, release date or UI version label was changed.

README/build instructions distinguish Flutter 3.47.7/Dart 3.13.5 from declared minimums, confirm locally installed SDK Platform 36 and Build Tools 36.1.0, and document Flutter's API/NDK defaults and Gradle/Java needs. Build/install guidance explains app-private data loss on uninstall and warns against signing-mismatch/downgrade workarounds. No private reporting email was invented. SECURITY.md directs researchers to GitHub's Security tab / Report a vulnerability only after that channel is enabled and verified.

## Validation results

| Check | Result |
| --- | --- |
| Working source `flutter pub get` | PASS, existing package versions resolved. |
| Working source `flutter analyze` | PASS, no issues. |
| Working source `flutter test` | PASS, all 53 existing tests. |
| Working source `flutter build apk --debug` | PASS, version-prepared debug APK generated. |
| Fresh source-only export | PASS: `pub get`, clean analysis, all 53 tests and Android debug build from the 174-file index export. No local configuration, patient data, original build artifacts, historical targets or district logo copied. The final iOS sanitation/whitespace/document changes were refreshed into that export and a second final verification also passed all four commands. |
| Final candidate and index audit | PASS: 174 reviewed files (138 text files and 36 platform images), no heuristic findings, exact inventory/index match; ignored-path probes pass and no known PHI/secrets staged. |
| APK version metadata | PASS: package `com.pvfd3.pvfd_epcr`, versionName `0.1.0-alpha`, versionCode `1`, compile SDK 36. No application ID/signing change. |

No tablet installation, uninstall, clear-data, signing change or physical acceptance run was performed for Milestone 3. User-reported prior Samsung synthetic creation and PDF/XML export to OneDrive are acknowledged, not represented as newly performed validation. Existing PDF Helvetica Unicode warnings and share_plus Kotlin Gradle Plugin migration warnings remain nonfatal. The fresh Android build also reports obsolete Java 8 source/target warnings from dependencies; the build succeeds.

## Local Git completion status

Repository root: workspace `PVFDePCR/`; branch: `main`. No inherited history existed. All local audits passed. The initial local commit contains the exact 174-file reviewed inventory with message `Initial PVFD ePCR development baseline (v0.1.0-alpha)`. It uses repository-local GitHub no-reply author/committer metadata, not the inherited personal address. Its sole history is this initial commit, with no pre-existing history rewritten. Author/committer identity uses the verified intended account ID and GitHub's documented no-reply format; it is not an invented personal email or disclosure contact. No eligible untracked or modified files remain after completion; ignored local artifacts are deliberately retained. Commit identifier can be obtained with `git rev-parse HEAD` (not embedded self-referentially in its own commit). No remote, tag or public release is authorized or created. Ignored local artifacts remain preserved outside the index. A temporary pre-sanitization index blob may remain unreachable in local Git storage; it is not part of the committed/reachable history. Publish only the reviewed Git history, never an archive of the workspace or `.git` directory.

## Required publication sequence — stop for approval

1. Review this audit, the exact inventory and staged/committed metadata; resolve any new source/credential/rights finding before publication.
2. Obtain explicit approval for external GitHub repository creation and source publication. Local commit permission does not authorize those actions.
3. Following approval, create only the intended empty repository initially. GitHub documents Private Vulnerability Reporting for public repositories, so it must be enabled and verified on the approved empty repository **before uploading source**. See [GitHub maintainer configuration](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) and [researcher reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).
4. Confirm the form is available and reports reach maintainers; do not send PHI to test the route. Then, within the explicit approval scope, configure the remote and push only the reviewed source/history.
5. Treat tagging, a public release, binary uploads, signing/rollout and production use as separate decisions; none is performed in this milestone.

Local publication preparation is distinct from operational safety approval. All development security/standards limitations remain visible in the README/security policy and historical audits.
