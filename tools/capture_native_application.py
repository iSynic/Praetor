"""Record settled, unpatched First Patrol startup from the owned guest harness.

The known original opening-TEXT display stall remains an incomplete gate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from native_guest import request


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def capture(args):
    out=args.run.resolve();runtime=out/"runtime";level=args.level.resolve()
    def read(at,n):
        return bytes.fromhex(request(runtime,"read-memory","--address",hex(at),"--length",str(n))["hex"])
    a5=int.from_bytes(read(0x904,4),"big")
    globals_=read(a5+0x42720,200)
    field=lambda at:struct.unpack_from(">i",globals_,at-0x42720)[0]
    position=[field(0x42774),field(0x42764)+field(0x42778),field(0x42768)+field(0x4277c)]
    mission=read(a5+0x1d1c4,464)
    assert mission==(level/"Data Mission").read_bytes()[:464]
    stage=mission[7:7+mission[6]].decode("mac_roman")
    code=int.from_bytes(read(a5-0x1de2,4),"big")
    presentation={hex(at):read(code+at,n).hex() for at,n in [(0x3ebde,4),(0x3edb0,2)]}
    assert position==[0,2,2],position
    assert stage=="First Patrol",stage
    assert presentation=={"0x3ebde":"4e56ffee","0x3edb0":"a9dd"},presentation
    inputs=json.loads((out/"inputs.json").read_text())
    changed=[p for p,h in inputs.items() if sha(Path(p))!=h]
    assert not changed,changed
    captures=[p for p in out.glob("*.png")]
    receipt=dict(producer="centurions-native-application",status="partial",authority="original_application",
        startup_status="passed",prologue_status="incomplete",
        prologue_limitation="Original TEScroll/offscreen display stall; existing reference workaround patches instructions and was not used",
        installation="Disposable HFS volume; Cargo Pod MENU 130 item 5 label changed only",
        stage=stage,position=position,ordinary_input="Map click and Conditions feedback observed after arrival",
        a5=a5,code1=code,presentation_instruction_bytes=presentation,instruction_patches=[],
        source_inputs_unchanged=True,export_files={str(p.relative_to(level)).replace('\\','/'):sha(p) for p in sorted(level.rglob('*')) if p.is_file()},
        export_directories=sorted(str(p.relative_to(level)).replace('\\','/') for p in level.rglob('*') if p.is_dir()),
        captures={p.name:sha(p) for p in captures},installation_receipt_sha256=sha(out/"installation.json"),
        globals_hex=globals_.hex())
    (out/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
    print(json.dumps({k:receipt[k] for k in ['status','startup_status','prologue_status','stage','position','presentation_instruction_bytes','source_inputs_unchanged']},indent=2))


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run",type=Path,required=True);p.add_argument("--level",type=Path,required=True)
    capture(p.parse_args())
