#!/usr/bin/env python3
"""nurlc's core IR (`nurlc --emit-core`) as a program of formal/A2's calculus,
for the verified checker of formal/C (`C.progOK2B`, `C.checkA2`,
`C.checked_program_safe2`) to decide (AGORA-975).

First subset: functions over integers (`i64`, `i1`, and the `void` of a
statement's join temporary): bindings, number computations, calls, `if`
and returns. A function's body is a block; `ret` stores the result slot
(variable `params`) and leaves it (`exit 0`). A number the IR does not
track (`c`) is read as a literal: the typing of an integer does not depend
on its value. Anything else is `Unsupported`, and the program is not
emitted.

    python3 tools/ncore/tolean.py prog.core > Prog.lean
"""
import re
import sys

INT_TYS = {"i64", "i1", "i32", "i16", "i8", "void",
           "u64", "u32", "u16", "u8", "f64", "f32", "double", "float"}


# Struct types from the IR's `ty` lines: name → [(field, type), …].
STRUCTS = {}
# The fused walk's summaries from the IR's `sum` lines: name → {key: value}.
SUMS = {}


def borrowed(f):
    """Does function `f` hand back a value that views what it was handed
    (its summary: `ret_unowned=1`, or `rviews` naming a parameter)?"""
    sm = SUMS.get(f, {})
    if "ret_owned" in sm:
        # (its `__ret_owned` marker: it hands over a fresh result; its
        # `ret_unowned` only says no call needs a per-call ownership answer)
        return False
    return sm.get("ret_unowned") == "1" or sm.get("rviews", ":") not in (":", "")


def view_deps(f):
    """What `f`'s result may view (`rviews`: `:` then, for each parameter,
    `k` its own storage or `^k` only its elements'), as A2 dependencies
    (formal/A2/Syntax.lean, `Kind`): `^k` is `inner` (strictly inside its
    elements: a view of an element's String), `k` its own buffer or handle
    (`view`, `self`). `%k`, a copy of the views argument k holds, is not
    translated yet."""
    out = []
    for tok in SUMS.get(f, {}).get("rviews", ":").lstrip(":").split(","):
        tok = tok.strip()
        if not tok:
            continue
        if tok.startswith("%"):
            raise Unsupported(f"{f}: a result holding a copy of argument {tok[1:]}'s views")
        if tok.startswith("^") and tok[1:].isdigit():
            out.append((int(tok[1:]), ".inner"))
        elif tok.isdigit():
            out += [(int(tok), ".view"), (int(tok), ".self")]
        else:
            raise Unsupported(f"{f}: rviews {tok}")
    return out


# Closure types: one interface Fn per type (`{ R (i8*, A…)*, i8* }`), placed
# after the program's own functions (`CLO_BASE`), in the order first seen.
CLO_SIGS = {}
CLO_LIST = []
CLO_BASE = [0]


def clo_sig(t):
    """A closure type's interface: (result, arguments), each an IR type with
    no nested aggregate, or None where `t` is not a closure type."""
    if not (t.startswith("{ ") and t.endswith(", i8* }") and " (i8*" in t):
        return None
    head = t[2:-len(", i8* }")]
    r, _, rest = head.partition(" (i8*")
    if not rest.endswith(")*"):
        raise Unsupported(f"closure type {t}")
    args = [a.strip() for a in rest[:-2].split(",") if a.strip()]
    if "i8*" in [r] + args:
        # a raw string a closure takes or hands back is a view or owned
        # text by its use, which a closure type does not say
        raise Unsupported(f"closure type {t}: a raw string argument or result")
    for x in [r] + args:
        if "{" in x or "(" in x or "*" in x and x != "i8*":
            raise Unsupported(f"closure type {t}: a nested or pointer type")
    return r, args


def clo_index(t):
    """The interface Fn index of closure type `t`."""
    if t not in CLO_SIGS:
        CLO_SIGS[t] = CLO_BASE[0] + len(CLO_LIST)
        CLO_LIST.append(t)
    return CLO_SIGS[t]


def no_clo(t):
    """A type inside another (an element, a payload, a field, a channel's
    element) is no closure: nurlc copies a closure stored in a value
    (`nurl_closure_own_copy`), which the core IR does not show."""
    tt = t if t.startswith("{") else t
    if clo_sig(tt) is not None:
        raise Unsupported(f"a closure inside a value ({t})")
    return t


# The program's functions, for a call's parameter modes.
FNS = []


def cap_ty(t):
    """A capture by value's A2 type, where the translation follows it: a
    number, copied into the environment, or a buffer of numbers (a String, a
    `Vec` of numbers). A buffer captured by value is a copy of its handle
    that depends on the binding (MEMORY.md §2.11: the binding given a new
    value ends the closure): A2's capture by name, read only (`inp`)."""
    lt = lean_ty(t)
    if lt in (".int", "(.vec .int)"):
        return lt
    raise Unsupported(f"a capture of type {t}")


def by_name(t):
    """Is a capture of IR type `t` one by name (a buffer), not a number?"""
    return cap_ty(t) != ".int"


# The calls that change a buffer in place, through the handle they are given
# (a closure's copy of a captured handle reaches the binding's buffer).
CHANGERS = ("vec_push__", "vec_clear__", "vec_truncate__", "vec_reserve__",
            "vec_shrink_to_fit__", "string_push_str")


def changes(fn, k):
    """Does closure code `fn` change capture `k` in place? (Only precision
    rides on it: the code and the literal are both checked against the mode
    it picks.)"""
    for l in fn["body"]:
        w = l.split()
        if "call" in w:
            i = w.index("call")
            if (len(w) > i + 3 and w[i + 1].startswith(CHANGERS) and w[i + 3] == f"v{k}"):
                return True
    return False


def cap_mode(fn, k):
    """A capture by name's A2 mode in closure code `fn`: read only (`inp`),
    or, taken by pointer (the body changes it in place), `inout` at the
    widest bound short of a new value (`drop`; CapsOK's second case, a Vec
    only, so a number taken by pointer is not translated). The code is
    checked against that bound, so a body that gives the capture a new value
    is refused, never let through."""
    if not fn["flags"].get(k, 0) & 8 and not changes(fn, k):
        return ".inp"
    if cap_ty(fn["vars"][k]) != "(.vec .int)":
        raise Unsupported(f"{fn['name']}: a number capture taken by pointer")
    return "(.inout .drop)"


def env_ty(tys):
    """A closure environment of captures of A2 types `tys` (A2 has no unit
    or one-tuple: none is an integer, one is its value, more are pairs to
    the right)."""
    if not tys:
        return ".int"
    acc = tys[-1]
    for t in reversed(tys[:-1]):
        acc = f"(.prod {t} {acc})"
    return acc


def fn_sigma(ty):
    """`.fn [σ] .any` → σ."""
    m = re.fullmatch(r"\(\.fn \[(\d+)\] \.any\)", ty)
    if not m:
        raise Unsupported(f"a call through a value of type {ty}")
    return int(m.group(1))


def struct_fields(t):
    return STRUCTS.get(t if t.startswith("%") else "%" + t)


_EXPANDING = set()
DTOR_TYS = set()
# The program's functions by name → index (A2's `Prog`), for a destructor
# type's `f` (set by `emit` before any function is translated).
NAMES = {}


