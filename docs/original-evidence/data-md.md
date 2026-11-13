# Monsters (Data MD): what the original reads

This note holds what the static audit of the monster record has found. It is partial: the shop audit ([data-sd.md](data-sd.md)) is the standard, and
this one has not reached it. The levels are those of the shop note (static, dynamic, observed). Nothing here is dynamic yet.

Reproduce with `tools/native/AuditDecompileAll.java` (every routine of the Ghidra project to a folder of `.c` files) and
`python tools/audit_fields.py --decompiled <folder> --record <a monster record as the CLI prints it> --out <json>`.

## How the original keeps a monster

A definition is 288 bytes. A battle copies it, whole, into an array of fighting bodies (0x439d3c, 288 bytes each, indexed by body number minus 10);
`combatsetup` and `spelllist` copy a body to the build record at 0x440dbc and back with a long-word loop. The body keeps the definition's layout and
**overwrites parts of it as the battle runs**, so a byte that a routine writes may still be a defined field whose starting value the game reads.

Only 16 routines name either array: `attack`, `attack2`, `beast`, `bodycount`, `booty`, `buildmonster`, `buttonchoice`, `combatsetup`, `encounter2`,
`newland`, `resist`, `resolvedamage`, `resolvespell`, `spelllist`, `updatemonstermenu`, `updateodds`. Many more reach fields by the array's
address (`getup`, `movemonster`, `killbody`, `combat`, `checkforenemy` and others). The scan follows a field by its address, by a pointer built from the
array, and by an indexed access that starts at the field; it does not follow a record handed to another routine as a parameter.

## Findings

| Bytes | Editor field | What the original does | Level |
|---|---|---|---|
| 0x26 to 0x31 | Loot items (6 words) | `booty` walks all six; a nonzero word goes to `loaditem`, which loads definitions 0 to 999 only (see the shop note). The editor accepts 0 to 999 | Static |
| 0xa8 to 0xaf | Category (8 bytes) | `newland` (a story test), `getup`, `updateodds` and `spelltargets` index it by a category number minus one | Static |
| 0x8b to 0x90 | Saving throws (6 bytes) | `savevs` indexes it by the saving-throw kind; `resist`, `beast`, `combatupdate2` and `spelllist` read and change it | Static |
| 0x93 to 0xa6 | Natural attacks (5 x 4 bytes) | `getup` fills an empty attack slot from slot 0 up to half the attack count; `beast` and `showresults` read the slots | Static |
| 0xb0, 0xb1 | Mechanical, capturable | `checkformechanicalunits` treats 0xb0 equal to 1 as mechanical; `attack`, `bodycount` and `destroymonster` set it to 1 and to -1 during a battle, so it is a state with an authored starting value | Static |
| 0xb2 to 0xd9 | **Forty condition counters** | `getup` takes one from every counter above zero at the start of each round; `attack2` and `spelllist` set them; a cure sets them to zero. Eight bytes at 0xc2 were presented as "protection from scan level"; that name has no evidence, and the bytes are counters | Static |
| 0xda to 0xf7 | Name | `beast` and `updatemonstermenu` read it | Static |
| 0xf8 to 0x102 | | No routine names these bytes | Static (none found) |
| 0x103 to 0x11f | Not edited | Battle state (position, targets, status) that every combat routine reads and writes | Static |

## Withdrawn

- **Protection from scan level (0xc2 to 0xc9).** Part of the condition counters above, with no reader of its own. The editor no longer edits it as a field of its own;
  the bytes are conditions 17 to 24 of the counters it now lists.

## Reconciliation with the reconstruction

The reconstruction's capability map (`evidence/capability-map.json`) already lists each record field with its offset, width, type, the routines that read it
and the values that reach unrecovered behaviour. [data-md-ledger.md](data-md-ledger.md) joins it to the editor's fields and to the scan above. Both are static
evidence from the same decompilation; neither is a run of the original. The result:

- **44 fields agree** (same offset, readers in the map, and the scan reaches the bytes) and **39 are map only**: array elements the scan cannot follow (spell
  slots, attacks 2 to 5, saves 2 to 5, categories 5 to 8, loot items 3 to 6) and `movement`. The map reads the spell slots in `combat/spells/packets.rs`, so the
  earlier note that no routine names them was a limit of the scan, not evidence that they are unread.
