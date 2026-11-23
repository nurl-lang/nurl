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
JPUSH2 = re.compile(r"call void @nurl_journal_push_drop2\(ptr (%[\w.]+), ptr (%[\w.]+|null), ptr @[\w.]+\)")
JFORGET_SLOT = re.compile(r"call void @nurl_journal_forget_slot\(ptr (%[\w.]+)\)")
JRAW = ("@nurl_journal_push(", "@nurl_journal_push_drop(", "@nurl_journal_push_slice(",
        "@nurl_journal_forget(", "@nurl_journal_disown(")
CALL = re.compile(r"call [^@]*@([\w.$]+)\(")
# calls that cannot panic: the journal's and the drops' own entry points,
# LLVM intrinsics, the Vec control block's accessors (D1 asks nothing at them)
NOPANIC = ("nurl_journal_", "__dropif", "llvm.", "nurl_vctl_", "__nurl_cloneif", "nurl_free")
UNTRACKED = ("__nurl_clear_if", "__nurl_hown", "__nurl_set_if", "invoke ", "indirectbr", "resume ")


class Unsupported(Exception):
    pass


def may_panic_set(core_text, nurlc, llvm_text=""):
    """The functions that may start a panic, from nurlc's core IR: one with
    an inline panic point (`fn` flag bit 3), an indirect call or a construct
    the walk did not lower, or a call of one that may; a runtime entry as
    nurlc's journal elision answers it (`--may-panic=`). The names are the
    LLVM ones (`__nurl_fn.<name>` / `<entry>`)."""
    import subprocess
    fns, calls, cur = {}, {}, None
    clo_of, roots, indirect = {}, set(), set()
    for raw in core_text.splitlines():
        f = raw.split("\t")
        if f[0] == "fn":
            cur = f[1]
            fl = int(f[6]) if len(f) > 6 and f[6].isdigit() else 8
            fns[cur] = bool(fl & 8)
            calls[cur] = set()
        elif f[0] == "endfn":
            cur = None
        elif cur is not None:
            w = raw.split()
            if len(w) >= 4 and w[0] == "let" and w[2] == "closure":
                clo_of[(cur, "v" + w[1])] = w[3]
            if "recover" in w:
                k = w.index("recover")
                if k > 0 and w[k - 1] == "call" and k + 2 < len(w):
                    c = clo_of.get((cur, w[k + 2]))
                    roots.add(c if c else "*")
            if "callind" in w:
                indirect.add(cur)
            for k, t in enumerate(w):
                if t == "call" and k + 1 < len(w):
                    calls[cur].add(w[k + 1])
                elif t in ("callind", "opaque"):
                    fns[cur] = True
    ext = sorted({c for cs in calls.values() for c in cs if c not in fns} |
                 # runtime entries the LLVM calls that the IR does not name
                 {c for c in re.findall(r"call [^@]*@(nurl_\w+)\(", llvm_text) if c not in fns})
    ans = {}
    if ext:
        out = subprocess.run([nurlc, "--may-panic=" + ",".join(ext)], capture_output=True, text=True).stdout
        for line in out.splitlines():
            w = line.split()
            if len(w) == 2:
                ans[w[0]] = w[1] == "T"
    mp = {n for n, v in fns.items() if v} | {n for n, v in ans.items() if v}
    unknown = {c for c in ext if c not in ans}
    mp |= unknown
    changed = True
    while changed:
        changed = False
        for n, cs in calls.items():
            if n not in mp and cs & mp:
                mp.add(n); changed = True
    known = set(fns) | set(ans)
    # the functions that may run under a recover frame: the closures handed
    # to `recover` and what they reach (an indirect call reaches every
    # closure; a recover of a closure not bound here, every function)
    if "*" in roots:
        under = set(fns)
    else:
        under, work = set(), [r for r in roots if r]
        while work:
            n = work.pop()
            if n in under:
                continue
            under.add(n)
            work += [c for c in calls.get(n, ()) if c in fns]
            if n in indirect:
                work += [c for c in fns if c.startswith("__closure")]
    under_ll = {"__nurl_fn." + n for n in under} | under
    return ({"__nurl_fn." + n for n in mp} | mp, {"__nurl_fn." + n for n in known} | known, under_ll)


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


MAYPANIC = None   # (may-panic names, known names), from --core


def can_panic(callee):
    if callee.startswith(NOPANIC):
        return False
    if MAYPANIC is None:
        return True
    mp, known, _ = MAYPANIC
    return callee in mp or callee not in known


