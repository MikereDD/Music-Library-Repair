# Architecture

## Pipeline

The canonical engine is:

```text
Discover
→ Strict source decode audit
→ Identify / Review
→ Preview / Plan
→ Approve
→ Apply
→ Verify
```

Every future mode should use the same engine. Automation changes how much review is required; it must not create a second, weaker safety path.

## Intended operating modes

### Interactive
Human reviews album-level decisions.

### AutoHighConfidence
Future mode. Automates only decisions that pass strict confidence rules.

### Nuclear
Future mode. Aggressive cleanup of clear defects, while still refusing ambiguity and damaged source audio.

"Nuclear" is shorthand for breadth of repair, not reduced safety.

## Discovery

The engine recursively discovers supported audio extensions and groups them by album folder.

Current discovery extensions include:

```text
.mp3 .flac .m4a .aac .ogg .opus .wav .wma .aiff .aif .ape .wv .m4b
```

## Source integrity

Before approval/apply, each source is decoded with FFmpeg using strict error behavior.

A metadata probe is not considered an integrity test.

## Planning

Plans are persisted to state so review can stop/resume without losing decisions.

A plan may include:

- artist
- album artist
- album
- date
- genre
- cover path
- cover provenance
- MusicBrainz release ID
- explicit missing-cover approval
- title overrides

## Apply

v0.6 Apply is MP3-only.

The intended transactional sequence is:

1. Build rewritten files in staging.
2. Stream-copy audio.
3. Normalize metadata/artwork.
4. Strictly verify staged output.
5. Stage originals safely.
6. Install repaired files.
7. Roll back if installation fails.
8. Record result.

Originals must not be destroyed before the replacement has passed verification.

## Verification

Verification is required both before and after mutation.

A repaired file is not complete merely because FFmpeg returned exit code 0; decoder error output must also be considered.

## State

Default runtime root:

```text
$HOME\Downloads\Music-Library-Repair
```

State/report formats are not yet guaranteed stable before v1.0.
