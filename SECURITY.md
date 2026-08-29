# Security and Data-Safety Policy

Music Library Repair operates on user-owned media files, so **data integrity is a security property**.

## Supported status

Music Library Repair is currently **pre-1.0**.

Current development baseline: **v0.7-dev.7.2**

## Reporting a problem

For security issues, destructive-behavior bugs, unsafe replacement behavior, path traversal, command injection, rollback failures, or any condition that could cause unintended media loss, report the issue privately before publishing exploit details.

Do not attach private runtime reports publicly without reviewing them first; reports may contain full local file paths.

## Data-safety expectations

A repair operation must never:

- re-encode healthy audio merely to change metadata
- overwrite an original before a staged result is built and verified
- silently approve known decoder failures
- silently guess ambiguous metadata, artwork, or releases
- silently downgrade or substitute a different release
- treat a successful metadata probe as proof that audio fully decodes
- classify malformed artwork as damaged audio without evidence
- replace a source file merely because FFmpeg emitted a warning
- discard rollback information before a verified operation completes

## Recommended use

Until v1.0:

1. Use `-BackupOriginals` for apply runs.
2. Keep an independent backup of the music library.
3. Review plans before approval.
4. Do not use `-SkipSourceDecodeAudit` for normal repair work.
5. Treat unexpected FFmpeg output as a review condition until understood.
6. Keep generated audit/state reports out of public repositories unless sanitized.

## Runtime data

Runtime reports may expose full local file paths, library structure, metadata, diagnostics, and replacement-candidate information. These files are intentionally ignored by Git.

## Replacement safety

```text
identify expected track
→ obtain candidate
→ strict-decode candidate
→ verify identity / duration / metadata
→ stage candidate
→ verify staged result
→ transactional swap
→ verify library result
→ retain rollback path
```

Ambiguous or unverifiable candidates must be rejected rather than guessed.