- **One conflict: the name.** The map has it as a policy row with no readers; the scan finds `beast` and `updatemonstermenu` reading it.
- **Size is -3 to 3.** `movemonster` indexes a four-word footprint by the absolute value of the size and a sign test remains in the tile restore, so a negative
  size is a different value the original handles. The map blocks anything beyond that range. The editor allowed 0 to 3; it now allows -3 to 3.
- **The level is limited to 127 above** (`combatsetup` counts dice in a signed byte). The editor's other narrowings (level at least 1, stamina 0 to 30000,
  speed and movement 1 to 100) have no evidence for the lower bounds or the maxima; they stay until step 2 finds the consumers' bounds, and they are narrower
  than the original may require.
- **Fields the scan and the map list that the editor now exposes:** the weapon the monster starts with (0x4e, -9 or greater: -1 to -9 pick one of nine random weapon tables;
  `combatsetup` reads it before choosing and replaces it from the item list), the shield points (0x58), the bestiary-menu flag (0xa7, read by `updatemonstermenu`) and the forty
  condition counters at the start of a battle (0xb2 to 0xd9, signed bytes; `getup` counts the positive ones down, and `attack2` and `spelllist` do not add to a negative one).
- **Overwritten at battle start, so padding:** 0x82, which `combatsetup` sets to zero before `combat` reads it.
- **Cross-record effects the map flags:** a monster's first item (0x26) is its primary weapon, and a firearm whose item spell word is below 1101 takes a fallback
  that reads the combat loop register, so the editor should warn when a monster carries one.

## Value domains for the statistics

Read in `combatsetup` (static):

- **Level (0x00).** Counts the stamina dice in a signed byte that wraps at 128, so a level above 127 never ends the loop. A level of 0 or below rolls no dice. The editor allows 0 to 127.
- **Base stamina (0x02).** Added to the dice (1 to 8 each) in a word with no clamp on that path, so the sum must stay under 32,767. The editor keeps 0 to 30,000, which is safe for any level.
- **Speed (0x04).** Raised or lowered by the random roll and then made at least 1. The editor allows 1 to 32,767.
- **Armor (0x08).** Adjusted the same way and made at least 0, so any negative value acts as 0; the editor already allows the whole word.
- **Movement (0x06).** Cut to a signed byte when the battle starts, so only 0 to 127 means what it says. The editor allows 0 to 127.

- **Cast and missile percent (0x42, 0x48).** A roll of 1 to 100 is compared with the value (`<=`) and the value is also tested against zero, so a negative value is
  a different case from zero (the monster tries but never succeeds) and a value above 100 acts as 100. The editor allows the whole word.

## Spell slots (0x12 to 0x25)

The reconstruction's `select_packet` (`combat/spells/packets.rs`) is the reader: a monster picks one of its ten slots at random, up to 30 times, and takes the
first pick whose value is above 1100. A value of 1100 or below is not a spell, whatever it is. A larger value is a descriptor: the thousands digit less one is the
school, the hundreds digit less one the level, the units digit less one the index, and the three index the spell packet table at 2842, 406 and 58 bytes, so a
descriptor that decodes outside the table is refused. The editor accepts any value up to 1100 as an empty slot and checks the digits of a larger one (school 1 to 4,
level and index 1 to 7). The scan above did not see this reader because it reaches the slots through the record's accessor, not by address.

- **Sounds (0x6a, 0x6c) and the shield chance (0x56).** `sound` takes any word (see the item ledger); the shield chance is capped at 95 when rolled. The editor allows the whole word for each.

## The bestiary menu

The game reads `Data MENU` first and builds it from the monsters' names when the file is missing (`updatemonstermenu`; the reconstruction's `bestiary-work.md`
gives the order). A scenario that renames a monster or adds one must not keep the old file, or the menu shows the old order and omits the new monster. The
Divinity manual says its editor deletes the file on every visit for this reason. The editor now removes `Data MENU` from the exported scenario when a
name, a hidden flag or the number of records differs from the import.

## Padding

The bytes 0xf8 to 0x102 and the counters' starting values are not authored by the editor. A new monster row is made by copying an existing definition, so
the padding is whatever that definition holds. Every byte the original reads is a field the editor shows, and the rest are not read, so any fill is
equivalent; the copy keeps the new row identical to an authored one.

## Open

- A dynamic run of `booty`, `getup`, `beast`, `savevs` and `spelllist` on an authored definition.
- The bounds of the numeric fields beyond the statistics: percents, sounds, icons and the rest keep the reconstruction's ranges.
- The offset 0x10, which `cast` passes on as a spell argument although the map and the editor treat it as the size.
