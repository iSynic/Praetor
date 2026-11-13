"""Build a level for the original game that uses imported resources, or a renamed item.

From a First Patrol project it imports an icon as number 192, which the game draws as the party marker, and a
picture, and puts a walking trigger at (3, 3), the first square the party walks to from the start, whose steps show that picture and wait for a click. The level is
exported to a new folder, ready for `stage_native_runtime.py` and a run in the original.

    python tools/build_native_resource_level.py --editor target/release/centurions-adapter.exe
        --project artifacts/native-startup-08/first-patrol-project --installation <TheNewCenturions>
        --icon marker.png --picture banner.png --out artifacts/my-native-level
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ICON = -40  # a map square holding this number is drawn as the icon of that number
CELL = (6, 4)
PICTURE = 23360
TRIGGER = (3, 3)  # the first square a click on the map walks the party to from the start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--installation", type=Path, required=True)
    parser.add_argument("--item-name", default="Ration Pack", help="names: the name given to item 800")
    parser.add_argument("--messages", action="store_true", help="calendar: the stories show a message and wait for a click")
    parser.add_argument("--direct", action="store_true", help="calendar: the trigger itself changes the tile, to see the tile change shows at all")
    parser.add_argument("--simple", action="store_true", help="calendar: one entry that always passes, to see whether the scan runs a story at all")
    parser.add_argument("--kind", choices=["resources", "names", "objects", "calendar", "notes", "secrets"], default="resources")
    parser.add_argument("--icon", type=Path)
    parser.add_argument("--picture", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="a new folder")
    args = parser.parse_args()
    process = subprocess.Popen([str(args.adapter)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
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

    installation = str(args.installation).replace("\\", "/")
    opened = ask({"op": "open", "path": str(args.project).replace("\\", "/")})
    step = lambda slot, opcode, operand: {"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": slot, "opcode": opcode, "operand": operand}
    trigger = [
        {"kind": "event_activation", "map": 0, "x": TRIGGER[0], "y": TRIGGER[1], "enabled": True},
        {"kind": "walking_location", "map": 0, "slot": 0, "x": TRIGGER[0], "y": TRIGGER[1]},
        {"kind": "walking_chance", "id": 0, "chance": 100},
    ]
    summary = {}
    if args.kind == "objects":
        # Objects near the start (buildings, an icon), then a copy of the map with them as Map 1,
        # which the stage starts on, so the game must load the added map and draw what its object layer holds.
        stage = next(row for row in opened["result"]["stages"] if int(row["id"]) == 0)
        sx, sy = int(stage["x"]), int(stage["y"])
        objects = [(sx + 2, sy + 1, 55), (sx + 4, sy + 1, 10), (sx + 2, sy + 4, -3001)]
        only_added = (sx + 6, sy + 4, 50)  # painted on the added map alone, so what the game shows must come from it
        edits = [{"kind": "map_object", "map": 0, "x": x, "y": y, "value": value} for x, y, value in objects]
        first = ask({"op": "apply", "expected_revision": opened["revision"], "edits": edits})
        added = ask({"op": "add_map", "expected_revision": first["revision"], "copy_of": 0, "tile": 0, "floor": True, "objects": True, "triggers": True, "regions": True})
        opened = added
        summary = {"objects": objects, "only_on_the_added_map": only_added, "map_count": added["result"].get("maps"), "start": [sx, sy]}
        new_map = int(added["result"]["maps"]) - 1
        edits = [{"kind": "stage_start", "id": 0, "map": new_map, "x": sx, "y": sy}, {"kind": "opening", "map": new_map, "x": sx, "y": sy},
                 {"kind": "map_object", "map": new_map, "x": only_added[0], "y": only_added[1], "value": only_added[2]}]
    elif args.kind == "secrets":
        # Floor cells around the start with the same tile written as it, as 1000 more, 2000 more and 3000 more, to see what the
        # game draws and whether the party can walk on them; the party's walk then searches the squares around it.
        stage = next(row for row in opened["result"]["stages"] if int(row["id"]) == 0)
        sx, sy = int(stage["x"]), int(stage["y"])
        cells = [(sx + 1, sy, 3012), (sx - 1, sy, 2012), (sx, sy + 1, 1012), (sx, sy - 1, 12), (sx + 1, sy + 1, -3012), (sx + 1, sy - 1, 3150)]
        edits = [{"kind": "floor", "map": 0, "x": x, "y": y, "tile": tile} for x, y, tile in cells]
        summary = {"cells": cells, "start": [sx, sy]}
    elif args.kind == "calendar":
        # The trigger sets the clock to the end of day 50, so the game turns the day and scans the calendar for day 51
        # with the party standing on (3, 3). Entry 0 waits for another cell and is passed over; entry 1 waits for
        # this one and changes the floor of (1, 3) through story 377; entry 2 can never pass its chance and ends the scan; entry 3
        # would change the floor of (0, 3) through story 378 if the scan went on. The trigger then shows message 105. Entry 0 would also change (7, 3) if it were not passed over.
        # Each step names a row of its own: the step names a row that suits its code, the step is made independent (a
        # copy in a new row at the end of Data EDCD, 670, 671 and 672 in the order of the edits' names) and the copy is filled in.
        entry = lambda slot, story, chance, x, y, place: {"kind": "calendar_entry", "slot": slot, "day": 51, "interval": 7, "chance": chance,
            "story": story, "map": 0, "region": -1, "x": x, "y": y, "item": -1, "flag": -1, "place": place}
        own = lambda family, id: {"kind": "extra_independent", "family": family, "id": id, "branch": 0, "slot": 0}
        story = lambda id: {"kind": "script_step", "family": "story", "id": id, "branch": 0, "slot": 0, "opcode": 12, "operand": 91}
        if args.direct:
            edits = [{"kind": "script_step", "family": "walking", "id": 0, "branch": 0, "slot": 1, "opcode": 12, "operand": 91},
                     {"kind": "extra_independent", "family": "walking", "id": 0, "branch": 0, "slot": 0},
                     {"kind": "extra_independent", "family": "walking", "id": 0, "branch": 0, "slot": 1},
                     {"kind": "extra_row", "record": 670, "words": [1, 50, 24, 0, 0]},
                     {"kind": "extra_row", "record": 671, "words": [0, 1, 3, 17, 0]},
                     *trigger, step(0, 63, 0), step(2, 1, 105), step(3, 24, 0)]
        elif args.messages:
            line = lambda id, slot, op, operand: {"kind": "script_step", "family": "story", "id": id, "branch": 0, "slot": slot, "opcode": op, "operand": operand}
            edits = [line(377, 0, 1, 103), line(377, 1, 26, 0), line(378, 0, 1, 104), line(378, 1, 26, 0), own("walking", 0),
                     {"kind": "extra_row", "record": 670, "words": [1, 50, 24, 0, 0]},
                     entry(0, 378, 100, 9, 9, 1), entry(1, 377, 100, 4, 4, 1), entry(2, 378, 0, -1, -1, -1), entry(3, 378, 100, -1, -1, -1),
                     *trigger, step(0, 63, 0), step(1, 1, 105), step(2, 24, 0)]
        else:
          edits = [
            story(377), story(378), own("story", 377), own("story", 378), own("walking", 0),
            {"kind": "extra_row", "record": 670, "words": [0, 1, 3, 17, 0]},
            {"kind": "extra_row", "record": 671, "words": [0, 0, 3, 17, 0]},
            {"kind": "extra_row", "record": 672, "words": [1, 50, 24, 0, 0]},
            *([entry(0, 377, 100, -1, -1, -1)] if args.simple else [
                entry(0, 378, 100, 9, 9, 1), entry(1, 377, 100, 4, 4, 1), entry(2, 378, 0, -1, -1, -1), entry(3, 378, 100, -1, -1, -1)]),
            *trigger,
            step(0, 63, 0),
            step(1, 1, 105),
            step(2, 24, 0),
        ]
        summary = {"day_before": 50, "expected": "the floor of (1, 3) changes and the floor of (0, 3) does not"}
    elif args.kind == "notes":
        # The Maps and Notes menu lists the labels; a note the party does not have shows its first label, disabled.
        label = lambda note, identified, text: {"kind": "note_label", "note": note, "identified": identified, "text": text}
        edits = [label(1, False, "Cave We Have Not Seen"), label(1, True, "The Cave We Found"), label(2, False, "Second Place, Unknown")]
        # Note 0 is a section of the first map with a mark; note 1 is a picture. The trigger gives note 0 (the menu then enables its
        # item) and shows note 1 at once.
        note = lambda n, **fields: {"kind": "map_note", "note": n, **{"marks": [[0, 0, 0]] * 10, "start_x": 0, "start_y": 0, "level": 0, "picture": 0,
            "icon_size": 32, "show": 0, "bottom": 0, "right": 0, "text": "", **fields}}
        edits += [note(0, marks=[[137, 3, 3]] + [[0, 0, 0]] * 9, icon_size=32, text="A section of the first map, marked where the squad lands."),
                  note(1, picture=23010, text="A picture note."),
                  *trigger, step(0, 29, 0), step(1, 29, -1), step(2, 24, 0)]
        summary = {"expected": "the picture note shows when the trigger fires; the menu's first item reads The Cave We Found and shows the section"}
    elif args.kind == "names":
        # The trigger awards reward row 0, which holds scenario item 800, renamed; the loot list names it.
        edits = [
            {"kind": "item_name", "index": 0, "name": args.item_name},
            {"kind": "reward_item", "id": 0, "slot": 0, "item": 800, "level": 0},
            *trigger,
            step(0, 10, 0),
            step(1, 24, 0),
        ]
    else:
        icon = ask({"op": "import_prepare", "kind": "icon", "path": str(args.icon.resolve()).replace("\\", "/"), "id": ICON, "options": {}, "installation": installation})["result"]
        picture = ask({"op": "import_prepare", "kind": "picture", "path": str(args.picture.resolve()).replace("\\", "/"), "id": PICTURE, "options": {}, "installation": installation})["result"]
        summary = {"icon_bytes": icon["bytes"], "picture_bytes": picture["bytes"], "picture_colours": picture["colours"]}
        edits = [
            {"kind": "resource_change", "resource_type": "cicn", "id": ICON, "data": icon["data"]},
            {"kind": "resource_change", "resource_type": "PICT", "id": PICTURE, "data": picture["data"]},
            {"kind": "floor", "map": 0, "x": CELL[0], "y": CELL[1], "tile": ICON},
            *trigger,
            step(0, 27, PICTURE),
            step(1, 26, 0),
            step(2, 24, 0),
        ]
    applied = ask({"op": "apply", "expected_revision": opened["revision"], "edits": edits})
    exported = ask({"op": "export", "expected_revision": applied["revision"], "destination": str(args.out.resolve()).replace("\\", "/")})
    process.stdin.close()
    print(json.dumps({"level": str(args.out), **summary, "export": exported.get("result")}, default=str)[:600])

if __name__ == "__main__":
    main()
