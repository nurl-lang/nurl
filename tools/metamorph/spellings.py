#!/usr/bin/env python3
# tools/metamorph/spellings.py — metamorphic coverage harness for nurlc's
# diagnostics.
#
# The fuzzers in tools/fuzz ask "does this program compute the right
# value?" — a differential question against an oracle. This asks a
# different one, on the axis where nurlc's real bugs have actually lived:
#
#     the same semantic situation, written N ways, must get the SAME
#     verdict from the checker.
#
# Four consecutive fixes in August 2026 were all one shape — the checker
# asked its question at one syntactic spelling and missed the others:
#
#   #898  a wrapper that frees its parameter was a sink … unless generic
#   #899  a handle got a second name via `: T b a` … but not via
#         `?` / `??` / `=` / a callee returning its argument
#   #901  an option payload was type-checked … unless the slot was
#         i64-shaped, where a pointer was silently ptrtoint'd into it
#   #902  a thread closure mutating shared Arc contents was caught …
#         unless the mutation sat one call deep in a helper
#
# Every one of them is a disagreement between spellings of one situation,
# and every one would have been caught here automatically.
#
# HOW A FINDING IS JUDGED. A disagreement alone is not proof of a
# compiler bug: the template may simply not express the same situation.
# So a spelling that is ACCEPTED where its class says REJECT is escalated
# — rebuilt with --no-borrowck and run under AddressSanitizer. If it
# crashes or leaks, the program really is broken and the checker really
# missed it. If it runs clean, the finding is reported as UNCONFIRMED and
# the template is the thing to look at. That step is what keeps this from
# being a generator of plausible-looking noise.
#
# Usage:
#   tools/metamorph/spellings.py                 # report, gate on regressions
#   tools/metamorph/spellings.py --verify        # + ASan-confirm every gap
#   tools/metamorph/spellings.py --class NAME    # one class only
#   tools/metamorph/spellings.py --update-known  # re-baseline KNOWN_GAPS
#
# Exit: 0 = no NEW gap · 1 = a new gap (or a control regressed) · 2 = setup

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
NURLC = ROOT / "build" / "nurlc"
RUNTIME = ROOT / "stdlib" / "runtime.native.o"
KNOWN = pathlib.Path(__file__).resolve().parent / "known_gaps.json"

# ── Verdicts ────────────────────────────────────────────────────────────
# What the checker said, normalised so spellings are comparable.
ACCEPT = "accept"           # compiles clean under both modes
WARN = "warn"               # compiles, but the checker says something
REJECT_STRICT = "strict"    # only --strict-borrowck rejects it
REJECT_DEFAULT = "reject"   # the default checker rejects it

# A class states the WEAKEST verdict it will accept. `reject` is stronger
# than `strict` is stronger than `accept`; a spelling that does better
# than its class demands is fine and is reported, not failed.
STRENGTH = {ACCEPT: 0, WARN: 1, REJECT_STRICT: 2, REJECT_DEFAULT: 3}
# INVALID never satisfies a class; it is a template bug.
STRENGTH_INVALID = -1

PRELUDE_VEC = "$ `stdlib/core/vec.nu`\n"
PRELUDE_ARC = "$ `stdlib/std/arc.nu`\n$ `stdlib/std/thread.nu`\n$ `stdlib/core/vec.nu`\n"
PRELUDE_THREAD = "$ `stdlib/std/thread.nu`\n"

# The escape classes all need one thing: a value that IS a reference into
# the current frame. In NURL that is a closure capturing a `: ~` binding
# BY POINTER — `f` below points at `caller`'s own `c` alloca, so anything
# that outlives `caller` and still holds `f` is holding a dead frame.
ESC_CTR = ": Counter { i n i max }\n"
ESC_SLOT = ": Slot { ( @ v ) cb }\n"
ESC_MKREF = ("    : ~ Counter c @ Counter { 0 10 }\n"
             "    : ( @ v ) f \\ → v { = . c n + . c n 1 }\n")


def prog(body, prelude=PRELUDE_VEC, extra=""):
    return f"{prelude}{extra}\n@ main → i {{\n{body}\n    ^ 0\n}}\n"


# ── The classes ─────────────────────────────────────────────────────────

