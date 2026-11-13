# Authored reconstruction acceptance

Editor commit `905411e` established supported connected-mission authoring.
The subsequent cross-project receipt proved named loading and full state/event
continuation using the production reconstruction boundary. The current follow-up
adds a production replay save option, Windows desktop observation and two narrow
authored cases. These are reconstruction checks; original-game fidelity and
backlog closure remain separate.

## Production replay saves

The local runtime CLI accepts `replay ... --save OUTPUT` and uses production
`save()` directly. An artifact-local gameplay wrapper is no longer required.
The maintained [patch and application instructions](../tools/runtime/README.md)
change only the tools entry point. The read-only runtime reference is untouched.

The built local CLI is
`artifacts/replay-desktop-acceptance-01/runtime/centurions-tools.exe`, SHA-256
`ca40cfb386290ed9beb57fc841a8e37beb09c881a3d7049754584e846a0e8d77`.
`replay-save/receipt.json` beside it records production save/load equality at
choice, battle, battle-loot, reward-loot and transition boundaries. Ordered
events and complete final states match uninterrupted execution. Rejected idle
Continue saves the unchanged state while returning nonzero; repeated load does
not repeat credits or transition. Missing/duplicate output arguments and failed
save destinations are checked. The modified tools package passes formatting,
strict Clippy and a release build in the workspace-local runtime copy.

## Windows observation of the exact Micro Patrol export

The unmodified reconstruction desktop executable was copied into the isolated
runtime directory, SHA-256
`567adde92165ee346ae5683d826898a56ad4dbd084c80bd848a469c17ed640a8`.
It opened a genuine pending-choice save produced by the save-enabled CLI against
the exact accepted Micro Patrol installation. All settings, logs and desktop saves
use isolated paths under `desktop-live/`.

Observed through actual Windows controls:

- Authored prompt and Engage / Not yet labels; Engage entered the battle.
- Ordinary automatic-turn controls completed the enemy encounter.
- Battle loot and explicit reward windows opened and closed normally.
- The authored reward confirmation appeared.
- Transition displayed inherited `TEXT` 1001, then the authored completion text
  at map 0 (4,2), followed by free exploration.
- The normal Game / Save command produced a genuine desktop save.

The desktop save matches the headless replay's **complete Session**, including
25 credits, stage 1, position (4,2), no combat and no pending presentation.
`desktop-live/audit.jsonl`, captured PNGs and the saved envelope bind this result.
The loot window shows generic original equipment text rather than the credit
amount. Thus the 25-credit amount is state evidence, not a claim of a visible
numeric reward display or original-game visual fidelity. P02 is not closed.
The inherited transition text still describes Thunder content, as expected from
the preserved template resources; it is not newly authored scenario text.

## Selective scenario cases

| Case | Target | Evidence | Still outside this case |
|---|---|---|---|
| No Loot Patrol | I11/B01 alternate ordinary cleanup | Typed battle EXTRA mode 5 survives battle teardown and save/reopen; full completion, 25-credit award, ordered events and complete state equal an uninterrupted replay. | The genuine producer leaves NPC count zero. Positive retained-NPC mode 5 and adjacent-storage ownership remain open; no missing state is fabricated. |
| Death Return Patrol | B01 death-script continuation | Imported monster seed 17 retains death hook 3. A new message replaces only its supported message operand. Ordinary combat reaches that dialogue during death processing, saves/loads it, and completes with identical full state and ordered events. | Other inherited death-script instructions are preserved. This does not qualify nested callbacks, changed selected-NPC aliases, detached frames or original-native reentrancy. |

These cases use the Thunder-derived unchanged template; they are deliberately
bounded reproductions of those inherited record relationships. They do not
establish a universal scenario builder or close I11/B01. Each uses existing typed
editor operations and production replay commands; no raw state/seed patching,
Thunder replacement or runtime gameplay changes are used.

## Reproduce

Use new output directories, because inputs/checkpoints/exports remain immutable:

```powershell
python tools/verify_replay_save.py --binary artifacts/replay-desktop-acceptance-01/runtime/centurions-tools.exe --installation artifacts/replay-desktop-acceptance-01/installation --commands artifacts/replay-desktop-acceptance-01/micro-commands.json --out artifacts/my-save-check
python tools/verify_cleanup_scenario.py --editor artifacts/windows-editor-10/centurions-editor.exe --runtime artifacts/replay-desktop-acceptance-01/runtime/centurions-tools.exe --template artifacts/unchanged-01/imported --installation artifacts/replay-desktop-acceptance-01/installation --commands artifacts/replay-desktop-acceptance-01/micro-commands.json --out artifacts/my-mode5-check
python tools/verify_death_return.py --editor artifacts/windows-editor-10/centurions-editor.exe --runtime artifacts/replay-desktop-acceptance-01/runtime/centurions-tools.exe --template artifacts/unchanged-01/imported --installation artifacts/replay-desktop-acceptance-01/installation --out artifacts/my-death-check
```

Current evidence is under `artifacts/replay-desktop-acceptance-01/`, including
`replay-save/receipt.json`, `cleanup-mode5-final/receipt.json`,
`death-return-final/receipt.json`, `desktop-live/`, and the aggregate `receipt.json`.
The reference installation, previously accepted editor checkpoints/exports and
all runtime gameplay source remain unchanged. No push or publication occurs.
