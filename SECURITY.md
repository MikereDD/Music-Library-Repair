# Security and Data-Safety Policy

Music Library Repair operates on user-owned media files and therefore treats data integrity as a security property.

## Supported status

The project is pre-1.0. The current baseline is v0.6.

## Report a problem

For security issues, destructive-behavior bugs, unsafe replacement behavior, path traversal, command injection, or a condition that could cause unintended media loss, open a private Forgejo issue or contact the maintainer privately before publishing exploit details.

## Data-safety expectations

A repair operation should never:

- re-encode healthy audio merely to change metadata
- overwrite an original before the staged replacement is built and verified
- approve known decoder failures
- silently guess ambiguous metadata or artwork
- silently downgrade or substitute a different release
- treat a successful metadata probe as proof that audio fully decodes

## Recommended use

Until v1.0:

1. Use `-BackupOriginals` for apply runs.
2. Keep an independent library backup.
3. Review the plan before approval.
4. Do not use `-SkipSourceDecodeAudit` for normal repair work.
5. Treat unexpected FFmpeg output as a failure until understood.

## Sensitive data

Runtime reports may contain full local file paths. Do not publish state/report files without reviewing them first.
