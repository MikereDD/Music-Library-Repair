# Music Library Repair

<p align="center">
  <img src="assets/Music-Library-Repair-logo.png" alt="Music Library Repair logo" width="220">
</p>

<p align="center">
  <strong>Typezer∅ Music Library Repair</strong><br>
  Safe, transactional music-library repair and normalization toolkit for Windows.
</p>

**Typezer∅ Music Library Repair** is a safety-first Windows/PowerShell toolkit for auditing, normalizing, repairing, and verifying music libraries without re-encoding healthy audio.

> Current development baseline: **v0.6**

The project grew out of real-world cleanup work against large, inconsistent music libraries. Its core rule is simple:

**Never turn a metadata problem into an audio problem.**

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

The repair engine is deliberately conservative. Ambiguous releases, damaged source audio, unresolved artwork, and suspicious metadata are surfaced for review rather than guessed away.

## Current capabilities

- Recursive discovery from an arbitrary library root
- Metadata inspection through `ffprobe`
- Strict source-audio decode audit using `ffmpeg -xerror -err_detect explode`
- Album-level interactive review
- Persistent state/resume
- Canonical filename planning
- Single-disc naming:
  - `01 - Artist - Title.ext`
- Multi-disc naming:
  - `1-01 - Artist - Title.ext`
- Metadata normalization
- Album-artist repair
- Suspicious 30-character title detection for likely ID3v1 truncation
- Per-track title overrides
- Loose artwork detection
- Embedded artwork recovery
- MusicBrainz release lookup
- Exact-release Cover Art Archive lookup
- Cover provenance stored in state
- Explicit unresolved/missing-cover handling
- Approval blocking when source decode errors exist
- Transactional MP3 rewrite/apply
- Audio stream-copy only; no audio re-encoding
- Backup-original option
- Post-write metadata/artwork/decode verification
- Apply report generation

## Important v0.6 limitation

**Apply mode is deliberately MP3-only.**

Discovery and auditing understand additional formats, but v0.6 will not rewrite non-MP3 albums. FLAC/M4A and broader apply support are roadmap items.

## Requirements

- Windows
- PowerShell 7+
- `ffmpeg`
- `ffprobe`
- Internet access only when using MusicBrainz / Cover Art Archive lookup

Verify the required executables are visible:

```powershell
Get-Command ffmpeg
Get-Command ffprobe
```

## Quick start

From the repository root:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music"
```

Resume an existing review:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -Resume
```

Apply only albums explicitly marked reviewed/approved:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyApproved `
    -BackupOriginals
```

The apply path requires explicit confirmation unless `-Yes` is supplied.

## Runtime data

By default, state, reports, cover cache, and backups are kept outside the repository under:

```text
$HOME\Downloads\Music-Library-Repair
```

Typical runtime output includes:

- `tracks.csv`
- `albums.csv`
- `rename-plan.csv`
- `source-decode-audit.csv`
- `apply-report.csv`
- `state.json`
- `cover-cache\`
- `Backups\`

These are intentionally ignored by Git.

## Strict decode helper

A standalone strict decoder is included:

```powershell
.\tools\Test-MusicLibraryDecodeStrict.ps1 `
    -Root "P:\Music"
```

It catches decoder failures that ordinary metadata probes can miss.

## Safety model

The project treats these as separate conditions:

- **Metadata problem** — file is healthy but tags/naming/artwork need repair.
- **Source decode error** — file exists but audio is damaged.
- **Missing track** — expected album content is absent.
- **Ambiguous release** — metadata/art cannot be safely inferred.

A source decode error blocks approval. The current file remains untouched until a verified replacement exists.

See [docs/safety-model.md](docs/safety-model.md).

## Project status

v0.6 has been exercised successfully against real multi-album collections, including:

- strict preflight detection of pre-existing damaged MP3s
- selective application to only approved clean albums
- 2-CD filename normalization
- embedded-cover recovery
- exact MusicBrainz + Cover Art Archive resolution
- post-write strict verification

The next major development target is a first-class **bad-source replacement queue/workflow**.

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository philosophy

This repository is the development home. A tagged v1.0 release will be produced from the same source after the repair engine has earned stable status through repeated real-world use and regression testing.

## License

MIT. See [LICENSE.md](LICENSE.md).
