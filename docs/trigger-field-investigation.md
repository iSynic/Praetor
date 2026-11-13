# Trigger, encounter and combat field investigation

Local investigation, 2026-10-26. References remain read-only. No push or publication.

## Providence UI reuse

Providence's controls, themes, master/detail lists, split panes, step selection,
record pickers, dialogs and map interactions can be reused directly or adapted
closely. A different binary format does not require a different visual design.
The earlier smaller interface was a scope decision, not a technical prohibition.

The exact `map_ap_placement_inspector.tscn` presentation scene is now reused,
with Centurions-specific text and controller wiring at runtime. Its donor hash
and GPL provenance are in `ui-provenance.json`. The donor's
`simple_encounter_editor.tscn`, `simple_encounter_step_dialog.tscn`,
`action_step_workbench.tscn` and monster reference picker show further reusable
presentation. Their controllers and resource dependencies are not drop-in:
they depend on Realmz project types, operations, reference libraries and opcode
helpers. The full simple-encounter pane also requests a 245-pixel master plus
950-pixel detail; placed unchanged beside our sidebar it exceeds the supported
1200-pixel window. That calls for responsive layout adaptation, not replacement
of the visual vocabulary. A complete UI redesign is outside this batch.

| Concept | Necessary Centurions divergence |
|---|---|
| Walking AP / trigger | 100 existing 42-byte DD headers per map; independent location key and return destination. First matching header wins. |
| Programs | Eight slots remain a reusable UI idea. DD/ED3 opcodes are i16; ED/ED2 branch opcodes are signed bytes. Meanings and operand reference types come from Centurions. |
| Choice / typed encounters | Four result programs can share Providence's layout. Centurions uses separate 426/516-byte records and its own selectors, physical-action sets, spell categories, item alternatives and retry behavior. |
| Trigger conditions | Chance and selection conditions are native fields. Script-level flag/EXTRA-dependent conditions need separate opcode investigations. |
| Battles | BD stores a 26x26 population of signed monster references. Tactical terrain and actual placement are runtime concerns. |
| Monsters | 288-byte MD definitions with Centurions fields and references; Realmz monster forms cannot supply field semantics or artwork IDs. |
| Saving | Immutable imported blobs plus bounded overlays and new checkpoint directories; presentation can reuse dialogs while storage commands remain Centurions-specific. |

## Original instruction execution

`tools/verify_trigger_fields.py` runs `VerifyTriggerFields.java` against a
disposable copy of the verified original mapped application. It hashes the
original application resource fork, original-code/A5 inputs and the exact probe
and harness. Original code bytes are loaded intact. Audio cycling and Rand
replies are explicit services. The one spell-category case hosts the spell
definition lookup while executing the original matching instructions.

Eight walking cases enter newland at **0x1400e4**, stop on selection at
**0x14032e** or normal rejection, and compare the complete copied 42-byte header
and unchanged 4200-byte input table. Cases cover chance 100 with zero/nonzero
map event cells, disabled-first duplicate shadowing, -1 retirement, another
negative chance, failure/pass exactly around the random boundary, and no match.

The key is map*10000 + y*100 + x. Lookup reads the first matching header, copies
it, rejects signed chance <=0 and accepts Rand(100) <= chance. It does not test
the LD event-cell value. The ordinary walking caller at **0x109766..0x109884** separately checks the LD
cell at 0x414390+4*(x*90+y). A signed value <=0 bypasses newland. Three captured
original caller cases (-1, 0, 203) verify rejection/rejection/invocation with
correct (3,2) arguments. moveparty position and timeclick replies are hosted;
the gate and call setup execute original instructions.

**Correction to version 4:** its direct-lookup evidence did not establish the
ordinary caller. Version 5 requires both the map gate and eligible DD header,
and couples placement with bounded activation edits. The 18 prior independent
lookup/condition cases remain alongside the three new caller cases.

Ten additional bounded condition cases execute these original blocks:

| Boundary | Verified result |
|---|---|
| 0x122a5c..0x122adc | Empty physical requirement fails; an exact nonempty set returns its selector; an extra selected action fails to selector 4. |
| 0x1229ea..0x122adc | Fifth item alternative can match; no match returns 4. |
| 0x122918..0x122adc | Spell ID match, no match, and criterion 1..6 matching a loaded spell category. |
| 0x12182e..0x121846 | Fourth displayed choice may return branch selector 2; selector -4 remains signed. |

These are original-instruction field/selection proofs. They do not claim a
complete original dialog interaction, password/retry playthrough, battle or
campaign playthrough. The first spell/item alternative also gates the native
UI, established in the original caller at 0x122996 and the spell-path tests.

