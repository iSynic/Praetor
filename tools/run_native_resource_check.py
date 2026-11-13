"""Run a level in the original game and take pictures of what it draws.

Stages a level into a disposable disk (`stage_native_runtime.py`), starts the emulator with its guest harness,
takes the game from the Finder to the first mission with the clicks recorded for First Patrol, and saves
screenshots after the mission opens. Only the emulator process this run started is ever stopped.

    python tools/run_native_resource_check.py --level artifacts/my-native-level --out artifacts/my-native-run
        --pydeps artifacts/pydeps --reference <the reconstruction checkout> --rom <Quadra-650.ROM>
"""
import argparse
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).parent))
from native_guest import request  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--level", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="a new folder under artifacts")
    parser.add_argument("--pydeps", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--scenario-name", default="First Patrol")
    parser.add_argument("--tail", choices=["resources", "calendar", "notes"], default="resources", help="what to do after the party reaches the trigger")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    staged = subprocess.run([sys.executable, str(here / "stage_native_runtime.py"), "--reference", str(args.reference),
                             "--pydeps", str(args.pydeps), "--rom", str(args.rom), "--level", str(args.level),
                             "--out", str(args.out), "--scenario-name", args.scenario_name], capture_output=True, text=True)
    if staged.returncode:
        sys.exit(staged.stdout + staged.stderr)
    out = args.out.resolve()
    runtime = out / "runtime"
    process = subprocess.Popen([str(runtime / "BasiliskII.exe"), "--config", str(runtime / "BasiliskII_prefs"), "--divinity-harness"],
                               cwd=runtime, stdout=open(runtime / "launch.stdout.log", "w"), stderr=open(runtime / "launch.stderr.log", "w"),
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    (runtime / "owned.pid").write_text(str(process.pid))
    try:
        for _ in range(60):
            if (runtime / "divinity-harness-token.txt").exists():
                break
            time.sleep(1)
        time.sleep(12)

        def act(*arguments, wait=1.0):
            reply = request(runtime, *arguments)
            time.sleep(wait)
            return reply

        def snap(name):
            act("snapshot-framebuffer", "--out", f"{out.as_posix()}/{name}.png", wait=0.5)

        click = lambda x, y, wait=1.0: act("mouse-click", "--x", x, "--y", y, wait=wait)
        drag = lambda a, b, c, d, wait=2.0: act("mouse-drag", "--from-x", a, "--from-y", b, "--to-x", c, "--to-y", d, wait=wait)
        key = lambda code, wait=1.0: act("press-key", "--mac-keycode", code, wait=wait)
        # The Finder: dismiss the shutdown notice, open the test disk's game folder, list it, open the game.
        key("0x24", 4)
        act("mouse-double-click", "--x", 759, "--y", 104, wait=2)
        act("mouse-double-click", "--x", 39, "--y", 94, wait=3)
        drag(132, 10, 156, 47)
        act("type-text", "--text", "New Centurions", wait=1)
        act("press-chord", "--modifiers", "command", "--mac-keycode", "0x1f", wait=12)
        snap("01-launch")
        # The game's notices about sound and music, the title, the start of a mission.
        click(400, 348, 3)
        key("0x24", 4)
        click(241, 163, 2)
        click(622, 460, 3)
        drag(113, 10, 163, 94)
        drag(113, 10, 165, 31, 3)
        snap("02-squad")
        for _ in range(2):
            click(151, 117)
            click(325, 125)
            click(326, 325, 3)
            click(225, 195, 2)
        snap("03-after-squad")
        click(241, 163, 6)
        key("0x24", 5)
        snap("04-mission")
        click(225, 195, 2)
        snap("05-after-popup")
        # A click on the map walks the party; the trigger waits where it stops.
        click(225, 195, 1.5)
        snap("06-walking")
        time.sleep(3)
        snap("07-walked")
        if args.tail == "notes":
            # The picture note (note 1) shows at once, then waits for a click in its box; the section note is chosen from the menu.
            snap("08-picture-note")
            click(230, 250, 2.5)
            snap("09-after-click")
            click(225, 195, 2.5)
            snap("10-after-help")
            click(370, 9, 1.5)  # the Maps and Notes menu
            snap("11-menu")
            click(430, 94, 3.0)  # its first note, which the trigger gave
            snap("12-section-note")
            return
        if args.tail == "calendar":
            # What the game holds after the walk: its clock, its map and position, and the last calendar record it read.
            import json as _json
            read = lambda at, n: bytes.fromhex(request(runtime, "read-memory", "--address", hex(at), "--length", str(n))["hex"])
            a5 = int.from_bytes(read(0x904, 4), "big")
            word = lambda at: int.from_bytes(read(a5 + at - 0x400000, 2), "big", signed=True)
            long = lambda at: int.from_bytes(read(a5 + at - 0x400000, 4), "big", signed=True)
            record = read(a5 + 0x439d14 - 0x400000, 40)
            sbyte = lambda at: int.from_bytes(read(a5 + at - 0x400000, 1), "big", signed=True)
            state = {"day": word(0x4427d4), "hour": word(0x4427ca), "minute": word(0x4427c8), "map": long(0x442774),
                     "x": long(0x442764) + long(0x442778), "y": long(0x442768) + long(0x44277c), "x_game": long(0x442778) + long(0x442764) + sbyte(0x442736), "y_game": long(0x44277c) + long(0x442768) + sbyte(0x442737), "parts": [long(0x442764), long(0x442778), sbyte(0x442736), long(0x442768), long(0x44277c), sbyte(0x442737)],
                     "calendar_record": [int.from_bytes(record[n:n + 2], "big", signed=True) for n in range(0, 22, 2)]}
            (out / "memory.json").write_text(_json.dumps(state, indent=2))
            print(_json.dumps(state))
            # The scan runs the story of the entry that passes: its message, then the trigger's own.
            click(230, 250, 2.5)  # inside the game's "Click Mouse" box; the first story ends
            snap("08-first-click")
            click(225, 195, 2.5)  # the game's help popup, shown the first time something is clicked
            snap("09-after-help")
            click(230, 250, 2.5)
            snap("10-second-click")
            click(225, 195, 2.5)
            snap("11-after-help")
            record = read(a5 + 0x439d14 - 0x400000, 40)
            state["calendar_record_at_the_end"] = [int.from_bytes(record[n:n + 2], "big", signed=True) for n in range(0, 22, 2)]
            (out / "memory.json").write_text(_json.dumps(state, indent=2))
            print(_json.dumps(state["calendar_record_at_the_end"]))
            return
        # A reward opens the game's bounty screen, behind a help popup the first time.
        click(225, 195, 2)
        snap("08-after-popup")
        # Selecting the item in the loot shows what the game says of it.
        click(36, 50, 2)
        snap("09-item-selected")
    finally:
        process.terminate()
    print(f"snapshots in {out}")


if __name__ == "__main__":
    main()
