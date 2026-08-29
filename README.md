<p align="center">
  <img src="assets/Music-Library-Repair-logo.png" alt="Music Library Repair logo" width="240">
</p>

<h1 align="center">Music Library Repair</h1>

<p align="center">
  <strong>Typezer∅ Music Library Repair</strong><br>
  Safety-first auditing, normalization, repair, and verification for large Windows music libraries.
</p>

<p align="center">
  <a href="LICENSE.md"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform: Windows" src="https://img.shields.io/badge/platform-Windows-0078D4.svg">
  <img alt="PowerShell 7+" src="https://img.shields.io/badge/PowerShell-7%2B-5391FE.svg">
  <img alt="Development baseline" src="https://img.shields.io/badge/version-v0.7--rc.1.3-orange.svg">
  <img alt="Status: pre-1.0" src="https://img.shields.io/badge/status-pre--1.0-yellow.svg">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#safety-model">Safety model</a> ·
  <a href="#audit--diagnostics">Audit & diagnostics</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="SECURITY.md">Security</a>
</p>

---

**Music Library Repair** is a conservative Windows/PowerShell toolkit for discovering, auditing, normalizing, repairing, and verifying large music libraries without re-encoding healthy audio.

> **Never turn a metadata problem into an audio problem.**

The tool is built for real-world libraries where malformed tags, damaged frames, truncated titles, bad embedded artwork, ambiguous releases, inconsistent filenames, and genuinely corrupt source files can all exist side-by-side.

> Current development baseline: **v0.7-rc.1.3**

## Core workflow

```text
Discover
  → Strict source decode audit
  → Identify / Review
  → Preview / Plan
  → Approve
  → Apply transactionally
  → Verify again
```

Ambiguity is surfaced. Damaged source audio is blocked. Artwork errors stay artwork errors. Originals are not replaced until a staged result has been verified.

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
- Transactional MP3 rewrite/apply
- Stream-copy only for healthy audio — no audio re-encoding
- Optional original backups
- Post-write metadata, artwork, and strict-decode verification
- Failure-domain classification for audio, artwork, and container problems
- Report-only repair action queue generated from validated classification
- Replacement-review queue foundation for genuinely bad source media

## Canonical filenames

Single-disc releases:

```text
01 - Artist - Title.ext
```

Multi-disc releases:

```text
1-01 - Artist - Title.ext
```

## Requirements

- Windows
- PowerShell 7+
- `ffmpeg`
- `ffprobe`
- Internet access only for MusicBrainz / Cover Art Archive lookup

```powershell
Get-Command ffmpeg
Get-Command ffprobe
```

## Quick start

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music"
```

Resume:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -Resume
```

Apply reviewed and approved albums:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyApproved `
    -BackupOriginals
```

## Audit & diagnostics

Whole-library read-only audit:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AuditOnly
```

Analyze existing reports without decoding again:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeAuditReports
```

Recheck only previous strict failures:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -RecheckAuditFailures
```

Sample failure severity:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeFailureSeverity
```

Classify every known failure:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ClassifyAuditFailures
```

Reclassify existing measurements without decoding again:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ReclassifyFailureDomains
```

Build the report-only repair action queue from the newest available failure classification:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -BuildRepairQueue
```

`-BuildRepairQueue` writes:

```text
repair-action-queue.csv
repair-action-queue-summary.csv
```

It does not decode audio, modify media, or change persistent repair state. `ReplacementReview` is a review state only; it does **not** authorize replacement.

Analyze only the `ReplacementReview` subset:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeReplacementReview
```

This reads `repair-action-queue.csv` and writes `replacement-review-analysis.csv` plus `replacement-review-summary.csv`. It groups severe review items by decoded completion, signature, format, and evidence assessment without re-decoding audio.

Resolve the `NeedsMoreEvidence` subset with a targeted diagnostic pass:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeReplacementEvidence
```

This mode reads `replacement-review-analysis.csv`, targets only `NeedsMoreEvidence` items, attempts a fresh ffprobe duration read plus tolerant audio decode, and writes:

```text
replacement-evidence-analysis.csv
replacement-evidence-summary.csv
```

Possible evidence resolutions include `ConfirmedSevereAudioDamage`, `ContainerOrHeaderFailure`, `ProbeDurationUnavailable`, `AudioDecodesButDurationUnknown`, `UnreadableMediaSource`, `MissingSourcePath`, and `NeedsManualInspection`. Even a high-confidence result remains review-only and does not authorize replacement.

Create and review local replacement candidates:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ReviewReplacementCandidates
```

The first run creates `replacement-candidate-intake.csv` for high-confidence `UnreadableMediaSource` items. Add a local replacement file path to the `CandidatePath` column for any item you want to test, then rerun the same command.

Candidate validation checks that the file exists, is a supported audio format, is readable by ffprobe, passes the strict audio-decode gate, has a usable duration, and has plausible artist/album/track/title identity. Results are written to `replacement-candidate-validation.csv` and `replacement-candidate-summary.csv`.

`CandidateValidatedForReview` is deliberately not an approval state. It means the candidate is structurally clean and identity-plausible enough for human review; staging and replacement remain disabled.

If normal probing fails for a `.mp3`, dev.11.1 performs a conservative MP3-demuxer fallback. A candidate that passes forced MP3 probe and forced strict decode is labeled `CandidateForcedDemuxerReview`, never silently promoted to normal validation. The report preserves the normal-probe failure and the forced-probe/decode evidence.

Dev.12 reconstructs expected identity when damaged source tags are missing. It prefers source tags, then cautiously derives track/title/artist/disc from recognized filename patterns and album/artist/year from the directory layout. Validation reports record the provenance for each expected field (`SourceTag`, `FileName`, `ParentFolder`, or `GrandparentFolder`) so inferred identity is never presented as authoritative metadata.

