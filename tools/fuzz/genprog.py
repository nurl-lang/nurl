#!/usr/bin/env python3
# tools/fuzz/genprog.py — structural NURL program generator + oracle.
#
# The differential fuzzer's second stage. gen.py probes integer/float
# CODEGEN with expression trees; this generator probes the STRUCTURAL
# surface where the historical bugs actually lived: enums with N-ary
# mixed payloads, match (guards, literal constraints, or-patterns),
# struct field writes, closures (creation-time capture of scalars),
# while/foreach loops, defer (reachability-armed, LIFO), `% Drop`
# destructors across scope shapes, string/Vec/slice ownership traffic,
# helper-function calls and self-recursion (TCO).
#
# Like gen.py, the SAME script computes the expected stdout: every
# observable value is printed as its exact 64-bit pattern through the
# shared phex prelude, and the oracle simulates each statement with
# explicit two's-complement semantics. stdout(-O0) != oracle,
# stdout(-O2) != oracle, a nonzero exit, a build failure — or an
# ASan/LSan report on the sanitized leg — is a compiler bug.
#
# Usage:
#   genprog.py SEED                  → the NURL program on stdout
#   genprog.py SEED --oracle         → the expected stdout
#   genprog.py SEED --stmts N        (statement budget, default 14)
#   genprog.py SEED --depth D        (expression depth, default 3)

import sys
import random

import gen  # the expression engine + oracle primitives (same directory)

from gen import (
    TYPES, TYPE_NAMES, wrap, to_u64_bits, Lit, Var, Cmp, Bin, Gen,
)

STRING_POOL = ["hi", "nurl", "fuzz", "abc", "xyzw", "k9", "deep",
               "owl", "prefix-arity", "zz"]

# Payload-capable types for enum variants. `s` (string) and `f` are the
# historically dangerous ones (bit-complete i64 slots, bitcast floats).
PAYLOAD_TYPES = ["i64", "i8", "i16", "i32", "u", "u16", "u32", "u64", "f", "s"]

INT_PAYLOADS = [t for t in PAYLOAD_TYPES if t not in ("f", "s")]


class MutVar(gen.Node):
    """A leaf whose value the oracle updates (loop vars, params)."""
    def __init__(self, ty, name, value=0):
        super().__init__(ty)
        self.name = name
        self.value = value

    def render(self):
        return self.name

    def eval(self):
        return self.value


def norm_ty(ty):
    """The NURL type token for declarations (`i` covers i64)."""
    return ty


