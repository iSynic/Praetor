"""Probe original Centurions trigger fields in a disposable read-only Ghidra copy."""
import argparse,hashlib,json,os,shutil,subprocess
from pathlib import Path

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def run(args):
    root=Path(__file__).resolve().parents[1];out=args.out.resolve();base=args.baseline.resolve();reference=args.reference.resolve()
    if not out.is_relative_to(root/'artifacts'):raise ValueError('output must be under artifacts')
    out.mkdir(exist_ok=False)
    prior=json.loads((base/'receipt.json').read_text())
    assert prior['original_binary_relocation_rebuilt'] and prior['original_application_resource_sha256']==digest(reference/'NewCenturions/TheNewCenturions/New Centurions.rsrc')
    scripts=out/'scripts';scripts.mkdir()
    for source in [root/'tools/native/VerifyTriggerFields.java',reference/'tools/ghidra/ActionOracleHarness.java']:shutil.copyfile(source,scripts/source.name)
    project=out/'ghidra-project';shutil.copytree(base/'ghidra-project',project)
    inputs=[reference/'NewCenturions/TheNewCenturions/New Centurions.rsrc',base/'rebuilt/analysis/ghidra/startup/code1-mapped.bin',base/'rebuilt/analysis/ghidra/startup/a5-mapped.bin',*scripts.iterdir()]
    hashes={str(p):digest(p) for p in inputs}
    command=[str(args.ghidra/'support/analyzeHeadless.bat'),str(project),'CenturionsMapped','-process','code1-mapped.bin','-noanalysis','-readOnly','-scriptPath',str(scripts),'-postScript','VerifyTriggerFields.java',str(base),str(out)]
    with (out/'ghidra.log').open('xb') as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,cwd=out,timeout=180,creationflags=0x08000000 if os.name=='nt' else 0)
    log=(out/'ghidra.log').read_text(errors='replace');assert r.returncode==0 and not any(s in log.lower() for s in ['exception','error ','uninitialized']),log[-5000:]
    capture=json.loads((out/'capture.json').read_text());assert [r['selected'] for r in capture['walking']]==[True,True,False,False,False,False,True,False],capture
    assert [(r['event_value'],r['calls_newland']) for r in capture['movement']]==[(-1,False),(0,False),(203,True)]
    assert all(digest(Path(p))==h for p,h in hashes.items())
    (out/'receipt.json').write_text(json.dumps(dict(status='passed',authority=capture['authority'],input_sha256=hashes,reference_writes=False,capture=capture),indent=2)+'\n',encoding='utf8')
    print(json.dumps(capture,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['baseline','reference','ghidra','out']:p.add_argument('--'+name,type=Path,required=True)
    run(p.parse_args())