def dtor_of(t):
    """A type with a `% Drop` of the program's own, `%T` with `drop__T`: its
    destructor's index and its struct as A2's `Ty.dtor f u`. A struct of one
    field is padded with an integer (`prod u int`): A2's destructor types
    are of a struct (`Ty.isStruct`), and the padding is read by no one."""
    f = NAMES.get("drop__" + t.lstrip("%"))
    fs = struct_fields(t)
    if f is None or fs is None or not fs:
        raise Unsupported(f"type {t}, with a destructor A2's translation does not see")
    for _, ft in fs:
        if (ft if ft.startswith("%") else "%" + ft) in DTOR_TYS:
            raise Unsupported(f"type {t}, holding a value of a destructor type ({ft})")
    _EXPANDING.add(t)
    try:
        u = (f"(.prod {dtor_field_ty(fs[0][1])} .int)" if len(fs) == 1
             else _struct_ty(fs, dtor_field_ty))
    finally:
        _EXPANDING.discard(t)
    return f, u


def dtor_field_ty(ft):
    """A destructor struct's field type: a raw string held in a value is a
    view of the text it was made from (MEMORY.md §2.13), a slice: the
    destructor's reads of it are reads of that text."""
    return "(.slice .int)" if ft == "i8*" else lean_ty(ft)


def lean_ty(t):
    """An IR type as an A2 type: an integer, or a `Vec` of them (`%Vec__T`)."""
    if t.lstrip("%") in INT_TYS or t in ("i", "u", "b"):
        # (a scalar: A2's int, its value no part of the memory model)
        return ".int"
    if t == "i8*":
        # a raw string bound from a literal or a fresh string: owned text,
        # A2's buffer of bytes (MEMORY.md §1; one held in a value is a view,
        # §2.13, and is not translated yet)
        return "(.vec .int)"
    sig = clo_sig(t)
    if sig is not None:
        # a closure: code and an environment it owns, of the program's
        # interface for its type; class `any` (it crosses nowhere: a closure
        # sent or spawned needs a class of its own, not translated yet)
        for x in [sig[0]] + sig[1]:
            lean_ty(x)
        return f"(.fn [{clo_index(t)}] .any)"
    if t.startswith("{ i1, ") and t.endswith(" }"):
        # an option: `sum int t`, None the first variant (formal/A2/Syntax.lean)
        return f"(.sum .int {lean_ty(no_clo(t[len('{ i1, '):-2]))})"
    if not t.startswith("%"):
        t = "%" + t   # a type argument's name, inside another (`%Vec__String`)
    if t.startswith("%Vec__"):
        return f"(.vec {lean_ty(no_clo(t[len('%Vec__'):]))})"
    if t.startswith("%Channel__"):
        # A3.4: a `Channel A` is a lock share whose payload is its queue and
        # its closed flag, `lk (prod (vec A) int)` (formal/A2/Syntax.lean,
        # `Ty.ChanOf`). Only an element that holds no destructor value: a
        # channel of those is a lock of the glued struct (`Ty.dtor g …`,
        # nurlc's `ChImpl A` with its drop), not translated.
        return f"(.lk (.prod (.vec {chan_elem(t[len('%Channel__'):])}) .int))"
    if t in ("%str", "str"):
        # a raw string held in a value (a container's element) is a view
        # of a buffer someone else owns (MEMORY.md §2.13)
        return "(.slice .int)"
    if t == "%String":
        return "(.vec .int)"   # a Vec of bytes (formal/A2/Syntax.lean)
    if t.startswith("%Slice__"):
        return f"(.slice {lean_ty(t[len('%Slice__'):])})"
    if t in DTOR_TYS:
        # A2's destructor type (`Ty.dtor f u`): its values are bound by `letd`,
        # whose scope's end runs `f` on them (formal/A2, A2-drop); leaving the
        # destructor out would leave out the reads it makes where a value ends
        if t in _EXPANDING:
            raise Unsupported(f"type {t}, recursive")
        f, u = dtor_of(t)
        return f"(.dtor {f} {u})"
    fs = struct_fields(t)
    if fs is not None and t in _EXPANDING:
        raise Unsupported(f"type {t}, recursive")
    if fs is not None and len(fs) == 1 and fs[0][1] == "i8*":
        raise Unsupported(f"type {t}: a raw string held in a struct field")
    if fs is not None and len(fs) == 1:
        # a struct of one field: A2 has no one-element tuple, so it is its field
        _EXPANDING.add(t)
        try:
            return lean_ty(no_clo(fs[0][1]))
        finally:
            _EXPANDING.discard(t)
    if fs is not None and len(fs) >= 2:
        _EXPANDING.add(t)
        try:
            return _struct_ty(fs)
        finally:
            _EXPANDING.discard(t)
    raise Unsupported(f"type {t}")


def chan_elem(t):
    """A channel's element type, where it holds no destructor value: an
    integer, a String, or a Vec of integers. Anything else is Unsupported."""
    if t in INT_TYS or t in ("i", "u", "b") or t in ("String", "%String"):
        return lean_ty(t)
    if t.lstrip("%").startswith("Vec__") and t.lstrip("%")[len("Vec__"):] in INT_TYS:
        return lean_ty(t)
    raise Unsupported(f"a channel of {t}")


def _struct_ty(fs, fty=None):
    """A struct: its fields nested in pairs to the right (formal/A2's `prod`)."""
    if fty is None:
        for _, ft in fs:
            if ft == "i8*":
                # a raw string in a value is a view (MEMORY.md §2.13), which a
                # field's translation as owned text would not be (a destructor
                # type's fields go through its own `fty`, which gives a view)
                raise Unsupported("a raw string held in a struct field")
    fty = fty or lean_ty
    acc = fty(no_clo(fs[-1][1]))
    for _, ft in reversed(fs[:-1]):
        acc = f"(.prod {fty(no_clo(ft))} {acc})"
    return acc


def vec_elem(fname, prefix):
    """`vec_push__i64` → the element type of the instance."""
    return lean_ty(fname[len(prefix):])


class Unsupported(Exception):
    pass


def parse(text):
    fns, cur = [], None
    for raw in text.splitlines():
        if not raw.strip():
            continue
        f = raw.split("\t")
        if f[0] == "fn":
            cur = {"name": f[1], "ret": f[2], "np": int(f[3]), "file": f[5], "vars": {}, "flags": {}, "body": []}
        elif f[0] == "v" and cur is not None:
            cur["vars"][int(f[1])] = f[-1]
            cur["flags"][int(f[1])] = int(f[4])
            cur.setdefault("kind", {})[int(f[1])] = int(f[2])
        elif f[0] == "sum" and cur is None:
            SUMS[f[1]] = dict(kv.split("=", 1) for kv in f[3:] if "=" in kv)
        elif f[0] == "ty" and cur is None:
            # ty <type> <class> <drops> <base> A <n> … F <n> (<field> <type>)… V …
            i = f.index("F")
            n = int(f[i + 1])
            STRUCTS[f[1]] = [(f[i + 2 + 2 * k], f[i + 3 + 2 * k]) for k in range(n)]
            if len(f) > 3 and "d" in f[3]:
                DTOR_TYS.add(f[1])
        elif f[0] == "endfn":
            if cur["name"].startswith("drop__") and not cur["file"].startswith("stdlib/"):
                # a `% Drop` of the program's own: it runs at the end of every
                # value of the type (MEMORY.md §2.14)
                DTOR_TYS.add("%" + cur["name"][len("drop__"):])
            fns.append(cur)
            cur = None
        elif cur is not None:
            cur["body"].append(Line(raw.strip(), len(cur["body"])))
    return fns


class Line(str):
    """A core IR line that knows its index in its function's body, so a
    check can look at everything after it, not only its own list."""
    def __new__(cls, text, pos):
        o = super().__new__(cls, text)
        o.pos = pos
        return o


def block_of(lines, i):
    """The statements from lines[i] to the matching `end` / `else` at
    depth 0: (statements, index of the closing line)."""
    out, depth = [], 0
    while i < len(lines):
        w = lines[i].split()[0]
        if depth == 0 and w in ("end", "else", "arm"):
            return out, i
        if w in ("scope", "if", "loop", "match", "foreach", "defer"):
            depth += 1
        elif w == "end":
            depth -= 1
        out.append(lines[i])
        i += 1
    return out, i


