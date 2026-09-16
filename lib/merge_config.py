# /// script
# requires-python = ">=3.9"
# dependencies = ["tomlkit==0.13.3"]
# ///
"""Format adapters for dot composition. JSON requests on stdin, results on stdout.

To add a format, register its parser/writer here and its suffix in composition.py.
The deployment planner, ownership tracking, and backups are format-independent.
"""
import json
from pathlib import Path
import sys

import tomlkit


def merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        result = dict(base)
        for key, value in overlay.items():
            result[key] = merge(result[key], value) if key in result else value
        return result
    return overlay


def merge_toml(base, overlay):
    # Unwrap syntax nodes so tables merge by value, not by formatting/type hints.
    return tomlkit.dumps(merge(tomlkit.parse(base).unwrap(), tomlkit.parse(overlay).unwrap()))


ADAPTERS = {"toml": merge_toml}


def main():
    outputs = []
    for request in json.load(sys.stdin):
        try:
            base = Path(request["base"]).read_text(encoding="utf-8")
            overlay = Path(request["overlay"]).read_text(encoding="utf-8")
            outputs.append(ADAPTERS[request["format"]](base, overlay))
        except (OSError, ValueError, KeyError) as error:
            print(f"{request['base']} + {request['overlay']}: {error}", file=sys.stderr)
            return 1
    json.dump(outputs, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
