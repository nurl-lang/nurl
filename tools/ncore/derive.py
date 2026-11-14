# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""A library function's summary, from what the walk believes of it.

A function whose body uses raw memory has no body the checker can read.
Until its summary is declared in source (PROPOSAL_CORE_IR D2), the answers
the fused walk already holds for it (`sum` lines of `nurlc --emit-core`)
are read into the checker's form here: the same trust the compiler places
in that function today, in the engine's words.

`prims.py` wins where it declares a function: those summaries were written
against docs/MEMORY.md and the probes.  `compare()` says where the two
disagree.
"""

from lower import Types
from check import VIEW_TYPES


def _idx(ws, key, n):
    return [int(w) for w in ws.get(key, "").split() if w.isdigit() and int(w) < n]


def _rows(ws, key):
    """The words of a `:`-headed answer (`:` alone: answered, none)."""
    v = ws.get(key, "")
    return v[1:].split() if v.startswith(":") else []


def _place(w, n):
    """`k`, `^k`, `%k` -> (k, path, kind): a parameter's storage, its
    elements' storage, a copy of the views it holds."""
    kind, path = "view", ()
    if w.startswith("^"):
        w, path = w[1:], ("*",)
    elif w.startswith("%"):
        w, kind = w[1:], "held"
    if not w.isdigit() or int(w) >= n:
        return None
    return int(w), path, kind


def derive(prog, fn, ws):
    """The checker's summary of `fn` (an FnIR: params, modes, ret, vars) from
    the walk's answers `ws` (key -> words)."""
    T = Types(prog)
    n = len(fn.params)
    pty = [fn.vars[v].ty for v in fn.params]
    scalar = lambda ty: ty is not None and T.is_scalar(ty)
    ret_scalar = fn.ret is None or T.is_scalar(fn.ret)
    ret_view = fn.ret is not None and fn.ret[0] in VIEW_TYPES

    sink, keeps = set(_idx(ws, "sink", n)), set(_idx(ws, "keeps", n))
    stored, hand = set(_idx(ws, "stores", n)), set(_idx(ws, "handkeeps", n))
    consumes = {k for k in sink | {k for k in keeps if k in stored or k not in hand} if not scalar(pty[k])}
    consumes |= {k for k, m in enumerate(fn.modes) if m == "sink"}

    reallocs, mutates = set(_idx(ws, "reallocs", n)), set(_idx(ws, "mutates", n))
    effects = {(k, (), "realloc") for k in reallocs}
    # (its contents changed, its buffer where it was: what was lent out of
    # an element ends, a view of the buffer does not)
    effects |= {(k, ("*",), "replace") for k in mutates - reallocs}
    effects |= {(k, ("*",), "realloc") for k in _idx(ws, "ireallocs", n)}
    for w in ws.get("drops", "").split():
        k, _, rel = w.partition(".")
        if k.isdigit() and int(k) < n:
            effects.add((int(k), tuple(rel.split("."))[:3] if rel else (), "drop"))
    for w in ws.get("replaces", "").split():
        k, _, f = w.partition(".")
        if k.isdigit() and int(k) < n:
            effects.add((int(k), (f,) if f else (), "replace"))
    # where a value the function keeps may end up: the arguments it changes
    changed = [k for k in range(n) if (k in reallocs or k in mutates or fn.modes[k] == "inout") and not scalar(pty[k])]

    lends, rholds, stores = set(), set(), set()
    for k, c in enumerate(ws.get("lkind", "")[:n]):
        if scalar(pty[k]) or (pty[k] is not None and pty[k][0] == "closure"):
            # (a closure has no part to lend)
            continue
        if c == "1":
            lends.add((k, (), "handle"))
        elif c == "2":
            lends.add((k, ("*",), "handle"))
    for k in _idx(ws, "retptr", n):
        if not scalar(pty[k]):
            lends.add((k, (), "view"))
    for w in _rows(ws, "rviews"):
        pl = _place(w, n)
        if pl is None:
            continue
        k, path, kind = pl
        if kind == "held":
            rholds.add(((), k, (), "held"))
        elif ret_view:
            lends.add((k, path, "view"))
        else:
            rholds.add(((), k, path, "view"))
    for w in _rows(ws, "vkeeps"):
        h, _, src = w.partition(">")
        pl = _place(src, n)
        if pl is None or not h.isdigit() or int(h) >= n:
            continue
        k, path, kind = pl
        if pty[k] is not None and pty[k][0] == "closure":
            # (a closure kept is a copy: the holder holds what it holds)
            kind = "held"
        stores.add((int(h), (), k, () if kind == "held" else path, kind))
    for k in _idx(ws, "vcopies", n):
        for h in changed:
            if h != k:
                stores.add((h, (), k, (), "held"))
        if not ret_scalar:
            rholds.add(((), k, (), "held"))
    for k in sorted((keeps | set(_idx(ws, "escapes", n))) - {k for k in range(n) if scalar(pty[k])}):
        dests = [h for h in changed if h != k]
        for h in dests:
            stores.add((h, ("*",), k, (), "value"))
        if not dests and not ret_scalar and not ret_view:
            rholds.add(((), k, (), "held"))

    # What no table says: a value made from an argument, or an argument the
    # function changes, holds what the arguments hold (formal/A2's
    # `heldOfArgs`, the answer for a callee with no walk of its own).
    only_run = set(_idx(ws, "invoke_only", n))
    rv_answered = ws.get("rviews", "").startswith(":")
    for k in range(n):
        if scalar(pty[k]) or (k in only_run and pty[k] is not None and pty[k][0] == "closure"):
            # (a closure the function only runs is kept nowhere)
            continue
        if not ret_scalar and not (rv_answered and pty[k] is not None and pty[k][0] in VIEW_TYPES):
            # (an argument that is itself a view - a raw string, a slice -
            # holds nothing but that view, and which of them the result
            # views the walk has answered: `rviews`)
            rholds.add(((), k, (), "held"))
        if not ws.get("vkeeps", "").startswith(":"):
            # (…unless the walk answered what it leaves in its arguments)
            for h in changed:
                if h != k:
                    stores.add((h, (), k, (), "held"))

    invokes = {k for k in range(n) if pty[k] is not None and pty[k][0] == "closure"}
    invokes |= {k for k in _idx(ws, "hrun", n)}

    if fn.ret == ("s",) and ws.get("ret_owned"):
        # the walk knows the result for a string of its own (`ret_owned`):
        # a fresh buffer, which holds nothing of the arguments
        rholds = set()
    if not ret_scalar and not ret_view and not T.view_capable(fn.ret):
        # a result whose type has nowhere to keep a view or a borrowed
        # handle holds none, whatever the raw code's provenance reached
        lends = {l for l in lends if l[2] == "handle"}
        rholds = set()
    if ret_scalar:
        res = "none"
    elif lends:
        res = "lent"
    else:
        res = "own"
    return {"modes": list(fn.modes), "res": res, "lends": sorted(lends), "rholds": sorted(rholds),
            "effects": sorted(effects), "stores": sorted(stores), "consumes": sorted(consumes),
            "elems": [], "detaches": [], "invokes": sorted(invokes), "cloargs": [], "shares": [],
            "derived": True}


