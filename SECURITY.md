# Security policy

## Supported development version

The current planned development line is **0.1.0-alpha**. It is unreleased and experimental, with no production security-support SLA. Historical alternate entry points are unsupported and excluded from publication.

## Preferred channel: GitHub Private Vulnerability Reporting

After the intended `Shashaness/pvfd-epcr` repository is created **and reporting is enabled**, sign in to GitHub, open the repository's **Security** tab and select **Report a vulnerability**. Use that private form to contact maintainers. Follow [GitHub's researcher instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

**Mandatory publication prerequisite:** the repository does not exist yet, so this channel is not currently available or verified. Before uploading public source, the maintainer must enable GitHub Private Vulnerability Reporting and verify that the private reporting form is available and reaches maintainers. Local preparation/commit is authorized; repository creation, remote configuration and pushing still require explicit approval. No personal email address is published or implied as a fallback.

GitHub documents this feature for public repositories. After explicit approval, an empty public repository may need to be created to enable and verify the channel **before any source push**. Do not interpret this policy as authorization to create that repository now. See [GitHub's maintainer configuration instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).

Do not post vulnerability details publicly before maintainers have an opportunity to review them. If the private reporting form is unavailable, do not put exploit details, records or credentials in a public issue, pull request, discussion or attachment. Ask only for the reporting route without including sensitive details, and wait for an available private channel.

Use synthetic reproduction data and describe the affected version, platform, impact and minimal reproduction steps. Do not transmit patient data through the reporting form; agree on a protected investigation process if clinical evidence is necessary. Maintainers should coordinate disclosure privately; no response deadline or SLA is promised.

## Security-sensitive issues

Examples include unintended access to ePCR files or exports, record corruption/data loss, path traversal, excessive URI grants, backup leakage, logging of clinical information, signing/update weaknesses, dependency vulnerabilities and clinical field changes caused by malformed input.

Public issues are not an appropriate place to upload patient records, ePCR JSON, PDF/XML exports, device backups, identifying screenshots, access tokens or signing keys. Use entirely invented examples and sanitized diagnostics.

## Current limitations

Milestone 4.2B implements encrypted-only local records and app-private recovery staging. Controlled synthetic qualification on one development-only Samsung tablet passed according to the operator report; normal-editor acceptance and production deployment remain pending. Process termination and simulated ENOSPC do not prove hardware power-loss durability or real full-volume behavior. No plaintext migration is implemented. PDF/XML exports remain plaintext. See [the storage design and review gates](docs/MILESTONE_4_2B_ENCRYPTED_STORAGE.md). Authentication, authorization, clinical audit trails, protected backup/recovery and secure retention need reviewed designs. Release signing remains configured with debug keys. Native recipients can retain copies; sharing grants and cached export retention need further work. OS termination can prevent uncommitted edits from saving. NEMSIS mappings/identity semantics are not fully validated.

App-private storage and backup exclusions do not establish HIPAA compliance. This development application must not be deployed for actual patient information without an appropriate security and operational review. See the historical [Milestone 1 audit](docs/MILESTONE_1_AUDIT.md), [architecture](docs/MILESTONE_2_ARCHITECTURE.md) and current [publication audit](docs/MILESTONE_3_PUBLICATION_AUDIT.md).
