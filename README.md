<p align="center">
  <img src="assets/Music-Library-Repair-logo.png" alt="Music Library Repair logo" width="240">
</p>

<h1 align="center">Music Library Repair</h1>

<p align="center">
  <strong>Typezer∅ Music Library Repair</strong><br>
  Safety-first auditing, normalization, repair, replacement, and verification for large Windows music libraries.
</p>

<p align="center">
  <a href="LICENSE.md"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform: Windows" src="https://img.shields.io/badge/platform-Windows-0078D4.svg">
  <img alt="PowerShell 7+" src="https://img.shields.io/badge/PowerShell-7%2B-5391FE.svg">
  <img alt="Version: v0.7" src="https://img.shields.io/badge/version-v0.7-brightgreen.svg">
  <img alt="Status: stable pre-1.0" src="https://img.shields.io/badge/status-stable%20pre--1.0-green.svg">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#audit-and-classification">Audit</a> ·
  <a href="#replacement-workflow">Replacement</a> ·
  <a href="#safety-model">Safety</a> ·
  <a href="#documentation">Documentation</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

**Music Library Repair** is a conservative Windows/PowerShell toolkit for discovering, auditing, normalizing, repairing, replacing, and verifying music-library files without re-encoding healthy audio.

> **Never turn a metadata problem into an audio problem.**

The tool is built for real-world libraries where malformed tags, damaged frames, truncated titles, bad embedded artwork, ambiguous releases, inconsistent filenames, container faults, and genuinely corrupt source files can all exist side-by-side.

**Current stable release: v0.7**

## Core workflow

```text
Discover
  → Audit
  → Classify
  → Identify / Review
  → Preview / Plan
  → Approve
  → Apply transactionally
  → Verify again
```

Ambiguity is surfaced instead of guessed. Raw decoder errors are treated as evidence, not automatic replacement instructions. Artwork errors stay artwork errors. Originals are not replaced until a candidate has been reviewed, staged, verified, explicitly approved, backed up, and verified again during the transaction.

## Highlights

- Recursive discovery from any library root
- Metadata inspection with `ffprobe`
- Strict full-audio decode auditing with `ffmpeg`
- Read-only whole-library audit mode
- Album-level interactive review
- Persistent state/resume
- Canonical filename planning
- Metadata and album-artist normalization
- Suspicious/truncated-title detection
- Per-track title overrides
- Loose and embedded artwork inspection
- Embedded artwork recovery
- MusicBrainz release lookup
- Exact-release Cover Art Archive lookup
- Cover provenance tracking
- Stream-copy metadata/artwork rewriting for healthy MP3 audio
- Optional original backups
- Post-write metadata, artwork, and strict-decode verification
- Failure-domain classification for audio, artwork, and container problems
- Classification-aware repair action queue
- Replacement evidence analysis
- Conservative identity reconstruction
- Local candidate intake and validation
- Forced-demuxer review when normal MP3 probing fails
- Explicit non-destructive staging
- SHA-256 verification before and after staging
- Transactional same-extension replacement
- Transactional cross-extension replacement
- Lossless-to-lossy downgrade protection
- Best-effort rollback from a verified backup
- Post-replacement verification and affected-album requalification
- Synthetic release-gate regression testing

## Canonical filenames

Single-disc releases:

```text
01 - Artist - Title.ext
```

Multi-disc releases:

```text
1-01 - Artist - Title.ext
```

Windows-invalid filename characters are sanitized only in filenames; authoritative punctuation remains in embedded metadata.

## Requirements

- Windows
- PowerShell 7+
- `ffmpeg`
- `ffprobe`
- Internet access only for MusicBrainz / Cover Art Archive lookup

Check dependencies:

```powershell
Get-Command ffmpeg
Get-Command ffprobe
```

Built-in help:

```powershell
Get-Help .\src\Repair-MusicLibrary.ps1 -Full
```

## Quick start

Interactive review:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music"
```

Resume a previous review:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -Resume
```

Apply previously reviewed and approved metadata/artwork plans:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyApproved `
    -BackupOriginals
```

## Audit and classification

