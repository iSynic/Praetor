# Centurions format and support map

All multi-byte numbers below are signed big-endian unless stated otherwise.
Evidence is reconstruction source/control flow, independently tested here for
serialization. It is not a live original-binary compatibility claim.

Inputs are extracted **scenario-level folders** such as
`Scenarios/The Thunder of Guns/0`. Import/export is a generic folder envelope:
every supplied file, resource/metadata sidecar, nested directory and unknown
name is preserved. Native HFS volumes, archives, OS extended attributes and
alternate data streams are outside this envelope; extract them to explicit
sidecars first. Links and reparse points are rejected.
There is no scenario hash allowlist.

| Family | Centurions geometry / evidence | Current authoring support |
|---|---|---|
| `Data CS` | Opening map at 8, x at 12, y at 16: i32. `mission.rs::OpeningMission::read/read_level`. Shipped size 316 is an observation, not a schema. | Opening coordinates/map overlay; other bytes opaque. |
| Scenario-named header | Original `setupnewgame` opens the selected menu item's name under the selected level. First 20 bytes are five i32 values, followed by two 20-byte blocks. The supplied named header and `Data CS` are byte-equal. | Native startup identity is explicit in version 2. Copy the template header/sidecar under the new name; opening edits overlay 8..20 in both views. Other bytes remain opaque. Native `Displaymissionname` then supplies the final stage-zero location. |
| `Data Mission` | 464-byte rows, i16 x/y/map at 0/2/4; Pascal name length 6 and payload 7..262; i16 start script 262. `mission.rs::read_level`. | Stage name/start location and start-story ID (0 means none). Remaining bytes opaque. |
| `Data LD` | 64800 bytes per 90x90 map: 8100 i16 floor, 8100 i16 object, 8100 i32 event cells; native index `x*90+y`. The editor accepts 1..20 maps ([maps.md](original-evidence/maps.md)). | Read map projection; floor cells, the object layer (`Edit::MapObject`: a positive value is the building picture 23000 plus it, a negative value an icon), bounded walking activation gates, and adding a map (`Edit::AddMap`, which also adds its `Data DD` and `Data RD` records). Walking/region overlays are separate projections. A floor number above 2999 is a cell hidden until a search finds it (the Cell tab's Secret box); one from 301 to 1999 is reported by the Problems check ([maps.md](original-evidence/maps.md), "Secret cells"). |
| `Data DD` | 4200 bytes/map = 100 x 42-byte walking story rows. Key i32 at 0, map/x/y/chance signed bytes at 4..8. | Walking markers and eight-slot step editor for supported operations. Create/place/move/disable/remove within fixed slots, coupled map activation, and level-0 return destination; stamp remains read-only. Minimal candidate disables starting-map keys using -1 while retaining all action/unknown bytes. |
| `Data ED3` | 42-byte stories; 8 i16 opcodes at 8..24 and 8 i16 operands at 24..40; level byte 40, dispatch stamp 41. `records/story.rs`, `story_destination.rs`. | Eight-slot step editor for supported Centurions operations; header, byte 40/41 and unsupported pairs retained read-only. No generic raw editing. |
| `Data RD` | 644 bytes/map; 20 rectangles 0..160; encounter chances 160..200; battle min/max 200..280; script IDs 280..400; chances 400..520; terrain byte 520. `records/exploration_tables.rs`; also exclusive flags at 524, avoidance chance at 544, avoidance sound at 564 and dialogue at 604. | Rectangles, encounter chances, battle ranges, event stories and chances, exclusive flags and avoidance fields are edited per region (`Edit::Region`, project version 6); only the region's own bytes change. The map's tile set (1 to 9, 15 to 19) and sight limit and light level are edited per map (`Edit::MapLook`, bytes 520, 522 and 523); minimal candidate zeros starting-map regional activation fields only. Unknown/remaining bytes retained. |
| `Data MD2` | 340-byte map notes: ten marks (icon, column, row) at 0, section start 60 and 62, land 64, picture 66, cell size 68, text number 70, picture size 80 and 82, words (Pascal) at 84; words 72 and 74 and the bytes after the words are never read. [notes.md](original-evidence/notes.md). | `Edit::MapNote` (notes 0 to 18; a note just past the last adds one) and the Notes page, with a preview of the window; unread bytes kept. |
| `Data SD2` | 256-byte Pascal Mac Roman rows. `mission.rs::StoryTables::dialogue`. | Strict Mac Roman message editing, maximum 255 encoded bytes; only length and new payload owned, unused suffix/tail preserved. |
| `Data ED` | 426-byte menu rows; eight signed-byte opcodes per branch, four branches; i16 operands. `core/src/story.rs`. | Four eight-slot branch editors for supported operations. Choice selectors, prompt ID and four Str79 labels editable; unresolved policies retained. Template-derived allocation supported. Shipped 24-byte fragment retained. |
| `Data ED2` | 516-byte typed encounters; selectors signed bytes, header 156 followed by nine 40-byte labels. `records/typed_encounter.rs`. | Four eight-slot branch editors for supported operations. Supported physical/spell/item conditions editable; password/retry policy, dialogue and nine labels read-only; no Realmz encounter compatibility. |
| `Data EDCD` | 10-byte extra records; interpretation depends on opcode. `records/story*.rs`, route inspector. | Typed ordinary-battle EXTRA for opcode 2 only; other interpretations unresolved. |
| `Data TD3` | 40-byte calendar records, 151 reached; offsets 0..21 are the eleven words the scan reads, 22..39 padding. Day 0 ends scan. See `docs/original-evidence/calendar.md`; authored by `Edit::CalendarEntry` and the Calendar page. | Every entry field the scan reads (`Edit::CalendarEntry`); a slot just past the last adds an entry; bytes 22..39 kept. The minimal candidate sets the first day to 0 only. |
| `Data BD` | 1372-byte battle rows. `combat.rs`. | See bounded field support in connected-authoring.md; all other bytes preserved. |
| `Data MD` | 288-byte monster rows. `combat.rs`; `records/monster.rs` for the definition fields. | The name, stats, drops, stories, spells and the definition fields of `monsters.rs` (icon, size, side, flags, armor, immunity, dodge, accuracy, damage, attacks, victory points, shield, psi, behaviour percents, sounds, saves, categories, protections, carried items, credit bound); all other bytes preserved. |
| `Data TD` | 88-byte treasure rows. `records/story_effects.rs`, `exploration_tables.rs`. | See bounded field support in connected-authoring.md; all other bytes preserved. |
| `Data SD` | 3002-byte shops: 1000 item ids, 1000 quantities, price percent at 3000. `records/shop.rs`. | Stock slots (stocked when the quantity is not zero) and the price percent; all other bytes preserved. |
| `Data NI` | Runtime reads first 200 x 150-byte item records (scenario IDs 800..999); shipped file is larger. `content/src/lib.rs`, `mission.rs`; `records/item.rs` for the fields. | The definition fields of `items.rs` for the first 200 rows; **all** other supplied bytes, extra rows and the tail are preserved. |
| `Data NI Des`, `Data NID`, `Data DES` | NI Des / creature descriptions read in 256-byte strings; `Data NID` not established by cited loader. | `Data NI Des` descriptions are edited as length-prefixed Mac Roman text (255 bytes); `Data DES` is a Pascal string of at most 255 bytes in a 256-byte slot for each monster, edited by `Edit::MonsterDescription` (the Archives page shows it); a new monster gets a copy of its seed's slot. `Data NID` is preserved, no inferred alias. |
| The monster vault | Not a file of the game. Stock monsters are read from the `Data MD` of each level of the installation's scenarios and never saved or removed; the monsters the author adds are kept beside the editor's settings file (`centurions-monster-vault/vault.json`). Each entry is the 288 bytes of a `Data MD` row, its description and, when a resource file holds it, the picture of its icon. | `Edit::MonsterImport` writes a whole row and its description after the row's allocation, and replays before the author's other edits of the row; a copy imports the icon's `cicn` too, under the next free number when another picture holds the number. |
| `Data MENU` | Optional exact 502-byte bestiary order, nonzero u16 values map to index value-1. `content/src/lib.rs`. | Preserved; removed from the export when a monster name, hidden flag or the record count changes, so the game builds a new one. |
| `Scenario.rsrc` | Loader reads scenario `TEXT` (including prologue 1000), `STR#` -101/-102; `STR#` 801 holds the names of the scenario items 800..999; `STR#` -101 and -102 the Maps and Notes labels (notes 1 to 19); `STR#` 802 is read by nothing. Original Mac resource chain remains authority. | A resource-fork writer keeps every entry it does not change: scrolling texts (`TEXT` with `styl`), pictures, icons and sounds imported from PNG and WAV files, item names (`STR#` 801), note labels (`STR#` -101, -102). Other types are preserved. |
| `Scenario`, `Global`, `Layout`, `Data CI`, `Data RI`, `Data Solids`, `Data Scan` | Names and bytes observed, only partial or unresolved semantics. | Preserve-only; never populate defaults from Realmz. |
| `*.rsrc`, `.finf`, `._*`, arbitrary other files | Container sidecars and unknown data. | Preserve exactly, including nested paths and empty directories. |
| Installation `Data Files/*` | Stock items/races/MOS/attacks, tutorial, tile properties/media. `mission.rs`, `tile_sets.rs`. | External read-only dependency, not bundled into a scenario. |

## Ownership and failure behavior

Unchanged export copies immutable source blobs, independent of decoding success.
Edits carry typed identities and are revalidated on reopen, then overlay only
their declared byte ranges. Original blobs remain intact. An unsupported edit,
short record, unknown version, corrupt blob, path traversal, collision, link,
or unsafe output destination fails before publication. Warnings for unresolved
tables and fragments are inspectable, never normalized away. No arbitrary patch
command is exposed.

## Minimal candidate boundary

No source-free bootstrap is claimed. A minimal candidate starts from a successfully
round-tripped imported level. It authors one named starting stage and a quiet
opening map, disables other stage names, starting-map walking triggers/regional
activation and the schedule scan. It retains all original maps, support tables,
resource forks, unused fields and dormant content. Inherited global hooks,
prologue and other unresolved bootstrap data remain explicit limitations.
It is a new local scenario candidate, not an asset-free or certified playable
scenario. Original-binary loading and playtesting are required before promotion.

Bounded original startup now passes with a controlled Mission menu binding; see
[the exact proof and remaining gates](native-startup-validation.md). Native staging
uses DD rows and can retain an additional temporary map beyond the LD count.
No extra imported row is removed or normalized because of that discrepancy.

## Native editor milestone

The Godot workbench exposes the same message, stage-name/start, header-opening,
and floor-cell overlays through the Rust session adapter. Existing inactive
stage rows may be named; no additional native rows are allocated. Construction
operations such as clearing startup scripts and disabling schedules remain
reserved for the gated template command. Unresolved fields stay read-only; supported script pairs and template-derived allocation are documented in [script support](script-support.md) and [connected authoring](connected-authoring.md).

Original tile artwork is a derived view, not project truth. Centurions resource
lookup and 32-pixel atlas indexing are checked separately from floor serialization.
First Patrol now reaches original-application exploration at map 0 (2,2), while
the inherited TEXT prologue remains incomplete. See the
[current evidence report](native-editor-validation.md).

## Remembered artwork and script updates

Project version 3 adds existing fixed-slot script edits. Versions 1/2 remain
readable. The exact byte spans, supported operations, signed icon lookup and
limits are documented in [script support](script-support.md). Preferences and
derived artwork remain outside project truth.

## Version 5 connected authoring

[Connected authoring](connected-authoring.md) specifies allocation limits,
initialization and every new owned byte span. Messages, choices, stories,
ordinary battle EXTRA, battles, monsters and rewards can be allocated from
imported seeds. The original movement caller requires a positive LD event cell;
map markers now distinguish this from direct newland lookup eligibility.
Version 4's lookup-only conclusion was incomplete; the corrected caller proof
and existing independent condition cases remain reproducible.
