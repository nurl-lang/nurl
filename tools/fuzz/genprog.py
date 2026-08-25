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
    def __init__(self, rng, depth, selfcheck=False):
        self.rng = rng
        self.depth = depth
        self.selfcheck = selfcheck
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
        self.once = set()         # one-shot declaration blocks already emitted
        self.traits = []          # (trait, method, default, [(struct, fty, field)])

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

    def chk(self, node_render, value_bits, cast=True):
        """The rendered observation call for one value.

        Normal mode prints the 64-bit pattern and `fuzz.sh` compares the
        whole stdout against the separately-generated oracle. Self-check mode
        carries the expectation INSIDE the program as a 16-hex-digit string
        literal and compares there — which is what makes the reducer sound:
        deleting a line cannot invalidate the checks that remain, the way
        deleting a line would desynchronise an external oracle."""
        bits = value_bits & ((1 << 64) - 1)
        wide = f"# i64 {node_render}" if cast else node_render
        if self.selfcheck:
            return f"( fzchk {wide} `{bits:016x}` )"
        return f"( phex {wide} )"

    def phex(self, node_render, value_bits):
        self.emit("    " + self.chk(node_render, value_bits))
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

            # optional guarded arm. Guard leaves carry the payload's
            # DECLARED type — the in-program binding is that type, and
            # the compiler (correctly) rejects mixed-width operands.
            if is_target and ptypes and self.rng.random() < 0.5:
                guard_leaves = [MutVar(pt, pn, wrap(raw, pt)) for pn, raw, pt in
                                zip(pnames, raws, ptypes) if pt not in ("f", "s")]
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

    def stmt_nested_closure(self):
        """A closure literal inside a closure literal, and a closure that owns
        a `% Drop` value of its own while one is live in the frame around it.

        The lifted-function boundary is where ownership bookkeeping goes
        wrong: the outer frame's rosters were visible inside the closure body
        until 2026-08-26, so its `^` dropped values belonging to its caller.
        Nesting asks the same question one level deeper, and the `% Drop`
        variant asks whether the closure's OWN values still get released."""
        f = self.fresh("nc")
        inner = self.fresh("ni")
        k = self.rng.randrange(1 << 20)
        m = self.rng.randint(2, 7)
        own_drop = self.drop_used and self.rng.random() < 0.5
        body = [f"        : ( @ i i ) {inner} \\ i y → i {{ ^ * y {m} }}"]
        if own_drop:
            h = self.fresh("nh")
            body.append(f"        : DH {h} @ DH {{ x }}")
        body.append(f"        ^ + ( {inner} x ) {k}")
        self.emit(f"    : ( @ i i ) {f} \\ i x → i {{")
        self.lines.extend(body)
        self.emit("    }")
        for _ in range(self.rng.randint(1, 2)):
            arg = self.rng.randrange(1 << 24)
            self.phex(f"( {f} {arg} )", to_u64_bits(wrap(arg * m + k, "i64"), "i64"))
            if own_drop:
                self.drops += 1

    def stmt_early_return(self):
        """A helper that returns from INSIDE a loop with owned values live.

        `^` is not the block's normal exit: it skips the code the
        fall-through would have run, so the compiler has to emit the whole
        drop sequence — for the loop body's values AND the function's — at
        the return. One value is created before the loop and one per
        iteration, so the oracle knows exactly how many destructors must
        have fired by the time control leaves."""
        if not self.drop_used:
            self.stmt_helper_call()          # nothing to count without % Drop
            return
        fn = self.fresh("erf")
        n = self.rng.randint(2, 7)
        thr = self.rng.randint(1, n + 1)     # > n means "never taken"
        bonus = self.rng.randrange(1 << 16)
        self.decls += [
            f"@ {fn} i seed → i {{",
            "    : DH outer @ DH { seed }",
            "    : ~ i acc seed",
            "    : ~ i k 0",
            f"    ~ < k {n} {{",
            "        = k + k 1",
            "        : DH inner @ DH { k }",
            f"        ? == k {thr} {{ ^ + acc {bonus} }} {{}}",
            "        = acc + acc k",
            "    }",
            "    ^ acc",
            "}",
        ]
        seed = self.rng.randrange(1 << 20)
        acc = seed
        fired = 1                            # `outer`, on whichever exit
        for k in range(1, n + 1):
            fired += 1                       # `inner`, this iteration
            if k == thr:
                acc = wrap(acc + bonus, "i64")
                break
            acc = wrap(acc + k, "i64")
        self.drops += fired
        # Bind before observing: the call has SIDE EFFECTS (each invocation
        # fires its destructors), so a leaf that re-renders as the call would
        # run it again every time an expression tree picked it up and the
        # drop count would stop matching.
        rv = self.fresh("er")
        self.emit(f"    : i {rv} ( {fn} {seed} )")
        self.phex(rv, to_u64_bits(acc, "i64"))
        self.env.append(Var("i64", rv, acc))

    def stmt_defer(self):
        lit = self.rng.randrange(1 << 32)
        call = self.chk(str(lit), lit, cast=False)
        if self.rng.random() < 0.6:
            self.emit(f"    ; {{ {call} }}")
            self.deferred.append(lit)
        else:
            # defer inside a conditional arm: armed iff the arm runs
            crender, truth = self.cond()
            self.emit(f"    ? {crender} {{ ; {{ {call} }} }} {{}}")
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

    # ── generics ─────────────────────────────────────────────────

    def decl_generics(self):
        """Generic functions + a generic struct, declared once per program.

        `Q7` is a CONCRETE struct whose name is deliberately spelled like a
        type parameter. Instantiation used to be decided by spelling, so
        `( GBox Q7 )` was skipped as "still abstract" and the program died
        on a `%GBox__Q7` nothing defined — a failure that depended on the
        length of the user's own type name (fixed 2026-08-25)."""
        if "gen" in self.once:
            return
        self.once.add("gen")
        self.decls += [
            ": Q7 { i8 qa  u16 qb }",
            ": GBox [T] { T slot }",
            "@ g_id [T] T x → T { ^ x }",
            "@ g_add [T] T a T b → T { ^ + a b }",
            "@ g_div [T] T a T b → T { ^ / a b }",
            "@ g_shr [T] T a T b → T { ^ >> a b }",
            "@ g_box [T] T x → ( GBox T ) { ^ @ ( GBox T ) { x } }",
        ]

    def stmt_generic(self):
        """A generic call or generic-struct instantiation at a random type.

        The type argument decides signedness AFTER monomorphisation, which
        is the interesting part: `g_div` must pick sdiv for `[i8]` and udiv
        for `[u]` from the same template body."""
        self.decl_generics()
        kind = self.rng.choice(["id", "add", "div", "shr", "box", "qbox"])
        if kind == "qbox":
            a = self.rng.randrange(1 << 8)
            b = self.rng.randrange(1 << 16)
            gb = self.fresh("gq")
            self.emit(f"    : ( GBox Q7 ) {gb} "
                      f"( g_box [Q7] @ Q7 {{ # i8 {a} # u16 {b} }} )")
            self.phex(f". . {gb} slot qa", to_u64_bits(wrap(a, "i8"), "i8"))
            self.phex(f". . {gb} slot qb", to_u64_bits(wrap(b, "u16"), "u16"))
            return
        ty = self.rng.choice(INT_PAYLOADS)
        w, _signed = TYPES[ty]
        a = Lit(ty, self.rng.randrange(1 << min(w, 62)))
        if kind == "id":
            self.phex(f"( g_id [{ty}] {a.render()} )", to_u64_bits(a.eval(), ty))
            return
        if kind == "box":
            gb = self.fresh("gb")
            self.emit(f"    : ( GBox {ty} ) {gb} ( g_box [{ty}] {a.render()} )")
            self.phex(f". {gb} slot", to_u64_bits(a.eval(), ty))
            self.env.append(gen.FieldRead(ty, gb, "slot", a.eval()))
            return
        if kind == "div":
            # A small POSITIVE divisor in every type: no /0, and no
            # INT_MIN/-1 (the one signed division that traps).
            b = Lit(ty, self.rng.randint(1, min(9, (1 << w) - 1)))
        elif kind == "shr":
            b = Lit(ty, self.rng.randrange(w))       # shift amount < width
        else:
            b = Lit(ty, self.rng.randrange(1 << min(w, 62)))
        op = {"add": "+", "div": "/", "shr": ">>"}[kind]
        node = Bin(ty, op, a, b)
        self.phex(f"( g_{kind} [{ty}] {a.render()} {b.render()} )",
                  to_u64_bits(node.eval(), ty))

    # ── option / result ──────────────────────────────────────────

    def stmt_option(self):
        """`?T` construction, `??` destructure, and a stdlib combinator."""
        fn = self.fresh("optf")
        thr = self.rng.randrange(1 << 16)
        self.decls.append(
            f"@ {fn} i n → ?i {{ ? > n {thr} "
            f"{{ ^ @ ?i {{ T * n 3 }} }} {{ ^ @ ?i {{ F 0 }} }} }}")
        arg = self.rng.randrange(1 << 17)
        alt = self.rng.randrange(1 << 20)
        ov = self.fresh("ov")
        bnd = self.fresh("ob")
        res = self.fresh("orv")
        self.emit(f"    : ?i {ov} ( {fn} {arg} )")
        self.emit(f"    : i {res} ?? {ov} {{")
        self.emit(f"        T {bnd} → * {bnd} 2")
        self.emit(f"        F      → {alt}")
        self.emit("    }")
        val = wrap(arg * 3 * 2, "i64") if arg > thr else alt
        self.phex(res, to_u64_bits(val, "i64"))
        self.env.append(Var("i64", res, val))
        d = self.rng.randrange(1 << 20)
        got = wrap(arg * 3, "i64") if arg > thr else d
        self.phex(f"( opt_unwrap_or [i] ( {fn} {arg} ) {d} )",
                  to_u64_bits(got, "i64"))

    def stmt_result(self):
        """`!T E` through a `\\` try-propagation chain, then destructured.

        The propagating wrapper is the point: the Err path has to return
        early out of the middle of a function whose own Ok payload is built
        afterwards."""
        fn = self.fresh("resf")
        use = self.fresh("resu")
        thr = self.rng.randrange(1 << 16)
        k = self.rng.randrange(1 << 10)
        self.decls.append(
            f"@ {fn} i n → !i i {{ ? > n {thr} "
            f"{{ ^ @ !i i {{ T * n 2 }} }} {{ ^ @ !i i {{ F - 0 n }} }} }}")
        self.decls.append(
            f"@ {use} i n → !i i {{ : i q \\ ( {fn} n )  ^ @ !i i {{ T + q {k} }} }}")
        arg = self.rng.randrange(1 << 17)
        rv = self.fresh("rv")
        ok = self.fresh("rok")
        er = self.fresh("rer")
        out = self.fresh("rout")
        self.emit(f"    : !i i {rv} ( {use} {arg} )")
        self.emit(f"    : i {out} ?? {rv} {{")
        self.emit(f"        T {ok} → {ok}")
        self.emit(f"        F {er} → {er}")
        self.emit("    }")
        val = wrap(arg * 2 + k, "i64") if arg > thr else wrap(-arg, "i64")
        self.phex(out, to_u64_bits(val, "i64"))
        self.env.append(Var("i64", out, val))

    # ── traits ───────────────────────────────────────────────────

    def decl_trait(self):
        """A trait with one required method and one default, implemented for
        two or three structs of different field types, plus a bounded
        generic that reaches the default through the bound."""
        n = len(self.traits) + 1
        tr, m1, m2 = f"Tr{n}", f"tm{n}base", f"tm{n}scaled"
        impls = []
        self.decls.append(f"% {tr} [T] {{")
        self.decls.append(f"    @ {m1} T self → i")
        self.decls.append(f"    @ {m2} T self i k → i {{ ^ * ( {m1} self ) k }}")
        self.decls.append("}")
        for j in range(self.rng.randint(2, 3)):
            sname, fty, fld = f"{tr}S{j}", self.rng.choice(INT_PAYLOADS), f"fv{j}"
            self.decls.append(f": {sname} {{ {fty} {fld} }}")
            impls.append((sname, fty, fld))
        for sname, fty, fld in impls:
            read = f". self {fld}" if fty == "i64" else f"# i . self {fld}"
            self.decls.append(
                f"% {tr} {sname} {{ @ {m1} {sname} self → i {{ ^ {read} }} }}")
        self.decls.append(
            f"@ {tr}_via [X: {tr}] X x i k → i {{ ^ ( {m2} x k ) }}")
        self.traits.append((tr, m1, m2, impls))

    def stmt_trait(self):
        if not self.traits or self.rng.random() < 0.5:
            self.decl_trait()
        tr, m1, m2, impls = self.rng.choice(self.traits)
        sname, fty, _fld = self.rng.choice(impls)
        w, _ = TYPES[fty]
        val = wrap(self.rng.randrange(1 << min(w, 62)), fty)
        inst = self.fresh("ti")
        self.emit(f"    : {sname} {inst} @ {sname} {{ # {fty} {val & ((1 << w) - 1)} }}")
        base = to_u64_bits(val, fty)              # widened per the field's sign
        self.phex(f"( {m1} {inst} )", base)
        k = self.rng.randrange(1 << 12)
        widened = wrap(val, fty) if TYPES[fty][1] else val & ((1 << w) - 1)
        scaled = to_u64_bits(wrap(widened * k, "i64"), "i64")
        self.phex(f"( {m2} {inst} {k} )", scaled)          # default method
        self.phex(f"( {tr}_via [{sname}] {inst} {k} )", scaled)  # via the bound

    # ── nested aggregates ────────────────────────────────────────

    def decl_nested(self):
        if "nest" in self.once:
            return
        self.once.add("nest")
        self.decls += [
            ": NIn { i8 nx  u16 ny }",
            ": NMid { NIn nm  i32 nk }",
            ": NOut { NIn ninner  i32 nz }",
            ": NTop { NMid nt  i64 nw }",
            ": | NShape {",
            "    NPt NIn",
            "    NSeg NIn NIn",
            "    NNil",
            "}",
        ]

    def _nin(self):
        """One `NIn` literal + its (nx, ny) oracle values."""
        a, b = self.rng.randrange(1 << 8), self.rng.randrange(1 << 16)
        return f"@ NIn {{ # i8 {a} # u16 {b} }}", wrap(a, "i8"), b & 0xffff

    def stmt_nested_store(self):
        """Three levels of aggregate, WRITTEN at every depth.

        Reading a nested path always worked; writing one was rejected until
        2026-08-26, because the object of a nested path is a by-value
        register rather than a binding with an alloca. Each write is read
        back, and its neighbours are read back too — a store that lands one
        field over is exactly what a GEP chain gets wrong."""
        self.decl_nested()
        a0, b0 = self.rng.randrange(1 << 8), self.rng.randrange(1 << 16)
        k0 = self.rng.randrange(1 << 32)
        w0 = self.rng.randrange(1 << 40)
        t = self.fresh("nt")
        self.emit(f"    : ~ NTop {t} @ NTop {{ @ NMid {{ "
                  f"@ NIn {{ # i8 {a0} # u16 {b0} }} # i32 {k0} }} {w0} }}")
        vals = {"nx": wrap(a0, "i8"), "ny": b0 & 0xffff,
                "nk": wrap(k0, "i32"), "nw": wrap(w0, "i64")}
        paths = {"nx": f". . . {t} nt nm nx", "ny": f". . . {t} nt nm ny",
                 "nk": f". . {t} nt nk", "nw": f". {t} nw"}
        types = {"nx": "i8", "ny": "u16", "nk": "i32", "nw": "i64"}
        for _ in range(self.rng.randint(1, 4)):
            f = self.rng.choice(["nx", "ny", "nk", "nw"])
            ty = types[f]
            w, _signed = TYPES[ty]
            bits = self.rng.randrange(1 << min(w, 62))
            self.emit(f"    = {paths[f]} # {ty} {bits}")
            vals[f] = wrap(bits, ty)
        for f in ["nx", "ny", "nk", "nw"]:
            self.phex(paths[f], to_u64_bits(vals[f], types[f]))
        self.env.append(Var("i64", paths["nw"], vals["nw"]))

    def stmt_nested(self):
        """A struct inside a struct, and a struct as an enum payload —
        aggregates whose members are themselves aggregates, read through a
        two-hop `. . o inner field` path and through match bindings."""
        self.decl_nested()
        lit, nx, ny = self._nin()
        c = self.rng.randrange(1 << 32)
        o = self.fresh("no")
        self.emit(f"    : NOut {o} @ NOut {{ {lit} # i32 {c} }}")
        self.phex(f". . {o} ninner nx", to_u64_bits(nx, "i8"))
        self.phex(f". . {o} ninner ny", to_u64_bits(ny, "u16"))
        self.phex(f". {o} nz", to_u64_bits(wrap(c, "i32"), "i32"))
        self.env.append(Var("i64", f"# i . {o} nz", wrap(c, "i32")))

        which = self.rng.choice(["NPt", "NSeg", "NNil"])
        ev = self.fresh("ns")
        if which == "NPt":
            l1, x1, y1 = self._nin()
            self.emit(f"    : NShape {ev} @ NShape {{ NPt {l1} }}")
            val = wrap(x1 + y1, "i64")
        elif which == "NSeg":
            l1, x1, y1 = self._nin()
            l2, x2, y2 = self._nin()
            self.emit(f"    : NShape {ev} @ NShape {{ NSeg {l1} {l2} }}")
            val = wrap(x1 + y1 + x2 + y2, "i64")
        else:
            self.emit(f"    : NShape {ev} @ NShape {{ NNil }}")
            val = 0
        rv = self.fresh("nm")
        self.emit(f"    : i {rv} ?? {ev} {{")
        self.emit("        NPt np1        → + # i . np1 nx # i . np1 ny")
        self.emit("        NSeg np1 np2   → + + # i . np1 nx # i . np1 ny "
                  "+ # i . np2 nx # i . np2 ny")
        self.emit("        NNil           → 0")
        self.emit("    }")
        self.phex(rv, to_u64_bits(val, "i64"))
        self.env.append(Var("i64", rv, val))

    # ── loop control ─────────────────────────────────────────────

    def stmt_loopctl(self):
        """A loop whose body jumps: `continue` on one predicate, `break` on
        another, over both loop forms. A `% Drop` value built at the top of
        the body must be released exactly once on every path out — the
        jump skips the block's own cleanup, so the jump has to emit it."""
        n = self.rng.randint(2, 9)
        skip = self.rng.randint(1, 4)
        stop = self.rng.randint(1, n + 2)
        acc = self.fresh("lacc")
        drop_here = self.drop_used and self.rng.random() < 0.5
        self.emit(f"    : ~ i {acc} 0")
        if self.rng.random() < 0.5:
            xs = self.fresh("lxs")
            self.emit(f"    : [i {xs} [ i | {' '.join(str(e) for e in range(1, n + 1))} ]")
            var = self.fresh("lel")
            self.emit(f"    ~ {var} {xs} {{")
        else:
            var = self.fresh("lk")
            self.emit(f"    : ~ i {var} 0")
            self.emit(f"    ~ < {var} {n} {{")
            self.emit(f"        = {var} + {var} 1")
        if drop_here:
            h = self.fresh("lh")
            self.emit(f"        : DH {h} @ DH {{ {var} }}")
        self.emit(f"        ? == % {var} {skip} 0 {{ continue }} {{}}")
        self.emit(f"        ? == {var} {stop} {{ break }} {{}}")
        self.emit(f"        = {acc} + {acc} {var}")
        self.emit("    }")
        total = 0
        for k in range(1, n + 1):
            if drop_here:
                self.drops += 1
            if k % skip == 0:
                continue
            if k == stop:
                break
            total = wrap(total + k, "i64")
        self.phex(acc, to_u64_bits(total, "i64"))
        self.env.append(Var("i64", acc, total))

    # ── containers of aggregates ─────────────────────────────────

    def stmt_vec_struct(self):
        """A Vec and a slice whose ELEMENT is a struct — the generic
        instantiation, the element-sized GEP, and the by-value load out of
        `vec_get`'s `?A` all at once."""
        self.decl_generics()
        items = [(self.rng.randrange(1 << 8), self.rng.randrange(1 << 16))
                 for _ in range(self.rng.randint(1, 4))]
        total = 0
        for a, b in items:
            total = wrap(total + wrap(a, "i8") + (b & 0xffff), "i64")

        if self.rng.random() < 0.5:
            vv = self.fresh("vq")
            self.emit(f"    : ( Vec Q7 ) {vv} ( vec_new [Q7] )")
            for a, b in items:
                self.emit(f"    ( vec_push [Q7] {vv} @ Q7 {{ # i8 {a} # u16 {b} }} )")
            self.phex(f"( vec_len [Q7] {vv} )", len(items))
            sm, j, e = self.fresh("vs"), self.fresh("vj"), self.fresh("ve")
            self.emit(f"    : ~ i {sm} 0")
            self.emit(f"    : ~ i {j} 0")
            self.emit(f"    ~ < {j} ( vec_len [Q7] {vv} ) {{")
            self.emit(f"        : Q7 {e} ( opt_unwrap [Q7] ( vec_get [Q7] {vv} {j} ) )")
            self.emit(f"        = {sm} + {sm} + # i . {e} qa # i . {e} qb")
            self.emit(f"        = {j} + {j} 1")
            self.emit("    }")
            self.emit(f"    ( vec_free [Q7] {vv} )")
        else:
            xs, sm, e = self.fresh("sq"), self.fresh("ss"), self.fresh("se")
            lits = " ".join(f"@ Q7 {{ # i8 {a} # u16 {b} }}" for a, b in items)
            self.emit(f"    : [Q7 {xs} [ Q7 | {lits} ]")
            self.emit(f"    : ~ i {sm} 0")
            self.emit(f"    ~ {e} {xs} {{ = {sm} + {sm} + # i . {e} qa # i . {e} qb }}")
        self.phex(sm, to_u64_bits(total, "i64"))
        self.env.append(Var("i64", sm, total))


