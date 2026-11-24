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
- `store i1 0, flag`: the slot's value moves out (or there is none). If the
  slot owned it, the value must be handed on along the path: to a call, a
  store, an aggregate or the `ret`, or into another slot that owns it
  (`= d s`). A flag cleared with the value handed nowhere is a leak
  (formal/D/Drops.lean's `off` without a `copy`). Where the value came from
  is not followed (a load through another value's pointer, a field: maybe a
  lend, which owns nothing) or the function calls `mem_forget` (with
  `--sums`), it is reported unsupported instead.
- `__dropif_T(flag, slot)` with the flag set: the slot must own a value (else
  it would be released twice), which is released.
- `ret`: no slot owns a value (it would leak).

A value a register loaded from one slot and stored into another is the same
value in both (not a new one), so the two slots release it once between
them. A parameter of an owning type, and a clone the path knows was made
(`__nurl_cloneif(true, …)`), are values of their own from the start.

A function whose drops depend on an answer the analysis does not follow
(the per-call ownership answers: `__nurl_clear_if`, `__nurl_hown*`, a flag
loaded from memory it does not own, a flag computed) is reported
`unsupported`, never guessed.

D0c (`--sums core`, the core IR nurlc prints with `--emit-core`): each
function's `sink` / `keeps` parameters, from its `sum` line. Then, also:
- a value handed to such a parameter is not released by the frame as well
  (its flag must be cleared), nor handed on twice;
- a parameter the function only borrows is never released, nor handed to
  a `sink` (stored and loaded back, or as it came); a slot that only ever
  holds one owns nothing (no flag needed);
- a value whose flag is cleared is handed to such a parameter, not to one
  the callee only borrows (that would be a leak);
- a slot is not read after the value it holds was released.
A per-call answer whose key is a constant of the module (`__nurl_clear_if`,
`__nurl_cloneifk` on `@.__nurl_sink.N` and the like) is followed: a result
the path knows is the value itself, not a clone, is checked as that value.
A call of a function with such parameters has every argument position read
(constants too), or the function is reported `unsupported`.

D1 (`--journal`): at each call that may panic (an indirect call is taken to
panic), every value the frame owns is registered
(`nurl_journal_push_drop2`) under its own slot's drop flag, the flag the
drain asks, none twice, none after its release or after a `sink` parameter
took it, and no value under two enabled registrations (two slots holding
one value after `= d s`); at a return nothing is left registered.

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
CLONEIF = re.compile(r"^\s*(%[\w.]+) = call [^@]*@__nurl_cloneif_[\w.]+\(i1 ([^,]+), [^,]* (%[\w.]+)\)")
RET_VAL = re.compile(r"^\s*ret \S.* (%[\w.]+)\s*$")
SWITCH = re.compile(r"^\s*switch\b")
STORE_ANY = re.compile(r"^\s*store .*, (?:ptr|[^,]+\*) (%[\w.]+)(?:, align \d+)?$")
JPUSH2 = re.compile(r"call void @nurl_journal_push_drop2\(ptr (%[\w.]+), ptr (%[\w.]+|null), ptr @[\w.]+\)")
JFORGET_SLOT = re.compile(r"call void @nurl_journal_forget_slot\(ptr (%[\w.]+)\)")
JRAW = ("@nurl_journal_push(", "@nurl_journal_push_drop(", "@nurl_journal_push_slice(",
        "@nurl_journal_forget(", "@nurl_journal_disown(")
CALL_KW = re.compile(r"^\s*(?:%[\w.]+ = )?(?:(?:tail|musttail|notail) )?call\b")
CALLEE = re.compile(r'[@%](?:[\w.$-]+|"[^"]*")')
# calls that cannot panic: the journal's and the drops' own entry points,
# LLVM intrinsics, the Vec control block's accessors (D1 asks nothing at them)
NOPANIC = ("nurl_journal_", "__dropif", "llvm.", "nurl_vctl_", "__nurl_cloneif", "nurl_free")
UNTRACKED = ("__nurl_clear_if", "__nurl_hown", "__nurl_set_if", "invoke ", "indirectbr", "resume ")
# a per-call ownership answer whose key is a constant of the module (a
# callee that answers statically): followed, not reported
CLEARIF = re.compile(r"call void @__nurl_clear_if\(ptr (@[\w.]+), ptr (%[\w.]+)\)")
CLONEIFK = re.compile(r"^\s*(%[\w.]+) = call [^@]*@__nurl_cloneifk_[\w.]+\(ptr (@[\w.]+), i1 ([^,]+), [^,]* (%[\w.]+)\)")
CONST_I1 = re.compile(r"^(@[\w.]+) = private constant i1 (true|false)", re.M)
CONSTS = {}   # @key → its constant answer
SINKS = {}    # D0c (--sums): llvm function → (arity, indices of sink=/keeps= parameters)
PARAMS = {}   # llvm function → its parameters' names, in order
PTYPES = {}   # llvm function → {parameter: its LLVM type}
FORGETS = set()   # D0c (--sums): llvm functions whose core IR calls `mem_forget`


class Unsupported(Exception):
    pass


def parse_call(l):
    """A `call` line read whole: (callee, args), or None where the line has
    no call. The callee is `@name` (direct), `%reg` (indirect), or None where
    it is not found (inline asm, a form not read): the return type is
    skipped by its brackets (`{ void (i8*)*, i8* } @f(`, `void (ptr, ...)
    @printf(`). Each argument is its value: a register (`%r3`), else its
    constant text; None for one that is not read (a constant expression).
    The args are None where the list does not close."""
    m = CALL_KW.search(l)
    if not m:
        return None
    s, i, depth = l, m.end(), 0
    while i < len(s):
        ch = s[i]
        if ch in "({[<":
            depth += 1
        elif ch in ")}]>":
            depth -= 1
        elif depth == 0 and ch in "@%":
            mm = CALLEE.match(s, i)
            if mm and s.startswith("(", mm.end()):
                return mm.group(0), call_args(s, mm.end())
            if mm:
                i = mm.end()
                continue
        i += 1
    return None, None


def call_args(s, i):
    """The arguments of the list opening at s[i] == "(": each its value."""
    args, cur, depth = [], "", 0
    for k in range(i, len(s)):
        ch = s[k]
        if ch in "({[<":
            depth += 1
            if depth == 1:
                continue
        elif ch in ")}]>":
            depth -= 1
            if depth == 0:
                if cur.strip() or args:
                    args.append(cur)
                return [arg_value(a) for a in args]
        elif ch == "," and depth == 1:
            args.append(cur)
            cur = ""
            continue
        cur += ch
    return None


def arg_value(a):
    # (a register is always the argument's last word; a constant, a constant
    # expression included, names none)
    w = a.split()
    if w and re.fullmatch(r"%[\w.]+", w[-1]):
        return w[-1]
    return None


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
            inner = raw[raw.index("(", m.end() - 1) + 1:raw.rindex(")")]
            PARAMS[cur] = re.findall(r"(%[\w.]+)(?=\s*(?:,|$))", inner)
            PTYPES[cur] = dict((n, t.strip()) for t, n in re.findall(r"(?:^|,)\s*([^,]*?)\s+(%[\w.]+)(?=\s*(?:,|$))", inner))
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
    # (an indirect call, or a callee not read, may reach any function: it is
    # taken to panic, as nurlc's own answer takes `callind`)
    if callee is None or not callee.startswith("@"):
        return True
    callee = callee[1:]
    if callee.startswith(NOPANIC):
        return False
    if MAYPANIC is None:
        return True
    mp, known, _ = MAYPANIC
    return callee in mp or callee not in known


PROTECT = {}   # D0b: llvm function → {slot: binding} the core IR never moves


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
            mk = CLEARIF.search(l)
            if mk and mk.group(1) in CONSTS:
                continue
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
    # (a slot that only ever holds a parameter the function borrows, one the
    # core IR's summary does not make a `sink` or `keeps`, owns nothing: its
    # value is the caller's, and the function releases none of it)
    params = PARAMS.get(name, [])
    borrowed, lent = set(), set()
    if name in SINKS and SINKS[name][0] == len(params):
        lent = {p for i, p in enumerate(params) if i not in SINKS[name][1]}
        for sl in own_slots - set(slot_flag):
            vals = [mv.group(1) for _, lines in blocks for l in lines
                    if (mm := STORE_ANY.match(l)) and mm.group(1) == sl
                    for mv in [re.match(r"^\s*store \S+ (%[\w.]+), ", l)] if mv] 
            nst = sum(1 for _, lines in blocks for l in lines if (mm := STORE_ANY.match(l)) and mm.group(1) == sl)
            if vals and len(vals) == nst and all(v in lent for v in vals):
                borrowed.add(sl)
    for sl in (own_slots & stored) - borrowed:
        if sl not in slot_flag:
            raise Unsupported(f"{name}: an owning slot {sl} with no drop flag")
    # (a function with no drop flag still hands values to `sink`
    # parameters: its parameters, a clone; those handovers are checked)
    if not pairs and not any((pc := parse_call(l)) and pc[0] and pc[0][1:] in SINKS and SINKS[pc[0][1:]][1]
                             for _, lines in blocks for l in lines):
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

    # (the registers that may hold a clone, a `__nurl_cloneif` whose answer
    # this path does not know, are the state's `maybe`: what they carry may
    # not be the slot's own value when it is handed on; a result known to be
    # the value itself is not among them)
    lent_ids = set()
    # (the values stored into a slot from a register whose origin is not a
    # call or a parameter: a load through another value's pointer, a field,
    # a phi. A slot given one and its flag cleared may hold a lend, which
    # owns nothing, as well as a leak: not followed)
    defs = {}
    for _, lines in blocks:
        for l in lines:
            md = re.match(r"^\s*(%[\w.]+) = (?:(?:tail|musttail|notail) )?(\w+)", l)
            if md:
                defs[md.group(1)] = md.group(2)
    unk_src = set()

    def canon(st):
        flag_v, val, released, regv, regid, jr, given, maybe, pend = st
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
        gv = tuple(sorted(r(x) for x in given if x in ren))
        lv = tuple(sorted(r(x) for x in lent_ids if x in ren))
        uv = tuple(sorted(r(x) for x in unk_src if x in ren))
        pd = tuple(sorted((r(x), sl) for x, sl in pend.items() if x in ren))
        return (tuple(sorted(flag_v.items())), v, rel, rv, ri, tuple(sorted(jr.items())), gv, lv,
                tuple(sorted(maybe)), pd, uv)

    def run(lab, st, visits, path):
        visits = dict(visits)
        visits[lab] = visits.get(lab, 0) + 1
        key = (lab, min(visits[lab], 3), canon(st))
        if key in seen:
            # a block reached again in a state already explored from it:
            # every path on from here was checked then
            return None
        if visits[lab] > 3:
            # a loop still changing the state after its body ran twice: not
            # every path was followed, so nothing is claimed
            raise Unsupported(f"{name}: a loop whose drop state still changes after two rounds ({lab})")
        seen.add(key)
        path = path + [lab]
        flag_v, val, released = dict(st[0]), dict(st[1]), set(st[2])
        regv, regid, jr, given = dict(st[3]), dict(st[4]), dict(st[5]), set(st[6])
        maybe, pend = set(st[7]), dict(st[8])
        fresh_put = set()

        def owned(f):
            return flag_v.get(f) and val.get(f) is not None and val[f] not in released

        def owns(f):
            # (a journal-only slot owns nothing the frame releases: what it
            # holds moved on, and only the journal's forget says so)
            # (nor does a slot that is always released, `!slot`: its value
            # may move out by a load, with no flag to say so; only its
            # releases are checked, each value once)
            return owned(f) and next(iter(pairs[f])) not in jonly and not f.startswith("!")

        def cleared(f):
            # A flag cleared while its slot owns the value (`store i1 0`, or a
            # constant `__nurl_clear_if` of a consuming callee): the value
            # must be handed on (D2's `clr`), or another slot must own it
            # (`= d s`, D2's `off` after a `copy`); else it leaks, the block
            # live with no owner. A hand-on still to come on the path is
            # awaited (`pend`): codegen loads the value, clears the flag,
            # then hands the register on.
            # (not a store the slot never owned, `= out <a lend>`)
            if not owns(f) or next(iter(pairs[f])) in fresh_put:
                return
            v = val[f]
            if v in pend and pend[v] is None:
                # (handed on before the flag was cleared: into an aggregate,
                # a store)
                del pend[v]
                return
            if v in given or any(g != f and flag_v.get(g) and val.get(g) == v for g in flags):
                return
            pend[v] = next(iter(pairs[f]))

        def handed(regs, before=False):
            # registers handed on by this line: their values are no longer
            # awaited; `before`: a hand-on that also counts ahead of the
            # clear (a move into an aggregate or into memory, not a call)
            for r in regs:
                if r not in regid or r in loads or regid[r] is None:
                    continue
                v = regid[r]
                if v in pend and pend[v] is not None:
                    if r in maybe:
                        # (what is handed on may be a clone: the value
                        # itself may still be owed a release)
                        raise Unsupported(f"{name}: a value whose drop flag was cleared, handed on as a "
                                          f"possible clone ({r})")
                    del pend[v]
                elif before and any(owns(f) and val[f] == v for f in flags):
                    pend[v] = None

        def go(o):
            return run(o, (flag_v, val, released, regv, regid, jr, given, maybe, pend), visits, path)

        for l in body.get(lab, []):
            if flags:
                hc = parse_call(l)
                if hc:
                    # (a call hands on what a `sink` / `keeps` parameter of a
                    # summarized callee takes; with no summary, what it takes
                    # is not known, and every argument counts as handed on,
                    # as D0 alone takes a call: D0c is what knows a borrow)
                    callee, args = hc
                    if callee and callee[1:].startswith(NOPANIC + ("__nurl_clear_if",)):
                        pass
                    elif args is None:
                        handed(re.findall(r"%[\w.]+", l))
                    elif callee and callee.startswith("@") and callee[1:] in SINKS:
                        ar, idx = SINKS[callee[1:]]
                        if len(args) == ar:
                            handed([args[i] for i in idx if i < ar])
                        else:
                            handed(args)
                    else:
                        handed(args)
                elif (ms := re.match(r"^\s*store \S+ (%[\w.]+), (?:ptr|[^,]+\*) (%[\w.]+)", l)):
                    # (stored anywhere but back into its own slot: into
                    # another slot, a field, another frame's memory)
                    tf = slot_flag.get(ms.group(2))
                    if not (tf and regid.get(ms.group(1)) is not None and val.get(tf) == regid[ms.group(1)]):
                        handed([ms.group(1)], True)
                elif (mr := RET_VAL.match(l)):
                    handed([mr.group(1)])
                elif re.match(r"^\s*%[\w.]+ = insertvalue ", l):
                    # (moved into an aggregate)
                    handed(re.findall(r"%[\w.]+", l.split("=", 1)[1]), True)
                elif not LOAD_VAL.match(l):
                    used = [r for r in re.findall(r"%[\w.]+", l.split("=", 1)[-1] if " = " in l else l)
                            if r in regid and r not in loads and pend.get(regid[r], None) is not None]
                    if used:
                        raise Unsupported(f"{name}: a value whose drop flag was cleared, used where its "
                                          f"hand-on is not read ({l.strip()[:60]})")
            if journal:
                m = JPUSH2.search(l)
                if m and m.group(1) in slot_flag:
                    if m.group(1) in jr:
                        return f"mismatch: {name} {m.group(1)} journaled twice: {'>'.join(path)}"
                    # (with the flag it registers: the drain releases the
                    # slot's value where that flag says so)
                    jr[m.group(1)] = m.group(2)
                    continue
                m = JFORGET_SLOT.search(l)
                if m:
                    jr.pop(m.group(1), None)
                    continue
                pc = parse_call(l)
                if pc and can_panic(pc[0]) and not DROPIF.search(l):
                    # a call that may panic (an indirect one too): what a
                    # drain would release must be what the frame owns, each
                    # once, under the slot's own drop flag
                    callee = pc[0] or "an unread callee"
                    enabled = {}
                    for sl, f in slot_flag.items():
                        if owned(f) and sl not in jr:
                            return f"mismatch: {name} {sl} owned but not journaled at a call to {callee}: {'>'.join(path)}"
                        if sl in jr and jr[sl] != (f if not f.startswith("!") else "null"):
                            return (f"mismatch: {name} {sl} journaled with flag {jr[sl]}, not its drop flag "
                                    f"{f}, at a call to {callee}: {'>'.join(path)}")
                        if sl in jr and flag_v.get(f) and (val.get(f) is None or val[f] in released):
                            return f"mismatch: {name} {sl} journaled after its release, at a call to {callee}: {'>'.join(path)}"
                        if sl in jr and flag_v.get(f) and val[f] in given:
                            # (the drain would release what a `sink`
                            # parameter took: the flag must be cleared)
                            return (f"mismatch: {name} {sl} journaled after a `sink` parameter took its value, "
                                    f"at a call to {callee}: {'>'.join(path)}")
                        if sl in jr and flag_v.get(f):
                            if val[f] in enabled:
                                # (one value in two slots, each registered
                                # and enabled: the drain releases it twice)
                                return (f"mismatch: {name} {enabled[val[f]]} and {sl} journaled with one value, "
                                        f"both enabled, at a call to {callee}: {'>'.join(path)}")
                            enabled[val[f]] = sl
            m = LOAD_FLAG.match(l)
            if m:
                regv[m.group(1)] = flag_v.get(m.group(2))
                regid[m.group(1)] = val.get(m.group(2))
                continue
            m = LOAD_VAL.match(l)
            if m and m.group(3) in slot_flag:
                f = slot_flag[m.group(3)]
                if (val.get(f) is not None and val[f] in released and m.group(3) not in jonly
                        and not f.startswith("!")):
                    # D0c: a slot read after the value it holds was
                    # released (a release before its scope's end)
                    return f"mismatch: {name} {m.group(3)} read after its value was released: {'>'.join(path)}"
                regid[m.group(1)] = val.get(f)
                fresh_put.discard(m.group(3))
            m = CLEARIF.search(l)
            if m and m.group(1) in CONSTS:
                if CONSTS[m.group(1)] and m.group(2) in flags:
                    # the callee consumes: the binding's value moves out
                    sl = next(iter(pairs[m.group(2)]))
                    if sl in PROTECT.get(name, {}) and owned(m.group(2)) and sl not in fresh_put:
                        return (f"mismatch: {name} {sl} ({PROTECT[name][sl]}) is never moved in the core IR, "
                                f"but its flag is cleared while it owns a value: {'>'.join(path)}")
                    cleared(m.group(2))
                    flag_v[m.group(2)] = False
                continue
            m = CLONEIFK.match(l)
            if m:
                # a clone exactly when the key and the flag are both set; the
                # value itself otherwise
                k, fl = CONSTS.get(m.group(2)), m.group(3).strip()
                fl = regv.get(fl) if fl.startswith("%") else fl in ("true", "1")
                regid.pop(m.group(1), None)
                maybe.discard(m.group(1))
                if k is False or fl is False:
                    if m.group(4) in regid:
                        regid[m.group(1)] = regid[m.group(4)]
                    if m.group(4) in maybe:
                        maybe.add(m.group(1))
                elif k is True and fl is True:
                    # a clone, known on this path: a value of its own
                    regid[m.group(1)] = next(fresh)
                else:
                    maybe.add(m.group(1))
                continue
            m = CLONEIF.match(l)
            if m:
                # a clone where the flag is set, the value itself otherwise;
                # where this path does not know which, the result is the
                # caller's either way (`ret` hands it over)
                c = m.group(2).strip()
                c = regv.get(c) if c.startswith("%") else c in ("true", "1")
                regid.pop(m.group(1), None)
                maybe.discard(m.group(1))
                if c is True:
                    # a clone, known on this path: a value of its own (handed
                    # to a `sink` once, not twice)
                    regid[m.group(1)] = next(fresh)
                elif m.group(3) in regid:
                    regid[m.group(1)] = regid[m.group(3)]
                if c is None or (c is False and m.group(3) in maybe):
                    maybe.add(m.group(1))
            m = STORE_FLAG.match(l) or STORE_FLAG_PTR.match(l)
            if m:
                if m.group(1) in ("false", "0") and m.group(2) in flags:
                    # D0b: a binding the core IR keeps to its scope end is
                    # not handed on: its flag is not cleared while it owns
                    sl = next(iter(pairs[m.group(2)]))
                    if sl in PROTECT.get(name, {}) and owned(m.group(2)) and sl not in fresh_put:
                        return (f"mismatch: {name} {sl} ({PROTECT[name][sl]}) is never moved in the core IR, "
                                f"but its flag is cleared while it owns a value: {'>'.join(path)}")
                if m.group(1) in ("false", "0") and m.group(2) in flags:
                    cleared(m.group(2))
                if m.group(1) in ("true", "1") and m.group(2) in flags:
                    # (an owned store: what the slot holds is its own now)
                    fresh_put.discard(next(iter(pairs[m.group(2)])))
                    # (and a value awaited is owned again)
                    pend.pop(val.get(m.group(2)), None)
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
                if mv and regid.get(mv.group(1)) is not None:
                    # a value a register loaded from another slot: the same
                    # value, now in two slots (released once between them)
                    if mv.group(1) in maybe:
                        raise Unsupported(f"{name}: a slot given a value that may be a clone ({m.group(1)})")
                    val[f] = regid[mv.group(1)]
                else:
                    val[f] = next(fresh)
                    if not (mv and defs.get(mv.group(1)) == "call"):
                        unk_src.add(val[f])
                if mv and mv.group(1) in lent:
                    # D0c: a parameter the function borrows (not a `sink`)
                    lent_ids.add(val[f])
                # (a store whose flag is cleared before anything reads the
                # slot is a value the slot does not own: `= out <a lend>`)
                fresh_put.add(m.group(1))
                if f.startswith("!"):
                    flag_v[f] = True
                continue
            pc = parse_call(l)
            if pc and pc[0] and pc[0][1:] in SINKS and pc[0].startswith("@") and not DROPIF.search(l):
                callee = pc[0][1:]
                ar, idx = SINKS[callee]
                args = pc[1]
                if args is None or len(args) != ar or any(i >= ar for i in idx):
                    # every argument position is read, or nothing is said
                    raise Unsupported(f"{name}: a call of {callee} whose arguments are not read as its {ar}")
                for i in sorted(idx):
                    a = args[i]
                    vid = regid.get(a) if a else None
                    if a in maybe or vid is None:
                        continue
                    if vid in lent_ids:
                        return f"mismatch: {name} a borrowed parameter handed to a `sink` of {callee}: {'>'.join(path)}"
                    if vid in given:
                        return f"mismatch: {name} a value handed to a `sink` of {callee} twice: {'>'.join(path)}"
                    if vid in released:
                        return f"mismatch: {name} a released value handed to a `sink` of {callee}: {'>'.join(path)}"
                    given.add(vid)
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
                    if val[f] in lent_ids:
                        return f"mismatch: {name} {m.group(2)} releases a parameter it only borrows: {'>'.join(path)}"
                    if val[f] in given:
                        return f"mismatch: {name} {m.group(2)} released after a `sink` parameter took it: {'>'.join(path)}"
                    released.add(val[f])
                    continue
                f = loads[m.group(1)]
                if f not in flags:
                    continue
                on = regv.get(m.group(1))
                if on is None:
                    raise Unsupported(f"{name}: a drop whose flag's value is not known")
                if on:
                    # the flag as loaded decides; what is released is what
                    # the slot holds at the call
                    vid = val.get(f)
                    if vid is None or vid in released:
                        return f"mismatch: {name} {next(iter(pairs[f]))} released twice: {'>'.join(path)}"
                    if vid in lent_ids:
                        return f"mismatch: {name} {next(iter(pairs[f]))} releases a parameter it only borrows: {'>'.join(path)}"
                    if vid in given:
                        # D0c: the callee took it (`sink`), and the frame
                        # releases it too
                        return f"mismatch: {name} {next(iter(pairs[f]))} released after a `sink` parameter took it: {'>'.join(path)}"
                    released.add(vid)
                continue
            if RET.match(l):
                if journal and jr:
                    return f"mismatch: {name} {sorted(jr)[0]} still journaled at the return: {'>'.join(path)}"
                m = RET_VAL.match(l)
                if m and regid.get(m.group(1)) is not None:
                    # the value the register loaded, handed to the caller:
                    # once, and not one the frame released or handed on
                    rv = regid[m.group(1)]
                    if rv in released or rv in given:
                        return f"mismatch: {name} returns a value it released or handed on: {'>'.join(path)}"
                    if rv in lent_ids:
                        return f"mismatch: {name} returns a parameter it only borrows as its own: {'>'.join(path)}"
                    released.add(rv)
                for f in flags:
                    if owns(f):
                        return f"mismatch: {name} {next(iter(pairs[f]))} leaks at the return: {'>'.join(path)}"
                for v, sl in sorted((v, sl) for v, sl in pend.items() if sl is not None):
                    if v not in released and v not in given and not any(owned(f) and val[f] == v for f in flags):
                        if v in unk_src:
                            raise Unsupported(f"{name}: {sl}'s flag cleared, its value handed nowhere, and where "
                                              f"the value came from is not followed (a lend, or a leak)")
                        if name in FORGETS:
                            # (`mem_forget` gives a value up on purpose: the
                            # LLVM clears its flag and calls nothing)
                            raise Unsupported(f"{name}: {sl}'s flag cleared with its value handed nowhere, "
                                              f"in a function that calls `mem_forget`")
                        return (f"mismatch: {name} {sl}'s flag cleared while it owned its value, "
                                f"and the value handed nowhere: it leaks: {'>'.join(path)}")
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

    # (each parameter register is a value of its own from the entry, the
    # ones the function borrows among the lent: a parameter handed on
    # directly, `eat(%p)`, is checked as the parameter, as is one stored
    # into a slot and loaded back)
    # (a parameter of a type that owns: a view, a scalar, a pointer hands no
    # ownership on)
    regid0 = {}
    for p in params:
        if PTYPES.get(name, {}).get(p, "").lstrip("%") not in owning:
            continue
        regid0[p] = next(fresh)
        if p in lent:
            lent_ids.add(regid0[p])
    return run("entry", ({}, {}, set(), {}, regid0, {}, set(), set(), {}), {}, [])


def main():
    text = open(sys.argv[1]).read()
    fns = functions(text)
    if "--protect" in sys.argv:
        for line in open(sys.argv[sys.argv.index("--protect") + 1]):
            w = line.split()
            if len(w) == 3:
                PROTECT.setdefault(w[0], {})[w[1]] = w[2]
    owning = set(re.findall(r"@__dropifv?_([\w.]+)\(", text))
    CONSTS.update((k, v == "true") for k, v in CONST_I1.findall(text))
    if "--sums" in sys.argv:
        # D0c: each function's `sink` / `keeps` parameters, from the core IR
        cur = None
        for raw in open(sys.argv[sys.argv.index("--sums") + 1]):
            f = raw.rstrip("\n").split("\t")
            if f[0] == "fn" and len(f) > 1:
                cur = "_nurl_main" if f[1] == "main" else "__nurl_fn." + f[1]
            elif f[0] == "endfn":
                cur = None
            elif cur and "call mem_forget" in raw:
                FORGETS.add(cur)
            if f[0] == "sum" and len(f) > 2 and f[2].isdigit():
                idx = set()
                for kv in f[3:]:
                    for key in ("sink=", "keeps="):
                        if kv.startswith(key):
                            idx |= {int(x) for x in kv[len(key):].split() if x.isdigit()}
                ll = "_nurl_main" if f[1] == "main" else "__nurl_fn." + f[1]
                SINKS[ll] = (int(f[2]), idx)
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
