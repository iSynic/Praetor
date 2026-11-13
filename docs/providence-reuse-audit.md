# Providence reuse audit

Audit date: 2026-10-26. Completed before codec implementation.

This is a selective source fork, with its own Git repository and no remote,
rather than a clone of private history or a renamed Realmz application.

## Pinned local donors

| Donor | Read-only path | Observed HEAD | Observed worktree |
|---|---|---|---|
| Native Providence | `C:\Users\Eric\Documents\ChatGPT\New project 2` | `53b0a533d085ef108f4347967e8ce0f3de9b323b` | clean |
| Earlier Providence | `F:\Realmz - Providence` | `e65836c01b9d0a50ddeec20b62aa9ea8c1321836` | untracked `.finf/`; preserved |
| Centurions reconstruction | `D:\The New Centurions Codex` | `4d459e75574a2485f75036289089f06bafbce4af` | 83 status entries; preserved |

Current source and original payload hashes are captured in the private local
verification receipt. These pins describe this audit, not subsequent donor work.

## Components and decisions

| Component inspected | Reuse decision | Reason / replacement boundary |
|---|---|---|
| Native `providence-core/src/codecs/classic_text_resources.rs` | Adapt Mac Roman name conversion and table | Generic character encoding only; strict unsupported-character errors, no silent replacement. Centurions Pascal geometry is independently established. |
| Native `providence-core/src/codecs/owned_byte_diff.rs` | Adapt ownership-diff algorithm | Replace Realmz family descriptors with explicit Centurions byte ranges. No inferred append defaults. |
| Native `providence-core/src/codecs/classic_messages.rs` | Architecture reference | Source overlays and retained file tails are useful; do not copy whole-row zeroing, Realmz IDs, or models. |
| Native `providence-storage/src/portable_snapshot.rs`, `atomic_file.rs` | Architecture reference | Deterministic manifest + hashed blobs. Implement a small independent store with validated relative paths and new-directory publication. No Realmz snapshot migration or SQLite dependency. |
| Native compatibility classification and source annex | Architecture reference | Distinguish readable, writable, opaque, and runtime-unverified; preserve original payloads as immutable blobs. |
| Native Godot shell, dialogs, themes, session client | Deferred | UI/workbench commands are deeply coupled to Realmz documents. Retain native desktop direction, add no misleading graphical shell in the format milestone. |
| Native resource/PICT/audio/StuffIt helpers | Deferred | Potential generic reuse after format preservation. This milestone copies `.rsrc`/metadata sidecars without decoding or rewriting. |
| Earlier `realmz/record_bytes.rs` | Reject direct reuse | Indexed record reconstruction and ASCII fallback can destroy unknown bytes and non-ASCII text. |
| Earlier `realmz/assembly.rs`, project model, schemas | Reject | Realmz file names do not establish Centurions layouts. |
| Both compilers, trigger graph, opcode catalogs, runtime preview | Reject | No Centurions authority. Centurions needs its own VM semantics, reference types, and original-binary checks. |

Adapted files retain GPL-3.0-or-later licensing. No application support archives,
artwork, private configuration, scenario payloads, generated evidence, or donor
history were copied into maintained source. `docs/provenance.json` records exact
adapted source hashes. No donor tests or claims are retired by this fork.

## Sequence and acceptance boundaries

1. Audit and format/support map.
2. Import any extracted scenario folder, persist exact files and empty
   directories, reopen it, export to a new directory, and independently compare
   complete path sets and all bytes. Semantic warnings never block unchanged export.
3. Expose only bounded, documented fields as typed authoring operations; preserve
   inactive records, unknown fields, file fragments, and sidecars.
4. Create a minimal **template-derived candidate** after the unchanged gate.
   Unresolved bootstrap/resource fields prohibit a claim of source-free native
   scenario construction. Keep inherited support and identify it explicitly.
5. Original binary load/play and later native GUI work remain separate gates.

## Subsequent native UI adaptation

The initial deferred UI work is now implemented for the existing Centurions
fields. Generic theme/stroke/framing code is adapted; shell, command bar,
message master/detail and map interaction patterns are reconnected to a
Centurions-specific Rust session adapter. Realmz routes, document models,
compiler, preview process, asset identities and opcode semantics remain excluded.
`ui-provenance.json` records exact additional donor hashes and adaptation decisions.
The GPL Centurions reference contributes its generic PICT raster decoder only.
Original artwork remains an external read-only dependency.

See [native editor validation](native-editor-validation.md) for functional,
rendered and original-application evidence and the incomplete prologue gate.