class Fn:
    def __init__(self, fn, index):
        self.fn, self.index = fn, index
        self.np = fn["np"]
        top = max(list(fn["vars"]) + [self.np - 1, -1])
        self.next = top + 2  # past every core variable and the result slot
        # (a closure's code: its environment first, then its parameters,
        # then the result slot; its captures are read out of the environment
        # at the top of the body - A2/Invariant.lean, `Implements`)
        self.vmap, self.rslot, self.caps = None, self.np, []
        self.closure = fn["name"].startswith("__closure_")
        if self.closure:
            kinds, flags = fn.get("kind", {}), fn["flags"]
            caps = sorted(k for k in fn["vars"] if kinds.get(k) == 3)
            prms = sorted(k for k in fn["vars"] if kinds.get(k) == 0)
            if len(prms) != self.np:
                raise Unsupported(f"{fn['name']}: closure parameters")
            for k in caps:
                cap_ty(fn["vars"][k])
                cap_mode(fn, k)
            for k in prms:
                if flags.get(k, 0) & 6:
                    raise Unsupported(f"{fn['name']}: a closure parameter taken sink or inout")
            if borrowed(fn["name"]):
                raise Unsupported(f"{fn['name']}: a closure whose result is lent")
            vm = {p: 1 + i for i, p in enumerate(prms)}
            # (captures by name: the code's parameters after the interface's,
            # `Implements`: `… ++ cs.map (·.2)`)
            named = [k for k in caps if by_name(fn["vars"][k])]
            for j, k in enumerate(named):
                vm[k] = 1 + self.np + j
            caps = [k for k in caps if k not in named]
            self.named = named
            self.rslot = self.np + 1 + len(named)
            nxt = self.rslot + 1
            for k in sorted(fn["vars"]):
                if k not in vm:
                    vm[k] = nxt
                    nxt += 1
            self.vmap, self.caps, self.prms = vm, caps, prms
            self.next = nxt + 1
        for v, ty in fn["vars"].items():
            lean_ty(ty)
        self.lits = []
        self.depth = 0   # the loops' blocks around the statement
        for i in range(self.np):
            if self.is_dtor(fn["vars"].get(i, "")) and fn["flags"].get(i, 0) & 6:
                # a `sink` / `inout` destructor parameter: moved to a `letd`
                # first thing, or never assigned (dtorParamsB), not yet
                raise Unsupported(f"{fn['name']}: a destructor value as a sink or inout parameter")
        if self.is_dtor(fn["ret"]):
            raise Unsupported(f"{fn['name']}: a destructor value handed back")
        self.res_ty = lean_ty(fn["ret"])
        self.res_own = self.res_ty != ".int"
        self.views = self.view_vars()
        self.lends = []
        sm = SUMS.get(fn["name"], {})
        if sm.get("retdyn") == "1":
            # owned on some paths and lent on others, answered per call:
            # A2's results are one or the other
            raise Unsupported(f"{fn['name']}: a result owned or lent per call")
        if "ret_alias" in sm and not borrowed(fn["name"]) and self.res_own:
            raise Unsupported(f"{fn['name']}: a result aliasing parameter {sm['ret_alias']}")
        rets = [l.split() for l in fn["body"] if l.split()[:1] in (["ret"], ["retnx"])]
        lit_only = bool(rets) and all(len(w) > 1 and w[1] == "c" for w in rets)
        if borrowed(fn["name"]) and sm.get("rviews", ":") in (":", "") and not lit_only:
            # lent, but from no parameter's storage: a copy of a view an
            # argument holds (a raw string's), which A2 tracks only as a
            # held dependency, not translated yet.  (AGORA-980: one that
            # hands back only literals lends nothing, `Rhs.slit`.)
            raise Unsupported(f"{fn['name']}: a result copying a view an argument holds")
        if borrowed(fn["name"]):
            # a result that views what it was handed (the walk's summary,
            # `rviews`): a `slice` of it, not owned, depending on the
            # parameters it names; every kind of dependency on each is
            # declared (a summary may name more than the body needs: a
            # caller only depends on more)
            if fn["ret"] != "i8*":
                raise Unsupported(f"{fn['name']}: a borrowed result of type {fn['ret']}")
            self.res_ty, self.res_own = "(.slice .int)", False
            for k, kind in view_deps(fn["name"]):
                if k < self.np:
                    self.lends.append(f"({k}, {kind})")

    @staticmethod
    def is_dtor(t):
        return t in DTOR_TYS or ("%" + t) in DTOR_TYS

    def view_vars(self):
        """The raw-string variables that hold a view, not their own text:
        bound from `string_data` or from a call whose result is borrowed, or
        handed one (`use`)."""
        views = set()
        changed = True
        while changed:
            changed = False
            for l in self.fn["body"]:
                w = l.split()
                if len(w) >= 4 and w[0] == "let" and w[2] == "call" and (
                        w[3] in ("string_data", "vec_at__str") or borrowed(w[3])):
                    v = int(w[1])
                elif len(w) >= 4 and w[0] == "let" and w[2] == "use" and w[3].startswith("v") and w[3][1:].isdigit() \
                        and int(w[3][1:]) in views:
                    v = int(w[1])
                else:
                    continue
                if v not in views:
                    views.add(v)
                    changed = True
        return views

    def views_of(self, k):
        """`k` and the variables that may view it: bound from a call that
        hands back a view of an argument `k` is (string_data, slice_from_vec,
        vec_at, a borrowed result), or a copy of one of those."""
        out, changed = {k}, True
        mk = ("string_data", "slice_from_vec__", "vec_at__", "slice_at__")
        while changed:
            changed = False
            for l in self.fn["body"]:
                w = l.split()
                if len(w) < 3 or w[0] != "let":
                    continue
                j = int(w[1])
                if j in out:
                    continue
                args = {a.split("/")[0] for a in w[3:]}
                hit = any(f"v{i}" in args for i in out)
                if not hit:
                    continue
                if w[2] == "call" and (w[3].startswith(mk) or borrowed(w[3])):
                    out.add(j); changed = True
                elif w[2] == "use" and self.fn["kind"].get(j) == 2 and j in self.views:
                    out.add(j); changed = True
        return out

    def vlean(self, k):
        """Variable `k`'s A2 type: a raw string that holds a view is a slice."""
        t = self.fn["vars"][k]
        if t == "i8*" and k in self.views:
            return "(.slice .int)"
        return lean_ty(t)

    def var(self, k):
        if self.vmap is not None:
            return self.vmap[k]
        return k if k < self.np else k + 1

    def pvar(self, op):
        """A place that is a whole variable (`v3`), as an A2 variable."""
        if not (op.startswith("v") and op[1:].isdigit()):
            raise Unsupported(f"{self.fn['name']}: the place {op} where a variable is needed")
        return self.var(int(op[1:]))

    def fresh(self):
        self.next += 1
        return self.next - 1

    def lit_temp(self):
        """An integer temporary holding a number the IR does not track,
        bound once at the top of the body (`lean`), so a branch needs no
        scope of its own for it."""
        t = self.fresh()
        self.lits.append(t)
        return t

    def field_temp(self, op, pre):
        """`v/f`: the field read into a temporary. A struct of n fields is
        `prod t0 (prod t1 (… (prod t(n-2) t(n-1))))`: field i is i `snd`s,
        then a `fst` (the last field, `n-1`, is the last `snd` itself).
        The bindings it needs are appended to `pre`."""
        base, field = op.split("/", 1)
        if "/" in field:
            raise Unsupported(f"{self.fn['name']}: nested field {op}")
        b = int(base[1:])
        bt = self.fn["vars"][b]
        fs = struct_fields(bt)
        # (a destructor struct of one field is padded, `prod u int`: dtor_of)
        padded = fs is not None and len(fs) == 1 and self.is_dtor(bt)
        if fs is not None and len(fs) == 1 and not padded:
            return self.var(b)   # a struct of one field is its field
        if fs is None or (len(fs) < 2 and not padded):
            raise Unsupported(f"{self.fn['name']}: field of {self.fn['vars'][b]}")
        names = [f for f, _ in fs] + (["(padding)"] if padded else [])
        i, n = names.index(field), len(names)
        cur = self.var(b)
        for _ in range(i):
            t = self.fresh(); pre.append((t, f".snd {cur}")); cur = t
        if i < n - 1:
            t = self.fresh(); pre.append((t, f".fst {cur}")); cur = t
        return cur

    def operand(self, op, pre=None):
        if op == "c":
            return "(.lit 0)"
        if "/" in op and pre is not None:
            return f"(.var {self.field_temp(op, pre)})"
        if op.startswith("v") and op[1:].isdigit():
            return f"(.var {self.pvar(op)})"
        raise Unsupported(f"{self.fn['name']}: operand {op}")

    def vty(self, op):
        """The IR type of a place: a variable's, or a field's through its struct."""
        base, _, path = op.partition("/")
        if not (base.startswith("v") and base[1:].isdigit()):
            raise Unsupported(f"{self.fn['name']}: the place {op}")
        t = self.fn["vars"].get(int(base[1:]), "i64")
        for f in [p for p in path.split("/") if p]:
            fs = struct_fields(t)
            if fs is None or f not in dict(fs):
                raise Unsupported(f"{self.fn['name']}: the field path {op}")
            t = dict(fs)[f]
        return t

    def flean(self, op):
        """A field's A2 type: a destructor struct's raw string field is a view
        (dtor_field_ty)."""
        base = self.fn["vars"].get(int(op.split("/")[0][1:]), "")
        if self.is_dtor(base):
            return dtor_field_ty(self.vty(op))
        return lean_ty(self.vty(op))

    def is_int(self, op):
        return op == "c" or self.vty(op) in INT_TYS

    def rhs(self, words, dest=None, pre=None, assign=False):
        k = words[0]
        if k == "agg" and words[1] in ("T", "F") and dest is not None:
            ty = lean_ty(self.fn["vars"][dest])
            if not ty.startswith("(.sum .int "):
                raise Unsupported(f"{self.fn['name']}: aggregate of type {ty}")
            pay = ty[len("(.sum .int "):-1]
            if words[1] == "F":
                return f".inl {self.lit_temp()} {pay}"
            op = words[3]
            if op == "c":
                return f".inr .int {self.lit_temp()}"
            return f".inr .int {self.pvar(op)}"
        if k == "payload" and words[2] == "T" and words[3] == "0":
            return f".getr {self.pvar(words[1])}"
        if k == "none":
            # a slot not yet given a value: A2 binds only with one, so only a
            # scalar's (whose placeholder no read can tell apart) is translated
            if dest is not None and lean_ty(self.fn["vars"].get(dest, "i64")) != ".int":
                raise Unsupported(f"{self.fn['name']}: an owner bound before its value")
            return ".expr (.lit 0)"
        if k == "use" and words[1] == "c" and dest is not None and self.fn["vars"].get(dest) == "i8*":
            return ".new .int"   # a literal: its own copy of the text
        if k == "use" and "/" in words[1]:
            # a field's value: an integer is read through the pairs; an owning
            # one would move out of its struct, which A2 does only by `unpair`
            base, field = words[1].split("/", 1)
            fs = struct_fields(self.fn["vars"].get(int(base[1:]), "")) or []
            fty = dict(fs).get(field)
            if fty not in INT_TYS or pre is None:
                raise Unsupported(f"{self.fn['name']}: the field {words[1]} moved or copied")
            return f".expr (.var {self.field_temp(words[1], pre)})"
        if k == "use":
            op = words[1]
            if op != "c" and self.vty(op) not in INT_TYS:
                y = int(op[1:])
                kinds, flags = self.fn.get("kind", {}), self.fn["flags"]
                vt = self.fn["vars"]
                # (A `: ~` binding of another binding or of a parameter is a
                # cursor, a borrow of it, MEMORY.md §2.3; a temporary's value
                # moves into its holder.)
                if not assign and dest is not None and kinds.get(dest) == 1 and flags.get(dest, 0) & 1 and kinds.get(y) in (0, 1):
                    return f".borrow {self.var(y)}"
                if (assign and kinds.get(y) == 0 and not flags.get(y, 0) & 6
                        and vt.get(y) != "i8*" and kinds.get(dest) != 0):
                    # a borrowed parameter assigned to a local: codegen re-points
                    # the local at it and clears its drop flag, an owner turned
                    # into a lend, which A2's bindings are not
                    raise Unsupported(f"{self.fn['name']}: an owner given a borrowed parameter's value")
                if (assign and pre is not None and kinds.get(y) == 0
                        and not flags.get(y, 0) & 6 and kinds.get(dest) == 0
                        and flags.get(dest, 0) & 2 and vt.get(y) == vt.get(dest)
                        and vt.get(y) != "i8*"):
                    # a borrowed parameter assigned to an `inout` one: codegen
                    # copies it (`__nurl_clone_T`; the IR's `use` leaves the
                    # copy implicit), a read of the parameter and a fresh owner
                    ty = lean_ty(vt[y])
                    if not ty.startswith("(.vec "):
                        raise Unsupported(f"{self.fn['name']}: a copy of a {vt[y]} parameter")
                    t = self.fresh()
                    pre.append((t, f".expr (.len {self.var(y)})"))
                    return f".new {ty[len('(.vec '):-1]}"
                if assign and vt.get(y) == "i8*":
                    # `= dst src` of raw text copies it (MEMORY.md §2.13: a
                    # copy of a binding that owns its text is a view of it),
                    # which a move would not be
                    raise Unsupported(f"{self.fn['name']}: raw text assigned from another binding")
                return f".var {self.var(y)}"
            return f".expr {self.operand(op)}"
        if (k == "agg" and words[1] == "-" and dest is not None and int(words[2]) == 1
                and self.is_dtor(self.fn["vars"][dest])):
            # a destructor struct of one field: its field and the padding
            op = words[3]
            v = str(self.lit_temp()) if op == "c" else str(self.pvar(op))
            return f".pair {v} {self.lit_temp()}"
        if k == "agg" and words[1] == "-" and dest is not None and int(words[2]) == 1:
            # a struct of one field is its field's value
            op = words[3]
            if op == "c" or self.is_int(op):
                return f".expr {self.operand(op)}"
            return f".var {self.pvar(op)}"
        if k == "agg" and words[1] == "-" and dest is not None:
            # a struct literal: its fields nested in pairs to the right
            n = int(words[2])
            vs = [str(self.lit_temp()) if o == "c" else str(self.pvar(o)) for o in words[3:3 + n]]
            if n < 2:
                raise Unsupported(f"{self.fn['name']}: struct of {n} field(s)")
            acc = vs[-1]
            for v in reversed(vs[1:-1]):
                t = self.fresh(); pre.append((t, f".pair {v} {acc}")); acc = str(t)
            return f".pair {vs[0]} {acc}"
        if k == "scalar":
            ops = [self.operand(o, pre) for o in words[2:2 + int(words[1])]]
            e = "(.lit 0)"
            for o in ops:
                e = f"(.add {e} {o})"
            return f".expr {e}"
        raise Unsupported(f"{self.fn['name']}: rvalue {k}")

    def argvar(self, op, pre):
        if op == "c":
            return self.lit_temp()
        return self.pvar(op)

    def intrinsic(self, words, rest, x=None):
        """A standard-library call A2 has a construct for, or None. An
        argument it only reads may be a struct's field (`v3/name`), read
        through the pairs into a temporary (`field_temp`) that lends it."""
        fpre = []
        def rd(op):
            return self.field_temp(op, fpre) if "/" in op else self.pvar(op)
        got = self._intrinsic(words, rest, x, rd)
        return None if got is None else self.wrap(fpre, got)

    def _intrinsic(self, words, rest, x, rd):
        """A standard-library call A2 has a construct for, or None."""
        f, n = words[1], int(words[2])
        ops = words[3:3 + n]
        if f == "nurl_println_int" and n == 1 and x is None:
            # it reads a scalar: nothing of memory to check past the read
            return rest if ops[0] == "c" else f"(.letv {self.fresh()} (.expr {self.operand(ops[0])}) {rest})"
        if f == "nurl_println" and n == 1 and x is None:
            # it reads its argument: the read checked live
            if ops[0] == "c":
                return rest
            y = rd(ops[0])
            ty = self.vlean(int(ops[0][1:])) if "/" not in ops[0] else self.flean(ops[0])
            e = f"(.slen {y})" if ty.startswith("(.slice") else f"(.len {y})" if ty.startswith("(.vec") else f"(.var {y})"
            t = self.fresh()
            return f"(.letv {t} (.expr {e}) {rest})"
        def read(op):
            # a read of raw text, checked live: a view's length or an owner's
            # (a field by its projected type, as nurl_println's: a destructor
            # struct's raw text field is a view)
            y = rd(op)
            ty = self.vlean(int(op[1:])) if "/" not in op else self.flean(op)
            if ty.startswith("(.slice"):
                return f"(.slen {y})"
            if ty.startswith("(.vec"):
                return f"(.len {y})"
            raise Unsupported(f"{self.fn['name']}: {f} of a {ty}")
        if f == "nurl_str_cat" and n == 2:
            # a fresh string from two it reads: each read checked live
            x = self.fresh() if x is None else x
            s = f"(.letv {x} (.new .int) {rest})"
            for op in ops:
                if op != "c":
                    t = self.fresh()
                    s = f"(.letv {t} (.expr {read(op)}) {s})"
            return s
        if f == "nurl_str_len" and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr {read(ops[0])}) {rest})"
        if f == "string_from" and n == 1:
            # a fresh owned String copied from the text it reads (checked live;
            # a literal needs no check)
            x = self.fresh() if x is None else x
            s = f"(.letv {x} (.new .int) {rest})"
            if ops[0] != "c":
                s = f"(.letv {self.fresh()} (.expr {read(ops[0])}) {s})"
            return s
        if f == "string_data" and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.view {rd(ops[0])}) {rest})"
        if f == "string_len" and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr (.len {rd(ops[0])})) {rest})"
        if f.startswith("vec_new__") and n == 0:
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.new {vec_elem(f, 'vec_new__')}) {rest})"
        if f.startswith("vec_push__") and n == 2 and x is None:
            pre = []
            v, y = self.argvar(ops[0], pre), self.argvar(ops[1], pre)
            s = self.seq(f"(.push {v} {y})", rest)
            if vec_elem(f, "vec_push__") == "(.slice .int)":
                # a raw string pushed where it is held in a value: the Vec
                # keeps a view of it (MEMORY.md §2.13), of the text a binding
                # owns, or the view a binding holds, copied
                if ops[1] == "c":
                    raise Unsupported(f"{self.fn['name']}: a literal string held in a Vec (no static strings in A2)")
                k = int(ops[1][1:])
                if self.vlean(k) == "(.vec .int)":
                    t = self.fresh()
                    s = f"(.letv {t} (.view {y}) {self.seq(f'(.push {v} {t})', rest)})"
            for t in reversed(pre):
                s = f"(.letv {t} (.expr (.lit 0)) {s})"
            return s
        if f.startswith("chan_new__") and n == 0:
            # `lockNew` of a fresh queue and a 0 flag (A3.4)
            x = self.fresh() if x is None else x
            q, k, p = self.fresh(), self.fresh(), self.fresh()
            el = chan_elem(f[len("chan_new__"):])
            return (f"(.letv {q} (.new {el}) (.letv {k} (.expr (.lit 0)) (.letv {p} (.pair {q} {k}) "
                    f"(.letv {x} (.lockNew (.prod (.vec {el}) .int) {p}) {rest}))))")
        if f.startswith("Channel_share__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.lockClone {rd(ops[0])}) {rest})"
        if f.startswith("chan_send__") and n == 2 and ops[0] != "c":
            # the value moves to the back of the queue, as `vec_push` takes it;
            # the answer (sent or dropped on a closed channel) is an integer
            chan_elem(f[len("chan_send__"):])
            pre = []
            y = self.argvar(ops[1], pre)
            x = self.fresh() if x is None else x
            s = f"(.letv {x} (.chanSend {rd(ops[0])} {y}) {rest})"
            for t in reversed(pre):
                s = f"(.letv {t} (.expr (.lit 0)) {s})"
            return s
        if (f.startswith("chan_recv__") or f.startswith("chan_try_recv__")) and n == 1 and ops[0] != "c":
            # the head moves out as `some`, or `none`: an owned `sum int A`
            w = "true" if f.startswith("chan_recv__") else "false"
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.chanRecv {w} {rd(ops[0])}) {rest})"
        if f.startswith("chan_close__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.chanClose {rd(ops[0])}) {rest})"
        if f.startswith("vec_len__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr (.len {rd(ops[0])})) {rest})"
        if f.startswith("slice_from_vec__") and "(.slice" in vec_elem(f, "slice_from_vec__"):
            raise Unsupported(f"{self.fn['name']}: a slice of a Vec of views")
        if f.startswith("slice_from_vec__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.view {rd(ops[0])}) {rest})"
        if (f.startswith("vec_clear__") and n == 1 or f.startswith("vec_truncate__") and n == 2) and ops[0] != "c":
            # the callee changes the Vec through the borrow it is handed:
            # its elements past the new length dropped (A2's `edit`, `trunc`)
            pre = []
            i = "(.lit 0)" if n == 1 else self.operand(ops[1], pre)
            b = self.fresh()
            s = f"(.letv {b} (.borrow {rd(ops[0])}) (.edit true {b} (.trunc {i})))"
            if x is not None:   # vec_truncate's answer, a Bool
                rest = f"(.letv {x} (.expr (.lit 0)) {rest})"
            return self.wrap(pre, self.seq(s, rest))
        if ((f.startswith("vec_reserve__") and n == 2 or f.startswith("vec_shrink_to_fit__") and n == 1)
                and x is None and ops[0] != "c"):
            # the buffer may move, its length unchanged: through the borrow it
            # is handed, a push (which may move it) and a cut back to the
            # length it had; only a scalar element, which a cut drops freely
            pfx = "vec_reserve__" if f.startswith("vec_reserve__") else "vec_shrink_to_fit__"
            if vec_elem(f, pfx) != ".int":
                raise Unsupported(f"{self.fn['name']}: {pfx[:-2]} of a non-scalar element")
            pre = []
            if n == 2:
                self.operand(ops[1], pre)
            b, c, k = self.fresh(), self.lit_temp(), self.fresh()
            st = (f"(.letv {b} (.borrow {rd(ops[0])}) (.letv {k} (.expr (.len {b})) "
                  f"(.seq (.edit true {b} (.push {c})) (.edit true {b} (.trunc (.var {k}))))))")
            return self.wrap(pre, self.seq(st, rest))
        if f == "string_push_str" and n == 2 and x is None and ops[0] != "c":
            # the String it is handed grows through the borrow (one byte stands
            # for the bytes: A2's `push`, which may move its buffer), and only
            # then are the bytes of the text copied in: the text is read after
            # the change, so a view of the String itself is dead by then
            b, c = self.fresh(), self.lit_temp()
            st = f"(.letv {b} (.borrow {rd(ops[0])}) (.edit true {b} (.push {c})))"
            if ops[1] != "c":
                y = rd(ops[1])
                ty = self.vlean(int(ops[1][1:])) if "/" not in ops[1] else self.flean(ops[1])
                e = f"(.slen {y})" if ty.startswith("(.slice") else f"(.len {y})" if ty.startswith("(.vec") else None
                if e is None:
                    raise Unsupported(f"{self.fn['name']}: string_push_str of a {ty}")
                st = f"(.seq {st} (.letv {self.fresh()} (.expr {e}) .skip))"
            return self.seq(st, rest)
        if (f.startswith("vec_free__") or f == "string_free") and n == 1 and x is None and ops[0] != "c":
            # a sink that releases what it is handed (A2's `free`)
            return self.seq(f"(.free {self.pvar(ops[0])})", rest)
        if f.startswith("vec_at__") and n == 2 and ops[0] != "c":
            # a bounds-checked element read; only a scalar element, whose
            # value is copied out, is translated (a lent aggregate element
            # needs the borrow the IR's next line takes, not yet followed)
            if vec_elem(f, "vec_at__") not in (".int", "(.slice .int)"):
                raise Unsupported(f"{self.fn['name']}: vec_at of a non-scalar element")
            pre = []
            i = self.operand(ops[1], pre)
            if x is None:
                t = self.fresh()
                s = self.seq(f"(.letv {t} (.at {rd(ops[0])} {i}) .skip)", rest)
            else:
                s = f"(.letv {x} (.at {rd(ops[0])} {i}) {rest})"
            return self.wrap(pre, s)
        if f.startswith("slice_len__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr (.slen {rd(ops[0])})) {rest})"
        return None

    def call(self, words, names, rest, x=None):
        """`call f n op…` into `x` (a fresh temporary if none), then `rest`."""
        f, n = words[1], int(words[2])
        got = self.intrinsic(words, rest)
        if got is not None:
            return got
        if f not in names:
            raise Unsupported(f"{self.fn['name']}: call of {f}, not in the program")
        pre, args = [], []
        callee = FNS[names[f]] if names[f] < len(FNS) else None
        for i, op in enumerate(words[3:3 + n]):
            if (callee is not None and op.startswith("v") and op[1:].isdigit()
                    and clo_sig(self.fn["vars"].get(int(op[1:]), "")) is not None
                    and callee["flags"].get(i, 0) & 6):
                # nurlc copies a closure it hands to a `sink` / `inout`
                # parameter (`nurl_closure_clone`), which the IR does not show
                raise Unsupported(f"{self.fn['name']}: a closure handed to a sink or inout parameter of {f}")
            if op == "c":
                args.append(str(self.lit_temp()))
            elif "/" in op:
                raise Unsupported(f"{self.fn['name']}: a field as an argument ({op})")
            else:
                args.append(str(self.pvar(op)))
        x = self.fresh() if x is None else x
        s = f"(.letcall {x} {names[f]} [{', '.join(args)}] {rest})"
        for t in reversed(pre):
            s = f"(.letv {t} (.expr (.lit 0)) {s})"
        return s

    def stmts(self, lines, names, tail=".skip"):
        """A statement list as one A2 statement, ending in `tail`: each
        binding scoped over what follows it."""
        if not lines:
            return tail
        eff = [k for k, l in enumerate(lines) if l.split()[0] not in ("line", "drop")]
        if eff and lines[eff[-1]].split()[0] == "ret":
            # A list ending in `ret` (the last line of a list is at its own
            # depth: a nested block's ends in `end`) leaves the function from
            # inside every binding made before it. The exit is put after
            # them: ending their scopes and then leaving is what leaving
            # from inside them does (the unwinding ends them in that order),
            # and an exit at the end of a sequence is one a branch around it
            # may end elsewhere (`checkX`'s tail).
            k = eff[-1]
            body = lines[:k] + ["retnx " + " ".join(lines[k].split()[1:])]
            return self.seq(self.stmts(body, names), f"(.exit {self.depth})")
        head, i = lines[0].split(), 1
        w = head[0]
        if w == "drop":
            # a temporary's statement ended: it is released here, which the
            # translation leaves to the end of its scope. That is the same
            # only if nothing reads it, or a view of it, afterwards: else
            # unsupported (CORE_IR.md §2)
            # (everything after the drop in the function, not only the rest
            # of its own list: a drop inside an `if` arm or a block is
            # followed by what comes after that block; github#2242's review)
            k = int(head[1])
            if lean_ty(self.fn["vars"].get(k, "i64")) != ".int" or self.fn["vars"].get(k) == "i8*":
                dead = self.views_of(k)
                pos = getattr(lines[0], "pos", None)
                if pos is None:
                    raise Unsupported(f"{self.fn['name']}: a drop whose place in the body is unknown")
                for later in self.fn["body"][pos + 1:]:
                    toks = set(later.replace("/", " ").split())
                    if any(f"v{j}" in toks for j in dead):
                        raise Unsupported(f"{self.fn['name']}: a temporary, or a view of it, read after its drop")
            return self.stmts(lines[1:], names, tail)
        if w == "line":
            return self.stmts(lines[1:], names, tail)
        if w == "scope":
            body, j = block_of(lines, 1)
            return self.seq(self.stmts(body, names), self.stmts(lines[j + 1:], names, tail))
        if w == "loop":
            # `loop <condition> loopcond op <body> end`: a block around A2's
            # `loop`, whose body runs the condition and leaves the block
            # (`exit 0`) when it is false; `break` leaves it too, and a `ret`
            # leaves it and every block around it.
            depth, j = 0, 1
            while j < len(lines):
                ww = lines[j].split()[0]
                if depth == 0 and ww == "loopcond":
                    break
                if ww in ("scope", "if", "loop", "match", "foreach", "defer"):
                    depth += 1
                elif ww == "end":
                    depth -= 1
                j += 1
            cond, c = lines[1:j], lines[j].split()[1]
            body, k = block_of(lines, j + 1)
            # (the body is a block of its own: `continue` leaves it, `exit 0`,
            # and `break` leaves it and the loop's, `exit 1`)
            self.depth += 1
            self.depth += 1
            inner_body = self.stmts(body, names)
            self.depth -= 1
            if c in ("T", "1"):
                # `~ T { … }`: no condition, the body block alone (`break`
                # and `continue` keep their targets)
                inner = f"(.block {inner_body})"
            else:
                inner = f"(.ite {self.operand(c)} (.block {inner_body}) (.exit 0))"
            loop_body = self.stmts(cond, names, inner)
            self.depth -= 1
            return self.seq(f"(.block (.loop {loop_body}))", self.stmts(lines[k + 1:], names, tail))
        if w == "foreach":
            # `foreach x v … end` over a Vec: the loop holds a borrow of the
            # container for its whole run (a view of it, `view`), and lends
            # each element through it (`sat`), as nurlc's `~` loop does; an
            # index counts up, stepped before the body so `continue` keeps
            # it; the blocks as `loop`'s
            body, k = block_of(lines, 1)
            xs = head[2]
            if not self.fn["vars"].get(int(xs[1:]) if xs[1:].isdigit() else -1, "").startswith("%Vec__"):
                raise Unsupported(f"{self.fn['name']}: foreach over {xs}")
            if "(.slice" in lean_ty(self.fn["vars"][int(xs[1:])]):
                # (a view of a Vec whose elements hold views is not A2's `view`)
                raise Unsupported(f"{self.fn['name']}: foreach over a Vec of views")
            v, x, i, w = self.pvar(xs), self.var(int(head[1])), self.fresh(), self.fresh()
            self.depth += 2
            inner = self.stmts(body, names)
            self.depth -= 2
            step = f"(.assign {i} (.expr (.add (.var {i}) (.lit 1))))"
            each = f"(.letv {x} (.sat {w} (.var {i})) (.seq {step} {inner}))"
            loop = f"(.loop (.ite (.lt (.var {i}) (.slen {w})) (.block {each}) (.exit 0)))"
            return self.seq(f"(.block (.letv {i} (.expr (.lit 0)) (.letv {w} (.view {v}) {loop})))",
                            self.stmts(lines[k + 1:], names, tail))
        if w == "break":
            return self.seq("(.exit 1)", self.stmts(lines[1:], names, tail))
        if w == "continue":
            return self.seq("(.exit 0)", self.stmts(lines[1:], names, tail))
        if w == "match":
            # an option's match: `isl` is 1 for its first variant, None (`F`)
            arms, j = {}, 1
            while j < len(lines) and lines[j].split()[0] == "arm":
                body, k = block_of(lines, j + 1)
                arms[lines[j].split()[1]] = body
                j = k   # the next `arm`, or the match's `end`
            if set(arms) != {"T", "F"}:
                raise Unsupported(f"{self.fn['name']}: match arms {sorted(arms)}")
            m = self.pvar(head[1])
            ite = f"(.ite (.isl {m}) {self.stmts(arms['F'], names)} {self.stmts(arms['T'], names)})"
            return self.seq(ite, self.stmts(lines[j + 1:], names, tail))
        if w == "if":
            a, j = block_of(lines, 1)
            if lines[j].split()[0] == "else":
                b, k = block_of(lines, j + 1)
            else:
                b, k = [], j
            c = self.operand(head[1])
            ite = f"(.ite {c} {self.stmts(a, names)} {self.stmts(b, names)})"
            return self.seq(ite, self.stmts(lines[k + 1:], names, tail))
        if w in ("ret", "retnx"):
            # (`retnx`: the result set, its exit placed after the list, above)
            ex_ = "" if w == "retnx" else f" (.exit {self.depth})"
            if head[1] == "c" and self.res_ty == "(.slice .int)":
                # AGORA-980: a literal handed back as a view is a static
                # block's text (`Rhs.slit`); its length is no part of the
                # typing, so the model's text is empty
                a = f"(.assign {self.rslot} (.slit 0))"
            elif head[1] != "-" and not self.is_int(head[1]):
                a = f"(.assign {self.rslot} (.var {self.pvar(head[1])}))"
            else:
                v = "(.lit 0)" if head[1] == "-" else self.operand(head[1])
                a = f"(.assign {self.rslot} (.expr {v}))"
            ex = f"(.seq {a}{ex_})" if ex_ else a
            return self.seq(ex, self.stmts(lines[1:], names, tail))
        if w == "let" and head[2] not in ("call", "closure", "callind"):
            # `let x r` whose value is returned at once: the result takes `r`
            nxt = [l for l in lines[1:] if l.split()[0] not in ("line", "drop")]
            if nxt and nxt[0].split() == ["ret", f"v{head[1]}"] and not self.is_dtor(self.fn["vars"].get(int(head[1]), "")):
                k = lines.index(nxt[0])
                pre = []
                r = self.rhs(head[2:], int(head[1]), pre)
                ex = self.wrap(pre, f"(.seq (.assign {self.rslot} ({r})) (.exit {self.depth}))")
                return self.seq(ex, self.stmts(lines[k + 1:], names, tail))
        if w == "let" and head[2] == "closure":
            x = self.var(int(head[1]))
            rest = self.stmts(lines[1:], names, tail)
            pre, r = self.closure_lit(head[2:], int(head[1]), names, rest)
            return self.wrap(pre, f"(.letv {x} ({r}) {rest})")
        if (w in ("let", "assign") and len(head) > 3 and head[2] == "use" and head[3].startswith("v")
                and head[3][1:].isdigit()
                and clo_sig(self.fn["vars"].get(int(head[3][1:]), "")) is not None
                and (w == "assign" or self.fn.get("kind", {}).get(int(head[3][1:])) != 2)):
            # a closure moves only from the temporary its literal made into its
            # binding; given another binding, nurlc copies it, unseen here
            raise Unsupported(f"{self.fn['name']}: a closure bound from another binding")
        if w == "let" and head[2] == "callind":
            x = self.var(int(head[1]))
            rest = self.stmts(lines[1:], names, tail)
            return self.callind(head[2:], rest, x)
        if w == "let":
            x = self.var(int(head[1]))
            rest = self.stmts(lines[1:], names, tail)
            d = self.is_dtor(self.fn["vars"].get(int(head[1]), ""))
            if head[2] == "call":
                if d:
                    # a call's owned destructor value goes to its `letd` first
                    # thing in A2 (A2-drop.3a), not translated yet
                    raise Unsupported(f"{self.fn['name']}: a destructor value a call hands back")
                got = self.intrinsic(head[2:], rest, x)
                if got is not None:
                    return got
                return self.call(head[2:], names, rest, x)
            pre = []
            r = self.rhs(head[2:], int(head[1]), pre)
            if d:
                # a value of a destructor type: a `letd` binding, whose scope's
                # end runs the destructor on it (the IR's `drop` lines are that
                # end); a literal, or a value of the type moved in
                f, _ = dtor_of(self.fn["vars"][int(head[1])])
                s = f"(.letd {x} {f} ({r}) {rest})"
            else:
                s = f"(.letv {x} ({r}) {rest})"
            return self.wrap(pre, s)
        if w == "eval":
            rest = self.stmts(lines[1:], names, tail)
            if head[1] == "call":
                return self.call(head[1:], names, rest)
            if head[1] == "callind":
                return self.callind(head[1:], rest)
            t = self.fresh()
            pre = []
            r = self.rhs(head[1:], None, pre)
            return self.wrap(pre, f"(.letv {t} ({r}) {rest})")
        if w == "assign":
            if not (head[1].startswith("v") and head[1][1:].isdigit()):
                raise Unsupported(f"{self.fn['name']}: store to {head[1]}")
            if self.fn["vars"].get(int(head[1][1:])) == "void":
                # a join's value that no one takes (a `void` holder): nothing moves
                return self.stmts(lines[1:], names, tail)
            if self.is_dtor(self.fn["vars"].get(int(head[1][1:]), "")):
                # a destructor binding is given no other value (A2's `letd`)
                raise Unsupported(f"{self.fn['name']}: a destructor binding assigned")
            pre = []
            r = self.rhs(head[2:], int(head[1][1:]), pre, assign=True)
            return self.seq(self.wrap(pre, f"(.assign {self.pvar(head[1])} ({r}))"),
                            self.stmts(lines[1:], names, tail))
        raise Unsupported(f"{self.fn['name']}: statement {w}")

    def read_caps(self, inner):
        """A closure's captures read out of its environment (variable 0,
        lent) at the top of its body: one is the environment, more are its
        pairs' fields (`env_ty`). A number is copied; a buffer is lent from
        the environment, which holds the closure's own copy of it."""
        caps = self.caps
        if not caps:
            return inner
        def take(c, src):
            return f".expr (.var {src})" if cap_ty(self.fn["vars"][c]) == ".int" else f".var {src}"
        if len(caps) == 1:
            return f"(.letv {self.vmap[caps[0]]} ({take(caps[0], 0)}) {inner})"
        binds, cur = [], 0
        for i, c in enumerate(caps):
            if i < len(caps) - 1:
                binds.append((self.vmap[c], f".fst {cur}"))
                t = self.fresh()
                binds.append((t, f".snd {cur}"))
                cur = t
            else:
                binds.append((self.vmap[c], take(c, cur)))
        return self.wrap(binds, inner)

    def closure_lit(self, words, x, names, rest):
        """`closure __closure_N n caps…`: its environment, the captured
        numbers copied into one value (`env_ty`), packed with the code and
        its type's interface (A2's `pack`, captures by name none)."""
        f, n = words[1], int(words[2])
        caps = words[3:3 + n]
        if f not in names:
            raise Unsupported(f"{self.fn['name']}: closure {f}, not in the program")
        for c in caps:
            if c == "c" or "/" in c or not (c.startswith("v") and c[1:].isdigit()):
                raise Unsupported(f"{self.fn['name']}: a capture that is not a variable")
        # (the literal's captures in the code's order: numbers by value into
        # the environment, buffers by name)
        named = [c for c in caps if by_name(self.fn["vars"][int(c[1:])])]
        caps = [c for c in caps if c not in named]
        n = len(caps)
        tys = [cap_ty(self.fn["vars"][int(c[1:])]) for c in caps]
        code = FNS[names[f]]
        ck = sorted(k for k in code["vars"] if code.get("kind", {}).get(k) == 3)
        ck = [k for k in ck if by_name(code["vars"][k])]
        if len(ck) != len(named):
            raise Unsupported(f"{self.fn['name']}: closure {f}'s captures by name")
        cs = ", ".join(f"({self.pvar(c)}, {cap_mode(code, k)}, {self.vlean(int(c[1:]))})"
                       for c, k in zip(named, ck))
        sigma = fn_sigma(self.vlean(int(x)) if isinstance(x, int) else x)
        pre = []
        vals = [self.pvar(c) for c in caps]
        if n == 0:
            y = self.fresh()
            pre.append((y, ".expr (.lit 0)"))
        elif n == 1:
            y = vals[0]
        else:
            acc = vals[-1]
            for v in reversed(vals[:-1]):
                t = self.fresh()
                pre.append((t, f".pair {v} {acc}"))
                acc = t
            y = acc
        return pre, f".pack [{names[f]}] {env_ty(tys)} [{sigma}] {y} [{cs}]"

    def callind(self, words, rest, x=None):
        """`callind n c args…`: method 0 of the package `c`, of its type's
        interface (A2's `callc`)."""
        n = int(words[1])
        ops = words[2:2 + n]
        if ops[0] == "c" or "/" in ops[0]:
            raise Unsupported(f"{self.fn['name']}: a call through {ops[0]}")
        c = self.pvar(ops[0])
        sigma = fn_sigma(self.vlean(int(ops[0][1:])))
        pre, zs = [], []
        for op in ops[1:]:
            if op == "c":
                zs.append(str(self.lit_temp()))
            elif "/" in op:
                raise Unsupported(f"{self.fn['name']}: a field as an argument ({op})")
            else:
                zs.append(str(self.pvar(op)))
        x = self.fresh() if x is None else x
        return f"(.callc {x} {c} 0 {sigma} [{', '.join(zs)}] {rest})"

    @staticmethod
    def wrap(pre, s):
        """The bindings `pre` (temporary, right-hand side) scoped over `s`."""
        for t, r in reversed(pre):
            s = f"(.letv {t} ({r}) {s})"
        return s

    @staticmethod
    def seq(a, b):
        return a if b == ".skip" else f"(.seq {a} {b})"

    def lean(self, names):
        # (a `void` function may fall off its end: its result is the unit)
        tail = f"(.assign {self.rslot} (.expr (.lit 0)))" if self.fn["ret"] == "void" else ".skip"
        inner = self.stmts(self.fn['body'], names, tail)
        for t in reversed(self.lits):
            inner = f"(.letv {t} (.expr (.lit 0)) {inner})"
        if self.closure:
            inner = self.read_caps(inner)
        body = f"(.block {inner})"
        def mode(i):
            fl = self.fn["flags"].get(i, 0)
            if fl & 4:
                return ".sink"            # `sink`: the callee takes it over
            if fl & 2:
                return "(.inout .replace)"  # `inout`: the caller's, changed in place
            return ".inp"
        if self.closure:
            # the environment (lent, `inp`), then the interface's parameters
            params = ", ".join([f"(.inp, {env_ty([cap_ty(self.fn['vars'][c]) for c in self.caps])})"] +
                               [f"(.inp, {self.vlean(p)})" for p in self.prms] +
                               [f"({cap_mode(self.fn, k)}, {self.vlean(k)})" for k in self.named])
        else:
            params = ", ".join(f"({mode(i)}, {self.vlean(i)})" for i in range(self.np))
        own = "true" if self.res_own else "false"
        lends = ", ".join(self.lends)
        return (f"{{ params := [{params}], resTy := {self.res_ty}, resOwn := {own}, lends := [{lends}], rholds := [{lends}],\n"
                f"    outHolds := [], body := {body}, nvars := {self.next + 1} }}")


def emit(text):
    # The standard library's functions are A2's constructs (`intrinsic`),
    # not bodies to check: their code is phase B's.
    fns = [f for f in parse(text) if not f["file"].startswith("stdlib/")]
    names = {f["name"]: i for i, f in enumerate(fns)}
    NAMES.clear()
    NAMES.update(names)
    if "main" not in names:
        raise Unsupported("no main")
    out = ["import C.A3Prog", "open A2 C", ""]
    CLO_SIGS.clear()
    CLO_LIST.clear()
    CLO_BASE[0] = len(fns)
    FNS[:] = fns
    defs = []
    for i, f in enumerate(fns):
        defs.append(f"def fn{i} : Fn :=\n  {Fn(f, i).lean(names)}")
    # one interface per closure type: the receiver (the closure, lent),
    # then its parameters; its body is never run (a call runs the
    # package's code), so it is one that type-checks: a result of the type,
    # made fresh (a number, or an empty buffer)
    for k, t in enumerate(CLO_LIST):
        r, args = clo_sig(t)
        sigma = CLO_BASE[0] + k
        ps = ", ".join([f"(.inp, (.fn [{sigma}] .any))"] + [f"(.inp, {lean_ty(a)})" for a in args])
        rty = lean_ty(r)
        own = "false" if rty == ".int" else "true"
        rs = len(args) + 1
        if rty == ".int":
            made = "(.expr (.lit 0))"
        elif rty.startswith("(.vec ") and rty.count("(") == 1:
            made = f"(.new {rty[len('(.vec '):-1]})"
        else:
            raise Unsupported(f"closure type {t}: a result of type {rty}")
        defs.append(f"def fn{sigma} : Fn :=\n  {{ params := [{ps}], resTy := {rty}, resOwn := {own}, lends := [], "
                    f"rholds := [],\n    outHolds := [], body := (.block (.seq (.assign {rs} {made}) (.exit 0))), "
                    f"nvars := {rs + 1} }}")
    out += defs
    out.append("")
    out.append("def P : Prog := [" + ", ".join(f"fn{i}" for i in range(len(fns) + len(CLO_LIST))) + "]")
    out.append(f"def entry : Stmt := .letcall 0 {names['main']} [] .skip")
    out.append("")
    out.append("#eval progOK2B P && (checkA2 P entry.vars (fun _ => none) [] entry).isSome && stmtCodesB P entry")
    return "\n".join(out) + "\n"


def main():
    # (each statement is nested over the rest of its list: deep for a long body)
    sys.setrecursionlimit(100000)
    text = open(sys.argv[1]).read()
    try:
        sys.stdout.write(emit(text))
    except Unsupported as e:
        print(f"unsupported: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
