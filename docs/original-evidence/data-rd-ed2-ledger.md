# Regions (Data RD) and typed encounters (Data ED2): editor fields against the reconstruction

Both tables are joined by offset to the reconstruction's accessors (`RegionTable` in `crates/content/src/records/exploration_tables.rs`, the typed
encounter and menu views in the capability map), and to the Realmz structures `randlevel` and `encount2`. Every offset and width the editor writes
matches. The sources are static; none is a run of the original, and the capability map names no value domain for any of these fields.

## Regions: 644 bytes a map, twenty regions

| Editor field | Bytes | Accessor | Consumer | What the code does with the value |
|---|---|---|---|---|
| Rectangle (first row, first column, last row, last column) | slot x 8 + 0, 2, 4, 6 | `first_y` to `last_x` | `exploration/regions.rs` | The party's square is tested against it inclusively; an all-zero rectangle is an empty region |
| Encounter chance | 160 + slot x 2 | `encounter_chance` | `exploration/regions.rs` | A roll of 1 to 10000 is not above the chance divided by the caller's divisor, so values above 10000 matter when the divisor is more than 1 |
| Lowest and highest battle | 200 + slot x 4, +2 | `battle_minimum`, `battle_maximum` | `exploration/regions.rs` | A lowest battle of zero disables the battle; otherwise a random number from the lowest to the highest, both included. The range arithmetic wraps and does not require the lowest to be the smaller |
| Three stories | 280 + slot x 6 + event x 2 | `event_script` | `exploration/regions.rs` | Run when the event's percent roll succeeds |
| Three story chances | 400 + slot x 6 + event x 2 | `event_chance` | `exploration/regions.rs` | The magnitude is the percent, so 100 and above always succeed; a positive chance is cleared after it fires, so the sign tells a once-only story from a repeating one |
| Exclusive | 524 + slot | `exclusive` | `exploration/regions.rs` | Stops the scan of the lower regions |
| Avoidance chance | 544 + slot | `avoidance_chance` (a signed byte) | `exploration/regions.rs` | The party avoids a battle when a roll of 1 to 100 is below it: 100 avoids 99 times in 100, 101 and above always, below 1 never |
| Avoidance sound and dialogue | 564 and 604 + slot x 2 | `avoidance_sound`, `avoidance_dialogue` | `exploration/regions.rs` | The dialogue's magnitude is used |

Per map, outside the twenty regions (the scan of the loaded table at 0x443086): the tile set (520), read when the land loads and written by the land story code, edited as 1 to 9 or 15 to 19 because the loader quits the original for any other number without a property file; the sight limit (523), read by both drawing routines (`centerpictlarge`, `centerpictsmall`), edited; and the light level (522), written and compared only by `newland` and read by nothing that draws, so it is a stored byte (0 to 255) that only the story codes use, edited. Byte 521 has no reader.

Ranges now in the editor: encounter chance 0 to 32767, story chances -100 to 100 (every magnitude above 100 acts as 100, so the range is complete), avoidance chance
-128 to 127 (the whole byte; 101 and above differ from 100), battle numbers 0 and above.

## Typed encounters: 516 bytes

| Editor field | Bytes | Accessor | Range now in the editor |
|---|---|---|---|
| Physical result selector | 96 | `action_selector` | 0 to 4 |
| Password result selector | 97 | `password_selector` | 0 to 4 |
| Required actions | 98 to 105 | `required_actions` | 0 or 1 each |
| Spell and item selectors | 126 to 135, 146 to 150 | `spell_selector`, `item_selector` | as the selectors |
| Tries | 152 | `attempts` (a signed byte) | 0 to 127 |
| Dialogue | 154 | `dialogue` (12 readers) | 0 to 32767 |
| Nine labels | 156 + n x 40 | action and password labels | 39 Mac Roman bytes each |

The Realmz `encount2` has the same order up to the dialogue and no labels; the labels are New Centurions' own. The selector ranges are confirmed by the reconstruction's own refusal: a selector outside the four authored branches
reaches `finish_typed_selection` as an unrecovered dependency, a selector of 0 disables physical or typed input, and the fallback for a missed match is branch 4.

## What the scan of the encounters in play adds (the loaded headers at 0x443396 and 0x443432)

- **Typed encounter, byte 151.** `encounter2` reads it and lays out its controls at one of two widths; the Realmz `canbackout` is at the same place. The editor lists it as "Can back out" (any byte; zero is no).
- **Menu encounter, bytes 100 and 101.** `encounter` reads byte 100 for the same layout choice (`canbackout`), and `newland` copies byte 101 into the tries counter, the same count byte 152 gives a typed encounter. Both are listed now. The menu's dialogue (104) is edited as the choice prompt.
- **Tries** are signed bytes tested with `1 <`, `< 2` and `== 0`, so a negative value is handled and the editor allows -128 to 127.
- **The typed dialogue** is passed as the negative of its absolute value, so its sign does nothing and any word is accepted.
- Bytes 0 to 95 are the four branches' codes and story numbers, read by `newland` through the Scripts workspace; 106, 126, 136 and 146 are the spell and item criteria and selectors. The bytes between are not read.

## The battle record (Data BD, 1372 bytes)

Scanned at 0x43979c. The grid (bytes 0 to 1351) and the following words are read by `combatsetup`, `combat`, `getup`, `timeclick` and `newland`: the message before the battle (1352), the message after a win (1354), the squad's start column and row (1356, 1358; 0 to 25), **five stories run each round (1360 to 1369, read by `getup`; `newland` clears one, and `timeclick` reads the fifth)** and the greatest starting distance (1370, a signed byte rolled with `Rand`). The editor listed the first four and the distance but did not edit them and did not show the round stories; all are edited now. Byte 1371 is not read.

## Rewards (Data TD, 88 bytes), scanned at 0x44331c

`booty`, `encounter2` and `newland` read twenty item ids (words 0 to 19, bytes 0 to 39) and, beside them, twenty levels (bytes 40 to 79): an id above 0 goes into the loot and, with its level raised by the party's difficulty (at least 1), steers the random item that comes with it. Bytes 80 and 84 are the experience and the credits, long integers: a negative value is a random award, rolled up to its magnitude, and only a magnitude that fits a word is rolled as written (-32767 or more). The editor listed only the two awards (0 to 1,000,000) and kept the items as imported; it now edits the item and level of each slot and the awards over the range above. An item above 999 is refused, because `loaditem` leaves the previous item in place for it.

## Stages (Data Mission) and walking headers (Data DD)

The stage name, start map and start square (words 0, 2 and 4 and the name that follows) are read by `Displaymissionname` and the start story (byte 262) by `encounter2` and `newland`; the editor edits each. A walking header and a story record are the same 42 bytes, loaded by `loaddoor2` into the current record at 0x479eaa: the location key (0), the return destination (4 to 6), the chance (7), the eight operations (8), the eight operands (24) and the captured level (40). Byte 41 is not read. The editor edits all of them.
