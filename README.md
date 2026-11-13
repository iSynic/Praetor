# Praetor

Praetor is a scenario editor for **The New Centurions** (version 1.3.2), the Macintosh game that
[Newer Centurions](https://github.com/iSynic/NewerCenturions) plays on modern systems. With it you build and
change scenarios: maps and their triggers, scripts, stories and encounters, messages and scrolling texts, battles,
monsters, rewards, items and shops, the calendar, map notes, and the pictures, icons and sounds a scenario uses.
Every editable field is checked against what the original game reads, and a scenario is saved and exported as the
game's own files, with every byte the editor does not own kept exactly as it was.

Praetor is a native Godot application over a Rust library. It does not include the game or any of its art: it reads
the player's own installation of The New Centurions.

## Using it

1. Put Praetor in the folder that holds your New Centurions 1.3.2 installation (and Newer Centurions, to play what you
   build). It finds them there.
2. Start it and choose **New from template**, **Import level** (an extracted scenario folder) or **Open checkpoint**.
3. Press **F2** or click the badge at the top left for the guide to the editor.

The editor never changes the files you start from: **Save** writes a new checkpoint folder and **Export** writes a new
scenario folder. **Play from here** runs your scenario in Newer Centurions when it is found beside the editor.

## Building it

You need Rust 1.98 or later and Godot 4.7.1 with its export templates.

```powershell
cargo build --release
.\tools\build_editor.ps1 -Output '.\artifacts\my-build'
```

The guide's pictures show the game's own art, so they are not in the repository. After `cargo build --release`,
`python tools/build_guide_pictures.py --installation "<your New Centurions folder>"` makes them from your installation.

`cargo test --workspace` runs the tests that need no game data; the capture and verification drivers in `godot/tools`
and `tools/` need an installation and are described in [docs/verification.md](docs/verification.md).

## Where things are

- [docs/guide/guide.md](docs/guide/guide.md): the guide, and [docs/editor-shell.md](docs/editor-shell.md): how the editor is built.
- [docs/format-support-map.md](docs/format-support-map.md): what each file holds and what the editor writes.
- [docs/original-evidence/](docs/original-evidence/): what the original game does with each field, the evidence for it.
- [docs/providence-reuse-audit.md](docs/providence-reuse-audit.md) and [NOTICE](NOTICE): where borrowed code comes from.

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE). The New Centurions and its art belong to their owners and are not distributed here.
