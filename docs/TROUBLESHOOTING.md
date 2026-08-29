# Troubleshooting

## `ffmpeg` or `ffprobe` is not found

Confirm both commands work in the same PowerShell session:

```powershell
ffmpeg -version
ffprobe -version
```

## A track reports a decoder failure

Do not assume the audio must be replaced. Run the classification pipeline. Attached artwork, container damage, probe ambiguity, and actual decoded-audio damage are separate evidence domains.

## Candidate says `CandidateForcedDemuxerReview`

This is intentionally not treated as a normal clean candidate. Automatic probing failed, but a conservative extension-specific demuxer path produced usable probe/decode evidence. Review the identity and source provenance before approval.

## `QualityDowngradeRequiresExplicitApproval`

The candidate would change a known lossless source class into a known lossy replacement class. This is blocked unless the intake row explicitly sets `QualityDowngradeApproved=Yes`.

## `ReplacementTargetAlreadyExists`

A cross-extension target already exists. The tool refuses to overwrite it automatically.

## `StagedHashChanged`

The staged file no longer matches the hash recorded when staging was verified. Re-stage the candidate; do not force the transaction.

## File is locked or in use

Close software using the media file, including players/library scanners, then retry. The tool should never require killing unrelated processes or deleting a source manually.

## A repaired item still appears in an old audit report

Historical reports are not silently rewritten. Use `-VerifyReplacementTransactions` for current transaction state and run a fresh `-AuditOnly` for a new canonical whole-library snapshot.
