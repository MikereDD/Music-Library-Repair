# Roadmap

## v0.7 target — Source Replacement

Priority:

- export `replacement-needed.csv`
- persistent replacement status in state
- interactive replacement-candidate selection
- strict candidate decode
- duration/identity checks
- transactional replacement
- album re-audit after replacement
- preserve unresolved items across runs

## Near-term

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
