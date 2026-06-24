#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import plistlib
import re
from pathlib import Path


VERSION_KEY = "CFBundleShortVersionString"
BUILD_KEY = "CFBundleVersion"


def next_version(current: str, bump: str) -> str:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", current)
    if not match:
        raise ValueError(f"{VERSION_KEY} must be semantic version X.Y.Z, got {current!r}")

    major, minor, patch = (int(part) for part in match.groups())
    if bump == "major":
        major += 1
        minor = 0
        patch = 0
    elif bump == "minor":
        minor += 1
        patch = 0
    elif bump == "patch":
        patch += 1
    else:
        raise ValueError(f"unsupported bump type: {bump}")

    return f"{major}.{minor}.{patch}"


def next_build(current: object) -> str:
    try:
        return str(int(str(current)) + 1)
    except (TypeError, ValueError):
        return "1"


def main() -> None:
    parser = argparse.ArgumentParser(description="Bump ClipMind Info.plist version.")
    parser.add_argument("--plist", default="ClipMind/Info.plist", help="Path to Info.plist")
    parser.add_argument("--bump", choices=["major", "minor", "patch"], default="patch")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    plist_path = Path(args.plist)
    with plist_path.open("rb") as file:
        plist = plistlib.load(file)

    old_version = str(plist.get(VERSION_KEY, "0.0.0"))
    old_build = plist.get(BUILD_KEY, "0")
    version = next_version(old_version, args.bump)
    build = next_build(old_build)

    if not args.dry_run:
        plist[VERSION_KEY] = version
        plist[BUILD_KEY] = build
        with plist_path.open("wb") as file:
            plistlib.dump(plist, file, sort_keys=False)

    print(f"version={version}")
    print(f"build={build}")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as file:
            file.write(f"version={version}\n")
            file.write(f"build={build}\n")


if __name__ == "__main__":
    main()
