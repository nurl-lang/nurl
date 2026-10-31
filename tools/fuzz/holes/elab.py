#!/usr/bin/env python3
"""tools/fuzz/holes/elab.py — the elaborated twin of each hole probe.

    elab.py OUTDIR PROBE.nu...

A probe whose `^` or `=` statement takes a producer form (a value block, a
`?`, a `??`) gets a twin in which the form is bound first and the consumer
reads the binding, as the calculus has it (docs/dev/ELABORATION.md):

    ^ <form>      →   : __el <form>
                      ^ __el
    = x <form>    →   : __el <form>
                      = x __el

A value block bound that way also gets a typed twin, `: T __el { … }`, with
T the function's return type (`^`) or the target's declared type (`=`):
a typed binding of a value block is elaborated by the compiler (#222 stage
1: the binding first, the block's tail assigned to it before the block's
names end), an untyped one is not. Typed twins are written under `typed/`.

The twin must be no hole either: check.sh runs every twin after the probes
(Agora #242). A twin that faults is a gap in the let-then-name path, the
path every consumer will go through once producers are elaborated (#222).

Twins known to fault are listed in open/twins.txt, one probe per line with
the reason (`typed/<probe>` for a typed twin); they are not written, and are
reported as open.

The twins are written to OUTDIR at the probe's path (a probe under
`stdlib/` keeps that directory) and their paths, relative to OUTDIR, are
printed one per line. A statement the small prefix parser below cannot
delimit is left alone: the twin covers what it can parse, nothing else.
"""
import os
import re
import sys

TOKEN = re.compile(r'`[^`]*`|//[^\n]*|\s+|[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*'
                   r'|-?\d+(?:\.\d+)?[a-z0-9]*|→|==|!=|<=|>=|<<|>>|\?\?|.')
BINARY = {'+', '-', '*', '/', '%', '==', '!=', '<', '>', '<=', '>=', '&', '|', '<<', '>>'}
UNARY = {'!'}
STATEMENT = re.compile(r'(?m)^([ \t]*)(\^|= ([A-Za-z_]\w*)) (?=\{|\?)')


class NoParse(Exception):
    pass


def tokens(text):
    out = []
    for m in TOKEN.finditer(text):
        s = m.group(0)
        if s.isspace() or s.startswith('//'):
            continue
        out.append((s, m.start(), m.end()))
    return out


def group(toks, i, opening, closing):
    depth = 0
    while i < len(toks):
        if toks[i][0] == opening:
            depth += 1
        elif toks[i][0] == closing:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise NoParse


def expr(toks, i):
    """The index just past the prefix expression starting at token i."""
    if i >= len(toks):
        raise NoParse
    s = toks[i][0]
    if s == '(':
        return group(toks, i, '(', ')')
    if s == '[':
        return group(toks, i, '[', ']')
    if s == '{':
        return group(toks, i, '{', '}')
    if s in BINARY:
        return expr(toks, expr(toks, i + 1))
    if s in UNARY:
        return expr(toks, i + 1)
    if s == '.':
        j = expr(toks, i + 1)
        if j < len(toks) and re.match(r'[A-Za-z_]\w*$|\d+$', toks[j][0]):
            return j + 1
        raise NoParse
    if s == '?':
        return expr(toks, expr(toks, expr(toks, i + 1)))
    if s == '??':
        j = expr(toks, i + 1)
        if j < len(toks) and toks[j][0] == '{':
            return group(toks, j, '{', '}')
        raise NoParse
    if s.startswith('`') or re.match(r'-?\d', s) or re.match(r'[A-Za-z_]', s):
        return i + 1
    raise NoParse


FN_HEAD = re.compile(r'(?m)^[ \t]*(?:unsafe[ \t]+)?@[ \t]+[A-Za-z_]\w*[^\n]*?→[ \t]*(.+?)[ \t]*\{[ \t]*$')
SCALARS = {'v', 'i', 'b', 'f', 'u', 'u8', 'i8', 'i16', 'i32', 'i64', 'u16', 'u32', 'u64', 'f32', 'f64', 's'}


def declared_type(text, at, consumer, target):
    """The type a typed twin binds `__el` as: the enclosing function's
    return type for `^`, the target's declared type for `= x`; None when it
    is not found or holds nothing to drop."""
    head = text[:at]
    if consumer == '^':
        fns = list(FN_HEAD.finditer(head))
        ty = fns[-1].group(1) if fns else None
    else:
        decls = list(re.finditer(r'(?m)^[ \t]*:[ \t]+~[ \t]+(.+?)[ \t]+' + re.escape(target) + r'[ \t]', head))
        ty = decls[-1].group(1) if decls else None
    if ty is None or ty in SCALARS:
        return None
    return ty


def twin(text, typed=False):
    """The elaborated text, or None when no statement was rewritten.
    `typed`: only value blocks, bound with their type (`: T __el { … }`)."""
    toks = tokens(text)
    at = {start: k for k, (_, start, _) in enumerate(toks)}
    out, pos, changed = [], 0, 0
    for m in STATEMENT.finditer(text):
        if m.start() < pos or m.end() not in at:
            continue
        indent, consumer, target = m.group(1), m.group(2), m.group(3)
        ty = ''
        if typed:
            if text[m.end()] != '{':
                continue
            ty = declared_type(text, m.start(), consumer, target)
            if ty is None:
                continue
            ty += ' '
        try:
            end = toks[expr(toks, at[m.end()]) - 1][2]
        except NoParse:
            continue
        use = '^ __el' if consumer == '^' else f'= {target} __el'
        out.append(text[pos:m.start()])
        out.append(f'{indent}: {ty}__el {text[m.end():end]}\n{indent}{use}')
        pos, changed = end, changed + 1
    if not changed:
        return None
    out.append(text[pos:])
    return ''.join(out)


def known_open(here):
    path = os.path.join(here, 'open', 'twins.txt')
    names = set()
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#'):
                names.add(line.split()[0])
    return names


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    outdir, probes = argv[1], argv[2:]
    skip = known_open(here)
    for probe in probes:
        text = open(os.path.join(here, probe), encoding='utf-8').read()
        for name, typed in ((probe, False), (os.path.join('typed', probe), True)):
            if name in skip:
                continue
            t = twin(text, typed)
            if t is None:
                continue
            dest = os.path.join(outdir, name)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, 'w', encoding='utf-8') as f:
                f.write(t)
            print(name)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