Run a whole-library read-only audit:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AuditOnly
```

A strict decoder failure is recorded as an observation in:

```text
source-decode-observations.csv
```

That report is evidence only. It does **not** authorize replacement.

Analyze and classify existing audit evidence:

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeAuditReports
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -RecheckAuditFailures
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeFailureSeverity
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -ClassifyAuditFailures
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -ReclassifyFailureDomains
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -BuildRepairQueue
```

The classification-aware queue is written to:

```text
repair-action-queue.csv
repair-action-queue-summary.csv
```

Current action states include:

```text
PendingAudioReview
PendingContainerReview
PendingArtworkRepair
PendingReplacementReview
PendingLocateFile
PendingManualReview
```

`ReplacementReview` means **review this source for possible replacement**. It is not an approval state.

## Failure-domain model

The classifier separates the primary problem from all observed evidence.

```text
PrimaryDomain
  AUDIO
  ARTWORK
  CONTAINER
  UNKNOWN

EvidenceDomain
  AUDIO
  ARTWORK
  CONTAINER
  AUDIO+CONTAINER
  AUDIO+ARTWORK
  ARTWORK+CONTAINER
  ...
```

Disposition is driven by **PrimaryDomain + decoded completion**, while broader evidence remains available for diagnostics.

## Replacement workflow

Analyze only the items classified for replacement review:

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeReplacementReview
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeReplacementEvidence
```

Create or refresh local candidate intake and validation:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ReviewReplacementCandidates
```

Candidate validation checks structural readability, strict decode, duration, and plausible artist/album/track/title identity. When damaged source tags are unavailable, expected identity can be reconstructed conservatively from source tags, recognized filename patterns, parent album folders, and grandparent artist folders. The report records the provenance of each reconstructed field.

A candidate that normal probing cannot read but a conservative forced MP3 demuxer can verify is labeled:

```text
CandidateForcedDemuxerReview
```

That remains a review state rather than silently becoming a normal clean validation.

### Stage an approved candidate

Set `StageApproved=Yes` in `replacement-candidate-intake.csv`, then run:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -StageReplacementCandidates
```

Staging copies the candidate into the repair workspace, verifies SHA-256, and strict-decodes the staged copy. `StagedVerified` still does **not** replace the source.

### Apply a staged replacement

Replacement requires all of the following:

- `ReplaceApproved=Yes` in `replacement-candidate-intake.csv`
- a `StagedVerified` candidate
- `-BackupOriginals`
- `-Yes`
- `QualityDowngradeApproved=Yes` when a known lossless source would be replaced by a known lossy candidate

Run:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyStagedReplacements `
    -BackupOriginals `
    -Yes
```

Before commit, the source is SHA-256 hashed, copied to `replacement-backups`, and the backup hash must match. The staged candidate is re-hashed and strict-decoded before it is allowed to replace anything.

Same-extension replacements use a transactional replace path. Cross-extension replacements publish and verify the new target before the damaged source is removed. Transaction failures trigger best-effort rollback from the verified backup. Successful backups are retained for manual recovery.

### Quality downgrade gate

Known extension classes are treated conservatively:

```text
Lossless: FLAC, WAV, AIFF/AIF, APE
Lossy:    MP3, AAC, Opus
Unknown:  ambiguous containers remain Unknown rather than guessed
```

A known lossless-to-lossy replacement is blocked unless `QualityDowngradeApproved=Yes` is explicitly recorded in the candidate intake.

