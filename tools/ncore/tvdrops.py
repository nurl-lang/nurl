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
  store through a pointer to memory not the frame's (a parameter's, as the
  output or an `inout` one, a pointer read through it or from a slot that
  only holds such pointers, one a call returned), or the `ret`; or be owned
  by another slot (`= d s`, its flag set), or released. A store into
  another slot is no hand-on until that slot's flag is set; one into the
  frame's own storage otherwise (a slot with no flag, a field of a slot),
  or through a pointer not followed, is reported unsupported. A move into
  an aggregate (`insertvalue`) passes what is owed on to the aggregate,
  which must go on in its turn; one value moved in twice is a double
  owner, and a field holding such a value replaced is reported
  unsupported. A slot the journal alone tracks, or one
  always released (`!slot`), is no owner (and a journal `forget` hands
  nothing on): only its release says the value went. A flag cleared with
  the value handed nowhere is a leak (formal/D/Drops.lean's `off` without
  a `copy`). Where the value came from is not followed (a load through
  another value's pointer, a field: maybe a lend, which owns nothing), it
  went on early through a possible clone, or the function calls
  `mem_forget` (with `--sums`), it is reported unsupported instead.
- `store i1 %f, flag` (`= d s`): the flag is copied, not the value. The
  target slot must hold what the source held, else unsupported.
- `__dropif_T(flag, slot)` with the flag set: the slot must own a value (else
  it would be released twice), which is released.
- `__dropifv_T(flag, %r)`, a release of the value a register holds, is
  checked as a slot's. A flag whose value is not known on the path, or a
  register that may be a clone of the value (`__nurl_cloneif` with a
  condition not known), is reported unsupported.
- `ret`: no slot owns a value (it would leak).

A value a register loaded from one slot and stored into another is the same
value in both (not a new one), so the two slots release it once between
them. A parameter of an owning type, and a clone the path knows was made
(`__nurl_cloneif(true, …)`), are values of their own from the start. Such
a clone is the frame's to hand on or release, as a cleared value is. Paths
that meet in one state but for what each still owes, or for what an
aggregate carries, are not merged. A function with no ownership operation
at all (no drop flag, release, clone, journal entry or `sink` call) is
validated without its paths being followed.

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
one value after `= d s`); a value whose flag was cleared and that is still
owed a hand-on is held by an enabled registration (of it, or of an
aggregate it went into), else a panic there leaks it (an aggregate held by
a registration of one value it carries is reported unsupported: what else
it carries is not all followed); at a return nothing
is left registered.

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
# a release of a value a register holds (not a slot): `__dropifv_T(i1 f, T %r)`
DROPIFV = re.compile(r"call void @__dropifv_[\w.]+\(i1 (%[\w.]+|true|false|1|0), .+ (%[\w.]+)\)\s*$")
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


def split_top(s):
    """s split at its commas outside brackets."""
    out, cur, depth = [], "", 0
    for ch in s:
        if ch in "({[<":
            depth += 1
        elif ch in ")}]>":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        cur += ch
    return out + [cur]


