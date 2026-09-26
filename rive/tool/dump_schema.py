"""Dump `rive schema <Type> --json --all` for every type into one file.

Produces tool/rive_schema.json: {TypeName: schemaObject}. The decoder uses it
to turn typeKeys / propertyKeys in a .riv into RML element / attribute names.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")
HERE = os.path.dirname(os.path.abspath(__file__))


def run(args):
    out = subprocess.run([RIVE, *args], capture_output=True)
    return out.stdout.decode("utf-8", "replace")


def main():
    names = json.loads(run(["schema", "--list", "--json"]))

    def one(n):
        txt = run(["schema", n, "--json", "--all"])
        try:
            return n, json.loads(txt)
        except json.JSONDecodeError:
            return n, None

    with ThreadPoolExecutor(8) as ex:
        res = dict(ex.map(one, names))
    bad = [k for k, v in res.items() if v is None]
    path = os.path.join(HERE, "rive_schema.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(res, f)
    print(f"{len(res) - len(bad)} types -> {path}; unreadable: {bad}")


if __name__ == "__main__":
    sys.exit(main())
