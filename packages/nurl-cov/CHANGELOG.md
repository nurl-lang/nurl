# Changelog

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

Output: a summary table, the uncovered line ranges and the functions
nothing called, an LCOV tracefile, one self-contained HTML page, JSON, and
`--fail-under` as a CI gate.
