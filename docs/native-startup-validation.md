# First Patrol: original-instruction startup validation

Headless validation passed for the bounded native scenario-selection and
`setupnewgame` path. This establishes original loader behavior under explicit
hosted filesystem, resource and presentation services. It does not establish
live Macintosh UI startup or play acceptance.

## Defect and correction

The original `setupnewgame` instructions at `0x153a74..0x153ade` obtain the selected
Mission menu item's text, construct its scenario-level path with `getfilename`,
and open that **scenario-named file**. First Patrol's first export retained
`The Thunder of Guns` and `Data CS`, but lacked `First Patrol`. The native control
loaded successfully; the first candidate reached `scratch(189)` at `0x138be8`
after its `Scenarios:First Patrol:0:First Patrol` open failed.

The corrected export adds `First Patrol` and `First Patrol.rsrc` as exact copies
of the identified template startup header and sidecar. It retains all 59 imported
paths, including the old named header. Only the previously authored DD, RD,
Mission and TD3 fields change in those retained files. Unknown header bytes and
fork bytes remain exact. Opening-field edits now update both the cached `Data CS`
and the effective native header, without rewriting other header bytes.

Project version 2 records the native scenario name and startup-header source.
Version 1 imported checkpoints still support exact unchanged export. Legacy
minimal-template checkpoints, including the original First Patrol project,
migrate in memory when a unique header with the same bytes as `Data CS` exists;
their stored manifests and blobs are never overwritten. Ambiguous header identity,
unrepresentable/overlong native names and output-name collisions fail explicitly.

`Data Mission` stage zero supplies the final starting map/x/y through the original
`Displaymissionname` instructions. It can override the initial header values.
Those are distinct fields; a header edit alone does not promise a different
native stage-zero arrival.

## Execution and independent checks

The runner extracts CODE 0–3 and DATA 0 directly from the original application's
resource fork, reconstructs the analysis relocation in this workspace, compares
it with the reference relocation, and verifies the executing Ghidra program's
complete CODE 1–3 bytes. It operates on a copied Ghidra project in read-only mode.
No application instruction patch or desktop emulator launch is used.

Native instructions exercised:

- `selectscenario` `0x1366f8`, including path construction and resource-fork selection.
- `setupnewgame` `0x1538ba`, including its native compatibility check and state setup.
- `resetgamefiles` `0x14f96e`, including original table-to-temporary-file loops.
- `getfilename` `0x136cfa`, `gettempfilename` `0x136d86` and native C string-copy/append helpers.
- `Displaymissionname` `0x133f3e` and `loadland` `0x13107a`.
- `loadpixmap` `0x131182`, including actual stock property-file selection and reads.

The original control and corrected First Patrol both return normally. First
Patrol selects stage `First Patrol`, map 0, x 2, y 2, terrain 2. Complete mission,
walking-header, region, visibility, floor, object, event and tile-property buffers
match independent Python constructions from the exported files and original stock
data. The default tile is 155 and its tick flag is 0. The native property reader
requests 16000 bytes but the supplied stock file contains 12000 property bytes;
the test verifies both those bytes and the unchanged initial tail.

The native DD-driven staging loop produces eleven temporary map records from the
shipped eleven DD blocks, while the source `Data LD` contains ten maps. This is
recorded without normalization. Acceptance here covers the selected opening map,
not the additional staged record or campaign topology.

## Controlled services and remaining gates

The hosted C filesystem preserves fread partial-read/EOF behavior, creates only
virtual temporary files and supplies the actual exported bytes. Number/Pascal
string conversion, disk-space queries, resource/menu Toolbox calls, display-only
menus, the stage-name flash and the keep-existing-crate reply are explicit services.
The effective-registered condition is a declared input. Graphics instructions
`0x1312c0..0x131364` are a hosted presentation span; native property loading then
continues normally. The runner rejects unexpected services, instruction-budget
failures, uninitialized-memory warnings and other Ghidra errors.

The reference Mission MENU 130 has `The Thunder of Guns` at item 5. The First
Patrol cases use a **controlled menu fixture** changing that item's label to
`First Patrol`; the reference resource fork remains unchanged. Resource counts
come from the actual original resource chain: one application NEWC resource plus
five scenario NEWC resources. This tests a compatible slot; it does not prove
automatic discovery of an arbitrary new scenario or compatibility with another
menu position. The exporter now reports that scenario-folder and matching-menu
installation are separate work.

Live menu installation, window/dialog rendering, the opening prologue, subsequent
event-loop behavior, movement, original save/load and campaign completion remain
unverified. No host-window computer-use actions were performed. The initial
Basilisk copy was never launched; its offline catalog parser failed on an existing
catalog record, so it was not used as evidence. The accepted proof uses Ghidra
headless execution instead.

This paragraph describes the bounded-instruction milestone. Subsequent isolated
original-application installation and startup now pass through the guest harness;
the prologue gate remains incomplete. See
[the newer native editor/application report](native-editor-validation.md).

## Reproduce

```powershell
python tools\verify_native_startup.py --reference 'D:\The New Centurions Codex' --ghidra 'F:\Ghidra\ghidra_12.1.2_PUBLIC' --editor target\release\centurions-editor.exe --legacy-level artifacts\first-patrol-01\level --out artifacts\my-new-native-startup-run
```

The legacy level supplies the known failing control. Output must be new and under
this checkout's ignored `artifacts/`. Reference files and the source Ghidra project
are read-only inputs. Input hashes are verified again after execution.

Accepted artifacts are under `artifacts/native-startup-04/`: `receipt.json`,
`capture.json`, `ghidra.log`, `inputs.json`, `controlled-menu.json`,
`first-patrol-project/project.json`, `first-patrol-level/` and complete captured
buffers. Earlier exploratory receipts remain private and are superseded; only
run 04 includes the final editor build and resource/menu fixture checks.

Rust preservation/migration tests, Clippy, formatting and release build passed.
The unchanged real-folder gate still preserves 59/59 files. The corrected
candidate has 61 files: all 59 originals plus the two named header aliases.
All 293 original installation files, pinned source inputs, reference disk, ROM,
XPRAM and emulator/client files remain byte-identical. No push or publication.
