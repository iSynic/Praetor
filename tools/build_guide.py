"""Builds the guide to the editor: godot/data/guide/guide.json and the pictures it shows.

    python tools/build_guide.py            # from docs/guide/guide.md and docs/guide/shots.json

`guide.md` is Markdown with `##` chapters, `###` sections, paragraphs, bullet and numbered lists, tables, paragraphs that begin
`NOTE:` and figures written `![Figure 1.0 · Caption](shot:name)`. `shots.json` says where each named picture comes from, a capture
the verification drivers write (`from`, a path under artifacts) and an optional `crop` of [x, y, width, height].
"""
import argparse
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def blocks(lines):
    """The blocks of one section: paragraphs, notes, lists, tables and figures."""
    found, paragraph, items, rows = [], [], [], []

    def flush():
        nonlocal paragraph, items, rows
        if paragraph:
            text = " ".join(part.strip() for part in paragraph)
            found.append({"note": text[5:].strip()} if text.startswith("NOTE:") else {"p": text})
            paragraph = []
        if items:
            found.append({"li": items})
            items = []
        if rows:
            found.append({"table": rows})
            rows = []

    for line in lines:
        figure = re.match(r"^!\[(.*)\]\(shot:([A-Za-z0-9_-]+)\)\s*$", line)
        if figure:
            flush()
            found.append({"figure": figure.group(2), "caption": figure.group(1)})
        elif line.startswith("|"):
            if paragraph or items:
                flush()
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-+:?", cell) for cell in cells):
                rows.append(cells)
        elif re.match(r"^\s*([-*]|\d+\)) ", line):
            if paragraph or rows:
                flush()
            items.append(re.sub(r"^\s*([-*]) ", "", line).rstrip())
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            if items or rows:
                flush()
            paragraph.append(line)
    flush()
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "docs/guide/guide.md")
    parser.add_argument("--shots", type=Path, default=ROOT / "docs/guide/shots.json")
    parser.add_argument("--out", type=Path, default=ROOT / "godot/data/guide")
    parser.add_argument("--text-only", action="store_true", help="write guide.json and leave the pictures as they are (a copy of the editor ships none)")
    args = parser.parse_args()
    lines = args.source.read_text(encoding="utf-8").splitlines()
    title = lines[0].lstrip("# ").strip()
    chapters, current, section = [], None, None
    lead = []
    for line in lines[1:]:
        if line.startswith("## "):
            current = {"title": line[3:].strip(), "lead": [], "sections": []}
            chapters.append(current)
            section = None
            current["_buffer"] = []
        elif line.startswith("### ") and current is not None:
            section = {"title": line[4:].strip(), "blocks": []}
            current["sections"].append(section)
            section["_buffer"] = []
        elif current is None:
            lead.append(line)
        elif section is None:
            current["_buffer"].append(line)
        else:
            section["_buffer"].append(line)
    for chapter in chapters:
        chapter["lead"] = blocks(chapter.pop("_buffer"))
        for part in chapter["sections"]:
            part["blocks"] = blocks(part.pop("_buffer"))
    names = set()
    for chapter in chapters:
        for part in [chapter] + chapter["sections"]:
            for block in part.get("lead", []) + part.get("blocks", []):
                if "figure" in block:
                    names.add(block["figure"])
    args.out.mkdir(parents=True, exist_ok=True)
    if not args.text_only:
        shots = json.loads(args.shots.read_text(encoding="utf-8")) if args.shots.exists() else {}
        missing = sorted(name for name in names if name not in shots)
        if missing:
            raise SystemExit("no source for the pictures: " + ", ".join(missing))
        from PIL import Image
        for name in sorted(names):
            entry = shots[name]
            source = ROOT / entry["from"]
            if not source.exists():
                raise SystemExit(f"{name}: {source} does not exist; run the captures first")
            image = Image.open(source).convert("RGB")
            if "crop" in entry:
                x, y, w, h = entry["crop"]
                image = image.crop((x, y, x + w, y + h))
            image.save(args.out / f"{name}.png", optimize=True)
        for stale in args.out.glob("*.png"):
            if stale.stem not in names:
                stale.unlink()
    filled = [index for index, line in enumerate(lead) if line.strip()]
    document = {"title": title, "subtitle": lead[filled[0]].strip() if filled else "",
                "intro": blocks(lead[filled[0] + 1:]) if filled else [], "chapters": chapters}
    (args.out / "guide.json").write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(chapters)} chapters, {len(names)} pictures{' (not built)' if args.text_only else ''} -> {args.out}")


if __name__ == "__main__":
    main()
