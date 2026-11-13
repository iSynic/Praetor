# Current connected authoring evidence

Version 5 adds the connected mission workflow. See [connected authoring](connected-authoring.md)
for current fields, allocation and corrected ordinary-movement semantics, and
[delivery evidence](connected-delivery.md) for the current build and receipts.
The earlier milestones below are historical; version 4 lookup-only marker and
placement conclusions are superseded. The full-emulator prologue gate remains
incomplete.

# Native editor and original-application validation

2026-10-26. Work is local; original assets and all generated captures remain in
ignored `artifacts/`. No push or publication.

## Result and evidence boundaries

First Patrol loads and starts in the original application, using a disposable
installation with only Cargo Pod's Mission MENU 130 item 5 label changed. Its
stage-zero mission record matches the export. Live original globals confirm map
0, relative position (2,2), viewport (0,0), hence final position (2,2). Captures
show the First Patrol stage flash, exploration screen, and subsequent UI feedback.

The full native acceptance gate is **partial**. Opening TEXT display stalls in
TEScroll/offscreen drawing. The established Centurions chat documents the same
problem in `tools/reference_debug.py`: its workaround replaces loaded presentation
instructions and explicitly disqualifies those observations as unmodified proof.
That workaround was not used here. Live bytes at CODE 1 + `0x3ebde` and `0x3edb0`
remain `4e56ffee` and `a9dd`. Prologue completion and broad gameplay acceptance
remain unverified.

The native Godot editor implements the supported authoring workflow. Rust owns
canonical snapshots, validation, revisions and undo/redo. Pending form drafts stay
in Godot. Windows file pickers use Godot's native dialogs; automation exercises
their folder/destination callbacks without driving Windows input.

## Original installation and runtime

`tools/stage_native_runtime.py` reads the supplied HFS boot disk and creates a
separate 64 MiB test volume. The boot disk contains one malformed catalog leaf
record: index 4824, bytes beginning `Format Button Test`. The tool recognizes
and records only that exact anomaly during reading; any other malformed record
fails. It never writes a catalog repair into the supplied disk or rewrites that
disk with the third-party serializer.

The staging CLI accepts `--scenario-name NAME`, defaulting to `First Patrol`.
The explicit name must be a single Mac Roman HFS component of 1..31 bytes and
must match a startup-header file in the supplied export. It selects the staged
scenario folder and Mission MENU 130 item 5 label. The test-volume label uses
the first 22 characters plus ` Test` to fit HFS's 27-byte volume-name limit;
the complete scenario name remains unchanged. This installs an existing export
into the compatible menu slot; it does not establish original-game acceptance.

All 217 files in the test volume pass data-fork, resource-fork, type/creator,
Finder flags/location and timestamp read-back comparisons. The tool extracts
AppleDouble resource entries correctly; metadata-only sidecars do not become
resource-fork data. Original application resource payloads match before staging;
the extracted original application's exact fork is installed in the test copy.
Only MENU 130's selected label changes in Cargo Pod; other resource payloads
remain identical. This is installation into a compatible existing slot, not a
claim of arbitrary automatic scenario discovery or a general installer.

SDL dummy video supports the startup capture through the guest harness. A hidden
Windows-video retry and a 32-bit display retry did not resolve the text-display
stall. There were no host
mouse/keyboard automation actions. The muted run's initial sound/music notices
were handled through ordinary guest dialogs; sound quality was not evaluated.

Primary native artifacts:

- `artifacts/native-application-04/installation.json`: staging/read-back receipt.
- `artifacts/native-application-04/receipt.json`: exact exported-file hashes,
  live mission/position and unchanged presentation instructions; partial status.
- `artifacts/native-application-04/patrol-startup.png`, `patrol-arrival.png`,
  `patrol-input.png`, `patrol-conditions.png`: actual original framebuffer captures.
- `artifacts/native-application-04/guest-actions.jsonl`: guest harness requests.

The existing bounded original-instruction runner remains the regression test for
the original control, missing-header/error-189 control, corrected candidate,
complete load buffers and input preservation. Its hosted services remain explicit.

## Native workbench and interface

Providence's theme, scene composition, text/master-detail workbench patterns,
map interactions, stroke collector and JSON-line framing were adapted selectively.
`ui-provenance.json` pins each input and decision. Realmz domain controllers,
record layouts, opcode catalogs, artwork and runtime were not imported.

The adapter uses protocol 1: one JSON request per line, containing `protocol`,
`id`, and tagged `operation`; responses carry `ok`, `revision`, `result` or a
structured `error`. Open/import/new, bounded record projections, typed edit
batches, undo/redo, save-as, export, artwork lookup and receipt matching use the
same core/store as the CLI. Mutations require the current expected revision.
Project format is now version 4 for condition/placement overlays, with version-1/2/3 compatibility.

Rejected edits leave state/revision unchanged. A completed paint stroke is one
batch and one undo step. An interrupted or malformed adapter response requires
reopening; pending drafts are retained for review. Applied edits survive process
loss only after saving a checkpoint. Existing projects/exports are never replaced.

PICT artwork resolves the imported Scenario fork before the selected installation's
Cargo Pod/application forks. Ambiguous or malformed overrides cannot silently
fall through to stock artwork. Verified atlases use 20 by 15 cells of 32 pixels,
tile IDs 1..300. Missing/unsupported pictures and unknown tile IDs use labeled
numeric placeholders. Cache images are outside the application package and the
immutable project store. No original artwork is bundled.

