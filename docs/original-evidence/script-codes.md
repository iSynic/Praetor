# Script codes: what the original reads

`tools/audit_script_words.py` reads the decompiled `newland` (the routine that runs every step) and lists, for each code, which of the five Extra Codes words (E1 to E5, at 0x44330a to 0x443312) its case mentions, following the shared blocks it jumps to. It compares them with the table of script codes (`data/script_codes.json`). The scan is static and approximate: a shared block can add a word a case does not use, and a read that goes through a pointer is not seen.

## Result

- No code reads a word the table calls unused, except in three explained cases: code 92 reads E3 of the *second* row (the new sides), and codes 40 and 72 reach shared blocks that read E5 and E3 for other codes.
- Every word the table names is read, except where the original ignores it: code 59 computes a tile number and uses nothing of it, so its E1 is kept as a word the game does not read.
- Codes 20 and 45 read all five words in a block they share; codes 33, 38, 42, 46, 58 and 59 read their first words in the case and the standard jump (E3 to E5) in a shared block.

## Checks that changed the table

- **Codes 17 and 18, E1.** `loadspell2` decodes the scan number as a spell descriptor (school, level and index from the thousands, hundreds and units, each less one) and reads the spell table at that place whatever it holds; the editor accepts a descriptor inside the table (schools 1 to 4, levels and indexes 1 to 7).
- **Code 125, E2.** A count of -32768 keeps its absolute value negative, and the case then destroys the current monster instead of the monsters it names; the count is -32767 to 32767. The capability map names the same domain.
- **Code 54, E1.** The calendar entry is a 40-byte record at index E1 of `Data TD3`; it must exist.
- **Code 30.** When the kind of test is not 0 the first word names an attribute and indexes the character record by it; the attributes are 0 to 6.
- **Code 40, E4.** The party condition is a byte of the array at 0x442562, which ends where the difficulty begins: 0 to 19.
- **Code -32** reads the price percentage, the sound and the text in that order (its case jumps to the block that calls `temple`).

## Per code (the codes the capability map marks source-ported)

| Code | Name | Words the original reads | Words the table names |
|---|---|---|---|
| -32 | Enter the clinic | E1, E2, E3 | E1, E2, E3 |
| 1 | Show text | none (the ID only) | none |
| 2 | Battle | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 3 | Ask a yes/no question | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 4 | Simple encounter | none (the ID only) | none |
| 5 | Typed encounter | none (the ID only) | none |
| 6 | Open a shop | none (the ID only) | none |
| 9 | Play a sound | none (the ID only) | none |
| 11 | Give victory points | none (the ID only) | none |
| 17 | Cast a scan on the picked warriors | E1, E2, E3, E4 | E1, E2, E3, E4 |
| 18 | Cast a scan on the whole party | E1, E2, E3, E4 | E1, E2, E3, E4 |
| 22 | Change items held by the party | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 23 | Change a region's random battles | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 26 | Wait for a click | none (the ID only) | none |
| 29 | Give or show a map note | none (the ID only) | none |
| 30 | Pick warriors by a test | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 33 | Charge credits and branch | E1, E2, E3, E4 | E1, E2, E3, E4, E5 |
| 35 | Remove a choice from the running simple encounter | none (the ID only) | none |
| 36 | Take or return the party's belongings | none (the ID only) | none |
| 38 | Branch if the party has an item (standard jump) | E1 | E1, E2, E3, E4, E5 |
| 39 | Replace the script | E1, E2, E3, E4, E5 | none |
| 42 | Branch on a percent chance | E1, E2 | E1, E2, E3, E4, E5 |
| 62 | Show Scrolling Text | none (the ID only) | none |
| 68 | Alter Squad Fatigue | E1, E3 | E1, E3 |
| 69 | Set Psi Restrictions | E1, E2, E3 | E1, E2, E3 |
| 85 | Branch at Random | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 87 | Branch on Ally Present | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 98 | Require registration | none (the ID only) | none |
| 99 | Scenario registration check | none (the ID only) | none |
| 101 | Back up the squad | none (the ID only) | none |
| 105 | Suspend or restore allies | none (the ID only) | none |
| 107 | Battle with a choice of battles | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |
| 111 | Limited shop or treasure | E1, E2, E3 | E1, E2, E3 |
| 120 | Replace the monster in the battle | E1, E3, E4, E5 | E1, E3, E4, E5 |
| 122 | Make monsters neutral | E1, E2 | E1, E2 |
| 124 | Add monsters to the battle | E2, E3, E4 | E2, E3, E4 |
| 125 | Destroy monsters of one kind | E1, E2, E3 | E1, E2, E3 |
| 128 | Show an animation on the map | E1, E2, E3, E4, E5 | E1, E2, E3, E4, E5 |