### Verify committed replacements

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -VerifyReplacementTransactions
```

Post-verification is read-only. It checks the current replacement hash/decode state, retained backup integrity, source disposition, queue clearance, and affected-album qualification.

`QueueStatus=ClearedByCurrentState` means the current filesystem state satisfies the committed replacement transaction. Historical audit reports are intentionally not rewritten; run a fresh `-AuditOnly` when a new whole-library snapshot is wanted.

## Safety model

| Condition | Meaning | Default behavior |
|---|---|---|
| Metadata problem | Audio is healthy; tags/naming need repair | Safe to plan |
| Artwork problem | Cover data is malformed or missing | Repair artwork, preserve audio |
| Container problem | Wrapper/input structure needs review | Review before rewriting |
| Audio problem | Decoder reports audio-specific faults | Measure and classify |
| Replacement review | Source cannot yet be trusted safely | Review; do not replace automatically |
| Missing track | Expected album content is absent | Do not guess |
| Ambiguous release | Exact release cannot be identified safely | Require review |

Key rule:

> **Decoder observation ≠ replacement authorization.**

The action queue, candidate review, explicit approval flags, verified staging, backup verification, and transaction gates are separate layers by design.

See [docs/safety-model.md](docs/safety-model.md).

## Release gate

The repository includes an isolated synthetic regression harness:

```powershell
.\scripts\Test-ReleaseCandidate.ps1
```

The v0.7 release gate exercises parser/version consistency, authored PowerShell help, read-only auditing, observation-vs-authorization semantics, quality-downgrade refusal, missing-stage refusal, changed-stage-hash refusal, existing-target refusal, verified backups, same-extension replacement, cross-extension FLAC→MP3 replacement, post-verification, queue clearance, and cleanup of transaction temporary files.

The harness operates only inside a temporary workspace and does not point at the real music library.

## Runtime data

Runtime state, reports, staging data, cover cache, and replacement backups live beneath:

```text
$HOME\Downloads\Music-Library-Repair
```

Generated reports may contain local paths and are intentionally excluded from version control.

## Strict decode helper

```powershell
.\tools\Test-MusicLibraryDecodeStrict.ps1 `
    -Root "P:\Music"
```

## Current limitations

- The legacy metadata/artwork rewrite/apply path remains deliberately MP3-focused.
- The v0.7 replacement transaction path is verified for same-extension replacement and the tested FLAC→MP3 cross-extension path; other format combinations should be treated conservatively and verified before broad use.
- Playlist path rewriting (`.m3u`) is not automatic in v0.7 and is deferred to a later release.
- Replacement-source acquisition is not automated; candidates are supplied locally and reviewed explicitly.
- Ambiguous releases are never guessed.
- Audiobook workflows are future shared-engine work and are not part of v0.7.
- Pre-1.0 use should still include an independent library backup in addition to the tool's transactional backups.

## Project status

**v0.7 is the current stable pre-1.0 release.**

It establishes the unified repair engine for whole-library audit, failure classification, repair-action routing, replacement evidence analysis, local candidate validation, conservative identity reconstruction, verified staging, transactional replacement, rollback, quality-downgrade protection, post-replacement verification, and synthetic release-gate testing.

Future work can now build on this stable baseline instead of maintaining parallel audit and repair rule sets.

See [docs/ROADMAP.md](docs/ROADMAP.md), [docs/RELEASE-NOTES-0.7.md](docs/RELEASE-NOTES-0.7.md), and [CHANGELOG.md](CHANGELOG.md).

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — complete command workflow and examples
- [`docs/REPORTS.md`](docs/REPORTS.md) — report meanings and evidence/action separation
- [`docs/architecture.md`](docs/architecture.md) — architecture and repair-engine design
- [`docs/RECOVERY.md`](docs/RECOVERY.md) — backup, rollback, and recovery behavior
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — common diagnostics and safe responses
- [`docs/RELEASE-CHECKLIST.md`](docs/RELEASE-CHECKLIST.md) — stable-promotion gate
- [`docs/RELEASE-NOTES-0.7.md`](docs/RELEASE-NOTES-0.7.md) — v0.7 milestone scope
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — future development
- [`CHANGELOG.md`](CHANGELOG.md) — version history
- [`SECURITY.md`](SECURITY.md) — security guidance

PowerShell help is embedded directly in the main script:

```powershell
Get-Help .\src\Repair-MusicLibrary.ps1 -Full
```

## Repository philosophy

A tagged v1.0 release will be cut only after the repair engine has earned that milestone through continued real-world use, regression testing, safe rollback behavior, and verified handling of damaged media.

Precision, safety, recoverability, and truthful diagnostics take priority over speed.

## License

Released under the **MIT License**.

Copyright © 2026 **Typezer∅**.

See [LICENSE.md](LICENSE.md).
