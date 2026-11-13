"""Author a death-dialogue continuation case for the B01 saved-caller frontier."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root/'artifacts'):
        raise ValueError('output must be a new artifacts directory')
    out.mkdir(exist_ok=False)

    def run(binary, name, arguments, expected_success=True):
        argv = [str(binary.resolve()), *map(str, arguments)]
        result = subprocess.run(argv, cwd=out, capture_output=True, text=True, encoding='utf8',
                                timeout=60, creationflags=0x08000000 if os.name == 'nt' else 0)
        (out/(name+'.stdout')).write_text(result.stdout, encoding='utf8')
        (out/(name+'.stderr')).write_text(result.stderr, encoding='utf8')
        (out/(name+'-process.json')).write_text(json.dumps({'argv': argv, 'exit_code': result.returncode}, indent=2), encoding='utf8')
        if expected_success:
            assert result.returncode == 0, result.stderr
        return result

    spec = {'name': 'Death Return Patrol', 'monster_seed': 17, 'monster_name': 'Training Node',
            'introduction': 'An unstable control node blocks the route.'}
    (out/'spec.json').write_text(json.dumps(spec, indent=2), encoding='utf8')
    run(args.editor, 'create', ['micro', args.template.resolve(), out/'spec.json', out/'project'])
    allocation = run(args.editor, 'allocate', ['allocate', out/'project', 'message', 0, out/'allocated'])
    message = json.loads(allocation.stdout)['id']
    edits = [{'kind': 'message', 'id': message, 'text': 'Control node shutdown acknowledged.'},
             {'kind': 'script_step', 'family': 'story', 'id': 3, 'branch': 0, 'slot': 0, 'opcode': 1, 'operand': message}]
    (out/'edits.json').write_text(json.dumps(edits, indent=2), encoding='utf8')
    run(args.editor, 'edit', ['edit', out/'allocated', out/'edits.json', out/'authored'])
    run(args.editor, 'export', ['export', out/'authored', out/'level'])
    # Seed 17 retains its native death hook 3. Only the supported message step is edited;
    # native sound/removal instructions and every other prototype byte stay inherited.
    monster_table = (out/'level/Data MD').read_bytes()
    assert monster_table[136*288+96:136*288+98] == b'\x00\x03'
    installation = out/'installation'
    shutil.copytree(args.installation.resolve(), installation)
    shutil.copytree(out/'level', installation/'Scenarios/Death Return Patrol/0')
    commands = ['ImportStarters', {'SelectStarters': {'indices': list(range(6))}},
                {'EnterMission': {'name': spec['name']}}, {'Move': {'dx': 1, 'dy': 0}},
                'Continue', {'SelectMenuEntry': {'index': 0}}]
    (out/'entry-commands.json').write_text(json.dumps(commands, indent=2), encoding='utf8')
    entry = run(args.runtime, 'entry', ['replay', installation, out/'entry-commands.json', '--save', out/'entry.save.json'])
    events = [json.loads(line) for line in entry.stdout.splitlines() if line.strip()][:-1]
    saved = out/'entry.save.json'
    state = json.loads(saved.read_text())['session']
    last = ''
    death_pause = None
    failure = None
    for index in range(60):
        presentation = state['exploration']['presentation']
        combat = state.get('combat')
        if presentation is not None:
            command = 'Continue'
        elif combat is not None:
            if combat.get('selection_pending'):
                command = 'ResumeCombatSelection'
            elif combat['order'][combat['cursor']] >= 10:
                command = 'RunEnemyTurn'
            else:
                command = 'RunControlledTurn' if last == 'BeginAutomaticTurn' else 'BeginAutomaticTurn'
        else:
            break
        path = out/f'step-{index:02}-command.json'
        path.write_text(json.dumps([command]), encoding='utf8')
        output = out/f'step-{index:02}.save.json'
        result = run(args.runtime, f'step-{index:02}', ['replay', installation, path,
                     '--from', saved, '--save', output], expected_success=False)
        commands.append(command)
        values = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        events.extend(value for value in values if isinstance(value, list))
        if result.returncode:
            failure = {'input_save': str(saved), 'command': command, 'diagnostic': result.stderr,
                       'result_save': str(output), 'backlog': 'B01'}
            break
        state = json.loads(output.read_text())['session']
        presentation = state['exploration']['presentation']
        if isinstance(presentation, dict) and presentation.get('Dialogue', {}).get('id') == message:
            assert state['combat'] is not None
            death_pause = {'save': str(output), 'message': message, 'pending_combat_story': state.get('combat_story')}
        saved = output
        last = command
        if state['mission_stage'] == 1 and state['exploration']['presentation'] is None:
            break
    (out/'commands.json').write_text(json.dumps(commands, indent=2), encoding='utf8')
    assert failure is None, failure
    assert death_pause is not None, 'No genuine death-dialogue pause reached'
    assert state['party_currency'] == 25 and state['mission_stage'] == 1
    assert state['exploration']['presentation'] is None and state['combat'] is None
    uninterrupted = run(args.runtime, 'uninterrupted', ['replay', installation, out/'commands.json',
                        '--save', out/'uninterrupted.save.json'])
    values = [json.loads(line) for line in uninterrupted.stdout.splitlines() if line.strip()]
    assert values[-1] == state and values[:-1] == events
    receipt = {'status': 'passed_for_authored_death_dialogue_return', 'backlog': 'B01',
               'death_pause': death_pause, 'complete_state_equal': True, 'ordered_events_equal': True,
               'reward_credits': 25, 'completion_stage': 1, 'commands': len(commands),
               'runtime_sha256': digest(args.runtime), 'editor_sha256': digest(args.editor),
               'export_sha256': {p.relative_to(out/'level').as_posix(): digest(p) for p in (out/'level').rglob('*') if p.is_file()},
               'remaining_gap': 'This is one ordinary NPC death-dialogue return; nested callbacks, detached frames, original-native qualification and B01 closure remain outside this case.'}
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in receipt.items() if k not in ['death_pause', 'export_sha256']}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['editor', 'runtime', 'template', 'installation', 'out']:
        parser.add_argument('--'+name, type=Path, required=True)
    verify(parser.parse_args())
