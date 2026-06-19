# Generation-accuracy harness

Does a model write **correct code on the first try** more readily when the
grammar is regular and locally decodable? This harness measures that for NURL
against mainstream languages, and reports it alongside the BPE token cost of
what the model emitted.

It is the affirmative counterpart to the matched-source token study
([`../TOKEN_EFFICIENCY.md`](../TOKEN_EFFICIENCY.md)). That study retired one
claim — on today's tokenisers NURL is **not** fewer tokens than Python. This one
asks the question token count cannot: given the rules, can a model *produce
working NURL*? Our runs are in [`RESULTS.md`](RESULTS.md).

Three numbers per program, all **first-pass** (the model's first and only
attempt — no human edits, no retry loop):

- **compile** — built with zero edits?
- **correct** — printed exactly the expected bytes? (compiles-but-wrong = miss)
- **tokens** — BPE token cost of the emitted program (cl100k / o200k).

The NURL **primer**'s own token cost is reported separately: in the primed
condition it is prepended to every NURL prompt, so it is a real recurring
expense and we do not hide it.

## Why NURL gets a primer and Python/Rust don't

Public LLMs have **zero lines of NURL** in their training data and millions of
lines of Python and Rust. A "write it from memory" test would therefore measure
*training exposure*, not the grammar. So by default the model is handed NURL's
one-page reference (`primers/nurl.md`); Python and Rust, being in-distribution,
are not. The question becomes: *given the rules, does the regular grammar let a
model write correct code at a rate comparable to languages it already knows?*
The `--no-primer` / `--primer-all` flags let you measure the other framings;
state which you used when quoting a number.

## Reproduce it with any model

You need an `ANTHROPIC_API_KEY` for generation; scoring needs only the NURL
toolchain (`build/nurlc` + the usual `clang`/`rustc`/`python3`/`node`). Token
columns need `tiktoken`, so score with the study venv.

```sh
# 0. one-time: a venv with tiktoken for the token columns
python3 -m venv bench/_venv && bench/_venv/bin/pip install tiktoken

# 1. generate (pick any Anthropic model id). --tag keeps conditions from
#    overwriting each other; --runs N draws N samples/task for a rate.
export ANTHROPIC_API_KEY=sk-ant-...
python3 bench/genacc/generate.py --model MODEL_ID --runs 5 --temperature 0.7 --tag main

# 2. (optional) the "what the primer buys" contrast: NURL with no reference
python3 bench/genacc/generate.py --model MODEL_ID --runs 5 --temperature 0.7 \
        --langs nurl --no-primer --tag noprimer

# 3. score + build the combined report
bench/_venv/bin/python bench/genacc/score.py \
        MODEL_ID__main MODEL_ID__noprimer --detail --md bench/genacc/RESULTS.md
```

`generate.py` writes to `solutions/<model>__<tag>/run<k>/<task>.<ext>`.
`score.py` takes those directory names and writes the report. A directory whose
name contains `noprimer` is reported as the no-reference condition.

Smaller/cheaper models (e.g. `claude-haiku-4-5-20251001`) discriminate better
than large ones on the *arithmetic* tasks: a strong model ceilings at ~100% in
every language there. On the *held-out string* tasks the spread is visible at
every size — see `RESULTS.md` for a haiku/sonnet/opus/mercury comparison. Some
models (e.g. `claude-opus-4-8`) reject the `temperature` parameter; `generate.py`
detects that and retries without it, so the model runs at its default sampling.

To drive a **non-Anthropic** model, use `generate_inception.py` (Inception Labs'
Mercury diffusion LLM, an OpenAI-compatible endpoint; needs `INCEPTION_API_KEY`).
It reuses `generate.py`'s task specs and prompts verbatim, so its output scores
identically; give a reasoning/diffusion model a generous `--max-tokens` (it can
spend the budget "thinking" and return empty otherwise).

## Files

```
genacc/
├── tasks.json          7 self-contained tasks; spec + verified expected output
├── primers/nurl.md     the one-page NURL reference (also a drop-in system-prompt
│                       cheatsheet for any agent writing NURL)
├── generate.py         calls a fixed Anthropic model; one program per (task, lang)
│                       --model --runs --temperature --langs --tag --tasks
│                       --no-primer / --primer-all (primer framing)
├── generate_inception.py  same, for Inception Labs' Mercury (OpenAI-compatible,
│                       INCEPTION_API_KEY); reuses generate.py's prompts verbatim
├── score.py            compiles + runs each program; reports compile / correct /
│                       tokens, primer cost broken out; --detail, --md; no model
├── RESULTS.md          our runs + interpretation (regenerate with score.py)
└── solutions/
    └── _reference/     ORACLE: the hand-written, verified bench programs.
                        `score.py _reference` is the scorer's 100%/100% self-test,
                        not a model result. Real model output is gitignored.
```

## Extending it

Add tasks to `tasks.json` (`name`, `spec`, `expected`). The `spec` must fully
determine the output with no external input. **Verify each new `expected` first**
by writing the program in every language and running `bench/verify.sh` — the
study is only meaningful because every task has one agreed-upon answer. Good
additions are non-arithmetic shapes (parsing, state machines, string munging)
where a grammar's regularity has more room to matter.

The **primer is a tuned artifact**, not fixed. Its job is to teach the general
rules a model trips on from cold; when a run surfaces a recurring first-pass
mistake, the fix belongs in `primers/nurl.md` as a *general* rule (not a
task-specific hint — that would overfit the eval). It was already revised once
this way (v1→v2: "`:` bindings and parameters are immutable; use `: ~`"), which
lifted first-pass NURL compile from 82% to 97% — see `RESULTS.md`. When you
tighten it against in-sample failures, re-measure on held-out tasks too.
