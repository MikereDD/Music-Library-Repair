# Roadmap

## v0.7 target — Source Replacement

Implemented in `v0.7-dev.1`:

- export `replacement-needed.csv`
- persistent replacement items/status in state
- first/last detection timestamps
- queue history preservation across rescans

Implemented in `v0.7-dev.8`:

- report-only `-BuildRepairQueue`
- actionable `repair-action-queue.csv`
- `repair-action-queue-summary.csv`
- queue grouping by disposition, status, primary domain, and severity
- metadata enrichment from the existing audit track report
- explicit non-destructive `ReplacementReview` state

Implemented in `v0.7-dev.9`:

- report-only `-AnalyzeReplacementReview`
- replacement-review evidence/completion breakdown
- priority bands for severe review items
- signature/format/album identity context before candidate sourcing

Implemented in `v0.7-dev.10`:

- targeted `-AnalyzeReplacementEvidence` pass for `NeedsMoreEvidence`
- fresh ffprobe duration evidence only for unresolved review items
- tolerant diagnostic decode only for unresolved review items
- evidence-resolution and confidence reports before candidate sourcing
- dev.10.1 distinguishes missing paths from present-but-unreadable media sources

Implemented in `v0.7-dev.11`:

- non-destructive `-ReviewReplacementCandidates`
- persistent CSV intake for local candidate paths
- ffprobe readability validation
- strict candidate decode validation
- candidate duration readability check
- conservative expected-vs-candidate identity scoring and conflict detection
- validated-for-review status without staging or replacement authority
- dev.11.1 conservative forced-MP3 demuxer fallback with explicit review-only status when automatic probing misdetects a candidate

Implemented in `v0.7-dev.12`:

- expected-identity reconstruction when source tags are missing
- provenance for inferred identity fields
- filename-based track/title/artist/disc recovery
- parent-folder album/year inference
- grandparent-folder artist inference
- candidate comparison against reconstructed identity without granting replacement authority

Implemented in `v0.7-dev.13`:

- explicit per-candidate `StageApproved` gate
- non-destructive workspace staging
- SHA-256 copy verification
- strict decode verification of staged media
- forced-demuxer preservation during staged verification
- staging manifest and summary reports
- no original-library or persistent-state mutation

Next:

- exercise dev.11 candidate intake against known clean local replacement files
- improve authoritative duration/identity verification where source duration is unavailable
- interactive/assisted candidate discovery
- transactional replacement
- album re-audit after replacement
- preserve unresolved items across runs

## Near-term

- [x] non-interactive `-AuditOnly` whole-library reporting mode
- [x] classify strict-decode failures by extension and error signature
- [x] classify failure concentration by album
- [x] ffprobe/strict-decode cross-check reporting
- [x] analyze existing audit reports without re-decoding media
- [x] isolate strict source-audio decode from attached artwork/non-audio streams
- [x] targeted recheck of previous audit failures
- [x] sampled failure-severity diagnostics before replacement decisions
- [x] canonicalize volatile FFmpeg decoder signatures
- [x] separate audio, artwork, container, mixed, and unknown error domains
- [x] domain-aware severity/disposition model
- [x] preserve combined error-domain evidence without precedence loss
- [x] classify all known strict-audit failures with the validated disposition model
- [x] separate primary failure domain from secondary evidence domains
- [x] reclassify existing full-audit measurements without repeat decoding
- [x] make report-only reclassification independent of ffmpeg/ffprobe preflight
- [x] build a report-only actionable repair queue from validated classification
- missing-track / track-number gap detector
- disc-aware gap detection
- authoritative MusicBrainz tracklist comparison
- MusicBrainz media breakdown
  - distinguish 2×CD audio from 2×CD + DVD aggregate counts
- better exact-release scoring
- retry another Cover Art Archive candidate without leaving resolver
- locked/in-use file preflight
- metadata diff preview
- no-op/already-applied detection
- avoid unnecessary rewrites

## Format expansion

- FLAC apply
- M4A/MP4 apply
- format-specific artwork/tag verification
- preserve codec/container-native metadata correctly

## Library integration

- stale `.m3u` detection/update
- optional `.nfo` preservation
- folder-art canonicalization
- cleanup of superseded artwork only after verification

## Automation modes

All modes must use the same safety engine.

- Interactive
- AutoHighConfidence
- Nuclear

Nuclear means broad repair, not guessing.

## Testing

- Pester test harness
- generated synthetic audio fixtures
- intentional corrupt fixtures
- filename sanitization cases
- disc-numbering cases
- cover/no-cover cases
- state migration tests
- transaction rollback tests
- locked-file tests
- regression tests for every real-world bug found during development

## v1.0 gate

v1.0 should not be tagged until:

- source integrity gates are stable
- transactional replacement is proven
- rollback is tested
- common MP3/FLAC/M4A paths are supported
- repeated apply is safe/idempotent enough
- state migration is defined
- destructive edge cases are covered by tests
- documentation matches actual behavior
