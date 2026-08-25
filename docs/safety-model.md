# Safety Model

## Principle

**Never turn a metadata problem into an audio problem.**

## Failure classes

### Metadata defect
The audio is healthy. Tags, filename, artwork, or organization need repair.

Action: repair may proceed after review.

### Source decode error
The file exists but strict decode reports damaged audio.

Action: block approval/apply. Queue for replacement.

### Missing track
The album appears incomplete.

Action: do not fabricate or renumber around the missing content. Verify against an authoritative release before declaring a gap.

### Ambiguous release
Multiple plausible releases exist and the distinction matters.

Action: require a human selection or stronger evidence.

### Missing artwork
No trustworthy artwork is available.

Action: resolve through known local/embedded art, exact MusicBrainz + Cover Art Archive release lookup, a user-supplied image, or explicit acknowledgment that art remains missing.

## Source decode policy

Use FFmpeg with strict decode behavior:

```text
-xerror -err_detect explode
```

Treat either a non-zero result or decoder error output as failure.

Do not rely on `ffprobe` success alone.

## Replacement policy

A damaged source should be replaced only after the candidate replacement:

1. strictly decodes
2. matches the expected album/track identity
3. has plausible duration
4. is staged separately
5. is verified before the damaged source is displaced

The damaged source should remain recoverable until the replacement transaction completes.

## Backups

`-BackupOriginals` is strongly recommended for all pre-1.0 apply runs.

## No guessing

The tool must never silently invent:

- titles
- release dates
- track order
- disc assignment
- cover art
- edition identity

High confidence can reduce interaction; it does not relax correctness.
