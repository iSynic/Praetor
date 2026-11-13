"""Exercise typed authoring and independently audit a template-derived candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from verify_unchanged import call, tree


def verify(binary, template, source, out):
    artifact_root = Path(__file__).resolve().parents[1] / "artifacts"
    if not out.is_relative_to(artifact_root):
        raise ValueError("verification output must be inside this checkout's artifacts directory")
    out.mkdir(exist_ok=False)
    project, level = out / "project", out / "level"
    created = call(binary, "new", template, project, "First Patrol")
    exported = call(binary, "export", project, level)
    original_tree, new_tree = tree(source), tree(level)
    assert original_tree["directories"] == new_tree["directories"]
    assert set(new_tree["files"]) == set(original_tree["files"]) | {"First Patrol", "First Patrol.rsrc"}
    manifest = json.loads((project / "project.json").read_text(encoding="utf-8"))
    header = manifest["native"]["startup_header_source"]
    assert (level / "First Patrol").read_bytes() == (source / header).read_bytes()
    assert (level / "First Patrol.rsrc").read_bytes() == (source / f"{header}.rsrc").read_bytes()
    original_opening = struct.unpack_from(">iii", (source / "Data CS").read_bytes(), 8)
    opening_map, x, y = original_opening
    name = b"First Patrol"
    changed = {}
    for relative in original_tree["files"]:
        before = (source / relative).read_bytes()
        after = (level / relative).read_bytes()
        assert len(before) == len(after), relative
        allowed = set()
        if relative == "Data Mission":
            allowed.update(range(0, 6))
            allowed.update(range(6, 7+len(name)))
            allowed.update(range(262, 264))
            allowed.update(i*464+6 for i in range(1, len(before)//464))
            assert after[6] == len(name) and after[7:7+len(name)] == name
            assert struct.unpack_from(">hhh", after) == (x, y, opening_map)
            assert struct.unpack_from(">h", after, 262)[0] == 0
            assert sum(after[i*464+6] > 0 for i in range(len(after)//464)) == 1
        elif relative == "Data DD":
            for i in range(100):
                at = opening_map*4200+i*42
                allowed.update(range(at, at+4))
                assert struct.unpack_from(">i", after, at)[0] == -1
        elif relative == "Data RD":
            at = opening_map*644
            allowed.update(range(at+160, at+280))
            allowed.update(range(at+400, at+520))
            assert after[at+160:at+280] == bytes(120)
            assert after[at+400:at+520] == bytes(120)
        elif relative == "Data TD3":
            allowed.update(range(2))
            assert after[:2] == bytes(2)
        delta = [i for i, (a, b) in enumerate(zip(before, after)) if a != b]
        assert all(i in allowed for i in delta), (relative, "unowned byte changes")
        if delta:
            changed[relative] = dict(changed_bytes=len(delta), owned_changes_only=True)

    # Exercise public authoring against real rows, without relying on the codec's diff.
    edits = out / "edits.json"
    edits.write_text(json.dumps([
        dict(kind="message", id=1, text="Patrol ready.\nCafé."),
        dict(kind="floor", map=opening_map, x=x, y=y, tile=-300),
    ]), encoding="utf-8")
    edited_project, edited_level = out / "edited-project", out / "edited-level"
    call(binary, "edit", project, edits, edited_project)
    call(binary, "export", edited_project, edited_level)
    edited_tree = tree(edited_level)
    assert new_tree["files"].keys() == edited_tree["files"].keys()
    assert new_tree["directories"] == edited_tree["directories"]
    for relative in new_tree["files"]:
        expected = bytearray((level / relative).read_bytes())
        if relative == "Data SD2":
            text = "Patrol ready.\rCafé.".encode("mac_roman")
            expected[256] = len(text)
            expected[257:257+len(text)] = text
        elif relative == "Data LD":
            struct.pack_into(">h", expected, opening_map*64800+(x*90+y)*2, -300)
        assert (edited_level / relative).read_bytes() == expected, relative
    assert original_tree == tree(source), "source changed"
    report = dict(status="passed", binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                  candidate=created, exporter_receipt=exported, source=original_tree,
                  candidate_tree=new_tree, changes=changed,
                  real_authoring_checks=["message and map cell overlay", "all other bytes retained"],
                  original_runtime_verified=False)
    receipt = out / "candidate-receipt.json"
    receipt.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(dict(status="passed", files=len(new_tree["files"]), changed_files=changed,
                          receipt=str(receipt))))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("binary", "template", "source", "out"):
        parser.add_argument(f"--{option}", type=Path, required=True)
    args = parser.parse_args()
    verify(*(getattr(args, key).resolve() for key in ("binary", "template", "source", "out")))
