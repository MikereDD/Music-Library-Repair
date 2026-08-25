# Testing

## Current status

The project has extensive real-world manual validation but does not yet have a formal automated test suite.

Do not confuse real-world proof with regression coverage; both are needed before v1.0.

## Test fixture policy

Never commit copyrighted music files.

Use generated/synthetic fixtures for:

- valid MP3
- valid FLAC
- valid M4A
- deliberately truncated/corrupted files
- embedded artwork
- no artwork
- multiple disc tags
- missing album artist
- malformed track numbers
- suspicious 30-character titles

Synthetic audio can be generated locally with FFmpeg.

## Manual smoke test

Before an apply-changing commit:

1. Run read-only discovery.
2. Confirm source audit counts.
3. Review plan output.
4. Apply only to disposable/test copies.
5. Confirm strict post-write decode.
6. Confirm tags and artwork.
7. Confirm canonical filename.
8. Confirm backups/rollback behavior where applicable.

## Regression rule

Every bug found against a real library should eventually become a synthetic regression test reproducing the same class of failure.
