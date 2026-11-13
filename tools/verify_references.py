"""Verify pinned read-only inputs against the private pre-work baseline."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import subprocess


def verify(baseline_path, output=None):
    root = Path(__file__).resolve().parents[1]
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    provenance = json.loads((root / "docs/provenance.json").read_text(encoding="utf-8"))
    references = Path(provenance["donors"][1]["path"])
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    originals_changed = [name for name, old in baseline["originals"].items()
                         if not (references / name).is_file() or digest(references / name) != old]
    referenced_source_changed = [dict(donor=d["path"], file=name)
        for d in provenance["donors"] for name, old in d["files"].items()
        if digest(Path(d["path"]) / name) != old]
    for ui in [root / "docs/ui-provenance.json",root / "docs/script-provenance.json"]:
      if ui.exists():
        referenced_source_changed += [dict(donor=entry["donor"], file=ui.name)
            for entry in json.loads(ui.read_text(encoding="utf-8"))["inputs"]
            if digest(Path(entry["donor"])) != entry["sha256"]]
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    status_changes = {}
    for path, old in baseline["donor_status"].items():
        current = subprocess.check_output(["git", "-C", path, "status", "--porcelain=v1", "--untracked-files=all"],
                                          text=True, env=environment)
        if current != old:
            status_changes[path] = list(difflib.unified_diff(old.splitlines(), current.splitlines(),
                                                          fromfile="before", tofile="current", lineterm=""))
    report = dict(status="passed_for_pinned_inputs" if not originals_changed and not referenced_source_changed else "failed",
                  original_files_checked=len(baseline["originals"]), original_changes=originals_changed,
                  referenced_source_changes=referenced_source_changed,
                  donor_status_changes=status_changes,
                  scope="All original files and pinned referenced source bytes; no whole-checkout immutability claim",
                  reference_writes_performed=False)
    target = output.resolve() if output else root / "artifacts/reference-preservation.json"
    if output and (not target.is_relative_to(root / 'artifacts') or target.exists()):
        raise ValueError('output must be a new artifacts file')
    target.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k != "donor_status_changes"}, indent=2))
    print(f"Donor status changes: {len(status_changes)}; details in {target}")
    if originals_changed or referenced_source_changed:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args=parser.parse_args()
    verify(args.baseline,args.out)
