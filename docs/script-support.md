# Centurions trigger, encounter and special-floor support

The original application remains behavior authority. `script-provenance.json`
pins consulted native decompilation and provisional reconstruction views. This
is Centurions geometry; no Realmz AP, encounter or opcode compatibility is used.

## Existing program editing

All programs have eight fixed slots. The UI numbers steps 1–8; the adapter uses
slots 0–7. Choice and typed programs have four branches, numbered 0–3 in the UI
and protocol. These are program branches, not a claim that each visible choice
dispatches directly to the same-numbered branch: selectors have an independent
mapping. Supported condition editing is described below.

| Family | Native file / record stride | Owned bytes for slot s and branch b |
|---|---|---|
| walking | Data DD / 42; 100 records per map | i16 opcode at 8+2s, i16 operand at 24+2s |
| story | Data ED3 / 42 | i16 opcode at 8+2s, i16 operand at 24+2s |
| menu | Data ED / 426 | signed byte opcode at 8b+s, i16 operand at 32+16b+2s |
| typed | Data ED2 / 516 | signed byte opcode at 8b+s, i16 operand at 32+16b+2s |

Offsets are relative to the record; all multi-byte numbers are big-endian.
The typed table uses its on-disk 516-byte stride, independently of the original
runtime's separate menu-replacement stride behavior. Existing row edits retain table size. Version 5 allocation inserts complete seed-derived rows before retained tails; see connected-authoring.md. No trailing fragment or unused suffix is normalized.
Walking rows outside the native map count remain inspect-only.

Authorable operations are deliberately bounded:

| Opcode | Native operation | Operand validation |
|---|---|---|
| 0 | Continue / empty slot | UI retains operand |
| 1 | Show message through textbox | Magnitude must name an existing Data SD2 row |
| 2 | Ordinary battle | Existing typed battle EXTRA row; supported modes 0/5 |
| 10 | Explicit reward | Existing Data TD row |
| 14 | Pick party members | Positive count 1..6; native getchoice supplies the actual selection dialog |
| 100 | End combat and process ordinary rewards | Operand 0 only; no reward-table reference |
| 110 | Stage transition | Signed one-based stage; magnitude 1..20, negative skips confirmation |
| 4 | Choice encounter | Nonnegative existing Data ED row |
| 5 | Typed encounter | Nonnegative existing Data ED2 row |
| 9 | Play sound | Nonnegative signed i16 resource ID; availability is not promised |
| 24 | End script | UI retains operand |
| 39 | Replace program from story | Nonnegative existing Data ED3 row |
| 48 | Selected-party battle | Existing selected-battle EXTRA row; its fifth word is an optional Data TD reference |

`newland` at 0x1400e4 supplies the operation switch: message at case 1, choice
case 4, typed case 5, sound case 9, end case 0x18 and story replacement case
0x27. Native branch dispatch sign-extends each stored opcode byte and copies
the corresponding eight i16 operands. This prevents a generic i16 story view
from being applied to byte-wide encounter branches.

Case 100 at the native 0x14131e call clears COMBAT and passes the stored WORD
operand multiplied by two to `booty`, with its second argument zero. Operand 0
therefore selects ordinary reward mode 0; it does not name Data TD row 0. Only
this operand is currently authorable. Other imported opcode-100 operands remain
read-only. The GUI selects zero automatically; CLI/API reject nonzero values.
This is recovered authoring support, not original-runtime acceptance of a new
cleanup or callback path. Imported opcode 125 remains preserved and read-only.

CLI/API edits `monster_turn_story` own the signed chance WORD at monster offsets
0x5c..0x5d and story WORD at0x5e..0x5f. Chance is bounded to -100..100; the story
must exist, including story0. Native Getup at126938..126a18 uses these fields for
its accepted general turn macro. `selected_battle_extra` owns the five existing
EXTRA WORDs for opcode48: battle minimum/maximum, sound, message and optional
treasure. This separate edit keeps the ordinary-battle fifth-word mode meaning.
Opcode48's wrapper at14551c..1456f0 has its own reward calls; authoring does not
establish the runtime's nested callback return or original-game fidelity.
Script links may also target an imported EXTRA with a fixed negative battle ID
and zero maximum. Its magnitude selects the battle; the runtime route uses its
sign for enemy surprise. The complete signed EXTRA row remains preserved.
Negative variable ranges and newly authored negative battle fields remain
unsupported. This reference support does not establish new native acceptance.
Opcode14 calls getchoice with count minus one at the original newland14 arm.
Its positive count1..6 form is authorable through CLI/API. Other imported
operands and the inverted negative opcode remain preserved and read-only.
This lets a selected battle receive actual picked members through production
ChooseWarrior commands, instead of inheriting an empty selection mask.

CLI/API edits `monster_retreat_threshold` and `monster_death_story` own only
the signed monster WORDs at0x44 and0x60 respectively. Getup's morale check
sets Retreating when the threshold exceeds100; the separate removal chance
WORD at0x46 is preserved. A nonzero death-story ID must name an existing story;
zero disables it. These fields permit an original dialogue to observe a
movement reaction return. They do not establish original callback timing or
authorize editing preserved unsupported story operations.

CLI/API edit `monster_spell_slots` owns ten signed spell-ID WORDs at monster
offsets0x12..0x25. The original picker at114856..11487c samples indices0..9.
Each slot accepts0 (disabled) or a canonical original packet ID: school1..4,
level1..7 and spell1..7 in the thousands/hundreds/final-two-digit fields.
Numeric holes such as2308 are rejected. The installation-wide DataS table is
neither imported nor changed; chance, attempts, AP and other monster fields
remain preserved. Untouched imported slot values are not normalized. This
authoring support does not establish runtime support or native cast fidelity.

