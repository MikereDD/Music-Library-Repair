# Music-Library-Repair 0.7 Release Notes

## What 0.7 establishes

0.7 is the first stable milestone for the unified music-library repair engine.

The release establishes:

- strict whole-library source decode auditing,
- decoder signature and severity analysis,
- evidence-domain classification,
- classification-aware repair queues,
- replacement evidence analysis,
- conservative identity reconstruction,
- candidate validation including forced-demuxer review,
- verified staging,
- explicit replacement approval,
- lossless-to-lossy downgrade protection,
- verified source backups,
- same-extension transactional replacement,
- cross-extension transactional replacement,
- rollback behavior,
- post-replacement verification,
- affected-album requalification,
- synthetic release-candidate regression testing.

## Safety model

Raw decoder failure is evidence only. It does not authorize replacement.

Replacement requires multiple independent gates and a verified backup. Known quality downgrade requires its own explicit approval.

## Deferred

The following remain future work and are not implied by the 0.7 stable label:

- automatic `.m3u` playlist path rewriting,
- audiobook workflows,
- fully automated source acquisition,
- guessing ambiguous releases,
- silent quality downgrades.
