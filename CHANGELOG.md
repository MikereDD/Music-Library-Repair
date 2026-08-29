# Changelog

All notable changes to Music Library Repair are tracked here.

The project is still pre-1.0. Behavior and state formats may evolve while the safety model is hardened.

## [Unreleased]

### Fixed
- `-ReclassifyFailureDomains` now bypasses normal ffprobe/ffmpeg preflight checks because it only reads existing CSV measurements
- Fixes silent pre-banner exit when running the report-only reclassification mode
- Preserve combined error evidence instead of letting `AUDIO` override simultaneous `CONTAINER` or `ARTWORK` evidence
- Combined domains now surface explicitly (`AUDIO+CONTAINER`, `AUDIO+ARTWORK`, `ARTWORK+CONTAINER`, or all three)
- Combined-domain dispositions default conservatively to `ManualReview`
- Wrapped mutually exclusive mode selection in an explicit array. Under strict mode, a single selected switch could collapse to a scalar Boolean and `.Count` raised before the startup banner.
- Corrected `-RecheckAuditFailures` mode dispatch; v0.7-dev.4 accidentally inserted the recheck call inside the mode-label expression, causing the command to return immediately instead of running the targeted audit.

### Added
- `-AnalyzeReplacementReview` report-only mode for the `ReplacementReview` subset
- `replacement-review-analysis.csv` with review priority, evidence assessment, completion band, signature, format, and track identity context
- `replacement-review-summary.csv` grouped by priority, evidence assessment, completion band, severity, signature, and extension
- Conservative review buckets that distinguish missing/very-low-completion files, substantial decoded loss, near-complete damaged files, and complete-or-nearly-complete severe diagnostics
- Replacement-review analysis reuses the existing repair queue and does not decode media or modify persistent state
- `-BuildRepairQueue` report-only mode
- `repair-action-queue.csv` generated from the newest available reclassified/full failure classification
- `repair-action-queue-summary.csv` grouped by action, queue status, primary domain, and severity
- Audit `tracks.csv` metadata enrichment for repair-queue rows when available
- Queue statuses for audio review, container review, artwork repair, replacement review, missing-file lookup, and manual review
- Explicit guarantee that `ReplacementReview` is non-destructive review state and does not authorize replacement
- `-ReclassifyFailureDomains` mode that reuses existing full-classification measurements without re-decoding audio
- Separate `PrimaryDomain` and `EvidenceDomain` fields
- Primary domain is derived from the canonical signature and drives disposition
- Evidence domain preserves every domain observed in FFmpeg diagnostics
- `failure-classification-reclassified.csv` and summary report
- `-ClassifyAuditFailures` full-library failure classification mode
- Classifies every row from `audio-only-recheck.csv` using the validated canonical signature, error-domain, audio-completion, severity, and disposition model
- `failure-classification.csv` with per-file results
- `failure-classification-summary.csv` with counts by action, domain, severity, and canonical signature
- Full classification remains read-only and does not change media or persistent repair state
- Canonical FFmpeg error signatures that remove volatile decoder addresses
- Independent error domains: `AUDIO`, `ARTWORK`, `CONTAINER`, `MIXED`, `UNKNOWN`
- Domain-aware failure dispositions: `RepairArtwork`, `ContainerReview`, `AudioReview`, `ManualReview`, `ReplacementReview`
- Severity now combines audio completion with error domain instead of treating all FFmpeg stderr equally
- `-AnalyzeFailureSeverity` diagnostic mode
- Configurable `-FailureSamplesPerSignature` sampling (default 5), spread across albums where possible
- Tolerant audio decode diagnostics comparing decoded progress with ffprobe-reported duration
- Diagnostic severity buckets: `DegradedButComplete`, `MostlyDecodable`, `DecodableWithErrors`, `Severe`, and `MissingFile`
- `failure-severity-samples.csv`
- `-RecheckAuditFailures` mode to retest only previously failed files instead of re-decoding the entire library
- `audio-only-recheck.csv` report
- Strict audio decode now disables video, subtitle, and data streams at both input and output so malformed attached artwork cannot be misclassified as source-audio corruption
- `-AnalyzeAuditReports` mode to classify an existing whole-library audit without re-decoding media
- Decode failures grouped by audio extension
- Normalized decoder-error signature report
- Per-album failure concentration classification: isolated, partial, mostly-album, or whole-album
- ffprobe vs strict-decode cross-check report
- Classification is also generated automatically at the end of future `-AuditOnly` runs
- Real `-AuditOnly` mode for non-interactive, read-only library-wide auditing
- Audit reports isolated under `Music-Library-Repair\audit` so an audit cannot overwrite an in-progress repair `state.json`
- Audit summary counts for album status, probe errors, strict decode failures, suspicious titles, and missing embedded artwork
- Persistent source-replacement queue stored in `state.json`
- `replacement-needed.csv` export for strict source decode failures
- First/last detection timestamps for replacement items
- Queue history is preserved when a previously failing path no longer fails
- Existing future replacement fields are preserved across rescans