class Prog:
    def __init__(self, rng, depth):
        self.rng = rng
        self.depth = depth
        self.lines = []           # main body source lines
        self.decls = []           # top-level declaration lines
        self.out = []             # expected stdout lines (hex16)
        self.deferred = []        # armed defer outputs, LIFO at exit
        self.env = []             # reusable int leaves (Var/MutVar), live values
        self.names = 0
        self.helpers = []         # (name, [param MutVars], body AST)
        self.enums = []           # (ename, [(vname, [ptypes])])
        self.drop_used = False
        self.drops = 0            # oracle count of fired %Drop destructors

    # ── plumbing ─────────────────────────────────────────────────

    def fresh(self, base):
        self.names += 1
        return f"{base}{self.names}"

    def emit(self, line):
        self.lines.append(line)

    def expect_val(self, value, ty):
        self.out.append(f"{to_u64_bits(value, ty):016x}")

    def expect_i64_bits(self, bits):
        self.out.append(f"{bits & ((1 << 64) - 1):016x}")

    def genx(self, ty, extra_env=None, depth=None):
        """An expression tree of type `ty` over literals + given leaves."""
        g = Gen(self.rng)
        g.env = list(self.env if extra_env is None else extra_env)
        return g.gen(ty, self.depth if depth is None else depth)

    def cond(self, leaves=None):
        """A rendered `b`-typed comparison + its oracle truth value."""
        ty = self.rng.choice(TYPE_NAMES)
        a = self.genx(ty, extra_env=leaves, depth=2)
        b = self.genx(ty, extra_env=leaves, depth=2)
        op = self.rng.choice(["<", "<=", ">", ">=", "==", "!="])
        w, signed = TYPES[ty]
        va, vb = a.eval(), b.eval()
        if not signed:
            va &= (1 << w) - 1
            vb &= (1 << w) - 1
        truth = {"<": va < vb, "<=": va <= vb, ">": va > vb,
                 ">=": va >= vb, "==": va == vb, "!=": va != vb}[op]
        return f"{op} {a.render()} {b.render()}", truth

    def phex(self, node_render, value_bits):
        self.emit(f"    ( phex # i64 {node_render} )")
        self.expect_i64_bits(value_bits)

    # ── features ─────────────────────────────────────────────────

    def stmt_int_let(self):
        ty = self.rng.choice(TYPE_NAMES)
        init = self.genx(self.rng.choice(TYPE_NAMES))
        name = self.fresh("v")
        self.emit(f"    : {norm_ty(ty)} {name} {init.render()}")
        self.env.append(Var(ty, name, wrap(init.eval(), ty)))

    def stmt_phex_expr(self):
        ty = self.rng.choice(TYPE_NAMES)
        node = self.genx(ty)
        self.phex(node.render(), to_u64_bits(node.eval(), ty))

    def stmt_struct(self):
        sname = self.fresh("S")
        nfields = self.rng.randint(2, 4)
        ftypes = [self.rng.choice(INT_PAYLOADS) for _ in range(nfields)]
        self.decls.append(f": {sname} {{")
        for i, ft in enumerate(ftypes):
            self.decls.append(f"    {ft} f{i}")
        self.decls.append("}")
        inst = self.fresh("st")
        inits = []
        vals = []
        for ft in ftypes:
            n = self.genx(self.rng.choice(INT_PAYLOADS), depth=2)
            inits.append(n.render())
            vals.append(None)  # filled below
            vals[-1] = wrap(n.eval(), ft)
        self.emit(f"    : {sname} {inst} @ {sname} {{ {' '.join(inits)} }}")
        field_vals = dict(enumerate(vals))
        # a few field writes + reads, values tracked exactly
        for _ in range(self.rng.randint(1, 3)):
            idx = self.rng.randrange(nfields)
            ft = ftypes[idx]
            if self.rng.random() < 0.7:
                node = self.genx(self.rng.choice(INT_PAYLOADS), depth=2)
                self.emit(f"    = . {inst} f{idx} {node.render()}")
                field_vals[idx] = wrap(node.eval(), ft)
            else:
                self.phex(f". {inst} f{idx}", to_u64_bits(field_vals[idx], ft))
        # expose current field values as leaves
        for idx, ft in enumerate(ftypes):
            self.env.append(gen.FieldRead(ft, inst, f"f{idx}", field_vals[idx]))

    def decl_enum(self):
        ename = self.fresh("E")
        nvar = self.rng.randint(2, 4)
        variants = []
        for vi in range(nvar):
            vname = f"{ename}V{vi}"
            if self.rng.random() < 0.3:
                ptypes = []                       # tag-only
            else:
                nslots = self.rng.randint(1, 5)
                ptypes = [self.rng.choice(PAYLOAD_TYPES) for _ in range(nslots)]
            variants.append((vname, ptypes))
        self.decls.append(f": | {ename} {{")
        for vname, ptypes in variants:
            self.decls.append(("    " + vname + " " + " ".join(ptypes)).rstrip())
        self.decls.append("}")
        self.enums.append((ename, variants))

    def payload_literal(self, ptype):
        """(render, oracle_int_contribution, raw_value) for one payload."""
        if ptype == "f":
            base = self.rng.randint(-40, 40)
            frac = self.rng.choice([0.0, 0.5])
            val = base + (frac if base >= 0 else -frac)
            r = repr(val)
            return r, int(val), val               # `# i b` truncates toward 0
        if ptype == "s":
            lit = self.rng.choice(STRING_POOL)
            return f"`{lit}`", len(lit), lit      # arm uses nurl_str_len
        w, _signed = TYPES[ptype]
        hi = (1 << 62) if w == 64 else (1 << w)
        bits = self.rng.randrange(hi)
        return str(bits), wrap(bits, ptype), wrap(bits, ptype)

    def arm_expr_terms(self, ptypes, pnames):
        """Render + oracle for an arm body: payloads folded into an i64 sum.
        int payload  → widened per its declared signedness
        f payload    → `# i x` (fptosi, truncates toward zero)
        s payload    → `( nurl_str_len x )`"""
        terms_r = []
        for pt, pn in zip(ptypes, pnames):
            if pt == "f":
                terms_r.append(f"# i {pn}")
            elif pt == "s":
                terms_r.append(f"( nurl_str_len {pn} )")
            elif pt == "i64":
                terms_r.append(pn)
            else:
                terms_r.append(f"# i {pn}")
        if not terms_r:
            lit = self.rng.randrange(1 << 16)
            return str(lit), lit
        # left-nested prefix sum: + + a b c
        r = terms_r[0]
        for t in terms_r[1:]:
            r = f"+ {r} {t}"
        return r, None  # oracle value computed by caller from contributions

    def stmt_enum_match(self):
        if not self.enums or self.rng.random() < 0.5:
            self.decl_enum()
        ename, variants = self.rng.choice(self.enums)
        # pick the runtime variant + its payload values
        tidx = self.rng.randrange(len(variants))
        tname, tptypes = variants[tidx]
        renders, contribs, raws = [], [], []
        for pt in tptypes:
            r, c, raw = self.payload_literal(pt)
            renders.append(r)
            contribs.append(c)
            raws.append(raw)
        ev = self.fresh("e")
        ctor = f"@ {ename} {{ {tname} {' '.join(renders)} }}" if renders \
            else f"@ {ename} {{ {tname} }}"
        self.emit(f"    : {ename} {ev} {ctor}")

        # build arms in declaration order; compute the oracle by first-match
        arms = []          # rendered arm lines
        result = None      # oracle value of the match expression (i64)
        tag_only = [v for v, p in variants if not p]
        use_orpat = (len(tag_only) >= 2 and self.rng.random() < 0.5)
        orpat_members = tag_only[:2] if use_orpat else []
        orpat_lit = self.rng.randrange(1 << 16)
        orpat_emitted = False

        for vi, (vname, ptypes) in enumerate(variants):
            if vname in orpat_members:
                if not orpat_emitted:
                    arms.append(f"        {' | '.join(orpat_members)} → {orpat_lit}")
                    orpat_emitted = True
                    if tname in orpat_members and result is None:
                        result = orpat_lit
                continue
            pnames = [f"p{vi}_{k}" for k in range(len(ptypes))]
            is_target = (vi == tidx)

            # optional literal-constrained arm (first int slot)
            int_slots = [k for k, pt in enumerate(ptypes) if pt not in ("f", "s")]
            if is_target and int_slots and self.rng.random() < 0.5:
                k = self.rng.choice(int_slots)
                match_it = self.rng.random() < 0.5
                litv = raws[k] if match_it else wrap(raws[k] + 1, ptypes[k])
                # negative literals lex fine (`-3`); u-typed raws are >= 0
                pats = list(pnames)
                pats[k] = str(litv)
                body, _ = self.arm_expr_terms(
                    [pt for j, pt in enumerate(ptypes) if j != k],
                    [pn for j, pn in enumerate(pnames) if j != k])
                lit_result = sum(c for j, c in enumerate(contribs) if j != k) \
                    if len(ptypes) > 1 else None
                if len(ptypes) == 1:
                    litbody = str(self.rng.randrange(1 << 16))
                    arms.append(f"        {vname} {pats[0]} → {litbody}")
                    if match_it and result is None:
                        result = int(litbody)
                else:
                    arms.append(f"        {vname} {' '.join(pats)} → {body}")
                    if match_it and result is None:
                        result = wrap(lit_result, "i64")

            # optional guarded arm
            if is_target and ptypes and self.rng.random() < 0.5:
                guard_leaves = [MutVar("i64", pn, c) for pn, c, pt in
                                zip(pnames, contribs, ptypes) if pt not in ("f", "s")]
                if guard_leaves:
                    grender, gtruth = self.cond(leaves=guard_leaves)
                    gbody = str(self.rng.randrange(1 << 16))
                    arms.append(f"        {vname} {' '.join(pnames)} ? {grender} → {gbody}")
                    if gtruth and result is None:
                        result = int(gbody)

            # the plain covering arm
            body, flat = self.arm_expr_terms(ptypes, pnames)
            arms.append(("        " + vname + " " + " ".join(pnames)).rstrip()
                        + f" → {body}")
            if is_target and result is None:
                result = wrap(sum(contribs), "i64") if ptypes else flat

        rv = self.fresh("m")
        self.emit(f"    : i {rv} ?? {ev} {{")
        for a in arms:
            self.emit(a)
        self.emit("    }")
        self.phex(rv, to_u64_bits(result, "i64"))
        self.env.append(Var("i64", rv, wrap(result, "i64")))

    def stmt_while(self):
        ty = self.rng.choice(TYPE_NAMES)
        acc0 = self.genx(ty, depth=2)
        accv = wrap(acc0.eval(), ty)
        acc = self.fresh("acc")
        k = self.fresh("k")
        n = self.rng.randint(0, 10)
        acc_leaf = MutVar(ty, acc, accv)
        k_leaf = MutVar("i64", k, 0)
        body = self.genx(ty, extra_env=self.env + [acc_leaf] +
                         ([k_leaf] if ty == "i64" else []), depth=2)
        self.emit(f"    : ~ {norm_ty(ty)} {acc} {acc0.render()}")
        self.emit(f"    : ~ i {k} 0")
        self.emit(f"    ~ < {k} {n} {{")
        self.emit(f"        = {acc} {body.render()}")
        self.emit(f"        = {k} + {k} 1")
        maybe_drop = self.drop_used and self.rng.random() < 0.5
        if maybe_drop:
            h = self.fresh("h")
            self.emit(f"        : DH {h} @ DH {{ {k} }}")
        self.emit("    }")
        for it in range(n):
            k_leaf.value = it
            acc_leaf.value = wrap(body.eval(), ty)
            if maybe_drop:
                self.drops += 1
        self.phex(acc, to_u64_bits(acc_leaf.value, ty))
        self.env.append(Var(ty, acc, acc_leaf.value))

    def stmt_foreach(self):
        ety = self.rng.choice(INT_PAYLOADS)
        w, _ = TYPES[ety]
        nelem = self.rng.randint(1, 6)
        elems = [self.rng.randrange(1 << min(w, 62)) for _ in range(nelem)]
        xs = self.fresh("xs")
        sm = self.fresh("sum")
        self.emit(f"    : [{ety} {xs} [ {ety} | {' '.join(str(e) for e in elems)} ]")
        self.emit(f"    : ~ i {sm} 0")
        x = self.fresh("x")
        cast = x if ety == "i64" else f"# i {x}"
        self.emit(f"    ~ {x} {xs} {{ = {sm} + {sm} {cast} }}")
        total = 0
        for e in elems:
            total = wrap(total + to_i64(e, ety), "i64")
        self.phex(sm, to_u64_bits(total, "i64"))
        self.env.append(Var("i64", sm, total))

    def stmt_closure(self):
        # captures snapshot scalar values at creation time
        cap_pool = [v for v in self.env if isinstance(v, Var) and v.ty == "i64"]
        caps = self.rng.sample(cap_pool, min(len(cap_pool), self.rng.randint(0, 2)))
        f = self.fresh("cl")
        x = MutVar("i64", "x", 0)
        body = self.genx("i64", extra_env=caps + [x], depth=2)
        self.emit(f"    : (@ i i) {f} \\ i x → i {{ ^ {body.render()} }}")
        for _ in range(self.rng.randint(1, 2)):
            arg = self.rng.randrange(1 << 32)
            x.value = arg
            self.phex(f"( {f} {arg} )", to_u64_bits(body.eval(), "i64"))

    def stmt_defer(self):
        lit = self.rng.randrange(1 << 32)
        if self.rng.random() < 0.6:
            self.emit(f"    ; {{ ( phex {lit} ) }}")
            self.deferred.append(lit)
        else:
            # defer inside a conditional arm: armed iff the arm runs
            crender, truth = self.cond()
            self.emit(f"    ? {crender} {{ ; {{ ( phex {lit} ) }} }} {{}}")
            if truth:
                self.deferred.append(lit)

    def stmt_drop_scope(self):
        # %Drop values inside a closed scope — counted; the final
        # g_drops phex observes exactly the closed-scope drops.
        self.drop_used = True
        crender, truth = self.cond()
        n = self.rng.randint(1, 3)
        self.emit(f"    ? {crender} {{")
        for j in range(n):
            h = self.fresh("h")
            self.emit(f"        : DH {h} @ DH {{ {j} }}")
        self.emit("    } {}")
        if truth:
            self.drops += n

    def stmt_string(self):
        sn = self.fresh("str")
        self.emit(f"    : String {sn} ( string_new )")
        chars = [self.rng.randint(65, 90) for _ in range(self.rng.randint(0, 6))]
        for c in chars:
            self.emit(f"    ( string_push_char {sn} {c} )")
        self.phex(f"( nurl_str_len ( string_data {sn} ) )", len(chars))
        if chars and self.rng.random() < 0.5:
            other = "".join(chr(c) for c in chars)
            if self.rng.random() < 0.5 and len(other) > 1:
                other = other[:-1] + chr(((ord(other[-1]) - 65 + 1) % 26) + 65)
            eq = 1 if other == "".join(chr(c) for c in chars) else 0
            self.phex(f"( nurl_str_eq ( string_data {sn} ) `{other}` )", eq)
        self.emit(f"    ( string_free {sn} )")

    def stmt_vec(self):
        vv = self.fresh("vec")
        lo = self.rng.randint(-5, 5)
        hi = lo + self.rng.randint(0, 6)
        self.emit(f"    : ( Vec i ) {vv} ( vec_iota {lo} {hi} )")
        vals = list(range(lo, hi))
        for _ in range(self.rng.randint(0, 3)):
            x = self.rng.randrange(1 << 32)
            self.emit(f"    ( vec_push [i] {vv} {x} )")
            vals.append(x)
        sm = self.fresh("vs")
        j = self.fresh("j")
        self.emit(f"    : ~ i {sm} 0")
        self.emit(f"    : ~ i {j} 0")
        self.emit(f"    ~ < {j} ( vec_len [i] {vv} ) {{")
        self.emit(f"        = {sm} + {sm} ( opt_unwrap [i] ( vec_get [i] {vv} {j} ) )")
        self.emit(f"        = {j} + {j} 1")
        self.emit("    }")
        self.emit(f"    ( vec_free [i] {vv} )")
        total = 0
        for e in vals:
            total = wrap(total + e, "i64")
        self.phex(sm, to_u64_bits(total, "i64"))
        self.env.append(Var("i64", sm, total))

    def decl_helper(self):
        hn = self.fresh("hf")
        nparams = self.rng.randint(1, 3)
        ptys = [self.rng.choice(INT_PAYLOADS) for _ in range(nparams)]
        params = [MutVar(pt, f"a{i}", 0) for i, pt in enumerate(ptys)]
        # widened i64 views of the params as expression leaves
        body = None
        g = Gen(self.rng)
        g.env = list(params)
        body = g.gen("i64", self.depth)
        sig = " ".join(f"{pt} a{i}" for i, pt in enumerate(ptys))
        self.decls.append(f"@ {hn} {sig} → i {{ ^ {body.render()} }}")
        self.helpers.append((hn, params, body, ptys))

    def stmt_helper_call(self):
        if not self.helpers or self.rng.random() < 0.4:
            self.decl_helper()
        hn, params, body, ptys = self.rng.choice(self.helpers)
        args = []
        for p, pt in zip(params, ptys):
            w, _ = TYPES[pt]
            bits = self.rng.randrange(1 << min(w, 62))
            p.value = wrap(bits, pt)
            args.append(str(bits) if pt == "i64" else f"# {pt} {bits}")
        self.phex(f"( {hn} {' '.join(args)} )", to_u64_bits(body.eval(), "i64"))

    def stmt_recursion(self):
        rn = self.fresh("rec")
        self.decls.append(
            f"@ {rn} i n i acc → i {{ ? <= n 0 {{ ^ acc }} {{ ^ ( {rn} - n 1 + acc n ) }} }}")
        n = self.rng.randint(0, 40)
        acc = 0
        m = n
        while m > 0:
            acc = wrap(acc + m, "i64")
            m -= 1
        self.phex(f"( {rn} {n} 0 )", to_u64_bits(acc, "i64"))

    def stmt_ternary(self):
        crender, truth = self.cond()
        ty = self.rng.choice(TYPE_NAMES)
        a = self.genx(ty, depth=2)
        b = self.genx(ty, depth=2)
        r = self.fresh("t")
        self.emit(f"    : {norm_ty(ty)} {r} ? {crender} {a.render()} {b.render()}")
        val = wrap((a if truth else b).eval(), ty)
        self.phex(r, to_u64_bits(val, ty))
        self.env.append(Var(ty, r, val))


