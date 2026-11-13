"""Create a private HFS test installation; never rewrite the supplied boot volume.

Uses locally installed machfs/macresources, supplied explicitly with --pydeps.
The known malformed catalog record is recorded and quarantined only while
reading. No catalog repair is written back to the input volume.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys

sys.dont_write_bytecode = True


def sha(data):
    return hashlib.sha256(data).hexdigest()


def scenario_name(value):
    try:
        encoded = value.encode("mac_roman")
    except UnicodeEncodeError as error:
        raise argparse.ArgumentTypeError("scenario name must be Mac Roman") from error
    if (not 1 <= len(encoded) <= 31 or value in (".", "..")
            or any(character in value for character in "/\\:")
            or any(byte < 32 or byte == 127 for byte in encoded)):
        raise argparse.ArgumentTypeError("scenario name must be one HFS component of 1..31 bytes")
    return value


def resource_fork(data):
    if data[:4] not in (bytes.fromhex("00051607"), bytes.fromhex("00051600")):
        return data
    entries = [struct.unpack_from(">III", data, 26+12*i)
               for i in range(struct.unpack_from(">H", data, 24)[0])]
    forks = [data[at:at+size] for kind, at, size in entries if kind == 2 and at+size <= len(data)]
    if not any(kind == 2 for kind, _, _ in entries):
        return b""
    if len(forks) != 1:
        raise ValueError("invalid AppleDouble resource fork")
    return forks[0]


def inventory(folder):
    result = {}
    for path, obj in folder.iter_paths():
        if hasattr(obj, "data"):
            result["/".join(path)] = dict(data=sha(obj.data), rsrc=sha(obj.rsrc),
                type=obj.type.hex(), creator=obj.creator.hex(), flags=obj.flags,
                x=obj.x, y=obj.y, crdate=obj.crdate, mddate=obj.mddate, bkdate=obj.bkdate)
    return result


def run(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / "artifacts"):
        raise ValueError("output must be a new artifacts directory")
    name = args.scenario_name
    if not (args.level.resolve() / name).is_file():
        raise ValueError("export must contain its scenario-named startup header")
    out.mkdir(exist_ok=False)
    sys.path.insert(0, str(args.pydeps.resolve()))
    import machfs
    from machfs import btree
    from macresources import make_file, parse_file

    reference = args.reference.resolve()
    source = reference / "NewCenturions/TheNewCenturions"
    runtime = out / "runtime"
    runtime.mkdir()
    inputs = [reference / "reference/centurions.hfv", reference / "reference/xpram.dat", args.rom.resolve()]
    inputs += [reference / "reference/bin" / name for name in
               ("BasiliskII.exe", "divinity-harness-client.exe", "libgcc_s_dw2-1.dll", "libwinpthread-1.dll")]
    inputs += [p for p in args.level.resolve().rglob("*") if p.is_file()]
    inputs += [source / "New Centurions", source / "New Centurions.rsrc"]
    identities = {str(p): sha(p.read_bytes()) for p in inputs}
    (out / "inputs.json").write_text(json.dumps(identities, indent=2)+"\n")
    for p in inputs[:7]:
        shutil.copyfile(p, runtime / p.name)

    anomalies = []
    dump = btree.dump_btree

    def checked_records(buf):
        for index, rec in enumerate(dump(buf)):
            if rec and rec[0] != 7 and len(rec) <= ((rec[0]+2) & ~1):
                # This exact invalid record is present in the supplied boot disk.
                expected = bytes.fromhex("466f726d617420427574746f6e20546573740000093c085363656e6172696f00")
                if rec != expected:
                    raise ValueError(f"unrecognized malformed catalog record {index}: {rec.hex()}")
                anomalies.append(dict(index=index, hex=rec.hex(), action="read quarantine; input untouched"))
                continue
            yield rec

    btree.dump_btree = checked_records
    boot = machfs.Volume()
    boot.read(inputs[0].read_bytes())
    btree.dump_btree = dump
    game = copy.deepcopy(boot["TheNewCenturions"])
    before = inventory(game)
    # Establish that this disk's application is the same original used by the oracle.
    original_app = resource_fork((source / "New Centurions.rsrc").read_bytes())
    resource_identity = lambda fork: {(r.type, r.id): (bytes(r.data), r.name, r.attribs) for r in parse_file(fork)}
    assert resource_identity(game["New Centurions"].rsrc) == resource_identity(original_app)
    # Resource Manager changes handle fields in fork maps on disk. Install the
    # exact extracted original container as well as its identical code payloads.
    game["New Centurions"].rsrc = original_app
    game["New Centurions"].data = (source / "New Centurions").read_bytes()
    level = copy.deepcopy(game["Scenarios"]["The Thunder of Guns"]["0"])
    exported = args.level.resolve()
    for p in sorted(exported.iterdir()):
        if not p.is_file() or p.name.endswith(".rsrc"):
            continue
        if p.name not in level:
            level[p.name] = copy.deepcopy(level["The Thunder of Guns"])
        level[p.name].data = p.read_bytes()
        fork = exported / (p.name + ".rsrc")
        if fork.exists():
            level[p.name].rsrc = resource_fork(fork.read_bytes())
    new_scenario = copy.deepcopy(game["Scenarios"]["The Thunder of Guns"])
    new_scenario["0"] = level
    game["Scenarios"][name] = new_scenario

    cargo = game["Data Files"]["Cargo Pod"]
    resources = list(parse_file(cargo.rsrc))
    original_resources = {(r.type, r.id): bytes(r.data) for r in resources}
    menu = next(r for r in resources if r.type == b"MENU" and r.id == 130)
    payload = bytes(menu.data)
    at = 15 + payload[14]
    for _ in range(4):
        at += payload[at]+5
    length = payload[at]
    assert payload[at+1:at+1+length] == b"The Thunder of Guns"
    label = name.encode("mac_roman")
    menu.data = payload[:at] + bytes([len(label)]) + label + payload[at+1+length:]
    cargo.rsrc = make_file(resources)
    changed = [(t.decode("mac_roman"), i) for (t, i), data in original_resources.items()
               if data != next(bytes(r.data) for r in parse_file(cargo.rsrc) if (r.type, r.id) == (t, i))]
    assert changed == [("MENU", 130)]
    assert sha(game["New Centurions"].rsrc) == sha(original_app)

    volume = machfs.Volume()
    volume.name = name[:22] + " Test"
    volume["TheNewCenturions"] = game
    expected = inventory(volume)
    image = volume.write(size=64*1024*1024, bootable=False, desktopdb=False)
    check = machfs.Volume()
    check.read(image)
    assert inventory(check) == expected, "HFS write/read-back fork or metadata mismatch"
    (runtime / "first-patrol.hfv").write_bytes(image)
    prefs = f'''rom {runtime / 'Quadra-650.ROM'}
disk {runtime / 'centurions.hfv'}
disk {runtime / 'first-patrol.hfv'}
bootdriver 0
ramsize 134217728
frameskip 1
modelid 14
cpu 4
fpu true
screen win/800/600
displaycolordepth 8
nosound true
nocdrom true
nogui true
enableextfs false
xpram {runtime / 'xpram.dat'}
sdlrender software
sdl_vsync false
title {name} Validation
'''
    (runtime / "BasiliskII_prefs").write_text(prefs)
    assert all(sha(Path(p).read_bytes()) == h for p, h in identities.items())
    receipt = dict(status="staged; application startup pending", catalog_anomalies=anomalies,
        input_hashes_unchanged=True, application_resource_unchanged=True,
        menu_change=dict(owner="Data Files/Cargo Pod", type="MENU", id=130, item=5,
                         before="The Thunder of Guns", after=name),
        readback_files=len(expected), image_sha256=sha(image), files=expected)
    (out / "installation.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print(json.dumps({k:v for k,v in receipt.items() if k != "files"}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("reference", "pydeps", "rom", "level", "out"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--scenario-name", type=scenario_name, default="First Patrol")
    run(parser.parse_args())
