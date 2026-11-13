"""Which Extra Codes words does the original read for each code?

`newland` loads the Extra Codes row a step names into five words (E1 to E5 at 0x44330a, 0x44330c, 0x44330e, 0x443310 and 0x443312) and its main
switch handles each code. This reads the decompiled `newland`, finds the words each code's case mentions, and compares them with the table: a
word the table calls unused that the original reads, or a word the table names that the case never mentions, is listed for a closer look. A case
that jumps to a shared block is marked, because the reads of that block are not counted."""
import argparse
import json
from pathlib import Path
import re

WORDS = {"0044330a": 0, "0044330c": 1, "0044330e": 2, "00443310": 3, "00443312": 4}
CASE = re.compile(r"^  case (0x[0-9a-fA-F]+|-?\d+):")
WORD = re.compile(r"DAT_(0044330a|0044330c|0044330e|00443310|00443312)\b")


def blocks(text):
    """code -> the text of its case in the main switch (two-space indent)."""
    found = {}
    current = None
    for line in text.splitlines():
        match = CASE.match(line)
        if match:
            raw = match.group(1)
            value = int(raw, 16) if raw.startswith("0x") else int(raw)
            if value > 0x7FFF:
                value -= 0x10000
            current = value
            found.setdefault(current, [])
            continue
        if line.startswith("  default:") or re.match(r"^\S", line):
            current = None
        if current is not None:
            found[current].append(line)
    return {code: "\n".join(lines) for code, lines in found.items()}


def labels(text):
    """label -> the text that follows it, up to the next label at the left margin (a shared block a case jumps to)."""
    lines = text.splitlines()
    found = {}
    for index, line in enumerate(lines):
        match = re.match(r"^(\w+):\s*$", line)
        if match:
            end = index + 1
            while end < len(lines) and end < index + 200 and not re.match(r"^\w+:\s*$", lines[end]):
                end += 1
            found[match.group(1)] = chr(10).join(lines[index + 1:end])
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--newland", type=Path, required=True, help="the decompiled newland routine")
    parser.add_argument("--table", type=Path, default=Path("crates/centurions-format/data/script_codes.json"))
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    text = args.newland.read_text(errors="replace")
    cases = blocks(text)
    shared = labels(text)
    table = json.loads(args.table.read_text(encoding="utf-8"))["codes"]
    report = []
    for code in table:
        if not code["authorable"] or code["code"] not in cases:
            continue
        body = cases[code["code"]]
        for jump in sorted(set(re.findall(r"goto (\w+);", body))):
            body += chr(10) + shared.get(jump, "")
        read = sorted({WORDS[m] for m in WORD.findall(body)})
        extra = code.get("extra")
        named = [i for i, kind in enumerate(extra or []) if kind["kind"] != "unused"]
        row = {"code": code["code"], "name": code["name"], "evidence": code["evidence"], "read": read, "named": named,
               "jumps": sorted(set(re.findall(r"goto (\w+);", cases[code["code"]]))), "lines": body.count("\n") + 1}
        row["unused_but_read"] = [i for i in read if extra and i not in named]
        row["named_but_not_read"] = [i for i in named if i not in read]
        report.append(row)
    args.out.write_text(json.dumps(report, indent=1) + "\n")
    for row in report:
        flag = ""
        if row["unused_but_read"]:
            flag += f" UNUSED-READ {row['unused_but_read']}"
        if row["named_but_not_read"]:
            flag += f" NAMED-NOT-READ {row['named_but_not_read']}"
        if row["jumps"]:
            flag += f" jumps {row['jumps'][:3]}"
        print(f"{row['code']:4d} {row['evidence'][:7]:7s} read E{[i + 1 for i in row['read']]}{flag}")


if __name__ == "__main__":
    main()
