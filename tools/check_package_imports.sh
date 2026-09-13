#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_package_imports.sh — assert that no package imports
#  itself through a `packages/<name>/…` path.
#
#  Inside this repo every build runs from the repo root, so
#  `$ \`packages/torchpt/src/pickle.nu\`` resolves and every test
#  passes. Installed from the registry the package lands under
#  `deps/<name>/src/`, that path does not exist, and the FIRST thing a
#  consumer sees is:
#
#      nurlc: cannot open 'packages/torchpt/src/pickle.nu'
#
#  torchpt 0.1.0 shipped that way and was uninstallable from the day it
#  was published — no in-repo test can catch it, because in the repo it
#  works. A sibling module is imported by bare filename (`\`pickle.nu\``),
#  which resolves relative to the importing file and is therefore
#  correct in both layouts; a DEPENDENCY is imported through
#  `deps/<pkg>/src/…`, which nurlpkg symlinks in both layouts too.
#
#  Run from the repo root:  ./tools/check_package_imports.sh
# ============================================================
set -eu
cd "$(dirname "$0")/.."

# Git's inventory includes tracked and untracked development sources while
# respecting ignore files. Exported source trees have no index, so walk them
# directly, always pruning dependency/vendor and generated-output directories.
# Python handles NUL-separated paths and I/O errors without shell glob limits.
exec python3 - <<'PYTHON'
from pathlib import Path
import os
import re
import stat
import subprocess
import sys

artifacts = {'deps', 'build', 'target', 'node_modules', 'vendor', '.git', '.nurl-bin'}
packages = Path('packages')
pattern = re.compile(rb'^\s*\$[ \t]*`packages/')


def fail(message):
    print(f'package import check: {message}', file=sys.stderr)
    raise SystemExit(1)


def git_inventory():
    try:
        probe = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        if Path('.git').exists():
            fail('git is required to enumerate repository ignore rules')
        return None
    except OSError as error:
        fail(f'cannot invoke git: {error}')
    if probe.returncode:
        if Path('.git').exists():
            fail('cannot enumerate repository: ' + os.fsdecode(probe.stderr).strip())
        return None
    # An exported directory may happen to be inside an unrelated Git checkout.
    if Path(os.fsdecode(probe.stdout).strip()).resolve() != Path.cwd():
        return None
    result = subprocess.run(['git', 'ls-files', '--cached', '--others',
                             '--exclude-standard', '-z', '--', 'packages'],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode or result.stderr:
        fail('cannot enumerate package sources: ' + os.fsdecode(result.stderr).strip())
    return {Path(os.fsdecode(path)) for path in result.stdout.split(b'\0') if path}


def exported_inventory():
    files = set()
    pending = [packages]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.name in artifacts:
                    continue
                if entry.is_dir(follow_symlinks=False):
                    pending.append(Path(entry.path))
                elif entry.name.endswith('.nu'):
                    files.add(Path(entry.path))
    return files


try:
    if not packages.is_dir():
        fail('packages directory is missing or unreadable')
    inventory = git_inventory()
    if inventory is None:
        inventory = exported_inventory()
    sources = []
    for path in sorted(inventory):
        if path.suffix != '.nu' or any(part in artifacts for part in path.parts[1:]):
            continue
        try:
            info = path.stat()
        except FileNotFoundError:
            # A tracked file deleted in the working tree is no longer source.
            # Dangling source symlinks, however, are read failures.
            if path.is_symlink():
                raise
            continue
        if not stat.S_ISREG(info.st_mode):
            fail(f'expected a regular source file: {path}')
        sources.append(path)
    hits = []
    for path in sources:
        with path.open('rb') as source:
            for line_number, line in enumerate(source, 1):
                if pattern.match(line):
                    text = line.rstrip(b'\r\n').decode('utf-8', errors='replace')
                    hits.append(f'{path}:{line_number}: {text}')
except OSError as error:
    fail(f'cannot enumerate or read package sources: {error}')

if hits:
    print("package sources may not import through a 'packages/…' path:", file=sys.stderr)
    print('(inside the repo it resolves; installed under deps/ it does not)\n', file=sys.stderr)
    for hit in hits:
        print('  ' + hit, file=sys.stderr)
    print("\nimport a sibling by a relative path and a dependency through 'deps/<pkg>/src/…'.",
          file=sys.stderr)
    raise SystemExit(1)

count = len({path.parts[1] for path in sources if len(path.parts) > 2})
print(f"package imports OK ({count} packages, {len(sources)} source files, no 'packages/…' self-imports)")
PYTHON
