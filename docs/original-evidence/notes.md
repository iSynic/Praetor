# Map notes (Data MD2): what the original reads

Static evidence from the decompilation of `showmap` (0x134e82), `fastplotmap`, `updatemapmenu` (0x13b212), the Maps and Notes arm of `HandleMenuChoice` and `newland` code 29, read against the
reconstruction's source notes for the same routines; a level run in the original (below) is the dynamic evidence.

## A note and its number

Code 29 with operand `n` (its magnitude) sets note flag `n` (a byte array of 19, at 0x442722), rebuilds the Maps and Notes menu and, when the operand is below 0, shows note `n` at once. The menu
shows note `n` as item `n + 4`, and its label is string `n + 1` of `STR#` -101 (the note is not yet held; the item is disabled) or `STR#` -102 (held; enabled). Choosing the item calls `showmap(n)`.

- Notes are numbered **0 to 18**. A flag number of 19 or more writes past the array into the game's own variables (the byte after it is the party's step in progress), so the editor refuses a note above 18 and warns of a step that names one.
- Note 0 cannot be shown at once (-0 is 0), but it is held and shown from the menu like the others.
- The Notes page numbers a note as the operand of code 29 does (0 to 18); `Edit::NoteLabel` numbers the same note from 1 (the string of the lists), so note 0 is label 1.

## Seen in the original

A level built with `python tools/build_native_resource_level.py --kind notes` and run with `tools/run_native_resource_check.py --tail notes` (`artifacts/p6-notes-run`): a trigger gives note 0 (a section
of map 0 from (0, 0) with a mark of icon 137 on cell (3, 3), cells of 32 pixels) and shows note 1 (picture 23010) at once.

- Note 1: the game drew the picture in the middle of the 320-pixel window ((320 - 128) / 2 across, (320 - 96) / 2 down), put the note's words in the message area and waited for a click in a "Click Mouse" box.
- The Maps and Notes menu then listed both notes with their second labels, enabled and ticked, as the labels were authored.
- Note 0, chosen from the menu: the section of map 0 in the window, the mark on cell (3, 3), the words in the message area and the click box.
- A text window (a text number) was not run.

## The record (340 bytes, read at `n * 340`)

| Offset | Width | Meaning |
|---|---|---|
| 0 to 59 | 10 marks of (icon, column, row), words | The icon (a `cicn`; 0 is an empty mark) and the cell it stands on, counted in note cells from the section's top-left corner; drawn only for a map section |
| 60, 62 | words | The column and the row of the map where the section starts |
| 64 | word | The land (map) the section is taken from |
| 66 | word | A picture (`PICT`) shown instead of a section; 0 shows the section |
| 68 | word | The side of one note cell in pixels; the section is `320 / size` cells across (one more when that does not reach 320). A size of 0 divides by zero in the original |
| 70 | word | A text number: when it is not 0 the game plays the scrolling-text window of that `TEXT` and shows nothing else |
| 72 | word | Never read |
| 74 | word | Never read |
| 76 to 83 | 4 words | A rectangle (top, left, bottom, right) for a picture: when the bottom or the right is not 0 those two replace the picture's own size; the top and the left are overwritten by the centring |
| 84 | Pascal string | The words shown in the note's dialog (at most 255 bytes); not shown for a text window |

The order is: a text number, else a picture, else the section; then, after a picture or a section, the dialog with the words and a wait for a click. Marks are drawn inside the section branch only. A picture is centred in the 320-pixel window and clipped to it.
A mark's icon is drawn at 32 pixels, centred on its cell, whatever the cell size is.

Bytes after the words, and words 72 and 74, are read by nothing: they are padding and are kept as they are. The bundled scenario's records 5 to 10 hold leftovers (a text number of 2000, and 0x02 bytes), reachable only by a story that names them.
