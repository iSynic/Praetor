"""Map every access to a record's bytes in the original's decompiled routines.

The decompiler names a global by its address, so a field of a record array reached as
`(&DAT_00439e43)[body * 0x120]` is the byte 0x107 of the record whose array starts at 0x439d3c.
A pointer built from the array (`p = (undefined4 *)(&DAT_00439d3c + body * 0x90)`) is followed through
`p[k]`, `*(T *)((long)p + c)` and `*p`. An access whose index is a variable (`(&DAT_00439dee)[slot + body * 0x120]`)
is recorded as a run starting at that byte. Each window is one place the original keeps the record."""
import argparse
import collections
import json
from pathlib import Path
import re

# Where the original keeps a monster: the array of fighting bodies (288 bytes each) and the record being built.
# A window is (first address, record size, records); a field is the address's place in its record.
MONSTER_WINDOWS = {"bodies": (0x439D3C, 288, 1), "build": (0x440DBC, 288, 1)}
# Where it keeps an item definition: the one in use, and the thousand it loaded (150 bytes each).
ITEM_WINDOWS = {"item": (0x45363C, 150, 1), "table": (0x4537FE, 150, 1000)}
# The land in play: the region table loaded from Data RD (644 bytes).
REGION_WINDOWS = {"land": (0x443086, 644, 1)}
# The typed encounter in play (156-byte header) and the menu encounter (106-byte header).
ENCOUNTER_WINDOWS = {"typed": (0x443396, 156, 1), "menu": (0x443432, 106, 1)}
# A battle record (1372 bytes) as combat loads it.
BATTLE_WINDOWS = {"battle": (0x43979C, 1372, 1)}
WINDOWS = MONSTER_WINDOWS
SIZES = {"undefined": 1, "undefined1": 1, "byte": 1, "char": 1, "uchar": 1, "undefined2": 2, "short": 2, "ushort": 2,
         "undefined4": 4, "int": 4, "uint": 4, "long": 4, "ulong": 4, "undefined8": 8}
NAME = re.compile(r"(?<![A-Za-z0-9_])_?DAT_([0-9a-f]{8})(\._?\d+_\d+_)?")
DECLARATION = re.compile(r"^\s*([A-Za-z0-9_]+) \*([A-Za-z0-9_]+);")
POINTER = re.compile(r"^\s*([A-Za-z0-9_]+) = (?:\(([A-Za-z0-9_]+) \*\))?\(?&DAT_([0-9a-f]{8})")


def window_of(address):
    for window, (base, size, count) in WINDOWS.items():
        if base <= address < base + size * count:
            return window, (address - base) % size
    return None, None


def is_write(line, start, end):
    before = line[:start].strip()
    after = line[end:].strip()
    return bool(re.match(r"(\)|\])*\s*(\[[^\]]*\]\s*)*=[^=]", after)) and not before.startswith(("if", "while", "return"))


def scan(directory):
    """field offset -> window -> {"read": routines, "write": routines}; indexed runs are recorded at their first byte."""
    found = collections.defaultdict(lambda: collections.defaultdict(lambda: {"read": set(), "write": set(), "run": set()}))

    def note(offset, window, routine, written, run=False):
        if 0 <= offset < WINDOWS[window][1]:
            found[offset][window]["run" if run else ("write" if written else "read")].add(routine)

    for path in sorted(directory.glob("*.c")):
        routine = path.name.rsplit("_", 1)[0]
        lines = path.read_text(errors="replace").splitlines()
        kinds = {}
        for line in lines:
            match = DECLARATION.match(line)
            if match:
                kinds[match.group(2)] = SIZES.get(match.group(1), 1)
        pointers = {}
        for line in lines:
            for match in NAME.finditer(line):
                window, offset = window_of(int(match.group(1), 16))
                if window:
                    indexed = bool(re.match(r"\)?\s*\[[^\]]*[A-Za-z_][^\]]*\]", line[match.end():].lstrip(")")))
                    note(offset, window, routine, is_write(line, match.start(), match.end()), indexed and not line[match.end():].lstrip(")").startswith("[(ulong)"))
            assign = POINTER.match(line)
            if assign:
                window, offset = window_of(int(assign.group(3), 16))
                if window:
                    pointers[assign.group(1)] = (window, offset, SIZES.get(assign.group(2), kinds.get(assign.group(1), 4)) if assign.group(2) else kinds.get(assign.group(1), 4))
                elif assign.group(1) in pointers:
                    del pointers[assign.group(1)]
            for name, (window, base, size) in pointers.items():
                for use in re.finditer(r"(?<![A-Za-z0-9_])" + name + r"\[(\d+)\]", line):
                    note(base + int(use.group(1), 0) * size, window, routine, is_write(line, use.start(), use.end()))
                for use in re.finditer(r"\(\(long\)" + name + r" \+ (-?(?:0x)?[0-9a-f]+)\)", line):
                    note(base + int(use.group(1), 0), window, routine, False)
                for use in re.finditer(r"\*" + name + r"(?![A-Za-z0-9_\[])", line):
                    note(base, window, routine, is_write(line, use.start(), use.end()))
                for use in re.finditer(r"(?<![A-Za-z0-9_])" + name + r"\[[^\]\d][^\]]*\]", line):
                    note(base, window, routine, False, run=True)
    return found


