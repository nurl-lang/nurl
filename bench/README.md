# NURL benchmarks

Comparative micro-benchmarks between NURL and the four most accessible
peer languages: **Python 3** (interpreter, the obvious "scripting"
baseline NURL is often compared to), **Rust** (the closest peer in the
LLVM-backed-systems-language design space), and **Node.js** (V8 JIT,
the JavaScript point of comparison).

Goal: replace the README's "Python ~46 tokens, C ~30 tokens, NURL ~13
tokens" framing with wall-clock numbers and honest commentary about
where NURL wins, where it ties, and where it loses.

`critic.md` §10 specifically called out NURL's "38× keep-alive speedup"
claim as a NURL-vs-NURL number, not a NURL-vs-peers number. This
directory exists to make peer comparisons available, runnable, and
reproducible on any developer's machine.

## Layout

Each benchmark ships as one source file per language at the top of
this directory:

```
bench/
├── lcg.{nu,py,rs,js}        — 100M-step linear congruential generator
├── sieve.{nu,py,rs,js}      — Sieve of Eratosthenes, π(10_000_000)
├── json_parse.{nu,py,rs,js} — parse a ~64 KB JSON file 5 times
├── data.json                — input for json_parse (regenerated on first run)
├── gen_data.py              — JSON generator (stable seed → deterministic bytes)
├── run.sh                   — compile, run, median-of-N, print table
└── RESULTS.md               — captured numbers from one specific machine
```

## Running

```sh
./bench/run.sh             # default: 5 runs of every benchmark, 30s/run timeout
./bench/run.sh 3           # 3 runs
./bench/run.sh --bench lcg # just one benchmark
./bench/run.sh --timeout 60 # raise the per-run timeout (slow-language cell otherwise reports >30s)
```

The runner detects which compilers/interpreters are installed
(`build/nurlc`, `python3`, `rustc`, `node`) and prints `n/a` for any
language that's missing. Each cell reports the **median wall-clock ms**
across the requested runs — median (not mean) so a transient stall
doesn't poison the cell.

## Benchmark choice rationale

| Bench | Tests | Why this shape |
|---|---|---|
| `lcg` | Tight integer loop, i64 wrap-around, single-stream data dependency | Pure compute; the data dependency between iterations defeats LLVM's "compute the closed form" optimisation that would otherwise collapse `sum 1..N`. |
| `sieve` | Random-access byte writes + a final scan over the array | Memory bandwidth + branch prediction; the marking step has irregular stride and no tractable closed form. |
| `json_parse` | Allocator pressure + string handling + recursive descent | Approximates real stdlib work: every language uses **what ships in its standard distribution** (Python `json`, Node `JSON.parse`, NURL `stdlib/ext/json.nu`). Rust has no JSON in stdlib, so the Rust file includes a small hand-written recursive-descent parser — the same "no external dependencies" rule as the other three. |

## What this is and isn't

**Is:** a fair-shaped, reproducible look at where NURL's compiled-LLVM
performance lands relative to the languages a NURL user is most likely
to be coming from. Numbers should reproduce within ~20 % on any modern
x86_64 box.

**Isn't:**

- A peer-reviewed throughput benchmark suite. There's no warm-up loop,
  no statistical analysis beyond a median. The cells are good for
  order-of-magnitude reasoning; don't draw sub-10% conclusions.
- A measurement of NURL's HTTP server vs. Go `net/http` / Rust `hyper`.
  That's the next benchmark suite worth building (see `HTTP_SERVER_PLAN.md`).
- A measurement of LLM agent throughput / token efficiency. That's a
  whole different methodology — see the "controlled study" point in
  `critic.md` §20.

See [`RESULTS.md`](RESULTS.md) for the numbers from one specific
machine plus the commentary.
