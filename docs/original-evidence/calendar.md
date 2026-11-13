# Calendar entries (Data TD3): what the original reads

The editor changes a byte only when the original 1.3.2 binary reads it. This note is the evidence for the 40-byte calendar record of
`Data TD3` (the table that code 54, Alter Calendar Entry, edits). It rests on the original's code, not on any scenario; the bytes in the
bundled scenario prove nothing about what the code reads.

Method: the decompilation of every routine that names the record's buffer (0x439d14), read against the instructions of the day-turn scan
(`timeclick`, 0x15e148, disassembled with Capstone from `code1-mapped.bin`, base 0x100000). Static evidence only.

## Every routine that touches the record buffer

| Routine | What it does with it |
|---|---|
| `timeclick` 0x15e148 | The day-turn scan (below). Reads offsets 0 to 21, writes back the whole record with only the day changed |
| `newland` 0x1400e4, code 54 | Reads record `n` whole, sets the chance (offset 4) when the given chance is 0 or more, sets the interval (offset 2) when the given interval is 0 or more, sets the day (offset 0) to today when "reset to today" is not 0, then adds "days to add" to the day when that is 0 or more; writes the whole record back |
| `encounter2` 0x12185a | A built-in test command, not scenario content: it rewrites record `n` as day tomorrow, chance 100, every test -1 |
| `load`, `resetgamefiles`, `fileprep`, `save` | Copy the file 40 bytes at a time into and out of the game's temporary copy |

No routine reads offsets 22 to 39. **They are padding** by the editor's rule. A new record writes zeros there; an existing record keeps its bytes.

## The scan (at the turn of a day)

The scan runs when the hour passes 24. The game's day counter is already incremented. It reads the temporary copy of the table one record at a time:

1. `d6` starts at -1. Each record is read (40 bytes at offset 40 x index); then `d6` is incremented and **a record is processed only while `d6` is at most 150**, so only records 0 to 150 are ever reached (151 of them). A table that is shorter simply ends: the read at the end of the file leaves the buffer as it was.
2. A record whose day (offset 0) is not today is passed over. If that day is 0 the scan ends: **day 0 ends the table.** A day of -1 (the bundled scenario's unused records) is never today.
3. On a due record the buffer's day becomes day + interval (offset 2, a word, wrapping) and the chance is tested: a draw of 1 to 100 (`Rand(100)`) greater than the chance (offset 4, signed) ends the scan after the write-back below. A chance of 100 always passes; 0 or less never does.
4. Item (offset 16): when above 0, some warrior must carry that item, else the same end.
5. Flag (offset 18): when 0 or more, that mission flag (0 to 127) must be set, else the same end.
6. Location (offset 20): 0 or less means no test and the entry passes. Above 1 means the entry is **passed over** (not rescheduled, not run). 1 requires the party to be on map `offset 8`; any other map passes the entry over. On that map: a region (offset 10, 0 or more) is a rectangle of the map's regions, tested with top <= row < bottom and left <= column < right of the party's cell; a column (offset 12, 0 or more) requires the party at that column and the row at offset 14 (a negative column ignores the row). Failing the region or the cell **passes the entry over**; the entry is not rescheduled. The rectangle is the one the region editor stores (first row, first column, last row, last column), but this test leaves out its last row and last column, where the region's own battle and story rolls include them.
7. An entry that passes every test, or that fails the chance, item or flag test, is written back with its new day; if it passed, the story with the number at offset 6 runs (`newland(script, 1)`; the story is a row of `Data ED3`) and, as the reconstruction reads the caller (not traced again here), the scan goes on with the next record when the story ends. If it failed, the scan ends.

Consequences for authoring:

- Order matters. The first due entry that fails its chance, item or flag stops the scan for the day, so every later entry is not looked at, and the draw is consumed for each due entry.
- A passed-over entry keeps today as its day, so it is never due again (until the day counter wraps). A location-gated entry gets one chance, on its due day, at the turn of that day.
- Records past the 151st are never reached.

## Seen in the original (dynamic)

A level built with `python tools/build_native_resource_level.py --kind calendar --messages` and run with `tools/run_native_resource_check.py --tail calendar` (`artifacts/p5-cal-run`, the game's memory read through the emulator harness) shows:

- A story that sets the clock to hour 24 of day 50 makes the game turn the day and scan the calendar for day 51.
- **Place.** Entry 0, due on day 51 at a cell the party was not on, ran nothing. Entry 1, due that day at the right cell, ran its story (its message appeared and the game waited for a click). The cell the game tested was **the party's world cell, which adds a step in progress**: the party stood on (3, 3) as the screen shows it and the game tested (4, 4), the sum of the map origin, the scroll and the signed bytes at 0x442736 and 0x442737. A calendar entry therefore names the cell the party is on or moving onto when the day turns.
- **Order.** When that story ended the scan went on: entry 2, due that day with chance 0, was read, rescheduled to day 58 (its record in memory held 58) and ended the scan; entry 3, due that day with chance 100, was never read and its story did not run.
- A scheduled story takes the place of the script that moved the clock: the trigger's own later step (a message) was not shown after the story ended.
- The template's switch-off of entry 0 (day 0) is an edit like any other; the Calendar page's entry 0 replaces it, because the editor applies it before the calendar entries.

Not seen: the item and flag tests, the region test, and the interval taking the entry to its next day (only the record in memory, 58, shows the new day).

## Difference found in the reconstruction

`scan_schedule` in the reconstruction (`crates/core/src/time.rs`) reschedules an entry whose region test fails and ends the scan. The binary (0x15e542 to 0x15e57c) clears the flag that would dispatch and passes the entry over without a write-back, exactly like a wrong map or cell. The map and cell tests agree.