def run(args):
    global WINDOWS
    if args.family == "item":
        WINDOWS = ITEM_WINDOWS
    elif args.family == "region":
        WINDOWS = REGION_WINDOWS
    elif args.family == "encounter":
        WINDOWS = ENCOUNTER_WINDOWS
    elif args.family == "battle":
        WINDOWS = BATTLE_WINDOWS
    elif args.family == "custom":
        WINDOWS = {}
        for text in args.window:
            name, base, size, count = text.split(":")
            WINDOWS[name] = (int(base, 0), int(size), int(count))
    found = scan(args.decompiled)
    if args.family in ("item", "region", "encounter", "battle", "custom"):
        size = max(width for _, width, _ in WINDOWS.values())
        covered = {off: {w: {k: sorted(v) for k, v in d.items()} for w, d in windows.items()} for off, windows in found.items()}
        args.out.write_text(json.dumps({"by_offset": covered}, indent=1) + chr(10))
        for off in range(size):
            names = {}
            for window in found.get(off, {}).values():
                for kind in ("read", "write", "run"):
                    for routine in window[kind]:
                        names.setdefault(routine, set()).add(kind[0])
            print(f"{off:#04x} " + " ".join(f"{r}:{''.join(sorted(k))}" for r, k in sorted(names.items())))
        if args.family == "custom":
            for window in WINDOWS:
                print("==", window)
                for off in sorted(found):
                    entry = found[off].get(window)
                    if entry:
                        print(f"{off:#04x} {off} R: {sorted(entry['read'] | entry['run'])} W: {sorted(entry['write'])}")
        return
    record = json.loads(args.record.read_text())
    # The fields the editor edits that the projection does not list with an offset.
    extra = [("name", 0xDA, 30), ("level", 0, 2), ("stamina_bonus", 2, 2), ("agility", 4, 2), ("movement", 6, 2), ("run_percent", 0x44, 2),
             ("turn_chance", 0x5C, 2), ("turn_story", 0x5E, 2), ("death_story", 0x60, 2)] + [("spell", 0x12 + 2 * n, 2) for n in range(10)]
    for index, (name, offset, width) in enumerate(extra):
        record["fields"].append({"field": name, "index": index if name == "spell" else 0, "offset": offset, "width": width})
    covered = {off: {w: {k: sorted(v) for k, v in d.items()} for w, d in windows.items()} for off, windows in found.items()}
    report = {"touched_offsets": sorted(found), "fields": []}
    for row in record["fields"]:
        span = range(row["offset"], row["offset"] + row["width"])
        reads, writes, runs = set(), set(), set()
        for off in span:
            for window in found.get(off, {}).values():
                reads |= window["read"]
                writes |= window["write"]
                runs |= window["run"]
        report["fields"].append({"field": row["field"], "index": row["index"], "offset": row["offset"], "width": row["width"],
                                 "readers": sorted(reads), "writers": sorted(writes), "runs": sorted(runs)})
    unreferenced = [o for o in range(288 if args.family == "monster" else 150) if o not in found]
    report["unreferenced"] = unreferenced
    args.out.write_text(json.dumps({"by_offset": covered, **report}, indent=1) + "\n")
    print(json.dumps({"touched": len(found), "unreferenced": len(unreferenced)}))
    for item in report["fields"]:
        state = "READ" if item["readers"] else ("RUN" if item["runs"] else ("WRITE-ONLY" if item["writers"] else "NONE"))
        print(f'{item["offset"]:#05x} w{item["width"]} {state:10s} {item["field"]}[{item["index"]}] {len(item["readers"])}r/{len(item["writers"])}w/{len(item["runs"])}run')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decompiled", type=Path, required=True)
    parser.add_argument("--window", action="append", default=[], help="name:first address:record size:records, for --family custom")
    parser.add_argument("--family", choices=["monster", "item", "region", "encounter", "battle", "custom"], default="monster")
    parser.add_argument("--record", type=Path, default=None, help="a monster record as the editor's CLI prints it")
    parser.add_argument("--out", type=Path, required=True)
    run(parser.parse_args())
