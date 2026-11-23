#!/usr/bin/env python3
"""tvdrops.py prog.ll: formal phase D0 (AGORA-981), translation validation of
the drops nurlc's code generation inserts.

nurlc releases an owned value through its slot's drop flag: a slot (an
`alloca` of an owning type) is paired with an `i1` flag, and
`__dropif_T(i1 flag, ptr slot)` releases the slot's value when the flag is
set (docs/MEMORY.md §2.4). Codegen sets the flag where it stores a value
the slot owns and clears it where the value moves out.

What is checked, on every path through each function of the program (a
loop's body taken at most twice): every value a slot comes to own is
released or moved exactly once.

- a store into the slot: the slot must not own a value then (the one it
  holds would leak, never released);
- `store i1 1, flag`: the slot owns the value it holds;
- `store i1 0, flag`: the slot's value moves out (or there is none).
- `__dropif_T(flag, slot)` with the flag set: the slot must own a value (else
  it would be released twice), which is released.
- `ret`: no slot owns a value (it would leak).

A function whose drops depend on an answer the analysis does not follow
(the per-call ownership answers: `__nurl_clear_if`, `__nurl_hown*`, a flag
loaded from memory it does not own, a flag computed) is reported
`unsupported`, never guessed.

Prints one line per program: `validated: N functions`, or the first
`mismatch: <fn> <slot> <what> <path>`, or `unsupported: …` with the
count of functions validated before it.
"""
import re
import sys

DEF = re.compile(r"^define [^@]*@([^\s(]+)\(")
LABEL = re.compile(r"^([A-Za-z0-9_.$-]+):")
STORE_FLAG = re.compile(r"^\s*store i1 (true|false|1|0), i1\* (%[\w.]+)")
STORE_FLAG_PTR = re.compile(r"^\s*store i1 (true|false|1|0), ptr (%[\w.]+)")
STORE_I1_VAR = re.compile(r"^\s*store i1 (%[\w.]+), (?:i1\*|ptr) (%[\w.]+)")
LOAD_FLAG = re.compile(r"^\s*(%[\w.]+) = load i1, (?:i1\*|ptr) (%[\w.]+)")
DROPIF = re.compile(r"call void @__dropif(?:v)?_[\w.]+\(i1 (%[\w.]+|true|false|1|0), (?:ptr|[^,]+\*) (%[\w.]+)\)")
BR_COND = re.compile(r"^\s*br i1 ([^,]+), label %([\w.]+), label %([\w.]+)")
BR = re.compile(r"^\s*br label %([\w.]+)")
RET = re.compile(r"^\s*ret\b")
LOAD_VAL = re.compile(r"^\s*(%[\w.]+) = load ([^,]+), (?:ptr|[^,]+\*) (%[\w.]+)")
CLONEIF = re.compile(r"^\s*(%[\w.]+) = call [^@]*@__nurl_cloneif_[\w.]+\(i1 [^,]+, [^,]* (%[\w.]+)\)")
RET_VAL = re.compile(r"^\s*ret \S.* (%[\w.]+)\s*$")
SWITCH = re.compile(r"^\s*switch\b")
STORE_ANY = re.compile(r"^\s*store .*, (?:ptr|[^,]+\*) (%[\w.]+)(?:, align \d+)?$")
UNTRACKED = ("__nurl_clear_if", "__nurl_hown", "__nurl_set_if", "invoke ", "indirectbr", "resume ")


class Unsupported(Exception):
    pass


def functions(text):
    """name -> list of (label, [lines]) blocks."""
    out, cur, blocks = {}, None, None
    for raw in text.splitlines():
        m = DEF.match(raw)
        if m:
            cur, blocks = m.group(1), [("entry", [])]
            continue
        if cur is None:
            continue
        if raw.startswith("}"):
            out[cur] = blocks
            cur = None
            continue
        line = raw.split(";", 1)[0].rstrip()
        if not line.strip():
            continue
        m = LABEL.match(line)
        if m and not line.startswith(" "):
            blocks.append((m.group(1), []))
            continue
        blocks[-1][1].append(line)
    return out


