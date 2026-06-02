# tools/fuzz — differential miscompile testing for nurlc

A generative, oracle-backed fuzzer that systematically hunts silent
integer miscompiles in `nurlc`. It complements the hand-written
`compiler/tests/` corpus: instead of checking a fixed set of programs, it
generates thousands of random ones and checks each against an independent
reference.

## How it works

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
- `let` bindings with a declared type that may differ from the initialiser
  (store coercion via `coerce_store_val`), plus variable reuse (binding
  reload signedness).
- Comparison operators (`== != < <= > >=`) — signed-vs-unsigned `icmp`.
- `int → float → int` round-trips (`# i64 # f # T v` / `# f32`) over
  exactly-representable values — probes `uitofp`/`sitofp`, `fptosi`, and
  side-channel cleanliness across the float conversion, all without needing
  to print a float bit-exactly.

## Bugs found (2026-06-02)

Five silent miscompiles, all fixed at the root in `compiler/nurlc.nu`;
locked in by `compiler/tests/cast_signedness.nu` + `cast_int_float.nu`.
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

## Scope / future

Covers integer + int↔float value semantics. Natural extensions: float
*arithmetic* with a rounding-aware oracle (currently only exact-integer
round-trips), option/result construction + `??` match payload widths,
struct field round-trips, and `-O0`-vs-`-O2` divergence on
loop/recursion-heavy programs.
