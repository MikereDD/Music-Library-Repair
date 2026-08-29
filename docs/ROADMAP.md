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

Next:

- inspect and validate the dev.9 ReplacementReview breakdown
- interactive replacement-candidate selection
- strict candidate decode
- duration/identity checks
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
