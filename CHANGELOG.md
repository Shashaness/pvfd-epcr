# Changelog

## Unreleased — planned 0.1.0-alpha

Initial experimental development baseline; no release date or public tag has been assigned.

### Added

- Offline local ePCR creation, listing and editing; incident/patient fields, responders, PMH, allergies, medications, GCS, vitals and clinical narratives.
- Forest Land/GPS and additional-contact/form-completion fields.
- PDF generation/printing, NEMSIS-oriented XML, Android sharing and external Maps lookup.
- Milestone 1 PMH compatibility, atomic replacement, ordered saves, secure randomized IDs, lossless/defensive JSON handling, lifecycle flushing and Android backup/cleartext hardening.
- Milestone 2 domain, repository/storage, controller, presentation and document/integration layers.
- 53 synthetic automated regression tests and Android debug-build validation.
- MIT licensing, contribution/security/build documentation and reviewed source-publication exclusions.

### Known limitations

- Experimental software; not a certified production EMS records system or verified HIPAA/NEMSIS-compliant application.
- Application-layer encryption, access controls, audit trails, secure backup/retention and production signing remain unfinished.
- NEMSIS UUID/identity/mapping issues and complete official XSD/Schematron validation remain future work.
- GitHub Private Vulnerability Reporting must be enabled and verified before public source publication.
