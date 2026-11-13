"""Verify production replay save output and connected-mission continuation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        raise ValueError('output must be a new artifacts directory')
    out.mkdir(exist_ok=False)
    binary = args.binary.resolve()
    installation = args.installation.resolve()
    commands = json.loads(args.commands.read_text(encoding='utf8'))
    inputs = {str(p.resolve()): digest(p) for p in [binary, args.commands,
              *(p for p in installation.rglob('*') if p.is_file())]}

    def replay(name, sequence, source=None, extra=None, expected_exit=0):
        path = out / (name + '-commands.json')
        path.write_text(json.dumps(sequence, indent=2), encoding='utf8')
        save = out / (name + '.save.json')
        argv = [str(binary), 'replay', str(installation), str(path)]
        if source:
            argv += ['--from', str(source)]
        argv += extra if extra is not None else ['--save', str(save)]
        result = subprocess.run(argv, cwd=out, capture_output=True, text=True, encoding='utf8',
                                timeout=60, creationflags=0x08000000 if os.name == 'nt' else 0)
        (out / (name + '.stdout')).write_text(result.stdout, encoding='utf8')
        (out / (name + '.stderr')).write_text(result.stderr, encoding='utf8')
        (out / (name + '-process.json')).write_text(json.dumps(
            {'argv': argv, 'exit_code': result.returncode}, indent=2), encoding='utf8')
        assert (result.returncode == 0) == (expected_exit == 0), (name, result.stderr)
        values = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        return save, values, result.stderr

    final_save, uninterrupted, _ = replay('uninterrupted', commands)
    final = uninterrupted[-1]
    assert json.loads(final_save.read_text())['session'] == final
    assert final['party_currency'] == 25 and final['mission_stage'] == 1
    assert final['exploration']['presentation'] is None
    cases = []
    # Each split reaches a different saved caller: choice, combat, two loot owners,
    # and the stage's prologue/start-story continuation.
    for cut, name in [(5, 'choice'), (6, 'battle'), (18, 'battle-loot'),
                      (19, 'reward-loot'), (21, 'transition')]:
        saved, prefix, _ = replay(name, commands[:cut])
        _, suffix, _ = replay(name + '-resumed', commands[cut:], saved)
        assert prefix[:-1] + suffix[:-1] == uninterrupted[:-1], name
        assert suffix[-1] == final, name
        _, loaded, _ = replay(name + '-roundtrip', [], saved)
        assert loaded[-1] == prefix[-1], name
        cases.append({'case': name, 'ordered_events_equal': True, 'complete_state_equal': True})

    rejected_save, rejected, diagnostic = replay('idle-continue', ['Continue'], final_save, expected_exit=1)
    assert 'no story page to continue' in diagnostic
    assert rejected == [final]
    assert json.loads(rejected_save.read_text())['session'] == final
    _, reloaded, _ = replay('idle-reload', [], rejected_save)
    assert reloaded == [final]
    replay('missing-output', [], extra=['--save'], expected_exit=1)
    replay('duplicate-output', [], extra=['--save', str(out/'unused.json'), '--save', str(out/'unused2.json')], expected_exit=1)
    assert not (out/'unused.json').exists() and not (out/'unused2.json').exists()
    directory = out/'save-directory'
    directory.mkdir()
    replay('save-failure', [], final_save, extra=['--save', str(directory)], expected_exit=1)
    assert json.loads(final_save.read_text())['session'] == final
    assert all(digest(Path(p)) == h for p, h in inputs.items())
    receipt = {'status': 'passed', 'binary_sha256': inputs[str(binary)],
               'input_sha256': inputs, 'boundaries': cases,
               'rejected_command_saved_actual_valid_state': True,
               'missing_duplicate_and_failed_outputs_rejected': True,
               'input_files_unchanged': True, 'artifact_local_gameplay_wrapper': False,
               'qualification': 'Production replay/apply/save/load only; reconstruction acceptance.'}
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'input_sha256'}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['binary', 'installation', 'commands', 'out']:
        parser.add_argument('--'+name, type=Path, required=True)
    verify(parser.parse_args())
