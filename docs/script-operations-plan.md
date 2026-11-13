# Authoring every script operation

Goal: the editor authors every one of the 112 operations ("codes") of the scripting manual, so that a scenario the original game
could load can be written and exported. Today it authors 13 (0, 1, 2, 4, 5, 9, 10, 14, 24, 39, 48, 100, 110) and preserves the rest.

## What is known

- `docs/scripting-codes.md` of the reconstruction describes each code: the ID, the sign options and the five Extra Codes (E-Codes). 12 codes take no
  operand, 30 a direct ID and 70 the number of an Extra Codes record, five big-endian signed words (ten bytes) of `Data EDCD`.
- The capability map marks 74 codes native-verified and 38 source-ported, and names four operand domains the reconstruction cannot reproduce
  (code 7 branch, code 57 tile set and land, code 125 count).
- The original editor (Divinity) edits an Extra Codes record in place, so every step that names it changes. The Providence donor solved the authoring side of
  this for Realmz (`docs/certification/action-settings-correction-checkpoint.md` there): in-place edit with an exact list of the callers and changed words
  to confirm; "make this step independent" allocates a record, reusing only unreferenced all-zero records and never a nonzero or referenced one;
  consecutive companion records (code 92 reads the next record too) are reserved as a pair; unrelated edits never reallocate.

## Decisions

1. **Source of truth.** A checked-in table of the codes, generated from the manual and the capability map and completed by hand where the manual is prose
   (each operand's kind and range). The table is the one place the validator, the forms and the tests read. Where the manual and the original binary disagree
   the binary wins and the table records the exception.
2. **Numbers the game does not know** are skipped by the original without a message. The editor allows them (they do nothing), with a warning in Problems.
3. **Registration codes (84, 98, 99)** are authorable, so exported scenarios can contain them; the reconstruction treats registration as satisfied.
4. **Shared Extra records** follow the Providence solution above.
5. **Merge after each phase.**

## Phases

- P0: the table, its generator and a conformance check; a generic Extra-record edit with impact list and independent copy; a generic step form. The 13
  codes are re-expressed through it and must write the same bytes as now.
- P1: codes with no operand or a direct ID (42 codes).
- P2: Extra codes whose fields are plain numbers.
- P3: codes that reference other records (branches and their flow edges, shops, items, battles, monsters, travel, calendar, random text).
- P4: the 38 source-ported codes checked against the binary, the four blocked domains enforced.
- P5: Flow, Find uses on Extra records, Problems, compact layout and the Choose action dialog.
- P6: a table-driven round-trip test, the manual-against-table check, the accessor check and Play replays of the native-verified fixtures.

## Status

- P0 done: the table and its generator (`--check`), table-driven validation of the thirteen codes, `Edit::ExtraWord` and `Edit::ExtraIndependent`, the impact
  query (`extra_impact`) and the generic Extra Codes form in the step panel. Differences from before, all from the original: code 9 takes a negative sound
  (the game then waits for it), code 14 takes a negative count (fallen warriors may be picked) and code 100 takes 0, 1 or 5.
- P1 done: the 32 codes that take no operand or a direct ID are authorable (45 codes in all). Each ID kind comes from the manual and the capability map: an unread ID
  (`ignored`), any word (`number`), a range, a signed count, a list of values, or a row of a table (a shop, a note, a monster, a message). Mission flags are
  0 to 127 (the story flag bytes at 0x44258c to 0x44260b). The table gained `label`, `family`, `order`, `takes` and `link`, and the workbench builds its action
  picker from it. Problems warns when a picture (27), a scrolling text (62) or an animation (128) names a resource neither the scenario nor the game holds (see "Resources the codes name" in `docs/original-evidence/script-codes.md`; code 113 names none). Not yet checked: the
  binary check of the source-ported codes among these (P4).
- P2 done: the 41 codes whose Extra Codes are plain numbers, sounds, texts, maps, cells or rows of a table are authorable (86 codes in all): clinic, clear objects, tile,
  event chances, heal or hurt, scans, random text, move and teleport, items, region battles, picks, conditions, shops, calendar, map look, credits, shift, time,
  random items, fatigue, psi, position, victory points, light, statistics, limited shop, monsters and animation. The manual numbers an Extra Code by its own digit,
  so a code that skips one leaves that word unused; the table keeps the digits, and 16 and 18 share the words of 15 and 17. A step may name a row of zeros (a fresh
  row, filled in afterwards); a row with words in it must hold words its code reads. Each word is checked as a draft by the kind of its Extra Code. The branching codes
  (those that jump to a script, step or branch) are P3.
- P3 done: the 27 branching codes are authorable, so all 112 codes of the manual are (113 with the empty step). A code's words may depend on one another, and the table
  says how in `rules`: when a word has one of these values (or lies in a range), other words are of a kind. A jump type decides whether the target is a script, a simple
  or a typed encounter, or a branch 0 to 3 with a start step 0 to 7; a selector decides the same for codes 21, 40, 67, 72, 75, 76, 77, 85, 86 and 87. The workbench writes a row
  as one draft (`ExtraRow`) so a jump type and its target change together, and the row is checked as a whole. Code 92 reads the row after the one it names:
  both rows are listed with their sharers, the second is checked by its own kinds, and Make this step independent takes two rows side by side. The Flow view and Callers follow
  every script or encounter a row hands the scene to. Code 7 limits the branch of a typed encounter to 0 to 3 (the four branches the editor holds). Code 128 is refused in an
  encounter's choice, which keeps its code in one signed byte. A row edit made before Make this step independent changes the shared row, not the copy. The findings that said the sound
  operand must be nonnegative and the combat cleanup operand 0 are gone.
- P4 done: `tools/audit_script_words.py` checks which Extra Codes words each code reads in the decompiled `newland` ([evidence](original-evidence/script-codes.md)); the table agrees with the
  original, with the changes the check made (the scan number of 17 and 18 is a spell descriptor, the count of 125 is not -32768, the calendar entry of 54 is a record of `Data TD3`, the
  attribute of 30 is 0 to 6, the party condition of 40 is 0 to 19, and the tile number of 59 is not read). A number that names no code does nothing in the game: the editor keeps it, may write over
  it, and Problems warns about it. The old findings that preserved steps are gone with the last preserved code.
- P5 done: the Extra Codes card has Find uses (the Callers list of the Find dock names every step that reads the row; a step that reads it as a code's second row is listed on the card, not in
  Find, so Replace cannot break the pair). Problems now lists every step whose ID or Extra Codes row holds what its code does not take (a row of zeros is a fresh one), and a picture (code 27) found in
  neither the scenario's resources nor the game's, which crashes the game. Checking the shipped scenario against the table found two steps outside it: a column of 90 in a -12 and a tile change on a map
  that does not exist. A value a scenario already holds stays editable (only a word the author changes is checked) and is listed. The animation coordinates of code 128 take any word: a negative one draws
  off the edge of the view. The Choose action dialog offers every code and says so.
- P6 done: `tools/check_script_codes.py` checks the table against the manual, the capability map's evidence and Extra Codes views, and the original's native fixtures; `tools/verify_authored_steps.py`
  authors steps, exports the scenario and plays it in the runtime. The check found six values the original handles that the table refused; they are now soft (accepted, advised against, listed in
  Problems). Edits to a step and to the row it names are applied in an order that lets one batch do both.
