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


def struct_fields(t):
    return STRUCTS.get(t if t.startswith("%") else "%" + t)


_EXPANDING = set()
DTOR_TYS = set()


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
    if t.startswith("{ i1, ") and t.endswith(" }"):
        # an option: `sum int t`, None the first variant (formal/A2/Syntax.lean)
        return f"(.sum .int {lean_ty(t[len('{ i1, '):-2])})"
    if not t.startswith("%"):
        t = "%" + t   # a type argument's name, inside another (`%Vec__String`)
    if t.startswith("%Vec__"):
        return f"(.vec {lean_ty(t[len('%Vec__'):])})"
    if t == "%String":
        return "(.vec .int)"   # a Vec of bytes (formal/A2/Syntax.lean)
    if t.startswith("%Slice__"):
        return f"(.slice {lean_ty(t[len('%Slice__'):])})"
    if t in DTOR_TYS:
        # A2's destructor types (`Ty.dtor f u`, letd / scopeD) are not
        # translated yet: leaving the destructor out would leave out the reads
        # it makes where each value ends
        raise Unsupported(f"type {t}, with a destructor of the program's own")
    fs = struct_fields(t)
    if fs is not None and t in _EXPANDING:
        raise Unsupported(f"type {t}, recursive")
    if fs is not None and len(fs) == 1:
        # a struct of one field: A2 has no one-element tuple, so it is its field
        _EXPANDING.add(t)
        try:
            return lean_ty(fs[0][1])
        finally:
            _EXPANDING.discard(t)
    if fs is not None and len(fs) >= 2:
        _EXPANDING.add(t)
        try:
            return _struct_ty(fs)
        finally:
            _EXPANDING.discard(t)
    raise Unsupported(f"type {t}")


