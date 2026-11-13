"""Author script steps with the editor, export the scenario and play it in the reconstructed runtime.

A walking trigger is placed on the first square of the mission's route and given a sound (code 9), an animation (code 128, an Extra Codes
row that the step first shares and then takes for itself) and a redraw (code 28). The scenario is exported over a scratch copy of an installation that
holds the mission, and the runtime replays a step onto the trigger. The check passes when the runtime ran the authored steps and reported the
sound, the animation with the words of the new row, and the redraw, in that order.

`--installation` names a scratch installation made by Play from here (it holds `Scenarios/<mission>/0`); it is copied, never changed."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

SHARED_ROW = 189  # a row of the shipped scenario that code 128 already reads
WORDS = [7, 12, 9, 64, 2]  # effect, column, row, size, delay


def run(command):
    result = subprocess.run([str(part) for part in command], capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        sys.exit(f"{command[0]} failed: {result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor", type=Path, required=True)
    parser.add_argument("--tools", type=Path, required=True, help="centurions-tools.exe of the reconstructed runtime")
    parser.add_argument("--installation", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True, help="a project of the mission, such as the first-patrol project")
    parser.add_argument("--mission", default="First Patrol")
    parser.add_argument("--out", type=Path, required=True, help="a new folder")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    scratch = args.out / "installation"
    shutil.copytree(args.installation, scratch)
    sound = 4321
    # The new row is the one after the last: Make this step independent appends it.
    inspect = json.loads(run([args.editor, "inspect", args.project]))
    rows = next(t["complete_records"] for t in inspect["tables"] if t["file"] == "Data EDCD")
    edits = [
        {"kind": "event_activation", "map": 0, "x": 3, "y": 2, "enabled": True},
        {"kind": "walking_location", "map": 0, "slot": 0, "x": 3, "y": 2},
        {"kind": "walking_chance", "id": 0, "chance": 100},
        {"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": 0, "opcode": 9, "operand": sound},
        {"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": 1, "opcode": 128, "operand": SHARED_ROW},
        {"kind": "extra_independent", "family": "walking", "id": 0, "branch": 0, "slot": 1},
        {"kind": "extra_row", "record": rows, "words": WORDS},
        {"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": 2, "opcode": 28, "operand": 0},
        {"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": 3, "opcode": 24, "operand": 0},
    ]
    changes = args.out / "edits.json"
    changes.write_text(json.dumps(edits), encoding="utf-8")
    run([args.editor, "edit", args.project, changes, args.out / "project"])
    run([args.editor, "export", args.out / "project", args.out / "level"])
    for source in (args.out / "level").iterdir():
        shutil.copyfile(source, scratch / "Scenarios" / args.mission / "0" / source.name)
    commands = args.out / "commands.json"
    commands.write_text(json.dumps(["ImportStarters", {"SelectStarters": {"indices": [0, 1, 2, 3, 4, 5]}}, {"EnterMission": {"name": args.mission}}, {"Move": {"dx": 1, "dy": 0}}]), encoding="utf-8")
    output = run([args.tools, "replay", scratch, commands, "--trace"])
    steps = [json.loads(line) for line in output.splitlines() if line.startswith('{"kind":"story"')]
    played = [(step["opcode"], step["parameter"]) for step in steps]
    expected = [(9, sound), (128, rows), (28, 0), (24, 0)]
    if played != expected:
        sys.exit(f"the runtime played {played}, expected {expected}")
    events = next(json.loads(line) for line in output.splitlines() if line.startswith("[") and "OutdoorEffect" in line)
    names = [next(iter(event)) if isinstance(event, dict) else event for event in events]
    effect = next(event["OutdoorEffect"] for event in events if isinstance(event, dict) and "OutdoorEffect" in event)
    if [effect[key] for key in ("effect", "x", "y", "size", "delay")] != WORDS:
        sys.exit(f"the animation was {effect}, expected the words {WORDS}")
    if not names.index("Sound") < names.index("OutdoorEffect") < names.index("ScreenRedrawn"):
        sys.exit(f"the events came in the order {names}")
    print(json.dumps({"status": "passed", "played": played, "events": names, "animation": effect}))


if __name__ == "__main__":
    main()
