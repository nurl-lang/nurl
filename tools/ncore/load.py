# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Load a probe with its imports: the probe's own declarations are parsed in
full; an imported standard-library file contributes only its type names and
the function headers the prototype has a declared summary for (prims.py), so
the stdlib's unsafe bodies are never read as program code."""
import os
from syntax import lex, Parser, scan_type_names, Unsupported, ParseError

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

ALLOWED_IMPORTS = {
    "stdlib/core/string.nu", "stdlib/core/vec.nu", "stdlib/core/slice.nu",
    "stdlib/core/option.nu", "stdlib/core/io.nu", "stdlib/core/box.nu",
}

_cache = {}


def stdlib_types(path):
    if path in _cache:
        return _cache[path]
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        toks = lex(f.read())
    names, gen = scan_type_names(toks)
    _cache[path] = (names, gen)
    return names, gen


def load(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    toks = lex(src)
    names, gen = scan_type_names(toks)
    imports = []
    for i, (t, k, _) in enumerate(toks):
        if t == "$" and k == "op" and toks[i + 1][1] == "str":
            imp = toks[i + 1][0]
            if not imp.endswith(".nu"):
                imp += ".nu"
            imports.append(imp)
    for imp in imports:
        if imp not in ALLOWED_IMPORTS:
            raise Unsupported(f"import {imp}")
        n2, g2 = stdlib_types(imp)
        names |= n2
        gen |= g2
    names |= {"String", "Vec", "Slice", "Box"}
    p = Parser(toks, names, gen)
    decls = p.parse_program()
    return decls, imports


HEADER_FILES = ["stdlib/core/builtins.nu"] + sorted(ALLOWED_IMPORTS)
_headers = None


def _parse_header(p, ffi=False):
    """At an `@`: name, type params, params, return type (bodies skipped)."""
    p.expect("@")
    name = p.next()[0]
    tparams = []
    if p.at("["):
        p.next()
        while not p.at("]"):
            tparams.append(p.next()[0])
            while p.at(":"):
                p.next()
                p.next()
        p.next()
    saved = p.type_names
    p.type_names = set(saved) | set(tparams)
    params = []
    while not p.at("→"):
        conv = "in"
        while p.tok() in ("in", "inout", "sink", "sync", "nocapture") and p.kind() == "id" and not p.at("→"):
            w = p.next()[0]
            if w in ("inout", "sink"):
                conv = w
        if p.tok() == "...":
            p.next()
            continue
        ty = p.parse_type()
        pname = "_"
        if not ffi:
            pname = p.next()[0]
        elif p.kind() == "id" and not p.is_type_start() and p.tok() not in ("in", "inout", "sink"):
            pname = p.next()[0]
        if p.at("="):
            p.next()
            p.next()
        params.append((conv, ty, pname))
    p.expect("→")
    if p.tok() == "sink" and p.kind() == "id":
        p.next()
    ret = p.parse_type()
    p.type_names = saved
    return name, (tparams, params, ret)


def lib_headers():
    global _headers
    if _headers is not None:
        return _headers
    out = {}
    names = {"String", "Vec", "Slice", "Box"}
    toks_by_file = {}
    for path in HEADER_FILES:
        with open(os.path.join(ROOT, path), encoding="utf-8") as f:
            toks = lex(f.read())
        toks_by_file[path] = toks
        n, g = scan_type_names(toks)
        names |= n
    for path, toks in toks_by_file.items():
        depth = 0
        for i, (t, k, _) in enumerate(toks):
            if k == "op" and t == "{":
                depth += 1
            elif k == "op" and t == "}":
                depth -= 1
            elif depth == 0 and k == "op" and t == "@":
                p = Parser(toks, names)
                p.p = i
                try:
                    ffi = i >= 2 and toks[i - 2][0] == "&"
                    name, hdr = _parse_header(p, ffi)
                except (Unsupported, ParseError, IndexError):
                    continue
                out.setdefault(name, hdr)
    _headers = out
    return out