### Planned
- Verified replacement candidate selection and strict candidate decode
- Duration/identity validation before staging
- Verified replacement staging and transactional swap
- Album re-audit after replacement
- Missing-track / track-gap detection
- MusicBrainz media breakdown instead of raw aggregate track count
- Better title verification against authoritative tracklists
- Better Cover Art Archive candidate retry flow
- Locked/in-use file preflight
- Already-applied/no-op detection
- FLAC and M4A apply support
- Metadata diff view
- Playlist handling
- Broader automated tests

## [0.6] - 2026-08-24

### Added
- First-class album artwork resolver
- Embedded artwork recovery
- MusicBrainz release search
- Exact-release Cover Art Archive lookup
- Cover cache and provenance
- `CoverReleaseId`
- `CoverSource`
- Explicit continue-without-cover state
- Cover validation/conversion to JPEG
- Persistent title overrides
- Interactive track-title review

### Safety
- Albums with source decode errors remain ineligible for approval/apply
- Apply verifies the rewritten output before completing replacement
- Missing cover must be resolved or explicitly acknowledged

### Validated
- Exact-release artwork lookup
- Embedded artwork recovery
- Clean partial apply when other albums in the same root contain bad source files
- 2-CD canonical naming

## [0.5]

### Added
- Exact bad-source filenames in review output
- Suspicious-title detection for likely 30-character ID3v1 truncation
- Interactive per-track title correction
- External artwork path support

## [0.4]

### Added
- Strict source decode pre-audit before review/apply
- `SOURCE ERROR` album status
- `source-decode-audit.csv`
- Approval blocking when source audio is damaged
- `-SkipSourceDecodeAudit` diagnostic override

### Changed
- Strict decode uses both FFmpeg error output and:
  - `-xerror`
  - `-err_detect explode`

## [0.3.2]

### Fixed
- Post-write verification no longer trusts FFmpeg exit code alone.
- Decoder error text now causes verification failure.

## [0.3.1]

### Fixed
- Apply mode automatically loads saved state.

## [0.3]

### Added
- First transactional MP3 apply path
- Stream-copy metadata/artwork rewrite
- Backup-original support
- Canonical `cover.jpg`
- Temporary build and verification before source replacement
- Apply report
- Rollback attempts on failure

## [0.2]

### Added
- Persistent interactive per-album planning
- Metadata editing
- Cover selection
- Plan preview
- Approval/review state

### Changed
- Removed naive artist-wide genre normalization.

## [0.1.2]

### Added
- Album readiness states
- Better metadata review notes

## [0.1.1]

### Fixed
- Artwork selector behavior.

## [0.1]

### Added
- Read-only recursive discovery
- Metadata audit
- Album grouping
- Rename planning
- CSV reports
- Persistent state/resume
