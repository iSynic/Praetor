# Local connected-mission delivery

The version-5 workbench adds imported-seed record allocation, active walking
trigger creation/movement/disable/removal, independent return coordinates,
choice labels/prompt/selectors, typed ordinary battle EXTRA, small populations,
basic monster fields, explicit fixed rewards and signed stage transitions.
Unknown imported bytes, forks, suffixes and tails remain retained.

Local artifacts (relative to `D:\New Centurions Scenario Editor`):

| Artifact | Location |
|---|---|
| Windows editor and Rust backend | `artifacts/windows-editor-10/New Centurions Scenario Editor.exe` |
| GUI-authored micro-mission checkpoint | `artifacts/connected-editor-package-10/checkpoint` |
| Native exported level | `artifacts/connected-editor-package-10/level` |
| Linked record recipe | `artifacts/connected-editor-package-10/recipe.json` |
| GUI/CLI/reopen byte comparison | `artifacts/connected-editor-package-10/receipt.json` |
| Reconstruction accept/decline replay | `artifacts/micro-runtime-06/receipt.json` |
| Bounded original connected instructions | `artifacts/micro-native-final-09/receipt.json` |
| 18 retained lookup/condition cases + 3 movement cases | `artifacts/trigger-fields-final-05/receipt.json` |
| Original startup/error-189 regression | `artifacts/native-startup-08/receipt.json` |
| Existing packaged editor regression | `artifacts/editor-regression-package-10/receipt.json` |
| Original/reference preservation | `artifacts/connected-reference-preservation.json` |
| New authoring rendered views | `artifacts/connected-captures-01/receipt.json` and adjacent PNGs |
| Aggregate source/build/evidence binding | `artifacts/connected-delivery-10.json` |

The micro-mission starts at map 0 (2,2). Walk east to (3,2), read the new
message, choose Engage, defeat the inherited-prototype training enemy, collect
the explicit 25-credit reward and reach Patrol Complete at (4,2). Not yet
returns to exploration without a battle or reward. Full reconstruction turns
exercise this route; the GUI and CLI exports are equal in every file byte.

Bounded original execution verifies battle selection/continuation, the complete
new treasure load and native stage/start-story arrival. It hosts choice input,
combat outcome, treasure processing and presentation. Original battle completion
and interactive completion of this new mission are not certified. The earlier
First Patrol native application evidence remains partial because the inherited
TEXT prologue stalls in TEScroll; no presentation-instruction workaround was used.

The first reconstruction receipt used a disposable Thunder-path alias. Later
acceptance verifies named scenario selection without that alias, plus genuine
save/resume and Windows observation; see [authored acceptance](authored-acceptance.md).
No runtime/reference source was changed in place. The editor package contains no
original assets; the local private checkpoint/export retain template data under ignored
artifacts. No push or publication was performed.

## Reproduction

Use new output names for every run:

```powershell
cargo fmt --all -- --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo build --workspace --release
python tools/verify_connected_editor.py --packaged --godot 'artifacts/windows-editor-10/New Centurions Scenario Editor.exe' --editor artifacts/windows-editor-10/centurions-editor.exe --template artifacts/unchanged-01/imported --installation 'D:/The New Centurions Codex/NewCenturions/TheNewCenturions' --out artifacts/my-connected-editor
python tools/verify_connected_native.py --baseline artifacts/native-startup-07 --reference 'D:/The New Centurions Codex' --ghidra F:/Ghidra/ghidra_12.1.2_PUBLIC --level artifacts/micro-scenario-05/level --out artifacts/my-connected-native
python tools/verify_connected_runtime.py --reference 'D:/The New Centurions Codex' --installation 'D:/The New Centurions Codex/NewCenturions/TheNewCenturions' --level artifacts/micro-scenario-05/level --out artifacts/my-connected-replay
```

The native connected probe intentionally expects the default Thunder-derived
micro-mission record IDs. Its receipt hashes all exact exported inputs and
code images. Use the saved default recipe for reproduction; this is not a
generic original-game scenario runner. See [authoring support](connected-authoring.md)
for limits, byte ownership and operations outside the milestone.
