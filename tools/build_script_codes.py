"""Build the table of script codes from the scripting manual and the capability map.

The manual describes every code: what its ID is, its sign options and its Extra Codes (E-Codes). The capability map says how well each code
is verified. The manual is prose, so what a value *is* (a text number, a battle, a sound, a count) and what it may be is curated by hand in
`tools/script_code_overlay.json`; a code the overlay does not mention is listed but not yet authorable. The output is
`crates/centurions-format/data/script_codes.json`, which the editor reads and a test compares with this tool's output."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def manual_codes(text):
    parts = re.split(r"^### Code (-?\d+): (.*)$", text, flags=re.M)
    for index in range(1, len(parts), 3):
        code, title, body = int(parts[index]), parts[index + 1].strip(), parts[index + 2]
        field = lambda key: (re.search(r"\*\*" + key + r":\*\*(.*?)(?=\n\n\*\*|\Z)", body, flags=re.S) or [None, ""])[1].strip()
        id_text = field("ID").split("\n")[0].strip()
        e_text = field("E-Codes")
        first = e_text.split("\n\n")[0]
        slots = [None] * 5
        for digit, label in re.findall(r"^\s*(\d)\)\s*(.+)$", first, flags=re.M):
            slots[int(digit) - 1] = None if label.lower().startswith("not used") else label.strip().rstrip(".")
        every = re.match(r"\s*1\) to 5\) (.+)", first)
        if every:
            slots = [every.group(1).strip().rstrip(".")] * 5
        if id_text.lower().startswith(("an extra codes", "extra codes")):
            id_class = "extra"
        elif id_text.lower().startswith(("not used", "none", "unused", "ignored")):
            id_class = "none"
        else:
            id_class = "direct"
        yield {
            "code": code,
            "name": title,
            "id_text": id_text,
            "id_class": id_class,
            "options": field("Options").split("\n")[0].strip(),
            "ecodes": slots if any(slots) else [],
        }


def build(manual, capability_map, overlay, manual_commit):
    status = {r["value"]: r["status"] for r in capability_map["rows"] if r["kind"] == "opcode" and isinstance(r.get("value"), int)}
    codes = []
    seen = set()
    for entry in manual_codes(manual.read_text(encoding="utf-8")):
        seen.add(entry["code"])
        entry["evidence"] = status.get(entry["code"], "unknown")
        entry.update(overlay.get(str(entry["code"]), {"authorable": False}))
        codes.append(entry)
    # Codes the manual does not describe because they are not steps: 0 is an empty slot.
    for key, extra in overlay.items():
        if int(key) not in seen:
            codes.append({"code": int(key), "name": extra.get("name", ""), "id_text": "", "id_class": "none", "options": "", "ecodes": [], "evidence": status.get(int(key), "native-verified"), **extra})
    by_code = {c["code"]: c for c in codes}
    for entry in codes:
        like = entry.pop("extra_like", None)
        if like is not None:
            entry["ecodes"] = by_code[like]["ecodes"]
            entry["extra"] = by_code[like]["extra"]
    codes.sort(key=lambda c: c["code"])
    return {"manual_commit": manual_commit, "codes": codes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manual", type=Path, required=True, help="docs/scripting-codes.md of the reconstruction")
    parser.add_argument("--capability-map", type=Path, required=True)
    parser.add_argument("--overlay", type=Path, default=Path("tools/script_code_overlay.json"))
    parser.add_argument("--out", type=Path, default=Path("crates/centurions-format/data/script_codes.json"))
    parser.add_argument("--godot-out", type=Path, default=Path("godot/data/script_codes.json"), help="the copy the workbench reads")
    parser.add_argument("--check", action="store_true", help="fail if the committed table differs")
    args = parser.parse_args()
    repository = args.manual.resolve().parents[1]
    commit = subprocess.run(["git", "-C", str(repository), "log", "-1", "--format=%H", "--", "docs/scripting-codes.md"], capture_output=True, text=True).stdout.strip()
    table = build(args.manual, json.loads(args.capability_map.read_text(encoding="utf-8")), json.loads(args.overlay.read_text(encoding="utf-8")), commit)
    text = json.dumps(table, indent=1, ensure_ascii=False) + "\n"
    if args.check:
        if args.out.read_text(encoding="utf-8") != text or args.godot_out.read_text(encoding="utf-8") != text:
            raise SystemExit("the committed script code table differs from the manual and the overlay")
        print("script code table matches")
        return
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    args.godot_out.parent.mkdir(parents=True, exist_ok=True)
    args.godot_out.write_text(text, encoding="utf-8")
    print(f"{len(table['codes'])} codes written")


if __name__ == "__main__":
    main()
