"""Run the connected GUI workflow and compare complete exports with CLI authoring."""
import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path


def tree(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


def run(args):
    root = Path(__file__).resolve().parents[1]
    out = args.out.resolve()
    if not out.is_relative_to(root / 'artifacts'):
        raise ValueError('new output must be under artifacts')
    out.mkdir(exist_ok=False)
    binary = args.editor.resolve()
    template = args.template.resolve()
    before = tree(template)
    def cli(*command):
        result = subprocess.run([str(binary), *map(str, command)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)
    cli('new', template, out / 'base', 'Micro Patrol')
    (out / 'spec.json').write_text('{}\n', encoding='utf8')
    recipe = cli('micro', template, out / 'spec.json', out / 'cli-project')
    (out / 'recipe.json').write_text(json.dumps(recipe, indent=2), encoding='utf8')
    cli('export', out / 'cli-project', out / 'cli-level')
    env = dict(os.environ, CENTURIONS_PROJECT=str(out / 'base'), CENTURIONS_TEST_OUT=str(out),
               CENTURIONS_SETTINGS_FILE=str(out / 'settings.json'),
               CENTURIONS_INSTALLATION=str(args.installation.resolve()))
    command = ([str(args.godot.resolve()), '--headless', '--', '--verify-connected'] if args.packaged else
               [str(args.godot), '--headless', '--path', str(root / 'godot'), '--', '--verify-connected'])
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=100,
                            creationflags=0x08000000 if os.name == 'nt' else 0)
    log = result.stdout + result.stderr
    (out / 'godot.log').write_text(log, encoding='utf8')
    assert result.returncode == 0 and 'CENTURIONS_CONNECTED_WORKFLOW_PASSED' in log, log
    assert not any(s in log for s in ['ERROR:', 'WARNING:']), log
    assert tree(out / 'level') == tree(out / 'cli-level') == tree(out / 'reopened-level')
    assert tree(template) == before
    receipt = {'status': 'passed', 'packaged': args.packaged, 'cli_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
               'gui_sha256': hashlib.sha256(args.godot.read_bytes()).hexdigest() if args.packaged else None,
               'complete_gui_cli_reopen_comparison': True, 'template_unchanged': True,
               'export_sha256': tree(out / 'level')}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'export_sha256'}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packaged', action='store_true')
    for name in ['godot', 'editor', 'template', 'installation', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    run(parser.parse_args())
