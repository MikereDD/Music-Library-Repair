# Music Library Repair

**Typezer∅ Music Library Repair** is a safety-first Windows/PowerShell toolkit for auditing, normalizing, repairing, and verifying music libraries without re-encoding healthy audio.

> Current development baseline: **v0.7-dev.7.2**

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

Run a non-interactive, read-only whole-library audit:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AuditOnly
```

`-AuditOnly` writes reports under `$HOME\Downloads\Music-Library-Repair\audit` and deliberately does **not** modify persistent repair/review state.


Analyze the most recent audit reports **without decoding the library again**:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeAuditReports
```

This produces failure classification reports by extension, decoder signature, album concentration, and ffprobe/decode cross-check.


Recheck only the files that failed the previous audit, using the hardened **audio-only** decode path:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -RecheckAuditFailures
```

This avoids another 41k-file pass while determining how many prior failures were caused by non-audio streams such as malformed embedded artwork. Results are written to `audit\audio-only-recheck.csv`.

Sample and characterize the remaining strict audio failures:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -AnalyzeFailureSeverity
```

The default is five samples per normalized decoder-error signature, spread across albums where possible. The diagnostic performs a tolerant audio decode and compares decoded progress with the reported duration. Increase sampling with `-FailureSamplesPerSignature 10`.


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
- `replacement-needed.csv`
- `decode-failures-by-extension.csv`
- `decode-error-signatures.csv`
- `decode-failures-by-album.csv`
- `audit-crosscheck.csv`
- `audio-only-recheck.csv`
- `failure-severity-samples.csv`
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

v0.7 development has started the first-class **bad-source replacement workflow**.

The first slice is now implemented: strict source decode failures are persisted in `state.json` and exported to `replacement-needed.csv` so damaged files cannot disappear from the work queue between runs. Candidate selection and transactional replacement are the next steps.

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository philosophy

This repository is the development home. A tagged v1.0 release will be produced from the same source after the repair engine has earned stable status through repeated real-world use and regression testing.

## License

MIT. See [LICENSE.md](LICENSE.md).


## v0.7-dev.6 failure-domain model

Failure diagnostics now normalize volatile FFmpeg decoder addresses and classify messages into independent domains: `AUDIO`, `ARTWORK`, `CONTAINER`, combined domains such as `AUDIO+CONTAINER`, and `UNKNOWN`.

Severity is based on actual audio completion plus the error domain. A malformed embedded PNG/JPEG that leaves audio complete is therefore an artwork-repair problem, not automatically a source-audio replacement.

`-AnalyzeFailureSeverity` now reports conservative dispositions such as `RepairArtwork`, `ContainerReview`, `AudioReview`, `ManualReview`, and `ReplacementReview`.


## v0.7-dev.7 full failure classification

After validating the domain/severity model with sampling, classify every file currently present in `audit\audio-only-recheck.csv`:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ClassifyAuditFailures
```

This does **not** rescan the full library and does not rerun the strict audit. It processes only the failures already identified by `-RecheckAuditFailures`, performs a tolerant audio decode for each one, then writes:

- `audit\failure-classification.csv`
- `audit\failure-classification-summary.csv`

No media files or persistent repair state are modified.


## v0.7-dev.7.1 primary vs evidence domain

The classifier now distinguishes the **primary domain** implied by the canonical signature from all domains observed in FFmpeg stderr.

Examples:

```text
Signature:      MP3 audio: header missing
PrimaryDomain:  AUDIO
EvidenceDomain: AUDIO+CONTAINER
```

```text
Signature:      Container: invalid input data
PrimaryDomain:  CONTAINER
EvidenceDomain: AUDIO+CONTAINER
```

Disposition uses `PrimaryDomain + decoded completion`, while `EvidenceDomain` is retained for diagnostics.

Reuse the existing full-classification measurements without decoding all failures again:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ReclassifyFailureDomains
```

This writes `failure-classification-reclassified.csv` and `failure-classification-reclassified-summary.csv`.


## v0.7-dev.7.2 preflight fix

`-ReclassifyFailureDomains` is a report-only mode and now bypasses normal ffprobe/ffmpeg preflight checks. It should start immediately, print the banner, and reuse the existing classification CSV without touching media.
