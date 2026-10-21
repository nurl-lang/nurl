#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_package_imports.sh — assert that a package's imports
#  resolve the same way once it is installed from the registry:
#
#   1. no package imports itself through a `packages/<name>/…` path;
#   2. every `deps/<name>/…` a packaged source imports names a package
#      declared in that package's [dependencies];
#   3. every other import of a packaged source (not `stdlib/…`, `deps/…`
#      or `packages/…`) names a file that exists relative to the
#      IMPORTING file.
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
#  Rule 3 is the same trap one directory down. nurlc resolves an import
#  relative to the importing file first, then the working directory
#  (spec §3.2), so `$ \`src/store.nu\`` written in src/service.nu misses
#  src/src/store.nu and finds the file through the cwd — which is the
#  package root in every in-repo build, and the CONSUMER's root once the
#  package is installed under deps/<pkg>/. Sixteen packages shipped that
#  way (anomaly's documented `$ \`deps/anomaly/src/dynamic.nu\`` among
#  them); a sibling is written `store.nu`, which resolves in both.
#
#  Rule 2 is the publish gate's (`nurlpkg publish` refuses "deps/<x>/… is
#  imported, but '<x>' is missing from nurl.toml"), run on every change
#  instead of at publication: deps/ is a local artefact, so an undeclared
#  dependency compiles in the repo, where the symlink exists, and fails
#  for every registry install. objdet 0.4.4 imported deps/gpu without
#  declaring it, passed CI, and was found only by the gate in the middle
#  of the 0.73.0 package sweep. The gate reads src/; this reads every
#  packaged source (src/** and the package root's *.nu), the same import
#  shape (a `$` that starts the line — a header comment documenting
#  `$ \`deps/http/src/http.nu\`` is not an import).
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
import tomllib

artifacts = {'deps', 'build', 'target', 'node_modules', 'vendor', '.git', '.nurl-bin'}
packages = Path('packages')
pattern = re.compile(rb'^\s*\$[ \t]*`packages/')
dep_import = re.compile(rb'^[ \t]*\$[ \t]*`deps/([^/`\r\n]+)/')
any_import = re.compile(rb'^[ \t]*\$[ \t]*`([^`\r\n]+)`')
rooted = (b'stdlib/', b'deps/', b'packages/')


def resolves_beside(path, target):
    # The importer-relative tier of nurlc's lookup, with its `.nu` retry.
    here = path.parent / os.fsdecode(target)
    return here.exists() or here.with_name(here.name + '.nu').exists()


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


def packaged(path):
    # What the packer ships as source: src/** and the package root's *.nu.
    rest = path.parts[2:]
    return len(rest) == 1 or (len(rest) > 1 and rest[0] == 'src')


def declared_dependencies(package, cache):
    if package not in cache:
        manifest = packages / package / 'nurl.toml'
        try:
            with manifest.open('rb') as source:
                cache[package] = set(tomllib.load(source).get('dependencies', {}))
        except FileNotFoundError:
            cache[package] = None  # not a package: nothing is published from it
        except (OSError, tomllib.TOMLDecodeError) as error:
            fail(f'cannot read {manifest}: {error}')
    return cache[package]


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
    undeclared = []
    cwd_only = []
    manifests = {}
    for path in sources:
        ships = packaged(path)
        with path.open('rb') as source:
            for line_number, line in enumerate(source, 1):
                text = None
                if pattern.match(line):
                    text = line.rstrip(b'\r\n').decode('utf-8', errors='replace')
                    hits.append(f'{path}:{line_number}: {text}')
                other = any_import.match(line) if ships else None
                if (other and not other.group(1).startswith(rooted)
                        and not resolves_beside(path, other.group(1))):
                    text = text or line.rstrip(b'\r\n').decode('utf-8', errors='replace')
                    cwd_only.append(f'{path}:{line_number}: {text}')
                dep = dep_import.match(line) if ships else None
                if dep:
                    name = dep.group(1).decode('utf-8', errors='replace')
                    declared = declared_dependencies(path.parts[1], manifests)
                    if declared is not None and name not in declared:
                        text = text or line.rstrip(b'\r\n').decode('utf-8', errors='replace')
                        undeclared.append(f'{path}:{line_number}: {text}'
                                          f"   ('{name}' is not in packages/{path.parts[1]}/nurl.toml)")
except OSError as error:
    fail(f'cannot enumerate or read package sources: {error}')

if hits:
    print("package sources may not import through a 'packages/…' path:", file=sys.stderr)
    print('(inside the repo it resolves; installed under deps/ it does not)\n', file=sys.stderr)
    for hit in hits:
        print('  ' + hit, file=sys.stderr)
    print("\nimport a sibling by a relative path and a dependency through 'deps/<pkg>/src/…'.",
          file=sys.stderr)
if undeclared:
    if hits:
        print(file=sys.stderr)
    print('packaged sources import a package their manifest does not declare:', file=sys.stderr)
    print('(deps/ is a local artefact: it compiles here and fails for every registry install;',
          file=sys.stderr)
    print(' `nurlpkg publish` refuses it)\n', file=sys.stderr)
    for hit in undeclared:
        print('  ' + hit, file=sys.stderr)
    print('\nadd each one to [dependencies], with the version requirement the import needs.',
          file=sys.stderr)
if cwd_only:
    if hits or undeclared:
        print(file=sys.stderr)
    print('packaged sources import a file that does not exist beside the importer:',
          file=sys.stderr)
    print('(nurlc then tries the working directory: the package root here, the consumer\'s',
          file=sys.stderr)
    print(' root once installed under deps/<pkg>/, where it is not found)\n', file=sys.stderr)
    for hit in cwd_only:
        print('  ' + hit, file=sys.stderr)
    print("\nwrite the path relative to the importing file: a sibling in src/ is `name.nu`,"
          " not `src/name.nu`.", file=sys.stderr)
if hits or undeclared or cwd_only:
    raise SystemExit(1)

count = len({path.parts[1] for path in sources if len(path.parts) > 2})
print(f'package imports OK ({count} packages, {len(sources)} source files, '
      "no 'packages/…' self-imports, every deps/ import declared, "
      'every sibling import relative to its importer)')
PYTHON
