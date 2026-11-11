#!/usr/bin/env python3
"""Read-only EFB profile configuration check. Never prints secrets or config values."""
import argparse
import os
import re
import sys
from importlib.metadata import entry_points
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Check EFB profile module entry points without logging credentials")
    parser.add_argument("--profile", default="default")
    parser.add_argument("--home", default=os.environ.get("HOME", ""))
    args = parser.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9_-]{0,23}", args.profile):
        parser.error("invalid profile name")
    if not args.home:
        parser.error("HOME must be set")
    path = Path(args.home) / ".ehforwarderbot" / "profiles" / args.profile / "config.yaml"
    if not path.is_file():
        print(f"Profile {args.profile}: config.yaml is missing; run efb-wizard --profile {args.profile}", file=sys.stderr)
        return 2
    try:
        from ruamel.yaml import YAML
        with path.open(encoding="utf-8") as f:
            config = YAML(typ="safe").load(f) or {}
        if not isinstance(config, dict):
            raise ValueError("config must be a mapping")
    except Exception as exc:
        print(f"Profile {args.profile}: configuration could not be parsed ({type(exc).__name__}); no values disclosed", file=sys.stderr)
        return 2

    master = config.get("master_channel")
    slaves = config.get("slave_channels", [])
    middlewares = config.get("middlewares", [])
    if not isinstance(master, str) or not master or not isinstance(slaves, list) or not slaves or not isinstance(middlewares, list):
        print(f"Profile {args.profile}: master/slave/middleware structure is incomplete", file=sys.stderr)
        return 2

    groups = (
        ("master", "ehforwarderbot.master", [master]),
        ("slave", "ehforwarderbot.slave", slaves),
        ("middleware", "ehforwarderbot.middleware", middlewares),
    )
    failures = []
    seen = 0
    for kind, group, configured in groups:
        registered = {ep.name for ep in entry_points(group=group)}
        for item in configured:
            if not isinstance(item, str):
                failures.append(f"{kind} entry has invalid type")
                continue
            module_id = item.split("#", 1)[0]
            if module_id not in registered:
                failures.append(f"missing {kind} module: {module_id}")
            seen += 1

    if failures:
        print(f"Profile {args.profile}: {len(failures)} module check(s) failed:", file=sys.stderr)
        for issue in failures:
            print(f"  {issue}", file=sys.stderr)
        print("Install compatible middleware packages (requirements-extra.txt), then rebuild/recheck; no config data was changed.", file=sys.stderr)
        return 3

    print(f"Profile {args.profile}: {seen} configured module(s) have registered entry points")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