CLASSES = [
    {
        "name": "handle-second-name",
        "severity": "memory-unsafety",
        "doc": "A heap handle acquires a SECOND name and both names are "
               "freed. However the second name is spelled, exactly one "
               "owner may free the buffer, so every spelling here is a "
               "double free.",
        "expect": REJECT_STRICT,
        "expect_msg": ["use of moved value", "may already be freed"],
        "spellings": {
            # Covered as of #899.
            "let-alias": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) b a\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "assign": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ~ ( Vec i ) b ( vec_new [i] )\n"
                "    ( vec_free [i] b )\n"
                "    = b a\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "ternary-definite": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    : ( Vec i ) b ? > c 0 a a\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "ternary-maybe": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    : ( Vec i ) b ? > c 0 a ( vec_new [i] )\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "match": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    : ( Vec i ) b ?? c { 1 → a _ → ( vec_new [i] ) }\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "callee-returns-arg": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) b ( pick a 1 )\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )",
                extra="@ pick ( Vec i ) a i f → ( Vec i ) "
                      "{ ^ ? > f 0 a ( vec_new [i] ) }\n"),
            "wrapper-plain": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( dispose a )\n"
                "    ( dispose a )",
                extra="@ dispose ( Vec i ) v → v { ( vec_free [i] v ) }\n"),
            "wrapper-generic": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( dispose [i] a )\n"
                "    ( dispose [i] a )",
                extra="@ dispose [T] ( Vec T ) v → v { ( vec_free [T] v ) }\n"),
            # Probes BEYOND what the four fixes covered. These are the
            # point of the harness: same situation, spellings nobody has
            # pointed the checker at yet.
            "ternary-nested": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    : ( Vec i ) b ? > c 0 ? > c 0 a ( vec_new [i] ) ( vec_new [i] )\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )"),
            "wrapper-two-deep": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( outer a )\n"
                "    ( outer a )",
                extra="@ inner ( Vec i ) v → v { ( vec_free [i] v ) }\n"
                      "@ outer ( Vec i ) v → v { ( inner v ) }\n"),
            "struct-field": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : Holder h @ Holder { a }\n"
                "    ( vec_free [i] . h v )\n"
                "    ( vec_free [i] a )",
                extra=": Holder { ( Vec i ) v }\n"),
            "closure-capture": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( @ v ) f \\ → v { ( vec_free [i] a ) }\n"
                "    ( f )\n"
                "    ( vec_free [i] a )"),
        },
    },
    {
        "name": "option-payload-type",
        "severity": "silent-wrong-value",
        "doc": "The payload of an option/result literal is not the type "
               "the option was declared over. Field 1 carries T's real "
               "type in both forms, so none of these has anywhere to go.",
        "expect": REJECT_DEFAULT,
        # Either site is a correct catch: the option-literal check, or the
        # general binding type-check the value hits on its way in. What
        # must NOT count is a syntax error in the template.
        "expect_msg": ["payload of this option/result literal",
                       "cannot initialise / assign a binding"],
        "spellings": {
            "int-into-string": prog("    : ?s o @ ?s { T 42 }\n"
                                    "    ?? o { T v → ^ 1  F → ^ 0 }", prelude=""),
            "string-into-int": prog("    : ?i o @ ?i { T `x` }\n"
                                    "    ?? o { T v → ^ v  F → ^ 0 }", prelude=""),
            "float-into-int": prog("    : ?i o @ ?i { T 1.5 }\n"
                                   "    ?? o { T v → ^ v  F → ^ 0 }", prelude=""),
            "int-into-float": prog("    : ?f o @ ?f { T 3 }\n"
                                   "    ?? o { T v → ^ 1  F → ^ 0 }", prelude=""),
            "string-into-result-int": prog("    : !i s o @ !i s { T `x` }\n"
                                           "    ?? o { T v → ^ v  F e → ^ 0 }", prelude=""),
            "vec-into-int": prog("    : ( Vec i ) d ( vec_new [i] )\n"
                                 "    : ?i o @ ?i { T d }\n"
                                 "    ?? o { T v → ^ v  F → ^ 0 }"),
        },
    },
    {
        "name": "arc-shared-mutation",
        "severity": "memory-unsafety",
        "doc": "A thread closure mutates the CONTENTS of an Arc it did "
               "not create, with no lock held. Arc makes the refcount "
               "atomic and nothing else.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["thread_spawn closure"],
        "spellings": {
            "inline-push": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( @ v ) w \\ → v {\n"
                "        : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "        ( vec_push [i] v 1 )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC),
            "helper-push": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( @ v ) w \\ → v { ( push_it a ) }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC,
                extra="@ push_it ( Arc ( Vec i ) ) a → v {\n"
                      "    : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                      "    ( vec_push [i] v 1 )\n}\n"),
            "helper-two-deep": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( @ v ) w \\ → v { ( outer_push a ) }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC,
                extra="@ inner_push ( Arc ( Vec i ) ) a → v {\n"
                      "    : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                      "    ( vec_push [i] v 1 )\n}\n"
                      "@ outer_push ( Arc ( Vec i ) ) a → v { ( inner_push a ) }\n"),
            "vec-set": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    ( vec_push [i] d 0 )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( @ v ) w \\ → v {\n"
                "        : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "        ( vec_set [i] v 0 9 )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC),
            "unlock-before-mutate": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : Mutex m ( mutex_new )\n"
                "    : ( @ v ) w \\ → v {\n"
                "        ( mutex_lock m )\n"
                "        ( mutex_unlock m )\n"
                "        : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "        ( vec_push [i] v 1 )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }\n"
                "    ( mutex_free m )",
                prelude=PRELUDE_ARC),
        },
    },
    {
        "name": "use-after-free",
        "severity": "memory-unsafety",
        "doc": "A handle is READ after it has been freed. Distinct from "
               "the double-free class: nothing frees twice here, the "
               "buffer is simply gone by the time it is used.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["use of moved value", "may already be freed"],
        "spellings": {
            "read-len": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( vec_free [i] a )\n"
                "    ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )"),
            "read-after-wrapper": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( dispose a )\n"
                "    ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )",
                extra="@ dispose ( Vec i ) v → v { ( vec_free [i] v ) }\n"),
            "read-after-generic-wrapper": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( dispose [i] a )\n"
                "    ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )",
                extra="@ dispose [T] ( Vec T ) v → v { ( vec_free [T] v ) }\n"),
            "push-after-free": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( vec_free [i] a )\n"
                "    ( vec_push [i] a 1 )"),
            "read-in-loop-after-free": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    ( vec_free [i] a )\n"
                "    : ~ i k 0\n"
                "    ~ < k 2 { ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) ) = k + k 1 }"),
            "read-through-alias": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) b a\n"
                "    ( vec_free [i] b )\n"
                "    ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )"),
        },
    },
    {
        "name": "forward-callee-move",
        "severity": "memory-unsafety",
        "doc": "The MOVE half of the interprocedural summaries — "
               "auto-`sink` (a helper that frees its parameter, §2.2) "
               "and the returned-handle summary (a helper that hands an "
               "argument back, §2.2) — consulted at a call to a callee "
               "defined BELOW it. The escape summaries park what they "
               "cannot answer and replay it after the module (§2.7 / "
               "§2.8); these still answer inline, and an empty summary "
               "reads as 'does not sink' rather than 'not known yet'. "
               "Every spelling here is the same program as its "
               "defined-above twin, and must get the same verdict as it. "
               "The class asks for REJECT_STRICT rather than "
               "REJECT_DEFAULT because the two families answer at "
               "different strengths by design: a sink is a DEFINITE "
               "move, while a returned handle is a MAYBE — the callee "
               "may hand it back or may return something fresh — and "
               "the conditional double-free is strict-only (§6.2). What "
               "must never differ is `accept` versus either of them, "
               "which is what definition order used to decide.",
        "expect": REJECT_STRICT,
        "expect_msg": ["use of moved value", "may already be freed"],
        "spellings": {
            "sink-above": prog(
                "    : ( Vec i ) v ( vec_new [i] )\n"
                "    ( release v )\n"
                "    ( vec_push [i] v 1 )",
                extra="@ release ( Vec i ) v → v { ( vec_free [i] v ) }\n"),
            "sink-forward": prog(
                "    : ( Vec i ) v ( vec_new [i] )\n"
                "    ( release v )\n"
                "    ( vec_push [i] v 1 )",
                extra="") + "@ release ( Vec i ) v → v { ( vec_free [i] v ) }\n",
            "ret-alias-above": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) b ( pick a )\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )",
                extra="@ pick ( Vec i ) v → ( Vec i ) { ^ v }\n"),
            "ret-alias-forward": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) b ( pick a )\n"
                "    ( vec_free [i] b )\n"
                "    ( vec_free [i] a )",
                extra="") + "@ pick ( Vec i ) v → ( Vec i ) { ^ v }\n",
        },
    },
    {
        "name": "loop-carried-free",
        "severity": "memory-unsafety",
        "doc": "An outer binding freed INSIDE a loop body: on the second "
               "iteration the buffer is already gone (docs/MEMORY.md "
               "§2.6). The documented exemptions live in `controls`.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["use of moved value", "may already be freed"],
        "spellings": {
            "while-loop": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ~ i k 0\n"
                "    ~ < k 3 { ( vec_free [i] a ) = k + k 1 }"),
            "while-loop-wrapper": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ~ i k 0\n"
                "    ~ < k 3 { ( dispose a ) = k + k 1 }",
                extra="@ dispose ( Vec i ) v → v { ( vec_free [i] v ) }\n"),
            "nested-loop": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ~ i k 0\n"
                "    ~ < k 2 { : ~ i j 0  ~ < j 2 { ( vec_free [i] a ) = j + j 1 } = k + k 1 }"),
            "foreach-outer": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( vec_free [i] a ) }\n"
                "    ( vec_free [i] xs )"),
        },
    },
    {
        "name": "iterator-invalidation",
        "severity": "diagnostic-consistency",
        "doc": "Mutating a container while a `~ x xs` foreach holds a "
               "borrow of it (docs/MEMORY.md §2.5). Severity is "
               "deliberately NOT memory-unsafety: measured, a forced "
               "realloc during iteration does not dangle, because a Vec "
               "is a handle to a control block and the loop reads "
               "through it. The rule is a conservative guard, so a gap "
               "here is an inconsistency in what gets DIAGNOSED — the "
               "direct push warns, the same push one call deep does not "
               "— and belongs below anything that corrupts memory.",
        "expect": WARN,
        "expect_msg": ["while iterating over it"],
        "spellings": {
            "push-in-foreach": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( vec_push [i] xs 2 ) }\n"
                "    ( vec_free [i] xs )"),
            "set-in-foreach": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( vec_set [i] xs 0 9 ) }\n"
                "    ( vec_free [i] xs )"),
            "free-in-foreach": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( vec_free [i] xs ) }"),
            "push-via-helper": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( grow xs ) }\n"
                "    ( vec_free [i] xs )",
                extra="@ grow ( Vec i ) v → v { ( vec_push [i] v 2 ) }\n"),
            "push-in-nested-foreach": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    : ( Vec i ) ys ( vec_new [i] )\n"
                "    ( vec_push [i] ys 1 )\n"
                "    ~ y ys { ~ z xs { ( vec_push [i] xs 3 ) } }\n"
                "    ( vec_free [i] xs )\n"
                "    ( vec_free [i] ys )"),
        },
    },
    {
        "name": "thread-nonsend",
        "severity": "memory-unsafety",
        "doc": "An `Rc` (non-atomic refcount) reaching a worker thread. "
               "Two threads racing on the control-block count is UB; "
               "`Arc` is the thread-safe counterpart. The first three "
               "spellings are what the original name-matching check "
               "caught — 'is this capture spelled Rc?'. Everything below "
               "them hides the Rc one hop further into the type (a "
               "field, an element, a payload, a generic argument) or one "
               "hop further into the program (a nested closure, a "
               "different boundary), and every one of them compiled "
               "clean until the check became a walk over the type's "
               "whole graph. Ten spellings of one bug, one of them "
               "diagnosed, is the exact shape this tool exists to find.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["is not Send"],
        "spellings": {
            "inline-closure": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : !Thread ThreadErr t ( thread_spawn \\ → v { ( rc_free [i] r ) } )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"),
            "named-closure": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( @ v ) w \\ → v { ( rc_free [i] r ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"),
            "via-helper": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( @ v ) w \\ → v { ( touch r ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n",
                extra="@ touch ( Rc i ) r → v { ( rc_free [i] r ) }\n"),
            # One struct field away. The capture is a `%Holder`, and
            # nothing about that name says "Rc".
            "struct-field": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : Holder hd @ Holder { r }\n"
                "    : ( @ v ) w \\ → v { : Holder c hd }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n",
                extra=": Holder { ( Rc i ) r }\n"),
            # Two struct fields away — the depth-two escape that
            # #902's function summary left open in its own domain.
            "struct-field-nested": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : Outer o @ Outer { @ Inner { r } }\n"
                "    : ( @ v ) w \\ → v { : Outer c o }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n",
                extra=": Inner { ( Rc i ) r }\n: Outer { Inner in }\n"),
            # Generic containers erase their element type from the LLVM
            # body (`: Vec [A] { s ctl }`); it survives only in the
            # monomorph's mangled name.
            "vec-element": prog(
                "    : ( Vec ( Rc i ) ) v ( vec_new [( Rc i )] )\n"
                "    : ( @ v ) w \\ → v { : i n ( vec_len [( Rc i )] v ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"
                        "$ `stdlib/core/vec.nu`\n"),
            "box-payload": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( Box ( Rc i ) ) b ( box_new [( Rc i )] r )\n"
                "    : ( @ v ) w \\ → v { : ( Rc i ) g ( box_get [( Rc i )] b ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"
                        "$ `stdlib/core/box.nu`\n"),
            # An atomic refcount wrapped around a non-atomic one. Also
            # the case where Arc holds its payload to the HARDER
            # question: shared, not merely sent.
            "arc-payload": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( Arc ( Rc i ) ) a ( arc_new [( Rc i )] r )\n"
                "    : ( @ v ) w \\ → v { : ( Rc i ) g ( arc_get [( Rc i )] a ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"
                        "$ `stdlib/std/arc.nu`\n"),
            # An enum's body is `{ i64, i64, … }` — payload slots are
            # type-free, so only the declared payload types remember.
            "enum-payload": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : Wrap wr @ Wrap { Held r }\n"
                "    : ( @ v ) w \\ → v { : Wrap c wr }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n",
                extra=": | Wrap { Held ( Rc i )  Empty }\n"),
            "option-payload": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ?( Rc i ) o @ ?( Rc i ) { r }\n"
                "    : ( @ v ) w \\ → v { : ?( Rc i ) c o }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"),
            # No type walk can find this one: a closure lowers to a
            # fn/env pair whose env contents are invisible.
            "nested-closure": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( @ v ) inner \\ → v { ( rc_free [i] r ) }\n"
                "    : ( @ v ) w \\ → v { ( inner ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"),
            # A different boundary entirely: whatever chan_send takes,
            # another thread or fiber receives.
            "chan-send": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( Channel ( Rc i ) ) ch ( chan_new [( Rc i )] )\n"
                "    : b ok ( chan_send [( Rc i )] ch r )",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"
                        "$ `stdlib/std/channel.nu`\n"),
            # And a third: a fiber runs on whichever M:N worker picks
            # it up, so `spawn` is a thread boundary too.
            "fiber-spawn": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : ( @ v ) w \\ → v { ( rc_free [i] r ) }\n"
                "    ( runtime_init 4 )\n"
                "    : Fiber f ( spawn w )",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/async.nu`\n"),
            # A hand-placed leaf must propagate exactly like a built-in
            # one — the FFI-handle case the compiler cannot see.
            "notsend-marker": prog(
                "    : Db d @ Db { `conn` }\n"
                "    : ( @ v ) w \\ → v { : Db c d }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/core/marker.nu`\n",
                extra=": Db { s handle }\n% NotSend Db { }\n"),
            "notsend-marker-in-vec": prog(
                "    : ( Vec Db ) v ( vec_new [Db] )\n"
                "    : ( @ v ) w \\ → v { : i n ( vec_len [Db] v ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/core/marker.nu`\n"
                        "$ `stdlib/core/vec.nu`\n",
                extra=": Db { s handle }\n% NotSend Db { }\n"),
        },
    },
    {
        "name": "thread-nonsync",
        "severity": "memory-unsafety",
        "doc": "The OTHER half of the question, and the one place the two "
               "halves come apart. A `Cell` is a raw byte buffer with "
               "unsynchronised reads and writes: MOVING one to a worker "
               "is fine and must stay accepted (see the "
               "`cell-moved-not-shared` control), SHARING one is a race "
               "on its bytes. `Arc` is what expresses sharing in NURL, "
               "so its payload — and only its payload — faces the "
               "stronger demand. Every spelling here reaches a Cell "
               "through an Arc.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["is not Send"],
        "spellings": {
            "arc-cell": prog(
                "    : Cell c ( cell_zero 64 )\n"
                "    : ( Arc Cell ) a ( arc_new [Cell] c )\n"
                "    : ( @ v ) w \\ → v { : Cell g ( arc_get [Cell] a ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/std/arc.nu`\n"
                        "$ `stdlib/core/cell.nu`\n"),
            "arc-struct-holding-cell": prog(
                "    : Buf bf @ Buf { ( cell_zero 64 ) }\n"
                "    : ( Arc Buf ) a ( arc_new [Buf] bf )\n"
                "    : ( @ v ) w \\ → v { : Buf g ( arc_get [Buf] a ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/std/arc.nu`\n"
                        "$ `stdlib/core/cell.nu`\n",
                extra=": Buf { Cell c }\n"),
            "arc-notsync-marker": prog(
                "    : Reg rg @ Reg { 0 }\n"
                "    : ( Arc Reg ) a ( arc_new [Reg] rg )\n"
                "    : ( @ v ) w \\ → v { : Reg g ( arc_get [Reg] a ) }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/std/arc.nu`\n"
                        "$ `stdlib/core/marker.nu`\n",
                extra=": Reg { i slot }\n% NotSync Reg { }\n"),
        },
    },
    {
        "name": "invalid-input",
        "severity": "invalid-ir",
        "doc": "Programs that are simply WRONG. A different axis from "
               "the rest of this file: not 'the same situation spelled N "
               "ways' but 'bad input must be diagnosed, never lowered'. "
               "Two shipped bugs escaped exactly here — #901 lowered a "
               "type-mismatched option payload and #906 lowered a match "
               "arm naming a variant that does not exist — and in both "
               "cases nurlc exited 0 and clang reported the problem, "
               "about generated IR rather than about the line to fix. "
               "Every spelling must produce a NURL diagnostic; and the "
               "universal IR check above catches any that is lowered "
               "anyway, whatever this class concludes.",
        "expect": REJECT_DEFAULT,
        "spellings": {
            "match-arm-rust-habit": prog(
                "    : i n ?? ( int_parse `12` ) { Ok v → v  _ → -1 }\n"
                "    ( nurl_print_int n )", prelude="$ `stdlib/std/int`\n"),
            "match-arm-unknown-variant": prog(
                "    : Color c Red\n"
                "    : i n ?? c { Red → 1  Purple → 2  _ → 0 }\n"
                "    ( nurl_print_int n )",
                prelude="", extra=": | Color { Red Green Blue }\n"),
            "payload-int-into-string": prog(
                "    : ?s o @ ?s { T 42 }\n"
                "    ?? o { T v → ^ 1  F → ^ 0 }", prelude=""),
            "payload-string-into-int": prog(
                "    : ?i o @ ?i { T `x` }\n"
                "    ?? o { T v → ^ v  F → ^ 0 }", prelude=""),
            "cast-to-a-binding": prog(
                "    : ~ i d 2\n"
                "    = d # d + d 1", prelude=""),
            "cast-aggregate-to-float": prog(
                "    : ?i o @ ?i { T 1 }\n"
                "    : f x # f o\n"
                "    ( nurl_print_int # i x )", prelude=""),
            "unknown-function": prog(
                "    ( no_such_function_here 1 )", prelude=""),
            "assign-to-immutable": prog(
                "    : i k 1\n"
                "    = k 2\n"
                "    ( nurl_print_int k )", prelude=""),
            "return-type-mismatch": prog(
                "    ^ ( vec_new [i] )"),
            "aggregate-literal-on-pointer": prog(
                "    : *i p @ *i { 1 }\n"
                "    ( nurl_print_int # i p )", prelude=""),
            "string-into-int-binding": prog(
                "    : i k `x`\n"
                "    ( nurl_print_int k )", prelude=""),
            "enum-payload-string-into-int": prog(
                "    : E e @ E { A `s` }\n"
                "    ^ ?? e { A v → v  B → 0 }",
                prelude="", extra=": | E { A i  B }\n"),
            "wrong-arg-count": prog(
                "    : ( Vec i ) v ( vec_new [i] )\n"
                "    ( vec_push [i] v )"),
        },
    },
    {
        "name": "ret-escape",
        "severity": "memory-unsafety",
        "doc": "A helper hands a caller's stack reference back OUT "
               "through its result (docs/MEMORY.md §2.8), and the caller "
               "then returns it. The frame the closure points at is gone "
               "the moment the caller returns, so every spelling here "
               "dangles. What changes between them is only HOW the "
               "reference rides out of the helper — bare `^ p`, a struct "
               "field, a struct field one level deeper, a closure that "
               "captured it — and WHEN the helper's summary is known: a "
               "callee defined below the call site, or a generic, has no "
               "summary to consult at the call.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["references a stack binding", "escapes"],
        "spellings": {
            "bare-return": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ id ( @ v ) cb → ( @ v ) { ^ cb }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( id f )\n}\n"),
            "bound-then-returned": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ id ( @ v ) cb → ( @ v ) { : ( @ v ) t cb ^ t }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( id f )\n}\n"),
            "ternary-return": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ id ( @ v ) cb i k → ( @ v ) { ^ ? > k 0 cb cb }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( id f 1 )\n}\n"),
            "result-bound-in-caller": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ id ( @ v ) cb → ( @ v ) { ^ cb }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    : ( @ v ) r ( id f )\n    ^ r\n}\n"),
            "transitive-two-deep": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ id ( @ v ) cb → ( @ v ) { ^ cb }\n"
                      + "@ id2 ( @ v ) cb → ( @ v ) { ^ ( id cb ) }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( id2 f )\n}\n"),
            "aggregate-field": prog(
                "    : Slot s ( caller )\n"
                "    : ( @ v ) g . s cb\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR + ESC_SLOT
                      + "@ wrap ( @ v ) cb → Slot { ^ @ Slot { cb } }\n"
                      + "@ caller → Slot {\n" + ESC_MKREF
                      + "    ^ ( wrap f )\n}\n"),
            # One aggregate level deeper. Nothing about the situation
            # changed; only the number of braces between `^` and `cb`.
            "nested-aggregate": prog(
                "    : Outer o ( caller )\n"
                "    : Inner n . o it\n"
                "    : ( @ v ) g . n cb\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + ": Inner { ( @ v ) cb }\n: Outer { Inner it }\n"
                      + "@ wrap2 ( @ v ) cb → Outer { ^ @ Outer { @ Inner { cb } } }\n"
                      + "@ caller → Outer {\n" + ESC_MKREF
                      + "    ^ ( wrap2 f )\n}\n"),
            # A closure carries the reference exactly as a struct field
            # does — the returned env holds `cb`, which holds the frame.
            "closure-capture": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ wrapc ( @ v ) cb → ( @ v ) { ^ \\ → v { ( cb ) } }\n"
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( wrapc f )\n}\n"),
            # Definition order. The situation is identical to
            # bare-return; the summary simply is not built yet when the
            # call compiles.
            "forward-callee": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR
                      + "@ caller → ( @ v ) {\n" + ESC_MKREF
                      + "    ^ ( id f )\n}\n"
                      + "@ id ( @ v ) cb → ( @ v ) { ^ cb }\n"),
            "generic-callee": prog(
                "    : Slot s ( caller )\n"
                "    : ( @ v ) g . s cb\n"
                "    ( g )",
                prelude="",
                extra=ESC_CTR + ESC_SLOT
                      + "@ idg [T] T x → T { ^ x }\n"
                      + "@ caller → Slot {\n" + ESC_MKREF
                      + "    : Slot s @ Slot { f }\n"
                      + "    ^ ( idg [Slot] s )\n}\n"),
            # Same passthrough, consumed by a different §2.3 sink: the
            # result is stored in a heap container instead of returned.
            "result-into-heap-vec": prog(
                "    : ( Vec Slot ) heap ( vec_new [Slot] )\n"
                "    ( fill heap )\n"
                "    ( vec_free [Slot] heap )",
                prelude=PRELUDE_VEC,
                extra=ESC_CTR + ESC_SLOT
                      + "@ wrap ( @ v ) cb → Slot { ^ @ Slot { cb } }\n"
                      + "@ fill ( Vec Slot ) heap → v {\n" + ESC_MKREF
                      + "    ( vec_push [Slot] heap ( wrap f ) )\n}\n"),
            # …and by the thread sink.
            "result-into-thread": prog(
                "    ( caller )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ id ( @ v ) cb → ( @ v ) { ^ cb }\n"
                      + "@ caller → v {\n" + ESC_MKREF
                      + "    : !Thread ThreadErr t ( thread_spawn ( id f ) )\n"
                      + "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"),
        },
    },
    {
        "name": "escape-into-callee",
        "severity": "memory-unsafety",
        "doc": "The mirror image of ret-escape: a stack reference passed "
               "INTO a helper that retains it past the call — a heap "
               "container or a worker thread (docs/MEMORY.md §2.7). The "
               "escape summary is inferred in codegen order and replayed "
               "after the module compiles, so definition order must not "
               "decide the verdict: a helper defined below the call, and "
               "a helper whose own escaping callee is defined below IT, "
               "are the same program written in a different order.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["escapes", "references a stack binding"],
        "spellings": {
            "direct-above": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ detach ( @ v ) cb → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"
                      + "@ leaky → v {\n" + ESC_MKREF + "    ( detach f )\n}\n"),
            "forward-callee": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ leaky → v {\n" + ESC_MKREF + "    ( detach f )\n}\n"
                      + "@ detach ( @ v ) cb → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"),
            "transitive-above": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ detach ( @ v ) cb → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"
                      + "@ outer ( @ v ) cb → v { ( detach cb ) }\n"
                      + "@ leaky → v {\n" + ESC_MKREF + "    ( outer f )\n}\n"),
            # The whole chain below the call site. `outer` compiles while
            # `detach` is still unknown, so outer's own summary is empty
            # when the parked check replays against it.
            "forward-chain": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ leaky → v {\n" + ESC_MKREF + "    ( outer f )\n}\n"
                      + "@ outer ( @ v ) cb → v { ( detach cb ) }\n"
                      + "@ detach ( @ v ) cb → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"),
            # The middle order: the helper is above the call, but its own
            # escaping callee is below the helper.
            "callee-above-its-callee-below": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR
                      + "@ outer ( @ v ) cb → v { ( detach cb ) }\n"
                      + "@ detach ( @ v ) cb → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"
                      + "@ leaky → v {\n" + ESC_MKREF + "    ( outer f )\n}\n"),
            "vec-push-sink": prog(
                "    : ( Vec Slot ) heap ( vec_new [Slot] )\n"
                "    ( leaky heap )\n"
                "    ( vec_free [Slot] heap )",
                prelude=PRELUDE_VEC,
                extra=ESC_CTR + ESC_SLOT
                      + "@ stash ( Vec Slot ) heap Slot item → v { ( vec_push [Slot] heap item ) }\n"
                      + "@ leaky ( Vec Slot ) heap → v {\n" + ESC_MKREF
                      + "    : Slot s @ Slot { f }\n    ( stash heap s )\n}\n"),
            "generic-sink": prog(
                "    : ( Vec Slot ) heap ( vec_new [Slot] )\n"
                "    ( leaky heap )\n"
                "    ( vec_free [Slot] heap )",
                prelude=PRELUDE_VEC,
                extra=ESC_CTR + ESC_SLOT
                      + "@ stashg [T] ( Vec T ) heap T item → v { ( vec_push [T] heap item ) }\n"
                      + "@ leaky ( Vec Slot ) heap → v {\n" + ESC_MKREF
                      + "    : Slot s @ Slot { f }\n    ( stashg [Slot] heap s )\n}\n"),
            # The reference reaches the escaping parameter wrapped in a
            # struct rather than bare.
            "wrapped-in-struct": prog(
                "    ( leaky )",
                prelude=PRELUDE_THREAD,
                extra=ESC_CTR + ESC_SLOT
                      + "@ detachs Slot box → v {\n"
                        "    : !Thread ThreadErr t ( thread_spawn . box cb )\n"
                        "    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }\n}\n"
                      + "@ leaky → v {\n" + ESC_MKREF
                      + "    : Slot s @ Slot { f }\n    ( detachs s )\n}\n"),
        },
    },
    {
        "name": "aliased-mutation",
        "severity": "diagnostic-consistency",
        "doc": "A binding passed `inout` — an exclusive mutable borrow "
               "for that call — and also READ by another argument of the "
               "same call (docs/MEMORY.md §2.4). Every sibling read is a "
               "snapshot taken before the callee runs, so this is a "
               "'did you mean the updated value?' fault rather than "
               "memory unsafety, and only the bare-identifier form is "
               "reported by DEFAULT: `( grow v ( vec_len v ) )` is an "
               "ordinary, correct idiom and the no-false-positive "
               "contract protects it. Under --strict-borrowck, which is "
               "documented to over-flag, the spellings must agree — a "
               "field read reported and the same read one parenthesis "
               "deeper ignored is the inconsistency, not the rule.",
        "expect": REJECT_STRICT,
        "expect_msg": ["exclusive access is violated"],
        "spellings": {
            "same-binding-twice": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( swap_counters c c )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ swap_counters inout Counter a inout Counter b → v {\n"
                      "    : i t . a n\n    = . a n . b n\n    = . b n t\n}\n"),
            "inout-and-byvalue": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump c c )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ bump inout Counter a Counter b → v { = . a n + . a n . b n }\n"),
            "field-read": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump_by c . c n )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ bump_by inout Counter a i b → v { = . a n + . a n b }\n"),
            "field-read-in-arithmetic": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump_by c + . c n 1 )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ bump_by inout Counter a i b → v { = . a n + . a n b }\n"),
            "read-through-a-call": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump_by c ( peek c ) )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ peek Counter c → i { ^ . c n }\n"
                      "@ bump_by inout Counter a i b → v { = . a n + . a n b }\n"),
            # The read is two calls deep and on the far side of an
            # operator — still the same binding, still read before the
            # callee mutates it.
            "read-two-calls-deep": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump_by c + ( twice ( peek c ) ) 1 )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ peek Counter c → i { ^ . c n }\n"
                      "@ twice i n → i { ^ * n 2 }\n"
                      "@ bump_by inout Counter a i b → v { = . a n + . a n b }\n"),
            # Reader first, writer second: the order of the arguments
            # must not decide the verdict.
            "read-before-inout": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    ( bump_rev ( peek c ) c )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ peek Counter c → i { ^ . c n }\n"
                      "@ bump_rev i b inout Counter a → v { = . a n + . a n b }\n"),
        },
    },
    {
        "name": "stale-borrow",
        "severity": "memory-unsafety",
        "doc": "A raw pointer taken from a container's buffer "
               "(`vec_data` / `string_data`) and read AFTER the "
               "container was grown or released (docs/MEMORY.md §2.10). "
               "The realloc moves the buffer, so the pointer reads freed "
               "memory — and it reads plausible garbage rather than "
               "crashing, which is what makes the diagnostic worth "
               "having. The mutation is the same mutation however it is "
               "spelled: inline, through a helper, on a field, in a "
               "loop.",
        "expect": WARN,
        "expect_msg": ["is stale", "may have reallocated"],
        "spellings": {
            "push-after-borrow": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    ( vec_push [u] v # u 2 )\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )"),
            "reserve-after-borrow": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    ( vec_reserve [u] v 64 )\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )"),
            "free-after-borrow": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    ( vec_free [u] v )\n"
                "    : i x # i . p 0"),
            # The same push, one call deep. #902's shape: a guard that
            # holds for the direct spelling and not for its twin teaches
            # "wrap it in a helper" as the cure.
            "push-via-helper": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    ( grow v )\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )",
                extra="@ grow ( Vec u ) v → v { ( vec_push [u] v # u 2 ) }\n"),
            "push-in-loop": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    : ~ i k 0\n"
                "    ~ < k 3 { ( vec_push [u] v # u 2 ) = k + k 1 }\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )"),
            "string-data-after-append": prog(
                "    : ~ String s ( string_new )\n"
                "    ( string_push_char s 65 )\n"
                "    : s p ( string_data s )\n"
                "    ( string_push_char s 66 )\n"
                "    : i x ( nurl_str_len p )\n"
                "    ( string_free s )",
                prelude="$ `stdlib/core/string.nu`\n"),
        },
    },
    {
        "name": "controls",
        "doc": "Correct programs. A class of its own because a checker "
               "that rejects these is worse than one that misses a bug — "
               "every entry here is code someone would reasonably write. "
               "Judged against the DEFAULT checker only: the "
               "no-false-positive contract is the default checker's, and "
               "--strict-borrowck is documented to over-flag (it also "
               "rejects the mutually-exclusive-frees pattern, and the "
               "loop-fixpoint version of the same conservatism flags "
               "freeing a foreach ELEMENT). Holding controls to strict "
               "would encode that documented noise as a regression.",
        "expect": ACCEPT,
        "spellings": {
            "single-thread-arc-mutation": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "    ( vec_push [i] v 1 )",
                prelude=PRELUDE_ARC),
            "thread-reads-only": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : ( @ v ) w \\ → v {\n"
                "        : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "        ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC),
            "thread-local-vec": prog(
                "    : ( @ v ) w \\ → v {\n"
                "        : ( Vec i ) mine ( vec_new [i] )\n"
                "        ( vec_push [i] mine 1 )\n"
                "        ( vec_free [i] mine )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }",
                prelude=PRELUDE_ARC),
            "mutex-guarded-mutation": prog(
                "    : ( Vec i ) d ( vec_new [i] )\n"
                "    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )\n"
                "    : Mutex m ( mutex_new )\n"
                "    : ( @ v ) w \\ → v {\n"
                "        ( mutex_lock m )\n"
                "        : ( Vec i ) v ( arc_get [( Vec i )] a )\n"
                "        ( vec_push [i] v 1 )\n"
                "        ( mutex_unlock m )\n"
                "    }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }\n"
                "    ( mutex_free m )",
                prelude=PRELUDE_ARC),
            # Send/Sync controls. A derivation that rejects the
            # thread-nonsend / thread-nonsync classes is worthless if it
            # also rejects these — the no-false-positive property
            # (docs/MEMORY.md §6.3) is what bounds the whole design, and
            # each of these is a shape that LOOKS like a rejected one.
            #
            # A Cell MOVED to a worker rather than shared. Cell is the
            # !Sync leaf, and only Arc asks about Sync: capturing one
            # directly is Send and stays accepted.
            "cell-moved-not-shared": prog(
                "    : Cell c ( cell_zero 64 )\n"
                "    : ( @ v ) w \\ → v { : i n ( cell_size c ) }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }\n"
                "    ( cell_free c )",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/core/cell.nu`\n"),
            # A Mutex is `{ Cell c }` — structurally the !Sync leaf, and
            # the very thing that makes contents shareable. If the
            # marker impls in thread.nu ever stop being consulted, this
            # is what notices.
            "mutex-captured": prog(
                "    : Mutex m ( mutex_new )\n"
                "    : ( @ v ) w \\ → v { ( mutex_lock m ) ( mutex_unlock m ) }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }\n"
                "    ( mutex_free m )",
                prelude="$ `stdlib/std/thread.nu`\n"),
            # The escape hatch must actually open: an explicit `% Send`
            # stops the walk at that type, Rc field and all.
            "send-marker-overrides": prog(
                "    : ( Rc i ) r ( rc_new [i] 1 )\n"
                "    : Wrapper wr @ Wrapper { r }\n"
                "    : ( @ v ) w \\ → v { : Wrapper c wr }\n"
                "    : !Thread ThreadErr t ( thread_spawn w )\n"
                "    ?? t { T h → { ( thread_join h ) } F e → {} }\n"
                "    ( rc_free [i] r )",
                prelude="$ `stdlib/std/rc.nu`\n$ `stdlib/std/thread.nu`\n"
                        "$ `stdlib/core/marker.nu`\n",
                extra=": Wrapper { ( Rc i ) r }\n% Send Wrapper { }\n"),
            # A String and a Vec of scalars crossing the boundary. NURL
            # spells String and every opaque FFI handle `i8*`, so
            # demoting either would demote both and take most correct
            # worker code with it.
            "string-and-vec-captured": prog(
                "    : s label `worker`\n"
                "    : ( Vec i ) nums ( vec_new [i] )\n"
                "    : ( @ v ) w \\ → v { ( puts label ) : i n ( vec_len [i] nums ) }\n"
                "    : !Thread ThreadErr r ( thread_spawn w )\n"
                "    ?? r { T t → { ( thread_join t ) } F e → {} }\n"
                "    ( vec_free [i] nums )",
                prelude="$ `stdlib/std/thread.nu`\n$ `stdlib/core/vec.nu`\n"),
            # `[T: Send]` is answered by the derivation, not by hunting
            # for an impl — otherwise the bound is unusable for `i`.
            "send-bound-on-scalar": prog(
                "    : i n ( ship [i] 42 )",
                prelude="$ `stdlib/core/marker.nu`\n",
                extra="@ ship [T: Send] T v → i { ^ 1 }\n"),
            "mutually-exclusive-frees": prog(
                "    : ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    ? > c 0 { ( vec_free [i] a ) } { ( vec_free [i] a ) }"),
            "rebound-then-freed": prog(
                "    : ~ ( Vec i ) a ( vec_new [i] )\n"
                "    : i c 1\n"
                "    ? > c 0 { ( vec_free [i] a ) = a ( vec_new [i] ) } {}\n"
                "    ( vec_free [i] a )"),
            "loop-elem-free": prog(
                "    : ( Vec String ) xs ( vec_new [String] )\n"
                "    ~ y xs { ( string_free y ) }\n"
                "    ( vec_free [String] xs )",
                prelude="$ `stdlib/core/vec.nu`\n$ `stdlib/core/string.nu`\n"),
            "loop-inner-declared-free": prog(
                "    : ~ i k 0\n"
                "    ~ < k 2 { : ( Vec i ) tmp ( vec_new [i] ) ( vec_free [i] tmp ) = k + k 1 }"),
            "loop-rebound-free": prog(
                "    : ~ ( Vec i ) buf ( vec_new [i] )\n"
                "    : ~ i k 0\n"
                "    ~ < k 2 { ( vec_free [i] buf ) = buf ( vec_new [i] ) = k + k 1 }\n"
                "    ( vec_free [i] buf )"),
            "foreach-read-only": prog(
                "    : ( Vec i ) xs ( vec_new [i] )\n"
                "    ( vec_push [i] xs 1 )\n"
                "    ~ y xs { ( nurl_print ( nurl_str_int y ) ) }\n"
                "    ( vec_free [i] xs )"),
            # Both of these were SUSPECTED bugs and measured to be
            # defined behaviour. They are controls now so the semantics
            # cannot drift silently: a partially-filled struct literal
            # zero-fills (the aggregate starts as `zeroinitializer`,
            # giving 7/0/0 rather than garbage), and a match arm may bind
            # a PREFIX of a variant's payloads and ignore the rest.
            # An earlier draft of an under-fill check rejected the first
            # and broke five tests that use it deliberately.
            "struct-partial-init": prog(
                "    : P p @ P { 7 }\n"
                "    ( nurl_print_int . p z )",
                prelude="", extra=": P { i x  i y  i z }\n"),
            "match-binds-payload-prefix": prog(
                "    : E e @ E { A 11 22 }\n"
                "    ^ ?? e { A x → x  B → 0 }",
                prelude="", extra=": | E { A i i  B }\n"),
            "option-payload-matches": prog(
                "    : ?i o @ ?i { T 42 }\n"
                "    ?? o { T v → ^ v  F → ^ 0 }", prelude=""),
            # Escape controls. The ret-escape / escape-into-callee
            # classes above widen what counts as "the reference got
            # out"; each of these is a shape that LOOKS like one and is
            # entirely legal, so they bound the widening.
            #
            # A helper that only INVOKES the closure cannot retain it —
            # passing a stack reference there is the documented legal
            # case (§2.7), and the one the whole callback idiom rests on.
            "helper-invokes-param": prog(
                "    : i n ( caller )",
                prelude="",
                extra=ESC_CTR
                      + "@ runit ( @ v ) cb → i { ( cb ) ^ 0 }\n"
                      + "@ caller → i {\n" + ESC_MKREF
                      + "    : i r ( runit f )\n    ^ + r . c n\n}\n"),
            # The Slot really does carry the reference — and is consumed
            # inside the referent's own frame, which is fine. Folding
            # "embeds a parameter" into "escapes" turns this red.
            "aggregate-consumed-in-scope": prog(
                "    : i n ( caller )",
                prelude="",
                extra=ESC_CTR + ESC_SLOT
                      + "@ wrap ( @ v ) cb → Slot { ^ @ Slot { cb } }\n"
                      + "@ caller → i {\n" + ESC_MKREF
                      + "    : Slot s ( wrap f )\n"
                      + "    : ( @ v ) g . s cb\n    ( g )\n    ^ . c n\n}\n"),
            # An ordinary constructor returns its parameters inside a
            # struct. Recording them is right; flagging them is not —
            # an `int` argument is not a reference.
            "constructor-of-values": prog(
                "    : Point p ( mk 3 4 )\n"
                "    : i n . p x",
                prelude="",
                extra=": Point { i x i y }\n"
                      + "@ mk i a i b → Point { ^ @ Point { a b } }\n"),
            # The nested-aggregate twin of the constructor: depth must
            # not be what makes a value a reference.
            "nested-constructor-of-values": prog(
                "    : Outer o ( mk2 3 )\n"
                "    : Inner n . o it\n"
                "    : i k . n x",
                prelude="",
                extra=": Inner { i x }\n: Outer { Inner it }\n"
                      + "@ mk2 i a → Outer { ^ @ Outer { @ Inner { a } } }\n"),
            # A closure over a HEAP handle is not a stack reference: the
            # Vec control block outlives the frame, so returning the
            # closure is the documented cure, not the disease (§4).
            "closure-over-heap-handle": prog(
                "    : ( @ v ) g ( caller )\n"
                "    ( g )",
                prelude=PRELUDE_VEC,
                extra="@ caller → ( @ v ) {\n"
                      "    : ( Vec i ) xs ( vec_new [i] )\n"
                      "    : ( @ v ) f \\ → v { ( vec_push [i] xs 1 ) }\n"
                      "    ^ f\n}\n"),
            # A helper returning a FRESH value, having merely borrowed
            # the reference, is not a passthrough — its result may be
            # returned freely.
            # §2.4 controls. A DIFFERENT binding read alongside the
            # `inout` one is the whole point of having two arguments.
            "inout-with-other-binding": prog(
                "    : ~ Counter c @ Counter { 3 10 }\n"
                "    : ~ Counter d @ Counter { 9 10 }\n"
                "    ( bump c d )",
                prelude="",
                extra=": Counter { i n i max }\n"
                      "@ bump inout Counter a Counter b → v { = . a n + . a n . b n }\n"),
            # §2.10 control: a borrow taken AFTER the mutation is fresh,
            # and a container never mutated invalidates nothing.
            "borrow-after-mutation": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    ( vec_push [u] v # u 2 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )"),
            "borrow-of-untouched-container": prog(
                "    : ~ ( Vec u ) v ( vec_new [u] )\n"
                "    : ~ ( Vec u ) w ( vec_new [u] )\n"
                "    ( vec_push [u] v # u 1 )\n"
                "    : * u p ( vec_data [u] v )\n"
                "    ( vec_push [u] w # u 2 )\n"
                "    : i x # i . p 0\n"
                "    ( vec_free [u] v )\n"
                "    ( vec_free [u] w )"),
            "fresh-result-not-passthrough": prog(
                "    : i n ( caller )",
                prelude="",
                extra=ESC_CTR
                      + "@ runit ( @ v ) cb → i { ( cb ) ^ 7 }\n"
                      + "@ caller → i {\n" + ESC_MKREF
                      + "    ^ ( runit f )\n}\n"),
        },
    },
]


# ── Driver ──────────────────────────────────────────────────────────────

def compile_verdict(src_path, strict):
    cmd = [str(NURLC)]
    if strict:
        cmd.append("--strict-borrowck")
    cmd.append(str(src_path))
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, cwd=ROOT)
    return r.returncode != 0, r.stderr.decode("utf-8", "replace")


INVALID = "invalid"          # the template is broken, not the compiler
_NO_LLVM_AS = False          # set once if llvm-as is missing (see ir_is_valid)


def ir_is_valid(src_path):
    """Does the module nurlc just emitted actually verify?

    The strongest invariant this harness has, and the one two shipped
    bugs broke: **whenever nurlc exits 0, the IR must be valid.** #901
    emitted `insertvalue { i1, i8* } …, i64 42, 1` and #906 emitted
    `alloca` with no type plus a load from a global that was never
    defined — both times nurlc reported success and clang delivered the
    news, about generated IR rather than about the line to change.

    Unlike everything else here this is never a template bug. Whatever
    a program says, if the compiler accepted it then the module it
    produced has to verify; a failure is the compiler's, always."""
    with tempfile.TemporaryDirectory() as td:
        ll = pathlib.Path(td) / "m.ll"
        r = subprocess.run([str(NURLC), str(src_path)],
                           stdout=open(ll, "wb"), stderr=subprocess.DEVNULL,
                           cwd=ROOT)
        if r.returncode != 0:
            return True, ""          # rejected: nothing was emitted to verify
        try:
            v = subprocess.run(["llvm-as", str(ll), "-o", "/dev/null"],
                               capture_output=True, cwd=ROOT)
        except FileNotFoundError:
            # No llvm-as on this host. Say so ONCE and loudly rather than
            # dying with a traceback or, worse, quietly reporting every
            # module as valid — an invariant that silently stops being
            # checked is the failure mode this harness exists to prevent.
            global _NO_LLVM_AS
            if not _NO_LLVM_AS:
                print("WARNING: llvm-as not found — the IR-validity "
                      "invariant is NOT being checked (install llvm).",
                      file=sys.stderr)
                _NO_LLVM_AS = True
            return True, ""
        if v.returncode == 0:
            return True, ""
        err = v.stderr.decode("utf-8", "replace").strip().splitlines()
        return False, (err[0][:110] if err else "llvm-as rejected the module")


def verdict_of(src_path, want_msg, default_only=False):
    """Normalised verdict + the diagnostic that produced it.

    A rejection only counts when it is the rejection this class is about.
    Without that, a typo in a template compiles to a syntax error, the
    harness reads "rejected" as "the checker caught it", and the gap it
    was written to find is hidden by the very test meant to expose it —
    a false negative that looks like coverage. `want_msg` is a substring
    the diagnostic has to contain; anything else is INVALID and is
    reported against the template, never against nurlc."""
    wants = [want_msg] if isinstance(want_msg, str) else list(want_msg or [])

    def says(text):
        return (not wants) or any(w in text for w in wants)

    rej_def, err_def = compile_verdict(src_path, strict=False)
    if rej_def:
        return (REJECT_DEFAULT if says(err_def) else INVALID), err_def
    # Not fatal, but the checker may still have spoken — an
    # iterator-invalidation borrow is a warning, and a warning is the
    # checker catching it, just without stopping the build.
    if "warning:" in err_def and says(err_def):
        return WARN, err_def
    if default_only:
        return ACCEPT, ""
    rej_str, err_str = compile_verdict(src_path, strict=True)
    if rej_str:
        return (REJECT_STRICT if says(err_str) else INVALID), err_str
    if "warning:" in err_str and says(err_str):
        return WARN, err_str
    return ACCEPT, ""


def runtime_is_broken(src_path, tmpdir):
    """Escalation for an accepted spelling that should have been rejected:
    build it with the checker OFF and run it under ASan. A crash or a leak
    proves the program really is broken, so the miss is the checker's and
    not the template's."""
    ll = tmpdir / "m.ll"
    exe = tmpdir / "m.bin"
    r = subprocess.run([str(NURLC), "--no-borrowck", str(src_path)],
                       stdout=open(ll, "wb"), stderr=subprocess.DEVNULL, cwd=ROOT)
    if r.returncode != 0:
        return None, "did not compile with --no-borrowck"
    # ASan instruments only functions carrying the `sanitize_address`
    # attribute, which the C frontend adds and hand-written IR does not
    # have. Without this line every escalation here saw ONLY what the
    # sanitized runtime's malloc interceptors caught — heap double-free,
    # heap use-after-free — and nothing at all about the code nurlc
    # emitted. A dangling STACK reference, which is what the escape
    # classes are made of, ran clean and was reported "UNCONFIRMED":
    # the harness was reading its own blind spot as evidence of
    # innocence. Stamping the attribute on every `define` is what makes
    # the generated code answerable to the sanitizer.
    src_ll = ll.read_text()
    ll.write_text(re.sub(r"^(define .*) \{$", r"\1 sanitize_address {",
                         src_ll, flags=re.M))
    # Prefer the runtime `./build.sh --san` just produced; the standalone
    # runtime_san.o can be an older artifact, and linking IR against a
    # stale ABI produces confusing hangs that look like findings.
    san = None
    cands = []
    env_rt = os.environ.get("NURL_SAN_RUNTIME")
    if env_rt:
        cands.append(pathlib.Path(env_rt))
    cands += [ROOT / "stdlib" / "runtime.o", ROOT / "stdlib" / "runtime_san.o"]
    for cand in cands:
        if cand.exists() and b"__asan_init" in subprocess.run(
                ["nm", str(cand)], capture_output=True).stdout:
            san = cand
            break
    if san is None:
        return None, "no sanitized runtime (./build.sh --san --no-tests)"
    link = subprocess.run(
        ["clang", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
         "-o", str(exe), str(ll), str(san), "-lm", "-lpthread"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    if link.returncode != 0:
        return None, "did not link"
    # symbolize=0 matters: ASan's symbolizer can stall for tens of
    # seconds on these binaries, and an early version of this harness
    # timed out and reported "hung" — throwing away a perfectly clear
    # "SEGV on 0xfffffffffffffff8, WRITE" that had already been printed.
    # A weak label on strong evidence is its own kind of wrong answer.
    # detect_stack_use_after_return: a closure that captured a caller's
    # binding by pointer is a live pointer into a dead frame, and without
    # the fake stack that read lands on memory that still happens to be
    # mapped. It is the whole failure mode of the escape classes.
    env = dict(os.environ, ASAN_OPTIONS=(
        "detect_leaks=1:symbolize=0:detect_stack_use_after_return=1"))
    partial = b""
    try:
        run = subprocess.run([str(exe)], capture_output=True, timeout=30, env=env)
        err_bytes, rc = run.stderr or b"", run.returncode
    except subprocess.TimeoutExpired as e:
        # Scan what it managed to print BEFORE giving up on it.
        partial = e.stderr or b""
        err_bytes, rc = partial, None
    out = err_bytes.decode("utf-8", "replace")
    for marker in ("AddressSanitizer", "LeakSanitizer", "runtime error:"):
        if marker in out:
            first = next((l for l in out.splitlines() if "ERROR:" in l), marker)
            return True, first.strip()[:90]
    if rc is None:
        return True, "hung with no sanitizer output (inspect by hand)"
    run_stub = None
    if rc is not None and rc < 0:
        return True, f"killed by signal {-rc}"
    return False, "ran clean"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true",
                    help="ASan-confirm every gap before reporting it")
    ap.add_argument("--class", dest="only", default=None)
    ap.add_argument("--update-known", action="store_true")
    args = ap.parse_args()

    if not NURLC.exists():
        print(f"ERROR: {NURLC} not built — run ./build.sh first", file=sys.stderr)
        return 2
    # A sanitized build/nurlc turns every one of the ~80 compiles below
    # into an ASan+LSan run: the sweep goes from seconds to the better
    # part of an hour and looks hung when it is only crawling. --verify
    # needs a sanitized RUNTIME, never a sanitized COMPILER.
    if b"__asan_init" in subprocess.run(["nm", str(NURLC)],
                                        capture_output=True).stdout:
        print("WARNING: build/nurlc is SANITIZED — every compile here will "
              "run under ASan and this sweep will take ~50x longer.\n"
              "         Run ./build.sh (no --san) first; --verify only needs "
              "a sanitized runtime,\n"
              "         which it finds via $NURL_SAN_RUNTIME or "
              "stdlib/runtime*.o.", file=sys.stderr)

    known = set()
    if KNOWN.exists():
        known = {tuple(x) for x in json.loads(KNOWN.read_text())["gaps"]}

    gaps, new_gaps, control_breaks, found, invalid = [], [], [], [], []
    bad_ir = []
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="nurl-metamorph-"))

    for cls in CLASSES:
        if args.only and cls["name"] != args.only:
            continue
        want = cls["expect"]
        print(f"\n── {cls['name']}  (expect ≥ {want})")
        for name, src in cls["spellings"].items():
            p = tmp / f"{cls['name']}__{name}.nu"
            p.write_text(src)
            got, _err = verdict_of(p, cls.get("expect_msg", ""),
                                   default_only=(want == ACCEPT))
            if got == INVALID:
                invalid.append((cls["name"], name))
                print(f"   {'INVALID':11} {name:26} → rejected for the wrong "
                      f"reason (template bug, not a checker gap)")
                continue
            # For a control, STRONGER is WORSE: the whole point is that
            # correct code compiles clean, so `reject` fails it. Using
            # `>=` here let a false positive pass as "better than asked",
            # which is the one direction this class exists to catch.
            # The universal invariant, checked for EVERY spelling the
            # compiler accepted, whatever its class says: an accepted
            # program must produce a module that verifies. This is never
            # a template bug — see ir_is_valid.
            if got in (ACCEPT, WARN):
                ir_ok, ir_why = ir_is_valid(p)
                if not ir_ok:
                    bad_ir.append((cls["name"], name, ir_why))
            ok = (got == ACCEPT) if want == ACCEPT \
                else STRENGTH[got] >= STRENGTH[want]
            mark = "ok " if ok else "GAP"
            extra = ""
            if not ok:
                if want == ACCEPT:
                    control_breaks.append((cls["name"], name, got))
                    mark = "REGRESSION"
                else:
                    key = (cls["name"], name)
                    gaps.append(key)
                    if args.verify:
                        broken, why = runtime_is_broken(p, tmp)
                        if broken is True:
                            extra = f"  [confirmed: {why}]"
                            found.append((cls["name"], name, why))
                        elif broken is False:
                            extra = "  [UNCONFIRMED — ran clean, check the template]"
                        else:
                            extra = f"  [not verified: {why}]"
                    if key not in known:
                        new_gaps.append(key)
            print(f"   {mark:11} {name:26} → {got}{extra}")

    if args.update_known:
        KNOWN.write_text(json.dumps(
            {"_comment": "Spellings the checker does not yet cover. A NEW "
                         "entry fails the gate; removing one is progress.",
             "gaps": sorted([list(g) for g in gaps])}, indent=2) + "\n")
        print(f"\nbaselined {len(gaps)} known gap(s) → {KNOWN.name}")
        return 0

    print(f"\n── summary: {len(gaps)} gap(s), {len(new_gaps)} new, "
          f"{len(control_breaks)} control regression(s), "
          f"{len(invalid)} invalid template(s), "
          f"{len(bad_ir)} invalid-IR escape(s)")
    for c, n in invalid:
        print(f"   INVALID    {c}/{n}: fix the template")
    for c, n, why in bad_ir:
        print(f"   INVALID IR {c}/{n}: nurlc exited 0 but the module does "
              f"not verify\n              {why}")
    for c, n, g in control_breaks:
        print(f"   REGRESSION {c}/{n}: correct code now rejected ({g})")
    for c, n in new_gaps:
        print(f"   NEW GAP    {c}/{n}")
    if args.verify:
        print("\n── worklist (most severe first)")
        rank = {"invalid-ir": 0, "memory-unsafety": 1,
                "silent-wrong-value": 2, "diagnostic-consistency": 3}
        sev_of = {c["name"]: c.get("severity", "unknown") for c in CLASSES}
        confirmed = {(c, n): why for c, n, why in found}
        rows = sorted(gaps, key=lambda g: (rank.get(sev_of.get(g[0]), 9), g[0]))
        if not rows:
            print("   (none)")
        for c, n in rows:
            why = confirmed.get((c, n))
            state = f"ASan: {why}" if why else "unconfirmed at runtime"
            print(f"   [{sev_of.get(c,'?'):22}] {c}/{n}\n"
                  f"       {state}")

    return 1 if (new_gaps or control_breaks or invalid or bad_ir) else 0


if __name__ == "__main__":
    sys.exit(main())
