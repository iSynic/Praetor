"""Use the isolated emulator's guest harness, without host input automation."""
import argparse
import json
from pathlib import Path
import subprocess


def request(runtime, *arguments):
    arguments = list(map(str, arguments))
    if "--out" in arguments:
        at = arguments.index("--out")+1
        arguments[at] = arguments[at].replace("\\", "/")
    result = subprocess.run([str(runtime / "divinity-harness-client.exe"), "--token-file",
        str(runtime / "divinity-harness-token.txt"), *map(str, arguments)],
        capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    reply = json.loads(result.stdout)
    if not reply.get("ok"):
        raise RuntimeError(reply)
    with (runtime.parent / "guest-actions.jsonl").open("a", encoding="utf-8") as log:
        log.write(json.dumps(dict(arguments=arguments, reply=reply))+"\n")
    return reply


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    print(json.dumps(request(args.runtime.resolve(), *args.arguments)))
