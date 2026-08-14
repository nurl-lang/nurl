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
ACCEPT = "accept"           # compiles under both default and --strict-borrowck
REJECT_DEFAULT = "reject"   # the default checker rejects it
REJECT_STRICT = "strict"    # only --strict-borrowck rejects it

# A class states the WEAKEST verdict it will accept. `reject` is stronger
# than `strict` is stronger than `accept`; a spelling that does better
# than its class demands is fine and is reported, not failed.
STRENGTH = {ACCEPT: 0, REJECT_STRICT: 1, REJECT_DEFAULT: 2}

PRELUDE_VEC = "$ `stdlib/core/vec.nu`\n"
PRELUDE_ARC = "$ `stdlib/std/arc.nu`\n$ `stdlib/std/thread.nu`\n$ `stdlib/core/vec.nu`\n"


def prog(body, prelude=PRELUDE_VEC, extra=""):
    return f"{prelude}{extra}\n@ main → i {{\n{body}\n    ^ 0\n}}\n"


# ── The classes ─────────────────────────────────────────────────────────

CLASSES = [
    {
        "name": "handle-second-name",
        "doc": "A heap handle acquires a SECOND name and both names are "
               "freed. However the second name is spelled, exactly one "
               "owner may free the buffer, so every spelling here is a "
               "double free.",
        "expect": REJECT_STRICT,
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
                "    : ( Vec i ) b ? > c 0 ( ? > c 0 a ( vec_new [i] ) ) ( vec_new [i] )\n"
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
        "doc": "The payload of an option/result literal is not the type "
               "the option was declared over. Field 1 carries T's real "
               "type in both forms, so none of these has anywhere to go.",
        "expect": REJECT_DEFAULT,
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
        "doc": "A thread closure mutates the CONTENTS of an Arc it did "
               "not create, with no lock held. Arc makes the refcount "
               "atomic and nothing else.",
        "expect": REJECT_DEFAULT,
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
        "name": "controls",
        "doc": "Correct programs. A class of its own because a checker "
               "that rejects these is worse than one that misses a bug — "
               "every entry here is code someone would reasonably write.",
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


def verdict_of(src_path):
    """Normalised verdict + the diagnostic that produced it."""
    rej_def, err_def = compile_verdict(src_path, strict=False)
    if rej_def:
        return REJECT_DEFAULT, err_def
    rej_str, err_str = compile_verdict(src_path, strict=True)
    if rej_str:
        return REJECT_STRICT, err_str
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
    for cand in (ROOT / "stdlib" / "runtime.o", ROOT / "stdlib" / "runtime_san.o"):
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
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=1")
    try:
        run = subprocess.run([str(exe)], capture_output=True, timeout=30, env=env)
    except subprocess.TimeoutExpired:
        # Weaker evidence than a diagnosed report, but not nothing: a
        # double free that corrupts the allocator's free list spins
        # instead of aborting. Labelled so it is never mistaken for a
        # clean ASan diagnosis.
        return True, "hung (weak signal — inspect by hand)"
    out = (run.stderr or b"").decode("utf-8", "replace")
    for marker in ("AddressSanitizer", "LeakSanitizer", "runtime error:"):
        if marker in out:
            return True, marker
    if run.returncode < 0:
        return True, f"killed by signal {-run.returncode}"
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

    known = set()
    if KNOWN.exists():
        known = {tuple(x) for x in json.loads(KNOWN.read_text())["gaps"]}

    gaps, new_gaps, control_breaks, found = [], [], [], []
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="nurl-metamorph-"))

    for cls in CLASSES:
        if args.only and cls["name"] != args.only:
            continue
        want = cls["expect"]
        print(f"\n── {cls['name']}  (expect ≥ {want})")
        for name, src in cls["spellings"].items():
            p = tmp / f"{cls['name']}__{name}.nu"
            p.write_text(src)
            got, _err = verdict_of(p)
            ok = STRENGTH[got] >= STRENGTH[want]
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
          f"{len(control_breaks)} control regression(s)")
    for c, n, g in control_breaks:
        print(f"   REGRESSION {c}/{n}: correct code now rejected ({g})")
    for c, n in new_gaps:
        print(f"   NEW GAP    {c}/{n}")
    if args.verify and found:
        print(f"\n   {len(found)} gap(s) CONFIRMED broken at runtime:")
        for c, n, why in found:
            print(f"     {c}/{n}: {why}")

    return 1 if (new_gaps or control_breaks) else 0


if __name__ == "__main__":
    sys.exit(main())
