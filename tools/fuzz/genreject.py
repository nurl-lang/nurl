#!/usr/bin/env python3
# tools/fuzz/genreject.py — the INVERSE oracle: programs the compiler MUST
# reject.
#
# gen.py and genprog.py ask "does this valid program compute the right
# answer?". This asks the opposite question, and it is the one a borrow
# checker is actually judged on: "does this INVALID program get caught?" A
# missed rejection is silent — the program compiles, runs, and corrupts the
# heap — so nothing but a deliberate hunt finds it.
#
# The shape of the hunt comes from what the two holes it found had in common:
# both were the SAME violation, in a context nobody had written it in. A
# double free is rejected at the top of a function, inside a `?` arm, a `~`
# loop, a foreach body, a bare block, a helper, a generic body, a trait
# method and a defer — and used to sail through a `??` arm and a closure
# body, where the checker was, for principled reasons, not looking. So the
# generator crosses a small set of violation CORES with a large set of
# CONTEXTS and nests them: one bug written every way the language allows.
#
# The oracle is a marker string, not an output: the program must fail to
# compile AND the diagnostic must be the one this violation deserves.
# Rejecting it for an unrelated reason (a syntax error the generator
# introduced, say) does not count as catching it.
#
# Usage:
#   genreject.py SEED             → the NURL program on stdout
#   genreject.py SEED --oracle    → the diagnostic marker it must produce
#   genreject.py SEED --depth N   → max nested contexts (default 3)
#
# A finding here is a program that COMPILES, or one rejected with the wrong
# diagnostic. Both mean the checker has a blind spot with a shape.

import sys
import random

# ── violation cores ───────────────────────────────────────────────────
#
# Each core is a body that is a definite ownership violation wherever it is
# placed, and the marker its diagnostic must contain. `n` makes every binding
# unique so nesting two cores, or a core beside a context's own bindings,
# cannot collide.


def core_alias_double_free(n):
    """Two names for one Vec, both freed."""
    return ([
        f": ( Vec i ) a{n} ( vec_new [i] )",
        f"( vec_push [i] a{n} 10 )",
        f": ( Vec i ) b{n} a{n}",
        f"( vec_free [i] a{n} )",
        f"( vec_free [i] b{n} )",
    ], "use of moved value")


def core_same_binding_double_free(n):
    """One name, freed twice."""
    return ([
        f": ( Vec i ) a{n} ( vec_new [i] )",
        f"( vec_free [i] a{n} )",
        f"( vec_free [i] a{n} )",
    ], "use of moved value")


def core_use_after_move(n):
    """Read through a name whose value has moved to another binding."""
    return ([
        f": ( Vec i ) a{n} ( vec_new [i] )",
        f": ( Vec i ) b{n} a{n}",
        f": i n{n} ( vec_len [i] a{n} )",
        f"( vec_free [i] b{n} )",
        f"( nurl_print ( nurl_str_int n{n} ) )",
    ], "use of moved value")


def core_string_double_free(n):
    """The same violation on a String handle rather than a Vec."""
    return ([
        f": String s{n} ( string_new )",
        f"( string_push_char s{n} 65 )",
        f": String t{n} s{n}",
        f"( string_free s{n} )",
        f"( string_free t{n} )",
    ], "use of moved value")


def core_loop_carried_free(n):
    """A free inside a loop body: the second iteration frees a dead handle."""
    return ([
        f": ( Vec i ) a{n} ( vec_new [i] )",
        f": ~ i k{n} 0",
        f"~ < k{n} 3 {{",
        f"    ( vec_free [i] a{n} )",
        f"    = k{n} + k{n} 1",
        "}",
    ], "use of moved value")


def core_iter_invalidation(n):
    """Growing a container while a `~` cursor is walking it."""
    return ([
        f": ( Vec i ) xs{n} ( vec_new [i] )",
        f"( vec_push [i] xs{n} 1 )",
        f"~ e{n} xs{n} {{ ( vec_push [i] xs{n} e{n} ) }}",
        f"( vec_free [i] xs{n} )",
    ], "while iterating over it")


CORES = [
    core_alias_double_free,
    core_same_binding_double_free,
    core_use_after_move,
    core_string_double_free,
    core_loop_carried_free,
    core_iter_invalidation,
]

# Cores that already contain a loop of their own. Nesting one inside a
# foreach would iterate a container it also mutates — a second, different
# violation whose diagnostic wins, and the oracle would be checking for the
# wrong marker. Keep the finding attributable to one cause.
LOOPY = {core_loop_carried_free, core_iter_invalidation}


def indent(lines, by="    "):
    return [by + l for l in lines]


# ── contexts ──────────────────────────────────────────────────────────
#
# A context wraps a body in one more layer of syntax without changing
# whether the body is a violation. Block contexts nest freely inside each
# other; function contexts open a new frame and may only appear outermost.


class Ctx:
    """(name, wrap) where wrap(body_lines, n, decls) -> lines. A context that
    needs a top-level declaration of its own appends it to `decls`."""

    def __init__(self, name, wrap, loopish=False, blocks_defer=False):
        self.name, self.wrap = name, wrap
        self.loopish = loopish            # introduces a `~` cursor
        self.blocks_defer = blocks_defer  # `;` is rejected inside this


