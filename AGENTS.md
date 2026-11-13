# New Centurions Scenario Editor

- Publish only an allowlisted source snapshot, never this checkout's private history, and never original game data or art. The guide's pictures show the game's art, so they are built from the player's installation (`tools/build_guide_pictures.py`) and are ignored by git.
- The New Centurions reconstruction checkout and both Providence donors are read-only references. Never build, clean, stage, or generate reports there.
- The original Centurions binary is behavior authority. Reconstruction source establishes provisional format knowledge, not original-runtime acceptance.
- Keep Centurions models, record geometry, and opcode semantics independent of Realmz. Reuse generic infrastructure only, with provenance and licenses.
- Preserve every imported file, fork sidecar, unknown byte, extra row, and trailing fragment. Imported semantic edits must overlay only documented owned spans. Unresolved fields are not authorable.
- Core code is independent of filesystem and UI. Storage owns paths, integrity, and publication to new local directories. Never overwrite source, existing projects, or existing exports.
- The native Godot workbench and CLI share the Rust authoring boundary. Keep authored potential, reconstruction execution and original-game observation distinct; do not promote a bounded proof to full runtime acceptance.
- Keep modules cohesive. Test preservation, failure boundaries, malformed input, and meaningful end-to-end workflows. Run formatting, focused workspace tests, Clippy, and release build before handoff.
- Private original-data projects and generated verification output stay ignored under `artifacts/`. Do not commit or redistribute original data.
- Every editable field needs evidence from the original binary (see `docs/original-evidence/`): bytes the original does not read are padding, never fields, and unknowns are resolved with Ghidra, Capstone or Basilisk, not by guessing or from a single scenario's data.
