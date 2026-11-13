"""Replay the exported micro mission in a disposable reconstruction installation."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        raise ValueError('output must be a new artifacts directory')
    out.mkdir(exist_ok=False)
    installation = out / 'installation'
    shutil.copytree(args.installation, installation)
    # This prebuilt runtime resolves scenario data through its Thunder loader.
    # The alias exists only in this disposable replay installation.
    shutil.copytree(args.level, installation / 'Scenarios/The Thunder of Guns/0', dirs_exist_ok=True)
    binary = args.reference / 'target/release/centurions-tools.exe'
    inputs = {str(p.resolve()): digest(p) for p in [binary, *args.level.rglob('*')] if p.is_file()}
    prefix = ['ImportStarters', {'SelectStarters': {'indices': list(range(6))}},
              {'EnterMission': {'name': 'The Thunder of Guns'}}, {'Move': {'dx': 1, 'dy': 0}}, 'Continue']

    def replay(commands, name):
        command_path = out / (name + '-commands.json')
        command_path.write_text(json.dumps(commands, indent=2), encoding='utf8')
        result = subprocess.run([str(binary.resolve()), 'replay', str(installation), str(command_path)],
                                capture_output=True, text=True, encoding='utf8', timeout=60)
        (out / (name + '.stdout')).write_text(result.stdout, encoding='utf8')
        (out / (name + '.stderr')).write_text(result.stderr, encoding='utf8')
        if result.returncode:
            raise RuntimeError(result.stderr)
        decoder = json.JSONDecoder()
        remaining = result.stdout.lstrip()
        values = []
        while remaining:
            value, end = decoder.raw_decode(remaining)
            values.append(value)
            remaining = remaining[end:].lstrip()
        state = values[-1]
        (out / (name + '-state.json')).write_text(json.dumps(state, indent=2), encoding='utf8')
        return state, values[:-1]

    commands = prefix + [{'SelectMenuEntry': {'index': 0}}]
    state, events = replay(commands, 'accept-00')
    for attempt in range(40):
        combat = state.get('combat')
        if combat:
            if combat.get('selection_pending'):
                commands.append('ResumeCombatSelection')
            elif combat['order'][combat['cursor']] >= 10:
                commands.append('RunEnemyTurn')
            else:
                commands += ['BeginAutomaticTurn', 'RunControlledTurn']
        else:
            if state.get('phase') == 'Exploration' and state.get('mission_stage') == 1:
                break
            commands.append('Continue')
        state, events = replay(commands, f'accept-{attempt+1:02}')
    (out / 'accepted-commands.json').write_text(json.dumps(commands, indent=2), encoding='utf8')
    (out / 'accepted-state.json').write_text(json.dumps(state, indent=2), encoding='utf8')
    assert state['phase'] == 'Exploration' and state['mission_stage'] == 1
    assert state['party_currency'] == 25
    assert [state['exploration'][k] for k in ['map', 'x', 'y']] == [0, 4, 2]
    decline, decline_events = replay(prefix + [{'SelectMenuEntry': {'index': 1}}, 'Continue'], 'decline')
    assert decline['phase'] == 'Exploration' and decline['mission_stage'] == 0
    assert decline['party_currency'] == 0 and decline['combat'] is None
    receipt = {'authority': 'read-only prebuilt reconstruction replay; not original-game acceptance',
               'mount_alias': 'Scenarios/The Thunder of Guns/0 in disposable installation only',
               'status': 'passed', 'input_sha256': inputs,
               'accepted': {'stage': 1, 'map': 0, 'x': 4, 'y': 2, 'credits': 25},
               'declined': {'stage': 0, 'credits': 0, 'combat': False}}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    assert all(digest(Path(p)) == h for p, h in inputs.items())
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['reference', 'installation', 'level', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    run(parser.parse_args())