def check_function(name, blocks):
    """None if validated, else a mismatch string. Raises Unsupported."""
    body = {lab: lines for lab, lines in blocks}
    # the flags: what `__dropif` reads, through a load of an i1 slot, for a
    # slot of this function's own frame (an `alloca`): a slot reached through
    # a pointer (a closure's capture by pointer, an `inout` parameter) is
    # another frame's, whose own check covers it
    local = set()
    for _, lines in blocks:
        for l in lines:
            mm = re.match(r"^\s*(%[\w.]+) = alloca\b", l)
            if mm:
                local.add(mm.group(1))
    loads, pairs = {}, {}
    for _, lines in blocks:
        for l in lines:
            m = LOAD_FLAG.match(l)
            if m:
                loads[m.group(1)] = m.group(2)
    for _, lines in blocks:
        for l in lines:
            m = DROPIF.search(l)
            if m:
                fv, slot = m.group(1), m.group(2)
                if fv not in loads:
                    raise Unsupported(f"{name}: a drop flag not loaded from a flag slot ({fv})")
                if slot not in local or loads[fv] not in local:
                    continue
                pairs.setdefault(loads[fv], set()).add(slot)
    if not pairs:
        return None
    for _, lines in blocks:
        for l in lines:
            if any(u in l for u in UNTRACKED):
                raise Unsupported(f"{name}: a drop decided at run time ({l.strip()[:60]})")
            if SWITCH.match(l):
                raise Unsupported(f"{name}: a switch")
            m = STORE_I1_VAR.match(l)
            if m and m.group(2) in pairs and loads.get(m.group(1)) not in pairs:
                raise Unsupported(f"{name}: a drop flag given a computed value")
    for flag, slots in pairs.items():
        if len(slots) != 1:
            raise Unsupported(f"{name}: flag {flag} guards several slots")
    flags = set(pairs)
    slot_flag = {next(iter(v)): f for f, v in pairs.items()}

    # paths: depth-first over the blocks, each block entered at most 3 times
    # on one path (a loop's body twice). The state: each slot's value (an
    # id: a store into the slot makes a new one, a flag moved from another
    # slot brings that slot's), each flag, and the values released.
    import itertools
    fresh = itertools.count(1)

    def run(lab, st, visits, path):
        visits = dict(visits)
        visits[lab] = visits.get(lab, 0) + 1
        if visits[lab] > 3:
            return None
        path = path + [lab]
        flag_v, val, released = dict(st[0]), dict(st[1]), set(st[2])

        regv = {}   # an i1 register's value, as its load read it
        regslot = {}   # a register holding a slot's value (its load, a cloneif of it)

        def owned(f):
            return flag_v.get(f) and val.get(f) is not None and val[f] not in released

        for l in body.get(lab, []):
            m = LOAD_FLAG.match(l)
            if m:
                regv[m.group(1)] = flag_v.get(m.group(2))
                continue
            m = LOAD_VAL.match(l)
            if m and m.group(3) in slot_flag:
                regslot[m.group(1)] = m.group(3)
            m = CLONEIF.match(l)
            if m and m.group(2) in regslot:
                # the value itself where the slot owns it, else a clone: the
                # result is the caller's either way (`ret` hands it over)
                regslot[m.group(1)] = regslot[m.group(2)]
            m = STORE_FLAG.match(l) or STORE_FLAG_PTR.match(l)
            if m:
                # (any i1 slot's known value: a drop flag, or a guard a
                # branch reads, `dkeep`'s, so an infeasible path is not taken)
                flag_v[m.group(2)] = m.group(1) in ("true", "1")
                continue
            m = STORE_I1_VAR.match(l)
            if m and m.group(2) not in flags:
                flag_v.pop(m.group(2), None)
            m = STORE_I1_VAR.match(l)
            if m and m.group(2) in flags:
                # a value moved from one slot to another (`= w v`): the
                # target owns it as the source did (whose flag is cleared next)
                f, src = m.group(2), loads[m.group(1)]
                flag_v[f], val[f] = flag_v.get(src, False), val.get(src)
                continue
            m = STORE_ANY.match(l)
            if m and m.group(1) in slot_flag:
                f = slot_flag[m.group(1)]
                if owned(f):
                    return f"mismatch: {name} {m.group(1)} overwritten while it owns a value: {'>'.join(path)}"
                val[f] = next(fresh)
                continue
            m = DROPIF.search(l)
            if m:
                f = loads[m.group(1)]
                if f not in flags:
                    continue
                if regv.get(m.group(1)):
                    if val.get(f) is None or val[f] in released:
                        return f"mismatch: {name} {next(iter(pairs[f]))} released twice: {'>'.join(path)}"
                    released.add(val[f])
                continue
            if RET.match(l):
                m = RET_VAL.match(l)
                if m and m.group(1) in regslot:
                    # the slot's value handed to the caller: moved out
                    f = slot_flag[regslot[m.group(1)]]
                    if owned(f):
                        released.add(val[f])
                for f in flags:
                    if owned(f):
                        return f"mismatch: {name} {next(iter(pairs[f]))} leaks at the return: {'>'.join(path)}"
                return None
            m = BR_COND.match(l)
            if m:
                c = m.group(1).strip()
                if regv.get(c) is not None:
                    c = "1" if regv[c] else "0"
                outs = [m.group(2)] if c in ("1", "true") else [m.group(3)] if c in ("0", "false") else [m.group(2), m.group(3)]
                for o in outs:
                    r = run(o, (flag_v, val, released), visits, path)
                    if r:
                        return r
                return None
            m = BR.match(l)
            if m:
                return run(m.group(1), (flag_v, val, released), visits, path)
            if l.strip().startswith("unreachable"):
                return None
        return None

    return run("entry", ({}, {}, set()), {}, [])


def main():
    text = open(sys.argv[1]).read()
    fns = functions(text)
    ok, uns, bad = 0, [], []
    for name, blocks in fns.items():
        try:
            r = check_function(name, blocks)
        except Unsupported as e:
            uns.append(str(e))
            continue
        if r:
            bad.append(r)
        else:
            ok += 1
    for b in bad:
        print(b)
    for u in uns if "-v" in sys.argv else []:
        print("unsupported:", u)
    print(f"validated {ok}, unsupported {len(uns)}, mismatch {len(bad)}")
    sys.exit(3 if bad else 0)


if __name__ == "__main__":
    main()
