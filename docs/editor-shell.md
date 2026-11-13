# Editor shell

The workbench is one window, `godot/src/editor_shell.tscn`. The shell owns the
adapter session, the unapplied edits and the guards around them, and routes
between pages. Everything else is a part, a page, a dialog or a shared widget.

## Parts (`godot/src/shell/`)

| Part | Scene and script | Holds |
|---|---|---|
| Header | `header.tscn`, `header.gd` | Editor name and open project, the File to Help menus with their keys, breadcrumb, Go to field, undo and redo, Check, Save, Play from here |
| Workspace rail | `workspace_rail.tscn`, `workspace_rail.gd`, `rail_button.gd` | The thirteen workspaces in their sections and their record counts; Export is a route |
| Record tabs | `record_tabs.tscn`, `record_tabs.gd` | The open page as a tab, marked while edits are unapplied |
| Page host | `page_host.gd` | Shows one page at a time; `current_tab` is the route index |
| Problems dock | `problems_dock.tscn`, `problems_dock.gd` | The findings, one row each with Go, and the Find tab for Find uses |
| Status bar | `status_bar.tscn`, `status_bar.gd` | The last status line with a dot for how it went, the state of the editor's folder, the unapplied and unsaved marks |
| Project flows | `project_flows.gd` | The dialogs of the project flows and the two questions the shell asks; see below |

The header reports menu and button choices as one `command` signal; the shell
runs them through the same guard as before. A control whose screen is not built
yet is present and disabled: Go to, Find uses, Check, Play from here, Stop,
Code helper, Technical details, the history arrows, the Map menu, the Stories,
Encounters, Monsters and Rewards workspaces, and the menu entries without a
command in `header.gd`.

Menu entries show their key (Godot writes it as `Ctrl+I`). The keys run through
the shell: `header.command_for_key` names the command, the menus' own shortcut
handling is off so a key never runs behind an open dialog, and `modal_open`
holds every key and the Project page's Open button while a dialog is up.

## Pages (`godot/src/pages/`)

Each page is a scene with its own script, set up once with `setup(shell)`.

| Route | Page | Reached from |
|---|---|---|
| Project | `project_page` | View ▸ Project |
| Stages | `stages_page` | Rail ▸ Stages |
| Messages | `messages_page` | Rail ▸ Messages |
| Maps | `maps_page` (with `maps/`) | Rail ▸ Maps |
| Inspection | `inspection_page` | View ▸ Inspection |
| Programs | `programs_page` (with `scripts/`) | Rail ▸ Triggers, Stories and Encounters; View ▸ Triggers, Stories, Encounters |
| Combat | `combat_page` | Rail ▸ Battles |
| Records | `records_page` (hosts `record_editor.gd`) | Rail ▸ Monsters and Rewards (`Records:monster`, `Records:reward`); Author records opens the other families |
| Items | `items_page` | Rail ▸ Items |
| Shops | `shops_page` | Rail ▸ Shops |
| Export | `export_page` | Rail ▸ Export, File ▸ Export native level… |
| Problems | `problems_page` | Rail ▸ Problems |

The condition editor, trigger placement and mission recipe controllers stay
beside the shell and work across pages.

Page state lives in its page. The shell keeps the names the controllers and the
verification drivers already use (`_program`, `_stage_id`, `_load_message`,
`_publish`, `_folder_selected`, `_destination_action`, `_scenario_name` and the
rest) as forwards to the pages, so `workflow_driver.gd` and
`connected_driver.gd` run unchanged. Nodes built in code have no owner, which
`find_child` does not look below; the ones the drivers and controllers look up
by name (`Installation`, `RuntimeStatus`, `ScenarioName`) are registered with
`shell.name_node` and found through `shell.ui`.

## Project flows

