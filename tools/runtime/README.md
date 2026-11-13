# Local reconstruction replay save patch

`replay-save.patch` changes only `crates/tools/src/main.rs` in a local copy of
the reconstruction's MIT-licensed source. It calls the existing production
`centurions_core::save()`; no session envelope, game state or RNG is constructed
by a separate test driver. `D:\The New Centurions Codex` remains read-only.

```text
centurions-tools replay INSTALLATION COMMANDS_JSON [--from INPUT_SAVE] [--trace] --save OUTPUT
```

On success, OUTPUT contains the final production save. If a gameplay command
is rejected, OUTPUT contains the actual valid state after that command boundary,
including any deliberate partial effects, and the process still exits nonzero.
With `--save`, that rejected command's resulting Session is also emitted as the
last stdout JSON line. Without `--save`, existing error output is unchanged.
JSON parsing or save-loading failures create no save. Missing/duplicate output
options fail; a filesystem save failure remains a process failure. Saving uses
the normal production replacement semantics for the explicitly selected path.

The patch's original main-file SHA-256 is
`b7627fb595481e186fcbce43a35d7c305d1a553601083078c89b575a6d49e1f7`;
the formatted patched file is
`b5c8e8a064ce0ec0ec7ddf965c3718cd2f270321544f16cf027b35b9bca26a04`.
Consult the source hash before applying it to a newer runtime revision.

To reproduce, copy the runtime source (no history or original assets) into a
new ignored `artifacts/.../runtime-source` directory, then apply the patch from
the editor checkout root:

```powershell
git apply --check --directory=artifacts/my-run/runtime-source tools/runtime/replay-save.patch
git apply --directory=artifacts/my-run/runtime-source tools/runtime/replay-save.patch
cargo build --release --offline --manifest-path artifacts/my-run/runtime-source/Cargo.toml --package centurions-tools --target-dir artifacts/my-run/runtime-target
```

All build outputs must stay outside the read-only reference checkout. The local
implementation and acceptance evidence are described in
[authored acceptance](../../docs/authored-acceptance.md). This patch is ready for
runtime-project integration; it has not been applied to the reference repository.
