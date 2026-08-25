# tools/fuzz — fuzzing for nurlc and the stdlib parsers

Three fuzzers, all run weekly (and on demand) by
[`.github/workflows/fuzz.yml`](../../.github/workflows/fuzz.yml), never as a
per-PR gate. Any finding fails the run and uploads its reproducer inputs
from `failures/` as an artifact. After every run the workflow renders
[`FUZZRESULTS.md`](../../FUZZRESULTS.md) via `report.py` and commits it to
main (the same publish-the-evidence flow `bench.yml` uses); the curated log
of real bugs lives in [`FINDINGS.json`](FINDINGS.json).

1. **Differential miscompile fuzzer, integer** (`fuzz.sh` + `gen.py`) —
   described below: oracle-backed hunt for silent integer/float miscompiles.
2. **Differential miscompile fuzzer, structural** (`FUZZ_GEN=struct fuzz.sh`
   + `genprog.py`) — whole programs over the structural surface: enums with
   N-ary mixed payloads (`i8…u64`, `f`, `s`), match with guards / literal
   constraints / or-patterns, struct field writes, **nested aggregates and
   struct-payload enums**, **generic functions and generic structs**
   instantiated at every sized type (and at a concrete struct whose *name*
   is tparam-shaped), **`?T` and `!T E` with `\` try-propagation**,
   **traits** with a required method, a default method and a bounded
   generic, closures (creation-time scalar capture), while/foreach loops
   **with `break` and `continue`**, `;` defer (reachability-armed, LIFO),
   `% Drop` destructors across scope shapes, string/Vec/slice ownership
   traffic **including containers whose element is a struct**, helper calls
   and self-recursion. The same script is the statement-level oracle.
   `FUZZ_SAN_EVERY=N` additionally builds every Nth seed with
   ASan+LSan+UBSan and runs it leak-detection-on: a leak or UAF in the
   generated ownership traffic is a finding even when stdout matches — this
   is the leg that hunts auto-drop bugs. `FUZZ_WASM_EVERY=N` compiles every
   Nth seed to wasm32-wasi (`packages/wasmbuilder`) and runs it under the
   reference wasmtime — a THIRD independent execution environment against
   the same oracle, hunting target-dependent codegen (32-bit pointers, i64
   payload slots). Requires zig + wasmtime.
2b. **Reducer** (`reduce.py`) — not a fuzzer: the thing that makes a finding
   usable. Called automatically by `fuzz.sh` on every finding; see
   [Reducing a finding](#reducing-a-finding-reducepy) below.

3. **Mutational parser fuzzer** (`fuzz_parsers.sh` + `fuzz_parsers.py` +
   `parse_harness.nu`) — mutates seeds for the untrusted-input parsers
   (x509/DER, cbor, msgpack, json, yaml, xml, toml) against an ASan+UBSan
   harness; a crash / out-of-bounds / UB / hang is a bug. Run it locally with
   `./tools/fuzz/fuzz_parsers.sh [SEED] [ITERS] [TIMEOUT]` after `./build.sh`.

All are deterministic per seed, so a finding reproduces. Seed corpora live
in-tree (`gen.py` / `genprog.py` generators; `fuzz_parsers.py`'s
`TEXT_SEEDS`/`BINARY_SEEDS`).

## Reducing a finding (`reduce.py`)

A raw seed is 150–400 lines across a dozen unrelated features, and the bug is
usually two of them interacting. Working out which two by hand costs more than
the fix does, so `fuzz.sh` shrinks every finding before filing it: alongside
`failures/struct_seed_N.nu` you get `failures/struct_seed_N.min.nu`, typically
a few dozen lines. The closure-drop miscompile of 2026-08-26 came out of a
397-line seed as 23 lines in 19 seconds — the enum, the closure and nothing
else.

Reduction is ddmin over **statements** (brace-balanced groups, so a five-line
`??` block is one deletable item) and then over lines, repeated until a whole
sweep changes nothing.

The property must survive line deletion or the reducer converges on a
different bug, so it is fingerprinted from the *original* failure — the
normalised error message, the ASan report kind, or the specific expectation
that disagreed — and every candidate must reproduce **that**. Without the
fingerprint, "does not compile" is true of almost any mangled program and
ddmin cheerfully reports a four-line file whose only problem is an undefined
identifier it created itself.

| mode | property | used for |
|---|---|---|
| `build` | fails to compile with the same error | build failures (the largest class) |
| `crash` | compiles, exits with the same nonzero status | runtime aborts |
| `diverge` | `-O0` and `-O2` disagree with each other | opt-sensitive miscompiles; needs no oracle |
| `check` | the self-checking program reports the same failed expectation | oracle mismatches, including *wrong at every opt level* |
| `sanitize` | same ASan/LSan/UBSan report under `NURL_SAN=1` | leaks, UAF, double free |

`check` is why `genprog.py --selfcheck` exists. It emits the same program with
each expected value embedded next to the expression that produces it, so the
program is its own oracle and exits nonzero on a mismatch. Deleting a line
then cannot desynchronise the checks that remain — which is exactly what
deleting a line would do to the external oracle file, and why a "wrong at
every optimisation level" miscompile could not be reduced before.

```bash
python3 tools/fuzz/genprog.py 684 --selfcheck > bug.nu
tools/fuzz/reduce.py bug.nu --mode check -o bug.min.nu
```

`--max-tests` bounds the compile budget (default 400, ~20–60 s); it stops with
whatever it has rather than running unbounded, so CI can always call it.
`FUZZ_REDUCE=0` turns reduction off, `FUZZ_REDUCE_TESTS` sets the budget. The
wasm leg is not reduced — its property needs wasmbuilder and wasmtime in the
loop — so those findings keep the full program only.

## Differential fuzzer — how it works

`gen.py` builds a random **integer expression tree** over NURL's sized
types (`i8 i16 i32 i64 u u16 u32 u64`) and operators (`+ - * / % & | << >>`
and width casts `# T`). It then does two things from the *same* tree:

