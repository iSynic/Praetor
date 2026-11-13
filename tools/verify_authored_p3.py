"""Author a scenario with what the editor adds in P1 to P3 and replay it in the reconstruction.

Over the unchanged Thunder of Guns level the script names an item, adds a scrolling text, paints buildings and an icon on
Map 0, writes a calendar entry, adds a copy of Map 0 as the next map and starts the first stage on it. The level is exported
into a disposable copy of the installation (never the installation itself) and the reconstruction's replay tool enters the
mission; the check is that the reconstruction loads the added map, its objects and the calendar as authored.

    python tools/verify_authored_p3.py --adapter target/release/centurions-adapter.exe
        --project artifacts/unchanged-01/imported --installation <TheNewCenturions>
        --reference <the reconstruction checkout> --out artifacts/my-p3-replay
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--installation", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="a new folder under artifacts")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / "artifacts"):
        raise ValueError("output must be a new artifacts directory")
    out.mkdir(exist_ok=False)
    process = subprocess.Popen([str(args.adapter.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    count = 0

    def ask(operation):
        nonlocal count
        count += 1
        process.stdin.write(json.dumps({"protocol": 1, "id": count, "operation": operation}) + "\n")
        process.stdin.flush()
        reply = json.loads(process.stdout.readline())
        if not reply.get("ok"):
            sys.exit(f"{operation['op']} failed: {reply.get('error')}")
        return reply

    opened = ask({"op": "open", "path": str(args.project.resolve()).replace("\\", "/")})
    stage = next(row for row in opened["result"]["stages"] if int(row["id"]) == 0)
    sx, sy = int(stage["x"]), int(stage["y"])
    buildings = [(sx + 3, sy + 1, 55), (sx + 5, sy + 1, 10)]
    icon = (sx + 3, sy + 4, -3001)
    edits = [{"kind": "item_name", "index": 0, "name": "Ration Pack"},
             {"kind": "scroll_text", "id": 2000, "text": "A scrolling text of the authored scenario.", "runs": None},
             *[{"kind": "map_object", "map": 0, "x": x, "y": y, "value": v} for x, y, v in [*buildings, icon]]]
    applied = ask({"op": "apply", "expected_revision": opened["revision"], "edits": edits})
    added = ask({"op": "add_map", "expected_revision": applied["revision"], "copy_of": 0, "tile": 0, "floor": True,
                 "objects": True, "triggers": True, "regions": True})
    new_map = int(added["result"]["maps"]) - 1
    assert new_map == 10, new_map
    # The calendar entry names the added map, so it is written after the map exists.
    started = ask({"op": "apply", "expected_revision": added["revision"], "edits": [
        {"kind": "stage_start", "id": 0, "map": new_map, "x": sx, "y": sy},
        {"kind": "opening", "map": new_map, "x": sx, "y": sy},
        # Only the added map holds this building, so a map that loads can only be that one.
        {"kind": "map_object", "map": new_map, "x": sx + 6, "y": sy + 2, "value": 20},
        {"kind": "calendar_entry", "slot": 2, "day": 5, "interval": 7, "chance": 80, "story": 0, "map": new_map, "region": -1,
         "x": sx, "y": sy, "item": 800, "flag": 3, "place": 1}]})
    level = out / "level"
    ask({"op": "export", "expected_revision": started["revision"], "destination": str(level).replace("\\", "/")})
    process.stdin.close()

    installation = out / "installation"
    shutil.copytree(args.installation, installation)
    # The prebuilt runtime finds scenario data through its Thunder loader; the alias lives only in this disposable copy.
    shutil.copytree(level, installation / "Scenarios/The Thunder of Guns/0", dirs_exist_ok=True)
    binary = args.reference / "target/release/centurions-tools.exe"
    before = digest(binary)
    prefix = ["ImportStarters", {"SelectStarters": {"indices": list(range(6))}}, {"EnterMission": {"name": "The Thunder of Guns"}}]

    def replay(commands, name):
        path = out / f"{name}-commands.json"
        path.write_text(json.dumps(commands, indent=2), encoding="utf8")
        run = subprocess.run([str(binary.resolve()), "replay", str(installation), str(path)], capture_output=True, text=True, encoding="utf8", timeout=90)
        (out / f"{name}.stderr").write_text(run.stderr, encoding="utf8")
        if run.returncode:
            raise RuntimeError(run.stderr)
        decoder, rest, values = json.JSONDecoder(), run.stdout.lstrip(), []
        while rest:
            value, end = decoder.raw_decode(rest)
            values.append(value)
            rest = rest[end:].lstrip()
        return values[-1]

    commands = list(prefix)
    state = replay(commands, "enter")
    for attempt in range(40):
        if state.get("phase") == "Exploration" and state.get("exploration"):
            break
        commands.append("Continue")
        state = replay(commands, f"enter-{attempt:02}")
    (out / "state.json").write_text(json.dumps(state, indent=2), encoding="utf8")
    place = state["exploration"]
    checks = {
        "phase": state["phase"] == "Exploration",
        "starts_on_the_added_map": place["map"] == new_map and (place["x"], place["y"]) == (sx, sy),
        "objects_loaded": all(place["objects"][x * 90 + y] == v for x, y, v in [*buildings, icon]) and place["objects"][(sx + 6) * 90 + sy + 2] == 20,
        "calendar_entry_loaded": len(place["schedule"]) >= 120,
    }
    schedule = place["schedule"]
    row = bytes(schedule[2 * 40:3 * 40]) if isinstance(schedule, list) else bytes.fromhex(schedule)[2 * 40:3 * 40]
    fields = [int.from_bytes(row[n * 2:n * 2 + 2], "big", signed=True) for n in range(11)]
    checks["calendar_fields_as_authored"] = fields == [5, 7, 80, 0, 10, -1, sx, sy, 800, 3, 1]
    receipt = {"authority": "read-only prebuilt reconstruction replay; not original-game acceptance", "status": "passed" if all(checks.values()) else "failed",
               "checks": checks, "map": place["map"], "calendar_entry_2": fields, "tool_unchanged": digest(binary) == before}
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf8")
    print(json.dumps(receipt, indent=2))
    sys.exit(0 if receipt["status"] == "passed" else 1)


if __name__ == "__main__":
    main()