def to_i64(bits, ty):
    """Widen a non-negative bit pattern of type ty to its i64 value."""
    return wrap(bits, ty) if TYPES[ty][1] else bits & ((1 << TYPES[ty][0]) - 1)


FEATURES = [
    ("int_let", 3), ("phex_expr", 2), ("struct", 2), ("enum_match", 3),
    ("while", 2), ("foreach", 2), ("closure", 2), ("defer", 2),
    ("drop_scope", 2), ("string", 2), ("vec", 1), ("helper_call", 2),
    ("recursion", 1), ("ternary", 2),
]


def build(seed, n_stmts, depth):
    rng = random.Random(seed)
    p = Prog(rng, depth)
    weighted = [name for name, w in FEATURES for _ in range(w)]
    # decide up front whether %Drop is in play so the decls exist
    p.drop_used = rng.random() < 0.6
    for _ in range(n_stmts):
        name = rng.choice(weighted)
        getattr(p, "stmt_" + name)()
    if p.drop_used:
        p.phex("g_drops", to_u64_bits(p.drops, "i64"))
    # defers fire LIFO after everything else
    for lit in reversed(p.deferred):
        p.expect_i64_bits(lit)
    return p


def emit_program(p):
    out = []
    out.append("// AUTO-GENERATED by tools/fuzz/genprog.py — structural differential probe.")
    out.append(gen.PRELUDE.split("\n", 1)[1])  # reuse imports + phex helpers
    out.append("$ `stdlib/core/vec.nu`")
    out.append("$ `stdlib/core/option.nu`")
    out.append("")
    if p.drop_used:
        out.append(": ~ i g_drops 0")
        out.append("")
        out.append(": DH { i tag }")
        out.append("% Drop ( DH ) { @ drop DH h → v { = g_drops + g_drops 1 } }")
        out.append("")
    out.extend(p.decls)
    out.append("")
    out.append("@ main → i {")
    out.extend(p.lines)
    out.append("    ^ 0")
    out.append("}")
    return "\n".join(out) + "\n"


def emit_oracle(p):
    return "\n".join(p.out) + ("\n" if p.out else "")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: genprog.py SEED [--oracle] [--stmts N] [--depth D]")
    seed = int(args[0])
    n_stmts = 14
    depth = 3
    if "--stmts" in args:
        n_stmts = int(args[args.index("--stmts") + 1])
    if "--depth" in args:
        depth = int(args[args.index("--depth") + 1])
    p = build(seed, n_stmts, depth)
    sys.stdout.write(emit_oracle(p) if "--oracle" in args else emit_program(p))


if __name__ == "__main__":
    main()
