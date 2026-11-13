"""Compare decoded tile geometry against an actual original-game framebuffer.

Requires Pillow. Original 8-bit QuickDraw output differs by up to five RGB
levels from the source picture; this checks alignment and raster patterns.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from PIL import Image


def verify(args):
    atlas=Image.open(args.atlas).convert("RGB")
    native=Image.open(args.capture).convert("RGB")
    land=args.land.read_bytes()
    rows=[]
    for x,y in [(6,3),(8,5),(10,7),(12,9),(4,8),(9,10),(5,4),(7,8)]:
        index=x*90+y
        tile=struct.unpack_from(">h",land,index*2)[0]
        assert struct.unpack_from(">h",land,16200+index*2)[0]==0,"choose unobscured floor cells"
        assert 1<=tile<=300
        errors=[]
        for py in range(32):
            for px in range(32):
                source=atlas.getpixel((((tile-1)%20)*32+px,((tile-1)//20)*32+py))
                target=native.getpixel((x*32+px,20+y*32+py))
                errors.extend(abs(a-b) for a,b in zip(source,target))
        assert max(errors)<=5,(x,y,tile,max(errors))
        rows.append(dict(x=x,y=y,tile=tile,max_channel_difference=max(errors),mean_channel_difference=sum(errors)/len(errors)))
    receipt=dict(status="passed",scope="Eight unobscured 32x32 floor rasters; original 8-bit color quantization retained",
        atlas_sha256=hashlib.sha256(args.atlas.read_bytes()).hexdigest(),
        capture_sha256=hashlib.sha256(args.capture.read_bytes()).hexdigest(),
        land_sha256=hashlib.sha256(land).hexdigest(),samples=rows)
    with args.out.open("x",encoding="utf-8") as f:f.write(json.dumps(receipt,indent=2)+"\n")
    print(json.dumps({"status":"passed","samples":len(rows),"maximum_channel_difference":5}))


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("atlas","capture","land","out"):p.add_argument("--"+name,type=Path,required=True)
    verify(p.parse_args())