| Flow | Where | What it does |
|---|---|---|
| First run, Project | `project_page.gd` | Three action cards (Import level, Open checkpoint, New from template), the recent projects (filter, origin badge, edits, saved time), the selected project's facts, contents, preservation notices, checkpoint history and the receipt comparison written beside its checkpoint, and the folder check. Open project and Open in new window sit at the foot of the side column. |
| Import level | `dialogs/import_dialog.gd` | Source (the folder read, its files and empty directories), destination (a new folder), then the result: name, contents, preservation notices |
| New from template | `dialogs/new_dialog.gd` | Name, template, destination; the unchanged gate shows what the template's manifest answers and that the rest runs on create |
| Save new checkpoint | `dialogs/save_dialog.gd` | A new folder; a refused folder returns with the adapter's reason |
| Save and reopen | Project page, status bar | The recent list is the history; the page shows `receipt.json` from beside the checkpoint when one passed |
| Export | `pages/export_page.gd` | The steps, the source, the kinds of edit since import, the destination as parent folder and name, what is written, and the compare option |
| Export result | `dialogs/export_result_dialog.gd` | Files written, a byte comparison with the import's blobs (`services/export_comparison.gd`), and the runtime evidence line |
| Preferences | `dialogs/preferences_dialog.gd` | The folder found, output parent, pinned seed, map grid, compact layout |
| Confirmations | `widgets/confirm_dialog.gd`, `project_flows.gd` | Unapplied edits (Discard, Cancel, Apply) and unsaved checkpoint (Don't save, Cancel, Save); Enter takes the safe choice |
| Status states | `status_bar.gd`, `services/status_level.gd` | The dot is green when done, orange when waiting on the author, red when it did not happen, blue while starting and grey for nothing yet |

`_destination_action`, `ui("DestinationPath")` and `_publish` keep their
meaning. `DestinationPath` is a hidden field that holds the destination; the
fields of the dialogs and of the Export page mirror it (`shell.set_destination`).
`_publish` returns whether the folder was written; the dialogs' buttons call it
and then show the result, while the drivers call it alone.

The installation is found, not chosen (owner decision 1). `services/folder_check.gd`
looks in the editor's own folder, the folder above it, `CENTURIONS_INSTALLATION`
(for development and the verifiers) and the installation the adapter remembered,
and reports the 1.3.2 application, the original data, The New Centurions.exe,
centurions-tools.exe and the artwork cache. What is missing is listed in the
status bar and on the Project page. The classic 1.3.2 application, The New
Centurions.exe and centurions-tools.exe are not read by the editor: the first
is shown as information, the other two as needed for Play, which stays
unavailable until they are found. Run from the source tree (not a package) with nothing found, the
Project page's folder card offers "Choose folder (development)…"; the pick is
checked for Data Files and Scenarios and remembered in the settings file.

### The settings file

`centurions-editor-settings.json` is shared. The adapter owns `installation` and
`recent` (up to 12 projects, newest first: path, name, origin, label, version,
edits, source files, saved time, contents counts and preservation notices, written
whenever a project is opened, imported, created or saved). The workbench owns
`output_parent`, `seed` (default 12), `grid` and `compact` (both default on),
written by `services/workspace_settings.gd`. Each side keeps the other's keys
when it writes. The grid and compact choices are stored; the screens that use
them are later phases.

The adapter's Describe reply names the file (`settings_file`) and carries the
recent list; Inspect carries `version`, `edits`, `edit_kinds` and `contents`.

## Maps workspace (`pages/maps_page.gd`, `src/maps/`, `map_canvas.gd`)

| Part | File | Holds |
|---|---|---|
| Canvas | `map_canvas.gd` | The floor art, grid, walking triggers (selected, dim at chance 0, shadowed), regions (dashed; drawn, moved and resized with the Region tool), stage starts and the paint preview; zoom, pan, hover |
| Toolbar | `maps/map_toolbar.gd`, `tool_button.gd` | Select V, Sample I, Paint B, Line L, Rectangle R, Fill G, Trigger T, Region E, Start S, Erase X, the Layer choice, and the options of the tool in hand |
| Sidebar | `maps/map_sidebar.gd`, `tile_palette.gd` | The maps (trigger counts and terrain of those read), the Floor and Icons palette, the layers |
| Minimap | `maps/map_minimap.gd` | The map in miniature with the view outlined; click or drag to move |
| Inspector | `maps/map_inspector.gd` | Cell, Map, Regions and Stage tabs and the Revert and Apply foot |
| Choose floor | `dialogs/choose_tile_dialog.gd` | The terrain's tiles large; arrows move, Enter uses |

What a tool costs: a freehand stroke, a line, a rectangle or a fill is one Apply and so one undo step;
choosing a tile for one cell is one Apply too. The Trigger tool places the slot in the toolbar through
`place_trigger` (header and movement gate together); Erase and the inspector's Remove ask first and
offer Disable instead; New at selected cell shows what it would do, then calls `create_trigger`. The
Start tool and the Stage tab draft `stage_start`, `stage_name` and the start story through
`stages_page.draft_*`, so they wait for Apply like the Stages page. The Trigger card's chance and its
operands are drafts too (`walking_chance`, `script_step`), keyed as the Triggers page keys them.
Regions are edited with the Region tool and the Regions tab; see Play and regions. The Map tab's Land card sets the map's tile set (1 to 9, or the scenario's custom sets 15 to 19; other numbers quit the original when the land loads) and whether the land shows only the squares the party has seen. The light level (0 to 255) is a stored byte that only story steps read. Project version 8 adds the map look (`Edit::MapLook`).

The controls the drivers know by name (`MapCanvas`, `TileID`, `PlacementSlot`, `PlacementChance`,
`PlacementFollow`) are registered with the shell. The Map menu's entries and keys run through
`maps.command`; a single-letter key goes to the map only on the Maps route and never while a field
has focus. The Grid choice is the `grid` setting, shared by the menu, the canvas switch and Preferences.

## Scripts workspace (`pages/programs_page.gd`, `src/scripts/`)

One page shows the four families of program: walking triggers, stories, choice encounters and typed
encounters. The rail's Triggers, Stories and Encounters and the View menu open it on a family
(`Programs:walking`, `Programs:story`, `Programs:menu`).

| Part | File | Holds |
|---|---|---|
| List | `scripts/script_list.gd` | The family tabs with counts, a filter, and the programs (cell and chance for triggers from the maps' reads, first step and steps used for stories, first choice for choice encounters) |
| Step card | `scripts/step_card.gd` | A step's number, opcode, name, what its operand points at, the bar of its family, the lock on a preserved step, a mark while drafted |
| Step form | `scripts/step_panel.gd` | The chosen step: its operation, evidence badges, the operand in the form that suits it, Move up and down, Duplicate, Clear step and Technical details |
| Code helper | `scripts/code_helper.gd` | F1 drawer: the step's entry in the scripting codes manual (`scripts/script_manual.gd` reads `data/script_manual.json`, built by `tools/build_script_manual.py`), then the evidence the reconstruction records for the code and the manual's chapter on names in texts |
| Guide | `dialogs/guide_window.gd` | The guide to the editor in a window of its own: contents at the left, text and pictures at the right. The header's mark (the Newer Centurions icon, shifted in colour) and Help ▸ Guide to the editor (F2) open it. `data/guide/` is built by `tools/build_guide.py` from `docs/guide/guide.md`, with pictures taken from the captures named in `docs/guide/shots.json` |
| Step colours | `scripts/capability.gd` (`KINDS`, `kind_of`), `theme/editor_tokens.gd` (`KIND`) | The bar of a step card, the steps of View flow and the groups of Choose action are coloured by what the step does (sixteen kinds), finer than the family of its code |
| Capability | `scripts/capability.gd` | The thirteen operations with a form, their families and operands, and the reader of the capability data |
| Choose action | `dialogs/choose_action_dialog.gd` | The forms by family with their evidence and what the change would do to the row's bytes |
| Choose message | `dialogs/choose_message_dialog.gd` | The message table searched by number or text, with the message as it reads in the game |

A walking trigger or story shows its eight steps in a column beside the form; a choice or typed
encounter shows four branches side by side with the form beneath. Every change is a draft through
`step_controls`, the model of the open branch's eight operations and operands that the drafts and the
verification drivers share; moving, duplicating and clearing set those controls, so each is the same
`script_step` edit as any other. Only steps the editor authors move; a preserved step stays where it is.
Walking-trigger chance is a `walking_chance` draft. The Maps placement controller's return controls sit
in the After the steps card (Linked records for the others).

The technical details read the row through the read-only `program_bytes` operation: the bytes, and
the span each field of the row covers, named only where the editor reads the field.

### Capability data

`godot/data/capability_opcodes.json` holds the opcode rows of the reconstruction's capability map:
operation, status, editor treatment, behaviour, evidence, diagnostic counts and routes, with the hash of
the file it was copied from. It is made deliberately by `tools/extract_capability_data.py --source
<evidence/capability-map.json>` and read by `scripts/capability.gd`; the export includes `data/*.json`.

## Records workspace (`pages/messages_page.gd`, `stages_page.gd`, `combat_page.gd`, `records_page.gd`)

Every record page is a list at the left, a header (`widgets/page_header.gd`: title, badges, the buttons
that act on the record), cards, and a side column. Each draft is the one the earlier forms made, so the
Apply bar, Discard, the unapplied and unsaved guards and the driver names are unchanged.

| Page | Holds |
|---|---|
| Messages | A list with All and Has ^1 scopes, paged by 128 and searched by the adapter; the text with its byte count against 255 and a meter, the ^1 hint, the message as it reads in the game's black window with yellow type, neighbours, and Find and replace over the project's messages (each change is a `message:<id>` draft after the text check) |
| Stages | The twenty stages with In use and Unused scopes; the name with its count, the arrival map and cell with a 90 × 90 map and Pick on map, the start story with its eight steps, the mission pack opening and whether it matches stage 0 |
| Battles | The 26 × 26 population on `battle_population.gd`: Select, Place and Erase with a brush monster and a squad flag (a negative id fights for the squad), the cell in hand, the roster with each monster's colour, the battle's fixed fields and the retained row. Each placement writes the whole population as one `battle_population:<id>` draft; putting every cell back removes the draft. A hidden `kind` and `details` keep the monster browse the verification driver reads |
| Monsters | The list of monster rows with names; Identity (name with the 29-byte limit), Body (level, stamina, speed, movement), Loot (item slots and cash bound as stored, and the drop-clearing draft) |
| Rewards | The list of reward rows; Payout (credits, experience) and Booty (the 80 preserved bytes before the experience and credits words) |

`record_editor.gd` still owns the forms of the other families (message, choice, story, battle extra), so
`record_ui.open_record`, `controls` and `changed` keep their meaning; a battle opens on the Battles page
(`combat.open_battle`). Duplicate clones the open imported row through `allocate_record`.

Dialogs: Author records (Edit ▸ Author records…) opens an existing row or clones an imported seed, with the
family chips, the new row's checks and Edit after cloning. The record pickers (`dialogs/record_picker_dialog.gd`)
choose a battle for a battle extra's minimum or maximum and a reward for an Explicit reward step, with a
preview of the chosen row. The Connected mission panel (`mission_recipe.gd`, `dialogs/connected_mission_dialog.gd`)
shows the recipe's fields with byte counters, the route the recipe wires with the ids it will allocate, the rows it
adds and the refusals the backend gives.

The adapter gained one read-only field here: `preserved_sizes` in the inspect result. A reward record lists its twenty items and their levels.

## Navigation (`shell/navigator.gd`, `dialogs/goto_dialog.gd`, `dialogs/flow_dialog.gd`, `pages/problems_page.gd`, `shell/problems_dock.gd`)

Four read-only adapter operations, computed from the effective files by `centurions-format::navigation`:

| Operation | Returns |
|---|---|
| `search {query, families, limit}` | Monsters (name), battles (name of a monster in them, or `B` and the number), messages (text or `M` and the number), walking triggers (`W` and the number) and stories (`S` and the number), grouped with totals |
| `uses {kind, id}` | Every step that names the record (message, battle extra, reward, choice, typed, story, stage or a sound id), with the step before it, and the fields that name it: a stage's start script, a monster's death script, a choice or typed prompt, a battle extra's battle range, a battle's monsters, the cell a walking trigger is placed on |
| `flow {family, id}` | The program and every story, choice and typed encounter it calls, as cards of steps and the edges between them; cut at 40 records |
| `problems` | The preservation notices and reference diagnostics as findings with a place to go, the read-only findings (steps the editor preserves, negative sound operands, end-combat operands, walking tables past the maps), and the steps by operation for the capability map |

Where each answer is used:

- Go to (Ctrl K, or the header field) searches as the author types, with prefixes, chips and arrow keys, and
  reads a pair of numbers as a cell of the open map. Choosing opens the record through the navigator, after
  the usual guard for unapplied edits.
- Find uses (Ctrl Shift F, every Callers button, the Used by card of the record pages) fills the dock's Find tab. Replace puts the number in
  the step form's place in every step that names the record: one `script_step` draft each, applied together
  by Apply. Message and stage operands keep their sign.
- View flow (View ▸ View flow, the Triggers & encounters and Stages pages) draws the graph; choosing a step names where it
  leads, Open takes the author there.
- Problems is a page of the rail (Release): the findings with filters, the operations in use with their
  evidence, editor treatment, form and steps from the capability data, and the detail of the chosen operation.
  The dock below the pages keeps the same findings (Ctrl J, View ▸ Problems). Check runs the checks again and
  says how they came out.

## Compact layout (`shell/compact_layout.gd`)

Below 1600 px, with the Preferences choice on (it is by default), the shell folds what the wide layout shows
beside the work; nothing is removed.

| Part | Folded into |
|---|---|
| The menus | One button before the project name; its menu lists File to Help as submenus, copied from the real menus each time it opens so their entries, keys and checks are as they stand |
| The record list of a page (maps and palette, programs, messages, stages, battles, monsters and rewards, items and shops, findings) | A drawer the first button of the tab row opens; the button names the record in view (`Story 13 ›`) |
| The inspector or side column of a page | A drawer the panel button at the right of the tab row opens |
| The Problems dock | A count in the status bar (`7 problems ▴`) that opens the dock; Find uses and Ctrl J open it too |

A page's list and side are its first and last parts when it has three, its first when it has two. A drawer
is a part shown beside the page's work, so the work gets the room back when it is closed; drawers start closed
on each page. The rail is icons only when the window is lower than 860 px.

## Play and regions (`services/play_session.gd`, `shell/play_bar.gd`; `centurions-format/src/regions.rs`)

**Play from here** (F5, the header button, Play ▸ Play from here) runs the open project through the runtime found in the
editor's folder: `The New Centurions.exe` and the patched `centurions-tools.exe` must both be there, or the button is
disabled with the reason. The installation is never written:

1. A scratch copy of the installation (without its programs) is made once under the output folder's `play` folder.
2. The project is exported into the copy's `Scenarios/<mission name>/0`, replacing the last run's. Play needs a scenario
   made from a template, because its name is the mission's name.
3. The commands are `ImportStarters`, `SelectStarters` 0 to 5, `EnterMission`, and one `Move` for each cell from the stage
   start to the selected cell of the open map, along x and then y. The runtime decides whether a step is allowed; the
   Play log shows where it refused.
4. `centurions-tools.exe replay … --from <save> --save <save>` runs a batch and each command's events come back one line
   each, so the session continues from the save of the run before. A command the runtime refuses stops the batch and the
   save is the state at that boundary.

`tools/build_editor.ps1 -Runtime <folder>` copies `centurions-tools.exe` and `centurions-desktop.exe` (as `The New Centurions.exe`) from a runtime build into a package; nothing is taken from the installation.

The bar over the pages shows the message the runtime is showing in the game's black window and has Continue (sends
`Continue`, then goes on with the rest of the route), Step (the next queued command alone), Restart (a new export) and Stop
(Shift F5). The dock's Play log lists each command and what it did, with Copy commands (the replay tool's JSON on the
clipboard) and Save replay… (the same, under the output folder's `replays`).

**Regions** are edited on the Maps page with the Region tool: drag a handle or the border of the chosen region to resize,
drag inside it to move, drag on empty floor to draw one in the first free slot. The Regions tab holds the fields of the
chosen region (rectangle, battle range and chance in 10000, three events with story and chance, avoidance chance, sound and
dialogue, Exclusive), New region and Remove region. Every change is a `region:<map>:<slot>` draft of the whole region, and
putting a region back as saved removes the draft. The edit (`Edit::Region`, project version 6) writes only the region's own
bytes of the map's 644-byte Data RD row; an all-zero rectangle empties the slot and zeroes the rest of the slot's fields.
The fields and their offsets come from the reconstruction's `RegionTable`, which the owner accepted as the evidence for
them (2026-11-10, replacing decision 2). Region stories are checked as linked programs, and the findings list regions that
run past the map edge, end before they begin, or draw battles the scenario does not hold.

## Decoded records: shops, monsters, typed encounters and items

The record layouts the reconstruction's `crates/content/src/records` already decodes are edited here. Only shops have been checked against the original so far; the other tables are marked provisional on their pages until [original-evidence](original-evidence/README.md) covers them. Each field is a
descriptor (offset, width, what the engine accepts) in the adapter, each change is an edit that owns only that field's bytes,
and a stored value the engine does not accept is shown and kept as recorded. Project version 7.

| Edit | File | Page |
|---|---|---|
| `ShopStock {shop, slot, item, quantity}`, `ShopPrice {shop, percent}` | Data SD | Shops, in the five categories of 200 slots the game keeps: the price percent (-32768 to 32767; below 0 the buyer is paid and the seller charged), the stocked slots (quantity 1 to 255 of an item 1 to 999), Add item (one more where the category holds it, else its first empty slot, as the game takes a sale in), and Clear, which writes quantity 0 and item 0 as the game does. Audited against the original: [original-evidence/data-sd.md](original-evidence/data-sd.md) |
| `MonsterField {id, field, index, value}` | Data MD | Monsters: Identity, Body, Psi, Behaviour, Sounds, Saves, Attacks and Loot cards of every definition field the reconstruction names, beside the existing name, level, stamina, speed, movement, turn story, run chance, death story, spell slots and drop clearing |
| `TypedLabel {id, index, text}`, and the password selector, tries and dialogue as encounter conditions | Data ED2 | The Conditions window of a typed encounter: its eight action labels and its password label (39 bytes each) with the existing selectors |
| `ItemField {index, field, slot, value}`, `ItemDescription {index, text}` | Data NI, Data NI Des | Items: the 200 scenario items (ids 800 to 999) with their definition fields in cards and their description; Used by lists the shops that stock the item, the monsters that carry it and the typed encounters that ask for it |

Item names are not in the item files. The game names item `id` from `STR#` resources: ids below 800 from the first 200 strings of
`STR#` 1, 201, 401 and 601 of the installation's `Data Files/Data ID` resource fork, ids 800 and up from the first 200 strings of
`STR#` 801 ("Misc. Short") of the scenario's own `Scenario` fork (reconstruction: `desktop/src/assets.rs` `names`,
`core/src/item_display/ammunition_menu.rs` and `rules::selection_base`; checked against the Thunder of Guns data, where item 800 is
"Rations" beside the description "Mmm! Meal ready to eat."). The adapter's `item_names` reads them (`media::item_names`); the Items,
Shops and Monsters pages show them, and names are read only because changing one means rewriting the resource fork.

`Data NID`, the rewards' booty slots and the objects layer of `Data LD` are still preserved: the reconstruction does not read the
first, and the layouts of the others are not decoded there either.

## Dialogs and shared widgets

| Widget | File | Use |
|---|---|---|
| Record list | `widgets/record_list.gd` | Title and count, filter, scope chips, rows in columns |
| Card | `widgets/card.gd` | Titled panel; scene children move into its body |
| Key-value row | `widgets/key_value_row.gd` | Dim key of fixed width and its value |
| Apply bar | `widgets/apply_bar.tscn` | Apply, Discard and the count of unapplied edits |
| Modal overlay | `widgets/modal_overlay.gd` | Panel over a scrim; closes on Esc, the close button or the scrim; a body taller than the window scrolls. Subclasses call `super()` first in `_init`. |
| Confirm dialog | `widgets/confirm_dialog.gd` | A question with a tone, the record it names, and the safe choice on Enter |
| Action card | `widgets/action_card.gd` | A whole card that is one choice, with its key |
| Check row | `widgets/check_row.gd` | A mark (good, warn, err, idle), a label and a mono note |
| Stat tile, contents grid | `widgets/stat_tile.gd`, `widgets/contents_grid.gd` | The counts a project holds |
| Notice list | `widgets/notice_list.gd` | Preservation notices |
| Path field | `widgets/path_field.gd` | A folder with the state of what it names (new folder, already exists, no parent) |
| Stepper | `widgets/stepper.gd` | The steps of a dialog |
| Keycap button | `widgets/kbd_button.gd` | A button with its key at the right, and a corner mark |
| Flow canvas | `widgets/flow_canvas.gd` | Cards of steps in columns by distance from the first program, with arrows from the step that calls to the program reached |
| Page header | `widgets/page_header.gd` | A record's title, badges, its line and the buttons that act on it, wrapping when narrow |
| Glyph, icon button | `widgets/glyph.gd`, `widgets/icon_button.gd` | Line icons drawn in code |

## Theme (`godot/theme/`)

`editor_tokens.gd` holds the design tokens. `godot/tools/build_theme.gd` turns
them into `editor_theme.tres`:

```
godot --headless --path godot --script res://tools/build_theme.gd
```

Type variations: `PrimaryButton`, `DangerButton`, `GhostButton`, `IconButton`,
`Chip`, `ActionCard`, `RowButton`, `Card`, `Tile`, `Detail`, `Inset`,
`ModalPanel`, `Circle…`, `Caption`, `Muted`, `Dim`, `Mono`, `Heading`,
`PageTitle`, `Kbd`, the `Badge…` and `Tag…` labels and the `LineEdit…`
variants. Switches and check boxes are drawn in the builder. The tokens are
also readable from the theme under the `EditorTokens` type. Provenance is in
`ui-provenance.json`.

## Script codes

`data/script_codes.json` (built by `tools/build_script_codes.py` from the scripting manual and the capability map, with the hand-curated kinds of
`tools/script_code_overlay.json`; `--check` fails if the committed copies differ) says what each code's ID and Extra Codes are. Rust validates a step
by it (`script_codes.rs`) and the step form reads the same file. A step that names an Extra Codes row shows its five words and the steps that share it;
a word is an `ExtraWord` draft, and "Make this step independent" is an `ExtraIndependent` draft that copies the row into the first unnamed all-zero row
(else a new one) and points the step at it. Plan: [script-operations-plan.md](script-operations-plan.md).

Problems lists a step whose ID or Extra Codes row holds what its code does not take, and a picture step (code 27) whose picture is in neither the scenario's resources nor the
game's (it needs the installation; the game crashes on a missing picture). The Extra Codes card has Find uses.

## Rewards

The Rewards form edits the credits and experience (a negative award is a random one) and each of the twenty item slots with its level (`Edit::RewardItem`).

## Battle settings

The Battles page edits the grid and the settings after it (`Edit::BattleSetting`): the messages before and after, the squad's start, the five stories run each round and the starting distance. Evidence: [original-evidence/data-rd-ed2-ledger.md](original-evidence/data-rd-ed2-ledger.md).

## Checks

- `tools/verify_editor_workflow.py` and `tools/verify_connected_editor.py` run
  the two drivers.
- `godot/tools/capture_editor.gd` captures every route at 1600×900 and 1200×720,
  checks that the shell's parts stay inside the window, and opens the Import,
  New from template, Preferences and Export result dialogs at both sizes to
  check their panels do too.
- `godot/tools/capture_widgets.gd` captures the open Problems dock, the menus
  and galleries of the shared widgets, and checks the dock, menu routing, list
  filter, overlay dismissal, shortcut routing, the status levels, the
  destination states, a question's answers and the shared settings file.
- `godot/tools/capture_scripts.gd` drives the Triggers & encounters workspace with the real forms and
  checks selecting a step, Choose action, moving, clearing and discarding, Choose message, applying a
  step and reading it back as one revision, F1, the technical details' 42 bytes, and the four branches of
  a choice encounter, with captures at both sizes. It needs `CENTURIONS_PROJECT` to be an imported level
  with an active walking trigger on map 0.
- `godot/tools/capture_maps.gd` drives the Maps workspace with real mouse events against an imported
  level and checks what each tool costs (one revision per stroke), the trigger, erase, start and
  region tools, the chance quick edit, Choose floor and New at selected cell, with captures at
  1600×900 and 1200×720. It needs `CENTURIONS_PROJECT` to be an imported level with walking triggers.
- `godot/tools/capture_records.gd` drives the record workspaces and checks the message's byte count, a
  battle placement being one draft that clears when the cell is put back, the monster list holding every
  row, the preserved file sizes, Author records in both modes, both record pickers and the Connected mission
  panel staying inside the window, with captures at both sizes. It needs `CENTURIONS_PROJECT` to be a project
  that is open at start.
- `godot/tools/capture_navigation.gd` drives Go to (prefixes, a cell, choosing a monster), Find uses with
  Replace, View flow, the Problems page and the dock, and checks the dialogs stay inside the window and that
  the page and the dock show the same findings, at both sizes. It needs `CENTURIONS_PROJECT` to be an imported level.
- `godot/tools/capture_guide.gd` opens the guide from the header mark and goes to two chapters from the contents. The guide's
  pictures are the captures of the other drivers, named in `docs/guide/shots.json`: run the drivers into
  `artifacts/guide-captures/<driver>` (editor, scripts, records, maps, navigation), then `python tools/build_guide.py`.
- `godot/tools/capture_compact.gd` checks that a wide window keeps the menus and the dock, that a narrow one
  folds the menus, the dock and the page parts, that each drawer opens and closes and starts closed on a new
  page, that the folded menu holds every menu and entry, that the status bar opens the dock, and that turning
  the Preferences choice off keeps the full layout, with captures at 1280×720.
- `godot/tools/capture_play.gd` plays a template-derived scenario through a folder that holds the runtime and checks the
  session enters the mission, every command is listed in the Play log, the installation itself is not written, and
  Continue and Stop work. It needs `CENTURIONS_INSTALLATION` to name a folder with the installation, `The New Centurions.exe`
  and `centurions-tools.exe`.
- `godot/tools/capture_regions.gd` drags a region out on empty floor with real mouse events, resizes and moves it, edits its
  fields, applies and undoes it, and checks that putting it back leaves no draft and that removing one drafts an empty one.
- `godot/tools/capture_project_flows.gd` walks the project flows against the
  adapter and captures First run, the Project page, Import level, New from
  template, Save (and its refusal), Export, the Export result, Preferences, the
  menus, the confirmations, every status line and the busy header. It needs
  `CENTURIONS_FIXTURES`, a folder holding `checkpoints.txt`, one checkpoint
  folder per line.

## Not matched to the design

- Play: the replay tool takes no seed, so the pinned seed is not applied and the log shows no draws; the runtime starts
  every session the same way. The session is a list of commands replayed from a save, not a live window: there is no
  player marker on the map, and Space does not press Continue. The route is straight steps along x then y, never a
  path around what blocks it. Play from the other maps' cells begins at the stage start with no moves. The log has no
  "where" column that links a command to a step.
- Regions: the Region tool's slot, First and Last fields are not in the tool row (the Regions tab holds them), a handle is the
  border cell of a region at least 3 × 3 (a smaller region is moved, not resized, by dragging it), and the light level,
  tile set and limits-sight bytes of the table are not edited.

- Compact layout: the drawers squeeze the page's work instead of floating over it. The map's list, palette and
  layers share one drawer, not three icons under the rail; the Records button names the record in view and has no
  "n of N" count. The rail's captions follow the window's height (icons only below 860 px), not the layout, so the
  Triggers frame's captioned rail at 1280 × 720 is not drawn. The folded menu is not searchable and the project
  title drops its path below 1280 px.

- Navigation: Go to has no Ctrl Enter new tab (there are no tabs for records), no Cells group without a pair of
  numbers and no Choices or Typed groups. Find uses has no Messages or Map cells chips (the table lists every
  kind of use and the cell a trigger is placed on) and its Replace is for steps only; stage, monster, battle and
  trigger targets cannot be replaced. View flow follows calls forward only (Callers is the dock's Find tab), has Fit but no pan
  by dragging and shows no dashed ends marks. Problems has no text-length or placement checks (the message
  table cannot hold a text over 255 bytes, and placement checks need the region fields, which are not recorded), no
  Fields or Spell effects capability tabs (the capability data holds operations), no Show read-only button and no
  Use bars per family. The detail panel's Find uses names a record, not an operation, so it is omitted. Findings have
  no Dock tab for Capability; the Capability tab of the dock stays disabled.

- Scripts: Callers, View flow, Duplicate (a record) and Play encounter are present and disabled (phases
  5 and 7). The list has no Warnings or Preserved scopes and no steps-used column for triggers. A
  message's text is shown with its in-game preview but edited in Messages; a choice's prompt and labels
  and a typed encounter's actions, password, scans and items are edited in Author records and
  Conditions, not inline. The Placement fields of a walking trigger are read only (Maps places it). Choose
  action has no per-operation project counts, no In this project card and no usage column; Choose message
  has no Shown by column, no Unused or Empty scope and no New message; the code helper has no Uses
  count. Steps cannot be dragged, only moved up and down. The page's own Apply bar is the shell's.

- Maps: the toolbar's Layer choice wraps under the tools below about 1700 px. The inspector shows
  no Light level, Limits sight or Movement gates, and no object count, because the adapter's map read
  does not carry them. The Cell tab's Return is read as the program's destination, not a choice; moving
  a trigger is by clicking a new cell, not by dragging; Callers waits for phase 5. The frames' cell
  tooltip for a rejected movement gate is not drawn. At 1200×720 the cursor reading over the canvas is
  hidden; the status bar has it.

- Records: Play battle and View flow of a battle are disabled (the runtime has no battle entry). Battles are
  listed as "Battle N" with no monster summary; the adapter reads no roster per row. The Monsters page
  lists the definition fields in cards but has no Behaviour preview, the art, the equipment and the
  description. The Rewards page lists no items: the booty slots are shown as preserved bytes because the
  reconstruction does not decode that layout either, and New from reward is not offered. The sound picker is not
  built (no operation lists sounds), and the reward picker shows no contents or Uses column. Item names are shown but
  not edited (a name lives in a resource fork) and Items have no Stock scope; the item "Used by" rows list shops, monsters and
  typed encounters but not rewards. Shops show the names of stock items only when the installation's `Data ID` fork is found. Duplicate on a battle is left to Author records.

- Menu keys read `Ctrl+I`, not `Ctrl I` in mono, and `Ctrl+Comma` for the
  Preferences key; Godot writes them.
- The Export page lists the kinds of edit and their counts; the design's
  before, after and byte columns need per-edit byte spans the adapter does not
  give. The result's table lists the changed files, their sizes and changed
  byte counts, compared against the import's blobs, without the design's
  Owned by column. Its third step is named "Compare with the import"; the
  adapter has no reopen-and-compare operation, so the dialog states only what
  the comparison proved.
- The New from template gate shows the first check from the template's
  manifest and leaves the other three to the create step.
- Save and reopen is not one board: the history, the reopen card and the
  status line sit on the Project page and the status bar. The Reopen
  comparison shows the keys `verify_editor_workflow.py` writes to
  `receipt.json`, not the design's wording.
- The Project page's Selected project shows the settings file's record of a
  project that is not open (including its contents and notices); the open one
  shows what the adapter reports now.
- Open in new window starts another instance with `--project=<folder>`; it was
  started once, not driven.
- At 1200×720 the keycaps beside Check, Save and Play drop away, the action
  cards drop their keys, and the Project page keeps its 468 px side column; the
  1280 compact layout is phase 6.
