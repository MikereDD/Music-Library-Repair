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
  <img alt="Development baseline" src="https://img.shields.io/badge/version-v0.7--dev.7.2-orange.svg">
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

> Current development baseline: **v0.7-dev.7.2**

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

## Safety model

| Condition | Meaning | Default behavior |
|---|---|---|
| Metadata problem | Audio is healthy; tags/naming need repair | Safe to plan |
| Artwork problem | Cover data is malformed or missing | Repair artwork, preserve audio |
| Container problem | Wrapper/input structure needs review | Review before rewriting |
| Audio problem | Decoder reports audio-specific faults | Review severity |
| Replacement candidate | Audio cannot be trusted safely | Block and queue |
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
- The source-replacement workflow is under active development.
- Pre-1.0 builds should be used with `-BackupOriginals` and an independent library backup.

## Project status

The v0.6 engine established the safe transactional repair foundation.

The v0.7 development branch now includes replacement-needed persistence, read-only whole-library auditing, targeted failure rechecks, canonical FFmpeg signatures, primary vs evidence domains, tolerant decode severity measurement, full failure classification, and report-only reclassification.

The next major step is verified replacement candidate selection, staging, transactional swap, rollback, and album re-audit.

See [docs/ROADMAP.md](docs/ROADMAP.md) and [CHANGELOG.md](CHANGELOG.md).

## Repository philosophy

A tagged v1.0 release will be cut only after the repair engine has earned stable status through repeated real-world use, regression testing, safe rollback behavior, and verified handling of damaged media.

Precision, safety, and recoverability take priority over speed.

## License

Released under the **MIT License**.

Copyright © 2026 **Typezer∅**.

See [LICENSE.md](LICENSE.md).