def extern(ws):
    """A function with no body in the program or the library (the runtime's,
    an extern): it keeps no argument and changes none the walk knows of;
    its result is the caller's own where the walk says so (`ret_owned`),
    and nothing to follow otherwise."""
    n = 16
    # (a foreign function writes through a pointer parameter it does not
    # declare `in`: `ffi_writes`)
    return {"modes": ["in"] * n, "res": "own" if ws.get("ret_owned") else "none", "lends": [], "rholds": [],
            "effects": [(k, (), "drop") for k in _idx(ws, "ffi_writes", n)], "stores": [],
            "consumes": sorted(_idx(ws, "sink", n)),
            "elems": [], "detaches": [], "invokes": [], "cloargs": [], "shares": [], "derived": True}


def walk_answers(prog, name):
    """The walk's answers for `name`: its own, and its template's where its
    own are silent (the walk keys some answers by either)."""
    ws = dict(prog.walk_sums.get(prog.fn_tmpl.get(name) or "", {}))
    ws.update(prog.walk_sums.get(name, {}))
    return ws


def compare(declared, derived):
    """Where a declared summary and the derived one differ: (key, declared
    only, derived only)."""
    out = []
    norm = lambda x: tuple(norm(i) for i in x) if isinstance(x, (list, tuple)) else x
    for key in ("res", "lends", "rholds", "effects", "stores", "consumes", "invokes"):
        a, b = declared.get(key, ()), derived.get(key, ())
        if key == "res":
            if a != b:
                out.append((key, a, b))
            continue
        sa, sb = set(map(norm, a)), set(map(norm, b))
        if sa != sb:
            out.append((key, sorted(sa - sb, key=repr), sorted(sb - sa, key=repr)))
    return out