A code with no Extra Codes reads its ID only. Numbers that name no code are skipped by the game; the editor keeps them, may write over them, and lists them in Problems.

## Checks of the table (`tools/check_script_codes.py`)

The check reads the manual, the capability map and the reconstruction's native fixtures (`evidence/fixtures`, 183 Extra Codes rows and 23 IDs from 227 steps that the original binary ran) and
fails when the table disagrees: a code of the manual that is not authorable, a different kind of ID, a different evidence, a word the reconstruction's accessors read that the table calls unused
(24 Extra Codes views), or a value a fixture ran that the table refuses. The last check found six values the original handled that an earlier table refused: a recipient of 3 for code 43, 22
random items for code 65, a light level of 0 for code 106, a count of 9 for code 14, a choice of 7 for code 41, a kind of test 9 for code 50 and a monster of -1 for code 127. They are now
**soft**: the editor accepts them, the form offers the values the manual advises, and Problems lists a value outside them. Code 14 keeps a hard bound, since a count of 0 was not seen. What the original does with each soft value, and the hard bounds that came of reading it, are in [ranges.md](ranges.md).

## Authored steps run

`tools/verify_authored_steps.py` authors a walking trigger with a sound (code 9), an animation (code 128, whose row the step first shares and then takes for itself with Make this step independent)
and a redraw (code 28), exports the scenario over a scratch installation and replays a step onto the trigger in the reconstructed runtime. The runtime ran the steps in order and reported the
sound, the animation with the words of the new row, and the redraw.

An edit is applied in the order of its identity, not the order it was made in. A step's edits sort before the edits of the rows it names (`step:` before `step~independent`, `step~row` and `step~word`),
so a step may be given its code and its own row in one batch.

## Resources the codes name (Problems)

Problems lists a step whose resource neither the scenario's `Scenario.rsrc` nor the game's (`Cargo Pod.rsrc`, `New Centurions.rsrc`) holds, found by the same search the game makes.

| Code | The game fetches | When it is missing | Evidence |
|---|---|---|---|
| 27 | `PICT` with the step's number | the game crashes | native-verified |
| 62 | `TEXT` and `styl`, both with the step's number (`movie`, the routine that shows the scrolling text; `GetResource` for each, then both are locked and used without a test) | the game crashes | `movie` 0x13ebde, called from case 62 of `newland` |
| 113 | nothing: the number only gates the party marker (`centerpictlarge` fetches the marker picture when the word is 0; the word's other readers are `newland`'s assignment, `load`, `save` and `setupnewgame`) | no check; the number need not name a resource | all 571 decompiled routines searched for the word at 0x40857a |
| 128 | `cicn` resources 12000 + 8 x animation number, eight in a row (`spelleffectoutdoors`, drawn with `ploticon3`, which skips a missing icon) | a missing icon is skipped, so an animation with none of its icons draws nothing, and the game does not crash | `spelleffectoutdoors` 0x15b84c, `ploticon3` |

The stock game holds no `TEXT` or `styl` resource outside the manual's (`NC Manual.rsrc`, which is not in the game's search), so a scenario's scrolling texts live in its own `Scenario.rsrc`; the shipped
scenario holds texts 1000 to 1005. The stock `Cargo Pod.rsrc` holds `cicn` 12000 to 15006, 207 icons. A problem is shown as a warning, since the editor cannot see a resource the player adds to the installation later.
