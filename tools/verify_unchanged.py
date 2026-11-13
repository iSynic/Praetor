"""Independent private-folder preservation gate. Never writes to its input."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def tree(root):
    files, directories = {}, []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"link in comparison input: {path}")
        relative = path.relative_to(root).as_posix()
        if path.is_dir():
            directories.append(relative)
        elif path.is_file():
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return dict(files=files, directories=directories)


def call(binary, *args):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def verify(binary, source, out):
    artifact_root = Path(__file__).resolve().parents[1] / "artifacts"
    if not out.is_relative_to(artifact_root):
        raise ValueError("verification output must be inside this checkout's artifacts directory")
    out.mkdir(exist_ok=False)
    before = tree(source)
    project, exported = out / "imported", out / "unchanged-export"
    call(binary, "import", source, project)
    receipt = call(binary, "export", project, exported)
    actual = tree(exported)
    if before != actual:
        raise AssertionError("independent complete tree comparison failed")
    if before != tree(source):
        raise AssertionError("input changed")
    if not receipt["byte_exact_to_import"]:
        raise AssertionError("exporter did not report unchanged")
    # Check selected projections with Python's independent endian and Mac Roman readers.
    mission = (source / "Data Mission").read_bytes()
    first = call(binary, "inspect", project)["stages"][0]
    assert first["name"] == mission[7:7+mission[6]].decode("mac_roman").replace("\r", "\n")
    assert (first["x"], first["y"], first["map"]) == struct.unpack_from(">hhh", mission)
    scripts = (source / "Data ED3").read_bytes()
    script = call(binary, "story", project, 1)
    assert [a["opcode"] for a in script["actions"]] == list(struct.unpack_from(">8h", scripts, 42+8))
    assert [a["operand"] for a in script["actions"]] == list(struct.unpack_from(">8h", scripts, 42+24))
    messages = (source / "Data SD2").read_bytes()
    for ident in (0, 1, len(messages)//256-1):
        row = messages[ident*256:(ident+1)*256]
        assert call(binary, "message", project, ident)["text"] == row[1:1+row[0]].decode("mac_roman").replace("\r", "\n")
    report = dict(
        status="passed", boundary="extracted folder files and empty directories",
        original_runtime_verified=False, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
        source=before, exported=actual, exporter_receipt=receipt,
        projection_checks=["stage name and coordinates", "eight signed story opcodes and operands", "Mac Roman message samples"],
    )
    (out / "unchanged-receipt.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(dict(status="passed", files=len(before["files"]), directories=len(before["directories"]),
                          receipt=str(out / "unchanged-receipt.json"))))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    verify(args.binary.resolve(), args.source.resolve(), args.out.resolve())