## Version 4 field ownership (historical; superseded below)

Offsets below are relative to each record. Scalars are big-endian where wider
than one byte. Imported values outside the newly supported authoring subset
remain read-only; unrelated bytes and file fragments are never rewritten.

| Table / offset | Meaning | Version 4 support |
|---|---|---|
| DD 0..4 | Walking location key | Place/move an existing slot within its owning map. Own exactly these four bytes. |
| DD 4/5/6 | Return destination map/x/y, signed bytes | Inspect and preserve. They are not trigger placement coordinates. |
| DD 7 | Signed chance | Author 0..100; zero disables, existing negative values remain understood as disabled/retired. |
| DD/ED3 8..40 | Eight opcode/operand pairs | Prior bounded step editing retained. |
| DD/ED3 40 | Return level byte, signed comparison against current level | Read-only; cross-level return needs separate validation. |
| DD/ED3 41 | Stamp / retained caller byte | Read-only. No synthesized default. |
| ED 0..96 | Four byte-opcode / i16-operand programs | Prior supported-step editing. |
| ED 96..100 | Four displayed-choice selectors | Author 0..4; 0 hides, 1..4 dispatch branches 0..3. Negative controls such as -4 stay read-only. |
| ED 100 | Native display/control mode | Inspect/preserve; not exposed as a guessed condition. |
| ED 101..104 | Remaining header bytes | Unresolved, preserved. |
| ED 104..106 | Dialogue ID | Read-only in this batch. |
| ED 106..426 | Four 80-byte Pascal label slots | Read-only, including suffix bytes. |
| ED2 0..96 | Four byte-opcode / i16-operand programs | Prior supported-step editing, independent 516-byte stride. |
| ED2 96 | Physical-action result selector | Author 0..4; 0 disables. |
| ED2 97 | Password selector | Read-only pending complete matcher and special-command investigation. |
| ED2 98..106 | Eight required-action bytes | Author 0/1. Native matching compares the exact nonempty set. |
| ED2 106..126 | Ten spell ID/category criteria | Author nonnegative i16 numeric criteria. First entry gates the UI. |
| ED2 126..136 | Ten spell result selectors | Author 0..4. |
| ED2 136..146 | Five item criteria | Author nonnegative i16 numeric criteria. First entry gates the UI. |
| ED2 146..151 | Five item result selectors | Author 0..4. |
| ED2 151 | Header byte | Unresolved, preserved. |
| ED2 152 | Attempts/retry counter source | Read-only: newland can change failure branch on last attempt; no guessed retry policy. |
| ED2 153 | Header byte | Unresolved, preserved. |
| ED2 154..156 | Dialogue ID | Read-only. |
| ED2 156..516 | Eight 40-byte labels and ninth password label | Read-only. Password handling also recognizes native special commands. |
| RD regions | Rectangles, battle ranges, script references/chances | Existing inspection and links; authoring remains outside this batch. |
| EDCD / other conditional opcodes | Ten-byte EXTRA records interpreted per opcode/caller | Retain; no generic raw-condition editor. |

Version 5 supersedes the placement/label/return restrictions in the historical
table above. It adds coupled header/gate edits, return coordinates at level 0,
choice labels/prompt, imported-seed allocation, typed battle EXTRA, basic
battle/monster/reward editing and signed stage transitions. Exact spans and
current limits are in [connected authoring](connected-authoring.md).

## Battle and monster browsing

There is no format-level blocker to read-only views. Original combat at
0x114378 seeks abs(battle)*0x55c and reads 1372 bytes. combatsetup at 0x11d406
walks x*26+y, seeks abs(monster)*0x120 and reads 288-byte definitions. A negative
population reference flips the loaded faction field. Basic MD fields and the
Str29 name at 218 are corroborated by the pinned record views and native callers.

Battles & monsters now provides paginated search, population hover IDs/names,
double-click navigation to monster definitions, known basic fields, and the
complete retained record as hex. The browsing pane is read-only and links to the bounded Author records forms. Native monster artwork,
runtime terrain composition, randomized placement and full battle/monster authoring are not claimed by this view.

## Reproduce

```powershell
python tools/verify_trigger_fields.py --baseline artifacts/native-startup-06 --reference 'D:\The New Centurions Codex' --ghidra 'F:\Ghidra\ghidra_12.1.2_PUBLIC' --out artifacts/my-trigger-proof
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

The shell workflow additionally exercises condition drafts, placement undo/redo,
save/reopen, and combat browsing. Independent Python comparison checks every
exported byte against the expected specific spans, including bounded positive LD activation and retained surrounding event bytes. All generated projects, resource payloads, code images, receipts
and captures stay ignored under artifacts.