def store_parts(l):
    """A `store` line's value and pointer registers (either None where it is
    not a register), the types read by their brackets; None for no store."""
    m = re.match(r"^\s*store (.*)$", l)
    if not m:
        return None
    ops = split_top(m.group(1))
    if len(ops) < 2:
        return None
    return arg_value(ops[0]), arg_value(ops[1])


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
    # parameters: its parameters, a clone; those handovers are checked. A
    # clone it makes is a value it owns, and must hand on or release; a
    # release by value (`__dropifv_T`) is checked as any release. Only a
    # function with no ownership operation at all is skipped)
    if not pairs and not any((pc := parse_call(l)) and pc[0] and pc[0][1:] in SINKS and SINKS[pc[0][1:]][1]
                             for _, lines in blocks for l in lines) \
            and not any(o in l for _, lines in blocks for l in lines
                        for o in ("@__nurl_cloneif", "@__dropif", "@nurl_journal_")):
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
    # (where a pointer a value is stored through points: "other" for memory
    # that is not this frame's (a parameter's, as the output or an `inout`
    # one, a pointer read from it, or one a call returned that was handed
    # none of the frame's own), "local" for the frame's own storage (an
    # `alloca`, a field of one), None where that is not followed (a phi, a
    # constant, a cast from an integer). A store is a hand-on only into
    # "other")
    deflines, roots = {}, {}
    for _, lines in blocks:
        for l in lines:
            md = re.match(r"^\s*(%[\w.]+) = (.*)$", l)
            if md:
                deflines[md.group(1)] = md.group(2)

    def ptr_root(p, seen_=()):
        if p in roots:
            return roots[p]
        if p is None or p in seen_:
            return None
        seen_ = seen_ + (p,)
        d = deflines.get(p, "")
        r = None
        if p in local or d.startswith("alloca "):
            r = "local"
        elif p in params:
            r = "other"
        elif (mg := re.match(r"getelementptr (?:inbounds )?(.*)$", d)):
            ops = split_top(mg.group(1))
            r = ptr_root(arg_value(ops[1]), seen_) if len(ops) > 1 else None
        elif (mg := re.match(r"(?:bitcast|addrspacecast) .* (%[\w.]+) to ", d)):
            r = ptr_root(mg.group(1), seen_)
        elif (mg := re.match(r"load [^,]+, (?:ptr|[^,]+\*) (%[\w.]+)", d)):
            a = mg.group(1)
            if a in local:
                # (a pointer the frame keeps in a slot of its own: where
                # every pointer stored into that slot points)
                rs = set()
                for _, lines in blocks:
                    for l in lines:
                        sp = store_parts(l)
                        if sp is not None and sp[1] == a:
                            rs.add(ptr_root(sp[0], seen_))
                r = "other" if rs == {"other"} else None
            else:
                r = "other" if ptr_root(a, seen_) == "other" else None
        elif (mg := re.match(r"extractvalue .*? (%[\w.]+), \d+(?:, \d+)*$", d)):
            # (a pointer field of an aggregate: where the aggregate came
            # from, a parameter (a slice's buffer) or what was stored in
            # the slot it was loaded from)
            r = ptr_root(mg.group(1), seen_)
            r = r if r == "other" else None
        elif re.match(r"(?:(?:tail|musttail|notail) )?call\b", d):
            pc = parse_call("  " + d)
            if pc and pc[1] is not None and all(ptr_root(x, seen_) != "local" for x in pc[1] if x):
                r = "other"
        roots[p] = r
        return r
    # (the values a store or an aggregate took, before their flag was
    # cleared, through a register that may be a clone: if it was not one,
    # that was their hand-on, so a later leak of them is not a sure one)
    maybe_early = set()
    # (the values that are aggregates an `insertvalue` built)
    agg_ids = set()
    # (for each `insertvalue` result, the `insertvalue` that set each of its
    # fields, along its chain; and the results a value the frame owned went
    # into, on some path: a field of one replaced is not followed)
    chain, owning_ins = {}, set()
    for _, lines in blocks:
        for l in lines:
            mi = re.match(r"^\s*(%[\w.]+) = insertvalue (.*)$", l)
            if mi:
                ops = split_top(mi.group(2))
                base = arg_value(ops[0]) if ops else None
                c = dict(chain.get(base, {}))
                c[tuple(x.strip() for x in ops[2:])] = mi.group(1)
                chain[mi.group(1)] = c

    def canon(st):
        flag_v, val, released, regv, regid, jr, given, maybe, pend, via = st
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
        # (every value awaited is in the key, the ones no slot or register
        # holds any more too: a path that owes a hand-on is not the one that
        # owes none. Renamed in the order they were made)
        pd = tuple(sorted((r(x), pend_key(sl, r)) for x, sl in sorted(pend.items())))
        # (and what every aggregate carries, owed now or not: it may be owed
        # again, and a child moved in twice is a double owner)
        vi = tuple(sorted((r(x), tuple(sorted(r(y) for y in ys))) for x, ys in sorted(via.items())))
        rel = tuple(sorted(r(x) for x in released if x in ren))
        gv = tuple(sorted(r(x) for x in given if x in ren))
        lv = tuple(sorted(r(x) for x in lent_ids if x in ren))
        uv = tuple(sorted(r(x) for x in unk_src if x in ren))
        mv = tuple(sorted(r(x) for x in maybe_early if x in ren))
        return (tuple(sorted(flag_v.items())), v, rel, rv, ri, tuple(sorted(jr.items())), gv, lv,
                tuple(sorted(maybe)), pd, uv, mv, vi)

    def pend_key(sl, r):
        # (an entry of `pend`: a slot name or a clone's register (a hand-on
        # owed), None (handed on before its flag was cleared), or ("in", A):
        # moved into the aggregate A before its flag was cleared)
        if isinstance(sl, tuple):
            return (sl[0], r(sl[1]))
        return ("", sl or "")

    # (the registers live into each block: read on some path on before they
    # are defined again. One that is not is left out of the state there, so
    # that paths which loaded different registers on the way still meet in
    # one state)
    succ, use, dfn, phis, phiops = {}, {}, {}, [], {}
    for lab, lines in blocks:
        succ[lab], use[lab], dfn[lab] = set(), set(), set()
        for l in lines:
            if (mb := BR_COND.match(l)):
                succ[lab] |= {mb.group(2), mb.group(3)}
            elif (mb := BR.match(l)):
                succ[lab].add(mb.group(1))
            md = re.match(r"^\s*(%[\w.]+) = ", l)
            rhs = l.split("=", 1)[1] if md else l
            if re.match(r"\s*phi\b", rhs):
                # (a phi reads each operand at the end of the block it
                # names, not in its own)
                ops = re.findall(r"\[\s*(%[\w.]+)\s*,\s*%([\w.]+)\s*\]", rhs)
                phis += ops
                # (kept in the state on entry, so the phi line itself still
                # sees what they hold)
                phiops.setdefault(lab, set()).update(v for v, _ in ops)
            else:
                use[lab] |= {x for x in re.findall(r"%[\w.]+", rhs) if x not in dfn[lab]}
            if md:
                dfn[lab].add(md.group(1))
    for v, pred in phis:
        if pred in use and v not in dfn[pred]:
            use[pred].add(v)
    live = {lab: set(use[lab]) for lab in use}
    changed = True
    while changed:
        changed = False
        for lab in use:
            out = set().union(*(live.get(s, set()) for s in succ[lab])) if succ[lab] else set()
            new_in = use[lab] | (out - dfn[lab])
            if new_in != live[lab]:
                live[lab], changed = new_in, True

    def run(lab, st, visits, path):
        visits = dict(visits)
        visits[lab] = visits.get(lab, 0) + 1
        lv = live.get(lab, set()) | phiops.get(lab, set())
        st = (st[0], st[1], st[2], {k: x for k, x in st[3].items() if k in lv},
              {k: x for k, x in st[4].items() if k in lv}, st[5], st[6], {k for k in st[7] if k in lv}) + tuple(st[8:])
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
        maybe, pend, via = set(st[7]), dict(st[8]), dict(st[9])
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
            # (the owner test is `owns`, one predicate: a slot the journal
            # alone tracks, or one always released (`!slot`), holding the
            # same value is no owner the frame releases it by)
            if not owns(f) or next(iter(pairs[f])) in fresh_put:
                return
            v = val[f]
            if v in pend and pend[v] is None:
                # (handed on before the flag was cleared: a store)
                del pend[v]
                return
            if isinstance(pend.get(v), tuple):
                # (moved into an aggregate before the flag was cleared: the
                # aggregate owes the hand-on now)
                settle(pend.pop(v)[1], next(iter(pairs[f])), v)
                return
            if v in given or slot_owner(v, f):
                return
            pend[v] = next(iter(pairs[f]))

        def slot_owner(v, but=None):
            # a slot whose flag the frame releases by owns v
            return any(g != but and owns(g) and val.get(g) == v for g in flags)

        def owed(v):
            # a hand-on (or a release) owed for v along the path
            return isinstance(pend.get(v), str)

        def settle(a, sl, u):
            # the aggregate a now carries sl's value, u (or what u carried):
            # owed unless a was handed on, released or taken by a slot
            # already. (`via`: what a carries; a child moved in twice is a
            # double owner)
            via[a] = tuple(sorted(set(via.get(a, ())) | {u} | set(via.pop(u, ()))))
            if a in released or a in given or (a in pend and pend[a] is None) or slot_owner(a):
                return
            if isinstance(pend.get(a), tuple):
                # (a itself was moved into another aggregate since: that one
                # carries it on)
                settle(pend[a][1], sl, a)
                return
            if not owed(a):
                pend[a] = sl

        def carries(a):
            # a is an aggregate some value was moved into, still owned by
            # its slot then
            return a in agg_ids and any(e == ("in", a) for e in pend.values())

        def handed(regs, before=False):
            # registers handed on by this line: their values are no longer
            # awaited; `before`: a hand-on that also counts ahead of the
            # clear (a move into memory, not a call). An aggregate counts
            # as handed on at a call too: no slot keeps it
            for r in regs:
                if r not in regid or r in loads or regid[r] is None:
                    continue
                v = regid[r]
                if owed(v):
                    if r in maybe:
                        # (what is handed on may be a clone: the value
                        # itself may still be owed a release)
                        raise Unsupported(f"{name}: a value whose drop flag was cleared, handed on as a "
                                          f"possible clone ({r})")
                    del pend[v]
                elif before and slot_owner(v):
                    if r in maybe:
                        # (a possible clone handed on is not the value's
                        # hand-on: if it was one, the value is still owed)
                        maybe_early.add(v)
                        continue
                    pend[v] = None
                elif carries(v) and not isinstance(pend.get(v), tuple):
                    # (an aggregate holding a value moved in, handed on)
                    pend[v] = None

        def leak(v, sl, where):
            # v is owed a hand-on that never came: a mismatch, or where the
            # analysis did not follow all of it, unsupported
            what = (f"the clone {sl[6:]} made here" if sl.startswith("clone ")
                    else f"{sl}'s flag cleared while it owned its value, and the value")
            if v in unk_src:
                raise Unsupported(f"{name}: {sl}'s flag cleared, its value handed nowhere {where}, and where "
                                  f"the value came from is not followed (a lend, or a leak)")
            if v in maybe_early:
                raise Unsupported(f"{name}: {sl}'s value handed nowhere {where} but through a possible clone")
            if name in FORGETS:
                # (`mem_forget` gives a value up on purpose: the LLVM clears
                # its flag and calls nothing)
                raise Unsupported(f"{name}: {sl}'s flag cleared with its value handed nowhere {where}, "
                                  f"in a function that calls `mem_forget`")
            return f"mismatch: {name} {what} handed nowhere {where}: it leaks: {'>'.join(path)}"

        def go(o):
            return run(o, (flag_v, val, released, regv, regid, jr, given, maybe, pend, via), visits, path)

        for l in body.get(lab, []):
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
            elif (ms := store_parts(l)) and ms[0] and ms[1]:
                # (stored into another frame's memory, a field: handed
                # on. Into a slot of this frame that has a flag: not
                # handed on; that slot owns it once its flag is set,
                # and releases it then, or the value is still owed)
                sv, dst = ms
                if dst in slot_flag or dst in borrowed:
                    pass
                elif sv in regid and sv not in loads and regid[sv] is not None and (
                        owed(regid[sv]) or slot_owner(regid[sv]) or carries(regid[sv])) and \
                        ptr_root(dst) != "other":
                    # (into the frame's own storage, a slot with no drop
                    # flag or a field of a slot: no hand-on, and who
                    # releases it is not followed; or through a pointer
                    # whose target is not followed)
                    where = "a slot of the frame that has no drop flag" if dst in local else (
                        "the frame's own storage" if ptr_root(dst) == "local" else "memory not followed")
                    raise Unsupported(f"{name}: an owned value stored into {where} ({dst})")
                elif dst not in local:
                    handed([sv], True)
            elif (mr := RET_VAL.match(l)):
                handed([mr.group(1)])
            elif (mi := re.match(r"^\s*(%[\w.]+) = insertvalue (.*)$", l)):
                # (moved into an aggregate: the aggregate, a value of its
                # own, owes the hand-on now, as its own register)
                ops = split_top(mi.group(2))
                base = arg_value(ops[0]) if ops else None
                elt = arg_value(ops[1]) if len(ops) > 1 else None
                a = regid.get(base) if base and base not in loads else None
                if a is None or (a in pend and pend[a] is None):
                    # (a new aggregate; or one built on an aggregate
                    # already handed on, which is not this one)
                    a = next(fresh)
                    agg_ids.add(a)
                idx = tuple(x.strip() for x in ops[2:])
                if any(i[:len(idx)] == idx or idx[:len(i)] == i for i, r in chain.get(base, {}).items()
                       if r in owning_ins):
                    # (a field that holds a value the frame owned replaced:
                    # the result no longer carries it, the base still does.
                    # One id for both is not that: not followed)
                    raise Unsupported(f"{name}: a field of an aggregate that holds an owned value "
                                      f"replaced ({mi.group(1)})")
                if elt and elt in regid and elt not in loads and regid[elt] is not None and regid[elt] != a:
                    u = regid[elt]
                    if any(u in ys for ys in via.values()):
                        # (one value moved into an aggregate, or two, twice:
                        # each would release it)
                        return f"mismatch: {name} {elt} moved into an aggregate twice: {'>'.join(path)}"
                    if owed(u) or slot_owner(u) or carries(u):
                        owning_ins.add(mi.group(1))
                    if owed(u):
                        if elt in maybe:
                            raise Unsupported(f"{name}: a value whose drop flag was cleared, moved into "
                                              f"an aggregate as a possible clone ({elt})")
                        settle(a, pend.pop(u), u)
                    elif slot_owner(u) or carries(u):
                        # (still owned by its slot, or an aggregate holding
                        # such a value: moved into this one)
                        if elt in maybe:
                            maybe_early.add(u)
                        elif u in pend:
                            raise Unsupported(f"{name}: a value moved into two aggregates, or into one "
                                              f"after it was handed on ({elt})")
                        else:
                            pend[u] = ("in", a)
                regid[mi.group(1)] = a
                continue
            elif not LOAD_VAL.match(l):
                used = [r for r in re.findall(r"%[\w.]+", l.split("=", 1)[-1] if " = " in l else l)
                        if r in regid and r not in loads and owed(regid[r])]
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
                    # (a value owed a hand-on that no enabled registration
                    # holds: on the panic edge the drain skips it, and the
                    # hand-on to come is never reached)
                    # (an aggregate is held by a registration of itself; one of
                    # a value it carries holds that value, not the others it
                    # carries, which are not all followed: not claimed)
                    for v, sl in sorted((v, sl) for v, sl in pend.items() if isinstance(sl, str)):
                        if v not in released and v not in given and v not in enabled:
                            if any(x in enabled for x in via.get(v, ())):
                                raise Unsupported(f"{name}: an aggregate owed a hand-on at a call to {callee} that "
                                                  f"may panic, held by a registration of one value it carries")
                            return leak(v, sl, f"before a call to {callee} that may panic")
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
            elif m and m.group(3) in borrowed:
                # (a slot that only holds a borrowed parameter: the register
                # loaded is that parameter)
                regid[m.group(1)] = val.get("b:" + m.group(3))
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
                    # a clone, known on this path: a value of its own, which
                    # the frame owns until it hands it on or releases it
                    regid[m.group(1)] = next(fresh)
                    pend[regid[m.group(1)]] = "clone " + m.group(1)
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
                    # to a `sink` once, not twice), owned by the frame until
                    # it hands it on or releases it
                    regid[m.group(1)] = next(fresh)
                    pend[regid[m.group(1)]] = "clone " + m.group(1)
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
                    # (and a value awaited is owned again, by a slot the
                    # frame releases: not one the journal alone tracks)
                    if next(iter(pairs[m.group(2)])) not in jonly:
                        pend.pop(val.get(m.group(2)), None)
                flag_v[m.group(2)] = m.group(1) in ("true", "1")
                continue
            m = STORE_I1_VAR.match(l)
            if m:
                if m.group(2) in flags:
                    # a value moved from one slot to another (`= w v`): the
                    # target owns what the source held when its flag was
                    # loaded, as the load read it
                    # (the flag alone is copied: the target slot holds what
                    # was stored into it, which must be what the source held,
                    # or the copy says nothing of what the target owns)
                    f, reg = m.group(2), m.group(1)
                    if regv.get(reg) is None:
                        raise Unsupported(f"{name}: a drop flag moved from an unknown value")
                    if regid.get(reg) is None or regid[reg] != val.get(f):
                        raise Unsupported(f"{name}: a drop flag copied into {f}, whose slot does not hold the "
                                          f"value the source flag's slot held")
                    if not regv[reg] and owns(f):
                        cleared(f)
                    flag_v[f] = regv[reg]
                    if regv[reg]:
                        # (an owned value, as after `store i1 1`: what the
                        # slot holds is its own now, no lend)
                        fresh_put.discard(next(iter(pairs[f])))
                    if regv[reg] and next(iter(pairs[f])) not in jonly and not f.startswith("!"):
                        # (a value awaited is owned again)
                        pend.pop(val.get(f), None)
                else:
                    flag_v.pop(m.group(2), None)
                continue
            m = STORE_ANY.match(l)
            if m and m.group(1) in borrowed:
                # (a slot that only holds a borrowed parameter: it holds that
                # parameter's identity, for the loads from it)
                mv = re.match(r"^\s*store \S+ (%[\w.]+), ", l)
                val["b:" + m.group(1)] = regid.get(mv.group(1)) if mv else None
                continue
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
            m = DROPIFV.search(l)
            if m and not DROPIF.search(l):
                # a release of the value a register holds, as its flag says
                vid = regid.get(m.group(2)) if m.group(2) not in loads else None
                fv = m.group(1)
                on = True if fv in ("true", "1") else False if fv in ("false", "0") else regv.get(fv)
                if vid is not None and on is None:
                    # (a value the frame follows, released or not as a flag
                    # not known says: whether it was owed, given to a `sink`,
                    # released, is not decided)
                    raise Unsupported(f"{name}: a release of a value whose flag's value is not known")
                if vid is not None and on and m.group(2) in maybe:
                    # (the value itself, or a clone of it: which one is
                    # released is not known)
                    raise Unsupported(f"{name}: a release of a possible clone ({m.group(2)})")
                if vid is not None and on:
                    if vid in released:
                        return f"mismatch: {name} {m.group(2)} released twice: {'>'.join(path)}"
                    if vid in lent_ids:
                        return f"mismatch: {name} {m.group(2)} releases a parameter it only borrows: {'>'.join(path)}"
                    if vid in given:
                        return f"mismatch: {name} {m.group(2)} released after a `sink` parameter took it: {'>'.join(path)}"
                    released.add(vid)
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
                # (a value still owed: released, or taken by a `sink`, or it
                # leaks. A slot the journal alone tracks, or one always
                # released, holding it is no owner: what it holds is
                # released by its `__dropif`, which says so in `released`)
                for v, sl in sorted((v, sl) for v, sl in pend.items() if isinstance(sl, str)):
                    if v not in released and v not in given:
                        return leak(v, sl, "at the return")
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
    return run("entry", ({}, {}, set(), {}, regid0, {}, set(), set(), {}, {}), {}, [])


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
