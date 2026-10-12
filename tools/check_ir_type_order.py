#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""A named type is defined before it is used as a parameter.

LLVM up to 18 resolves a forward reference to a named struct anywhere in a
module. LLVM 23 reads a parameter type with no body yet -- of a function
type inside another type's body, of a `define`, a `declare` or a `call` --
as an opaque struct and rejects the module ("invalid type for function
argument"). nurlc's writer moves every type definition to the top of the
module, each after the types its body names (__types_first); this check
holds that on IR the compiler emitted.

A pointer to a type (`%T*`) needs no body and is not checked, and a type
naming itself through a parameter of its own body is reported (LLVM 23
cannot read that either).

Usage: check_ir_type_order.py FILE.ll...   (exit 1 on the first offender
per file, listing them all)
"""
import re
import sys

TYPE_DEF = re.compile(r"^(%[A-Za-z0-9_.$-]+) = type ")
NAME = re.compile(r"%[A-Za-z0-9_.$-]+")


def param_lists(text):
    """Every parenthesised list in `text`, innermost ones included:
    function-type parameters and call / define / declare arguments."""
    out = []
    start = []
    for i, c in enumerate(text):
        if c == "(":
            start.append(i + 1)
        elif c == ")" and start:
            out.append(text[start.pop():i])
    return out


def split_items(params):
    """The comma-separated items of one list, nested brackets kept whole."""
    items, depth, cur = [], 0, []
    for c in params:
        if c in "({[<":
            depth += 1
        elif c in ")}]>":
            depth -= 1
        if c == "," and depth == 0:
            items.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    items.append("".join(cur))
    return [x.strip() for x in items if x.strip()]


def by_value_names(item):
    """Named types an item passes by value: its leading type when that is
    a `%T` not followed by `*` (pointer) or `(` (a function type's return
    type, whose parameters are a list of their own), and the by-value
    names inside a leading literal struct or array."""
    if item.startswith("%"):
        m = NAME.match(item)
        rest = item[m.end():].lstrip()
        if rest.startswith("*") or rest.startswith("("):
            return []
        return [m.group(0)]
    if item[:1] in "{[<":
        depth = 0
        for i, c in enumerate(item):
            if c in "{[<(":
                depth += 1
            elif c in "}]>)":
                depth -= 1
                if depth == 0:
                    inner = item[1:i]
                    names = []
                    for sub in split_items(inner):
                        # `[4 x %T]` / `<2 x %T>`: the element type.
                        sub = re.sub(r"^\d+\s+x\s+", "", sub)
                        names += by_value_names(sub)
                    return names
        return []
    return []


def check(path):
    defined = set()
    bad = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for no, line in enumerate(fh, 1):
            m = TYPE_DEF.match(line)
            if m:
                name = m.group(1)
                body = line[m.end():]
                for params in param_lists(body):
                    for item in split_items(params):
                        for t in by_value_names(item):
                            if t not in defined:
                                bad.append((no, t, line.strip()[:120]))
                defined.add(name)
                continue
            s = line.lstrip()
            if not (s.startswith("define ") or s.startswith("declare ")
                    or " call " in line or s.startswith("call ")):
                continue
            for params in param_lists(line):
                for item in split_items(params):
                    for t in by_value_names(item):
                        if t not in defined:
                            bad.append((no, t, line.strip()[:120]))
    return bad


def main(argv):
    rc = 0
    for path in argv[1:]:
        bad = check(path)
        for no, t, text in bad:
            print(f"{path}:{no}: {t} used as a parameter before its definition: {text}")
        if bad:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
