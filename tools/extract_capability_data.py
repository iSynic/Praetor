"""Copy the opcode rows of the reconstruction's capability map into the editor.

The reconstruction (read only) keeps evidence/capability-map.json. The editor
shows only what each operation is, how it is evidenced and whether it is allowed,
so this keeps those fields of the opcode rows, with the source's hash, and is run
deliberately when the map changes (owner decision 3, 2026-11-09).

    python tools/extract_capability_data.py --source <capability-map.json>
"""
import argparse
import hashlib
import json
from datetime import date
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "godot/data/capability_opcodes.json")
    args = parser.parse_args()
    raw = args.source.read_bytes()
    data = json.loads(raw)
    rows = []
    for row in data["rows"]:
        if row["kind"] != "opcode":
            continue
        rows.append({
            "value": row["value"],
            "operation": row["operation"],
            "status": row["status"],
            "editor": row["editor"],
            "behavior": row.get("behavior"),
            "evidence": row.get("evidence"),
            "diagnostics": len(row.get("diagnostics", [])),
            "open_diagnostics": len(row.get("open_diagnostics", [])),
            "routes": {name: context["route"] for name, context in row.get("contexts", {}).items()},
        })
    out = {
        "_provenance": {
            "source": "evidence/capability-map.json of the Centurions reconstruction (read only)",
            "sha256": hashlib.sha256(raw).hexdigest(),
            "schema_version": data["schema_version"],
            "authority": data["authority"],
            "extracted": date.today().isoformat(),
            "kept": "the opcode rows: operation, status, editor treatment, behavior, evidence, diagnostic counts and routes",
        },
        "opcodes": rows,
    }
    args.out.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(rows)} opcode rows -> {args.out}")


if __name__ == "__main__":
    main()
