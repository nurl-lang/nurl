# Compiler test suite

Every `*.nu` file in this directory is a compiler test. The runner
compiles it with `build/nurlc`, links it with `stdlib/runtime.o`, runs
the binary, and compares the captured outcome against a **per-test
golden file** in `outputs/<name>.txt`.

```
./build.sh                      # builds nurlc, then runs the suite
./compiler/tests/run_tests.sh   # just the suite (nurlc must be built)
```

A run is green only when **every** test matches its golden, no golden
is missing, and no golden is orphaned. Wall-clock target: under 3 min
(currently ~80 s, fully parallel).

## How a test is classified (by filename prefix)

| Prefix              | Expected outcome                                   |
|---------------------|----------------------------------------------------|
| *(none)*            | compiles, links, runs — golden records exit + stdout |
| `should_fail_*`     | compile **fails** (golden: `COMPILE FAIL` — the text is *not* kept) |
| `diag_*`            | compile fails and the **diagnostic text is baselined** — use this whenever the wording is the point |
| `borrow_*`          | borrow-checker rejects it; the diagnostic is baselined. `borrow_strict_*` only fire under `--strict-borrowck` |
| `should_warn_*`     | compiles, but the warning text is baselined        |
| `*_mod` `*_helper` `*_lib` | not a test — a module `$`-imported by another test (skipped) |
| `http_*` `net_*`    | network-dependent; most are skipped unless `NURL_HTTP_TESTS=1` / `NURL_NET_TESTS=1` |

### `should_fail_*` vs `diag_*`

`should_fail_*` records one word: `COMPILE FAIL`. It proves the compiler
*rejects* the program and nothing about what it says while doing it, so a
message can be gutted down to "expected ')'" without a single golden
moving. `diag_*` keeps the whole diagnostic.

The `ax` goal — a model handed a compile error learns the rule and the
fix from the message alone — lives entirely in text `should_fail_*`
throws away. **New negative tests should be `diag_*` unless the wording
genuinely does not matter.**

## Diagnostic coverage

`./tools/check_diag_coverage.sh` compiles the corpus, matches every
emitted diagnostic back to its site in `compiler/nurlc.nu`, and lists
the sites nothing made speak. An unfired message is unverified in every
way that matters: its wording has never been read next to the program
that caused it, its caret placement has never been checked, and it may
be dead outright — preempted by a looser check upstream, so the good
message exists and the user still gets the generic one.

The check ratchets against `tools/diag_coverage_baseline.txt`: existing
gaps do not fail, a **new** die site with no test that fires it does.
Adding a diagnostic and adding the program that triggers it are one
change, not two.

## Golden files (`outputs/`)

One file per test, holding exactly the record the runner builds:

```
COMPILE OK
LINK OK
EXIT 0
OUTPUT
<stdout+stderr, capped at 200 lines>
```

These files **are** the regression baseline — they are committed. A
test that drifts touches one file; the diff is surgical and reviewable,
never a multi-thousand-line rebaseline. The runner enforces an exact
bijection between tests and goldens:

* a test with **no** golden → `MISSING` (run fails) — no silent gaps.
* a golden with **no** test → `ORPHAN` (run fails) — no stale baselines.

## Updating goldens (when a change is intentional)

```
./compiler/tests/run_tests.sh --update            # rewrite all goldens
./compiler/tests/run_tests.sh --update vec_basic   # just one (or a few)
```

Review the resulting `git diff compiler/tests/outputs/` and commit it
alongside the code change that caused it.

## Adding a test

Drop `my_feature.nu` in this directory, then
`./compiler/tests/run_tests.sh --update my_feature` to mint its golden.
Commit both files. That's it.

## Determinism

Tests run in parallel (`NURL_TEST_JOBS`, default = `nproc`). Each test
binary executes in its own scratch directory under `build/tests/run/`,
so relative-path file side effects can't collide between concurrent
tests. Keep tests free of wall-clock, randomness, network, and
absolute shared paths (`/tmp/fixed_name`) so their output is stable —
otherwise gate them behind `NURL_NET_TESTS=1`.

## Sanitized runs

`./compiler/tests/run_san_tests.sh` re-runs the corpus under
ASan/UBSan (requires `./build.sh --san` first). It has its own
pass/fail logic and does not use the goldens.
