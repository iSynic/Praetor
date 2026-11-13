"""Run bounded original 68k scenario startup without launching a desktop emulator."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
from verify_unchanged import call, tree


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_extractor(path):
    spec = importlib.util.spec_from_file_location("native_extract", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resource_strings(extractor, path):
    lists = {}
    for resource in extractor.resources(path.read_bytes()):
        if resource["type"] != "STR#":
            continue
        raw = resource["payload"]
        count = struct.unpack_from(">H", raw)[0]
        at, values = 2, []
        for _ in range(count):
            size = raw[at]
            values.append(raw[at+1:at+1+size].hex())
            at += size+1
        lists[str(resource["id"])] = values
    return lists


def menu_items(payload):
    at, items = 15+payload[14], []
    while at < len(payload) and payload[at]:
        length=payload[at]
        items.append(payload[at+1:at+1+length].hex())
        at += length+5
    return items


def check_buffers(case, level, directory, stock, startup):
    mission = (level / "Data Mission").read_bytes()
    x, y, map_id = struct.unpack_from(">hhh", mission)
    assert (case["map"], case["x"], case["y"]) == (map_id, x, y)
    assert case["stage_name"] == mission[7:7+mission[6]].decode("mac_roman")
    assert (directory / "mission.bin").read_bytes() == mission[:9280]
    assert (directory / "headers.bin").read_bytes() == (level / "Data DD").read_bytes()[map_id*4200:(map_id+1)*4200]
    assert (directory / "regions.bin").read_bytes() == (level / "Data RD").read_bytes()[map_id*644:(map_id+1)*644]
    land = (level / "Data LD").read_bytes()[map_id*64800:(map_id+1)*64800]
    for filename, expected in [("floor",land[:16200]),("objects",land[16200:32400]),("events",land[32400:])]:
        assert (directory / f"{filename}.bin").read_bytes() == expected, filename
    assert (directory / "visibility.bin").read_bytes() == bytes(8100)
    terrain = case["terrain"]
    names = (None,"P","Swamp","Snow","Sub","Desert","Lava","Castle","Techno","Biologic")
    props = (stock / f"Data {names[terrain]} BD").read_bytes()
    assert case["terrain_default_tile"] == struct.unpack_from(">h", props)[0]
    assert case["terrain_tick_flag"] == struct.unpack_from(">h", props, 2)[0]
    baseline = startup.read_bytes()
    start = 0x43167c-0x3fe210
    expected = bytearray(baseline[start:start+16000])
    supplied = props[64:16064]
    expected[:len(supplied)] = supplied
    assert (directory / "tile-properties.bin").read_bytes() == expected


def verify(args):
    root = Path(__file__).resolve().parents[1]
    out, reference, ghidra, editor, old_level = (
        getattr(args, key).resolve() for key in ("out", "reference", "ghidra", "editor", "legacy_level"))
    if not out.is_relative_to(root / "artifacts"):
        raise ValueError("output must be a new directory inside this checkout's artifacts")
    out.mkdir(exist_ok=False)
    source = reference / "NewCenturions/TheNewCenturions"
    original_level = source / "Scenarios/The Thunder of Guns/0"
    stock = source / "Data Files"
    project_source = reference / "analysis/ghidra/project"
    inputs = [source / "New Centurions", source / "New Centurions.rsrc", stock / "Cargo Pod.rsrc",
              reference / "tools/extract.py", reference / "tools/decode_globals.py",
              reference / "tools/ghidra/ActionOracleHarness.java", editor,
              root / "tools/native/VerifyScenarioStartup.java", Path(__file__).resolve()]
    inputs += [p for p in (project_source / "CenturionsMapped.rep").rglob("*") if p.is_file()]
    inputs += [project_source / "CenturionsMapped.gpr"]
    inputs += [stock / f"Data {name} BD" for name in ("P","Swamp","Snow","Sub","Desert","Lava","Castle","Techno","Biologic")]
    inputs += [p for folder in (original_level, old_level) for p in folder.rglob("*") if p.is_file()]
    identities = {str(p): digest(p) for p in inputs}
    (out / "inputs.json").write_text(json.dumps(identities, indent=2)+"\n", encoding="utf-8")

    # Rebuild analysis relocation from the original application resource fork.
    scripts = out / "scripts"
    scripts.mkdir()
    for name in ("extract.py", "decode_globals.py"):
        shutil.copyfile(reference / "tools" / name, scripts / name)
    shutil.copyfile(reference / "tools/ghidra/ActionOracleHarness.java", scripts / "ActionOracleHarness.java")
    shutil.copyfile(root / "tools/native/VerifyScenarioStartup.java", scripts / "VerifyScenarioStartup.java")
    extract = load_extractor(scripts / "extract.py")
    rebuilt = out / "rebuilt"
    native = rebuilt / "analysis/extracted/resources/106"
    native.mkdir(parents=True)
    for resource in extract.resources((source / "New Centurions.rsrc").read_bytes()):
        if resource["type"] == "CODE" and resource["id"] in range(4) or resource["type"] == "DATA" and resource["id"] == 0:
            filename = f"{resource['type_hex']}_{resource['id']}.bin"
            (native / filename).write_bytes(resource["payload"])
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", GIT_OPTIONAL_LOCKS="0")
    relocation = subprocess.run([sys.executable, str(scripts / "decode_globals.py")], cwd=rebuilt,
                                env=environment, capture_output=True, text=True, timeout=60)
    (out / "relocation.log").write_text(relocation.stdout+relocation.stderr, encoding="utf-8")
    if relocation.returncode:
        raise RuntimeError("original resource relocation failed")
    startup = rebuilt / "analysis/ghidra/startup"
    for name in ("a5-mapped.bin", "code1-mapped.bin"):
        assert digest(startup / name) == digest(reference / "analysis/ghidra/startup" / name), name

    project = out / "ghidra-project"
    project.mkdir()
    shutil.copyfile(project_source / "CenturionsMapped.gpr", project / "CenturionsMapped.gpr")
    shutil.copytree(project_source / "CenturionsMapped.rep", project / "CenturionsMapped.rep")
    imported, candidate, level = out / "template", out / "first-patrol-project", out / "first-patrol-level"
    call(editor, "import", original_level, imported)
    call(editor, "new", imported, candidate, "First Patrol")
    call(editor, "export", candidate, level)
    original_tree = tree(original_level)
    assert tree(old_level)["files"].keys() == original_tree["files"].keys()
    mission_menu=next(resource["payload"] for resource in extract.resources((stock / "Cargo Pod.rsrc").read_bytes())
                      if resource["type"] == "MENU" and resource["id"] == 130)
    original_menu=menu_items(mission_menu)
    assert bytes.fromhex(original_menu[4]).decode("mac_roman") == "The Thunder of Guns"
    test_menu=original_menu.copy()
    test_menu[4]="First Patrol".encode("mac_roman").hex()
    (out / "controlled-menu.json").write_text(json.dumps(dict(resource_type="MENU",resource_id=130,
        original_payload_sha256=hashlib.sha256(mission_menu).hexdigest(), original_items=original_menu,
        test_items=test_menu, changed_item=5, scope="Host resource fixture only; original resource fork is unchanged"),indent=2)+"\n")
    spec = dict(
        a5_image=str(startup / "a5-mapped.bin"), stock_root=str(stock),
        newc_resource_count=sum(resource["type"] == "NEWC"
            for path in [source / "New Centurions.rsrc", original_level / "Scenario.rsrc"]
            for resource in extract.resources(path.read_bytes())),
        code_images=[dict(path=str(startup / "code1-mapped.bin"), address="100000"),
                     dict(path=str(native / "434f4445_2.bin"), address="200000"),
                     dict(path=str(native / "434f4445_3.bin"), address="300000")],
        string_lists=resource_strings(extract, stock / "Cargo Pod.rsrc"),
        cases=[dict(name="original-control", scenario_name="The Thunder of Guns", level_folder=str(original_level), select_scenario=True, menu_items=original_menu),
               dict(name="missing-header-control", scenario_name="First Patrol", level_folder=str(old_level), menu_items=test_menu),
               dict(name="first-patrol", scenario_name="First Patrol", level_folder=str(level), select_scenario=True, menu_items=test_menu)])
    spec_path = out / "spec.json"
    spec_path.write_text(json.dumps(spec, indent=2)+"\n", encoding="utf-8")
    command = [str(ghidra / "support/analyzeHeadless.bat"), str(project), "CenturionsMapped", "-process", "code1-mapped.bin",
               "-noanalysis", "-readOnly", "-scriptPath", str(scripts), "-postScript", "VerifyScenarioStartup.java",
               str(spec_path), str(out / "capture.json")]
    with (out / "ghidra.log").open("xb") as log:
        result = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT, env=environment,
                                timeout=180, creationflags=0x08000000 if os.name == "nt" else 0)
    log = (out / "ghidra.log").read_text(encoding="utf-8", errors="replace")
    assert result.returncode == 0, "Ghidra process failed"
    assert not any(marker in log.lower() for marker in ("uninitialized", "error ", "exception")), "unclean native probe log"
    receipt = json.loads((out / "capture.json").read_text(encoding="utf-8"))
    control, failure, fixed = receipt["cases"]
    assert control["status"] == fixed["status"] == "completed"
    assert control["selection_result"] == fixed["selection_result"] == 1
    assert failure["status"] == "failed" and "native scratch diagnostic 189" in failure["error"]
    assert any(row["path"] == "Scenarios:First Patrol:0:First Patrol" and row["count"] == 0
               for row in failure["services"] if row["service"].startswith("fopen"))
    check_buffers(control, original_level, out / "original-control", stock, startup / "a5-mapped.bin")
    check_buffers(fixed, level, out / "first-patrol", stock, startup / "a5-mapped.bin")
    assert digest(level / "First Patrol") == digest(original_level / "The Thunder of Guns")
    assert digest(level / "First Patrol.rsrc") == digest(original_level / "The Thunder of Guns.rsrc")
    assert original_tree == tree(original_level), "original scenario changed"
    changed_inputs = [path for path, before in identities.items() if digest(Path(path)) != before]
    assert not changed_inputs, changed_inputs
    report = dict(status="passed", proof_level="bounded original-instruction execution with explicit hosted OS/presentation services",
                  native_fail_before=189, native_selection_after=1, final_stage="First Patrol", final_position=[fixed["map"],fixed["x"],fixed["y"]],
                  complete_buffer_comparisons=["mission", "headers", "regions", "visibility", "floor", "objects", "events", "tile-properties"],
                  reference_inputs_unchanged=True, original_binary_relocation_rebuilt=True, code_segments_verified=[1,2,3],
                  live_gui_verified=False, candidate_project=str(candidate), candidate_level=str(level),
                  menu_binding="Controlled MENU 130 item 5 label; actual app discovery/installation is not certified",
                  capture_sha256=digest(out / "capture.json"), log_sha256=digest(out / "ghidra.log"),
                  editor_sha256=digest(editor), original_application_resource_sha256=digest(source / "New Centurions.rsrc"))
    (out / "receipt.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("reference", "ghidra", "editor", "legacy-level", "out"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    verify(parser.parse_args())
