# Reports Reference

Reports are written beneath the state root, normally:

```text
$HOME\Downloads\Music-Library-Repair\audit
```

Important reports:

| Report | Purpose |
|---|---|
| `tracks.csv` | Per-track metadata and audit state |
| `albums.csv` | Per-album qualification |
| `source-decode-audit.csv` | Strict decoder results |
| `source-decode-observations.csv` | Raw decoder-failure observations; **not replacement authorization** |
| `decode-error-signatures.csv` | Canonical decoder signatures |
| `audit-crosscheck.csv` | ffprobe / strict-decode evidence comparison |
| `repair-action-queue.csv` | Classification-aware action queue |
| `replacement-review-analysis.csv` | Evidence analysis for ReplacementReview items |
| `replacement-evidence-analysis.csv` | Targeted replacement evidence |
| `replacement-candidate-intake.csv` | Human-editable candidate and approval intake |
| `replacement-candidate-validation.csv` | Candidate probe/decode/identity validation |
| `replacement-staging-manifest.csv` | Verified staging evidence |
| `replacement-transaction-manifest.csv` | Backup/commit/rollback transaction record |
| `replacement-postverify.csv` | Read-only verification of committed replacements |

## Evidence versus action

`source-decode-observations.csv` answers:

> What files produced strict decoder evidence?

It does **not** answer:

> What files should be replaced?

That decision belongs to the classification pipeline and `repair-action-queue.csv`.

## Historical reports

Post-replacement verification does not silently rewrite old audit evidence. Historical reports remain evidence of what was observed at that time. Run a new full `-AuditOnly` when a fresh whole-library snapshot is needed.
