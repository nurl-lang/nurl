#!/usr/bin/env python3
"""tvir.py prog.core prog.g.ll: formal phase D0b (AGORA-985), the core IR's
side of the drop validation. It prints, one per line, the LLVM slots of
named bindings the core IR never moves: `<llvm function> <slot> <name>`;
and (D0d, AGORA-992) each temporary it never moves that a call's result
is, by that call: `<llvm function> call:<callee>:<k>:<n> v<id>`, the k-th
of the function's n calls to the callee.

`tvdrops.py --protect FILE` then asks of each such slot that its flag is
never cleared while it owns a value: what the IR keeps to its scope end, the
LLVM releases there (by `__dropif`), and does not hand on.

A binding counts as one the IR may move (and is left out) where it is
- `use vK`, a value handed to a new holder (CORE_IR.md §2);
- an operand of `agg` or `closure` (a literal it moves into);
- `ret vK`;
- an argument of a call at a `sink=` or `keeps=` index of the callee's `sum`
  line, or the operand of `mem_forget` (the binding it gives up), or of
  a call through a closure (`callind`), or of a construct the walk did not
  lower (`opaque`).
Only bindings (`v` kind 1) of a type with something to release (`ty`'s
drops `1`) are listed. The slot is found by name and line from the `--g`
build's `llvm.dbg.declare`: its allocas are the plain build's (same names),
so the slot names carry over; a binding with no unique match is left out.
"""
import re
import sys


# intrinsics that consume an operand, as nurlc's IR names it (AGORA-989:
# `call mem_forget 1 vK`, the binding given up)
CONSUMES = {"mem_forget": {0}}


def ir_protected(core):
    drops, sinks, out = set(), {k: set(v) for k, v in CONSUMES.items()}, []
    for raw in core.splitlines():
        f = raw.split("\t")
        if f[0] == "ty" and len(f) > 3 and f[3][:1] == "1":
            drops.add(f[1])
        elif f[0] == "sum":
            for kv in f[3:]:
                # a `sink` parameter takes the value; one the callee `keeps`
                # (stores where it outlives the call) is handed over too
                for key in ("sink=", "keeps="):
                    if kv.startswith(key):
                        sinks.setdefault(f[1], set()).update(
                            int(x) for x in kv[len(key):].split() if x.isdigit())
    cur = None
    for raw in core.splitlines():
        f = raw.split("\t")
        if f[0] == "fn":
            cur = {"name": f[1], "vars": {}, "body": []}
        elif f[0] == "v" and cur is not None:
            cur["vars"][int(f[1])] = (int(f[2]), f[7], int(f[5]), f[-1])
        elif f[0] == "endfn" and cur is not None:
            out.append(cur)
            cur = None
        elif cur is not None:
            cur["body"].append(raw.strip())
    res = []
    for fn in out:
        moved = set()
        # (D0d: where each move is - the arms of the `if`s around it, the
        # outermost first, as (if number, "t" / "e"); a move outside every
        # `if` has none)
        where, stack, nif = {}, [], 0
        for l in fn["body"]:
            w = l.split()
            if w[:1] == ["if"]:
                nif += 1
                stack.append(["if", nif, "t"])
            elif w[:1] == ["else"] and stack and stack[-1][0] == "if":
                stack[-1][2] = "e"
            elif w[:1] in (["scope"], ["loop"]):
                stack.append([w[0]])
            elif w[:1] == ["end"] and stack:
                stack.pop()
            ctx = tuple((b[1], b[2]) for b in stack if b[0] == "if")
            lm = set()   # (what this line moves)
            ops = [t.split("/")[0] for t in w]
            # (a `use` into a `void` holder, an `if`'s value no one takes,
            # moves nothing)
            dest = w[1] if len(w) > 1 and w[0] in ("let", "assign") else None
            dvoid = dest is not None and fn["vars"].get(int(dest.lstrip("v")) if dest.lstrip("v").isdigit() else -1,
                                                       (0, "", 0, ""))[3] == "void"
            for k, t in enumerate(w):
                if t in ("use", "ret") and k + 1 < len(w) and not (t == "use" and dvoid):
                    lm.add(w[k + 1].split("/")[0])
            if ("agg" in w or "closure" in w or "callind" in w or "opaque" in w):
                lm.update(o for o in ops if o.startswith("v"))
            if "call" in w:
                k = w.index("call")
                callee = w[k + 1] if k + 1 < len(w) else ""
                args = w[k + 3:] if k + 2 < len(w) else []
                for i in sinks.get(callee, ()):
                    if i < len(args):
                        lm.add(args[i].split("/")[0])
            moved |= lm
            for o in lm:
                where.setdefault(o, set()).add(ctx)
        for vid, (kind, name, line, ty) in fn["vars"].items():
            if kind == 1 and name and ty in drops and f"v{vid}" not in moved:
                res.append((fn["name"], name, line))
            # D0d (AGORA-992): a binding the IR moves on one arm of an `if`
            # only - every move inside that arm, the outermost `if` around
            # all of them: the LLVM hands it on in that arm's blocks only
            ws = where.get(f"v{vid}")
            if kind == 1 and name and ty in drops and ws and all(ws):
                tops = {c[0] for c in ws}
                if len(tops) == 1:
                    (i, arm), = tops
                    res.append((fn["name"], name, line, f"arm:{i}:{nif}:{arm}"))
        # D0d (AGORA-992): a temporary - an unnamed value, no binding - of a
        # dropping type the IR never moves, bound straight from a call
        # (`let N call F …`): its value is the result of that call, the
        # k-th of the function's calls to F. The LLVM's k-th call to F is
        # the same one where both have as many (tvdrops.py checks the
        # count), and its result is not handed on.
        calls, temps = {}, []
        for l in fn["body"]:
            w = l.split()
            for k, t in enumerate(w):
                if t == "call" and k + 1 < len(w):
                    f = w[k + 1]
                    calls[f] = calls.get(f, 0) + 1
                    if k == 2 and w[0] == "let" and w[1].isdigit():
                        temps.append((int(w[1]), f, calls[f]))
        for vid, f, k in temps:
            kind, name, line, ty = fn["vars"].get(vid, (0, "", 0, ""))
            if kind != 1 and not name and ty in drops and f"v{vid}" not in moved:
                res.append((fn["name"], f"call:{f}:{k}:{calls[f]}", f"v{vid}"))
    return res


