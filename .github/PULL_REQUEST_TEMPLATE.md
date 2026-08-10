## Why

<!-- The problem, concretely. What breaks, what is missing, what is
     silently wrong. Name the observed behaviour — the wrong output, the
     measured number, the program that fails — not the intention.

     "Improve error messages" is not a Why. "__kw_default_or_die told the
     reader NURL has no default parameter values, which it has had since
     kwargs" is: a reviewer can check it. -->

## What

<!-- The change. Enough that a reviewer can read the diff in the order
     you wrote it and can tell which parts are load-bearing. Call out
     anything that alters observable behaviour, and say why the goldens
     moved if they moved. -->

## Proof

<!-- What you ran, and what it actually said. Paste the real summary
     line rather than a paraphrase of it:

       ./build.sh                     # bootstrap fixed point + corpus
       ./compiler/tests/run_tests.sh  # PASS n · FAIL n · MISSING n · ORPHAN n

     If something failed for reasons that predate your change — a missing
     optional dependency, no network, a flaky test — list those failures
     BY NAME and say so. A reviewer cannot tell an environment failure
     from a regression at a glance, and you can.

     Do not report a gate you did not run. "Not run locally, left to CI"
     is a perfectly good answer.

     Compiler changes: docs/dev/COMPILER_INTERNALS.md §5 gives the gates
     and the order to run them in. -->

## Known remaining

<!-- What this change deliberately does NOT fix, and why. Delete the
     heading only if the answer is genuinely nothing.

     Scoping work down is fine and often right. Scoping it down silently
     is what costs a reviewer their afternoon. -->

---

<!-- ─────────────────────────────────────────────────────────────────
     For automated contributors — read this before filling in the
     sections above. It renders as nothing, so leave it in or delete
     it as you prefer.

  * Do not claim a gate passed unless you ran it and read the output.
    A PR body asserting a green suite over a red one is the single
    failure mode that costs a maintainer the most time.

  * Report what you actually did, including the parts that did not
    work. "The third case is still wrong, here is why" is worth more
    than a clean-looking PR that quietly dropped it.

  * Stay inside the scope you were given. Unrelated fixes you noticed
    along the way belong in their own PR — CONTRIBUTING.md asks for
    small, focused PRs and means it.

  * Language-surface changes — new syntax, grammar, type-system rules —
    need an issue FIRST. The grammar is deliberately small and every
    addition has to earn its keep. Do not land one sideways inside a
    bug fix.

  * A rejected program is a test, and the prefix decides what is kept:
    `diag_*.nu` baselines the diagnostic TEXT, `should_fail_*.nu`
    records only that compilation failed. If the wording is the point —
    and for an error message it usually is — use `diag_*`.

  * Disclose that the change was machine-authored. Every PR in this
    repo already does.
     ───────────────────────────────────────────────────────────────── -->