def check_function(name, blocks, owning, journal=False):
    """None if validated, else a mismatch string. Raises Unsupported.
    `owning`: the types the module has a `__dropif_T` for (what owns).
    `journal` (D1): also the panic journal's registrations."""
    body = {lab: lines for lab, lines in blocks}
    if journal:
        for _, lines in blocks:
            for l in lines:
                if any(r in l for r in JRAW):
                    raise Unsupported(f"{name}: a raw-pointer journal registration")
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
    loads, pairs, jonly = {}, {}, set()
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
                if fv in ("true", "1") and slot in local:
                    # an unconditional drop: the slot owns whatever is stored
                    # in it (a flag that is always set, `!slot`)
                    pairs.setdefault("!" + slot, set()).add(slot)
                    continue
                if fv in ("false", "0"):
                    continue
                if fv not in loads:
                    raise Unsupported(f"{name}: a drop flag not loaded from a flag slot ({fv})")
                if slot not in local or loads[fv] not in local:
                    continue
                pairs.setdefault(loads[fv], set()).add(slot)
    if journal:
        for _, lines in blocks:
            for l in lines:
                m = JPUSH2.search(l)
                if m and m.group(1) in local and m.group(2) in local and m.group(1) not in {
                        x for v in pairs.values() for x in v}:
                    # a slot the journal alone tracks (a temporary whose value
                    # moves on into an aggregate): its flag is the journal's
                    pairs.setdefault(m.group(2), set()).add(m.group(1))
                    jonly.add(m.group(1))
    for flag, slots in pairs.items():
        if len(slots) != 1 and not flag.startswith("!"):
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
        flag_v, val, released, regv, regid, jr = st
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
        return (tuple(sorted(flag_v.items())), v, rel, rv, ri, tuple(sorted(jr)))

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
        regv, regid, jr = dict(st[3]), dict(st[4]), set(st[5])

        def owned(f):
            return flag_v.get(f) and val.get(f) is not None and val[f] not in released

        def owns(f):
            # (a journal-only slot owns nothing the frame releases: what it
            # holds moved on, and only the journal's forget says so)
            # (nor does a slot that is always released, `!slot`: its value
            # may move out by a load, with no flag to say so; only its
            # releases are checked, each value once)
            return owned(f) and next(iter(pairs[f])) not in jonly and not f.startswith("!")

        def go(o):
            return run(o, (flag_v, val, released, regv, regid, jr), visits, path)

        for l in body.get(lab, []):
            if journal:
                m = JPUSH2.search(l)
                if m and m.group(1) in slot_flag:
                    if m.group(1) in jr:
                        return f"mismatch: {name} {m.group(1)} journaled twice: {'>'.join(path)}"
                    jr.add(m.group(1))
                    continue
                m = JFORGET_SLOT.search(l)
                if m:
                    jr.discard(m.group(1))
                    continue
                m = CALL.search(l)
                if m and can_panic(m.group(1)) and not DROPIF.search(l):
                    # a call that may panic: what a drain would release must
                    # be what the frame owns, each once
                    for sl, f in slot_flag.items():
                        if owned(f) and sl not in jr:
                            return f"mismatch: {name} {sl} owned but not journaled at a call to {m.group(1)}: {'>'.join(path)}"
                        if sl in jr and flag_v.get(f) and (val.get(f) is None or val[f] in released):
                            return f"mismatch: {name} {sl} journaled after its release, at a call to {m.group(1)}: {'>'.join(path)}"
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
                mv = re.match(r"^\s*store \S+ (%[\w.]+), ", l)
                if mv and val.get(f) is not None and regid.get(mv.group(1)) == val[f]:
                    # the value the slot holds, stored back (`= e { … e }`)
                    continue
                if owns(f):
                    return f"mismatch: {name} {m.group(1)} overwritten while it owns a value: {'>'.join(path)}"
                val[f] = next(fresh)
                if f.startswith("!"):
                    flag_v[f] = True
                continue
            m = DROPIF.search(l)
            if m:
                if m.group(1) in ("false", "0"):
                    continue
                if m.group(1) in ("true", "1"):
                    f = "!" + m.group(2)
                    if f not in flags:
                        continue
                    if val.get(f) is None or val[f] in released or not flag_v.get(f):
                        return f"mismatch: {name} {m.group(2)} released twice: {'>'.join(path)}"
                    released.add(val[f])
                    continue
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
                if journal and jr:
                    return f"mismatch: {name} {sorted(jr)[0]} still journaled at the return: {'>'.join(path)}"
                m = RET_VAL.match(l)
                if m and regid.get(m.group(1)) is not None:
                    # the value the register loaded, handed to the caller
                    released.add(regid[m.group(1)])
                for f in flags:
                    if owns(f):
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

    return run("entry", ({}, {}, set(), {}, {}, set()), {}, [])


def main():
    text = open(sys.argv[1]).read()
    fns = functions(text)
    owning = set(re.findall(r"@__dropifv?_([\w.]+)\(", text))
    # D1 (--journal): the journal is what a recover frame's catch drains;
    # without a recover in the program a panic ends the process, and no
    # registration is owed
    journal = "--journal" in sys.argv and "call i64 @nurl_recover" in text
    if journal and "--core" in sys.argv:
        global MAYPANIC
        i = sys.argv.index("--core")
        MAYPANIC = may_panic_set(open(sys.argv[i + 1]).read(), sys.argv[i + 2], text)
    ok, uns, bad, jok = 0, [], [], 0
    for name, blocks in fns.items():
        try:
            # (D1 asks the journal of a function that may run under a
            # recover frame; elsewhere a panic ends the process)
            jn = journal and (MAYPANIC is None or name in MAYPANIC[2])
            r = check_function(name, blocks, owning, jn)
        except Unsupported as e:
            uns.append(str(e))
            continue
        if r:
            bad.append(r)
        else:
            ok += 1
            jok += 1 if jn else 0
    for b in bad:
        print(b)
    for u in uns if "-v" in sys.argv else []:
        print("unsupported:", u)
    jtail = f", journal-checked {jok}" if journal else ""
    print(f"validated {ok}, unsupported {len(uns)}, mismatch {len(bad)}{jtail}")
    sys.exit(3 if bad else 0)


if __name__ == "__main__":
    main()
