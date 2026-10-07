# Changelog

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

## [0.2.0] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more.

- `GcovObj`, `LineTab` and `Cov` are handles instead of `*T` pointers:
  every copy is the same object and the last owner releases it.
  `gcov_read` → `!GcovObj GcovErr`, `gcov_new` → `GcovObj`, `lines_build`
  → `LineTab`, `cov_new` → `Cov`; every function that took the pointer
  takes the handle. New lent accessors for code outside the modules:
  `linetab_maxline`, `linetab_exists`, `linetab_count`, `linetab_br`,
  `linetab_fnrow`, `cov_objects`.
- `gcov_free`, `linetab_free`, `cov_free` and `runresult_free` are optional
  early releases; every redundant release in the library, the CLI and the
  tests is gone. `nurl-cov gcov` on a 940 KB notes file runs 9.8 % fewer
  instructions, `nurl-cov report` 16.7 % fewer (same output).

## 0.1.0

First release: a test-coverage mapper for NURL, reading the compiler's
GCOV coverage graphs in pure NURL.

The toolchain has been able to *produce* coverage data since 0.53.0 —
`nurlc --coverage=PREFIX` emits the metadata LLVM's GCOV pass needs — but
reading it meant `llvm-cov`, and nothing turned it into an answer about a
package's test suite. This does both: it reads `.gcno` and `.gcda` itself,
and it drives a package's tests end to end.

**Why the numbers can be trusted.** `nurl-cov gcov` prints the annotated
listing in gcov's own format, and the test suite diffs it byte for byte
against `llvm-cov gcov -b -c -p` over programs from the compiler's own test
corpus — every line count, every branch outcome, every percentage. A
coverage report is a claim nobody can check by hand; two independent
readers of the same two files agreeing is what makes it checkable.

**A line is not the sum of its blocks.** A condition and the two arms it
guards all carry the same source line, and adding them reports a line
running three times as often as its function was entered. The count is the
traffic entering the line's blocks from outside them, plus what goes round
in circles inside them — the second half is what makes a one-line loop
report its iterations rather than its single entry. The first
implementation here added blocks up, and it was wrong on every `?` in the
language.

**Dead-code elimination hides exactly what coverage is for.** A function
nothing calls is removed before it can be counted, so the report omits the
gap instead of reporting it. Builds pass `--no-dce`; on a four-function
sample that one flag moved the score from 88.9% to an honest 72.7%. The
build driver could not forward the flag at all, which is fixed in the
toolchain rather than worked around here — hence the 0.67.0 requirement.

**The solver is gcov's, not an equivalent.** An iterative fixed point over
the same equations agrees with gcov on ordinary functions and disagrees on
anything that forks or exits abnormally, where it shows up as a percentage
quietly a few points wrong. This implements the edge propagation gcov
itself uses, synthetic exit-to-entry arc included.

**The reader is handed files it did not write.** A fuzz sweep over
truncations and byte flips of a real pair found a hang and twelve
segfaults, all the same mistake: a number taken from the file and used
without a bound.

  * A flipped byte named source line 1970155382. The per-line tables are
    indexed BY line number, so the reader sized a table from it. Anything
    past sixteen million is now a malformed file, not an allocation.
  * Another turned a string's word count into 738 million, and the read
    walked that far past the buffer. Every string span is now bounded by
    the record it sits in.
  * Another named a block the function does not have. An arc pointing
    outside the block table leaves the walk that solves the flow unable to
    mark where it has been, and it loops — a hang rather than a wrong
    number, which is the worse of the two. Block numbers are checked at
    parse time, as gcov checks them.
  * And a function's own checksums are now checked against the notes,
    which is what catches a notes file corrupted after its build stamp was
    written.

645 cases per seed over five seeds, no crash and no hang; every case above
is a regression test, and the suite runs a deterministic sweep of its own.

The same sweep turned up two things worth having anyway: the propagation
walk kept a count of the arcs it had consumed and re-walked the chain to
find the next one, which is quadratic in a block's degree, and the edge
index leaked the six empty vectors it replaced.

Output: a summary table, the uncovered line ranges and the functions
nothing called, an LCOV tracefile, one self-contained HTML page, JSON, and
`--fail-under` as a CI gate.
