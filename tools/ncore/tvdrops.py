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


def check_function(name, blocks, owning):
    """None if validated, else a mismatch string. Raises Unsupported.
    `owning`: the types the module has a `__dropif_T` for (what owns)."""
    body = {lab: lines for lab, lines in blocks}
    for _, lines in blocks:
        for l in lines:
            if any(u in l for u in UNTRACKED):
                raise Unsupported(f"{name}: a drop decided at run time ({l.strip()[:60]})")
            if SWITCH.match(l):
                raise Unsupported(f"{name}: a switch")
    # The slots of this function's own frame (an `alloca`), and which of
    # them own (their type has a `__dropif`): found from the types, not from
    # the drops being checked. A slot reached through a pointer (a capture
    # by pointer, an `inout` parameter) is another frame's, checked there.
    local, own_slots = set(), set()
    for _, lines in blocks:
        for l in lines:
            mm = re.match(r"^\s*(%[\w.]+) = alloca ([^,]+?)(?:, align \d+)?$", l)
            if mm:
                local.add(mm.group(1))
                if mm.group(2).strip().lstrip("%") in owning:
                    own_slots.add(mm.group(1))
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
    for flag, slots in pairs.items():
        if len(slots) != 1:
            raise Unsupported(f"{name}: flag {flag} guards several slots")
    flags = set(pairs)
    slot_flag = {next(iter(v)): f for f, v in pairs.items()}
    # an owning slot that is given a value but has no drop flag: nothing here
    # says who releases what it holds
    stored = set()
    for _, lines in blocks:
        for l in lines:
            m = STORE_ANY.match(l)
            if m:
                stored.add(m.group(1))
    for sl in own_slots & stored:
        if sl not in slot_flag:
            raise Unsupported(f"{name}: an owning slot {sl} with no drop flag")
    if not pairs:
        return None
    for _, lines in blocks:
        for l in lines:
            m = STORE_I1_VAR.match(l)
            if m and m.group(2) in pairs and loads.get(m.group(1)) not in pairs:
                raise Unsupported(f"{name}: a drop flag given a computed value")

    # Paths, depth-first, each block entered at most 3 times on one path (a
    # loop's body twice). The state, carried from block to block: each i1
    # slot's known value, each owning slot's value (an id: a store into the
    # slot makes a new one), the values released, and the registers' loads
    # (a flag register's value and the value id it came with; a value
    # register's id). A block reached again in an equal state (ids renamed
    # in order) is not explored again.
    import itertools
    fresh = itertools.count(1)
    seen = set()

    def canon(st):
        flag_v, val, released, regv, regid = st
        ren = {}
        def r(x):
            if x is None:
                return None
            if x not in ren:
                ren[x] = len(ren) + 1
            return ren[x]
        v = tuple(sorted((k, r(x)) for k, x in sorted(val.items())))
        rv = tuple(sorted((k, x) for k, x in regv.items()))
        ri = tuple(sorted((k, r(x)) for k, x in sorted(regid.items())))
        rel = tuple(sorted(r(x) for x in released if x in ren))
        return (tuple(sorted(flag_v.items())), v, rel, rv, ri)

    def run(lab, st, visits, path):
        visits = dict(visits)
        visits[lab] = visits.get(lab, 0) + 1
        if visits[lab] > 3:
            return None
        key = (lab, visits[lab], canon(st))
        if key in seen:
            return None
        seen.add(key)
        path = path + [lab]
        flag_v, val, released = dict(st[0]), dict(st[1]), set(st[2])
        regv, regid = dict(st[3]), dict(st[4])

        def owned(f):
            return flag_v.get(f) and val.get(f) is not None and val[f] not in released

        def go(o):
            return run(o, (flag_v, val, released, regv, regid), visits, path)

        for l in body.get(lab, []):
            m = LOAD_FLAG.match(l)
            if m:
                regv[m.group(1)] = flag_v.get(m.group(2))
                regid[m.group(1)] = val.get(m.group(2))
                continue
            m = LOAD_VAL.match(l)
            if m and m.group(3) in slot_flag:
                regid[m.group(1)] = val.get(slot_flag[m.group(3)])
            m = CLONEIF.match(l)
            if m and m.group(2) in regid:
                # the value itself where the slot owns it, else a clone: the
                # result is the caller's either way (`ret` hands it over)
                regid[m.group(1)] = regid[m.group(2)]
            m = STORE_FLAG.match(l) or STORE_FLAG_PTR.match(l)
            if m:
                flag_v[m.group(2)] = m.group(1) in ("true", "1")
                continue
            m = STORE_I1_VAR.match(l)
            if m:
                if m.group(2) in flags:
                    # a value moved from one slot to another (`= w v`): the
                    # target owns what the source held when its flag was
                    # loaded, as the load read it
                    f, reg = m.group(2), m.group(1)
                    if regv.get(reg) is None:
                        raise Unsupported(f"{name}: a drop flag moved from an unknown value")
                    flag_v[f], val[f] = regv[reg], regid.get(reg)
                else:
                    flag_v.pop(m.group(2), None)
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
                on = regv.get(m.group(1))
                if on is None:
                    raise Unsupported(f"{name}: a drop whose flag's value is not known")
                if on:
                    vid = regid.get(m.group(1))
                    if vid is None or vid in released:
                        return f"mismatch: {name} {next(iter(pairs[f]))} released twice: {'>'.join(path)}"
                    released.add(vid)
                continue
            if RET.match(l):
                m = RET_VAL.match(l)
                if m and regid.get(m.group(1)) is not None:
                    # the value the register loaded, handed to the caller
                    released.add(regid[m.group(1)])
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
                    r = go(o)
                    if r:
                        return r
                return None
            m = BR.match(l)
            if m:
                return go(m.group(1))
            if l.strip().startswith("unreachable"):
                return None
        return None

    return run("entry", ({}, {}, set(), {}, {}), {}, [])


def main():
    text = open(sys.argv[1]).read()
    fns = functions(text)
    owning = set(re.findall(r"@__dropifv?_([\w.]+)\(", text))
    ok, uns, bad = 0, [], []
    for name, blocks in fns.items():
        try:
            r = check_function(name, blocks, owning)
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
