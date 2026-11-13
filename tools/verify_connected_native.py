"""Bound original micro-mission instructions to an exact exported level."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    base = args.baseline.resolve()
    reference = args.reference.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        raise ValueError('new output must be under artifacts')
    out.mkdir(exist_ok=False)
    prior = json.loads((base / 'receipt.json').read_text(encoding='utf8'))
    resource = reference / 'NewCenturions/TheNewCenturions/New Centurions.rsrc'
    assert prior['original_binary_relocation_rebuilt']
    assert prior['original_application_resource_sha256'] == digest(resource)
    scripts = out / 'scripts'
    scripts.mkdir()
    for source in [root / 'tools/native/VerifyConnectedMission.java',
                   root / 'tools/native/VerifyScenarioStartup.java',
                   reference / 'tools/ghidra/ActionOracleHarness.java']:
        shutil.copyfile(source, scripts / source.name)
    project = out / 'ghidra-project'
    shutil.copytree(base / 'ghidra-project', project)
    spec = json.loads((base / 'spec.json').read_text(encoding='utf8'))
    case = spec['cases'][1].copy()
    case.update(name='micro', scenario_name='Micro Patrol', level_folder=str(args.level.resolve()),
                select_scenario=False)
    case['menu_items'][4] = 'Micro Patrol'.encode('mac_roman').hex()
    spec['cases'] = [case]
    (out / 'spec.json').write_text(json.dumps(spec, indent=2), encoding='utf8')
    inputs = [resource, *scripts.iterdir(), out / 'spec.json',
              *(Path(row['path']) for row in spec['code_images']), Path(spec['a5_image']),
              *(p for p in args.level.rglob('*') if p.is_file())]
    hashes = {str(p.resolve()): digest(p) for p in inputs}
    command = [str(args.ghidra / 'support/analyzeHeadless.bat'), str(project), 'CenturionsMapped',
               '-process', 'code1-mapped.bin', '-noanalysis', '-readOnly', '-scriptPath', str(scripts),
               '-postScript', 'VerifyConnectedMission.java', str(out / 'spec.json'), str(out / 'capture.json')]
    with (out / 'ghidra.log').open('xb') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=out, timeout=180,
                                creationflags=0x08000000 if os.name == 'nt' else 0)
    assert result.returncode == 0
    capture = json.loads((out / 'capture.json').read_text(encoding='utf8'))
    case = capture['cases'][0]
    assert case['status'] == 'completed', {k: v for k, v in case.items() if k != 'services'}
    assert [case[k] for k in ['completion_stage', 'completion_map', 'completion_x', 'completion_y']] == [1, 0, 4, 2]
    operations = case['connected_operations']
    assert [r['value'] for r in operations if r['operation'] == 'battle-handoff'] == [152]
    assert [r['value'] for r in operations if r['operation'] == 'booty-arguments'] == [0, 65536]
    assert [r['value'] for r in operations if r['operation'] == 'treasure-credits'] == [0, 25]
    assert [r['value'] for r in operations if r['operation'] == 'message-presentation'] == [1348, 1351, 1352]
    capture['authority'] = ('Original startup and newland instructions through choice branch dispatch, battle EXTRA selection, '
                            'post-combat continuation, opcode 10 full 88-byte treasure load, signed one-based stage transition, '
                            'native land/start-story loading and completion-message request. Choice selector, combat result, '
                            'booty UI/award processing and presentation are explicit hosted services. Stops at completion text; '
                            'no full original battle, currency arithmetic, prologue or interactive teardown claim.')
    assert all(digest(Path(p)) == h for p, h in hashes.items())
    (out / 'receipt.json').write_text(json.dumps({'status': 'passed', 'input_sha256': hashes, 'capture': capture,
                                                 'reference_writes': False}, indent=2), encoding='utf8')
    print(json.dumps([{k: v for k, v in row.items() if k != 'services'} for row in capture['cases']], indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline', 'reference', 'ghidra', 'level', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    run(parser.parse_args())