1. **Emits a self-contained NURL program** that computes each expression
   and prints its exact 64-bit pattern (16 hex digits, MSB first — robust
   to arithmetic-vs-logical shift, so the print path can't mask a bug).
2. **Computes the expected output itself**, in Python, with explicit
   two's-complement / width / signedness semantics (the *oracle*).

`fuzz.sh` compiles each program at **`-O0` and `-O2`** and requires:

```
stdout(-O0) == stdout(-O2) == oracle      (value correctness)
exit(-O0)   == exit(-O2)   == 0           (no crash)
```

Any divergence is a compiler bug. Because the oracle is an independent
implementation, this catches miscompiles that are wrong at *every*
optimisation level (frontend codegen bugs) — not just opt-sensitive ones.

The generator is deterministic per seed, so every failure reproduces
exactly, and is biased toward the historically fragile surface: width
coercions (`# T` trunc/sext/zext), unsigned arithmetic
(udiv/urem/lshr/icmp-u), and mixed signed/unsigned operands.

No UB is generated: divisors are positive literals (no `/0`, no
`INT_MIN/-1`), shift amounts are `< width`, and `nurlc` emits plain
wrapping `add`/`mul` (no `nsw`/`nuw`), so signed overflow is defined.

## Usage

```sh
# Build the compiler first (needs build/nurlc + stdlib/runtime.o).
./build.sh

# Run 200 seeds (default), 12 expressions each, depth 4:
tools/fuzz/fuzz.sh

# Custom: START COUNT EXPRS DEPTH
tools/fuzz/fuzz.sh 1 1000 16 6

# Inspect / reproduce one seed:
python3 tools/fuzz/gen.py 42 --exprs 12 --depth 5            # the program
python3 tools/fuzz/gen.py 42 --exprs 12 --depth 5 --oracle   # expected output
```

Failures are saved under `tools/fuzz/failures/` as `seed_N.nu` +
`seed_N.expected` + `seed_N.out0/.out2` + `seed_N.diff_o0` for triage.

## Probe dimensions

- Integer expression trees: `+ - * / % & | ^^ << >>` and `# T` width casts.
- Float arithmetic: `# i64 OP # f a # f b` (fadd/fsub/fmul/fdiv) over
  bounded int-derived doubles, truncated back to i64 — exact f64 oracle.
- Structs: declare a struct of random-typed fields, construct an instance
  (field initialisers of a different type → field store coercion), and read
  each field back — probes `gen_member` field-load + `gen_agg_lit`
  field-store signedness.
- `let` bindings with a declared type that may differ from the initialiser
  (store coercion via `coerce_store_val`), plus variable reuse (binding
  reload signedness).
- Comparison operators (`== != < <= > >=`) — signed-vs-unsigned `icmp`.
- `int → float → int` round-trips (`# i64 # f # T v` / `# f32`) over
  exactly-representable values — probes `uitofp`/`sitofp`, `fptosi`, and
  side-channel cleanliness across the float conversion, all without needing
  to print a float bit-exactly.

## Bugs found (2026-06-02)

Seven silent miscompiles, all fixed at the root in `compiler/nurlc.nu`;
locked in by `compiler/tests/cast_signedness.nu` + `cast_int_float.nu` +
`struct_field_signedness.nu`.
Every one is the same underlying hazard: **the LLVM integer type cannot
carry NURL's signedness, so it must ride the `__last_unsigned__`
side-channel — and any path that forgets to set/clear it miscompiles.**

1. `# i64 # u 217` sign-extended an unsigned byte (−39, not 217). A nested
   cast-to-unsigned never set `__last_unsigned__`.
2. Signed `i8` arithmetic treated as unsigned: `gen_binary` inferred
   unsignedness from the LLVM type `i8`, which both `u` and signed `i8`
   share. Signed i8 `/ % >> <` picked udiv/urem/lshr/icmp-u.
3. Unsigned int → float used `sitofp` (unsigned values went negative).
4. Float → int ignored target signedness (no `fptoui`).
5. A float result leaked its source int's stale unsigned flag into a later
   `*`/`/` (negative product divided with `udiv`).
6. Reading an unsigned struct field sign-extended (`gen_member` didn't
   surface the field's signedness).
7. Constructing a wider field from a narrower unsigned value sign-extended
   (`gen_agg_lit` field-store hardcoded `sext`).

## Bugs found (2026-08-03, structural generator bring-up)

Four more, all fixed at the root the same day (see `FINDINGS.json` and the
regression tests named there): a `;` defer disabling every auto-drop in its
function (leak class), scoped defers emitting a branch to a nonexistent
cleanup block (invalid IR), field/element stores skipping width coercion
(invalid IR), and non-canonical narrow-int enum payload slots making a
match literal constraint disagree with the arm's own payload binding
(miscompile class).

## Bugs found (2026-08-26, structural surface wave 2)

Extending `genprog.py` past scalars — nested aggregates, generic
instantiation, `?T`/`!T E`, traits, loop control, containers of structs —
turned up three more, each fixed at the root with its own regression test:

1. **A closure body dropped the enclosing frame's values.** A `^`-bodied
   closure literal written after an owned value (`% Drop`, String, owned
   struct field) ended the *lifted* function with the outer frame's drop
   battery, loading an alloca that only exists in the caller. Invalid IR at
   best; use-after-scope plus a double drop had the register resolved. Found
   in 3 of the first 25 seeds, as soon as the generator started putting
   droppable aggregates at function scope. (`closure_body_outer_drops.nu`)
2. **`break` / `continue` were rejected in every foreach body**, though the
   spec scopes both to "the innermost enclosing `~` loop body". The foreach's
   hidden index bump lived in the body's fall-through, so a `continue` would
   have skipped it; the bump now has its own landing pad.
   (`foreach_break_continue.nu`)
3. **A struct whose NAME is tparam-shaped** (`P`, `Q3`) could not be a
   generic type argument: instantiation was decided by spelling, so
   `( Vec P )` was skipped as still-abstract and the program died on
   `type 'Vec__P' has no field 'ctl'` pointing into the stdlib. Now decided
   by scope. (`generic_short_type_name.nu`)

The last two were found by hand-probing the surface while writing the
generators for it — which is the honest reason to write the generators.

## Scope / future

Covers integer + int↔float value semantics (`gen.py`) and the structural
surface (`genprog.py`), each executed natively at `-O0`/`-O2` and, on
sampled seeds, sanitized and on wasm32-wasi, with every finding reduced
before it is filed. Natural extensions (tracked in TODO.md): float
*arithmetic* with a rounding-aware oracle, trait-object (`dyn`) dispatch,
threads / `Arc` traffic against a deterministic oracle, and borrow-checker
soundness fuzzing (generate programs that MUST be rejected — the inverse
oracle, where a program that *compiles* is the finding).
