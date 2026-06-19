# Generation-accuracy results

> First-pass compile + correct-output rates for model-generated solutions to
> the 7 matched tasks in `tasks.json`. Each cell is `n/7`. Generated with
> `generate.py`, scored with `score.py`. Reproduce per `README.md`.
>
> This file is curated. `score.py --md` writes a bare scoreboard; the
> interpretation below is added by hand.

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
