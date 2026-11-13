"""Run the native Godot workflow and independently compare every exported byte."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess


def tree(root):
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()}


def verify(args):
    root=Path(__file__).resolve().parents[1]
    out=args.out.resolve()
    if not out.is_relative_to(root/"artifacts"):
        raise ValueError("output must be a new artifacts directory")
    out.mkdir(exist_ok=False)
    source=tree(args.level.resolve())
    checkpoint_before=tree(args.project.resolve())
    env=dict(os.environ,CENTURIONS_PROJECT=str(args.project.resolve()),
        CENTURIONS_INSTALLATION=str(args.installation.resolve()),CENTURIONS_TEST_OUT=str(out),
        CENTURIONS_SETTINGS_FILE=str(out/"settings.json"),CENTURIONS_TEST_RECEIPT=str(args.receipt.resolve()),
        CENTURIONS_TEST_SOURCE=str(args.installation.resolve()/"Scenarios/The Thunder of Guns/0"))
    command=([str(args.godot.resolve()),"--headless","--","--verify-editor"]
        if args.packaged else [str(args.godot),"--headless","--path",str(root/"godot"),"--script","res://tools/editor_workflow.gd"])
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=100,
        cwd=args.godot.resolve().parent if args.packaged else root,
        creationflags=0x08000000 if os.name=="nt" else 0)
    log=result.stdout+result.stderr
    (out/"godot.log").write_text(log,encoding="utf-8")
    assert result.returncode==0 and ("CENTURIONS_EDITOR_WORKFLOW_PASSED" in log or args.packaged and (out/"godot-workflow.json").exists()),log
    assert not any(s in log for s in ("ERROR:","SCRIPT ERROR:","WARNING:")),log
    restart_env=dict(env);restart_env.pop("CENTURIONS_INSTALLATION",None)
    restart_command=command[:-1]+["--verify-installation"] if args.packaged else [str(args.godot),"--headless","--path",str(root/"godot"),"--","--verify-installation"]
    restarted=subprocess.run(restart_command,env=restart_env,capture_output=True,text=True,timeout=35,cwd=args.godot.resolve().parent if args.packaged else root,creationflags=0x08000000 if os.name=="nt" else 0)
    (out/"restart.log").write_text(restarted.stdout+restarted.stderr,encoding="utf8")
    assert restarted.returncode==0 and "CENTURIONS_INSTALLATION_RESTART_PASSED" in restarted.stdout,restarted.stdout+restarted.stderr
    original_scripts=tree(args.installation.resolve()/"Scenarios/The Thunder of Guns/0")
    program_manifest=json.loads((out/"program-checkpoint/project.json").read_text())
    step=next(e for e in program_manifest["edits"] if e["kind"]=="script_step")
    expected_scripts={n:bytearray(b) for n,b in original_scripts.items()}
    struct.pack_into(">h",expected_scripts["Data DD"],step["id"]*42+8+step["slot"]*2,9)
    struct.pack_into(">h",expected_scripts["Data DD"],step["id"]*42+24+step["slot"]*2,2)
    assert tree(out/"program-export")==expected_scripts,"GUI trigger edit changed unowned bytes"
    encounter_manifest=json.loads((out/"encounter-checkpoint/project.json").read_text())
    expected_encounters={n:bytearray(b) for n,b in original_scripts.items()}
    for step in encounter_manifest["edits"]:
        assert step["kind"]=="script_step",step
        path,stride={"walking":("Data DD",42),"story":("Data ED3",42),"menu":("Data ED",426),"typed":("Data ED2",516)}[step["family"]]
        base=step["id"]*stride
        op,arg=(base+8+step["slot"]*2,base+24+step["slot"]*2) if stride==42 else (base+step["branch"]*8+step["slot"],base+32+step["branch"]*16+step["slot"]*2)
        struct.pack_into(">h" if stride==42 else ">b",expected_encounters[path],op,step["opcode"])
        struct.pack_into(">h",expected_encounters[path],arg,step["operand"])
    assert tree(out/"encounter-export")==expected_encounters,"GUI encounter editing changed unowned bytes"
    condition_manifest=json.loads((out/"conditions-checkpoint/project.json").read_text())
    expected_conditions={n:bytearray(b) for n,b in expected_encounters.items()}
    for edit in condition_manifest["edits"]:
        if edit["kind"]=="walking_location": struct.pack_into(">i",expected_conditions["Data DD"],(edit["map"]*100+edit["slot"])*42,edit["map"]*10000+edit["y"]*100+edit["x"])
        elif edit["kind"]=="event_activation":
            at=edit["map"]*64800+32400+(edit["x"]*90+edit["y"])*4
            prior=struct.unpack_from(">i",original_scripts["Data LD"],at)[0]
            struct.pack_into(">i",expected_conditions["Data LD"],at,max(1,edit["map"]*10000+edit["y"]*100+edit["x"]) if edit["enabled"] else min(0,prior))
        elif edit["kind"]=="walking_chance": struct.pack_into(">b",expected_conditions["Data DD"],edit["id"]*42+7,edit["chance"])
        elif edit["kind"]=="encounter_condition":
            path,stride=("Data ED",426) if edit["family"]=="menu" else ("Data ED2",516)
            assert edit["field"] in ["choice_selector","physical_selector"]
            struct.pack_into(">b",expected_conditions[path],edit["id"]*stride+96+edit["index"],edit["value"])
    assert tree(out/"conditions-export")==expected_conditions,"Placement/condition edits changed unowned bytes"
    assert tree(out/"native-first-patrol")==source,"GUI unchanged First Patrol export differs from native-tested bytes"
    expected={n:bytearray(b) for n,b in source.items()}
    mission=expected["Data Mission"]
    manifest=json.loads(checkpoint_before["project.json"])
    original_mission=checkpoint_before["blobs/"+manifest["files"]["Data Mission"]["sha256"]]
    # A replacement edit overlays the immutable import, not an earlier authored
    # name. The unused original Pascal suffix must reappear unchanged.
    mission[6:262]=original_mission[6:262]
    struct.pack_into(">hhh",mission,0,7,11,0)
    name="Patrouille".encode("mac_roman");mission[6]=len(name);mission[7:7+len(name)]=name
    for n in ("Data CS","First Patrol"):
        struct.pack_into(">iii",expected[n],8,0,13,17)
    message="Café.\rPatrol test.".encode("mac_roman")
    expected["Data SD2"][0]=len(message);expected["Data SD2"][1:1+len(message)]=message
    for x,y in [(3,7),(4,7)]:struct.pack_into(">h",expected["Data LD"],(x*90+y)*2,17)
    actual=tree(out/"export")
    assert actual==expected,[n for n in actual.keys()|expected.keys() if actual.get(n)!=expected.get(n)]
    assert tree(args.project.resolve())==checkpoint_before,"input checkpoint changed"
    assert tree(args.level.resolve())==source,"input level changed"
    receipt=dict(status="passed",files=len(actual),packaged_executable=args.packaged,independent_complete_byte_comparison=True,
        input_checkpoint_unchanged=True,input_export_unchanged=True,installation_restored_after_restart=True,negative_floor_icons=True,walking_choice_typed_step_byte_comparison=True,placement_and_conditions_byte_comparison=True,combat_browsing_read_only=True,
        files_sha256={n:hashlib.sha256(b).hexdigest() for n,b in actual.items()})
    (out/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in receipt.items() if k!="files_sha256"},indent=2))


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--packaged",action="store_true")
    for name in ("godot","project","level","installation","receipt","out"):p.add_argument("--"+name,type=Path,required=True)
    verify(p.parse_args())
