#!/usr/bin/env python3
"""Copy stdlib/nurl_detmath.h into packages/gpu/src/cpu.nu (AGORA-568).

The deterministic double functions (exp, log, pow, sin, cos, tanh, erf, ...)
live in one header. The runtime includes it (float_exp / float_log). A gpu
CPU-backend kernel is compiled on the user's host from source text that
cpu.nu carries as a NURL string, so the header's text is copied into
cpu_detmath, between two marker lines. CPU-backend kernels and the CPU tape
of packages/grad then compute e^x and ln x with the same code, bit for bit.

    python3 tools/gen_detmath.py           rewrite the copy in cpu.nu
    python3 tools/gen_detmath.py --check   exit 1 if the copy is stale (CI)
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER = os.path.join(ROOT, 'stdlib', 'nurl_detmath.h')
TARGET = os.path.join(ROOT, 'packages', 'gpu', 'src', 'cpu.nu')
BEGIN = '// ── stdlib/nurl_detmath.h, copied by tools/gen_detmath.py: edit the header, then run it ──\n'
END = '// ── end of stdlib/nurl_detmath.h ──\n'


def read(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


def render(header, target):
    # A NURL backtick string takes the text as it is, except for a backslash
    # escape and the closing backtick: the header must hold neither.
    for ch, what in (('\\', 'a backslash'), ('`', 'a backtick')):
        if ch in header:
            line = header[:header.index(ch)].count('\n') + 1
            sys.exit(f'gen_detmath: {HEADER}:{line} holds {what}, which a NURL string cannot carry as is')
    b = target.find(BEGIN)
    e = target.find(END)
    if b < 0 or e < b:
        sys.exit(f'gen_detmath: the marker lines are missing from {TARGET}')
    if not header.endswith('\n'):
        header += '\n'
    return target[:b + len(BEGIN)] + header + target[e:]


def main():
    check = '--check' in sys.argv[1:]
    header = read(HEADER)
    target = read(TARGET)
    out = render(header, target)
    if check:
        if out != target:
            sys.exit('gen_detmath: packages/gpu/src/cpu.nu holds a stale copy of stdlib/nurl_detmath.h; '
                     'run python3 tools/gen_detmath.py')
        return
    if out != target:
        with open(TARGET, 'w', encoding='utf-8', newline='') as f:
            f.write(out)
        print('gen_detmath: updated packages/gpu/src/cpu.nu')


if __name__ == '__main__':
    main()
