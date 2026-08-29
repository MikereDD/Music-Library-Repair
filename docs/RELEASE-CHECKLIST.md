# v0.7 Release Checklist

Run the isolated RC harness from the repository root:

```powershell
.\scripts\Test-ReleaseCandidate.ps1
```

Required ending:

```text
RC RESULT: PASS
Real library touched: NO
```

The harness creates synthetic FLAC/MP3 fixtures only under a unique temporary directory and exercises parser/version checks, `AuditOnly`, strict decode reporting, downgrade refusal, verified backups, same-extension replacement, cross-extension replacement, post-verification, queue clearance, and album requalification.

Before stable:

1. RC harness passes.
2. Main script parses with zero PowerShell errors.
3. README and CHANGELOG describe all replacement safety gates.
4. Runtime reports, staging data, backups, and media remain ignored by Git.
5. No synthetic media files are committed.
6. Feature branch is pushed and checked against remote.
7. Merge to `main`.
8. Run the RC harness again from `main`.
9. Bump `VERSION` and `$ToolVersion` to `0.7`.
10. Commit, push, and tag `v0.7`.
