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
               "`Arc` is the thread-safe counterpart.",
        "expect": REJECT_DEFAULT,
        "expect_msg": ["which is an Rc"],
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
            "option-payload-matches": prog(
                "    : ?i o @ ?i { T 42 }\n"
                "    ?? o { T v → ^ v  F → ^ 0 }", prelude=""),
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
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=1:symbolize=0")
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
          f"{len(invalid)} invalid template(s)")
    for c, n in invalid:
        print(f"   INVALID    {c}/{n}: fix the template")
    for c, n, g in control_breaks:
        print(f"   REGRESSION {c}/{n}: correct code now rejected ({g})")
    for c, n in new_gaps:
        print(f"   NEW GAP    {c}/{n}")
    if args.verify:
        print("\n── worklist (most severe first)")
        rank = {"memory-unsafety": 0, "silent-wrong-value": 1,
                "diagnostic-consistency": 2}
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

    return 1 if (new_gaps or control_breaks or invalid) else 0


if __name__ == "__main__":
    sys.exit(main())