def to_i64(bits, ty):
    """Widen a non-negative bit pattern of type ty to its i64 value."""
    return wrap(bits, ty) if TYPES[ty][1] else bits & ((1 << TYPES[ty][0]) - 1)


FEATURES = [
    ("int_let", 3), ("phex_expr", 2), ("struct", 2), ("enum_match", 3),
    ("while", 2), ("foreach", 2), ("closure", 2), ("defer", 2),
    ("drop_scope", 2), ("string", 2), ("vec", 1), ("helper_call", 2),
    ("recursion", 1), ("ternary", 2),
    # The second wave: the surface the first wave never reached.
    ("generic", 3), ("option", 2), ("result", 2), ("trait", 2),
    ("nested", 3), ("loopctl", 2), ("vec_struct", 2),
    ("nested_closure", 2), ("early_return", 2), ("nested_store", 2),
]


SELFCHECK_PRELUDE = """\
// Self-check mode: the program carries its own expectations, so a reducer
// may delete any line without desynchronising the rest. Exit status is
// nonzero iff some observation disagreed with what the generator computed.
: ~ i g_fail 0

@ fzchk i v s want → v {
    : String hs ( string_new )
    : ~ i k 15
    ~ >= k 0 {
        ( string_push_char hs ( hexd & 15 >> v * k 4 ) )
        = k - k 1
    }
    ? ( nurl_str_eq ( string_data hs ) want ) {} {
        = g_fail + g_fail 1
        ( nurl_print `MISMATCH got=` ) ( nurl_print ( string_data hs ) )
        ( nurl_print ` want=` ) ( nurl_print want ) ( nurl_print `\\n` )
    }
    ( string_free hs )
}
"""


def build(seed, n_stmts, depth, selfcheck=False):
    rng = random.Random(seed)
    p = Prog(rng, depth, selfcheck)
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
    if p.selfcheck:
        out.append(SELFCHECK_PRELUDE)
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
    out.append("    ^ ? != g_fail 0 1 0" if p.selfcheck else "    ^ 0")
    out.append("}")
    return "\n".join(out) + "\n"


def emit_oracle(p):
    return "\n".join(p.out) + ("\n" if p.out else "")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: genprog.py SEED [--oracle] [--selfcheck] "
                 "[--stmts N] [--depth D]")
    seed = int(args[0])
    n_stmts = 14
    depth = 3
    if "--stmts" in args:
        n_stmts = int(args[args.index("--stmts") + 1])
    if "--depth" in args:
        depth = int(args[args.index("--depth") + 1])
    p = build(seed, n_stmts, depth, selfcheck="--selfcheck" in args)
    sys.stdout.write(emit_oracle(p) if "--oracle" in args else emit_program(p))


if __name__ == "__main__":
    main()
