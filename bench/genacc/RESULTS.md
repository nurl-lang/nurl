# Generation-accuracy results

> First-pass compile + correct-output rates for model-generated solutions to
> the 7 matched tasks in `tasks.json`. Each cell is `n/7`. Generated with
> `generate.py`, scored with `score.py`. Reproduce per `README.md`.
>
> This file is curated. `score.py --md` writes a bare scoreboard; the
> interpretation below is added by hand.

## Headline

A weak model (`claude-haiku-4-5`) cannot write NURL from memory **at all**
(0/35 — it falls back to writing Rust). Given NURL's **one-page** grammar
reference, the same model jumps to **80% correct first-try (28/35)** — **equal
to Rust (80%) and within five points of Python (85%)**, two languages it has
seen millions of lines of in training. The regular grammar appears genuinely
learnable from a single page. This is the affirmative LLM-native result the
token-count study could not provide; raw token count remains a loss for NURL
(see [`../TOKEN_EFFICIENCY.md`](../TOKEN_EFFICIENCY.md)).

## Run 2 — `claude-haiku-4-5-20251001`, 5 samples/task, temp 0.7 (the discriminating run)

| condition                         | first-pass compile | correct output |
|-----------------------------------|-------------------:|---------------:|
| **NURL — no primer** (raw recall) | 0/35 (0%)          | 0/35 (0%)      |
| **NURL — one-page primer**        | 29/35 (82%)        | 28/35 (80%)    |
| Python (in-distribution, no primer) | 35/35 (100%)     | 30/35 (85%)    |
| Rust (in-distribution, no primer) | 33/35 (94%)        | 28/35 (80%)    |

### Reading it honestly

- **The headline signal is the 0% → 80% jump**, not NURL "beating" anyone. With
  no primer, haiku doesn't know the language exists — every sample is literally
  Rust (`fn fib(n: i32) -> i32 { return fib(n-1) + fib(n-2); }`), so the NURL
  compiler rejects it at token 1. One page of reference closes almost the entire
  gap to languages with massive training presence. That is strong evidence for
  the regularity/local-semantics claim.
- **No language dominates per task; the failures are task-specific and small.**
  NURL missed on `collatz` (3/5), `matmul` (2/5), `rot13` (1/5), `quicksort`
  (1/5). Python's only misses were `rot13` (5/5 — every sample appended a
  trailing space to the input string, `7510` vs `7478`). Rust missed `rot13`
  (5/5, same kind of spec slip) and `quicksort` (2/5). On the string task NURL
  was actually the *most* reliable. The correct-output spread (80–85%) is within
  noise for N=35; treat the three primed/in-distribution columns as a tie.
- **This is a "with reference provided" result** — a statement about how
  learnable the grammar is from its rules, not about zero-context recall (which
  is 0%, exactly because the language is out-of-distribution).

### Caveats

Seven small algorithmic tasks, one weak model, 5 samples — a starter signal, not
a publication. The compile gap (NURL 82% vs Python 100%) is real and worth
chasing: the NURL compile failures are the most useful artifacts here (they show
which grammar corners a model still trips on from one page). Extend `tasks.json`
with non-arithmetic shapes and repeat on more models to firm this up.

## Run 1 — `claude-sonnet-4-6`, 1 sample/task, temp 0 (NURL primed; Py/Rust not)

| language | first-pass compile | correct output |
|----------|-------------------:|---------------:|
| NURL     | 7/7 (100%)         | 7/7 (100%)     |
| Python   | 7/7 (100%)         | 7/7 (100%)     |
| Rust     | 7/7 (100%)         | 7/7 (100%)     |

### What this does and does not show

**Does show (a real, if modest, point for the thesis):** given a *one-page*
grammar reference, a strong model writes **correct, idiomatic NURL on the first
try** for every task — including ones with manual memory management and
recursion. The generated `quicksort.nu`, for example, declared its own
`malloc`/`free` FFI, indexed raw pointers (`. arr hi`), used prefix arithmetic
(`% + * x 1103515245 12345 1048576`), obeyed the void-function rule (a `?`
guard instead of `^`), and cast correctly on free (`# *u a`). NURL was **not**
disadvantaged versus two languages the model knows from a vast training corpus.
That is consistent with "the regular grammar is learnable from a page."

**Does NOT show NURL is *better*:** this is a **ceiling effect.** A strong
model on small, well-specified algorithmic tasks scores 100% in every language,
so the experiment has no resolution — it cannot rank the languages. A skeptic
correctly says "the tasks are too easy."

### To make it discriminate (next runs)

The harness is built to push past the ceiling; these need an `ANTHROPIC_API_KEY`:

1. **Weaker model** — small models make the syntactic mistakes that separate a
   regular grammar from an irregular one:
   ```sh
   python3 bench/genacc/generate.py --model claude-haiku-4-5-20251001 \
       --runs 5 --temperature 0.7 --tag t07
   python3 bench/genacc/score.py claude-haiku-4-5-20251001__t07
   ```
   (5 samples/task at temp 0.7 turns a binary pass/fail into a rate.)

2. **The "what the primer buys" contrast** — NURL with vs without its reference,
   to show how much correctness a single page unlocks:
   ```sh
   python3 bench/genacc/generate.py --model claude-haiku-4-5-20251001 \
       --runs 5 --temperature 0.7 --langs nurl --no-primer --tag noprimer
   python3 bench/genacc/score.py claude-haiku-4-5-20251001__noprimer
   ```
   Expect this floor to be low (raw recall of an out-of-distribution language);
   the *gap* up to the primed run is the grammar-learnability signal.

3. **Harder / more tasks** — extend `tasks.json` with parsing, state machines,
   and string-munging shapes (verify each new expected output with
   `bench/verify.sh` first).
