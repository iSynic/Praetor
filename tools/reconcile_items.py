"""Join the editor's item fields to the reconstruction's capability map by offset.

The editor's descriptor table (`crates/centurions-format/src/items.rs`) gives each field's offset, width and range. The map rows of the family
"item" give the reconstruction's name, readers and editor treatment for the bytes at that offset. A field with no map row at its offset, or whose
row has no readers, is listed for the audit; so are the map rows no editor field reaches."""
import argparse
import json
from pathlib import Path
import re

PLACE = re.compile(r"F::(\w+) => (word|byte|place)\((.*?)\),?\s*$")
ELEMENTS = [140, 64, 66, 68, 70, 72, 74]
# Fields that are runs of bytes: the number of bytes.
TABLES = {"ForbiddenTraits": 2, "ForbiddenSchools": 1, "RequiredTraits": 2, "RequiredSchools": 2, "Abilities": 8}


def editor_fields(source):
    fields = []
    for line in source.read_text(encoding="utf-8").splitlines():
        match = PLACE.search(line.strip())
        if not match:
            continue
        name, kind, arguments = match.groups()
        parts = [p.strip() for p in arguments.split(",")]
        parts[0] = parts[0].split("+")[0].strip()
        if kind == "byte":
            at, width, low, high = int(parts[0]), 1, -128, 127
        elif kind == "word":
            at, width, low, high = int(parts[0]), 2, parts[1], parts[2]
        else:
            at, width, low, high = int(parts[0]), int(parts[1]), parts[3], parts[4]
        fields.append((name, at, width, f"{low}..{high}".replace("ANY.0", "-32768").replace("ANY.1", "32767").replace("i64::from(i32::MAX)", "2147483647")))
    fields.append(("ElementalDamage", 140, 2, "-32768..32767"))  # its descriptor spans several lines
    return fields


def run(args):
    rows = [r for r in json.loads(args.map.read_text())["rows"] if r["kind"] == "record_field" and r["family"] == "item" and r["view"] == "ItemDefinition"]
    scan = json.loads(args.scan.read_text())["by_offset"] if args.scan else {}
    by_offset = {}
    for row in rows:
        if row["offset"] is not None:
            by_offset.setdefault(row["offset"], []).append(row)
    lines = ["| Editor field | Offset | Range | Map accessors at the offset (treatment, readers) | Routines in the scan | Class |", "|---|---|---|---|---|---|"]
    covered = set()
    classes = {}
    for name, at, width, rng in editor_fields(args.source):
        offsets = ELEMENTS if name == "ElementalDamage" else [at + n for n in range(TABLES.get(name, 1))]
        for index, offset in enumerate(offsets):
            found = [r for o in range(offset, offset + width) for r in by_offset.get(o, [])]
            if name == "ElementalDamage":  # the map indexes the seven by element, not by offset
                found = [r for r in rows if r["accessor"] == "elemental_damage"]
            covered.update(r["accessor"] for r in found)
            readers = sum(len(r["readers"]) for r in found)
            scanned = sorted({routine for o in range(offset, offset + width) for window in scan.get(str(o), {}).values() for kind in ("read", "run") for routine in window[kind]})
            klass = "agreed" if readers and scanned else ("map only" if readers else ("scan only" if scanned else ("unread in map" if found else "no map row")))
            classes[klass] = classes.get(klass, 0) + 1
            text = "; ".join(f"{r['accessor']} {r['editor']} {len(r['readers'])}r" for r in found) or "-"
            label = f"{name}[{index}]" if len(offsets) > 1 else name
            lines.append(f"| {label} | {offset:#04x}/{width} | {rng} | {text} | {len(scanned)} | {klass} |")
    lines += ["", f"Classes: {json.dumps(classes, sort_keys=True)}", "", "Map rows no editor field reaches:", "", "| Accessor | Offset | Width | Treatment | Readers |", "|---|---|---|---|---|"]
    for row in sorted(rows, key=lambda r: (r["offset"] is None, r["offset"] or 0)):
        if row["accessor"] not in covered:
            lines.append(f"| {row['accessor']} | {'' if row['offset'] is None else hex(row['offset'])} | {row['width'] or ''} | {row['editor']} | {len(row['readers'])} |")
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(classes, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--source", type=Path, default=Path("crates/centurions-format/src/items.rs"))
    parser.add_argument("--scan", type=Path, default=None, help="the item output of audit_fields.py --family item")
    parser.add_argument("--out", type=Path, required=True)
    run(parser.parse_args())