def dbg_slots(ll):
    """(llvm function, variable name, line) → slot, from `llvm.dbg.declare`."""
    meta = {}
    for m in re.finditer(r'^(![0-9]+) = !DILocalVariable\(name: "([^"]*)",[^\n]*?line: ([0-9]+)', ll, re.M):
        meta[m.group(1)] = (m.group(2), int(m.group(3)))
    slots, cur = {}, None
    for line in ll.splitlines():
        m = re.match(r"^define [^@]*@([^\s(]+)\(", line)
        if m:
            cur = m.group(1)
            continue
        m = re.search(r"llvm\.dbg\.declare\(metadata [^,]* (%[\w.]+), metadata (![0-9]+)", line)
        if m and cur and m.group(2) in meta:
            key = (cur,) + meta[m.group(2)]
            slots.setdefault(key, set()).add(m.group(1))
    return slots


def main():
    core, ll = open(sys.argv[1]).read(), open(sys.argv[2]).read()
    slots = dbg_slots(ll)
    for fname, name, line, *arm in ir_protected(core):
        llname = "_nurl_main" if fname == "main" else "__nurl_fn." + fname
        if name.startswith("call:"):
            # (a temporary: found by its call in the plain build, tvdrops.py)
            print(llname, name, line)
            continue
        # by name in the function; the line only breaks a tie (the debug
        # line may be the IR's or one more)
        cands = {k: v for k, v in slots.items() if k[0] == llname and k[1] == name}
        if len(cands) > 1:
            cands = {k: v for k, v in cands.items() if k[2] in (line, line + 1)}
        if len(cands) == 1:
            s = next(iter(cands.values()))
            if len(s) == 1:
                print(llname, next(iter(s)), name, *arm)


if __name__ == "__main__":
    main()
