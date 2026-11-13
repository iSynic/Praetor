"""Makes the pictures of the guide to the editor from the player's own installation.

The pictures show the game's art (its tiles, icons and monsters), so a copy of the editor does not ship them. This runs the
editor's capture drivers on an import of the installation's scenario, builds `godot/data/guide/*.png` from the captures named
in `docs/guide/shots.json`, and imports them into the Godot project.

    python tools/build_guide_pictures.py --installation "<the New Centurions folder>"

It needs a release build (`cargo build --release`) and Godot 4.7.1 on the path.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DRIVERS = ["editor", "scripts", "records", "maps", "navigation"]


def run(command, **options):
    result = subprocess.run(command, capture_output=True, text=True, **options)
    if result.returncode:
        sys.exit(f"{' '.join(map(str, command))} failed:\n{result.stdout[-2000:]}{result.stderr[-2000:]}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installation", type=Path, default=os.environ.get("CENTURIONS_INSTALLATION"), required=os.environ.get("CENTURIONS_INSTALLATION") is None)
    parser.add_argument("--scenario", default="The Thunder of Guns")
    parser.add_argument("--godot", default=shutil.which("Godot_v4.7.1-stable_win64_console.exe") or shutil.which("godot") or "godot")
    args = parser.parse_args()
    installation = args.installation.resolve()
    level = installation / "Scenarios" / args.scenario / "0"
    if not level.is_dir():
        sys.exit(f"{level} is not a scenario level of the installation")
    suffix = ".exe" if os.name == "nt" else ""
    editor = ROOT / "target" / "release" / f"centurions-editor{suffix}"
    adapter = ROOT / "target" / "release" / f"centurions-adapter{suffix}"
    if not editor.exists() or not adapter.exists():
        sys.exit("build the editor first: cargo build --release")
    base = ROOT / "artifacts" / "guide-captures"
    if base.exists():
        shutil.rmtree(base)
    base.mkdir(parents=True)
    project = base / "project"
    run([editor, "import", level, project])
    for driver in DRIVERS:
        out = base / driver
        out.mkdir()
        env = dict(os.environ, CENTURIONS_ADAPTER=str(adapter), CENTURIONS_CAPTURE_OUT=str(out), CENTURIONS_PROJECT=str(project),
                   CENTURIONS_INSTALLATION=str(installation), CENTURIONS_SETTINGS_FILE=str(out / "settings.json"))
        print(f"capturing {driver}…", flush=True)
        run([args.godot, "--path", str(ROOT / "godot"), "--script", f"res://tools/capture_{driver}.gd"], env=env, timeout=600)
    run([sys.executable, str(ROOT / "tools" / "build_guide.py")])
    run([args.godot, "--headless", "--path", str(ROOT / "godot"), "--import"], timeout=600)
    print("the guide's pictures are in godot/data/guide")


if __name__ == "__main__":
    main()
