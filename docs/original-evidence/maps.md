# Maps (Data LD, Data DD, Data RD): what the original reads

Static evidence from the decompilation of `resetgamefiles` (0x14f96e), `loadland` (0x13107a), `saveland` (0x151e24), `save` (0x152378) and from
the reconstruction's reading of the drawing and movement routines. Observed means seen in the bundled scenario, which is consistency only.

## A map is three records, one count

A map ("land") is one record in each of three scenario files, and the game keeps them together:

| File | Bytes per map | Held by the game as |
|---|---|---|
| `Data DD` | 4200 (100 rows of 42) | the walking-story headers |
| `Data RD` | 644 | the regions and the map look |
| `Data LD` | 64800 | floor (8100 words), objects (8100 words), event cells (8100 longs), at index `x * 90 + y` |

`resetgamefiles` builds the game's temporary land file by looping until the read of a 4200-byte `Data DD` record fails: **the number of maps is
the number of `Data DD` records.** For each it reads one record from `Data RD` and one from `Data LD`, adds the 8100 bytes of cells the party has seen, and writes
77,744 bytes (0x12fb0). `loadland(n)` seeks `n * 0x12fb0`; `saveland` and `save` copy until the end of the file. A shorter `Data RD` or `Data LD` is not detected: a failed
read leaves the buffer holding the previous map, so every file must hold the same count. Nothing in these routines caps the count.

Limits that do apply: the walking row keeps its map as a signed byte (at most 127), and the reconstruction's own loaders and save format assume at most 20 maps per level. The
editor therefore keeps its limit of 20 maps per level; it is the editor's limit, not a found one, and it is recorded here so that it can be lifted with the reconstruction.

## Resizing and removing a map

- **Resize is not possible.** Every array of a land is read and written at a fixed size: 8100 cells of floor, objects and events, 8100 bytes of seen cells, 100 walking rows, 644 bytes of regions (`loadland`, `saveland`, `resetgamefiles`). A smaller map is a map whose outer cells are walls or the hidden tile.
- **Remove.** Only the last map can be removed, because the walking keys, the stages, the steps and the calendar all name maps by number. The editor refuses while anything names the map (stages, the opening, other maps' triggers that return to it, calendar entries, steps whose codes take a map) and when `Data DD` or `Data RD` hold a record beyond the maps, since the game counts a map for every `Data DD` record. The bundled scenario names an eleventh map in one step, so its last map cannot be removed.

## Event cells and walking rows

An event cell is a long. In the bundled scenario its values are 0, -1 or the key `map * 10000 + y * 100 + x`, with a few stray values that the editor keeps.
The walking row that the key names stores the same key at offset 0 (an unused row stores -1). Observed: every key in a map's cells carries that map's number.
A copy of a map therefore changes the map number inside its keys, in the cells and in the rows, and copies every other value as it is.

## The object layer (static)

The object layer is drawn after the floor (`centerpictlarge` and `centerpictsmall`) and is never read by movement or sight:

- A positive value is a **building**: `centerpictlarge` hands `value + 23000` to `fastplot`, which draws the picture (PICT) with that number, anchored at the cell's bottom-right corner and spilling up and left, so the picture is 23000 plus the value and a missing one draws nothing. No positive value draws a tile from the terrain sheet.
- A negative value is drawn as the icon (cicn) of its magnitude, after the land's background tile when the value is above -500.
- Cells the party has not seen are drawn as the blank tile in every pass.
- The game reads the layer past the floor's last row as a linear array when it sweeps for sight; that is an overrun of the original and no part of authoring.

Observed in the bundled scenario: positive values up to 353 (the scenario holds pictures 23350 to 23354) and negative values from -3001 to -3091 (icons).

## Secret cells: floor values above 300 (static, and a level run in the original)

The game keeps Realmz's search for secrets, and nothing else of Realmz's secrets:

- `checkforsecret` takes the absolute value of each floor cell around the party; one above 2999 is revealed when `Rand(100)` is not above the party's search skill, by taking 1000 off it (toward zero) and flashing a line of `STR#` 138 ("You have found a secret area to the north", one line for each of the nine squares).
- Nothing draws the thousands. `centerpictlarge` and `centerpictsmall` copy tile `value - 1` from the 20-per-row terrain sheet, so a value above 300 copies from outside the sheet and draws nothing; `fastplot` is the only routine that strips 1000, and the floor pass does not use it. There is no marker for a found secret (Realmz draws one) and no tile for a hidden one.
- Walking reads the tile's own properties only for 1 to 200: a magnitude above 200, or any negative value, uses the map's own tile (`DAT_00402f43`). The thousands change nothing about where the party can walk, so a secret path cannot be told from any other cell, and a found one stays as it was. `cansee` reads 1000 and up as the tile `value - 1000` for sight. Story code 59 only folds the value into -999 to 999.
- Realmz's secret action point (an action point that the party must find first) has no counterpart: an event cell is entered whatever the floor holds.

Seen in the original (`python tools/build_native_resource_level.py --kind secrets`, `artifacts/p7-secrets-run`): the cells around the start numbered 1012, 2012, 3012, 3150 and -3012 were drawn as black squares, except 2012, which showed a leftover picture of the memory the game had not cleared; the cell numbered 12 drew its tile. The editor offers the marking as the game reads it, and says what the game does with it: the Cell tab of the Maps page has the states Normal, Hidden secret (3000 added to the floor number) and Revealed secret (2000 added, what a search leaves), and the Secret cells overlay marks them on the map (a big S over the cell's own tile, red for a hidden one and orange for a revealed one). A secret entrance is a walking trigger on a hidden cell, since a trigger fires whatever the floor holds. The Problems list names the maps with a cell from 301 to 1999, which no marking explains, and where the first one is.
