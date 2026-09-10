#!/usr/bin/env python3
"""Inject required-tool failures into complete builds in isolated source copies."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'build/build-failure-controls'


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    paths = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT
    ).decode().split('\0')
    # Copy the actual working sources; no ignored binaries, runtime objects,
    # dependency caches or generated headers can satisfy the isolated build.
    selected = [p for p in paths if p and (
        p.startswith(('compiler/', 'stdlib/', 'tools/', 'examples/'))
        or p in ('build.sh', 'nurl.sh', 'CHANGELOG.md'))]
    with tempfile.TemporaryDirectory(prefix='nurl-build-fault-') as tmp:
        root = Path(tmp)
        for relative in selected:
            src, dst = ROOT / relative, root / relative
            if not src.is_file():
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        for tool, entry in [('nurlfmt', 'nurlfmt.nu'), ('nurlpkg', 'main.nu')]:
            source = root / f'tools/{tool}/{entry}'
            original = source.read_bytes()
            source.write_bytes(b'@\n')  # invalid declaration, rejected by the real compiler
            stale = root / f'build/{tool}'
            stale.parent.mkdir(exist_ok=True)
            stale.write_text('stale executable must not survive\n')
            stale.chmod(0o755)
            env = {**os.environ, 'NURL_SAN': '0'}
            run = subprocess.run(['bash', './build.sh', '--no-tests'], cwd=root, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
            (EVIDENCE / f'{tool}.log').write_bytes(run.stdout)
            source.write_bytes(original)
            if run.returncode == 0 or f'BUILD FAILED: {tool}'.encode() not in run.stdout:
                raise RuntimeError(f'{tool}: failure was not attributed to the required tool; see {EVIDENCE}')
            if stale.exists():
                raise RuntimeError(f'{tool}: failed rebuild left a stale executable')
            logs = list((root / 'build/logs').glob('build.*'))
            if not logs or not any(b'clang version' in p.read_bytes() for p in logs):
                raise RuntimeError(f'{tool}: build evidence was discarded')
            print(f'{tool}: full build failed, stale binary removed, log retained', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
