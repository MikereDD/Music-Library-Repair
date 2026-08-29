# Usage Guide

Music-Library-Repair follows one workflow:

`Discover -> Audit -> Classify -> Review -> Plan -> Approve -> Apply -> Verify`

## Requirements

- Windows PowerShell 7+
- `ffmpeg` and `ffprobe` available on `PATH`
- A local music-library root
- Write access to the state/report directory

The default state directory is:

```text
$HOME\Downloads\Music-Library-Repair
```

## Start with a non-destructive audit

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AuditOnly
```

A strict decoder failure is **evidence**, not replacement authorization. The audit writes `source-decode-observations.csv`; its rows are explicitly marked `ObservationOnly=True` and `ReplacementAuthorized=False`.

## Classification workflow

After a whole-library audit:

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeAuditReports
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeFailureSeverity
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -ClassifyAuditFailures
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -ReclassifyFailureDomains
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -BuildRepairQueue
```

`repair-action-queue.csv` is the action-oriented queue. `ReplacementReview` is only a recommendation to review the source; it is not permission to replace it.

## Replacement workflow

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeReplacementReview
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -AnalyzeReplacementEvidence
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -ReviewReplacementCandidates
```

Edit `replacement-candidate-intake.csv` only after reviewing the expected identity and candidate evidence.

To stage an approved candidate:

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -StageReplacementCandidates
```

Staging does not replace source media.

To commit an explicitly approved staged replacement:

```powershell
.\src\Repair-MusicLibrary.ps1 `
    -Root "P:\Music" `
    -ApplyStagedReplacements `
    -BackupOriginals `
    -Yes
```

The corresponding intake row must also have `ReplaceApproved=Yes`. A known lossless-to-lossy replacement additionally requires `QualityDowngradeApproved=Yes`.

## Post-replacement verification

```powershell
.\src\Repair-MusicLibrary.ps1 -Root "P:\Music" -VerifyReplacementTransactions
```

Verification is read-only. It checks current replacement hash/decode state, backup integrity, source disposition, queue clearance, and affected-album qualification.

## Built-in help

```powershell
Get-Help .\src\Repair-MusicLibrary.ps1 -Full
```

## What v0.7 intentionally does not do

Playlist rewriting (`.m3u`) is deferred to a later release. v0.7 does not silently edit playlists when a file extension/path changes.

Audiobook support is also a later shared-engine milestone rather than part of the v0.7 stable music workflow.
