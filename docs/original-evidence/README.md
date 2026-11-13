# Evidence from the original

The original 1.3.2 binary is the authority for what the editor edits. A field is editable only when the original reads it, and its values are limited to
those the original's code handles. Bytes the original never reads are presumed padding: they are kept as imported, get no form, and new rows are
written with a documented fill. Evidence comes from the original's code and from running that code on data authored for the purpose. A value that appears in the
bundled scenario is consistency only, and a byte that is zero there proves nothing.

`tools/audit_original.py` reads one table's consumers in the original and runs the original on authored values; its receipt names the routines found.

| Table | Editor edits | State |
|---|---|---|
| `Data SD` (shops) | Stock slots, price percent | Audited: [data-sd.md](data-sd.md) (static, with `loaditem` run dynamically) |
| `Data MD` (monsters) | Definition fields, stats, stories, spells | Partly audited: [data-md.md](data-md.md) (static; the readers of each byte, one field withdrawn, size corrected; [data-md-ledger.md](data-md-ledger.md) joins the editor to the reconstruction's map) |
| `Data NI`, `Data NI Des` (items) | Definition fields, descriptions | Audited: [data-ni-ledger.md](data-ni-ledger.md) (the map and a scan of every access to the item record; the editor now lists every byte the original reads except those it keeps as padding) |
| `Data ED2` (typed encounters) | Labels, selectors, tries, dialogue | Reconciled with the reconstruction's accessors and the Realmz structures: [data-rd-ed2-ledger.md](data-rd-ed2-ledger.md) (offsets agree; no recovered value domains beyond those listed there) |
| Script codes (`newland`) | Every step of every program | Checked: [script-codes.md](script-codes.md) (the words each code reads, found in the decompiled `newland`; value domains from the manual, the map and the binary where noted) |
| `Data TD3` (calendar) | Every field the day-turn scan reads (offsets 0 to 21) | Audited: [calendar.md](calendar.md) (static: every routine that names the record's buffer, the scan's instructions read one by one; bytes 22 to 39 are read by none) |
| `Data LD`, `Data DD`, `Data RD` (a map) | Adding a map, the object layer | Audited: [maps.md](maps.md) (static: what a map is made of and how the game counts maps; the object layer's drawing rules from the reconstruction's reading, checked in the original: a level whose stage starts on an added copy of a map drew its buildings and icon) |
| `Data MD2` (map notes) | The marks, section, land, picture, cell size, text number, picture size and words of each note | Audited: [notes.md](notes.md) (static, and a level with a section note and a picture note run in the original; a text window was not run) |
| Code 128, the soft script values, the light level and the item class | The words of code 128 and the seven soft values | Audited statically: [ranges.md](ranges.md) (the delay is in 1/60-second ticks and a negative delay never ends; a monster above 127 can never match code 127; choices past 10 and counts past 40 write past their buffers) |
| `Data RD` (regions) | Rectangle, chances, battles, events, avoidance | Reconciled with the reconstruction's accessors and the Realmz structures: [data-rd-ed2-ledger.md](data-rd-ed2-ledger.md) (offsets agree; no recovered value domains beyond those listed there) |

The item and monster ledgers are kept in step with the editor by `crates/centurions-format/tests/ledgers.rs`: a field whose offset, width or range changes, or is added or removed, fails the test until its ledger is regenerated from a new audit.

A provisional table stays editable and its pages say so. The audit of each is the same: list every routine that touches the record, read what each does with
each byte, run the original on authored boundary values, and then confirm, narrow or withdraw each field.
