# nurl-cov — test-coverage mapper for NURL

**Which lines do your tests actually run?** `nurl-cov` builds a package's
test suite with the compiler's coverage instrumentation, runs it, and reads
the resulting coverage graphs in pure NURL — no `llvm-cov`, no `gcov`,
nothing to install beyond the toolchain you already have.

```sh
nurlpkg install nurl-cov

cd packages/mypkg
nurl-cov run                              # build, run, report
nurl-cov run --uncovered                  # and name the lines nothing ran
nurl-cov run --fail-under 80              # turn it into a CI gate
nurl-cov run --html coverage.html         # one page you can send to someone
nurl-cov run --lcov coverage.info         # for Codecov, genhtml, your editor
```

```
File                                               lines   cover    branches     funcs
--------------------------------------------------------------------------------------
src/loader.nu                                      35/38   92.1%       10/20       2/2
src/template.nu                                  712/738   96.5%     431/578     66/79
--------------------------------------------------------------------------------------
TOTAL                                            747/776   96.3%     441/598     68/81

src/loader.nu
  uncovered lines: 45, 50, 57
src/template.nu
  uncovered lines: 60, 364, 368, 383, 391, 399, 496, 530, 539, 564, 638, 657, 659-664
  never called: __tset_find__fp4, __tpl_do_include__fp4, __tpl_apply_filter__fp6
```

## Why the numbers can be trusted

A coverage report is a claim nobody can check by hand. Two things make this
one checkable.

**It is verified against an independent implementation.** `nurl-cov gcov`
prints the annotated listing in `gcov`'s own format, and the test suite
diffs it byte for byte against `llvm-cov gcov -b -c -p` over programs from
the compiler's own test corpus: every line count, every branch outcome,
every percentage. Two readers of the same two files have to agree.

**It refuses to flatter you.** Dead-code elimination removes functions
nothing calls — exactly the code a coverage report exists to find — so
`nurl-cov` builds with `--no-dce`. On a four-function sample that one flag
moved the score from 88.9% to an honest 72.7%. Optimisation folds and
duplicates blocks until a line's count stops being a line's count, so it
builds at `-O0`.

## What it measures

| | |
| --- | --- |
| **lines** | how many times each line with code ran; `0` means nothing ran it |
| **branches** | each way out of a decision, and how often it was taken |
| **functions** | how often each function was entered, including the ones entered never |

A line's count is **not** the sum of its basic blocks. A condition and the
two arms it guards all carry the same source line, and adding them reports
a line running three times as often as its function was entered. The count
is the traffic *entering* the line's blocks from outside them, plus
whatever goes round in circles inside them — which is what makes a one-line
loop report its iterations rather than its single entry.

Every test binary is read separately and merged, so a helper that every
test calls reports the traffic of every test, and a line no test reaches is
the finding.

## CLI

```
nurl-cov run [options]            build tests/ instrumented, run them, report
nurl-cov report <dir> [options]   report on coverage graphs already written
nurl-cov gcov <dir|file.gcno>     annotated source, gcov's own format

  --tests DIR      where the tests live (default tests)
  --work DIR       where instrumented binaries go (default .nurl-cov)
  --include PREFIX keep only files under PREFIX (repeatable; default src)
  --all            keep every file, the stdlib included
  --uncovered      list the line ranges nothing executed
  --lcov FILE      write an LCOV tracefile
  --html FILE      write one self-contained HTML report
  --json FILE      write machine-readable JSON
  --fail-under PCT exit non-zero below this line coverage
  --quiet          suppress the summary table
  --no-color       plain text, even at a terminal
```

Exit codes: `0` all good · `1` below the floor, or a test failed · `2` a
usage error or a build that would not compile. A gate that cannot tell
"untested" from "failed to build" is not a gate, so those are different
codes.

By default only files under `src/` are reported: a test binary compiles the
whole stdlib in with it, and reporting that would drown the package you are
actually trying to measure. `--all` includes everything, and `--include`
picks a different subtree.

## In CI

```yaml
- run: nurl-cov run --fail-under 80 --lcov coverage.info
- uses: codecov/codecov-action@v4
  with: { files: coverage.info }
```

The LCOV tracefile is the ordinary `.info` format — `genhtml` renders it,
Codecov and Coveralls ingest it, and editors draw their gutter from it.

## Library

Every layer is importable on its own.

```nurl
$ `deps/nurl-cov/src/gcov.nu`
$ `deps/nurl-cov/src/lines.nu`
$ `deps/nurl-cov/src/model.nu`

?? ( gcov_read `build/tests.gcno` `build/tests.gcda` ) {
    T o → {
        : *Cov c ( cov_new )
        ( cov_add_object c o )
        : CovStat t ( cov_total c )
        ( nurl_println ( nurl_str_int . t lines_hit ) )
        ( cov_free c )
        ( gcov_free o )
    }
    F e → ( nurl_eprintln ( gcov_err_name e ) )
}
```

| call | |
| --- | --- |
| `( gcov_read notes data )` → `!*GcovObj GcovErr` | parse both graphs and solve the flow |
| `( lines_build o src )` → `*LineTab` | per-line counts and branches for one source file |
| `( cov_add_object c o )` | fold one object into a merged model |
| `( cov_total c )` → `CovStat` | lines/branches/functions, found and hit |
| `( lcov_render c )` / `( json_render c )` / `( html_render … )` → `String` | the output formats |
| `( gcovtext_render o src )` → `String` | the gcov-compatible annotated listing |

A missing `.gcda` is not an error. It is the answer "this was built and
never run", every count is zero, and a report has to be able to say that.

## How it works

`nurlc --coverage=PREFIX` asks LLVM's GCOV pass for two files: `PREFIX.gcno`
holds one control-flow graph per function plus the source lines each basic
block came from, and `PREFIX.gcda` holds one counter per instrumented arc,
written when the program exits. Re-running accumulates.

Neither file holds a per-line count. Only the arcs *outside* the
instrumenter's spanning tree are counted; everything else follows from
conservation of flow. `src/gcov.nu` parses both files and recovers the rest
with gcov's own edge propagation, `src/lines.nu` turns blocks into lines,
and the rest is reporting.

## Requirements

A toolchain whose build driver forwards `--no-dce` (NURL 0.67.0 and newer),
and a platform where `--coverage` is supported — Linux and macOS today.

## Licence

MIT OR Apache-2.0.