def _if_then(body, n, decls):
    return ["? T {"] + indent(body) + ["} {}"]


def _if_else(body, n, decls):
    return [f"? > {n} 1000 {{}} {{"] + indent(body) + ["}"]


def _while(body, n, decls):
    return [f": ~ i w{n} 0", f"~ < w{n} 1 {{"] + indent(body) + \
           [f"    = w{n} + w{n} 1", "}"]


def _foreach(body, n, decls):
    return [f": [i fx{n} [ i | 1 ]", f"~ fe{n} fx{n} {{"] + indent(body) + ["}"]


def _bare_block(body, n, decls):
    return ["{"] + indent(body) + ["}"]


def _defer(body, n, decls):
    return ["; {"] + indent(body) + ["}"]


def _match_arm(body, n, decls):
    decls.append(f": | Sel{n} {{ SA{n} i  SB{n} i  SC{n} }}")
    return [
        f": Sel{n} sel{n} @ Sel{n} {{ SA{n} 1 }}",
        f"?? sel{n} {{",
        f"    SA{n} p{n} → {{",
    ] + indent(body, "        ") + [
        f"        p{n}",
        "    }",
        f"    SB{n} p{n} → p{n}",
        f"    SC{n}     → 0",
        "}",
    ]


BLOCK_CTXS = [
    Ctx("if-then", _if_then),
    Ctx("if-else", _if_else),
    Ctx("while", _while, loopish=True),
    Ctx("foreach", _foreach, loopish=True),
    Ctx("bare-block", _bare_block),
    Ctx("defer", _defer),
    Ctx("match-arm", _match_arm),
]

# Function contexts: each emits a top-level declaration holding the body and
# a call in main. `decl(body, n) -> (decl_lines, call_line, extra_decls)`.


def _fn_helper(body, n):
    return ([f"@ hf{n} → v {{"] + indent(body) + ["}"], f"( hf{n} )", [])


def _fn_generic(body, n):
    # `[A]`, not `[T]`: `T` is also the boolean literal, and monomorphisation
    # rewrites the type parameter through the body by whole word — a `? T { }`
    # anywhere inside would be rewritten into the type argument. The stdlib
    # names its type variables `A` for exactly this reason.
    return ([f"@ gf{n} [A] A x{n} → i {{"] + indent(body) +
            ["    ^ 0", "}"], f"( gf{n} [i] 1 )", [])


def _fn_closure(body, n):
    return ([], f"( cl{n} 1 )",
            [f"    : ( @ i i ) cl{n} \\ i cx{n} → i {{"] +
            indent(body, "        ") + [f"        ^ cx{n}", "    }"])


def _fn_trait(body, n):
    return ([
        f"% Tr{n} [A] {{ @ tm{n} A self → i }}",
        f": Ts{n} {{ i f{n} }}",
        f"% Tr{n} Ts{n} {{",
        f"    @ tm{n} Ts{n} self → i {{",
    ] + indent(body, "        ") + [
        f"        ^ . self f{n}",
        "    }",
        "}",
    ], f"( tm{n} @ Ts{n} {{ 1 }} )", [])


FN_CTXS = [
    Ctx("helper", _fn_helper),
    Ctx("generic", _fn_generic),
    Ctx("closure", _fn_closure, blocks_defer=True),
    Ctx("trait-method", _fn_trait),
]


def build(seed, depth):
    rng = random.Random(seed)
    core = rng.choice(CORES)
    n = rng.randrange(1000, 9999)
    body, marker = core(n)

    # Nest 0..depth-1 block contexts, innermost first.
    nblocks = rng.randint(0, max(0, depth - 1))
    picks = []
    for _ in range(nblocks):
        c = rng.choice(BLOCK_CTXS)
        if c.loopish and core in LOOPY:
            continue                      # see LOOPY
        picks.append(c)

    fn = rng.choice(FN_CTXS) if rng.random() < 0.55 else None
    if fn is not None and fn.blocks_defer:
        picks = [c for c in picks if c.name != "defer"]

    decls = []
    for c in picks:
        n += 1
        body = c.wrap(body, n, decls)

    if fn is None:
        main_body = indent(body)
    else:
        d, call, inline = fn.wrap(body, n + 1)
        decls += d
        main_body = inline + indent([call])

    out = [
        "// AUTO-GENERATED by tools/fuzz/genreject.py — INVERSE oracle.",
        "// This program is INVALID on purpose. The compiler must reject it,",
        f"// with a diagnostic containing: {marker}",
        "$ `stdlib/core/string.nu`",
        "$ `stdlib/core/vec.nu`",
        "",
    ]
    out += decls
    out += ["", "@ main → i {"] + main_body + ["    ^ 0", "}"]
    return "\n".join(out) + "\n", marker



def main():
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: genreject.py SEED [--oracle] [--depth N]")
    seed = int(args[0])
    depth = 3
    if "--depth" in args:
        depth = int(args[args.index("--depth") + 1])
    prog, marker = build(seed, depth)
    sys.stdout.write(marker + "\n" if "--oracle" in args else prog)


if __name__ == "__main__":
    main()