Eight unobscured native floor samples establish atlas indexing and matching
raster patterns against the original framebuffer. Original 8-bit color conversion
differs from source picture colors by up to five RGB levels; exact color equality
is not claimed. The original pixel data is not changed to force agreement.

Receipts are external evidence. Matching requires the complete effective exported
file hashes, directory set, original-application authority and no instruction
patches. Any applied edit invalidates the match; pending drafts remove its display.
The UI reports startup and prologue separately and never promotes the partial
receipt to complete runtime acceptance.

## Reproduction and acceptance checks

Build the local package with `tools/build_editor.ps1 -Output artifacts/my-build`.
Godot 4.7.1 export templates and Rust 1.98+ are required. The package contains the
Godot application, Rust adapter/CLI and license notices, without game payloads.

`tools/verify_editor_workflow.py` runs the real workbench and adapter. It checks
asymmetric stage/header coordinates, Mac Roman refusal, floor stroke undo/redo,
checkpoint save/reopen, adapter interruption/recovery, draft cancel/discard,
read-only story inspection, import and New from Template. An independent Python
construction compares every exported byte and verifies input checkpoints/exports
are unchanged. It also exports unchanged First Patrol through the GUI and compares
it with the native-tested 61-file candidate.

Use `--packaged --godot <exported-exe>` to exercise the compiled package. The
package's explicit `--verify-editor` mode runs the same checks with release-active
failure checks; it is not dependent on debug-only assertions. All write locations
must be supplied under the local ignored artifacts directory.

`godot/tools/capture_editor.gd` captures five real rendered routes and draft/save
dialogs at 1600x900 and 1200x720. It checks shell bounds; visual review checks
readability, scrolling, clipping and dialog content. Embedded test dialogs allow
their content to appear in viewport captures without Windows input automation.

Required closeout: formatting, workspace tests, strict Clippy, release build,
unchanged real-folder comparison, native startup regression, source/payload
preservation, packaged workbench checks and rendered captures. Detailed current
paths and hashes are recorded in the private final verification receipt.

Current local deliverables and accepted receipts:

- `artifacts/windows-editor-05/`: Windows editor, adapter/CLI, docs and licenses.
- `artifacts/gui-package-04/`: final packaged workflow, independent byte comparison
  and unchanged GUI export `native-first-patrol/`.
- `artifacts/native-startup-05/`: final CLI original-instruction regression; its
  capture hash equals the preceding accepted startup run.
- `artifacts/gui-captures-03/`: rendered routes, dialogs and layout bounds.
- `artifacts/final-unchanged-01/` and `artifacts/final-candidate-01/`: independent
  real-data preservation gates.
- `artifacts/reference-preservation.json`: all 293 original files and pinned
  donor inputs unchanged; concurrent Centurions source work is reported separately.
- `artifacts/editor-closeout-01/receipt.json`: final build/evidence hashes and scope.

## Installation persistence, missing icons and program editing follow-up

The installation folder is saved independently of the immutable checkpoint, and
artwork is requested on every successful open/import/new operation. A second
fresh process with CENTURIONS_INSTALLATION removed verifies actual restoration
and artwork loading before visiting Maps. Test preferences are isolated from the
user settings file.

The screenshot gaps were signed native floor IDs (-1, -2, -3), not missing
positive atlas slots. The loader now resolves masked cicn resources by signed ID
through the same scenario-first resource chain. The native terrain property
file supplies the default floor beneath transparent pixels. Resolved icons appear
in the palette below the atlas; absent resources retain numeric placeholders.
Native floor bytes remain signed and unchanged. Objects/buildings still require
a separate rendering audit and remain preserved.

Triggers & encounters exposes walking/story programs and four branches each for
choice/typed encounters. Operations 0,1,4,5,9,24,39 are authorable only when the
existing source pair is supported. Other steps, record headers, selectors,
labels, trigger placement, regions and extra records stay read-only. Native
script-support.md and script-provenance.json bound this implementation. These
newly authored scripts have preservation proof, not a full original-game
playthrough or blanket opcode compatibility claim.

The extended real-shell workflow independently compares every exported byte for
walking, choice and typed edits, checks fresh-process preferences, negative
artwork, draft cancellation, save/reopen and prior regression cases. Rendered
captures cover six routes, both dialogs, negative-icon map areas, palette and
regions at 1600x900 and 1200x720. Original startup/prologue evidence and its
incomplete prologue gate remain separate and unchanged.

## Version 4 field and combat browsing follow-up (historical)

The field investigation in trigger-field-investigation.md records eighteen
original-instruction cases and exact read/write ownership. Version 4 corrects
walking marker eligibility (first matching header and positive signed chance;
no LD event-cell requirement), supports placement within existing 100-slot map
headers, and exposes supported choice/physical/spell/item conditions. Original
return destinations remain distinct, retained and read-only.

Battle and monster catalogues are read-only. The BD view is a native population
layout, with hover/name links to MD definitions. It does not simulate tactical
terrain, randomized deployment, native monster rendering or combat. Fifteen
Rust integration tests and the extended real-shell workflow cover preservation,
condition drafts, placement undo/redo, immutable checkpoint reopening and readonly
combat navigation. Independent full-folder byte comparisons cover every new
GUI-authored field. Thirty-two rendered captures exercise seven routes and the
condition/placement/monster views at both supported window sizes. Native startup
and inherited-prologue gates remain separately recorded.
