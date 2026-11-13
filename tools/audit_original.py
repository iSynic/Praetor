"""Read the original Centurions code for one table: every instruction that touches its record
storage, the decompilation of those routines, and bounded runs of the original with chosen values.
The Ghidra project is a disposable copy and is opened read only; the reference checkout is not touched."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

# The shop record's storage in the original: item words, quantity bytes, price percent word.
SHOP = {"first": "478288", "last": "478e41", "routines": ["loadshop", "saveshop", "updateshop", "itemcost", "moveicon", "installitem", "resetgamefiles", "choice", "Display", "newland", "loaditem"]}
EXPECTED_SHOP_CONSUMERS = {"choice", "Display", "load", "loadshop", "itemcost", "moveicon", "newland", "resetgamefiles", "save", "saveshop", "updateshop"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / "artifacts"):
        raise ValueError("output must be under artifacts")
    out.mkdir(exist_ok=False)
    base = args.baseline.resolve()
    scripts = out / "scripts"
    scripts.mkdir()
    for name in ["AuditConsumers.java", "AuditDecompile.java", "AuditLoadItem.java"]:
        shutil.copyfile(root / "tools/native" / name, scripts / name)
    shutil.copyfile(args.reference.resolve() / "tools/ghidra/ActionOracleHarness.java", scripts / "ActionOracleHarness.java")
    project = out / "ghidra-project"
    shutil.copytree(base / "ghidra-project", project)

    def headless(script, *arguments):
        command = [str(args.ghidra / "support/analyzeHeadless.bat"), str(project), "CenturionsMapped", "-process", "code1-mapped.bin", "-noanalysis", "-readOnly",
                   "-scriptPath", str(scripts), "-postScript", script, *map(str, arguments)]
        with (out / (script + ".log")).open("xb") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=out, timeout=300, creationflags=0x08000000 if os.name == "nt" else 0)
        text = (out / (script + ".log")).read_text(errors="replace")
        assert result.returncode == 0 and "Exception" not in text, text[-3000:]

    headless("AuditConsumers.java", out / "shop-consumers.tsv", SHOP["first"], SHOP["last"])
    headless("AuditDecompile.java", out / "decompiled", *SHOP["routines"])
    headless("AuditLoadItem.java", out / "loaditem.json")
    rows = [line.split("\t") for line in (out / "shop-consumers.tsv").read_text().splitlines()]
    consumers = {row[1] for row in rows}
    assert consumers == EXPECTED_SHOP_CONSUMERS, sorted(consumers ^ EXPECTED_SHOP_CONSUMERS)
    loaded = {row["id"]: row for row in json.loads((out / "loaditem.json").read_text())}
    for item in range(-999, 1000, 37):
        row = loaded.get(item)
        if row is not None:
            assert row["loaded"], row
    assert all(loaded[i]["loaded"] for i in (0, 199, 200, 799, 800, 999, -1, -999))
    assert not any(loaded[i]["loaded"] for i in (1000, 1199, 1999, 2000, -1000, 32767, -32768))
    receipt = {"status": "passed", "reference_writes": False, "program_sha256": digest(base / "rebuilt/analysis/ghidra/startup/code1-mapped.bin"),
               "shop_consumers": sorted(consumers), "references": len(rows), "loaditem": loaded}
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps({k: v for k, v in receipt.items() if k != "loaditem"}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["baseline", "reference", "ghidra", "out"]:
        parser.add_argument("--" + name, type=Path, required=True)
    run(parser.parse_args())
