# Connected mission authoring (project version 5; version 6 adds region edits)

The workbench can now author a small linked mission from an unchanged imported
template. Original Centurions instructions remain behavior authority. This does
not construct a scenario without inherited support files or unknown seed bytes.

## Workflow

1. Import an extracted level and keep that unchanged checkpoint as a template.
2. On Project, use **New from template** to create a new scenario/checkpoint.
3. Use **Author connected micro-mission…** on the fresh template-derived project.
   Edit stage/text/choice/reward fields and explicit imported monster, battle and
   choice seed IDs. The operation adds all links as one undo step. A recipe is
   rejected once that project contains other authored work or allocated rows.
4. **Author records** opens existing rows or clones an imported seed as a new
   row. It edits messages, choice labels/prompt/selectors, battle EXTRA, battle
   populations, basic monster fields and fixed credit/experience rewards.
   **Triggers & encounters** edits eight native program slots per branch.
5. Maps **Place trigger** moves a slot and updates its ordinary-movement gate.
   Select a cell in selection mode before **New at selected cell**. New uses an
   unplaced empty program slot and does not erase an existing program. Disable
   retains the location/program; Remove unplaces the header and clears its owned
   gate. Enable by placing with positive chance. A separate option makes the
   return destination follow placement; otherwise it remains independent.
6. Apply drafts, save a new checkpoint, reopen it, and export to a new folder.

Choice selectors 1–4 map to program branches 0–3; zero disables the choice.
Labels are strict Mac Roman, at most 79 encoded bytes. Message limit is 255 and
monster name limit is 29. Invalid encoding is rejected with a field location.
Stage start stories are editable separately from map/x/y and header opening.

The recipe's stage name need not be the scenario installation/menu name chosen
by **New from template**. It places a trigger one cell east of the start, a
completion stage two cells east, and a bounded floor clearing (default 16×16 at
start 2,2). Existing objects in that clearing cause rejection. It retains native
monster art, attacks, descriptions and other unresolved prototype fields.

## Native semantics and owned spans

All offsets are relative to a row; multi-byte values are big-endian.

| Operation | Owned bytes / constraint |
|---|---|
| Walking place | DD i32 key 0..4, signed chance byte 7; map*10000+y*100+x. 100 fixed slots per map. |
| Ordinary movement gate | LD 32400+4*(x*90+y), within 64800-byte map. Only -1, 0, 1 or matching coordinate key may be replaced; unresolved values reject. Enable writes positive key (1 for key zero). Disable preserves imported negative sentinel or writes zero. |
| Walking return | DD map/x/y 4/5/6 and level 40, currently only level 0. Stamp 41 retained. |
| Choice | ED prompt i16 104..106; selectors 96..100; each label length/payload at 106+80*c, at most 79 bytes; unused suffix retained. |
| Stage start story | Mission i16 262..264; 0 means none, otherwise existing ED3 row. 20 fixed stage slots. |
| Ordinary battle EXTRA | EDCD five i16 words: minimum battle, maximum (0=fixed minimum), sound, message, cleanup mode (0 ordinary / 5 no monster loot). This is opcode-specific; other EXTRA interpretations stay unresolved. |
| Battle population | BD 0..1352: 26×26 signed monster IDs, x*26+y. 1..100 nonzero actors; unique cells; retained squad start must be within 26×26. Remaining metadata retained. |
| Monster basics | MD i16 level/stamina/speed/movement at 0/2/4/6; name length/payload 218..248. Level 0..127, stamina 0..30000, speed 1..32767, movement 0..127 (evidence: `docs/original-evidence/data-md.md`). |
| Clear prototype drops | MD six i16 slots 0x26..0x32 and cash bound 0x3a..0x3c only. No inferred clearing of nearby fields. |
| Reward | TD i32 experience 80..84 and credits 84..88; fixed nonnegative values up to 1,000,000. Imported item bytes stay intact. |

Opcode **2** takes a battle EXTRA row ID. Word 8 is a cleanup mode, not a reward
ID. Opcode **10** explicitly loads an 88-byte TD row and requests treasure
processing. Opcode **110** directly takes a signed one-based stage number;
negative skips native confirmation. For stage index 1 use **-2**. It does not
use EXTRA. Other unsupported opcode/operand pairs remain immutable.

Allocation inserts a complete row before the retained table tail; original
blobs and original complete rows remain intact. Seeds must be imported rows,
not previously allocated/edited rows. Supported counts are at most 32768 rows
for messages, choices, stories, battle EXTRA, battles and rewards. Monsters are
conservatively bounded at 256 rows. A new monster takes a copy of its seed's 256-byte
Data DES description slot (the file grows by a slot when it has none). That is an editor support bound, not a claim
of the original engine's universal capacity.

New choices initialize only known programs/selectors 0..100 to zero; policy
bytes 100..104 and label slots are inherited. New stories initialize program
bytes 8..40 only. New rewards initialize item slots 0..80 to zero. Other new
rows clone the complete seed, then apply typed edits. No unknown headers,
policies, stamps, companion records or resource forks are synthesized.

The adapter remains JSON-lines protocol 1. Version 5 adds `authored_records`,
`authored_record`, `allocate_record`, `create_trigger`, `place_trigger` and
`author_connected_mission`. The read-only `search`, `uses`, `flow` and
`problems` operations answer navigation from the effective files. Mutations require `expected_revision`. Allocation,
linked recipe edits and trigger/gate changes validate before one atomic history
entry. Versions 1–4 still open with in-memory migration. Save creates an immutable
new checkpoint; failed operations leave the current state and visible drafts.

Authored links produce diagnostics with file/record/field/branch/step locations.
Dangling records, invalid ranges, inactive stage targets, missing companion
descriptions and unsupported ordinary-battle modes reject. Unrelated inherited
unknown steps are retained with warnings when reached by an authored link.

## Evidence and limits

The exact delivered project/export and build-bound receipts are listed in
`connected-delivery.md`. The default route is:

`walk (3,2) → new intro → choice → battle → explicit 25 credits → victory text
→ opcode 110/-2 → stage 1 (4,2) → new completion story`.

The decline branch shows a separate message and returns to exploration without
battle/reward. The reconstruction executes the real battle using normal turn
commands, without synthetic deaths or profile edits. The initial replay receipt
used a disposable Thunder-path alias. Subsequent
cross-project acceptance verified selection by the actual Micro Patrol name,
without Thunder replacement. Current save, desktop and authored-case evidence
is recorded in [authored acceptance](authored-acceptance.md). The runtime
reference remains read-only.

Bounded original instructions verify movement-gate behavior, choice branch
dispatch, battle ID selection/continuation, the full exported treasure-row load,
signed stage selection, new land coordinates and completion-story loading.
Choice input, combat outcome, treasure processing and presentation are explicit
services. The probe does not claim original battle simulation, currency
arithmetic or interactive completion. The known full-emulator TEXT/TEScroll
prologue limitation remains incomplete and was not reinvestigated.

Outside this slice: source-free construction, arbitrary retry/password policies,
generic conditional/EXTRA editing, new typed encounters, regional/object painting,
monster art editing, tactical terrain authoring, campaign completion and broad
gameplay compatibility.
