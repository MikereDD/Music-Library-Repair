# Architecture

## Canonical pipeline

```text
Discover
  -> strict source audit
  -> classify evidence
  -> build action queue
  -> identify/review
  -> preview/plan
  -> approve
  -> apply transaction
  -> verify current state
```

There is one canonical evidence model. Raw strict-decoder output is not a replacement queue.

## Evidence domains

The classifier separates a primary domain from broader evidence:

- `AUDIO`
- `CONTAINER`
- `ARTWORK`

A diagnostic can contain multiple evidence types. `PrimaryDomain` is the best current explanation for action routing; `EvidenceDomain` preserves broader evidence.

## Replacement state machine

```text
ReplacementReview
  -> evidence analysis
  -> candidate intake
  -> candidate validation
  -> explicit StageApproved
  -> verified staging
  -> explicit ReplaceApproved
  -> quality gate
  -> verified source backup
  -> transactional replacement
  -> committed replacement verification
  -> affected-album requalification
```

A lossless-to-lossy replacement has an additional explicit approval gate.

## Observation queue versus action queue

`source-decode-observations.csv` is observational. It exists so raw evidence is not lost.

`repair-action-queue.csv` is classification-aware and determines whether the next step is audio review, container review, artwork repair, replacement review, or another manual action.

This separation prevents a decoder diagnostic from silently becoming a destructive instruction.

## State and history

The tool preserves historical evidence rather than rewriting it to match current files. Targeted post-verification answers whether a committed replacement is currently healthy; a later whole-library audit creates a new canonical snapshot.
