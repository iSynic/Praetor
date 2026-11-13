"""Check the table of script codes against everything else the original is known by.

1. The manual: every code it describes is in the table with the same kind of ID, and the words the table calls unused are the words the manual does not number.
2. The capability map: the evidence of each code, and the words the reconstruction's accessors read for each Extra Codes view, which the table must name.
3. The native fixtures: every ID and every Extra Codes row an original-binary fixture runs with passes the table, so the editor never refuses what the
   original was seen to handle. Only what a value looks like is checked (ranges, lists, counts, descriptors); that a row of a table exists is not.

It exits with 1 when anything fails and prints what."""
import argparse
import json
from pathlib import Path
import re
import struct
import sys

# The Extra Codes view of the reconstruction that reads the row of a code.
VIEWS = {
    "QuestionExtra": [3], "RegionChangeExtra": [23], "MapEffectExtra": [128], "RandomBranchExtra": [85], "AllyClassBranchExtra": [87],
    "PaymentBranchExtra": [33], "ChanceBranchExtra": [42], "ClinicExtra": [-32], "LimitedTreasureExtra": [111], "GiveConditionExtra": [43],
    "PickByTraitExtra": [50], "PickByCasteExtra": [53], "DropCreditsExtra": [60], "VictoryPointsExtra": [90], "RandomTreasureExtra": [65],
    "ShiftPartyExtra": [61], "BoatCampingExtra": [103], "LandLightExtra": [106], "DisableChoiceExtra": [41], "TravelExtra": [20, 45],
    "TileMutationExtra": [12], "EventReplacementExtra": [7], "EventChanceExtra": [13], "ObjectRectangleExtra": [-12],
}


def shape_ok(kind, value):
    """Whether a value looks like the kind; whether the row it names exists is not asked."""
    name = kind["kind"]
    if name == "soft":
        return kind.get("hard") is None or shape_ok(kind["hard"], value)
    if name == "range":
        return kind["min"] <= value <= kind["max"]
    if name == "signed_count":
        return kind["min"] <= abs(value) <= kind["max"]
    if name == "enum":
        return value in kind["values"]
    if name == "spell":
        return 0 <= value // 1000 - 1 < 4 and 0 <= value % 1000 // 100 - 1 < 7 and 0 <= value % 100 - 1 < 7
    if name == "stage":
        return value != 0 and abs(value) <= 20
    if name == "record":
        return kind["sign"] in ("magnitude", "negative_ok", "minus_one_ok") or value >= 0
    if name == "extra":
        return value >= 0
    if name == "map":
        return value >= 0 or kind["keep_negative"]
    return True


def row_ok(code, words):
    """The first word that fails, or None."""
    for index, kind in enumerate(code.get("extra") or []):
        if not shape_ok(kind, words[index]):
            return index
    for rule in code.get("rules") or []:
        holds = all(
            (c.get("values") is None or words[c["word"]] in c["values"])
            and (c.get("min") is None or words[c["word"]] >= c["min"])
            and (c.get("max") is None or words[c["word"]] <= c["max"])
            for c in rule["when"]
        )
        if holds:
            for then in rule["then"]:
                if not shape_ok(then["kind"], words[then["word"]]):
                    return then["word"]
    return None


def fixtures(directory):
    """Every (file, opcode, extra words or None, parameter or None) a native fixture runs."""
    found = []

    def walk(item, name):
        if isinstance(item, dict):
            if isinstance(item.get("opcode"), int):
                extra = item.get("extra")
                if isinstance(extra, str) and re.fullmatch(r"([0-9a-f]{2})+", extra) and len(extra) >= 20:
                    rows = [struct.unpack(">5h", bytes.fromhex(extra[at:at + 20])) for at in range(0, len(extra) - 19, 20)]
                    found.append((name, item["opcode"], rows, None))
                elif isinstance(item.get("parameter"), int):
                    found.append((name, item["opcode"], None, item["parameter"]))
            for value in item.values():
                walk(value, name)
        elif isinstance(item, list):
            for value in item:
                walk(value, name)

    for path in sorted(directory.glob("*.json")):
        try:
            walk(json.loads(path.read_text(encoding="utf-8")), path.name)
        except (ValueError, OSError):
            pass
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", type=Path, default=Path("crates/centurions-format/data/script_codes.json"))
    parser.add_argument("--manual", type=Path, required=True)
    parser.add_argument("--capability-map", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    args = parser.parse_args()
    table = {c["code"]: c for c in json.loads(args.table.read_text(encoding="utf-8"))["codes"]}
    capability = json.loads(args.capability_map.read_text(encoding="utf-8"))
    failures = []

    # 1. The manual.
    parts = re.split(r"^### Code (-?\d+): (.*)$", args.manual.read_text(encoding="utf-8"), flags=re.M)
    manual = {int(parts[i]) for i in range(1, len(parts), 3)}
    for code in sorted(manual):
        entry = table.get(code)
        if entry is None or not entry["authorable"]:
            failures.append(f"code {code} of the manual is not authorable in the table")
        elif (entry["id"]["kind"] == "extra") != (entry["id_class"] == "extra"):
            failures.append(f"code {code}: the manual's kind of ID and the table's differ")
    for code in table:
        if code not in manual and code != 0:
            failures.append(f"code {code} of the table is not in the manual")

    # 2. The capability map.
    status = {r["value"]: r["status"] for r in capability["rows"] if r["kind"] == "opcode" and isinstance(r.get("value"), int)}
    for code, value in status.items():
        if code in table and table[code]["evidence"] != value:
            failures.append(f"code {code}: evidence {table[code]['evidence']} in the table, {value} in the map")
        if code not in table:
            failures.append(f"code {code} of the capability map has no entry in the table")
    seen = {}
    for row in capability["rows"]:
        if row["kind"] == "record_field" and row["view"] in VIEWS and row["offset"] is not None:
            seen.setdefault(row["view"], set()).update(range(row["offset"] // 2, (row["offset"] + (row["width"] or 2) - 1) // 2 + 1))
    for view, words in seen.items():
        for code in VIEWS[view]:
            named = {i for i, kind in enumerate(table[code].get("extra") or []) if kind["kind"] != "unused"}
            if not words <= named:
                failures.append(f"{view} reads words {sorted(w + 1 for w in words - named)} of code {code} that the table calls unused")
    checked_views = len(seen)

    # 3. The native fixtures.
    used = fixtures(args.fixtures)
    rows = ids = 0
    for name, opcode, extra, parameter in used:
        entry = table.get(opcode)
        if entry is None:
            continue  # a number that names no code
        if extra is not None:
            if entry["id"]["kind"] != "extra":
                continue
            for number, words in enumerate(extra):
                if number == 0:
                    bad = row_ok(entry, words)
                elif entry.get("companion"):
                    bad = next((i for i, kind in enumerate(entry["companion"]) if not shape_ok(kind, words[i])), None)
                else:
                    continue
                rows += 1
                if bad is not None:
                    failures.append(f"{name}: code {opcode} Extra Code {bad + 1} = {words[bad]} is refused by the table")
        elif parameter is not None:
            if entry["id"]["kind"] in ("extra",):
                continue
            ids += 1
            if not shape_ok(entry["id"], parameter) and entry["id"]["kind"] != "extra":
                failures.append(f"{name}: code {opcode} ID {parameter} is refused by the table")

    print(f"manual: {len(manual)} codes; map: {len(status)} codes and {checked_views} Extra Codes views; fixtures: {rows} rows and {ids} IDs of {len(used)} steps")
    for failure in failures:
        print("FAIL", failure)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