def _struct_ty(fs):
    """A struct: its fields nested in pairs to the right (formal/A2's `prod`)."""
    acc = lean_ty(fs[-1][1])
    for _, ft in reversed(fs[:-1]):
        acc = f"(.prod {lean_ty(ft)} {acc})"
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
            cur["body"].append(raw.strip())
    return fns


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
        for v, ty in fn["vars"].items():
            lean_ty(ty)
        self.lits = []
        self.depth = 0   # the loops' blocks around the statement
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
        if borrowed(fn["name"]) and sm.get("rviews", ":") in (":", ""):
            # lent, but from no parameter's storage: a copy of a view an
            # argument holds (a raw string's), which A2 tracks only as a
            # held dependency, not translated yet
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
                if len(w) >= 4 and w[0] == "let" and w[2] == "call" and (w[3] == "string_data" or borrowed(w[3])):
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

    def vlean(self, k):
        """Variable `k`'s A2 type: a raw string that holds a view is a slice."""
        t = self.fn["vars"][k]
        if t == "i8*" and k in self.views:
            return "(.slice .int)"
        return lean_ty(t)

    def var(self, k):
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
        fs = struct_fields(self.fn["vars"][b])
        if fs is not None and len(fs) == 1:
            return self.var(b)   # a struct of one field is its field
        if fs is None or len(fs) < 2:
            raise Unsupported(f"{self.fn['name']}: field of {self.fn['vars'][b]}")
        names = [f for f, _ in fs]
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
                return f".var {self.var(y)}"
            return f".expr {self.operand(op)}"
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
            ty = self.vlean(int(ops[0][1:])) if "/" not in ops[0] else lean_ty(self.vty(ops[0]))
            e = f"(.slen {y})" if ty.startswith("(.slice") else f"(.len {y})" if ty.startswith("(.vec") else f"(.var {y})"
            t = self.fresh()
            return f"(.letv {t} (.expr {e}) {rest})"
        if f == "nurl_str_cat" and n == 2:
            # a fresh string from two it reads: each read checked live
            x = self.fresh() if x is None else x
            s = f"(.letv {x} (.new .int) {rest})"
            for op in ops:
                if op != "c":
                    t = self.fresh()
                    s = f"(.letv {t} (.expr (.len {rd(op)})) {s})"
            return s
        if f == "nurl_str_len" and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr (.len {rd(ops[0])})) {rest})"
        if f == "string_from" and n == 1:
            # a fresh owned String of a text the IR does not track
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.new .int) {rest})"
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
            for t in reversed(pre):
                s = f"(.letv {t} (.expr (.lit 0)) {s})"
            return s
        if f.startswith("vec_len__") and n == 1 and ops[0] != "c":
            x = self.fresh() if x is None else x
            return f"(.letv {x} (.expr (.len {rd(ops[0])})) {rest})"
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
        if f == "string_push_str" and n == 2 and x is None and ops[0] != "c":
            # the String it is handed grows through the borrow (one byte stands
            # for the bytes: A2's `push`, which may move its buffer), and only
            # then are the bytes of the text copied in: the text is read after
            # the change, so a view of the String itself is dead by then
            b, c = self.fresh(), self.lit_temp()
            st = f"(.letv {b} (.borrow {rd(ops[0])}) (.edit true {b} (.push {c})))"
            if ops[1] != "c":
                y = rd(ops[1])
                ty = self.vlean(int(ops[1][1:])) if "/" not in ops[1] else lean_ty(self.vty(ops[1]))
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
            if vec_elem(f, "vec_at__") != ".int":
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
        for op in words[3:3 + n]:
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
        head, i = lines[0].split(), 1
        w = head[0]
        if w in ("line", "drop"):
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
        if w == "ret":
            if head[1] == "c" and self.res_ty == "(.slice .int)":
                # a literal handed back as a view: A2 has no static strings
                raise Unsupported(f"{self.fn['name']}: a literal string handed back as a view")
            if head[1] != "-" and not self.is_int(head[1]):
                ex = f"(.seq (.assign {self.np} (.var {self.pvar(head[1])})) (.exit {self.depth}))"
                return self.seq(ex, self.stmts(lines[1:], names, tail))
            v = "(.lit 0)" if head[1] == "-" else self.operand(head[1])
            ex = f"(.seq (.assign {self.np} (.expr {v})) (.exit {self.depth}))"
            return self.seq(ex, self.stmts(lines[1:], names, tail))
        if w == "let" and head[2] != "call":
            # `let x r` whose value is returned at once: the result takes `r`
            nxt = [l for l in lines[1:] if l.split()[0] not in ("line", "drop")]
            if nxt and nxt[0].split() == ["ret", f"v{head[1]}"]:
                k = lines.index(nxt[0])
                pre = []
                r = self.rhs(head[2:], int(head[1]), pre)
                ex = self.wrap(pre, f"(.seq (.assign {self.np} ({r})) (.exit {self.depth}))")
                return self.seq(ex, self.stmts(lines[k + 1:], names, tail))
        if w == "let":
            x = self.var(int(head[1]))
            rest = self.stmts(lines[1:], names, tail)
            if head[2] == "call":
                got = self.intrinsic(head[2:], rest, x)
                if got is not None:
                    return got
                return self.call(head[2:], names, rest, x)
            pre = []
            s = f"(.letv {x} ({self.rhs(head[2:], int(head[1]), pre)}) {rest})"
            return self.wrap(pre, s)
        if w == "eval":
            rest = self.stmts(lines[1:], names, tail)
            if head[1] == "call":
                return self.call(head[1:], names, rest)
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
            pre = []
            r = self.rhs(head[2:], int(head[1][1:]), pre, assign=True)
            return self.seq(self.wrap(pre, f"(.assign {self.pvar(head[1])} ({r}))"),
                            self.stmts(lines[1:], names, tail))
        raise Unsupported(f"{self.fn['name']}: statement {w}")

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
        tail = f"(.assign {self.np} (.expr (.lit 0)))" if self.fn["ret"] == "void" else ".skip"
        inner = self.stmts(self.fn['body'], names, tail)
        for t in reversed(self.lits):
            inner = f"(.letv {t} (.expr (.lit 0)) {inner})"
        body = f"(.block {inner})"
        def mode(i):
            fl = self.fn["flags"].get(i, 0)
            if fl & 4:
                return ".sink"            # `sink`: the callee takes it over
            if fl & 2:
                return "(.inout .replace)"  # `inout`: the caller's, changed in place
            return ".inp"
        params = ", ".join(f"({mode(i)}, {self.vlean(i)})" for i in range(self.np))
        own = "true" if self.res_own else "false"
        lends = ", ".join(self.lends)
        return (f"{{ params := [{params}], resTy := {self.res_ty}, resOwn := {own}, lends := [{lends}], rholds := [{lends}],\n"
                f"    outHolds := [], body := {body}, nvars := {self.next + 1} }}")


def emit(text):
    # The standard library's functions are A2's constructs (`intrinsic`),
    # not bodies to check: their code is phase B's.
    fns = [f for f in parse(text) if "stdlib/" not in f["file"]]
    names = {f["name"]: i for i, f in enumerate(fns)}
    if "main" not in names:
        raise Unsupported("no main")
    out = ["import C.A3Prog", "open A2 C", ""]
    defs = []
    for i, f in enumerate(fns):
        defs.append(f"def fn{i} : Fn :=\n  {Fn(f, i).lean(names)}")
    out += defs
    out.append("")
    out.append("def P : Prog := [" + ", ".join(f"fn{i}" for i in range(len(fns))) + "]")
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
