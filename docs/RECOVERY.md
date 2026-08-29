# Recovery and Rollback

The replacement transaction is designed around recoverability.

Before a source file is replaced, Music-Library-Repair:

1. hashes the source,
2. copies it into `replacement-backups`,
3. hashes the backup,
4. refuses the transaction if the hashes do not match,
5. verifies the staged replacement,
6. commits the replacement,
7. verifies the committed replacement.

Successful backups are retained for manual recovery.

## Backup location

```text
<StateRoot>\replacement-backups\<source-key>\<timestamp>\
```

## Same-extension replacement

Same-extension replacement uses `System.IO.File.Replace` with a temporary same-directory swap backup. The authoritative recovery copy is still the independently verified backup beneath `replacement-backups`. The temporary swap backup is removed after the transaction.

## Cross-extension replacement

The replacement is first published under the new extension and verified. Only then is the damaged source removed.

## If a transaction fails

The transaction manifest records `Blocked`, `RolledBack`, or `ReplacementCommitted`. A failure after a verified backup triggers best-effort rollback.

Do not delete `replacement-backups` until the repaired library has been independently checked and backed up by your normal backup system.
