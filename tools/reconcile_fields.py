"""Join the editor's monster fields to the reconstruction's capability map and to the audit's scan of the original.

Each editor field is matched, by the name the reconstruction gives the same bytes, to its row in `evidence/capability-map.json`
(offset, width, readers, editor treatment). A field is *agreed* when the map row sits at the same offset and has readers, and the scan
of the decompiled original also reaches the bytes; *map only* or *scan only* when one source lacks it; *conflict* when the offsets differ;
*none* when neither reaches it. The map rows no editor field covers are listed so that nothing the original reads is left unknown."""
import argparse
import json
from pathlib import Path

# Editor field -> the reconstruction's accessor for the same bytes (family "monster").
ACCESSOR = {
    "icon": "icon", "size": "size", "faction": "faction", "flying": "flying_flag", "capturable": "capture_flag",
    "mechanical": "mechanical_state", "survivor_marker": "survivor_marker", "armor": "armor_rating",
    "weapon_immunity": "weapon_immunity", "missile_dodge": "missile_dodge_bonus", "missile_accuracy": "missile_accuracy_bonus",
    "damage_plus": "damage_plus", "attack_count": "attack_count", "victory_points": "victory_points", "shield_chance": "shield_chance",
    "psi_resistance": "psi_resistance", "psi_points_max": "psi_points_max", "magic_attack_count": "magic_attack_count",
    "cast_percent": "cast_percent", "missile_percent": "missile_percent", "surrender_percent": "surrender_percent",
    "ammunition": "ammunition", "death_sound": "death_sound", "movement_sound": "movement_sound", "item": "item",
    "credit_bound": "credit_drop_bound", "save": "save", "attack_minimum": "natural_attack", "attack_maximum": "natural_attack",
    "attack_sound": "natural_attack", "attack_condition": "natural_attack", "category": "has_creature_category",
    "level": "hit_dice", "stamina_bonus": "stamina_bonus", "agility": "agility", "movement": "movement_max", "run_percent": "run_percent",
    "weapon": "weapon", "shield_points": "shield_points", "condition": "condition_duration", "turn_chance": "turn_macro_chance", "turn_story": "turn_macro", "death_story": "todo_on_death", "spell": "spell_slot", "name": "name",
}
# Fields the projection does not list.
EXTRA = [("level", 0, 2), ("stamina_bonus", 2, 2), ("agility", 4, 2), ("movement", 6, 2), ("run_percent", 0x44, 2),
         ("turn_chance", 0x5C, 2), ("turn_story", 0x5E, 2), ("death_story", 0x60, 2), ("name", 0xDA, 30)] + [("spell", 0x12 + 2 * n, 2) for n in range(10)]
# Fields the editor no longer edits, kept so the ledger shows why.
WITHDRAWN = [("level_protection", 0xC2, 1)]
DEFINITION_END = 0x103  # the bytes after this are battle state


def run(args):
    rows = [r for r in json.loads(args.map.read_text())["rows"] if r["kind"] == "record_field" and r["family"] == "monster"]
    by_accessor = {}
    for row in rows:
        by_accessor.setdefault(row["accessor"], []).append(row)
    scan = json.loads(args.scan.read_text())["by_offset"]
    record = json.loads(args.record.read_text())
    fields = [(f["field"], f["index"], f["offset"], f["width"], f"{f['minimum']}..{f['maximum']}") for f in record["fields"]]
    seen = {(name, index) for name, index, *_ in fields}
    for name, offset, width in EXTRA:
        index = 0
        if name == "spell":
            index = (offset - 0x12) // 2
        fields.append((name, index, offset, width, "see edits"))
    for name, offset, width in WITHDRAWN:
        fields.append((name, 0, offset, width, "withdrawn"))
    covered = set()
    lines = ["| Editor field | Offset | Range | Map accessor (offset, treatment, readers) | Scan | Class |", "|---|---|---|---|---|---|"]
    classes = {}
    for name, index, offset, width, rng in fields:
        accessor = ACCESSOR.get(name, name)
        mapped = by_accessor.get(accessor, [])
        hit = [r for r in mapped if r["offset"] == offset or (r["indexed"] and r["offset"] is not None and r["offset"] <= offset)]
        if not hit and accessor == "natural_attack":
            hit = mapped
        if not hit and accessor == "item":
            hit = [r for r in by_accessor.get("primary_weapon", []) + by_accessor.get("melee_weapon", []) if r["offset"] == offset]
        for r in mapped:
            covered.add((r["accessor"], r["offset"]))
        for r in hit:
            covered.add((r["accessor"], r["offset"]))
        reached = any(str(o) in scan for o in range(offset, offset + width))
        if name == "level_protection":
            klass = "withdrawn"
        elif hit and hit[0]["readers"] and reached:
            klass = "agreed"
        elif hit and hit[0]["readers"]:
            klass = "map only"
        elif reached and mapped:
            klass = "conflict"
        elif reached:
            klass = "scan only"
        elif mapped:
            klass = "conflict"
        else:
            klass = "none"
        classes[klass] = classes.get(klass, 0) + 1
        mapped_text = "; ".join(f"{r['accessor']} {'-' if r['offset'] is None else hex(r['offset'])} {r['editor']} {len(r['readers'])}r" for r in (hit or mapped)[:1]) or "no row"
        lines.append(f"| {name}[{index}] | {offset:#04x}/{width} | {rng} | {mapped_text} | {'yes' if reached else 'no'} | {klass} |")
    lines += ["", f"Classes: {json.dumps(classes, sort_keys=True)}", "", "Map rows no editor field covers (definition bytes first):", "",
              "| Accessor | Offset | Width | Treatment | Readers | In definition |", "|---|---|---|---|---|---|"]
    for row in sorted(rows, key=lambda r: (r["offset"] is None, r["offset"] or 0)):
        key = (row["accessor"], row["offset"])
        if key in covered:
            continue
        inside = row["offset"] is not None and row["offset"] < DEFINITION_END
        lines.append(f"| {row['accessor']} | {'' if row['offset'] is None else hex(row['offset'])} | {row['width'] or ''} | {row['editor']} | {len(row['readers'])} | {'yes' if inside else 'no'} |")
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(classes, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, required=True, help="evidence/capability-map.json of the reconstruction")
    parser.add_argument("--scan", type=Path, required=True, help="the output of audit_fields.py")
    parser.add_argument("--record", type=Path, required=True, help="a monster record as `centurions-editor record` prints it")
    parser.add_argument("--out", type=Path, required=True)
    run(parser.parse_args())