An imported unsupported opcode/operand pair cannot be edited or replaced. Version 5 adds the bounded battle/reward/stage operations above. Other EXTRA
interpretations and unsupported operations remain preserved. Choice prompt,
labels, walking return/activation and new row allocation use the typed forms
specified in [connected authoring](connected-authoring.md). Regional conditions,
objects, passwords and retry policies remain read-only.

Apply uses the same revision check, atomic batch validation, undo/redo and
immutable save/export machinery as floor and message edits. Project version 4 adds condition and walking placement overlays; version 3
added `script_step`. Versions 1/2/3 remain readable. All original source blobs are
retained. The GUI's linked-record buttons pass through the existing draft guard.

## Map projections

Walking keys decode as map*10000 + y*100 + x. Markers include placed nonempty
headers, with native chance and event-cell values available on selection. Cyan indicates a first matching positive-chance header with a positive LD event
cell, required by the ordinary movement caller. Later duplicates are shadowed
even when the first chance is zero. Direct newland lookup does not check that
gate; version 4 incorrectly generalized the lookup-only proof to the caller.
Multiple headers at one cell share a marker and
remain separately selectable. Double-click opens the first header; the cell
dropdown exposes all headers.

Data RD rectangles use first_y, first_x, last_y, last_x at 8-byte strides.
Encounter chances are at 160+2r; battle min/max at 200+4r/202+4r; three story IDs
at 280+6r and their chances at 400+6r. Regions can be outlined and selected for
read-only conditions and story links. There is no inferred single encounter
object placed on a square: regional scripts may invoke choice/typed encounters.

## Special floor icons

`fastplotmap` at 0x134d9e draws a negative floor ID over the terrain's default
floor, then passes its signed ID to `ploticon3` (0x14a02c), which calls GetCIcon,
PlotCIcon and DisposeCIcon. The main map presentation at 0x10f1c4 similarly
handles nonpositive floor IDs. Positive atlas IDs are indexed from 1 in a
20-column, 15-row, 32-pixel PICT atlas selected by terrain+299.

The default i16 floor comes from the native terrain BD property file. Standard
terrain property names follow `tile_sets.rs`; custom terrain 15–19 resolves a
single scenario `* BD` file, otherwise reports unresolved. Resource lookup is
scenario fork, Cargo Pod fork, application fork. Malformed or ambiguous
overrides fail instead of falling through. Icons are decoded only for signed
IDs used by the selected map, with audited 32x32 geometry and mask alpha.
Unavailable icons/default floors keep explicit diagnostics and placeholders.
The palette lists resolved special icons for that map underneath the atlas.

The generic cicn raster routine is adapted under GPL-3.0-or-later from the same
pinned Centurions graphics input as PICT decoding. Native resource identities,
terrain lookup and overlays are editor-specific. Cached PNGs are derived data;
source forks and tile values are unchanged. Positive object/building rendering
has different native lookup rules and is not silently treated as floor artwork.

## Evidence limits

Rust tests cover signed opcode widths, asymmetric coordinates/masks, record
strides, unknown pairs, rejected batches, stale revisions, undo and checkpoint
reopening. The real Godot workflow edits all three table geometries and compares
every exported byte independently, including unknown files and fragments. A
fresh second application process verifies remembered installation and automatic
artwork on project open. Rendered captures exercise both supported window sizes.

These checks do not prove a complete original-game playthrough of newly authored
programs. First Patrol's exact unchanged export retains its separately recorded
startup evidence; the inherited prologue display gate remains incomplete.

## Version 4: native-verified conditions and placement

See [the field investigation](trigger-field-investigation.md) for exact native
instruction boundaries, known fields, unresolved spans and reproduction commands.
The native probe executes eight walking lookup cases and ten encounter condition
cases without instruction patches. Only audio and deterministic random replies,
and one explicit spell-definition lookup, are hosted services.

Maps → Place trigger uses a selected existing slot 0–99 in the selected map.
It owns only that header's four-byte location key and one-byte chance, as one
undoable edit. Collision detection rejects another header at the destination;
new rows are never allocated. The original program, return destination, level,
stamp, unknown bytes and the entire Data LD file remain untouched. Moving a key
retains any authored return destination, which may cause travel when it runs.
Chance zero disables; the authorable percentage range is 0–100.

Conditions exposes choice selectors 0–4, typed physical selector 0–4, eight
required-action flags 0/1, ten spell criteria/selectors and five item
criteria/selectors. Program selectors 1–4 dispatch branches 0–3; selector zero
hides/disables the relevant UI path. Imported values outside the supported
ranges remain read-only. Password behavior, retry count, labels and remaining
bytes are inspected/preserved. Spell/item criterion IDs are numeric matching
criteria; editing them does not promise the installation contains that item or
spell. The first spell/item alternative gates its native UI even if later
alternatives are nonzero. Physical matching requires an exact nonempty set,
including rejection of extra selected actions; failure returns selector 4.

Battles & monsters supplies searchable read-only native views. Data BD rows
are 1372 bytes with a 26×26 signed monster population array at 0..1352 indexed
x*26+y; they are not saved tactical terrain. Negative IDs invert the loaded
faction in the native setup caller. Data MD uses 288-byte definitions, with a
Pascal Str29 at offset 218. Known basic fields and full retained hex are shown.
Double-click a population marker for its monster definition. This does not
simulate random placement, combat, or reconstruct native graphics.