Dev.13 adds explicit, non-destructive staging. Set `StageApproved` to `Yes` only after reviewing a candidate, then run:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -StageReplacementCandidates
```

Only `CandidateValidatedForReview` and `CandidateForcedDemuxerReview` are stage-eligible. The candidate is copied into the repair workspace under `staging/`, SHA-256 is checked before and after finalization, and the staged copy is strict-decoded again. `StagedVerified` still does not authorize replacement and the original library file is untouched.

Dev.14 adds the first transactional replacement commit. Replacement requires three explicit gates: `ReplaceApproved=Yes` in the candidate intake plus `-BackupOriginals` and `-Yes` on the command line.

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyStagedReplacements `
    -BackupOriginals `
    -Yes
```

Only `StagedVerified` items are eligible. Before commit, the current source is SHA-256 hashed, copied to `replacement-backups/`, and the backup hash must match. The staged file is re-hashed, copied into the source directory as a temporary file, and strict-decoded again. Same-extension replacements use `File.Replace`; cross-extension replacements are published under the correct extension and the damaged source is removed only after the new file passes hash and strict-decode verification. Any transaction failure triggers best-effort rollback from the verified backup. Backups are retained even after success.

Dev.14.1 adds a conservative quality-class gate before any replacement commit. The tool classifies only formats that are safe to infer from the extension: FLAC/WAV/AIFF/APE as lossless and MP3/AAC/Opus as lossy. Ambiguous containers such as M4A, OGG, WMA, and WV remain `Unknown` rather than being guessed.

A known lossless-to-lossy replacement is reported as `QualityDowngrade` and is blocked unless the candidate intake row also has `QualityDowngradeApproved=Yes`. This approval is separate from `ReplaceApproved` so a structurally valid replacement cannot silently reduce the library's quality class.

Dev.15 adds targeted post-replacement verification and album requalification. Successful replacement transactions are automatically checked again against the current filesystem, retained backup, SHA-256 hashes, and strict decode. The affected album folder is rescanned from disk and requalified with the same top-level statuses used by the main audit: `READY`, `NEEDS REVIEW`, `INCOMPLETE`, or `SOURCE ERROR`.

Existing committed transactions can also be rechecked without touching media:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -VerifyReplacementTransactions
```

`QueueStatus=ClearedByCurrentState` means the damaged source is gone when appropriate, the replacement exists, its current hash still matches the committed hash, and strict decode passes. This targeted verifier does not rewrite historical audit reports; a later full `-AuditOnly` remains the canonical whole-library snapshot.

### v0.7 release-candidate hardening

`v0.7-rc.1.3` includes the isolated synthetic regression harness:

```powershell
.\scripts\Test-ReleaseCandidate.ps1
```

It never points at the real music library. It builds temporary FLAC/MP3 fixtures and tests parser/version consistency, safe audit, downgrade refusal, verified backups, same- and cross-extension replacement, post-verification, queue clearance, and album requalification. See `docs/RELEASE-CHECKLIST.md`.

## Failure-domain model

The classifier separates the primary problem from all FFmpeg evidence.

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

Disposition is driven by **PrimaryDomain + decoded completion**, while secondary evidence remains available for diagnostics.

## Repair action queue

The report-only queue converts validated diagnostics into actionable review categories without treating every FFmpeg failure as a replacement case.

Current queue statuses include:

```text
PendingAudioReview
PendingContainerReview
PendingArtworkRepair
PendingReplacementReview
PendingLocateFile
PendingManualReview
```

When `audit\tracks.csv` is available, album and track metadata are joined back into queue rows so review can happen with useful identity context.

## Safety model

| Condition | Meaning | Default behavior |
|---|---|---|
| Metadata problem | Audio is healthy; tags/naming need repair | Safe to plan |
| Artwork problem | Cover data is malformed or missing | Repair artwork, preserve audio |
| Container problem | Wrapper/input structure needs review | Review before rewriting |
| Audio problem | Decoder reports audio-specific faults | Review severity |
| Replacement candidate | Audio cannot be trusted safely | Block and queue for review |
| Missing track | Expected album content is absent | Do not guess |
| Ambiguous release | Exact release cannot be identified safely | Require review |

See [docs/safety-model.md](docs/safety-model.md).

## Runtime data

Runtime state, reports, cover cache, and backups live under:

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

- Apply/rewrite mode is deliberately **MP3-only**.
- FLAC/M4A transactional apply support remains roadmap work.
- `-BuildRepairQueue` is report-only; candidate validation and replacement execution are not implemented yet.
- The source-replacement workflow is under active development.
- Pre-1.0 builds should be used with `-BackupOriginals` and an independent library backup.

## Project status

The v0.6 engine established the safe transactional repair foundation.

The v0.7 development branch now includes replacement-needed persistence, read-only whole-library auditing, targeted failure rechecks, canonical FFmpeg signatures, primary vs evidence domains, tolerant decode severity measurement, full failure classification, report-only reclassification, a report-only repair action queue, a focused read-only analyzer for `ReplacementReview` items, a targeted diagnostic pass for unresolved replacement evidence, and non-destructive local candidate intake/validation.

The next major step is verified replacement candidate selection, strict candidate validation, staging, transactional swap, rollback, and album re-audit.

See [docs/ROADMAP.md](docs/ROADMAP.md) and [CHANGELOG.md](CHANGELOG.md).

## Repository philosophy

A tagged v1.0 release will be cut only after the repair engine has earned stable status through repeated real-world use, regression testing, safe rollback behavior, and verified handling of damaged media.

Precision, safety, and recoverability take priority over speed.

## License

Released under the **MIT License**.

Copyright © 2026 **Typezer∅**.

See [LICENSE.md](LICENSE.md).
