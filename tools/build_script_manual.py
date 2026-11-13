"""Builds godot/data/script_manual.json from the scripting codes manual: every code's entry for the code helper, and the
chapters around them for the guide.

    python tools/build_script_manual.py --source "<reconstruction checkout>/docs/scripting-codes.md"

The manual is written in Markdown with one `### Code N: Title` entry per code, each made of bold labels (ID, Use, Options,
E-Codes, Note, Caution, Example). The output keeps each label's paragraphs in order, so the helper shows the entry as written.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

LABELS = ("ID", "Use", "Options", "E-Codes", "Note", "Caution", "Example")
ENTRY = re.compile(r"^### Code (-?\d+): (.*)$")


def paragraphs(lines):
    """Blank-line separated paragraphs of `lines`; a list item (a line beginning with `-` or `N)`) stays a line of its paragraph."""
    found, current = [], []
    for line in lines:
        if line.strip():
            current.append(line.rstrip())
        elif current:
            found.append("\n".join(current))
            current = []
    if current:
        found.append("\n".join(current))
    return found


def entry(code, title, lines):
    """One code: its labelled sections in the order the manual gives them."""
    sections, label, body = [], None, []

    def close():
        if label is not None:
            sections.append({"label": label, "paragraphs": paragraphs(body)})

    for line in lines:
        match = re.match(r"^\*\*(" + "|".join(LABELS) + r"):\*\*\s*(.*)$", line)
        if match:
            close()
            label, body = match.group(1), [match.group(2)] if match.group(2) else []
        elif re.match(r"^\*\*Example \d+:\*\*", line):
            close()
            label, body = "Example", [line.split(":**", 1)[1].strip()]
        else:
            body.append(line)
    close()
    return {"code": int(code), "title": title.strip(), "sections": sections}


def blocks(lines):
    """A chapter as blocks: headings ({"h": level, "t"}), paragraphs ({"p"}) and lists ({"li": [...]})."""
    found, current, items = [], [], []

    def flush():
        nonlocal current, items
        if current:
            found.append({"p": " ".join(part.strip() for part in current)})
            current = []
        if items:
            found.append({"li": items})
            items = []

    for line in lines:
        heading = re.match(r"^(#{2,4}) (.*)$", line)
        if heading:
            flush()
            found.append({"h": len(heading.group(1)), "t": heading.group(2).strip()})
        elif re.match(r"^\s*[-*] ", line):
            if current:
                found.append({"p": " ".join(part.strip() for part in current)})
                current = []
            items.append(re.sub(r"^\s*[-*] ", "", line).rstrip())
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            if items:
                found.append({"li": items})
                items = []
            current.append(line)
    flush()
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "godot/data/script_manual.json")
    args = parser.parse_args()
    lines = args.source.read_text(encoding="utf-8").splitlines()
    codes, chapters, at = [], [], 0
    title = lines[0].lstrip("# ").strip()
    # Split at the level-2 chapters; the chapters that hold codes are read entry by entry.
    starts = [i for i, line in enumerate(lines) if line.startswith("## ")] + [len(lines)]
    for begin, end in zip(starts, starts[1:]):
        chapter = lines[begin:end]
        name = chapter[0][3:].strip()
        if name.startswith("Codes "):
            entries = [i for i, line in enumerate(chapter) if ENTRY.match(line)] + [len(chapter)]
            for first, last in zip(entries, entries[1:]):
                code, heading = ENTRY.match(chapter[first]).groups()
                codes.append(entry(code, heading, chapter[first + 1:last]))
        else:
            chapters.append({"title": name, "blocks": blocks(chapter[1:])})
    source = args.source.resolve()
    try:
        revision = subprocess.run(["git", "-C", str(source.parent), "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        revision = ""
    document = {"_provenance": {"source": "docs/scripting-codes.md of the reconstruction", "revision": revision, "title": title,
                                "tool": "tools/build_script_manual.py"},
                "intro": blocks(lines[1:starts[0]]), "codes": codes, "chapters": chapters}
    args.out.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(codes)} codes, {len(chapters)} chapters -> {args.out}")


if __name__ == "__main__":
    main()
