# Bad-Source Replacement Workflow

This is the next major subsystem after v0.6.

## Goal

Turn a detected source failure into a durable, verifiable work item instead of merely skipping the album.

```text
SOURCE DECODE ERROR
→ replacement-needed queue
→ identify expected track
→ locate/supply candidate replacement
→ strict-decode candidate
→ verify identity/duration
→ stage candidate
→ transactional swap
→ re-audit album
→ restore eligibility for normal repair
```

## Replacement queue

Planned export:

```text
replacement-needed.csv
```

Each item should retain enough information to resume later:

- source path
- album folder
- artist
- album
- date
- disc
- track
- current title
- expected authoritative title if known
- decoder error summary
- MusicBrainz release ID if selected
- replacement status
- candidate path
- candidate verification status
- replacement timestamp

## Candidate verification

A replacement must not be trusted merely because its filename looks correct.

Minimum verification:

1. strict full decode passes
2. format/container can be inspected
3. track identity matches expected release
4. duration is plausible
5. metadata can be normalized independently
6. replacement is not byte-identical to the known-bad source when independent lineage is required

## Transaction

The initial bad source remains untouched while the candidate is being evaluated.

Only after the candidate is verified should the tool:

1. move/copy the bad source into recoverable backup/staging
2. install the candidate
3. rerun strict source audit
4. rerun album completeness/metadata review
5. mark the replacement item resolved

## Flogging Molly test case

The v0.6 Flogging Molly audit exposed ten known-bad source tracks across four skipped albums. Those tracks are a useful real-world test fixture conceptually, but copyrighted audio must never be committed to this repository.

Tests should use generated/synthetic fixtures instead.
