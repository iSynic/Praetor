"""Author one ordinary-battle cleanup-mode-5 case for the I11/B01 runtime frontier."""
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

    def run(binary, name, arguments, allow_failure=False):
        argv = [str(binary.resolve()), *map(str, arguments)]
        result = subprocess.run(argv, cwd=out, capture_output=True, text=True, encoding='utf8',
                                timeout=60, creationflags=0x08000000 if os.name == 'nt' else 0)
        (out/(name+'.stdout')).write_text(result.stdout, encoding='utf8')
        (out/(name+'.stderr')).write_text(result.stderr, encoding='utf8')
        (out/(name+'-process.json')).write_text(json.dumps({'argv': argv, 'exit_code': result.returncode}, indent=2), encoding='utf8')
        if not allow_failure:
            assert result.returncode == 0, result.stderr
        return result

    template = args.template.resolve()
    (out/'spec.json').write_text(json.dumps({'name': 'No Loot Patrol'}), encoding='utf8')
    created = run(args.editor, 'create', ['micro', template, out/'spec.json', out/'project'])
    recipe = json.loads(created.stdout)
    ids = recipe['records']
    extra = json.loads(run(args.editor, 'extra', ['record', out/'project', 'battle_extra', ids['battle_extra']]).stdout)
    edit = {key: extra[key] for key in ['id', 'minimum', 'maximum', 'sound', 'message']}
    edit.update(kind='battle_extra', cleanup_mode=5)
    (out/'edit.json').write_text(json.dumps([edit], indent=2), encoding='utf8')
    run(args.editor, 'edit', ['edit', out/'project', out/'edit.json', out/'mode5-project'])
    run(args.editor, 'export', ['export', out/'mode5-project', out/'level'])
    installation = out/'installation'
    shutil.copytree(args.installation.resolve(), installation)
    shutil.copytree(out/'level', installation/'Scenarios/No Loot Patrol/0')
    commands = json.loads(args.commands.read_text(encoding='utf8'))
    commands[2] = {'EnterMission': {'name': 'No Loot Patrol'}}
    # Isolate the victory/cleanup boundary from a genuine ordinary-turn producer;
    # no NPC, treasure or context records are fabricated.
    (out/'prefix-commands.json').write_text(json.dumps(commands[:17], indent=2), encoding='utf8')
    run(args.runtime, 'prefix', ['replay', installation, out/'prefix-commands.json', '--save', out/'before.save.json'])
    (out/'one-command.json').write_text(json.dumps([commands[17]], indent=2), encoding='utf8')
    result = run(args.runtime, 'boundary', ['replay', installation, out/'one-command.json',
                 '--from', out/'before.save.json', '--save', out/'after.save.json', '--trace'], allow_failure=True)
    values = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    before = json.loads((out/'before.save.json').read_text())['session']
    after = json.loads((out/'after.save.json').read_text())['session']
    events = [event for value in values if isinstance(value, list) for event in value]
    trace = [value for value in values if isinstance(value, dict) and 'kind' in value]
    (out/'ordered-events.json').write_text(json.dumps(events, indent=2), encoding='utf8')
    (out/'trace.json').write_text(json.dumps(trace, indent=2), encoding='utf8')
    assert result.returncode == 0, result.stderr
    assert after['ordinary_battle_rewards']['mode'] == 5
    assert after['npc_backing']['active_count'] == 0
    (out/'suffix-commands.json').write_text(json.dumps(commands[18:], indent=2), encoding='utf8')
    resumed = run(args.runtime, 'suffix', ['replay', installation, out/'suffix-commands.json',
                  '--from', out/'after.save.json', '--save', out/'completed.save.json'])
    final = json.loads((out/'completed.save.json').read_text())['session']
    assert final['party_currency'] == 25 and final['mission_stage'] == 1
    assert final['exploration']['presentation'] is None
    (out/'all-commands.json').write_text(json.dumps(commands, indent=2), encoding='utf8')
    full = run(args.runtime, 'uninterrupted', ['replay', installation, out/'all-commands.json',
               '--save', out/'uninterrupted.save.json'])
    assert json.loads((out/'uninterrupted.save.json').read_text())['session'] == final
    prefix_events = [json.loads(line) for line in (out/'prefix.stdout').read_text().splitlines() if line.strip()][:-1]
    suffix_events = [json.loads(line) for line in resumed.stdout.splitlines() if line.strip()][:-1]
    full_events = [json.loads(line) for line in full.stdout.splitlines() if line.strip()][:-1]
    boundary_events = [value for value in values if isinstance(value, list)]
    assert prefix_events + boundary_events + suffix_events == full_events
    receipt = {'runtime_exit_code': result.returncode, 'diagnostic': result.stderr.strip(),
               'status': 'passed_for_zero_count_outer_mode5',
               'remaining_gap': 'I11/B01 positive retained-NPC mode5 is not reached: ordinary battle teardown leaves active_count=0; no state is fabricated to reach that guard.',
               'saved_continuation_equal': True, 'ordered_events_equal': True,
               'state_unchanged': before == after, 'ordered_events': events,
               'scenario': 'No Loot Patrol', 'extra': edit,
               'backlog': ['I11', 'B01'], 'editor_serialization': 'typed battle_extra overlay',
               'runtime_sha256': digest(args.runtime), 'editor_sha256': digest(args.editor),
               'input_save_sha256': digest(out/'before.save.json'),
               'result_save_sha256': digest(out/'after.save.json'),
               'export_sha256': {p.relative_to(out/'level').as_posix(): digest(p) for p in (out/'level').rglob('*') if p.is_file()},
               'qualification': 'Production command boundary; original-binary behavior is not qualified by this case.'}
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'export_sha256'}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['editor', 'runtime', 'template', 'installation', 'commands', 'out']:
        parser.add_argument('--'+name, type=Path, required=True)
    verify(parser.parse_args())
