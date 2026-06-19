# Generation-accuracy harness

The token-efficiency study ([`../TOKEN_EFFICIENCY.md`](../TOKEN_EFFICIENCY.md))
retired one claim: on today's tokenisers NURL is **not** fewer tokens than
Python. This harness measures the *affirmative* LLM-native claim that the
token study cannot — **does a model write correct NURL on the first try more
reliably than mainstream languages, because the grammar is regular and
locally decodable?**

Two metrics per (task, language):

- **first-pass compile** — does the generated program build with **zero**
  human edits?
- **correct output** — does it print exactly the expected bytes?

> ⚠️ **Status: harness complete, study not yet run.** This directory ships the
> tasks, the generator, the scorer, and a reference oracle — but no model
> results, because running it needs an `ANTHROPIC_API_KEY` that this repo does
> not carry. Run it yourself (below); do not cite numbers that aren't here.

## Files

```
genacc/
├── tasks.json          7 self-contained tasks; spec + verified expected output
├── primers/nurl.md     one-page NURL reference (the fair-test input; see below)
├── generate.py         calls a fixed model, saves one program per (task,lang)
├── score.py            compiles + runs each program, scores compile & correctness
├── README.md           this file
└── solutions/
    └── _reference/     ORACLE: the hand-written, verified bench programs.
                        `score.py _reference` must report 100%/100% — it is the
                        scorer's self-test, not a model result.
```

## The fairness question (read before interpreting any result)

Every model has seen millions of lines of Python and Rust and almost no NURL.
A naive "write it from memory" test would therefore measure **training
exposure**, not grammar quality — the same confound that sank the token study.

So the default, honest design tests the *grammar*: the model is handed NURL's
one-page reference (`primers/nurl.md`) in the system prompt, then asked to
solve the task. Python and Rust are in-distribution and get no primer. The
question becomes: *given the language's rules, does NURL's regular grammar let
a model produce correct code first-try at a rate comparable to (or better
than) languages it already knows by heart?*

The knobs let you measure the other framings too:

- `--primer-all` — give every language its primer (full symmetry).
- `--no-primer` — give none (raw from-memory familiarity; expect NURL to lose,
  and that result is about corpus exposure, not the grammar).

Report which mode produced any number you quote.

## Running it

```sh
export ANTHROPIC_API_KEY=sk-ant-...
# generate (default: claude-sonnet-4-6, NURL gets the primer, temp 0)
python3 bench/genacc/generate.py --model claude-sonnet-4-6 --runs 1

# score what was generated, optionally writing a markdown scoreboard
python3 bench/genacc/score.py claude-sonnet-4-6 --md bench/genacc/RESULTS.md
```

`--runs N` draws N independent samples per (task, language) — pair it with
`--temperature 0.7` to estimate a pass rate rather than a single-shot result.
Smaller models (e.g. `claude-haiku-4-5-20251001`) tend to show grammar effects
more starkly than large ones and are cheaper to sample heavily.

## Honest caveats baked in

- **Seven small algorithmic tasks** is a starter set, not a representative
  sample of agent work. Extend `tasks.json` (add a `spec` + a verified
  `expected`; confirm the expected output with `bench/verify.sh` first).
- The result is conditional on **"reference provided"** — it is a statement
  about the grammar given the rules, not about zero-context recall.
- `score.py` calls no model; it only builds and runs. Generation and scoring
  are separate so results are inspectable and re-scorable.
