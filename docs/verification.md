# Local verification: 2026-10-26

This receipt documents the first command-line format/authoring milestone.
All original-data payloads and detailed receipts are private ignored artifacts.
It is historical. The subsequent [native startup validation](native-startup-validation.md)
fixes the missing named header and records the bounded original-instruction result.

| Check | Result |
|---|---|
| `cargo fmt --all --check` | Passed |
| `cargo test --workspace` | Passed: four integration tests covering preservation, corruption/failure boundaries, Centurions indexing/story geometry, and minimal construction |
| `cargo clippy --workspace --all-targets -- -D warnings` | Passed |
| `cargo build --workspace --release` | Passed |
| Supplied Thunder of Guns level 0 unchanged import/export/reopen | 59/59 files, exact path set and bytes; independent Python hash comparison |
| A scenario authored with the resource, calendar, object-layer and added-map features, exported to a disposable installation and entered in the reconstruction (`tools/verify_authored_p3.py`) | the mission starts on the added map, its objects load, the calendar entry holds the authored fields; reconstruction replay, not the original |
| A level with floor cells numbered 1012, 2012, 3012, 3150 and -3012 beside the start, run in the original (`tools/build_native_resource_level.py --kind secrets`, `tools/run_native_resource_check.py`) | the cells above 300 draw as black or leftover pictures; evidence for [maps.md](original-evidence/maps.md), "Secret cells" |
| Selected stage/story/message projections | Matched independent Python signed big-endian / Mac Roman readers |
| First Patrol candidate | Created only after unchanged gate; one named starting stage; 59 paths retained; changes in four files only, all within independently checked owned spans |
| Real message and floor-cell authoring | Exported values matched independently constructed bytes; all other bytes retained |
| Original installation preservation | 293/293 original files unchanged against pre-work SHA-256 baseline |
| Pinned reconstruction/Providence source inputs | All referenced file hashes unchanged |
| Donor worktree status | Both Providence statuses unchanged; Centurions gained unrelated dirty combat/runtime/test paths during execution. No implementation command wrote to a donor. Full-checkout immutability is not asserted. |
| Publishing | No remote configured; no push or publication |

## Local outputs

- Executable: `target/release/centurions-editor.exe`.
- Original import checkpoint: `artifacts/release-unchanged-01/imported/project.json`.
- Exact unchanged export: `artifacts/release-unchanged-01/unchanged-export/`.
- Unchanged receipt: `artifacts/release-unchanged-01/unchanged-receipt.json`.
- First Patrol project: `artifacts/first-patrol-01/project/project.json`.
- First Patrol level folder: `artifacts/first-patrol-01/level/`.
- Candidate byte-ownership receipt: `artifacts/first-patrol-01/candidate-receipt.json`.
- Reference preservation receipt: `artifacts/reference-preservation.json`.

## Remaining acceptance gates

The candidate inherits all ten maps and the original support catalogs, prologue,
media and unresolved global/bootstrap fields. Disabling activation on the starting
map is a bounded format operation, not proof that every inherited native hook is
inactive. This is not source-free native scenario construction or a complete
installable original-game scenario. Original-binary load/play, broader authoring
coverage and a native graphical editor are unverified and unfinished.
